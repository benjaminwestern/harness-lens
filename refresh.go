package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	refreshInitial   refreshTrigger = "initial"
	refreshScheduled refreshTrigger = "scheduled"
	refreshManual    refreshTrigger = "manual"
)

var (
	tablesReady            atomic.Bool
	refreshRequests        = make(chan refreshTrigger, 1)
	refreshSettingsChanged = make(chan struct{}, 1)
	dashboardUpdates       = newUpdateHub()
	analyticsMu            sync.RWMutex
	refreshState           = &refreshStateStore{state: Diagnostics{State: "starting", Message: "Waiting for first data refresh."}}
	refreshConfig          = &refreshConfigStore{enabled: true, interval: defaultRefreshInterval}
	profanityConfig        = &profanityConfigStore{enabled: true}
)

func newUpdateHub() *updateHub {
	return &updateHub{clients: make(map[chan struct{}]struct{})}
}

func (h *updateHub) subscribe() (chan struct{}, func()) {
	ch := make(chan struct{}, 1)
	h.mu.Lock()
	h.clients[ch] = struct{}{}
	h.mu.Unlock()
	return ch, func() {
		h.mu.Lock()
		delete(h.clients, ch)
		close(ch)
		h.mu.Unlock()
	}
}

func (h *updateHub) broadcast() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.clients {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

func (c *profanityConfigStore) snapshot() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.enabled
}

func (c *profanityConfigStore) set(enabled bool) {
	c.mu.Lock()
	c.enabled = enabled
	c.mu.Unlock()
}

func (c *refreshConfigStore) snapshot() (bool, time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.enabled, c.interval
}

func (c *refreshConfigStore) set(enabled bool, interval time.Duration) {
	if interval < time.Minute {
		interval = time.Minute
	}
	if interval > 24*time.Hour {
		interval = 24 * time.Hour
	}
	c.mu.Lock()
	c.enabled = enabled
	c.interval = interval
	c.mu.Unlock()
	select {
	case refreshSettingsChanged <- struct{}{}:
	default:
	}
}

func (c *refreshConfigStore) display() (bool, time.Duration, int) {
	enabled, interval := c.snapshot()
	return enabled, interval, int(interval / time.Minute)
}

func (s *refreshStateStore) snapshot() Diagnostics {
	s.mu.Lock()
	defer s.mu.Unlock()
	enabled, interval, minutes := refreshConfig.display()
	out := s.state
	out.TablesReady = tablesReady.Load()
	out.ProfanityCollectionEnabled = profanityConfig.snapshot()
	out.AutoRefreshEnabled = enabled
	out.RefreshIntervalMinutes = minutes
	if enabled {
		out.CycleInterval = interval.String()
		out.CycleDescription = "Auto-refresh is enabled."
	} else {
		out.CycleInterval = "off"
		out.CycleDescription = "Auto-refresh is off."
	}
	out.Revision = s.revision
	if !s.startedAt.IsZero() {
		out.LastStartedAt = s.startedAt.Format(time.RFC3339)
	}
	if !s.finishedAt.IsZero() {
		out.LastFinishedAt = s.finishedAt.Format(time.RFC3339)
	}
	if enabled && !s.nextRefreshAt.IsZero() {
		out.NextRefreshAt = s.nextRefreshAt.Format(time.RFC3339)
	}
	return out
}

func (s *refreshStateStore) setRunning(trigger refreshTrigger) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.startedAt = time.Now()
	s.state.State = "running"
	s.state.Trigger = string(trigger)
	s.state.Message = "Refreshing..."
	s.state.ErrorCode = ""
	s.state.ErrorMessage = ""
	s.state.RefreshInProgress = true
	s.revision++
}

func (s *refreshStateStore) setComplete(duration time.Duration, next time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.finishedAt = time.Now()
	s.nextRefreshAt = next
	s.state.State = "ok"
	s.state.Message = "Data refreshed."
	s.state.LastDuration = duration.Round(time.Second).String()
	s.state.RefreshInProgress = false
	s.revision++
}

