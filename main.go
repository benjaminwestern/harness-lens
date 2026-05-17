// Package main serves Harness Lens, a local-first dashboard for AI harness analytics.
package main

import (
	"database/sql"
	"embed"
	"encoding/json"
	"harness-lens/db"
	"html/template"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/duckdb/duckdb-go/v2"
)

//go:embed templates/*.html
var content embed.FS

var (
	tmpl    *template.Template
	dbConn  *sql.DB
	queries *db.Queries
	appLog  = newLogger()
)

const (
	defaultRefreshInterval = 15 * time.Minute
	modeExtend             = "extend"
	modeReplace            = "replace"
	stringTrue             = "true"
	viewDashboard          = "dashboard"
	viewDrill              = "drill"
	viewProfanity          = "profanity"
	viewSession            = "session"
	harnessCodex           = "codex"
	harnessGemini          = "gemini"
)

func main() {
	var err error
	tmpl, err = template.New("").Funcs(template.FuncMap{
		"json": func(v interface{}) template.JS {
			b, _ := json.Marshal(v)
			//nolint:gosec // json.Marshal output is embedded as inert chart data in quoted attributes.
			return template.JS(b)
		},
	}).ParseFS(content, "templates/*.html")
	if err != nil {
		log.Fatalf("template parse: %v", err)
	}

	http.HandleFunc("/events", handleEvents)
	http.HandleFunc("/refresh", handleRefresh)
	http.HandleFunc("/refresh-settings", handleRefreshSettings)
	http.HandleFunc("/profanity-settings", handleProfanitySettings)
	http.HandleFunc("/dictionary-template", handleDownloadDictionaryTemplate)
	http.HandleFunc("/upload-dictionary", handleUploadDictionary)
	http.HandleFunc("/session", handleSession)
	http.HandleFunc("/drill", handleDrill)
	http.HandleFunc("/profanity", handleProfanity)
	http.HandleFunc("/", handleDashboard)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	host := strings.TrimSpace(os.Getenv("HOST"))
	if host == "" {
		host = "127.0.0.1"
	}
	addr := net.JoinHostPort(host, port)
	server := &http.Server{
		Addr:              addr,
		ReadHeaderTimeout: 5 * time.Second,
	}
	serverErr := make(chan error, 1)
	go func() {
		appLog.Info("server listening", "addr", addr)
		serverErr <- server.ListenAndServe()
	}()

	dbConn, err = sql.Open("duckdb", ":memory:")
	if err != nil {
		log.Fatalf("duckdb open: %v", err)
	}
	dbConn.SetMaxOpenConns(1)
	dbConn.SetMaxIdleConns(1)
	defer func() { _ = dbConn.Close() }()

	queries = db.New(dbConn)

	go refreshWorker()
	go scheduleRefreshes()

	if err := <-serverErr; err != nil {
		log.Fatal(err)
	}
}
