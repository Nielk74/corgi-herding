// Package app hosts bounded two-player world actors, HTTP and WebSocket transport.
package app

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode"
	"unicode/utf8"

	"corgiherding/server/internal/game"
	"github.com/coder/websocket"
)

type Config struct {
	StateDir           string
	Version            string
	MaxSessions        int
	CheckpointInterval time.Duration
	Logger             *slog.Logger
}

type credentials struct {
	Code     string `json:"code"`
	PlayerID string `json:"player_id"`
	Token    string `json:"token"`
}

type savedHerd struct {
	World   *game.World       `json:"world"`
	Secrets map[string]string `json:"secrets"`
}

type checkpoint struct {
	Schema int         `json:"schema"`
	Herds  []savedHerd `json:"herds"`
}

type peer struct {
	id     string
	conn   *websocket.Conn
	cancel context.CancelFunc
	out    chan []byte
}

type event struct {
	kind          string
	id            string
	name          string
	hash          string
	input         game.Input
	peer          *peer
	result        chan error
	layoutVersion int
}

var errUpdateRequired = errors.New("Update Corgi Herding to visit this landscape.")
var errInvalidCredentials = errors.New("invalid herd credentials")

type herd struct {
	events chan event
	done   chan struct{}
	stop   chan struct{}
	state  atomic.Pointer[savedHerd]
	log    *slog.Logger
}

func newHerd(s savedHerd, log *slog.Logger) *herd {
	h := &herd{events: make(chan event, 128), done: make(chan struct{}), stop: make(chan struct{}), log: log}
	for i := range s.World.Players {
		s.World.Players[i].Connected = false
		if s.World.Layout.RockPass == nil && s.World.Layout.Ridge == nil {
			s.World.Players[i].Target = s.World.Players[i].Position
			if s.World.Players[i].State == "walking" {
				s.World.Players[i].State = "idle"
			}
		}
	}
	secrets := make(map[string]string, len(s.Secrets))
	for k, v := range s.Secrets {
		secrets[k] = v
	}
	h.state.Store(&savedHerd{World: s.World.Clone(), Secrets: secrets})
	go h.run(s)
	return h
}

