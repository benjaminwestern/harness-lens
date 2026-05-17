package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
)

var (
	standardEventViews       []string
	standardUserMessageViews []string
	dbInitialized            atomic.Bool
)

func initDuckDB(dbConn *sql.DB) error {
	ctx := context.Background()
	if err := execSQLScript(ctx, dbConn, "duckdb init", "init_duckdb.sql", nil); err != nil {
		return err
	}

	home, _ := os.UserHomeDir()
	opencodeDb := filepath.Join(home, ".local", "share", "opencode", "opencode.db")
	opencodeExists := false
	if _, err := os.Stat(opencodeDb); err == nil {
		opencodeExists = true
		if err := execSQLScript(ctx, dbConn, "attach opencode", "attach_opencode.sql", map[string]string{"Path": opencodeDb}); err != nil {
			log.Printf("warn: could not attach opencode: %v", err)
			opencodeExists = false
		}
	}

	if err := createPricingViews(dbConn); err != nil {
		return err
	}
	if err := createStandardEventViews(dbConn, home, opencodeExists); err != nil {
		return err
	}
	return nil
}

func createPricingViews(dbConn *sql.DB) error {
	return execSQLScript(context.Background(), dbConn, "pricing views", "pricing_views.sql", nil)
}

func hasFilesUnder(root, suffix string) bool {
	if _, err := os.Stat(root); err != nil {
		return false
	}
	found := false
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if found || d.IsDir() {
			return nil
		}
		if strings.HasSuffix(path, suffix) {
			found = true
		}
		return nil
	})
	return found
}

func createStandardEventViews(dbConn *sql.DB, home string, opencodeExists bool) error {
	standardEventViews = nil
	standardUserMessageViews = nil
	data := map[string]string{"Home": home}
	addView := func(name, label, script string, data any) error {
		if err := execSQLScript(context.Background(), dbConn, label, script, data); err != nil {
			return err
		}
		standardEventViews = append(standardEventViews, name)
		return nil
	}
	addUserView := func(name, label, script string, data any) error {
		if err := execSQLScript(context.Background(), dbConn, label, script, data); err != nil {
			return err
		}
		standardUserMessageViews = append(standardUserMessageViews, name)
		return nil
	}

	if matches, _ := filepath.Glob(filepath.Join(home, ".pi", "agent", "sessions", "*", "*.jsonl")); len(matches) > 0 {
		if err := addView("std_pi_events", "std pi events", "std_pi_events.sql", data); err != nil {
			return err
		}
		if err := addUserView("std_pi_user_messages", "std pi user messages", "std_pi_user_messages.sql", data); err != nil {
			return err
		}
	}

	if opencodeExists {
		if err := addView("std_opencode_assistant_events", "std opencode assistant events", "std_opencode_assistant_events.sql", nil); err != nil {
			return err
		}
		if err := addView("std_opencode_user_events", "std opencode user events", "std_opencode_user_events.sql", nil); err != nil {
			return err
		}
		if err := addView("std_opencode_tool_events", "std opencode tool events", "std_opencode_tool_events.sql", nil); err != nil {
			return err
		}
		if err := addUserView("std_opencode_user_messages", "std opencode user messages", "std_opencode_user_messages.sql", nil); err != nil {
			return err
		}
	}

	if hasFilesUnder(filepath.Join(home, ".claude", "projects"), ".jsonl") {
		if err := addView("std_claude_events", "std claude events", "std_claude_events.sql", data); err != nil {
			return err
		}
		if err := addUserView("std_claude_user_messages", "std claude user messages", "std_claude_user_messages.sql", data); err != nil {
			return err
		}
	}

	if matches, _ := filepath.Glob(filepath.Join(home, ".codex", "sessions", "*", "*", "*", "*.jsonl")); len(matches) > 0 {
		if err := addView("std_codex_events", "std codex events", "std_codex_events.sql", data); err != nil {
			return err
		}
		if err := addUserView("std_codex_user_messages", "std codex user messages", "std_codex_user_messages.sql", data); err != nil {
			return err
		}
	}

	if matches, _ := filepath.Glob(filepath.Join(home, ".gemini", "tmp", "*", "chats", "*.json")); len(matches) > 0 {
		if err := addView("std_gemini_message_events", "std gemini message events", "std_gemini_message_events.sql", data); err != nil {
			return err
		}
		if err := addView("std_gemini_tool_events", "std gemini tool events", "std_gemini_tool_events.sql", data); err != nil {
			return err
		}
		if err := addUserView("std_gemini_user_messages", "std gemini user messages", "std_gemini_user_messages.sql", data); err != nil {
			return err
		}
	}

	if len(standardEventViews) == 0 {
		return fmt.Errorf("no harness session sources found")
	}
	return nil
}

