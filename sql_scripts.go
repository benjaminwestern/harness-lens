package main

import (
	"bytes"
	"context"
	"database/sql"
	"embed"
	"fmt"
	"regexp"
	"strings"
	texttemplate "text/template"
)

//go:embed db/scripts/*.sql
var sqlScriptFS embed.FS

var sqlIdentPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

func sqlString(s string) string {
	return strings.ReplaceAll(s, `'`, `''`)
}

func sqlIdent(name string) (string, error) {
	if !sqlIdentPattern.MatchString(name) {
		return "", fmt.Errorf("unsafe SQL identifier %q", name)
	}
	return name, nil
}

func renderSQLScript(name string, data any) (string, error) {
	body, err := sqlScriptFS.ReadFile("db/scripts/" + name)
	if err != nil {
		return "", fmt.Errorf("read SQL script %s: %w", name, err)
	}
	tmpl, err := texttemplate.New(name).Funcs(texttemplate.FuncMap{
		"sql":   sqlString,
		"ident": sqlIdent,
	}).Parse(string(body))
	if err != nil {
		return "", fmt.Errorf("parse SQL script %s: %w", name, err)
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("render SQL script %s: %w", name, err)
	}
	return buf.String(), nil
}

func execSQLScript(ctx context.Context, dbConn *sql.DB, label, name string, data any) error {
	sqlText, err := renderSQLScript(name, data)
	if err != nil {
		return err
	}
	if _, err := dbConn.ExecContext(ctx, sqlText); err != nil {
		return fmt.Errorf("%s: %w", label, err)
	}
	return nil
}

func querySQLScript(ctx context.Context, dbConn *sql.DB, label, name string, data any) (*sql.Rows, error) {
	sqlText, err := renderSQLScript(name, data)
	if err != nil {
		return nil, err
	}
	rows, err := dbConn.QueryContext(ctx, sqlText)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", label, err)
	}
	return rows, nil
}

func prepareSQLScript(ctx context.Context, tx *sql.Tx, label, name string, data any) (*sql.Stmt, error) {
	sqlText, err := renderSQLScript(name, data)
	if err != nil {
		return nil, err
	}
	stmt, err := tx.PrepareContext(ctx, sqlText)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", label, err)
	}
	return stmt, nil
}
