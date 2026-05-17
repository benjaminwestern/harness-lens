package main

import (
	"harness-lens/db"
	"regexp"
	"sync"
	"time"
)

type profanitySeverity string

type profanityWord struct {
	Word     string            `json:"word"`
	Severity profanitySeverity `json:"severity"`
	Group    string            `json:"group"`
}

type profanityMatch struct {
	Word     string
	Group    string
	Severity profanitySeverity
}

type profanityDetector struct {
	pattern *regexp.Regexp
	words   map[string]profanityWord
	count   int
	custom  string
	mode    string
}

type ProfanityDictionaryInfo struct {
	Words      int    `json:"words"`
	CustomPath string `json:"custom_path"`
	Mode       string `json:"mode"`
}

type profanityDictionaryStore struct {
	mu       sync.RWMutex
	path     string
	mode     string
	override bool
}

type diagError struct {
	Source    string
	Code      string
	Operation string
	Message   string
	Err       error
}

type updateHub struct {
	mu      sync.Mutex
	clients map[chan struct{}]struct{}
}

type refreshTrigger string

type Diagnostics struct {
	State                      string
	Trigger                    string
	Message                    string
	ErrorCode                  string
	ErrorMessage               string
	LastStartedAt              string
	LastFinishedAt             string
	LastDuration               string
	NextRefreshAt              string
	CycleInterval              string
	CycleDescription           string
	AutoRefreshEnabled         bool
	RefreshIntervalMinutes     int
	RefreshInProgress          bool
	ProfanityCollectionEnabled bool
	TablesReady                bool
	Revision                   uint64
}

type refreshStateStore struct {
	mu            sync.Mutex
	state         Diagnostics
	startedAt     time.Time
	finishedAt    time.Time
	nextRefreshAt time.Time
	revision      uint64
}

type refreshConfigStore struct {
	mu       sync.Mutex
	enabled  bool
	interval time.Duration
}

type profanityConfigStore struct {
	mu      sync.Mutex
	enabled bool
}

type TemplateData struct {
	GeneratedAt             string
	IsFragment              bool
	Days                    int32
	Harness                 string
	Provider                string
	Model                   string
	Project                 string
	Tool                    string
	Filename                string
	View                    string
	SortTable               string
	SortBy                  string
	SortDir                 string
	Summary                 db.GetSummaryRow
	Harnesses               []HarnessData
	Providers               []ProviderData
	Models                  []ModelData
	Projects                []ProjectData
	Tools                   []ToolData
	ModelTools              []ModelToolData
	Timeline                []TimelineData
	Sessions                []Session
	TotalSessions           int
	ProfanitySummary        db.GetProfanitySummaryRow
	ProfanityGroups         []db.GetProfanityGroupsRow
	ProfanityModelHarnesses []db.GetProfanityModelHarnessesRow
	ProfanityModels         []ProfanityModelData
	ProfanityHarnesses      []db.GetProfanityHarnessesRow
	ProfanityDictionary     ProfanityDictionaryInfo
	SessionProfanity        []db.GetSessionProfanityRow
	SessionProfanityTotal   int64
	SessionProfanityFeel    int64
	SessionProfanityMood    string
	Diagnostics             Diagnostics
}

type HarnessData struct {
	Harness       string  `json:"harness"`
	Spend         float64 `json:"spend"`
	SpendDisplay  string  `json:"spend_display"`
	Tokens        int64   `json:"tokens"`
	TokensDisplay string  `json:"tokens_display"`
	Turns         int64   `json:"turns"`
	Tools         int64   `json:"tools"`
	Errors        int64   `json:"errors"`
}

type ProviderData struct {
	Provider      string  `json:"provider"`
	Spend         float64 `json:"spend"`
	SpendDisplay  string  `json:"spend_display"`
	Tokens        int64   `json:"tokens"`
	TokensDisplay string  `json:"tokens_display"`
	Tools         int64   `json:"tools"`
	Errors        int64   `json:"errors"`
}

