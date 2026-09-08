package app

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"corgiherding/server/internal/game"
)

func TestCloudCapabilityAndPausedRouteReconnectRestart(t *testing.T) {
	dir := t.TempDir()
	s, h := newTestServer(t, dir, 10)
	var a, b credentials
	if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"cloud"}`, 201), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
		t.Fatal(err)
	}
	for _, version := range []int{0, 1, 2, 3, 7, 99} {
		expectUpdateRequired(t, connectVersion(t, h.URL, a, &version))
	}
	if s.find(a.Code).state.Load().World.Player(a.PlayerID).Connected {
		t.Fatal("unsupported client entered Cloud")
	}
	version := 4
	ca, cb := connectVersion(t, h.URL, a, &version), connectVersion(t, h.URL, b, &version)
	snapshot(t, ca, func(w *game.World) bool { return len(w.Players) == 2 && w.Player(b.PlayerID).Connected })
	target := game.Vec2{X: 11, Y: 4}
	write(t, ca, map[string]any{"type": "move", "seq": 7, "target": target})
	write(t, cb, map[string]any{"type": "command", "dog_id": "mochi", "command": "go", "target": target})
	snapshot(t, ca, func(w *game.World) bool {
		return w.Player(a.PlayerID).Seq == 7 && len(w.Player(a.PlayerID).Route) > 0 && len(w.Dogs[0].Route) > 0
	})
	// Unsupported future capabilities must not evict the already valid peer.
	for _, unsupported := range []int{3, 7, 99} {
		expectUpdateRequired(t, connectVersion(t, h.URL, a, &unsupported))
	}
	write(t, ca, map[string]any{"type": "interact", "action": "gate"})
	if !strings.Contains(readError(t, ca), "no gate") {
		t.Fatal("Cloud accepted phantom gate")
	}
	write(t, ca, map[string]any{"type": "move", "seq": 8, "target": game.Vec2{X: 0, Y: 8}})
	if !strings.Contains(readError(t, ca), "dry land") {
		t.Fatal("Cloud accepted void target")
	}
	_ = ca.CloseNow()
	paused := snapshot(t, cb, func(w *game.World) bool { return !w.Player(a.PlayerID).Connected })
	pausedPlayer := *paused.Player(a.PlayerID)
	later := snapshot(t, cb, func(w *game.World) bool { return w.Tick >= paused.Tick+3 })
	if !reflect.DeepEqual(*later.Player(a.PlayerID), pausedPlayer) || pausedPlayer.Target != target || len(pausedPlayer.Route) == 0 {
		t.Fatal("disconnected Cloud herder moved or lost route")
	}
	replacement := connectVersion(t, h.URL, a, &version)
	snapshot(t, replacement, func(w *game.World) bool {
		p := w.Player(a.PlayerID)
		if p.Target != target || p.Seq != 7 {
			t.Fatal("reconnect lost Cloud target/sequence")
		}
		return p.Connected && p.Position.Sub(pausedPlayer.Position).Len() > .05
	})
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "herds.json"))
	if err != nil {
		t.Fatal(err)
	}
	var cp checkpoint
	if err = json.Unmarshal(data, &cp); err != nil {
		t.Fatal(err)
	}
	if len(cp.Herds[0].World.Player(a.PlayerID).Route) == 0 {
		t.Fatal("fixture lost in-flight Cloud route")
	}
	restored, rh := newTestServer(t, dir, 10)
	loaded := restored.find(a.Code).state.Load()
	if !reflect.DeepEqual(loaded.World, cp.Herds[0].World) || !reflect.DeepEqual(loaded.Secrets, cp.Herds[0].Secrets) {
		t.Fatal("restart changed Cloud layout/routes/animals/credentials")
	}
	time.Sleep(80 * time.Millisecond)
	if !reflect.DeepEqual(restored.find(a.Code).state.Load().World, loaded.World) {
		t.Fatal("empty Cloud world advanced after restart")
	}
	returned := connectVersion(t, rh.URL, a, &version)
	snapshot(t, returned, func(w *game.World) bool {
		p := w.Player(a.PlayerID)
		return p.Connected && p.Target == target && p.Seq == 7 && w.Layout.Equal(game.LayoutForLandscape(game.LandscapeCloud))
	})
}

func cloudCheckpoint(t *testing.T) checkpoint {
	t.Helper()
	a := credentials{Code: "ABCDEF", PlayerID: "0123456789abcdef", Token: strings.Repeat("c", 64)}
	w := game.New(a.Code)
	w.Landscape, w.Layout = game.LandscapeCloud, game.LayoutForLandscape(game.LandscapeCloud)
	if err := w.AddPlayer(a.PlayerID, "Ada"); err != nil {
		t.Fatal(err)
	}
	target := game.Vec2{X: 11, Y: 4}
	if err := w.Apply(a.PlayerID, game.Input{Type: "move", Seq: 7, Target: &target}); err != nil {
		t.Fatal(err)
	}
	if err := w.Apply(a.PlayerID, game.Input{Type: "command", DogID: "mochi", Command: "go", Target: &target}); err != nil {
		t.Fatal(err)
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(err)
	}
	return checkpoint{Schema: 1, Herds: []savedHerd{{World: w, Secrets: map[string]string{a.PlayerID: hashToken(a.Token)}}}}
}

func TestInvalidCloudGeometryAndRoutesPreserveOriginalCheckpoint(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(*game.World)
	}{
		{"unknown_version", func(w *game.World) { w.Layout.Version = 5 }},
		{"missing_layout", func(w *game.World) { w.Layout = nil }},
		{"missing_ridge", func(w *game.World) { w.Layout.Ridge = nil }},
		{"empty_spine", func(w *game.World) { w.Layout.Ridge.Spine = nil }},
		{"wrong_spine", func(w *game.World) { w.Layout.Ridge.Spine[1].Y = -4.9 }},
		{"reordered_spine", func(w *game.World) {
			w.Layout.Ridge.Spine[0], w.Layout.Ridge.Spine[1] = w.Layout.Ridge.Spine[1], w.Layout.Ridge.Spine[0]
		}},
		{"wrong_width", func(w *game.World) { w.Layout.Ridge.HalfWidth = 3.61 }},
		{"missing_shelf", func(w *game.World) { w.Layout.Ridge.Shelves = w.Layout.Ridge.Shelves[:2] }},
		{"wrong_shelf_center", func(w *game.World) { w.Layout.Ridge.Shelves[0].Center.X = -9 }},
		{"wrong_shelf_radius", func(w *game.World) { w.Layout.Ridge.Shelves[0].Radius = 6.21 }},
		{"wrong_rest", func(w *game.World) { w.Layout.Ridge.Rest.Radius = 5.2 }},
		{"invented_bridge", func(w *game.World) { w.Layout.BridgeY = 1 }},
		{"invented_forage", func(w *game.World) { w.Layout.Forage = &game.ForageZone{ID: "windfall"} }},
		{"invented_rock", func(w *game.World) { w.Layout.RockPass = &game.RockPass{Radius: 3.4} }},
		{"phantom_gate", func(w *game.World) { w.GateOpen = true }},
		{"player_in_void", func(w *game.World) { w.Players[0].Position = game.Vec2{Y: 8} }},
		{"player_target_in_void", func(w *game.World) { w.Players[0].Target = game.Vec2{Y: 8} }},
		{"dog_in_void", func(w *game.World) { w.Dogs[0].Position = game.Vec2{Y: 8} }},
		{"dog_target_in_void", func(w *game.World) { w.Dogs[0].Target = game.Vec2{Y: 8} }},
		{"sheep_in_void", func(w *game.World) { w.Sheep[0].Position = game.Vec2{Y: 8} }},
		{"out_of_bounds", func(w *game.World) { w.Players[0].Position = game.Vec2{X: 18} }},
		{"nonanchor", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -2, Y: -4.99}} }},
		{"target_in_route", func(w *game.World) { w.Players[0].Route = append(w.Players[0].Route, w.Players[0].Target) }},
		{"overlong", func(w *game.World) { w.Players[0].Route = make([]game.Vec2, 5) }},
		{"duplicate_anchor", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -2, Y: -5}, {X: -2, Y: -5}} }},
		{"first_segment_unsafe", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: 11, Y: 4}} }},
		{"middle_segment_unsafe", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -10}, {X: 11, Y: 4}} }},
		{"last_segment_unsafe", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -10}} }},
		{"idle_player_route", func(w *game.World) { w.Players[0].State = "idle" }},
		{"staying_dog_route", func(w *game.World) { w.Dogs[0].Command = "stay" }},
		{"ridge_on_old_landscape", func(w *game.World) { w.Landscape = game.LandscapeOasis }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cp := cloudCheckpoint(t)
			tc.mutate(cp.Herds[0].World)
			dir := t.TempDir()
			before := writeCheckpointFixture(t, dir, cp)
			if s, err := New(Config{StateDir: dir}); err == nil {
				_ = s.Close()
				t.Fatal("invalid Cloud checkpoint accepted")
			}
			after, err := os.ReadFile(filepath.Join(dir, "herds.json"))
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(before, after) {
				t.Fatal("invalid Cloud checkpoint overwritten")
			}
		})
	}
}