func materializeCoreEvents(dbConn *sql.DB) error {
	for _, view := range standardEventViews {
		log.Printf("ELT core insert: %s", view)
	}
	return execSQLScript(context.Background(), dbConn, "materialize core events", "materialize_core_events.sql", map[string][]string{"Views": standardEventViews})
}

func materializeUserMessages(dbConn *sql.DB) error {
	for _, view := range standardUserMessageViews {
		appLog.Info("ELT user message insert", "view", view)
	}
	return execSQLScript(context.Background(), dbConn, "materialize user messages", "materialize_user_messages.sql", map[string][]string{"Views": standardUserMessageViews})
}

func createProfanityTables(dbConn *sql.DB) error {
	return execSQLScript(context.Background(), dbConn, "create profanity tables", "create_profanity_tables.sql", nil)
}

func materializeProfanityDisabled(dbConn *sql.DB) error {
	if err := createProfanityTables(dbConn); err != nil {
		return err
	}
	if err := execSQLScript(context.Background(), dbConn, "drop user messages", "drop_user_messages.sql", nil); err != nil {
		return err
	}
	appLog.Info("profanity collection disabled; skipped user message extraction")
	return nil
}

func materializeProfanity(dbConn *sql.DB) error {
	if err := createProfanityTables(dbConn); err != nil {
		return err
	}
	detector, err := loadProfanityDetector()
	if err != nil {
		return diagnostic("profanity_dictionary_invalid", "load_profanity_dictionary", "Could not load the profanity dictionary.", err)
	}
	setCurrentProfanityDetector(detector)
	appLog.Info("profanity detector loaded", "words", detector.count, "custom_dictionary", detector.custom, "mode", detector.mode)

	rows, err := querySQLScript(context.Background(), dbConn, "read user messages for profanity", "select_user_messages_for_profanity.sql", nil)
	if err != nil {
		return err
	}
	defer func() { _ = rows.Close() }()
	hits := make([]profanityHit, 0)
	var hitID int64
	for rows.Next() {
		var harness, filename, text string
		var project sql.NullString
		var ts sql.NullInt64
		if err := rows.Scan(&harness, &filename, &project, &ts, &text); err != nil {
			return fmt.Errorf("scan user message for profanity: %w", err)
		}
		for _, match := range detector.detect(text) {
			hitID++
			hits = append(hits, profanityHit{id: hitID, harness: harness, filename: filename, project: project.String, ts: ts.Int64, word: match.Word, group: match.Group, severity: string(match.Severity)})
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate user messages for profanity: %w", err)
	}

	tx, err := dbConn.BeginTx(context.Background(), nil)
	if err != nil {
		return fmt.Errorf("begin profanity insert: %w", err)
	}
	stmt, err := prepareSQLScript(context.Background(), tx, "prepare profanity insert", "insert_profanity_hit.sql", nil)
	if err != nil {
		_ = tx.Rollback()
		return err
	}
	defer func() { _ = stmt.Close() }()
	for _, hit := range hits {
		if _, err := stmt.ExecContext(context.Background(), hit.id, hit.harness, hit.filename, hit.project, hit.ts, hit.word, hit.group, hit.severity); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("insert profanity hit: %w", err)
		}
	}
	if err := stmt.Close(); err != nil {
		_ = tx.Rollback()
		return fmt.Errorf("close profanity insert: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit profanity hits: %w", err)
	}

	if err := execSQLScript(context.Background(), dbConn, "attribute profanity hits", "attribute_profanity_hits.sql", nil); err != nil {
		return err
	}
	appLog.Info("profanity hits materialized", "hits", hitID)
	return nil
}

func createAggregateViews(dbConn *sql.DB) error {
	return execSQLScript(context.Background(), dbConn, "aggregate views", "aggregate_views.sql", nil)
}

func ensureDuckDBInitialized() error {
	if dbInitialized.Load() {
		return nil
	}
	if err := execSQLScript(context.Background(), dbConn, "set memory limit", "set_memory_limit.sql", nil); err != nil {
		appLog.Warn("could not set DuckDB memory limit", "error", err)
	}
	if err := initDuckDB(dbConn); err != nil {
		return diagnostic("duckdb_init_failed", "init_duckdb", "Could not initialize DuckDB extensions and source views.", err)
	}
	dbInitialized.Store(true)
	return nil
}
