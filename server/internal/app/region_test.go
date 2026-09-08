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

func TestRegionCapabilityAndPausedRouteReconnectRestart(t *testing.T) {
	dir := t.TempDir()
	s, h := newTestServer(t, dir, 10)
	var a, b credentials
	if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"alpine_valley"}`, 201), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
		t.Fatal(err)
	}
	for _, version := range []int{0, 1, 2, 3, 4, 5, 6, 8, 99} {
		expectUpdateRequired(t, connectVersion(t, h.URL, a, &version))
	}
	if s.find(a.Code).state.Load().World.Player(a.PlayerID).Connected {
		t.Fatal("unsupported client entered Region")
	}
	version := 7
	ca, cb := connectVersion(t, h.URL, a, &version), connectVersion(t, h.URL, b, &version)
	snapshot(t, ca, func(w *game.World) bool { return len(w.Players) == 2 && w.Player(b.PlayerID).Connected })
	target := game.Vec2{X: 30, Y: -63}
	write(t, ca, map[string]any{"type": "move", "seq": 7, "target": target})
	write(t, cb, map[string]any{"type": "command", "dog_id": "mochi", "command": "go", "target": target})
	snapshot(t, ca, func(w *game.World) bool {
		return w.Player(a.PlayerID).Seq == 7 && len(w.Player(a.PlayerID).Route) > 0 && len(w.Dogs[0].Route) > 0
	})
	// Unsupported future capabilities must not evict the already valid peer.
	for _, unsupported := range []int{6, 8, 99} {
		expectUpdateRequired(t, connectVersion(t, h.URL, a, &unsupported))
	}
	write(t, ca, map[string]any{"type": "interact", "action": "gate"})
	if !strings.Contains(readError(t, ca), "no gate") {
		t.Fatal("Region accepted phantom gate")
	}
	write(t, ca, map[string]any{"type": "move", "seq": 8, "target": game.Vec2{X: 72, Y: 96}})
	if !strings.Contains(readError(t, ca), "dry land") {
		t.Fatal("Region accepted void target")
	}
	_ = ca.CloseNow()
	paused := snapshot(t, cb, func(w *game.World) bool { return !w.Player(a.PlayerID).Connected })
	pausedPlayer := *paused.Player(a.PlayerID)
	later := snapshot(t, cb, func(w *game.World) bool { return w.Tick >= paused.Tick+3 })
	if !reflect.DeepEqual(*later.Player(a.PlayerID), pausedPlayer) || pausedPlayer.Target != target || len(pausedPlayer.Route) == 0 {
		t.Fatal("disconnected Region herder moved or lost route")
	}
	replacement := connectVersion(t, h.URL, a, &version)
	snapshot(t, replacement, func(w *game.World) bool {
		p := w.Player(a.PlayerID)
		if p.Target != target || p.Seq != 7 {
			t.Fatal("reconnect lost Region target/sequence")
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
		t.Fatal("fixture lost in-flight Region route")
	}
	restored, rh := newTestServer(t, dir, 10)
	loaded := restored.find(a.Code).state.Load()
	loadedJSON, _ := json.Marshal(loaded.World)
	savedJSON, _ := json.Marshal(cp.Herds[0].World)
	if !bytes.Equal(loadedJSON, savedJSON) || !reflect.DeepEqual(loaded.Secrets, cp.Herds[0].Secrets) {
		t.Fatal("restart changed Region layout/routes/animals/credentials")
	}
	time.Sleep(80 * time.Millisecond)
	if !reflect.DeepEqual(restored.find(a.Code).state.Load().World, loaded.World) {
		t.Fatal("empty Region world advanced after restart")
	}
	returned := connectVersion(t, rh.URL, a, &version)
	snapshot(t, returned, func(w *game.World) bool {
		p := w.Player(a.PlayerID)
		return p.Connected && p.Target == target && p.Seq == 7 && w.Layout.Equal(game.LayoutForLandscape(game.LandscapeAlpineValley))
	})
}

func TestRegionCapabilityPreservesAllEightEarlierLandscapes(t *testing.T) {
	for _, landscape := range []string{game.LandscapeAlpine, game.LandscapeCactus, game.LandscapeLarch, game.LandscapeOrchard, game.LandscapeOasis, game.LandscapeCloud, game.LandscapeJuniper, game.LandscapeBellflower} {
		t.Run(landscape, func(t *testing.T) {
			_, h := newTestServer(t, t.TempDir(), 10)
			var c credentials
			if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"`+landscape+`"}`, 201), &c); err != nil {
				t.Fatal(err)
			}
			for _, cap := range []int{game.LayoutForLandscape(landscape).Version, 7} {
				ws := connectVersion(t, h.URL, c, &cap)
				snapshot(t, ws, func(w *game.World) bool {
					if w.Layout.Region != nil || w.Landscape != landscape || !w.Layout.Equal(game.LayoutForLandscape(landscape)) {
						t.Fatal("new capability changed old world")
					}
					return true
				})
				_ = ws.CloseNow()
			}
		})
	}
}

