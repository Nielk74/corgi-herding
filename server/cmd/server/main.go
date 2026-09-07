package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"corgiherding/server/internal/app"
)

var version = "dev"

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)
	addr := os.Getenv("CORGI_ADDR")
	if addr == "" {
		addr = ":8790"
	}
	dir := os.Getenv("CORGI_STATE_DIR")
	if dir == "" {
		dir = "data"
	}
	maxSessions := 100
	if raw := os.Getenv("CORGI_MAX_SESSIONS"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 10000 {
			logger.Error("CORGI_MAX_SESSIONS must be between 1 and 10000")
			os.Exit(1)
		}
		maxSessions = n
	}
	appServer, err := app.New(app.Config{StateDir: dir, Version: version, MaxSessions: maxSessions, Logger: logger})
	if err != nil {
		logger.Error("cannot load meadow server", "error", err)
		os.Exit(1)
	}
	httpServer := &http.Server{Addr: addr, Handler: appServer.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 8192}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	failed := make(chan error, 1)
	go func() {
		logger.Info("meadow server listening", "address", addr, "version", version)
		failed <- httpServer.ListenAndServe()
	}()
	exitCode := 0
	select {
	case <-ctx.Done():
	case err = <-failed:
		if err != http.ErrServerClosed {
			logger.Error("HTTP server stopped", "error", err)
			exitCode = 1
		}
	}
	if err = appServer.Close(); err != nil {
		logger.Error("final checkpoint failed", "error", err)
		exitCode = 1
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err = httpServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("HTTP shutdown failed", "error", err)
		exitCode = 1
	}
	logger.Info("meadow server stopped")
	if exitCode != 0 {
		os.Exit(exitCode)
	}
}
