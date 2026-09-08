package app

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"corgiherding/server/internal/game"
	"github.com/coder/websocket"
)

func newTestServer(t *testing.T, dir string, maxSessions int) (*Server, *httptest.Server) {
	t.Helper()
	s, err := New(Config{StateDir: dir, Version: "test-version", MaxSessions: maxSessions, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	if err != nil {
		t.Fatal(err)
	}
	h := httptest.NewServer(s.Handler())
	t.Cleanup(func() { _ = s.Close(); h.Close() })
	return s, h
}

func post(t *testing.T, url, body string, status int) []byte {
	t.Helper()
	resp, err := http.Post(url, "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != status {
		t.Fatalf("POST %s status %d expected %d: %s", url, resp.StatusCode, status, data)
	}
	return data
}

func createHerd(t *testing.T, base string) credentials {
	t.Helper()
	var c credentials
	if err := json.Unmarshal(post(t, base+"/api/herds", `{"name":"Ada"}`, 201), &c); err != nil {
		t.Fatal(err)
	}
	if len(c.Token) != 64 || len(c.Code) != 6 || len(c.PlayerID) != 16 {
		t.Fatalf("invalid credentials: %v", c)
	}
	return c
}

func connect(t *testing.T, base string, c credentials) *websocket.Conn {
	t.Helper()
	return connectVersion(t, base, c, nil)
}

func connectVersion(t *testing.T, base string, c credentials, version *int) *websocket.Conn {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(base, "http")+"/api/herds/"+c.Code+"/ws", nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.CloseNow() })
	auth := map[string]any{"type": "auth", "player_id": c.PlayerID, "token": c.Token}
	if version != nil {
		auth["layout_version"] = *version
	}
	write(t, conn, auth)
	return conn
}

func write(t *testing.T, conn *websocket.Conn, body any) {
	t.Helper()
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err = conn.Write(ctx, websocket.MessageText, data); err != nil {
		t.Fatal(err)
	}
}

func snapshot(t *testing.T, conn *websocket.Conn, predicate func(*game.World) bool) *game.World {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if bytes.Contains(data, []byte(`"token"`)) || bytes.Contains(data, []byte(`"secrets"`)) {
			t.Fatal("credentials leaked in wire snapshot")
		}
		var w game.World
		if err = json.Unmarshal(data, &w); err != nil {
			t.Fatal(err)
		}
		if w.Type == "snapshot" && predicate(&w) {
			return &w
		}
	}
}

func readError(t *testing.T, conn *websocket.Conn) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var msg struct {
			Type    string `json:"type"`
			Message string `json:"message"`
		}
		if err = json.Unmarshal(data, &msg); err != nil {
			t.Fatal(err)
		}
		if msg.Type == "error" {
			return msg.Message
		}
	}
}