func regionCheckpoint(t *testing.T) checkpoint {
	t.Helper()
	a := credentials{Code: "ABCDEF", PlayerID: "0123456789abcdef", Token: strings.Repeat("c", 64)}
	w := game.NewForLandscape(a.Code, game.LandscapeAlpineValley)
	if err := w.AddPlayer(a.PlayerID, "Ada"); err != nil {
		t.Fatal(err)
	}
	target := game.Vec2{X: 30, Y: -63}
	if err := w.Apply(a.PlayerID, game.Input{Type: "move", Seq: 7, Target: &target}); err != nil {
		t.Fatal(err)
	}
	if len(w.Players[0].Route) == 0 {
		t.Fatal("checkpoint needs a retained route")
	}
	return checkpoint{Schema: 1, Herds: []savedHerd{{World: w, Secrets: map[string]string{a.PlayerID: hashToken(a.Token)}}}}
}

func TestRegionInvalidCheckpointNeverStartsOrOverwrites(t *testing.T) {
	cases := []struct {
		name string
		edit func(*game.World)
	}{
		{"unknown_version", func(w *game.World) { w.Layout.Version = 8 }},
		{"missing_region", func(w *game.World) { w.Layout.Region = nil }},
		{"wrong_recipe", func(w *game.World) { w.Layout.Region.RecipeID = "untrusted" }},
		{"wrong_landscape", func(w *game.World) { w.Landscape = game.LandscapeAlpine }},
		{"bounds_expanded", func(w *game.World) { w.Layout.Region.Bounds.Max.X++ }},
		{"bounds_inverted", func(w *game.World) { w.Layout.Region.Bounds.Min.Y = 100 }},
		{"bounds_missing", func(w *game.World) { w.Layout.Region.Bounds = game.Bounds{} }},
		{"missing_anchor", func(w *game.World) { w.Layout.Region.Anchors = w.Layout.Region.Anchors[1:] }},
		{"duplicate_anchor", func(w *game.World) { w.Layout.Region.Anchors[1] = w.Layout.Region.Anchors[0] }},
		{"too_many_anchors", func(w *game.World) { w.Layout.Region.Anchors = make([]game.Vec2, 33) }},
		{"invalid_corridor_index", func(w *game.World) { w.Layout.Region.Corridors[0].A = -1 }},
		{"invalid_corridor_end", func(w *game.World) { w.Layout.Region.Corridors[0].B = 32 }},
		{"invalid_corridor_width", func(w *game.World) { w.Layout.Region.Corridors[0].HalfWidth = 0 }},
		{"changed_corridor_width", func(w *game.World) { w.Layout.Region.Corridors[0].HalfWidth = 10.00000001 }},
		{"invented_corridor", func(w *game.World) { w.Layout.Region.Corridors[0].B = 6 }},
		{"duplicate_corridor", func(w *game.World) {
			w.Layout.Region.Corridors = append(w.Layout.Region.Corridors, w.Layout.Region.Corridors[0])
		}},
		{"too_many_corridors", func(w *game.World) { w.Layout.Region.Corridors = make([]game.RegionCorridor, 65) }},
		{"missing_clearing", func(w *game.World) { w.Layout.Region.Clearings = w.Layout.Region.Clearings[1:] }},
		{"changed_clearing", func(w *game.World) { w.Layout.Region.Clearings[0].Radius++ }},
		{"extra_old_geometry", func(w *game.World) { w.Layout.Ridge = game.LayoutForLandscape(game.LandscapeCloud).Ridge }},
		{"gate", func(w *game.World) { w.GateOpen = true }},
		{"objective", func(w *game.World) { w.Settled = 10 }},
		{"player_outside", func(w *game.World) { w.Players[0].Position = game.Vec2{X: 73} }},
		{"player_void", func(w *game.World) { w.Players[0].Position = game.Vec2{X: 72, Y: 96} }},
		{"player_target_outside", func(w *game.World) { w.Players[0].Target = game.Vec2{Y: -97} }},
		{"dog_outside", func(w *game.World) { w.Dogs[0].Position = game.Vec2{X: -73} }},
		{"dog_target_void", func(w *game.World) { w.Dogs[0].Target = game.Vec2{X: 72, Y: 96} }},
		{"sheep_outside", func(w *game.World) { w.Sheep[0].Position = game.Vec2{Y: 97} }},
		{"sheep_void", func(w *game.World) { w.Sheep[0].Position = game.Vec2{X: 72, Y: 96} }},
		{"nonanchor_route", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: -24.99, Y: 43}} }},
		{"missing_needed_route", func(w *game.World) { w.Players[0].Route = nil }},
		{"overlong_route", func(w *game.World) { w.Players[0].Route = make([]game.Vec2, 33) }},
		{"duplicate_route", func(w *game.World) { w.Players[0].Route = append(w.Players[0].Route, w.Players[0].Route[0]) }},
		{"route_contains_target", func(w *game.World) { w.Players[0].Route = append(w.Players[0].Route, w.Players[0].Target) }},
		{"unsafe_first", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: 44, Y: -36}} }},
		{"unsafe_middle", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: 34, Y: 8}, {X: 44, Y: -78}} }},
		{"unsafe_last", func(w *game.World) { w.Players[0].Route = []game.Vec2{{X: 34, Y: 8}} }},
		{"idle_route", func(w *game.World) { w.Players[0].State = "idle" }},
		{"stay_route", func(w *game.World) { w.Dogs[0].Route = []game.Vec2{{X: -42, Y: 64}}; w.Dogs[0].Command = "stay" }},
		{"invalid_player_state", func(w *game.World) { w.Players[0].State = "flying" }},
		{"invalid_dog_state", func(w *game.World) { w.Dogs[0].State = "flying" }},
		{"invalid_sheep_state", func(w *game.World) { w.Sheep[0].State = "nibbling" }},
		{"invalid_sheep_speed", func(w *game.World) { w.Sheep[0].Velocity = game.Vec2{X: 3} }},
		{"forage", func(w *game.World) { w.Sheep[0].Forage = &game.SheepForage{ZoneID: "windfall", RemainingTicks: 80} }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cp := regionCheckpoint(t)
			tc.edit(cp.Herds[0].World)
			data, err := json.Marshal(cp)
			if err != nil {
				t.Fatal(err)
			}
			dir := t.TempDir()
			path := filepath.Join(dir, "herds.json")
			if err = os.WriteFile(path, data, 0600); err != nil {
				t.Fatal(err)
			}
			s, err := New(Config{StateDir: dir, Version: "test", MaxSessions: 10})
			if err == nil {
				_ = s.Close()
				t.Fatal("invalid region checkpoint accepted")
			}
			after, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(after, data) {
				t.Fatal("invalid region checkpoint overwritten", err)
			}
		})
	}
	for _, jsonCase := range []struct{ name, before, after string }{
		{"missing_corridor_a", `"a":0,"b":1`, `"b":1`},
		{"null_corridor_b", `"a":0,"b":1`, `"a":0,"b":null`},
		{"fractional_corridor_index", `"a":0,"b":1`, `"a":0.1,"b":1`},
		{"extra_corridor_field", `"a":0,"b":1`, `"a":0,"b":1,"admin":true`},
	} {
		t.Run(jsonCase.name, func(t *testing.T) {
			data, _ := json.Marshal(regionCheckpoint(t))
			changed := []byte(strings.Replace(string(data), jsonCase.before, jsonCase.after, 1))
			if bytes.Equal(data, changed) {
				t.Fatal("JSON mutation missed")
			}
			dir := t.TempDir()
			path := filepath.Join(dir, "herds.json")
			_ = os.WriteFile(path, changed, 0600)
			s, err := New(Config{StateDir: dir, MaxSessions: 10})
			if err == nil {
				_ = s.Close()
				t.Fatal("malformed region corridor accepted")
			}
			after, _ := os.ReadFile(path)
			if !bytes.Equal(after, changed) {
				t.Fatal("bad JSON overwritten")
			}
		})
	}
}
