package main

import (
	"log/slog"
	"os"
	"strings"
)

func (e *diagError) Error() string {
	parts := []string{"diagnostic"}
	if e.Source != "" {
		parts = append(parts, "source="+e.Source)
	}
	if e.Code != "" {
		parts = append(parts, "code="+e.Code)
	}
	if e.Operation != "" {
		parts = append(parts, "op="+e.Operation)
	}
	if e.Message != "" {
		parts = append(parts, "msg="+e.Message)
	}
	if e.Err != nil {
		parts = append(parts, "cause="+e.Err.Error())
	}
	return strings.Join(parts, " ")
}

func (e *diagError) Unwrap() error { return e.Err }

func (e *diagError) UserMessage() string {
	if e.Message != "" {
		return e.Message
	}
	if e.Err != nil {
		return e.Err.Error()
	}
	return e.Operation + " failed"
}

func (e *diagError) Fields() []any {
	fields := []any{"source", e.Source, "code", e.Code, "operation", e.Operation, "message", e.UserMessage()}
	if e.Err != nil {
		fields = append(fields, "error", e.Err)
	}
	return fields
}

func diagnostic(code, op, msg string, err error) *diagError {
	return &diagError{Source: "go", Code: code, Operation: op, Message: msg, Err: err}
}

func newLogger() *slog.Logger {
	level := slog.LevelInfo
	if strings.EqualFold(os.Getenv("LOG_LEVEL"), "debug") {
		level = slog.LevelDebug
	}
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
}
