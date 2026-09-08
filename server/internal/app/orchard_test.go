package app

import (
	"bytes"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"corgiherding/server/internal/game"
)

func TestOrchardCapabilityRejectionPreservesCompatibleConnection(t *testing.T) {
	s, h := newTestServer(t, t.TempDir(), 10)
	var a credentials
	if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"orchard"}`, http.StatusCreated), &a); err != nil {
		t.Fatal(err)
	}
	for _, version := range []int{0, 1, 6, -1, 99} {
		expectUpdateRequired(t, connectVersion(t, h.URL, a, &version))
		if s.find(a.Code).state.Load().World.Player(a.PlayerID).Connected {
			t.Fatal("unsupported client entered Orchard")
		}
	}
	version := 2
	current := connectVersion(t, h.URL, a, &version)
	snapshot(t, current, func(w *game.World) bool {
		return w.Player(a.PlayerID).Connected && w.Layout.Equal(game.LayoutForLandscape(game.LandscapeOrchard))
	})
	oldVersion := 1
	expectUpdateRequired(t, connectVersion(t, h.URL, a, &oldVersion))
	write(t, current, map[string]any{"type": "move", "seq": 12, "target": game.Vec2{X: 0, Y: 3}})
	snapshot(t, current, func(w *game.World) bool { return w.Player(a.PlayerID).Seq == 12 })
	write(t, current, map[string]any{"type": "move", "seq": 13, "target": game.Vec2{X: 0, Y: 0}})
	if !strings.Contains(readError(t, current), "dry land") {
		t.Fatal("old centered bridge was accepted in Orchard")
	}
}

func orchardCheckpoint(t *testing.T) (checkpoint, credentials) {
	t.Helper()
	a := credentials{Code: "ABCDEF", PlayerID: "0123456789abcdef", Token: strings.Repeat("c", 64)}
	w := game.New(a.Code)
	w.Landscape, w.Layout = game.LandscapeOrchard, game.LayoutForLandscape(game.LandscapeOrchard)
	if err := w.AddPlayer(a.PlayerID, "Ada"); err != nil {
		t.Fatal(err)
	}
	// Controlled offline fixture: sheep still start at the normal ten spawn points.
	// Only the herder/dog positions are chosen to keep their pressure out of the patch.
	w.Players[0].Position, w.Players[0].Target = game.Vec2{X: -14, Y: 3}, game.Vec2{X: -14, Y: 3}
	for i := range w.Dogs {
		w.Dogs[i].Position = game.Vec2{X: -16, Y: float64(i*18 - 9)}
		w.Dogs[i].Target, w.Dogs[i].Command = w.Dogs[i].Position, "stay"
	}
	return checkpoint{Schema: 1, Herds: []savedHerd{{World: w, Secrets: map[string]string{a.PlayerID: hashToken(a.Token)}}}}, a
}

func writeCheckpointFixture(t *testing.T, dir string, cp checkpoint) []byte {
	t.Helper()
	data, err := json.Marshal(cp)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(dir, "herds.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	return data
}

func forageProgress(w *game.World) (assigned, remaining, satiated int) {
	for _, sheep := range w.Sheep {
		if sheep.Forage != nil {
			assigned++
			remaining += sheep.Forage.RemainingTicks
			if sheep.Forage.Satiated {
				satiated++
			}
		}
	}
	return
}

func TestOrchardForageProgressSurvivesRestartReconnectAndSatiation(t *testing.T) {
	dir := t.TempDir()
	cp, a := orchardCheckpoint(t)
	w := cp.Herds[0].World
	for i := 0; i < 1000; i++ {
		w.Step()
		assigned, remaining, _ := forageProgress(w)
		if assigned == 2 && remaining > 0 && remaining <= 30 {
			break
		}
	}
	assigned, before, _ := forageProgress(w)
	if assigned != 2 || before <= 0 || before > 30 {
		t.Fatal("fixture never reached partial nibbling progress")
	}
	writeCheckpointFixture(t, dir, cp)
	s, h := newTestServer(t, dir, 10)
	loaded := s.find(a.Code).state.Load()
	if !reflect.DeepEqual(loaded.World, w) || !reflect.DeepEqual(loaded.Secrets, cp.Herds[0].Secrets) {
		t.Fatal("restart changed saved forage progress or credentials")
	}
	pausedTick := loaded.World.Tick
	time.Sleep(80 * time.Millisecond)
	if s.find(a.Code).state.Load().World.Tick != pausedTick {
		t.Fatal("empty Orchard advanced its nibbling countdown")
	}
	version := 2
	first := connectVersion(t, h.URL, a, &version)
	firstWorld := snapshot(t, first, func(w *game.World) bool { return w.Player(a.PlayerID).Connected })
	_, firstRemaining, _ := forageProgress(firstWorld)
	if firstRemaining > before {
		t.Fatal("authentication reset partial nibbling")
	}
	reconnected := connectVersion(t, h.URL, a, &version)
	rejoined := snapshot(t, reconnected, func(w *game.World) bool { return w.Player(a.PlayerID).Connected })
	_, rejoinedRemaining, _ := forageProgress(rejoined)
	if rejoinedRemaining > firstRemaining {
		t.Fatal("replacement connection reset nibbling")
	}
	finished := snapshot(t, reconnected, func(w *game.World) bool {
		assigned, remaining, satiated := forageProgress(w)
		return assigned == 2 && remaining == 0 && satiated == 2
	})
	if err := finished.ValidateForage(); err != nil {
		t.Fatal(err)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	restored, restoredHTTP := newTestServer(t, dir, 10)
	assigned, remaining, satiated := forageProgress(restored.find(a.Code).state.Load().World)
	if assigned != 2 || remaining != 0 || satiated != 2 {
		t.Fatal("shutdown checkpoint lost completed satiation")
	}
	returned := connectVersion(t, restoredHTTP.URL, a, &version)
	snapshot(t, returned, func(w *game.World) bool {
		assigned, remaining, satiated := forageProgress(w)
		if assigned != 2 || remaining != 0 || satiated != 2 {
			t.Fatal("reconnecting a completed herd restarted the distraction")
		}
		return w.Tick >= finished.Tick+5
	})
}

func TestInvalidOrchardStateFailsWithoutOverwritingCheckpoint(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(*game.World)
	}{
		{"unknown_layout", func(w *game.World) { w.Layout.Version = 3 }},
		{"wrong_bridge", func(w *game.World) { w.Layout.BridgeY = -3 }},
		{"wrong_zone_id", func(w *game.World) { w.Layout.Forage.ID = "invented" }},
		{"wrong_zone_center", func(w *game.World) { w.Layout.Forage.Center.X = -8 }},
		{"wrong_zone_radius", func(w *game.World) { w.Layout.Forage.Radius = 100 }},
		{"missing_zone", func(w *game.World) { w.Layout.Forage = nil }},
		{"missing_layout", func(w *game.World) { w.Layout = nil }},
		{"unknown_progress_zone", func(w *game.World) { w.Sheep[0].Forage.ZoneID = "invented" }},
		{"negative_remaining", func(w *game.World) { w.Sheep[0].Forage.RemainingTicks = -1 }},
		{"excessive_remaining", func(w *game.World) { w.Sheep[0].Forage.RemainingTicks = game.ForageNibbleTicks + 1 }},
		{"satiated_with_remaining", func(w *game.World) { w.Sheep[0].Forage.Satiated = true }},
		{"empty_but_unsatiated", func(w *game.World) { w.Sheep[0].Forage.RemainingTicks = 0 }},
		{"active_satiated", func(w *game.World) {
			w.Sheep[0].Forage.RemainingTicks, w.Sheep[0].Forage.Satiated, w.Sheep[0].State = 0, true, "foraging"
		}},
		{"active_without_progress", func(w *game.World) { w.Sheep[0].Forage, w.Sheep[0].State = nil, "nibbling" }},
		{"active_outside_zone", func(w *game.World) { w.Sheep[0].Position, w.Sheep[0].State = game.Vec2{X: 10}, "foraging" }},
		{"nibbling_outside_windfall", func(w *game.World) { w.Sheep[0].State = "nibbling" }},
		{"third_assignment", func(w *game.World) {
			for i := 1; i < 3; i++ {
				w.Sheep[i].Forage = &game.SheepForage{ZoneID: "windfall", RemainingTicks: 50}
			}
		}},
		{"v1_with_forage", func(w *game.World) {
			w.Landscape, w.Layout = game.LandscapeAlpine, game.LayoutForLandscape(game.LandscapeAlpine)
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cp, _ := orchardCheckpoint(t)
			w := cp.Herds[0].World
			w.Sheep[0].Forage = &game.SheepForage{ZoneID: "windfall", RemainingTicks: 50}
			tc.mutate(w)
			dir := t.TempDir()
			before := writeCheckpointFixture(t, dir, cp)
			if s, err := New(Config{StateDir: dir}); err == nil {
				_ = s.Close()
				t.Fatal("invalid Orchard checkpoint accepted")
			}
			after, err := os.ReadFile(filepath.Join(dir, "herds.json"))
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(before, after) {
				t.Fatal("invalid checkpoint was overwritten instead of preserved")
			}
		})
	}
}
