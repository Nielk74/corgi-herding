package game

import (
	"crypto/sha256"
	"encoding/json"
	"strconv"
	"testing"
)

func applyDryWashLegacyTraceTick(t *testing.T, w *World, tick int) {
	t.Helper()
	var a []Vec2
	if w.Layout.Region != nil {
		a = w.Layout.Region.Anchors
	} else {
		a = w.Layout.Commons.Anchors
	}
	apply := func(id string, in Input) {
		if err := w.Apply(id, in); err != nil {
			t.Fatal(tick, err)
		}
	}
	move := func(id string, seq uint64, p Vec2) { apply(id, Input{Type: "move", Seq: seq, Target: &p}) }
	dog := func(id, name string, p Vec2) {
		apply(id, Input{Type: "command", DogID: name, Command: "go", Target: &p})
	}
	switch tick {
	case 0:
		move("a", 1, a[5])
		move("b", 1, a[3])
		dog("a", "mochi", a[4])
		dog("b", "maple", a[2])
	case 130:
		move("a", 2, a[0])
		move("b", 2, a[1])
		apply("a", Input{Type: "command", DogID: "mochi", Command: "come"})
		apply("b", Input{Type: "command", DogID: "maple", Command: "come"})
	case 300:
		move("a", 3, a[3])
		move("b", 3, a[5])
		dog("a", "maple", a[4])
		apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"})
	case 400:
		w.Player("a").Connected = false
	case 450:
		w.Player("a").Connected = true
		move("b", 4, a[0])
		apply("b", Input{Type: "command", DogID: "mochi", Command: "come"})
	case 550:
		apply("a", Input{Type: "interact", Action: "sit"})
	case 600:
		move("a", 4, a[1])
		dog("a", "maple", a[5])
	}
}

// Independent pre-change checkout 7f68be2, Go1.26.7 darwin/arm64. Tests never
// regenerate fixtures. Existing v1-v5 references remain untouched.
var preDryWashTraceChecksums = map[string]string{
	LandscapeBellflower:   "a4daab02c9c6d454d00d1b0f4b04a24bcf85d2b03acd9cf437962da6b3d22a86",
	LandscapeAlpineValley: "82427a0a94ae1417864630b80bf0fe3054096bcadd0bc597ed665cfda0825b92",
}

func TestPreDryWashBellflowerAndAlpineValleyPortableTraces(t *testing.T) {
	for landscape, checksum := range preDryWashTraceChecksums {
		t.Run(landscape, func(t *testing.T) {
			baseline := loadCompressedTraceLimit(t, "testdata/pre-drywash-"+landscape+".jsonl.gz.b64", checksum, 4<<20)
			w := NewForLandscape("ABCDEF", landscape)
			for _, id := range []string{"a", "b"} {
				if err := w.AddPlayer(id, id); err != nil {
					t.Fatal(err)
				}
				w.Player(id).Connected = true
			}
			digest := sha256.New()
			encoder := json.NewEncoder(digest)
			for tick := 0; tick < 700; tick++ {
				applyDryWashLegacyTraceTick(t, w, tick)
				w.Step()
				snapshot := w.Clone()
				if err := compareOrchardTrace(traceJSON(t, snapshot), baseline[tick], "$"); err != nil {
					t.Fatalf("pre-v8 %s changed tick%d: %v", landscape, w.Tick, err)
				}
				if err := encoder.Encode(snapshot); err != nil {
					t.Fatal(err)
				}
			}
			t.Logf("complete 700-snapshot JSONL sha256=%x", digest.Sum(nil))
		})
	}
}

func TestPreDryWashReferenceRejectsStateGeometryRoutesAndCoordinates(t *testing.T) {
	for landscape, checksum := range preDryWashTraceChecksums {
		baseline := loadCompressedTraceLimit(t, "testdata/pre-drywash-"+landscape+".jsonl.gz.b64", checksum, 4<<20)[0]
		for _, change := range []string{"route", "layout", "recipe", "width", "bounds", "identity", "sheep", "sequence", "connected", "state", "position", "target", "velocity"} {
			t.Run(landscape+"/"+change, func(t *testing.T) {
				changed := traceJSON(t, baseline).(map[string]any)
				player := changed["players"].([]any)[0].(map[string]any)
				layout := changed["layout"].(map[string]any)
				switch change {
				case "route":
					player["route"] = []any{map[string]any{"x": json.Number("0.0000000000001"), "y": json.Number("0")}}
				case "layout":
					layout["version"] = json.Number("8")
				case "recipe":
					layout["region"] = map[string]any{"recipe_id": "dry_wash_01"}
				case "width", "bounds":
					if region, ok := layout["region"].(map[string]any); ok {
						if change == "width" {
							region["corridors"].([]any)[0].(map[string]any)["half_width"] = json.Number("10.0000000000001")
						} else {
							region["bounds"].(map[string]any)["min"].(map[string]any)["x"] = json.Number("-72.0000000000001")
						}
					} else if change == "width" {
						layout["commons"].(map[string]any)["half_width"] = json.Number("3.6000000000001")
					} else {
						layout["commons"].(map[string]any)["bounds"] = nil
					}
				case "identity":
					player["id"] = "changed"
				case "sheep":
					changed["sheep"] = changed["sheep"].([]any)[:9]
				case "sequence":
					player["seq"] = json.Number("9007199254740993")
				case "connected":
					player["connected"] = false
				case "state":
					player["state"] = "idle"
				case "position", "target", "velocity":
					actor := player
					field := change
					if change == "velocity" {
						actor = changed["sheep"].([]any)[0].(map[string]any)
					}
					point := actor[field].(map[string]any)
					value, _ := point["x"].(json.Number).Float64()
					point["x"] = json.Number(strconv.FormatFloat(value+2e-12, 'g', -1, 64))
				}
				if err := compareOrchardTrace(changed, baseline, "$"); err == nil {
					t.Fatalf("accepted changed %s %s reference", landscape, change)
				}
			})
		}
	}
}
