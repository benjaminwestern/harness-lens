package main

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
)

const (
	severityMild     profanitySeverity = "mild"
	severityModerate profanitySeverity = "moderate"
	severityStrong   profanitySeverity = "strong"
)

func (s *profanityDictionaryStore) set(path, mode string) {
	if mode != modeReplace {
		mode = modeExtend
	}
	s.mu.Lock()
	s.path = path
	s.mode = mode
	s.override = true
	s.mu.Unlock()
}

func (s *profanityDictionaryStore) snapshot() (path, mode string) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.override {
		return s.path, s.mode
	}
	path = strings.TrimSpace(os.Getenv("HARNESS_LENS_DICTIONARY"))
	if path == "" {
		path = strings.TrimSpace(os.Getenv("DEVRAGE_DICTIONARY"))
	}
	if path == "" {
		path = strings.TrimSpace(os.Getenv("PROFANITY_DICTIONARY"))
	}
	if path == "" {
		candidate := filepath.Join(configDir(), "custom-dictionary.csv")
		if _, err := os.Stat(candidate); err == nil {
			path = candidate
		}
	}
	mode = strings.ToLower(strings.TrimSpace(os.Getenv("HARNESS_LENS_DICTIONARY_MODE")))
	if mode == "" {
		mode = strings.ToLower(strings.TrimSpace(os.Getenv("DEVRAGE_DICTIONARY_MODE")))
	}
	if mode != modeReplace {
		mode = modeExtend
	}
	return path, mode
}

var (
	currentDetectorMu         sync.RWMutex
	currentDetector           *profanityDetector
	profanityDictionaryConfig = &profanityDictionaryStore{}
)

func setCurrentProfanityDetector(detector *profanityDetector) {
	currentDetectorMu.Lock()
	currentDetector = detector
	currentDetectorMu.Unlock()
}

func getDefaultDictionaryCSV() ([]byte, error) {
	var buf bytes.Buffer
	writer := csv.NewWriter(&buf)
	if err := writer.Write([]string{"word", "severity", "group"}); err != nil {
		return nil, fmt.Errorf("write CSV header: %w", err)
	}
	for _, w := range defaultProfanityWords {
		if err := writer.Write([]string{w.Word, string(w.Severity), w.Group}); err != nil {
			return nil, fmt.Errorf("write CSV dictionary row: %w", err)
		}
	}
	writer.Flush()
	if err := writer.Error(); err != nil {
		return nil, fmt.Errorf("flush CSV dictionary: %w", err)
	}
	return buf.Bytes(), nil
}

func getProfanityDictionaryInfo() ProfanityDictionaryInfo {
	currentDetectorMu.RLock()
	detector := currentDetector
	currentDetectorMu.RUnlock()
	if detector == nil {
		path, mode := profanityDictionaryConfig.snapshot()
		return ProfanityDictionaryInfo{Words: len(defaultProfanityWords), CustomPath: path, Mode: mode}
	}
	return ProfanityDictionaryInfo{
		Words:      detector.count,
		CustomPath: detector.custom,
		Mode:       detector.mode,
	}
}

