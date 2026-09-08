package app

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"corgiherding/server/internal/game"
)

func TestOasisCapabilityAndPausedRouteReconnectRestart(t *testing.T) {
	dir := t.TempDir()
	s, h := newTestServer(t, dir, 10)
	var a, b credentials
	if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"oasis"}`, 201), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
		t.Fatal(err)
	}
	for _, version := range []int{0, 1, 2, 9, 99} {
		expectUpdateRequired(t, connectVersion(t, h.URL, a, &version))
	}
	if s.find(a.Code).state.Load().World.Player(a.PlayerID).Connected {
		t.Fatal("unsupported client entered Oasis")
	}
	version := 3
	ca, cb := connectVersion(t, h.URL, a, &version), connectVersion(t, h.URL, b, &version)
	snapshot(t, ca, func(w *game.World) bool { return len(w.Players) == 2 && w.Player(b.PlayerID).Connected })
	target := game.Vec2{X: 10, Y: 0}
	write(t, ca, map[string]any{"type": "move", "seq": 7, "target": target})
	write(t, cb, map[string]any{"type": "command", "dog_id": "mochi", "command": "go", "target": target})
	snapshot(t, ca, func(w *game.World) bool {
		return w.Player(a.PlayerID).Seq == 7 && len(w.Player(a.PlayerID).Route) > 0 && len(w.Dogs[0].Route) > 0
	})
	oldVersion := 2
	expectUpdateRequired(t, connectVersion(t, h.URL, a, &oldVersion))
	write(t, ca, map[string]any{"type": "interact", "action": "gate"})
	if !strings.Contains(readError(t, ca), "no gate") {
		t.Fatal("Oasis accepted phantom gate")
	}
	write(t, ca, map[string]any{"type": "move", "seq": 8, "target": game.Vec2{X: 1}})
	if !strings.Contains(readError(t, ca), "dry land") {
		t.Fatal("Oasis accepted target inside rock")
	}
	_ = ca.CloseNow()
	paused := snapshot(t, cb, func(w *game.World) bool { return !w.Player(a.PlayerID).Connected })
	pausedPlayer := *paused.Player(a.PlayerID)
	later := snapshot(t, cb, func(w *game.World) bool { return w.Tick >= paused.Tick+3 })
	if !reflect.DeepEqual(*later.Player(a.PlayerID), pausedPlayer) || pausedPlayer.Target != target || len(pausedPlayer.Route) == 0 {
		t.Fatal("disconnected herder moved or lost its paused route")
	}
	replacement := connectVersion(t, h.URL, a, &version)
	snapshot(t, replacement, func(w *game.World) bool {
		p := w.Player(a.PlayerID)
		if p.Target != target || p.Seq != 7 {
			t.Fatal("reconnect lost route target or sequence")
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
		t.Fatal("fixture did not preserve an in-flight bypass")
	}
	restored, rh := newTestServer(t, dir, 10)
	loaded := restored.find(a.Code).state.Load()
	if !reflect.DeepEqual(loaded.World, cp.Herds[0].World) || !reflect.DeepEqual(loaded.Secrets, cp.Herds[0].Secrets) {
		t.Fatal("restart changed Oasis route, animals or credentials")
	}
	returned := connectVersion(t, rh.URL, a, &version)
	snapshot(t, returned, func(w *game.World) bool {
		p := w.Player(a.PlayerID)
		return p.Connected && p.Target == target && p.Seq == 7 && w.Layout.Equal(game.LayoutForLandscape(game.LandscapeOasis))
	})
}

func oasisCheckpoint(t *testing.T) checkpoint {
	t.Helper()
	cp, a := orchardCheckpoint(t)
	w := cp.Herds[0].World
	w.Landscape, w.Layout = game.LandscapeOasis, game.LayoutForLandscape(game.LandscapeOasis)
	if err := w.Apply(a.PlayerID, game.Input{Type: "move", Seq: 1, Target: &game.Vec2{X: 10}}); err != nil {
		t.Fatal(err)
	}
	if err := w.Apply(a.PlayerID, game.Input{Type: "command", DogID: "mochi", Command: "go", Target: &game.Vec2{X: 10}}); err != nil {
		t.Fatal(err)
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(err)
	}
	return cp
}

func TestInvalidOasisGeometryAndRoutesPreserveOriginalCheckpoint(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(*game.World)
	}{
		{"unknown_version", func(w *game.World) { w.Layout.Version = 4 }},
		{"missing_layout", func(w *game.World) { w.Layout = nil }},
		{"missing_rock", func(w *game.World) { w.Layout.RockPass = nil }},
		{"wrong_center", func(w *game.World) { w.Layout.RockPass.Center.X = 1 }},
		{"wrong_radius", func(w *game.World) { w.Layout.RockPass.Radius = 3.3 }},
		{"invented_bridge", func(w *game.World) { w.Layout.BridgeY = 1 }},
		{"invented_forage", func(w *game.World) { w.Layout.Forage = &game.ForageZone{ID: "windfall"} }},
		{"phantom_gate", func(w *game.World) { w.GateOpen = true }},
		{"player_in_rock", func(w *game.World) { w.Players[0].Position = game.Vec2{} }},
		{"player_target_in_rock", func(w *game.World) { w.Players[0].Target = game.Vec2{} }},
		{"dog_in_rock", func(w *game.World) { w.Dogs[0].Position = game.Vec2{} }},
		{"dog_target_in_rock", func(w *game.World) { w.Dogs[0].Target = game.Vec2{} }},
		{"sheep_in_rock", func(w *game.World) { w.Sheep[0].Position = game.Vec2{} }},
		{"nonanchor", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -6, Y: 5}} }},
		{"overlong", func(w *game.World) { w.Players[0].Route = make([]game.Vec2, 9) }},
		{"duplicate_anchor", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -5.2}, {X: -5.2}} }},
		{"first_segment_unsafe", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: 5.2}} }},
		{"middle_segment_unsafe", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -5.2}, {X: 5.2}} }},
		{"last_segment_unsafe", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -5.2}} }},
		{"idle_player_route", func(w *game.World) { w.Players[0].State = "idle" }},
		{"staying_dog_route", func(w *game.World) { w.Dogs[0].Route = w.Players[0].Route; w.Dogs[0].Command = "stay" }},
		{"legacy_player_route", func(w *game.World) {
			w.Landscape, w.Layout = game.LandscapeAlpine, game.LayoutForLandscape(game.LandscapeAlpine)
		}},
		{"legacy_empty_route", func(w *game.World) {
			w.Landscape, w.Layout = game.LandscapeOrchard, game.LayoutForLandscape(game.LandscapeOrchard)
			w.Players[0].Route = []game.Vec2{}
			w.Dogs[0].Route = nil
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cp := oasisCheckpoint(t)
			tc.mutate(cp.Herds[0].World)
			dir := t.TempDir()
			before := writeCheckpointFixture(t, dir, cp)
			// omitempty intentionally prevents production snapshots from emitting
			// empty queues. Inject explicit [] to test legacy-field rejection.
			if tc.name == "legacy_empty_route" {
				before = bytes.Replace(before, []byte(`"connected":false`), []byte(`"connected":false,"route":[]`), 1)
				if err := os.WriteFile(filepath.Join(dir, "herds.json"), before, 0600); err != nil {
					t.Fatal(err)
				}
			}
			if s, err := New(Config{StateDir: dir}); err == nil {
				_ = s.Close()
				t.Fatal("invalid Oasis checkpoint accepted")
			}
			after, err := os.ReadFile(filepath.Join(dir, "herds.json"))
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(before, after) {
				t.Fatal("invalid checkpoint overwritten")
			}
		})
	}
}