func (s *refreshStateStore) setFailed(duration time.Duration, err error, next time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.finishedAt = time.Now()
	s.nextRefreshAt = next
	s.state.State = "error"
	s.state.Message = "Refresh failed."
	s.state.LastDuration = duration.Round(time.Second).String()
	s.state.RefreshInProgress = false
	var diag *diagError
	if errors.As(err, &diag) {
		s.state.ErrorCode = diag.Code
		s.state.ErrorMessage = diag.UserMessage()
	} else {
		s.state.ErrorCode = "refresh_failed"
		s.state.ErrorMessage = err.Error()
	}
	s.revision++
}

func (s *refreshStateStore) setQueued(trigger refreshTrigger) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Message = fmt.Sprintf("%s refresh requested; an existing refresh is already queued or running.", trigger)
	s.revision++
}

func (s *refreshStateStore) setNext(next time.Time) {
	s.mu.Lock()
	s.nextRefreshAt = next
	s.revision++
	s.mu.Unlock()
}

func (s *refreshStateStore) clearNext() {
	s.mu.Lock()
	s.nextRefreshAt = time.Time{}
	s.revision++
	s.mu.Unlock()
}

func requestRefresh(trigger refreshTrigger) bool {
	select {
	case refreshRequests <- trigger:
		appLog.Info("refresh requested", "trigger", trigger)
		return true
	default:
		refreshState.setQueued(trigger)
		dashboardUpdates.broadcast()
		appLog.Warn("refresh request skipped because one is already queued", "trigger", trigger)
		return false
	}
}

func renderStreamFragment(r *http.Request) (string, error) {
	view := r.URL.Query().Get("view")
	if view == viewSession && r.URL.Query().Get("filename") == "" {
		view = viewDashboard
	}
	if view != viewSession && view != viewDrill && view != viewProfanity {
		view = viewDashboard
	}
	var data TemplateData
	if tablesReady.Load() {
		var err error
		data, err = buildTemplateData(r.Context(), r, view)
		if err != nil {
			return "", fmt.Errorf("build stream fragment data: %w", err)
		}
	} else {
		data = emptyTemplateData(r, view)
	}
	data.IsFragment = true
	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "dashboard-content", data); err != nil {
		return "", fmt.Errorf("execute stream fragment template: %w", err)
	}
	return buf.String(), nil
}

func writeSSE(w http.ResponseWriter, flusher http.Flusher, event, data string) {
	_, _ = fmt.Fprintf(w, "event: %s\n", event)
	for _, line := range strings.Split(data, "\n") {
		_, _ = fmt.Fprintf(w, "data: %s\n", line)
	}
	_, _ = fmt.Fprint(w, "\n")
	flusher.Flush()
}

func refreshWorker() {
	for trigger := range refreshRequests {
		start := time.Now()
		refreshState.setRunning(trigger)
		dashboardUpdates.broadcast()
		err := refreshTables()
		duration := time.Since(start)
		enabled, interval := refreshConfig.snapshot()
		next := time.Time{}
		if enabled {
			next = time.Now().Add(interval)
		}
		if err != nil {
			refreshState.setFailed(duration, err, next)
			var diag *diagError
			if errors.As(err, &diag) {
				appLog.Error("refresh failed", diag.Fields()...)
			} else {
				appLog.Error("refresh failed", "error", err)
			}
		} else {
			tablesReady.Store(true)
			refreshState.setComplete(duration, next)
			appLog.Info("refresh completed", "trigger", trigger, "duration", duration.Round(time.Millisecond).String(), "next_refresh_at", next.Format(time.RFC3339))
		}
		dashboardUpdates.broadcast()
	}
}

func scheduleRefreshes() {
	requestRefresh(refreshInitial)
	for {
		enabled, interval := refreshConfig.snapshot()
		if !enabled {
			refreshState.clearNext()
			dashboardUpdates.broadcast()
			<-refreshSettingsChanged
			continue
		}
		next := time.Now().Add(interval)
		refreshState.setNext(next)
		dashboardUpdates.broadcast()
		timer := time.NewTimer(time.Until(next))
		select {
		case <-timer.C:
			requestRefresh(refreshScheduled)
		case <-refreshSettingsChanged:
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			continue
		}
	}
}

func handleRefresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if rejectCrossOriginWrite(w, r) {
		return
	}
	if requestRefresh(refreshManual) {
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte("refresh queued\n"))
		return
	}
	w.WriteHeader(http.StatusAccepted)
	_, _ = w.Write([]byte("refresh already queued\n"))
}