//nolint:goconst // The default dictionary is data, not repeated control-flow constants.
var defaultProfanityWords = []profanityWord{
	{Word: "fuck", Severity: severityStrong, Group: "fuck"},
	{Word: "fucking", Severity: severityStrong, Group: "fuck"},
	{Word: "fucked", Severity: severityStrong, Group: "fuck"},
	{Word: "fucker", Severity: severityStrong, Group: "fuck"},
	{Word: "fuckin", Severity: severityStrong, Group: "fuck"},
	{Word: "fucks", Severity: severityStrong, Group: "fuck"},
	{Word: "motherfucker", Severity: severityStrong, Group: "fuck"},
	{Word: "motherfucking", Severity: severityStrong, Group: "fuck"},
	{Word: "mothafucka", Severity: severityStrong, Group: "fuck"},
	{Word: "fuckup", Severity: severityStrong, Group: "fuck"},
	{Word: "fuckoff", Severity: severityStrong, Group: "fuck"},
	{Word: "clusterfuck", Severity: severityStrong, Group: "fuck"},
	{Word: "fuckwit", Severity: severityStrong, Group: "fuck"},
	{Word: "fucktard", Severity: severityStrong, Group: "fuck"},
	{Word: "fuckface", Severity: severityStrong, Group: "fuck"},
	{Word: "fuckhead", Severity: severityStrong, Group: "fuck"},
	{Word: "fukc", Severity: severityStrong, Group: "fuck"},
	{Word: "fukcing", Severity: severityStrong, Group: "fuck"},
	{Word: "fukced", Severity: severityStrong, Group: "fuck"},
	{Word: "fukcer", Severity: severityStrong, Group: "fuck"},
	{Word: "fcuk", Severity: severityStrong, Group: "fuck"},
	{Word: "fcuking", Severity: severityStrong, Group: "fuck"},
	{Word: "fcuked", Severity: severityStrong, Group: "fuck"},
	{Word: "fuk", Severity: severityStrong, Group: "fuck"},
	{Word: "fuking", Severity: severityStrong, Group: "fuck"},
	{Word: "fuked", Severity: severityStrong, Group: "fuck"},
	{Word: "fuker", Severity: severityStrong, Group: "fuck"},
	{Word: "fuxk", Severity: severityStrong, Group: "fuck"},
	{Word: "fuxking", Severity: severityStrong, Group: "fuck"},
	{Word: "shit", Severity: severityStrong, Group: "shit"},
	{Word: "shitty", Severity: severityStrong, Group: "shit"},
	{Word: "shitting", Severity: severityStrong, Group: "shit"},
	{Word: "shits", Severity: severityStrong, Group: "shit"},
	{Word: "shitted", Severity: severityStrong, Group: "shit"},
	{Word: "bullshit", Severity: severityStrong, Group: "shit"},
	{Word: "horseshit", Severity: severityStrong, Group: "shit"},
	{Word: "dipshit", Severity: severityStrong, Group: "shit"},
	{Word: "shitshow", Severity: severityStrong, Group: "shit"},
	{Word: "shithead", Severity: severityStrong, Group: "shit"},
	{Word: "shithole", Severity: severityStrong, Group: "shit"},
	{Word: "shitface", Severity: severityStrong, Group: "shit"},
	{Word: "shitfaced", Severity: severityStrong, Group: "shit"},
	{Word: "shitstain", Severity: severityStrong, Group: "shit"},
	{Word: "shitbag", Severity: severityStrong, Group: "shit"},
	{Word: "hsit", Severity: severityStrong, Group: "shit"},
	{Word: "siht", Severity: severityStrong, Group: "shit"},
	{Word: "shti", Severity: severityStrong, Group: "shit"},
	{Word: "sjit", Severity: severityStrong, Group: "shit"},
	{Word: "shjt", Severity: severityStrong, Group: "shit"},
	{Word: "bulshit", Severity: severityStrong, Group: "shit"},
	{Word: "bullsht", Severity: severityStrong, Group: "shit"},
	{Word: "ass", Severity: severityModerate, Group: "ass"},
	{Word: "asses", Severity: severityModerate, Group: "ass"},
	{Word: "asshole", Severity: severityStrong, Group: "ass"},
	{Word: "assholes", Severity: severityStrong, Group: "ass"},
	{Word: "jackass", Severity: severityStrong, Group: "ass"},
	{Word: "dumbass", Severity: severityStrong, Group: "ass"},
	{Word: "fatass", Severity: severityModerate, Group: "ass"},
	{Word: "asshat", Severity: severityStrong, Group: "ass"},
	{Word: "asswipe", Severity: severityStrong, Group: "ass"},
	{Word: "badass", Severity: severityMild, Group: "ass"},
	{Word: "damn", Severity: severityModerate, Group: "damn"},
	{Word: "damned", Severity: severityModerate, Group: "damn"},
	{Word: "damnit", Severity: severityModerate, Group: "damn"},
	{Word: "dammit", Severity: severityModerate, Group: "damn"},
	{Word: "goddamn", Severity: severityModerate, Group: "damn"},
	{Word: "goddamnit", Severity: severityModerate, Group: "damn"},
	{Word: "goddammit", Severity: severityModerate, Group: "damn"},
	{Word: "bitch", Severity: severityStrong, Group: "bitch"},
	{Word: "bitches", Severity: severityStrong, Group: "bitch"},
	{Word: "bitching", Severity: severityStrong, Group: "bitch"},
	{Word: "bitchy", Severity: severityStrong, Group: "bitch"},
	{Word: "bitchass", Severity: severityStrong, Group: "bitch"},
	{Word: "bastard", Severity: severityStrong, Group: "bastard"},
	{Word: "bastards", Severity: severityStrong, Group: "bastard"},
	{Word: "piss", Severity: severityModerate, Group: "piss"},
	{Word: "pissed", Severity: severityModerate, Group: "piss"},
	{Word: "pissing", Severity: severityModerate, Group: "piss"},
	{Word: "pissoff", Severity: severityModerate, Group: "piss"},
	{Word: "dick", Severity: severityModerate, Group: "dick"},
	{Word: "dickhead", Severity: severityStrong, Group: "dick"},
	{Word: "crap", Severity: severityModerate, Group: "crap"},
	{Word: "crappy", Severity: severityModerate, Group: "crap"},
	{Word: "crapping", Severity: severityModerate, Group: "crap"},
	{Word: "hell", Severity: severityMild, Group: "hell"},
	{Word: "wtf", Severity: severityMild, Group: "wtf"},
	{Word: "stfu", Severity: severityMild, Group: "stfu"},
	{Word: "lmfao", Severity: severityMild, Group: "lmfao"},
	{Word: "lmao", Severity: severityMild, Group: "lmao"},
	{Word: "cunt", Severity: severityStrong, Group: "cunt"},
	{Word: "cunts", Severity: severityStrong, Group: "cunt"},
}