func (h *herd) request(ctx context.Context, e event) error {
	e.result = make(chan error, 1)
	select {
	case h.events <- e:
	case <-h.done:
		return errors.New("server is stopping")
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case err := <-e.result:
		return err
	case <-h.done:
		return errors.New("server is stopping")
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (h *herd) run(s savedHerd) {
	defer close(h.done)
	ticker := time.NewTicker(time.Second / game.TickRate)
	defer ticker.Stop()
	peers := make(map[string]*peer, 2)
	store := func() {
		secrets := make(map[string]string, len(s.Secrets))
		for k, v := range s.Secrets {
			secrets[k] = v
		}
		h.state.Store(&savedHerd{World: s.World.Clone(), Secrets: secrets})
	}
	broadcast := func() {
		data, _ := json.Marshal(s.World)
		for _, p := range peers {
			// At most one pending snapshot: a slow connection never stalls the world.
			select {
			case p.out <- data:
			default:
				select {
				case <-p.out:
				default:
				}
				select {
				case p.out <- data:
				default:
				}
			}
		}
	}
	for {
		select {
		case <-h.stop:
			for id, p := range peers {
				p.cancel()
				s.World.Player(id).Connected = false
			}
			store()
			return
		case e := <-h.events:
			var err error
			switch e.kind {
			case "join":
				err = s.World.AddPlayer(e.id, e.name)
				if err == nil {
					s.Secrets[e.id] = e.hash
					store()
				}
			case "rollback_join":
				last := len(s.World.Players) - 1
				if last > 0 && s.World.Players[last].ID == e.id && peers[e.id] == nil {
					s.World.Players = s.World.Players[:last]
					delete(s.Secrets, e.id)
					store()
				} else {
					err = errors.New("could not roll back unsaved join")
				}
			case "connect":
				p := s.World.Player(e.id)
				if p == nil || subtle.ConstantTimeCompare([]byte(s.Secrets[e.id]), []byte(e.hash)) != 1 {
					err = errInvalidCredentials
					break
				}
				if !s.World.SupportsLayout(e.layoutVersion) {
					err = errUpdateRequired
					break
				}
				if previous := peers[e.id]; previous != nil {
					previous.cancel()
				}
				peers[e.id] = e.peer
				p.Connected = true
				h.log.Info("herder connected", "session_id", s.World.Code, "player_id", e.id, "tick", s.World.Tick)
				store()
				broadcast()
			case "disconnect":
				if peers[e.id] == e.peer {
					delete(peers, e.id)
					if p := s.World.Player(e.id); p != nil {
						p.Connected = false
						if s.World.Layout.RockPass == nil && s.World.Layout.Ridge == nil {
							p.Target = p.Position
							if p.State == "walking" {
								p.State = "idle"
							}
						}
					}
					store()
					broadcast()
					h.log.Info("herder disconnected", "session_id", s.World.Code, "player_id", e.id, "tick", s.World.Tick)
				}
			case "input":
				if peers[e.id] != e.peer {
					err = errors.New("connection has been replaced")
				} else {
					err = s.World.Apply(e.id, e.input)
				}
			}
			if e.result != nil {
				e.result <- err
			}
		case <-ticker.C:
			if len(peers) > 0 {
				s.World.Step()
				store()
				broadcast()
			}
		}
	}
}

type bucket struct {
	tokens float64
	last   time.Time
}

type Server struct {
	cfg          Config
	mu           sync.RWMutex
	herds        map[string]*herd
	limMu        sync.Mutex
	limits       map[string]bucket
	saveMu       sync.Mutex
	mutationMu   sync.Mutex
	closing      atomic.Bool
	persistError atomic.Bool
	closed       chan struct{}
	workerDone   chan struct{}
	closeOnce    sync.Once
	sockets      chan struct{}
}

func New(cfg Config) (*Server, error) {
	if cfg.MaxSessions <= 0 {
		cfg.MaxSessions = 100
	}
	if cfg.CheckpointInterval <= 0 {
		cfg.CheckpointInterval = 30 * time.Second
	}
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.StateDir == "" {
		return nil, errors.New("state directory is required")
	}
	if err := os.MkdirAll(cfg.StateDir, 0700); err != nil {
		return nil, err
	}
	s := &Server{cfg: cfg, herds: make(map[string]*herd), limits: make(map[string]bucket), closed: make(chan struct{}), workerDone: make(chan struct{}), sockets: make(chan struct{}, cfg.MaxSessions*2+32)}
	if err := s.load(); err != nil {
		return nil, err
	}
	go s.checkpointLoop()
	return s, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /readyz", s.health)
	mux.HandleFunc("POST /api/herds", s.create)
	mux.HandleFunc("POST /api/herds/{code}/join", s.join)
	mux.HandleFunc("GET /api/herds/{code}/ws", s.websocket)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		if s.closing.Load() {
			problem(w, http.StatusServiceUnavailable, "server is restarting")
			return
		}
		if strings.HasPrefix(r.URL.Path, "/api/") && !s.allow(r.RemoteAddr) {
			problem(w, http.StatusTooManyRequests, "please wait before trying again")
			return
		}
		mux.ServeHTTP(w, r)
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	n := len(s.herds)
	s.mu.RUnlock()
	status := "ok"
	code := http.StatusOK
	if s.persistError.Load() {
		status = "persistence_error"
		code = http.StatusServiceUnavailable
	}
	respond(w, code, map[string]any{"status": status, "version": s.cfg.Version, "protocol": 1, "layout_version": 1, "layout_versions": []int{1, 2, 3, 4}, "sessions": n})
}

func (s *Server) allow(remote string) bool {
	ip, _, err := net.SplitHostPort(remote)
	if err != nil {
		ip = remote
	}
	now := time.Now()
	s.limMu.Lock()
	defer s.limMu.Unlock()
	b, ok := s.limits[ip]
	if !ok {
		if len(s.limits) >= 4096 {
			for k, v := range s.limits {
				if now.Sub(v.last) > 2*time.Minute {
					delete(s.limits, k)
				}
			}
			if len(s.limits) >= 4096 {
				return false
			}
		}
		b = bucket{tokens: 20, last: now}
	}
	b.tokens = mathMin(20, b.tokens+now.Sub(b.last).Seconds()/3)
	b.last = now
	allowed := b.tokens >= 1
	if allowed {
		b.tokens--
	}
	s.limits[ip] = b
	return allowed
}

func mathMin(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

func randomString(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func decodeName(w http.ResponseWriter, r *http.Request) (string, error) {
	var body struct {
		Name string `json:"name"`
	}
	if err := decodeStrict(http.MaxBytesReader(w, r.Body, 1024), &body); err != nil {
		return "", errors.New("send a JSON name")
	}
	return cleanName(body.Name)
}

func decodeCreation(w http.ResponseWriter, r *http.Request) (string, string, error) {
	var body struct {
		Name      string          `json:"name"`
		Landscape json.RawMessage `json:"landscape"`
	}
	if err := decodeStrict(http.MaxBytesReader(w, r.Body, 1024), &body); err != nil {
		return "", "", errors.New("send a JSON name and optional landscape")
	}
	landscape := game.LandscapeAlpine
	if len(body.Landscape) > 0 {
		var selected string
		if err := json.Unmarshal(body.Landscape, &selected); err != nil {
			return "", "", errors.New("landscape must be alpine, cactus, larch, orchard, oasis or cloud")
		}
		landscape = selected
	}
	if !game.ValidLandscape(landscape) {
		return "", "", errors.New("landscape must be alpine, cactus, larch, orchard, oasis or cloud")
	}
	name, err := cleanName(body.Name)
	return name, landscape, err
}

func cleanName(raw string) (string, error) {
	name := strings.TrimSpace(raw)
	if name == "" {
		name = "Herder"
	}
	if !utf8.ValidString(name) || utf8.RuneCountInString(name) > 24 {
		return "", errors.New("names may contain at most 24 characters")
	}
	for _, r := range name {
		if unicode.IsControl(r) {
			return "", errors.New("name contains unsupported characters")
		}
	}
	return name, nil
}

func decodeStrict(r io.Reader, dst any) error {
	d := json.NewDecoder(r)
	d.DisallowUnknownFields()
	if err := d.Decode(dst); err != nil {
		return err
	}
	var extra any
	if err := d.Decode(&extra); err != io.EOF {
		return errors.New("expected one JSON object")
	}
	return nil
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	s.mutationMu.Lock()
	defer s.mutationMu.Unlock()
	name, landscape, err := decodeCreation(w, r)
	if err != nil {
		problem(w, 400, err.Error())
		return
	}
	token, err := randomString(32)
	if err != nil {
		problem(w, 500, "could not create credentials")
		return
	}
	id, err := randomString(8)
	if err != nil {
		problem(w, 500, "could not create credentials")
		return
	}
	s.mu.Lock()
	if s.closing.Load() {
		s.mu.Unlock()
		problem(w, 503, "server is restarting")
		return
	}
	if len(s.herds) >= s.cfg.MaxSessions {
		s.mu.Unlock()
		problem(w, 503, "this meadow server is full")
		return
	}
	var code string
	for {
		code, err = randomString(3)
		code = strings.ToUpper(code)
		if err != nil {
			s.mu.Unlock()
			problem(w, 500, "could not create invite")
			return
		}
		if s.herds[code] == nil {
			break
		}
	}
	world := game.New(code)
	world.Landscape = landscape
	world.Layout = game.LayoutForLandscape(landscape)
	_ = world.AddPlayer(id, name)
	h := newHerd(savedHerd{World: world, Secrets: map[string]string{id: hashToken(token)}}, s.cfg.Logger)
	s.herds[code] = h
	s.mu.Unlock()
	if err := s.Save(); err != nil {
		s.mu.Lock()
		delete(s.herds, code)
		s.mu.Unlock()
		close(h.stop)
		<-h.done
		_ = s.Save()
		s.cfg.Logger.Error("herd creation checkpoint failed", "error", err)
		problem(w, 503, "could not save the herd; try again later")
		return
	}
	s.cfg.Logger.Info("herd created", "session_id", code)
	respond(w, http.StatusCreated, credentials{Code: code, PlayerID: id, Token: token})
}

func (s *Server) find(code string) *herd {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.herds[strings.ToUpper(code)]
}

func (s *Server) join(w http.ResponseWriter, r *http.Request) {
	s.mutationMu.Lock()
	defer s.mutationMu.Unlock()
	if s.closing.Load() {
		problem(w, 503, "server is restarting")
		return
	}
	name, err := decodeName(w, r)
	if err != nil {
		problem(w, 400, err.Error())
		return
	}
	h := s.find(r.PathValue("code"))
	if h == nil {
		problem(w, 404, "herd not found")
		return
	}
	token, err := randomString(32)
	if err != nil {
		problem(w, 500, "could not create credentials")
		return
	}
	id, err := randomString(8)
	if err != nil {
		problem(w, 500, "could not create credentials")
		return
	}
	if err = h.request(r.Context(), event{kind: "join", id: id, name: name, hash: hashToken(token)}); err != nil {
		problem(w, 409, err.Error())
		return
	}
	if err = s.Save(); err != nil {
		rollbackCtx, rollbackCancel := context.WithTimeout(context.Background(), 2*time.Second)
		rollbackErr := h.request(rollbackCtx, event{kind: "rollback_join", id: id})
		rollbackCancel()
		if rollbackErr != nil {
			s.cfg.Logger.Error("failed to roll back unsaved join", "session_id", h.state.Load().World.Code, "error", rollbackErr)
		}
		_ = s.Save()
		s.cfg.Logger.Error("herd join checkpoint failed", "error", err)
		problem(w, 503, "could not save the herd; try again later")
		return
	}
	respond(w, http.StatusCreated, credentials{Code: h.state.Load().World.Code, PlayerID: id, Token: token})
}

func (s *Server) websocket(w http.ResponseWriter, r *http.Request) {
	select {
	case s.sockets <- struct{}{}:
		defer func() { <-s.sockets }()
	default:
		problem(w, 503, "server connection capacity reached")
		return
	}
	h := s.find(r.PathValue("code"))
	if h == nil {
		problem(w, 404, "herd not found")
		return
	}
	// Default origin checking protects browser clients. Native Godot sends no Origin.
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	defer conn.CloseNow()
	conn.SetReadLimit(2048)
	authCtx, cancelAuth := context.WithTimeout(r.Context(), 5*time.Second)
	_, payload, err := conn.Read(authCtx)
	cancelAuth()
	if err != nil {
		return
	}
	var auth game.Input
	if err = decodeStrict(strings.NewReader(string(payload)), &auth); err != nil || auth.Type != "auth" || len(auth.Token) != 64 || len(auth.PlayerID) != 16 {
		_ = conn.Close(websocket.StatusPolicyViolation, "authenticate with herd credentials")
		return
	}
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	p := &peer{id: auth.PlayerID, conn: conn, cancel: cancel, out: make(chan []byte, 1)}
	if err = h.request(ctx, event{kind: "connect", id: p.id, hash: hashToken(auth.Token), peer: p, layoutVersion: auth.LayoutVersion}); err != nil {
		if errors.Is(err, errUpdateRequired) {
			data, _ := json.Marshal(map[string]string{"type": "error", "code": "update_required", "message": errUpdateRequired.Error()})
			writeCtx, writeCancel := context.WithTimeout(ctx, 2*time.Second)
			_ = conn.Write(writeCtx, websocket.MessageText, data)
			writeCancel()
			_ = conn.Close(websocket.StatusCode(4002), "update required")
			return
		}
		if errors.Is(err, errInvalidCredentials) {
			_ = conn.Close(websocket.StatusPolicyViolation, "invalid herd credentials")
		} else {
			// Restart/cancellation is transient. Legacy clients interpret 1008 as
			// revoked credentials, so never use it for an unavailable world actor.
			_ = conn.Close(websocket.StatusTryAgainLater, "server temporarily unavailable")
		}
		return
	}
	defer func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), time.Second)
		defer cleanupCancel()
		_ = h.request(cleanupCtx, event{kind: "disconnect", id: p.id, peer: p})
	}()
	writerDone := make(chan struct{})
	go func() {
		defer close(writerDone)
		defer cancel()
		for {
			select {
			case <-ctx.Done():
				return
			case data := <-p.out:
				writeCtx, writeCancel := context.WithTimeout(ctx, 3*time.Second)
				err := conn.Write(writeCtx, websocket.MessageText, data)
				writeCancel()
				if err != nil {
					return
				}
			}
		}
	}()
	defer func() { cancel(); <-writerDone }()
	tokens, last := 80.0, time.Now()
	for {
		kind, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		now := time.Now()
		tokens = mathMin(80, tokens+now.Sub(last).Seconds()*40)
		last = now
		if tokens < 1 {
			_ = conn.Close(websocket.StatusPolicyViolation, "too many inputs")
			return
		}
		tokens--
		var input game.Input
		if kind != websocket.MessageText || decodeStrict(strings.NewReader(string(data)), &input) != nil {
			s.writeError(ctx, conn, "expected a protocol JSON message")
			continue
		}
		if err := h.request(ctx, event{kind: "input", id: p.id, input: input, peer: p}); err != nil {
			s.writeError(ctx, conn, err.Error())
		}
	}
}

func (s *Server) writeError(ctx context.Context, conn *websocket.Conn, message string) {
	data, _ := json.Marshal(map[string]string{"type": "error", "message": message})
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	_ = conn.Write(ctx, websocket.MessageText, data)
}

func respond(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
func problem(w http.ResponseWriter, status int, message string) {
	respond(w, status, map[string]string{"error": message})
}

func (s *Server) checkpointLoop() {
	defer close(s.workerDone)
	ticker := time.NewTicker(s.cfg.CheckpointInterval)
	defer ticker.Stop()
	for {
		select {
		case <-s.closed:
			return
		case <-ticker.C:
			if err := s.Save(); err != nil {
				s.cfg.Logger.Error("checkpoint failed", "error", err)
			}
		}
	}
}

func (s *Server) Save() (err error) {
	s.saveMu.Lock()
	defer s.saveMu.Unlock()
	defer func() { s.persistError.Store(err != nil) }()
	state := checkpoint{Schema: 1, Herds: []savedHerd{}}
	s.mu.RLock()
	for _, h := range s.herds {
		state.Herds = append(state.Herds, *h.state.Load())
	}
	s.mu.RUnlock()
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	temp, err := os.CreateTemp(s.cfg.StateDir, ".checkpoint-*")
	if err != nil {
		return err
	}
	name := temp.Name()
	defer os.Remove(name)
	if _, err = temp.Write(data); err != nil {
		_ = temp.Close()
		return err
	}
	if err = temp.Sync(); err != nil {
		_ = temp.Close()
		return err
	}
	if err = temp.Close(); err != nil {
		return err
	}
	if err = os.Rename(name, filepath.Join(s.cfg.StateDir, "herds.json")); err != nil {
		return err
	}
	// Sync directory metadata too, so an acknowledged invite survives a power loss.
	dir, err := os.Open(s.cfg.StateDir)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func (s *Server) load() error {
	file, err := os.Open(filepath.Join(s.cfg.StateDir, "herds.json"))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if info.Size() > 32<<20 {
		return errors.New("checkpoint exceeds 32 MiB limit")
	}
	var state checkpoint
	if err = decodeStrict(io.LimitReader(file, 32<<20), &state); err != nil {
		return fmt.Errorf("invalid checkpoint: %w", err)
	}
	if state.Schema != 1 || len(state.Herds) > s.cfg.MaxSessions {
		return errors.New("unsupported checkpoint schema or too many saved herds")
	}
	// Validate the entire checkpoint before starting any actors.
	seen := make(map[string]bool)
	for _, saved := range state.Herds {
		if saved.World == nil || len(saved.World.Code) != 6 || seen[saved.World.Code] || len(saved.World.Players) < 1 || len(saved.World.Players) > 2 || len(saved.World.Dogs) != 2 || len(saved.World.Sheep) != 10 {
			return errors.New("invalid saved herd")
		}
		seen[saved.World.Code] = true
		// Checkpoints from the first meadow build have no landscape field.
		if saved.World.Landscape == "" {
			saved.World.Landscape = game.LandscapeAlpine
		}
		if !game.ValidLandscape(saved.World.Landscape) {
			return errors.New("invalid saved landscape")
		}
		if saved.World.Layout == nil {
			if saved.World.Landscape != game.LandscapeAlpine && saved.World.Landscape != game.LandscapeCactus {
				return errors.New("missing saved landscape layout")
			}
			saved.World.Layout = game.LayoutForLandscape(saved.World.Landscape)
		}
		if err := saved.World.ValidateLayout(); err != nil {
			return err
		}
		if err := saved.World.ValidateForage(); err != nil {
			return err
		}
		if err := saved.World.ValidateNavigation(); err != nil {
			return err
		}
		for _, p := range saved.World.Players {
			if len(saved.Secrets[p.ID]) != 64 || !p.Position.Valid() || !p.Target.Valid() {
				return errors.New("invalid saved herder")
			}
		}
		for _, d := range saved.World.Dogs {
			if !d.Position.Valid() || !d.Target.Valid() {
				return errors.New("invalid saved corgi")
			}
		}
		for _, a := range saved.World.Sheep {
			if !a.Position.Valid() {
				return errors.New("invalid saved sheep")
			}
		}
	}
	for _, saved := range state.Herds {
		s.herds[saved.World.Code] = newHerd(saved, s.cfg.Logger)
	}
	return nil
}

// Close stops actors, closes connected sockets, and synchronously checkpoints.
func (s *Server) Close() error {
	var result error
	s.closeOnce.Do(func() {
		s.closing.Store(true)
		s.mutationMu.Lock()
		defer s.mutationMu.Unlock()
		close(s.closed)
		<-s.workerDone
		s.mu.RLock()
		herds := make([]*herd, 0, len(s.herds))
		for _, h := range s.herds {
			herds = append(herds, h)
		}
		s.mu.RUnlock()
		for _, h := range herds {
			close(h.stop)
		}
		for _, h := range herds {
			<-h.done
		}
		result = s.Save()
	})
	return result
}