func handleRefreshSettings(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if rejectCrossOriginWrite(w, r) {
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	enabled := r.FormValue("enabled") == stringTrue || r.FormValue("enabled") == "on" || r.FormValue("enabled") == "1"
	minutes := int(defaultRefreshInterval / time.Minute)
	if raw := strings.TrimSpace(r.FormValue("minutes")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil {
			http.Error(w, "minutes must be a number", http.StatusBadRequest)
			return
		}
		minutes = parsed
	}
	if minutes < 1 || minutes > 1440 {
		http.Error(w, "minutes must be between 1 and 1440", http.StatusBadRequest)
		return
	}
	refreshConfig.set(enabled, time.Duration(minutes)*time.Minute)
	if enabled {
		refreshState.setNext(time.Now().Add(time.Duration(minutes) * time.Minute))
	} else {
		refreshState.clearNext()
	}
	dashboardUpdates.broadcast()
	appLog.Info("refresh settings updated", "enabled", enabled, "interval_minutes", minutes)
	w.WriteHeader(http.StatusAccepted)
	_, _ = w.Write([]byte("refresh settings updated\n"))
}

func handleProfanitySettings(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if rejectCrossOriginWrite(w, r) {
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	enabled := r.FormValue("enabled") == stringTrue || r.FormValue("enabled") == "on" || r.FormValue("enabled") == "1"
	profanityConfig.set(enabled)
	if requestRefresh(refreshManual) {
		appLog.Info("profanity settings updated; refresh queued", "enabled", enabled)
	} else {
		appLog.Info("profanity settings updated; refresh already queued", "enabled", enabled)
	}
	dashboardUpdates.broadcast()
	w.WriteHeader(http.StatusAccepted)
	_, _ = w.Write([]byte("profanity settings updated\n"))
}

func handleEvents(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	updates, unsubscribe := dashboardUpdates.subscribe()
	defer unsubscribe()

	send := func() {
		fragment, err := renderStreamFragment(r)
		if err != nil {
			log.Printf("stream render error: %v", err)
			writeSSE(w, flusher, "error", err.Error())
			return
		}
		writeSSE(w, flusher, "fragment", fragment)
	}
	send()

	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-updates:
			send()
		case <-heartbeat.C:
			_, _ = fmt.Fprint(w, ": ping\n\n")
			flusher.Flush()
		}
	}
}

func refreshTables() error {
	appLog.Info("refreshing ELT tables")
	analyticsMu.Lock()
	defer analyticsMu.Unlock()
	if err := ensureDuckDBInitialized(); err != nil {
		return err
	}
	if err := materializeCoreEvents(dbConn); err != nil {
		return diagnostic("elt_core_materialize_failed", "materialize_core_events", "Could not load source harness events into DuckDB.", err)
	}
	if profanityConfig.snapshot() {
		if err := materializeUserMessages(dbConn); err != nil {
			return diagnostic("elt_user_messages_failed", "materialize_user_messages", "Could not load user messages for profanity aggregation.", err)
		}
		defer func() {
			_ = execSQLScript(context.Background(), dbConn, "drop user messages", "drop_user_messages.sql", nil)
		}()
		if err := materializeProfanity(dbConn); err != nil {
			return diagnostic("elt_profanity_failed", "materialize_profanity", "Could not build profanity aggregates.", err)
		}
	} else {
		if err := materializeProfanityDisabled(dbConn); err != nil {
			return diagnostic("elt_profanity_disabled_failed", "materialize_profanity_disabled", "Could not clear profanity aggregates while collection is disabled.", err)
		}
	}
	if err := createAggregateViews(dbConn); err != nil {
		return diagnostic("elt_aggregate_views_failed", "create_aggregate_views", "Could not rebuild aggregate DuckDB views.", err)
	}
	if err := execSQLScript(context.Background(), dbConn, "refresh materialized tables", "refresh_materialized_tables.sql", nil); err != nil {
		return diagnostic("elt_materialized_tables_failed", "refresh_materialized_tables", "Could not refresh materialized analytics tables.", err)
	}
	appLog.Info("ELT tables refreshed")
	return nil
}