func loadProfanityDetector() (*profanityDetector, error) {
	path, mode := profanityDictionaryConfig.snapshot()
	return buildProfanityDetector(path, mode)
}

func configDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	dir := filepath.Join(home, ".config", "harness-lens")
	_ = os.MkdirAll(dir, 0o700)
	return dir
}

func readProfanityDictionary(path string) ([]profanityWord, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read custom profanity dictionary: %w", err)
	}
	if strings.HasSuffix(strings.ToLower(path), ".csv") {
		return readProfanityDictionaryCSV(data)
	}
	var words []profanityWord
	if err := json.Unmarshal(data, &words); err != nil {
		return nil, fmt.Errorf("parse custom profanity dictionary: %w", err)
	}
	return words, nil
}

func readProfanityDictionaryCSV(data []byte) ([]profanityWord, error) {
	reader := csv.NewReader(bytes.NewReader(data))
	reader.TrimLeadingSpace = true
	records, err := reader.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("parse CSV dictionary: %w", err)
	}
	if len(records) == 0 {
		return nil, fmt.Errorf("CSV dictionary is empty")
	}
	startIdx := 0
	if len(records[0]) > 0 {
		first := strings.ToLower(strings.TrimSpace(records[0][0]))
		if first == "word" || first == "words" {
			startIdx = 1
		}
	}
	words := make([]profanityWord, 0, len(records)-startIdx)
	for _, record := range records[startIdx:] {
		if len(record) < 1 {
			continue
		}
		word := strings.TrimSpace(record[0])
		if word == "" {
			continue
		}
		severity := severityModerate
		if len(record) > 1 {
			s := strings.ToLower(strings.TrimSpace(record[1]))
			if s == string(severityMild) || s == string(severityModerate) || s == string(severityStrong) {
				severity = profanitySeverity(s)
			}
		}
		group := word
		if len(record) > 2 {
			g := strings.TrimSpace(record[2])
			if g != "" {
				group = g
			}
		}
		words = append(words, profanityWord{Word: word, Severity: severity, Group: group})
	}
	if len(words) == 0 {
		return nil, fmt.Errorf("CSV dictionary contains no valid words")
	}
	return words, nil
}

