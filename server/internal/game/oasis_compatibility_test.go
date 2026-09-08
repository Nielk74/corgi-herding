package game

import (
	"encoding/json"
	"strconv"
	"testing"
)

// This full trace was captured from the unchanged, independently compiled
// pre-Cloud simulator, and verified byte-identical to Cloud on each architecture.
// See testdata/README.md for exact source blobs and cross-architecture evidence.
func TestOasisPreCloudPortableTrace(t *testing.T) {
	baseline := loadCompressedTrace(t, "testdata/pre-cloud-oasis.jsonl.gz.b64", "de177e2df5f1201225169cfa89244a3e196f83fd837b04e776e546627f7fa2fe")
	w := herderWorld(t)
	w.Landscape, w.Layout = LandscapeOasis, LayoutForLandscape(LandscapeOasis)
	for tick := 0; tick < 700; tick++ {
		applyOasisTraceTick(w, tick)
		w.Step()
		// Shared narrow coordinate tolerance; all geometry, route anchors, state,
		// array order, ticks and sequence numbers remain exact and unrounded.
		if err := compareOrchardTrace(traceJSON(t, w.Clone()), baseline[tick], "$"); err != nil {
			t.Fatalf("pre-Cloud Oasis behavior changed at tick %d: %v", w.Tick, err)
		}
	}
}

func TestOasisTraceRejectsRouteAndGeometryChanges(t *testing.T) {
	baseline := loadCompressedTrace(t, "testdata/pre-cloud-oasis.jsonl.gz.b64", "de177e2df5f1201225169cfa89244a3e196f83fd837b04e776e546627f7fa2fe")[0]
	for _, mutation := range []string{"anchor_precision", "queue_removed", "ridge_added"} {
		t.Run(mutation, func(t *testing.T) {
			changed := traceJSON(t, baseline).(map[string]any)
			player := changed["players"].([]any)[0].(map[string]any)
			switch mutation {
			case "anchor_precision":
				anchor := player["route"].([]any)[0].(map[string]any)
				// Even below the actor-coordinate tolerance, anchor constants must
				// compare exactly because they are version-defined geometry.
				value, err := anchor["x"].(json.Number).Float64()
				if err != nil {
					t.Fatal(err)
				}
				anchor["x"] = json.Number(strconv.FormatFloat(value+1e-13, 'g', -1, 64))
			case "queue_removed":
				delete(player, "route")
			case "ridge_added":
				changed["layout"].(map[string]any)["ridge"] = nil
			}
			if err := compareOrchardTrace(changed, baseline, "$"); err == nil {
				t.Fatal("Oasis reference accepted changed route/geometry")
			}
		})
	}
}

func applyOasisTraceTick(w *World, tick int) {
	switch tick {
	case 0:
		_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{10, 0}})
		_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{9, 6}})
		_ = w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "go", Target: &Vec2{10, -5}})
		_ = w.Apply("b", Input{Type: "command", DogID: "maple", Command: "go", Target: &Vec2{10, 5}})
	case 130:
		_ = w.Apply("a", Input{Type: "move", Seq: 2, Target: &Vec2{-10, 0}})
		_ = w.Apply("b", Input{Type: "move", Seq: 2, Target: &Vec2{-9, -6}})
		_ = w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "come"})
		_ = w.Apply("b", Input{Type: "command", DogID: "maple", Command: "come"})
	case 300:
		_ = w.Apply("a", Input{Type: "move", Seq: 3, Target: &Vec2{11, 0}})
		_ = w.Apply("b", Input{Type: "move", Seq: 3, Target: &Vec2{11, 7}})
		_ = w.Apply("a", Input{Type: "command", DogID: "maple", Command: "go", Target: &Vec2{-10, 6}})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"})
	case 400:
		_ = w.Apply("a", Input{Type: "interact", Action: "sit"})
	case 450:
		_ = w.Apply("b", Input{Type: "move", Seq: 4, Target: &Vec2{-10, -4}})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "come"})
	case 600:
		_ = w.Apply("a", Input{Type: "move", Seq: 4, Target: &Vec2{-9, 7}})
		_ = w.Apply("a", Input{Type: "command", DogID: "maple", Command: "go", Target: &Vec2{10, -6}})
	}
}
