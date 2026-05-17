package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func handleDashboard(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	var data TemplateData
	if tablesReady.Load() {
		var err error
		data, err = buildTemplateData(r.Context(), r, viewDashboard)
		if err != nil {
			log.Printf("dashboard query error: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		data = emptyTemplateData(r, viewDashboard)
	}
	if data.IsFragment {
		if err := tmpl.ExecuteTemplate(w, "dashboard-content", data); err != nil {
			log.Printf("template error: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
		return
	}
	if err := tmpl.ExecuteTemplate(w, "index.html", data); err != nil {
		log.Printf("template error: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func handleSession(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("filename") == "" {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	var data TemplateData
	if tablesReady.Load() {
		var err error
		data, err = buildTemplateData(r.Context(), r, viewSession)
		if err != nil {
			log.Printf("session query error: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		data = emptyTemplateData(r, viewSession)
	}
	if data.IsFragment {
		if err := tmpl.ExecuteTemplate(w, "session-content", data); err != nil {
			log.Printf("session template error: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
		return
	}
	if err := tmpl.ExecuteTemplate(w, "index.html", data); err != nil {
		log.Printf("template error: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func handleFilteredPage(w http.ResponseWriter, r *http.Request, view, templateName string) {
	var data TemplateData
	if tablesReady.Load() {
		var err error
		data, err = buildTemplateData(r.Context(), r, view)
		if err != nil {
			log.Printf("%s query error: %v", view, err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		data = emptyTemplateData(r, view)
	}
	if data.IsFragment {
		if err := tmpl.ExecuteTemplate(w, templateName, data); err != nil {
			log.Printf("%s template error: %v", view, err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
		return
	}
	if err := tmpl.ExecuteTemplate(w, "index.html", data); err != nil {
		log.Printf("template error: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func handleDrill(w http.ResponseWriter, r *http.Request) {
	handleFilteredPage(w, r, viewDrill, "drill-content")
}

func handleProfanity(w http.ResponseWriter, r *http.Request) {
	handleFilteredPage(w, r, viewProfanity, "profanity-content")
}

func handleDownloadDictionaryTemplate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	data, err := getDefaultDictionaryCSV()
	if err != nil {
		http.Error(w, "Could not generate template: "+err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/csv")
	w.Header().Set("Content-Disposition", `attachment; filename="profanity-dictionary-template.csv"`)
	_, _ = w.Write(data)
}

func handleUploadDictionary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if rejectCrossOriginWrite(w, r) {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	//nolint:gosec // MaxBytesReader caps the upload before multipart parsing.
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		http.Error(w, "Could not parse form: "+err.Error(), http.StatusBadRequest)
		return
	}
	file, _, err := r.FormFile("dictionary")
	if err != nil {
		http.Error(w, "No file uploaded: "+err.Error(), http.StatusBadRequest)
		return
	}
	defer func() { _ = file.Close() }()
	mode := strings.ToLower(strings.TrimSpace(r.FormValue("mode")))
	if mode != modeReplace {
		mode = modeExtend
	}
	dir := configDir()
	path := filepath.Join(dir, "custom-dictionary.csv")
	tmp, err := os.CreateTemp(dir, "custom-dictionary-*.csv")
	if err != nil {
		http.Error(w, "Could not save file: "+err.Error(), http.StatusInternalServerError)
		return
	}
	tmpPath := tmp.Name()
	defer func() { _ = os.Remove(tmpPath) }()
	if _, err := io.Copy(tmp, file); err != nil {
		_ = tmp.Close()
		http.Error(w, "Could not write file: "+err.Error(), http.StatusInternalServerError)
		return
	}
	if err := tmp.Close(); err != nil {
		http.Error(w, "Could not close uploaded file: "+err.Error(), http.StatusInternalServerError)
		return
	}
	if _, err := buildProfanityDetector(tmpPath, mode); err != nil {
		http.Error(w, "Could not load dictionary: "+err.Error(), http.StatusBadRequest)
		return
	}
	if err := os.Rename(tmpPath, path); err != nil {
		http.Error(w, "Could not activate dictionary: "+err.Error(), http.StatusInternalServerError)
		return
	}
	if err := reloadProfanityDetector(path, mode); err != nil {
		http.Error(w, "Could not load dictionary: "+err.Error(), http.StatusBadRequest)
		return
	}
	requestRefresh(refreshManual)
	w.Header().Set("Content-Type", "application/json")
	info := getProfanityDictionaryInfo()
	if err := json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
		"path":   path,
		"mode":   info.Mode,
		"words":  strconv.Itoa(info.Words),
	}); err != nil {
		appLog.Warn("could not write dictionary upload response", "error", err)
	}
}
