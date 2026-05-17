package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"harness-lens/db"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func parseIntParam(val string, defaultVal int32) int32 {
	if val == "" || val == "all" {
		return defaultVal
	}
	i, err := strconv.ParseInt(val, 10, 32)
	if err != nil {
		return defaultVal
	}
	return int32(i)
}

func sessionID(harness, filename string) string {
	base := strings.TrimSuffix(filepath.Base(filename), filepath.Ext(filename))
	switch harness {
	case "pi":
		if i := strings.LastIndex(base, "_"); i >= 0 && i < len(base)-1 {
			return base[i+1:]
		}
	case harnessCodex:
		parts := strings.Split(base, "-")
		if len(parts) >= 5 {
			return strings.Join(parts[len(parts)-5:], "-")
		}
	case harnessGemini:
		return strings.TrimPrefix(base, "session-")
	}
	return base
}

func resumeLabel(harness string) string {
	switch harness {
	case "pi":
		return "Resume in Pi"
	case "opencode":
		return "Resume in OpenCode"
	case harnessCodex:
		return "Resume in Codex"
	case harnessGemini:
		return "Resume in Gemini"
	case "claude":
		return "Resume in Claude"
	default:
		return "Copy resume command"
	}
}

func resumeCommand(harness, filename, cwd string) string {
	id := sessionID(harness, filename)
	switch harness {
	case "pi":
		return "pi --session " + strconv.Quote(id)
	case "opencode":
		if cwd != "" {
			return "opencode " + strconv.Quote(cwd) + " --session " + strconv.Quote(id)
		}
		return "opencode --session " + strconv.Quote(id)
	case harnessCodex:
		return "codex resume " + strconv.Quote(id)
	case harnessGemini:
		return "gemini --resume " + strconv.Quote(id)
	case "claude":
		return "claude --resume " + strconv.Quote(id)
	default:
		return ""
	}
}

func parseFilters(r *http.Request) (db.GetSummaryParams, db.GetHarnessesParams, db.GetProvidersParams, db.GetModelsParams, db.GetProjectsParams, db.GetToolsParams, db.GetModelToolsParams, db.GetTimelineParams, db.GetSessionsParams) {
	days := parseIntParam(r.URL.Query().Get("days"), 0)
	harness := r.URL.Query().Get("harness")
	provider := r.URL.Query().Get("provider")
	model := r.URL.Query().Get("model")
	project := r.URL.Query().Get("project")
	tool := r.URL.Query().Get("tool")
	filename := r.URL.Query().Get("filename")
	sortTable := r.URL.Query().Get("sort_table")
	sortBy := r.URL.Query().Get("sort_by")
	sortDir := r.URL.Query().Get("sort_dir")
	if sortDir != "asc" {
		sortDir = "desc"
	}

	return db.GetSummaryParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool},
		db.GetHarnessesParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir},
		db.GetProvidersParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir},
		db.GetModelsParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir},
		db.GetProjectsParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir},
		db.GetToolsParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir},
		db.GetModelToolsParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir},
		db.GetTimelineParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool},
		db.GetSessionsParams{Days: days, Project: project, Filename: filename, Harness: harness, Provider: provider, Model: model, Tool: tool, SortTable: sortTable, SortBy: sortBy, SortDir: sortDir}
}

func emptyTemplateData(r *http.Request, view string) TemplateData {
	sumParams, harParams, proParams, _, _, toolParams, _, _, _ := parseFilters(r)
	isFragment := r.Header.Get("X-Fragment-Request") == stringTrue
	return TemplateData{
		GeneratedAt: time.Now().Format(time.RFC3339),
		IsFragment:  isFragment,
		Days:        sumParams.Days,
		Harness:     harParams.Harness,
		Provider:    proParams.Provider,
		Model:       proParams.Model,
		Project:     proParams.Project,
		Tool:        toolParams.Tool,
		Filename:    sumParams.Filename,
		View:        view,
		SortTable:   harParams.SortTable,
		SortBy:      harParams.SortBy,
		SortDir:     harParams.SortDir,
		Diagnostics: refreshState.snapshot(),
	}
}