func TestTwoPlayersCommandsReconnectionAndPersistence(t *testing.T) {
	dir := t.TempDir()
	server, httpServer := newTestServer(t, dir, 10)
	a := createHerd(t, httpServer.URL)
	var b credentials
	if err := json.Unmarshal(post(t, httpServer.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
		t.Fatal(err)
	}
	post(t, httpServer.URL+"/api/herds/"+a.Code+"/join", `{"name":"Third"}`, 409)
	ca, cb := connect(t, httpServer.URL, a), connect(t, httpServer.URL, b)
	w := snapshot(t, ca, func(w *game.World) bool {
		return len(w.Players) == 2 && w.Players[0].Connected && w.Players[1].Connected
	})
	if len(w.Dogs) != 2 || len(w.Sheep) != 10 {
		t.Fatal("incorrect meadow population")
	}
	write(t, ca, map[string]any{"type": "move", "seq": 7, "target": game.Vec2{X: -12, Y: -1.5}})
	snapshot(t, cb, func(w *game.World) bool {
		return w.Player(a.PlayerID).Seq == 7 && w.Player(a.PlayerID).Position.X > -12.9
	})
	write(t, cb, map[string]any{"type": "command", "dog_id": "mochi", "command": "stay"})
	snapshot(t, ca, func(w *game.World) bool { return w.Dogs[0].Command == "stay" && w.Dogs[0].Caller == b.PlayerID })
	write(t, ca, map[string]any{"type": "command", "dog_id": "mochi", "command": "come"})
	snapshot(t, cb, func(w *game.World) bool { return w.Dogs[0].Command == "come" && w.Dogs[0].Caller == a.PlayerID })
	write(t, ca, map[string]any{"type": "interact", "action": "sit"})
	snapshot(t, cb, func(w *game.World) bool { return w.Player(a.PlayerID).State == "sitting" })
	// A replacement connection owns control; an old socket cannot disconnect it.
	replacement := connect(t, httpServer.URL, a)
	snapshot(t, replacement, func(w *game.World) bool { return w.Player(a.PlayerID).Connected })
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	for {
		_, _, err := ca.Read(ctx)
		if err != nil {
			break
		}
	}
	cancel()
	write(t, replacement, map[string]any{"type": "move", "seq": 8, "target": game.Vec2{X: -11.7, Y: -1.5}})
	snapshot(t, replacement, func(w *game.World) bool { return w.Player(a.PlayerID).Seq == 8 })
	if err := server.Close(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "herds.json"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(data, []byte(a.Token)) || bytes.Contains(data, []byte(b.Token)) {
		t.Fatal("plaintext bearer token stored on disk")
	}
	info, err := os.Stat(filepath.Join(dir, "herds.json"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("checkpoint permissions: %v", info.Mode())
	}
	_, restored := newTestServer(t, dir, 10)
	rejoined := connect(t, restored.URL, a)
	resumed := snapshot(t, rejoined, func(w *game.World) bool { return w.Player(a.PlayerID).Connected })
	if resumed.Player(a.PlayerID).Seq != 8 || resumed.Players[1].Connected {
		t.Fatalf("restore lost sequence or retained stale connection: %+v", resumed.Players)
	}
}

func TestAuthAndMalformedInputIsolation(t *testing.T) {
	_, h := newTestServer(t, t.TempDir(), 10)
	a := createHerd(t, h.URL)
	bad := a
	bad.Token = strings.Repeat("0", 64)
	unauthorized := connect(t, h.URL, bad)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if _, _, err := unauthorized.Read(ctx); websocket.CloseStatus(err) != websocket.StatusPolicyViolation {
		t.Fatalf("expected auth policy close, got %v", err)
	}
	c := connect(t, h.URL, a)
	snapshot(t, c, func(w *game.World) bool { return true })
	write(t, c, map[string]any{"type": "move", "seq": 1, "target": game.Vec2{X: 999, Y: 0}})
	if !strings.Contains(readError(t, c), "meadow") {
		t.Fatal("bad target not rejected")
	}
	if err := c.Write(ctx, websocket.MessageText, []byte(`{"type":`)); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(readError(t, c), "JSON") {
		t.Fatal("malformed JSON not rejected")
	}
	write(t, c, map[string]any{"type": "interact", "action": "gate"})
	if !strings.Contains(readError(t, c), "closer") {
		t.Fatal("remote gate accepted")
	}
	write(t, c, map[string]any{"type": "move", "seq": 2, "target": game.Vec2{X: -12, Y: 0}})
	snapshot(t, c, func(w *game.World) bool { return w.Player(a.PlayerID).Seq == 2 })
}

func TestShutdownBetweenUpgradeAndAuthIsRetryable(t *testing.T) {
	s, h := newTestServer(t, t.TempDir(), 10)
	a := createHerd(t, h.URL)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	// The upgrade succeeds while the world exists, then shutdown wins before
	// its first authenticated actor request. Tokens are still valid on disk.
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(h.URL, "http")+"/api/herds/"+a.Code+"/ws", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.CloseNow()
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	write(t, conn, map[string]any{"type": "auth", "player_id": a.PlayerID, "token": a.Token})
	if _, _, err = conn.Read(ctx); websocket.CloseStatus(err) != websocket.StatusTryAgainLater {
		t.Fatalf("world shutdown must close1013 without invalidating credentials, got %v", err)
	}
}

func TestHTTPValidationCapacityAndHealth(t *testing.T) {
	_, h := newTestServer(t, t.TempDir(), 1)
	for _, body := range []string{`{"name":"Ada","admin":true}`, `{"name":"Ada"} {}`, `{"name":"1234567890123456789012345"}`, `{"name":"A\nB"}`, strings.Repeat("x", 2048)} {
		post(t, h.URL+"/api/herds", body, 400)
	}
	createHerd(t, h.URL)
	post(t, h.URL+"/api/herds", `{"name":"Overflow"}`, 503)
	post(t, h.URL+"/api/herds/XXXXXX/join", `{"name":"Missing"}`, 404)
	resp, err := http.Get(h.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var health struct {
		Status         string `json:"status"`
		Version        string `json:"version"`
		Sessions       int    `json:"sessions"`
		Protocol       int    `json:"protocol"`
		LayoutVersion  int    `json:"layout_version"`
		LayoutVersions []int  `json:"layout_versions"`
	}
	if err = json.NewDecoder(resp.Body).Decode(&health); err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 || health.Status != "ok" || health.Version != "test-version" || health.Sessions != 1 || health.Protocol != 1 || health.LayoutVersion != 1 || !reflect.DeepEqual(health.LayoutVersions, []int{1, 2}) {
		t.Fatalf("invalid health: %+v", health)
	}
}

func TestRateLimiterAndCorruptCheckpoint(t *testing.T) {
	s, _ := newTestServer(t, t.TempDir(), 10)
	for i := 0; i < 20; i++ {
		if !s.allow("192.0.2.1:1000") {
			t.Fatal("initial burst limited")
		}
	}
	if s.allow("192.0.2.1:2000") {
		t.Fatal("source port bypassed IP rate limit")
	}
	if !s.allow("192.0.2.2:1000") {
		t.Fatal("unrelated client rate limited")
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "herds.json"), []byte(`{"schema":999,"herds":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := New(Config{StateDir: dir}); err == nil {
		t.Fatal("unsupported persistence schema accepted")
	}
}

func TestFailedPersistenceDoesNotConsumeInviteSlot(t *testing.T) {
	dir := t.TempDir()
	s, h := newTestServer(t, dir, 10)
	a := createHerd(t, h.URL)
	// Point storage at a regular file to reproduce a full/unavailable volume
	// without changing system permissions or depending on the test user's UID.
	blocked := filepath.Join(dir, "blocked")
	if err := os.WriteFile(blocked, []byte("not a directory"), 0600); err != nil {
		t.Fatal(err)
	}
	s.saveMu.Lock()
	s.cfg.StateDir = blocked
	s.saveMu.Unlock()
	post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 503)
	if len(s.find(a.Code).state.Load().World.Players) != 1 {
		t.Fatal("failed save consumed permanent second slot")
	}
	post(t, h.URL+"/api/herds", `{"name":"Unsaved"}`, 503)
	s.mu.RLock()
	count := len(s.herds)
	s.mu.RUnlock()
	if count != 1 {
		t.Fatal("failed save left unreachable herd")
	}
	s.saveMu.Lock()
	s.cfg.StateDir = dir
	s.saveMu.Unlock()
	post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201)
}

func TestLandscapeSelectionSharedAndRestored(t *testing.T) {
	for _, tc := range []struct{ name, body, want string }{
		{"default", `{"name":"Ada"}`, "alpine"},
		{"alpine", `{"name":"Ada","landscape":"alpine"}`, "alpine"},
		{"cactus", `{"name":"Ada","landscape":"cactus"}`, "cactus"},
		{"larch", `{"name":"Ada","landscape":"larch"}`, "larch"},
		{"orchard", `{"name":"Ada","landscape":"orchard"}`, "orchard"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			s, h := newTestServer(t, dir, 10)
			var a, b credentials
			if err := json.Unmarshal(post(t, h.URL+"/api/herds", tc.body, 201), &a); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
				t.Fatal(err)
			}
			for _, creds := range []credentials{a, b} {
				version := 2
				conn := connectVersion(t, h.URL, creds, &version)
				w := snapshot(t, conn, func(w *game.World) bool { return true })
				if w.Landscape != tc.want {
					t.Fatalf("player received landscape %q, want %q", w.Landscape, tc.want)
				}
				if !w.Layout.Equal(game.LayoutForLandscape(tc.want)) {
					t.Fatalf("wrong shared layout: %+v", w.Layout)
				}
				_ = conn.CloseNow()
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			_, restored := newTestServer(t, dir, 10)
			version := 2
			conn := connectVersion(t, restored.URL, a, &version)
			w := snapshot(t, conn, func(w *game.World) bool { return true })
			if w.Landscape != tc.want {
				t.Fatalf("restart changed landscape to %q, want %q", w.Landscape, tc.want)
			}
			if !w.Layout.Equal(game.LayoutForLandscape(tc.want)) {
				t.Fatalf("restart changed immutable layout: %+v", w.Layout)
			}
		})
	}
}

func expectUpdateRequired(t *testing.T, conn *websocket.Conn) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var msg struct {
		Type    string `json:"type"`
		Code    string `json:"code"`
		Message string `json:"message"`
	}
	if err = json.Unmarshal(data, &msg); err != nil {
		t.Fatal(err)
	}
	if msg.Type != "error" || msg.Code != "update_required" || msg.Message == "" {
		t.Fatalf("expected update-required before any snapshot, got %s", data)
	}
	if _, _, err = conn.Read(ctx); websocket.CloseStatus(err) != 4002 {
		t.Fatalf("expected update-required close4002, got %v", err)
	}
}

func TestLayoutCapabilityProtectsLarchAndExistingConnection(t *testing.T) {
	s, h := newTestServer(t, t.TempDir(), 10)
	var a credentials
	if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"larch"}`, 201), &a); err != nil {
		t.Fatal(err)
	}
	legacy := connect(t, h.URL, a)
	expectUpdateRequired(t, legacy)
	if s.find(a.Code).state.Load().World.Player(a.PlayerID).Connected {
		t.Fatal("unsupported client entered the world")
	}
	version := 1
	current := connectVersion(t, h.URL, a, &version)
	snapshot(t, current, func(w *game.World) bool {
		return w.Player(a.PlayerID).Connected && w.Layout.BridgeY == -4 && w.Layout.GateY == 4
	})
	// Rejecting an old instance must not kick the already compatible instance.
	legacy = connect(t, h.URL, a)
	expectUpdateRequired(t, legacy)
	write(t, current, map[string]any{"type": "move", "seq": 12, "target": game.Vec2{X: 0, Y: -4}})
	snapshot(t, current, func(w *game.World) bool { return w.Player(a.PlayerID).Seq == 12 })
	write(t, current, map[string]any{"type": "move", "seq": 13, "target": game.Vec2{X: 0, Y: 0}})
	if !strings.Contains(readError(t, current), "dry land") {
		t.Fatal("centered bridge accepted in offset world")
	}
	unknown := 99
	expectUpdateRequired(t, connectVersion(t, h.URL, a, &unknown))
	centered := createHerd(t, h.URL)
	expectUpdateRequired(t, connectVersion(t, h.URL, centered, &unknown))
	// Legacy centered clients and saved credentials remain valid after rejection.
	centeredConnection := connect(t, h.URL, centered)
	snapshot(t, centeredConnection, func(w *game.World) bool { return w.Layout.Version == 1 && w.Layout.BridgeY == 0 && w.Layout.GateY == 0 })
	bad := a
	bad.Token = strings.Repeat("0", 64)
	unauthorized := connectVersion(t, h.URL, bad, &version)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if _, _, err := unauthorized.Read(ctx); websocket.CloseStatus(err) != websocket.StatusPolicyViolation {
		t.Fatalf("wrong token must remain an auth failure, got %v", err)
	}
}

func TestLegacyLayoutMigrationPreservesSavedHerd(t *testing.T) {
	for _, landscape := range []string{game.LandscapeAlpine, game.LandscapeCactus} {
		t.Run(landscape, func(t *testing.T) {
			dir := t.TempDir()
			s, h := newTestServer(t, dir, 10)
			var a, b credentials
			body, _ := json.Marshal(map[string]string{"name": "Ada", "landscape": landscape})
			if err := json.Unmarshal(post(t, h.URL+"/api/herds", string(body), 201), &a); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
				t.Fatal(err)
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "herds.json")
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var old checkpoint
			if err = json.Unmarshal(data, &old); err != nil {
				t.Fatal(err)
			}
			w := old.Herds[0].World
			w.Layout = nil
			w.Tick = 321
			w.GateOpen = true
			w.Settled = 1
			w.Players[0].Seq = 17
			w.Players[0].State = "sitting"
			w.Dogs[0].Command = "stay"
			w.Dogs[0].State = "happy"
			w.Dogs[0].Caller = a.PlayerID
			w.Sheep[0].Position = game.Vec2{X: 10, Y: 2}
			data, err = json.Marshal(old)
			if err != nil {
				t.Fatal(err)
			}
			data = bytes.Replace(data, []byte(`,"layout":null`), nil, 1)
			if err = os.WriteFile(path, data, 0600); err != nil {
				t.Fatal(err)
			}
			restored, server := newTestServer(t, dir, 10)
			state := restored.find(a.Code).state.Load()
			if !state.World.Layout.Equal(game.LayoutForLandscape(landscape)) {
				t.Fatal("missing legacy layout was not migrated to centered v1")
			}
			actual := state.World.Clone()
			actual.Layout = nil
			if !reflect.DeepEqual(actual, w) || !reflect.DeepEqual(state.Secrets, old.Herds[0].Secrets) {
				t.Fatal("layout migration changed animals, players, credentials or saved world state")
			}
			for _, creds := range []credentials{a, b} {
				conn := connect(t, server.URL, creds)
				snapshot(t, conn, func(w *game.World) bool { return w.Player(creds.PlayerID).Connected })
			}
			if err = restored.Close(); err != nil {
				t.Fatal(err)
			}
			data, err = os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Contains(data, []byte(`"layout":{"version":1,"bridge_y":0,"gate_y":0}`)) {
				t.Fatal("migrated layout was not saved")
			}
		})
	}
}

func TestUnknownSavedLayoutsFailWithoutOverwriting(t *testing.T) {
	for _, tc := range []struct {
		name, landscape string
		layout          *game.Layout
	}{
		{"unknown_version", game.LandscapeAlpine, &game.Layout{Version: 3}},
		{"wrong_center", game.LandscapeCactus, &game.Layout{Version: 1, GateY: 4}},
		{"missing_larch", game.LandscapeLarch, nil},
		{"missing_orchard", game.LandscapeOrchard, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := game.New("ABCDEF")
			_ = w.AddPlayer("0123456789abcdef", "Ada")
			w.Landscape = tc.landscape
			w.Layout = tc.layout
			state := checkpoint{Schema: 1, Herds: []savedHerd{{World: w, Secrets: map[string]string{w.Players[0].ID: strings.Repeat("a", 64)}}}}
			data, err := json.Marshal(state)
			if err != nil {
				t.Fatal(err)
			}
			dir := t.TempDir()
			path := filepath.Join(dir, "herds.json")
			if err = os.WriteFile(path, data, 0600); err != nil {
				t.Fatal(err)
			}
			if server, err := New(Config{StateDir: dir}); err == nil {
				_ = server.Close()
				t.Fatal("unsupported saved layout loaded")
			}
			after, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(data, after) {
				t.Fatal("failed migration overwrote original checkpoint")
			}
		})
	}
}

func TestLandscapeValidationAndLegacyCheckpoint(t *testing.T) {
	dir := t.TempDir()
	s, h := newTestServer(t, dir, 10)
	for _, body := range []string{
		`{"name":"Ada","landscape":"ocean"}`,
		`{"name":"Ada","landscape":""}`,
		`{"name":"Ada","landscape":42}`,
		`{"name":"Ada","landscape":null}`,
	} {
		post(t, h.URL+"/api/herds", body, 400)
	}
	a := createHerd(t, h.URL)
	post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea","landscape":"cactus"}`, 400)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "herds.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	legacy := bytes.Replace(data, []byte(`,"landscape":"alpine"`), nil, 1)
	if bytes.Equal(legacy, data) {
		t.Fatal("fixture did not remove landscape field")
	}
	if err = os.WriteFile(path, legacy, 0600); err != nil {
		t.Fatal(err)
	}
	restored, restoredHTTP := newTestServer(t, dir, 10)
	conn := connect(t, restoredHTTP.URL, a)
	w := snapshot(t, conn, func(w *game.World) bool { return true })
	if w.Landscape != "alpine" {
		t.Fatalf("legacy meadow loaded as %q", w.Landscape)
	}
	if err = restored.Close(); err != nil {
		t.Fatal(err)
	}
	data, err = os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(data, []byte(`"landscape":"alpine"`)) {
		t.Fatal("migration was not saved")
	}
}