func buildProfanityDetector(path, mode string) (*profanityDetector, error) {
	if mode != modeReplace {
		mode = modeExtend
	}
	words := append([]profanityWord(nil), defaultProfanityWords...)
	if path != "" {
		custom, err := readProfanityDictionary(path)
		if err != nil {
			return nil, err
		}
		if mode == modeReplace {
			words = custom
		} else {
			words = append(words, custom...)
		}
	}
	detector, err := newProfanityDetector(words)
	if err != nil {
		return nil, err
	}
	detector.custom = path
	detector.mode = mode
	return detector, nil
}

func reloadProfanityDetector(path, mode string) error {
	detector, err := buildProfanityDetector(path, mode)
	if err != nil {
		return err
	}
	profanityDictionaryConfig.set(path, detector.mode)
	setCurrentProfanityDetector(detector)
	return nil
}

func newProfanityDetector(words []profanityWord) (*profanityDetector, error) {
	if len(words) == 0 {
		return nil, fmt.Errorf("profanity dictionary is empty")
	}
	wordMap := make(map[string]profanityWord, len(words))
	patterns := make([]string, 0, len(words))
	for _, entry := range words {
		word := strings.ToLower(strings.TrimSpace(entry.Word))
		if word == "" {
			return nil, fmt.Errorf("profanity dictionary contains an empty word")
		}
		if entry.Severity == "" {
			entry.Severity = severityModerate
		}
		if entry.Severity != severityMild && entry.Severity != severityModerate && entry.Severity != severityStrong {
			return nil, fmt.Errorf("invalid severity %q for word %q", entry.Severity, entry.Word)
		}
		if strings.TrimSpace(entry.Group) == "" {
			entry.Group = word
		}
		entry.Word = word
		entry.Group = strings.ToLower(strings.TrimSpace(entry.Group))
		wordMap[word] = entry
	}
	for word := range wordMap {
		patterns = append(patterns, regexp.QuoteMeta(word))
	}
	sort.Slice(patterns, func(i, j int) bool { return len(patterns[i]) > len(patterns[j]) })
	pattern, err := regexp.Compile(`(?i)\b(` + strings.Join(patterns, "|") + `)\b`)
	if err != nil {
		return nil, fmt.Errorf("compile profanity detector: %w", err)
	}
	return &profanityDetector{pattern: pattern, words: wordMap, count: len(wordMap)}, nil
}

func (d *profanityDetector) detect(text string) []profanityMatch {
	matches := make([]profanityMatch, 0)
	seen := make(map[int]struct{})
	d.run(text, strings.ToLower(text), seen, &matches)
	collapsed := collapseRepeats(strings.ToLower(text))
	if collapsed != strings.ToLower(text) {
		d.run(text, collapsed, seen, &matches)
	}
	return matches
}

func (d *profanityDetector) run(_ string, search string, seen map[int]struct{}, matches *[]profanityMatch) {
	for _, loc := range d.pattern.FindAllStringIndex(search, -1) {
		if _, ok := seen[loc[0]]; ok {
			continue
		}
		word := strings.ToLower(search[loc[0]:loc[1]])
		entry, ok := d.words[word]
		if !ok {
			continue
		}
		seen[loc[0]] = struct{}{}
		*matches = append(*matches, profanityMatch{Word: word, Group: entry.Group, Severity: entry.Severity})
	}
}

func collapseRepeats(text string) string {
	var b strings.Builder
	var last rune
	for i, r := range text {
		if i > 0 && r == last {
			continue
		}
		b.WriteRune(r)
		last = r
	}
	return b.String()
}