func buildTemplateData(ctx context.Context, r *http.Request, view string) (TemplateData, error) {
	sumParams, harParams, proParams, modParams, projParams, toolParams, mtParams, timelineParams, sessParams := parseFilters(r)

	needSummary := view == viewDashboard || view == viewDrill
	needHarnesses := view == viewDashboard
	needProviders := view == viewDashboard
	needModels := view == viewDashboard || view == viewDrill
	needTools := view == viewDashboard || view == viewDrill
	needModelTools := view == viewSession
	needSessionProfanity := view == viewSession
	needTimeline := view == viewDrill
	needSessions := view == viewDashboard || view == viewDrill || view == viewSession
	needProfanitySummary := view == viewDashboard || view == viewDrill || view == viewProfanity
	needProfanityGroups := view == viewDrill || view == viewProfanity
	needProfanityTables := view == viewProfanity

	var (
		summary                 db.GetSummaryRow
		harnesses               []db.GetHarnessesRow
		providers               []db.GetProvidersRow
		models                  []db.GetModelsRow
		projects                []db.GetProjectsRow
		tools                   []db.GetToolsRow
		modelTools              []db.GetModelToolsRow
		sessionProfanity        []db.GetSessionProfanityRow
		timeline                []db.GetTimelineRow
		sessionsRaw             []db.GetSessionsRow
		profanitySummary        db.GetProfanitySummaryRow
		profanityGroups         []db.GetProfanityGroupsRow
		profanityModels         []db.GetProfanityModelsRow
		profanityModelHarnesses []db.GetProfanityModelHarnessesRow
		profanityHarnesses      []db.GetProfanityHarnessesRow
	)

	analyticsMu.RLock()
	var queryErrs []error
	if needSummary {
		var err error
		summary, err = queries.GetSummary(ctx, sumParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetSummary: %w", err))
		}
	}
	if needHarnesses {
		var err error
		harnesses, err = queries.GetHarnesses(ctx, harParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetHarnesses: %w", err))
		}
	}
	if needProviders {
		var err error
		providers, err = queries.GetProviders(ctx, proParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetProviders: %w", err))
		}
	}
	if needModels {
		var err error
		models, err = queries.GetModels(ctx, modParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetModels: %w", err))
		}
	}
	if needTools {
		var err error
		tools, err = queries.GetTools(ctx, toolParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetTools: %w", err))
		}
	}
	if needModelTools {
		var err error
		modelTools, err = queries.GetModelTools(ctx, mtParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetModelTools: %w", err))
		}
	}
	if needSessionProfanity && sessParams.Harness != "" && sessParams.Filename != "" {
		var err error
		sessionProfanity, err = queries.GetSessionProfanity(ctx, db.GetSessionProfanityParams{Harness: sessParams.Harness, Filename: sessParams.Filename})
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetSessionProfanity: %w", err))
		}
	}
	if needTimeline {
		var err error
		timeline, err = queries.GetTimeline(ctx, timelineParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetTimeline: %w", err))
		}
	}
	if needSessions {
		var err error
		sessionsRaw, err = queries.GetSessions(ctx, sessParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetSessions: %w", err))
		}
	}
	profParams := db.GetProfanitySummaryParams(sumParams)
	if needProfanitySummary {
		var err error
		profanitySummary, err = queries.GetProfanitySummary(ctx, profParams)
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetProfanitySummary: %w", err))
		}
	}
	if needProfanityGroups {
		var err error
		profanityGroups, err = queries.GetProfanityGroups(ctx, db.GetProfanityGroupsParams(profParams))
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetProfanityGroups: %w", err))
		}
	}
	if needProfanityTables {
		var err error
		profanityModels, err = queries.GetProfanityModels(ctx, db.GetProfanityModelsParams(profParams))
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetProfanityModels: %w", err))
		}
		profanityModelHarnesses, err = queries.GetProfanityModelHarnesses(ctx, db.GetProfanityModelHarnessesParams(profParams))
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetProfanityModelHarnesses: %w", err))
		}
		profanityHarnesses, err = queries.GetProfanityHarnesses(ctx, db.GetProfanityHarnessesParams(profParams))
		if err != nil {
			queryErrs = append(queryErrs, fmt.Errorf("GetProfanityHarnesses: %w", err))
		}
	}
	analyticsMu.RUnlock()
	if err := errors.Join(queryErrs...); err != nil {
		return TemplateData{}, err
	}
	totalSessions := len(sessionsRaw)
	sessions := make([]Session, totalSessions)
	for i, r := range sessionsRaw {
		s := Session{
			Harness:               r.Harness,
			Filename:              r.Filename,
			StartTimeStr:          r.StartTimeStr,
			EndTimeStr:            r.EndTimeStr,
			DurationSecCalc:       r.DurationSecCalc,
			Project:               r.Project.String,
			Cwd:                   r.Cwd.String,
			Cost:                  r.Cost,
			InTok:                 r.InTok,
			OutTok:                r.OutTok,
			CacheTok:              r.CacheTok,
			TotalTokens:           r.TotalTokens,
			UserTurns:             r.UserTurns,
			AgentTurns:            r.AgentTurns,
			TotalTurns:            r.TotalTurns,
			Errors:                r.Errors,
			ToolCount:             r.ToolCount,
			ToolErrorCount:        r.ToolErrorCount,
			ToolBreakdown:         r.ToolBreakdownJson,
			ToolErrorBreakdown:    r.ToolErrorBreakdownJson,
			ModelToolBreakdown:    r.ModelToolBreakdownJson,
			CostDisplay:           r.CostDisplay,
			TotalTokensDisplay:    r.TotalTokensDisplay,
			TokenBreakdownDisplay: r.TokenBreakdownDisplay,
			DurationDisplay:       r.DurationDisplay,
			ToolErrorPct:          r.ToolErrorPct,
			ResumeCommand:         resumeCommand(r.Harness, r.Filename, r.Cwd.String),
			ResumeLabel:           resumeLabel(r.Harness),
		}
		if r.ModelsJson != "" {
			if err := json.Unmarshal([]byte(r.ModelsJson), &s.Models); err != nil {
				return TemplateData{}, fmt.Errorf("decode session models for %s: %w", r.Filename, err)
			}
		}
		if r.ModelStatsJson != "" {
			if err := json.Unmarshal([]byte(r.ModelStatsJson), &s.ModelStats); err != nil {
				return TemplateData{}, fmt.Errorf("decode session model stats for %s: %w", r.Filename, err)
			}
		}
		sessions[i] = s
	}
	if len(sessions) > 25 {
		sessions = sessions[:25]
	}

	// Map sqlc NullString types to clean types for JSON serialization
	cleanHarnesses := make([]HarnessData, len(harnesses))
	for i, h := range harnesses {
		cleanHarnesses[i] = HarnessData{Harness: h.Harness, Spend: h.Spend, SpendDisplay: h.SpendDisplay, Tokens: h.Tokens, TokensDisplay: h.TokensDisplay, Turns: h.Turns, Tools: h.Tools, Errors: h.Errors}
	}
	cleanProviders := make([]ProviderData, len(providers))
	for i, p := range providers {
		cleanProviders[i] = ProviderData{Provider: p.Provider.String, Spend: p.Spend, SpendDisplay: p.SpendDisplay, Tokens: p.Tokens, TokensDisplay: p.TokensDisplay, Tools: p.Tools, Errors: p.Errors}
	}
	cleanModels := make([]ModelData, len(models))
	for i, m := range models {
		cleanModels[i] = ModelData{Model: m.Model.String, Provider: m.Provider, Spend: m.Spend, SpendDisplay: m.SpendDisplay, Sessions: m.Sessions, AvgCostPerSession: m.AvgCostPerSession, AvgCostPerSessionDisplay: m.AvgCostPerSessionDisplay, Tokens: m.Tokens, TokensDisplay: m.TokensDisplay, UnpricedTokens: m.UnpricedTokens, UnpricedTokensDisplay: m.UnpricedTokensDisplay, UnpricedSessions: m.UnpricedSessions, Tools: m.Tools, Errors: m.Errors}
	}
	cleanProjects := make([]ProjectData, len(projects))
	//nolint:gosec // Iterating over the same slice used to allocate cleanProjects keeps i in range.
	for i, p := range projects {
		cleanProjects[i] = ProjectData{Project: p.Project.String, Spend: p.Spend, SpendDisplay: p.SpendDisplay, Sessions: p.Sessions, AvgDuration: p.AvgDuration, AvgDurationDisplay: p.AvgDurationDisplay}
	}
	cleanTools := make([]ToolData, len(tools))
	for i, t := range tools {
		cleanTools[i] = ToolData{Tool: t.Tool.String, Count: t.Count, Errors: t.Errors, ErrorPct: t.ErrorPct}
	}
	cleanModelTools := make([]ModelToolData, len(modelTools))
	for i, mt := range modelTools {
		cleanModelTools[i] = ModelToolData{Model: mt.Model.String, Provider: mt.Provider, Tool: mt.Tool.String, Count: mt.Count, Errors: mt.Errors, ErrorPct: mt.ErrorPct}
	}
	cleanTimeline := make([]TimelineData, len(timeline))
	for i, tl := range timeline {
		cleanTimeline[i] = TimelineData{Date: tl.Date, Cost: tl.Cost, CostDisplay: tl.CostDisplay, Tokens: tl.Tokens, TokensDisplay: tl.TokensDisplay, ToolCalls: tl.ToolCalls, ToolCallsDisplay: tl.ToolCallsDisplay, ToolErrors: tl.ToolErrors, ToolErrorsDisplay: tl.ToolErrorsDisplay, ProfanityHits: tl.ProfanityHits, ProfanityHitsDisplay: tl.ProfanityHitsDisplay, FeelScore: tl.FeelScore, FeelDisplay: tl.FeelDisplay}
	}
	cleanProfanityModels := make([]ProfanityModelData, len(profanityModels))
	for i, m := range profanityModels {
		cleanProfanityModels[i] = ProfanityModelData{Model: m.Model.String, Provider: m.Provider, Count: m.Count, Sessions: m.Sessions}
	}
	sessionProfanityTotal := int64(0)
	sessionProfanityFeel := int64(0)
	sessionProfanityMood := "calm"
	if len(sessionProfanity) > 0 {
		sessionProfanityTotal = sessionProfanity[0].TotalHits
		sessionProfanityFeel = sessionProfanity[0].FeelScore
		sessionProfanityMood = sessionProfanity[0].FeelDisplay
	}

	isFragment := r.Header.Get("X-Fragment-Request") == stringTrue

	data := TemplateData{
		GeneratedAt:             time.Now().Format(time.RFC3339),
		IsFragment:              isFragment,
		Days:                    sumParams.Days,
		Harness:                 harParams.Harness,
		Provider:                proParams.Provider,
		Model:                   modParams.Model,
		Project:                 projParams.Project,
		Tool:                    toolParams.Tool,
		Filename:                sumParams.Filename,
		View:                    view,
		SortTable:               harParams.SortTable,
		SortBy:                  harParams.SortBy,
		SortDir:                 harParams.SortDir,
		Summary:                 summary,
		Harnesses:               cleanHarnesses,
		Providers:               cleanProviders,
		Models:                  cleanModels,
		Projects:                cleanProjects,
		Tools:                   cleanTools,
		ModelTools:              cleanModelTools,
		Timeline:                cleanTimeline,
		Sessions:                sessions,
		TotalSessions:           totalSessions,
		ProfanitySummary:        profanitySummary,
		ProfanityGroups:         profanityGroups,
		ProfanityModelHarnesses: profanityModelHarnesses,
		ProfanityModels:         cleanProfanityModels,
		ProfanityHarnesses:      profanityHarnesses,
		ProfanityDictionary:     getProfanityDictionaryInfo(),
		SessionProfanity:        sessionProfanity,
		SessionProfanityTotal:   sessionProfanityTotal,
		SessionProfanityFeel:    sessionProfanityFeel,
		SessionProfanityMood:    sessionProfanityMood,
		Diagnostics:             refreshState.snapshot(),
	}

	return data, nil
}
