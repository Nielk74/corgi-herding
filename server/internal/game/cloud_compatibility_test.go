package game

import (
	"encoding/json"
	"strconv"
	"testing"
)

func applyCloudTraceTick(w *World, tick int) {
	move := func(id string, seq uint64, target Vec2) {
		_ = w.Apply(id, Input{Type: "move", Seq: seq, Target: &target})
	}
	goDog := func(id, dog string, target Vec2) {
		_ = w.Apply(id, Input{Type: "command", DogID: dog, Command: "go", Target: &target})
	}
	switch tick {
	case 0:
		move("a", 1, Vec2{11, 4})
		move("b", 1, Vec2{15, 6})
		goDog("a", "mochi", Vec2{11, 9})
		goDog("b", "maple", Vec2{15, 4})
	case 130:
		move("a", 2, Vec2{-10, 0})
		move("b", 2, Vec2{-10, 6})
		_ = w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "come"})
		_ = w.Apply("b", Input{Type: "command", DogID: "maple", Command: "come"})
	case 300:
		move("a", 3, Vec2{11, 4})
		move("b", 3, Vec2{11, 9})
		goDog("a", "maple", Vec2{-2, -9})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"})
	case 400:
		w.Player("a").Connected = false
	case 450:
		w.Player("a").Connected = true
		move("b", 4, Vec2{-16, 0})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "come"})
	case 550:
		_ = w.Apply("a", Input{Type: "interact", Action: "sit"})
	case 600:
		move("a", 4, Vec2{-10, 6})
		goDog("a", "maple", Vec2{11, 4})
	}
}

func TestCloudPreJuniperPortableTrace(t *testing.T) {
	baseline := loadCompressedTrace(t, "testdata/pre-juniper-cloud.jsonl.gz.b64", "b0f11dbe927632631266a844ba27de4bcedef88104fd49e4a37c35301cb82fb4")
	w := cloudWorld(t)
	for tick := 0; tick < 700; tick++ {
		applyCloudTraceTick(w, tick)
		w.Step()
		if err := compareOrchardTrace(traceJSON(t, w.Clone()), baseline[tick], "$"); err != nil {
			t.Fatalf("pre-Juniper Cloud changed at tick %d: %v", w.Tick, err)
		}
	}
}

func TestCloudReferenceRejectsChangedRoutesGeometryAndBehavior(t *testing.T) {
	baseline := loadCompressedTrace(t, "testdata/pre-juniper-cloud.jsonl.gz.b64", "b0f11dbe927632631266a844ba27de4bcedef88104fd49e4a37c35301cb82fb4")[0]
	for _, mutation := range []string{"anchor_precision", "removed_route", "ridge_width", "rest_radius", "unexpected_shore", "player_state", "connected", "sequence", "tick", "settled", "sheep_state", "coordinate"} {
		t.Run(mutation, func(t *testing.T) {
			changed := traceJSON(t, baseline).(map[string]any)
			player := changed["players"].([]any)[0].(map[string]any)
			ridge := changed["layout"].(map[string]any)["ridge"].(map[string]any)
			switch mutation {
			case "anchor_precision":
				p := player["route"].([]any)[0].(map[string]any)
				v, _ := p["x"].(json.Number).Float64()
				p["x"] = json.Number(strconv.FormatFloat(v+1e-13, 'g', -1, 64))
			case "removed_route":
				delete(player, "route")
			case "ridge_width":
				ridge["half_width"] = json.Number("3.6000000000001")
			case "rest_radius":
				ridge["rest"].(map[string]any)["radius"] = json.Number("4.6000000000001")
			case "unexpected_shore":
				changed["layout"].(map[string]any)["shore"] = nil
			case "player_state":
				player["state"] = "idle"
			case "connected":
				player["connected"] = false
			case "sequence":
				player["seq"] = json.Number("2")
			case "tick":
				changed["tick"] = json.Number("2")
			case "settled":
				changed["settled"] = json.Number("1")
			case "sheep_state":
				changed["sheep"].([]any)[0].(map[string]any)["state"] = "nibbling"
			case "coordinate":
				p := player["position"].(map[string]any)
				v, _ := p["x"].(json.Number).Float64()
				p["x"] = json.Number(strconv.FormatFloat(v+2e-12, 'g', -1, 64))
			}
			if err := compareOrchardTrace(changed, baseline, "$"); err == nil {
				t.Fatal("changed Cloud reference accepted")
			}
		})
	}
}