type ModelData struct {
	Model                    string  `json:"model"`
	Provider                 string  `json:"provider"`
	Spend                    float64 `json:"spend"`
	SpendDisplay             string  `json:"spend_display"`
	Sessions                 int64   `json:"sessions"`
	AvgCostPerSession        float64 `json:"avg_cost_per_session"`
	AvgCostPerSessionDisplay string  `json:"avg_cost_per_session_display"`
	Tokens                   int64   `json:"tokens"`
	TokensDisplay            string  `json:"tokens_display"`
	UnpricedTokens           int64   `json:"unpriced_tokens"`
	UnpricedTokensDisplay    string  `json:"unpriced_tokens_display"`
	UnpricedSessions         int64   `json:"unpriced_sessions"`
	Tools                    int64   `json:"tools"`
	Errors                   int64   `json:"errors"`
}

type ProjectData struct {
	Project            string  `json:"project"`
	Spend              float64 `json:"spend"`
	SpendDisplay       string  `json:"spend_display"`
	Sessions           int64   `json:"sessions"`
	AvgDuration        int64   `json:"avg_duration"`
	AvgDurationDisplay string  `json:"avg_duration_display"`
}

type ToolData struct {
	Tool     string `json:"tool"`
	Count    int64  `json:"count"`
	Errors   int64  `json:"errors"`
	ErrorPct string `json:"error_pct"`
}

type ModelToolData struct {
	Model    string `json:"model"`
	Provider string `json:"provider"`
	Tool     string `json:"tool"`
	Count    int64  `json:"count"`
	Errors   int64  `json:"errors"`
	ErrorPct string `json:"error_pct"`
}

type TimelineData struct {
	Date                 string  `json:"date"`
	Cost                 float64 `json:"cost"`
	CostDisplay          string  `json:"cost_display"`
	Tokens               int64   `json:"tokens"`
	TokensDisplay        string  `json:"tokens_display"`
	ToolCalls            int64   `json:"tool_calls"`
	ToolCallsDisplay     string  `json:"tool_calls_display"`
	ToolErrors           int64   `json:"tool_errors"`
	ToolErrorsDisplay    string  `json:"tool_errors_display"`
	ProfanityHits        int64   `json:"profanity_hits"`
	ProfanityHitsDisplay string  `json:"profanity_hits_display"`
	FeelScore            int64   `json:"feel_score"`
	FeelDisplay          string  `json:"feel_display"`
}

type ProfanityModelData struct {
	Model    string
	Provider string
	Count    int64
	Sessions int64
}

type Session struct {
	Harness               string
	Filename              string
	StartTimeStr          string
	EndTimeStr            string
	DurationSecCalc       int64
	Project               string
	Cwd                   string
	Cost                  float64
	InTok                 int64
	OutTok                int64
	CacheTok              int64
	TotalTokens           int64
	UserTurns             int64
	AgentTurns            int64
	TotalTurns            int64
	Errors                int64
	ToolCount             int64
	ToolErrorCount        int64
	ToolBreakdown         string
	ToolErrorBreakdown    string
	ModelToolBreakdown    string
	CostDisplay           string
	TotalTokensDisplay    string
	TokenBreakdownDisplay string
	DurationDisplay       string
	ToolErrorPct          string
	ResumeCommand         string
	ResumeLabel           string
	ModelStats            []ModelStat
	Models                []string
}

type ModelStat struct {
	Model                 string  `json:"model"`
	Provider              string  `json:"provider"`
	Turns                 int64   `json:"turns"`
	Cost                  float64 `json:"cost"`
	InTok                 int64   `json:"in_tok"`
	OutTok                int64   `json:"out_tok"`
	CacheTok              int64   `json:"cache_tok"`
	Tools                 int64   `json:"tools"`
	Errors                int64   `json:"errors"`
	CostDisplay           string  `json:"cost_display"`
	TokenBreakdownDisplay string  `json:"token_breakdown_display"`
	ErrorPct              string  `json:"error_pct"`
	CostPerTurnDisplay    string  `json:"cost_per_turn_display"`
	CostPerToolDisplay    string  `json:"cost_per_tool_display"`
}

type profanityHit struct {
	id       int64
	harness  string
	filename string
	project  string
	ts       int64
	word     string
	group    string
	severity string
}
