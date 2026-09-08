package game

import (
	"encoding/json"
	"strconv"
	"testing"
)

func applyJuniperTraceTick(t *testing.T, w *World, tick int) {
	apply := func(id string, input Input) {
		if err := w.Apply(id, input); err != nil {
			t.Fatal(tick, err)
		}
	}
	move := func(id string, seq uint64, target Vec2) { apply(id, Input{Type: "move", Seq: seq, Target: &target}) }
	goDog := func(id, dog string, target Vec2) {
		apply(id, Input{Type: "command", DogID: dog, Command: "go", Target: &target})
	}
	switch tick {
	case 0:
		move("a", 1, Vec2{11, 4})
		move("b", 1, Vec2{13, 6})
		goDog("a", "mochi", Vec2{11, 7})
		goDog("b", "maple", Vec2{14, 4})
	case 130:
		move("a", 2, Vec2{-11, 2})
		move("b", 2, Vec2{-14, 4})
		apply("a", Input{Type: "command", DogID: "mochi", Command: "come"})
		apply("b", Input{Type: "command", DogID: "maple", Command: "come"})
	case 300:
		move("a", 3, Vec2{13, 5})
		move("b", 3, Vec2{11, 7})
		goDog("a", "maple", Vec2{-3, -7})
		apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"})
	case 400:
		w.Player("a").Connected = false
	case 450:
		w.Player("a").Connected = true
		move("b", 4, Vec2{-15, 2})
		apply("b", Input{Type: "command", DogID: "mochi", Command: "come"})
	case 550:
		apply("a", Input{Type: "interact", Action: "sit"})
	case 600:
		move("a", 4, Vec2{-14, 4})
		goDog("a", "maple", Vec2{11, 4})
	}
}

func TestJuniperBuild13PortableTrace(t *testing.T) {
	baseline := loadCompressedTrace(t, "testdata/pre-bellflower-juniper.jsonl.gz.b64", "980eeb37864063cdc521985a974b9b8507596b0d16eb37744870dccc429e863d")
	w := shoreWorld(t)
	for tick := 0; tick < 700; tick++ {
		applyJuniperTraceTick(t, w, tick)
		w.Step()
		if err := compareOrchardTrace(traceJSON(t, w.Clone()), baseline[tick], "$"); err != nil {
			t.Fatalf("released Juniper changed tick%d: %v", w.Tick, err)
		}
	}
}
func TestJuniperReferenceRejectsBehaviorGeometryAndRouteChanges(t *testing.T) {
	baseline := loadCompressedTrace(t, "testdata/pre-bellflower-juniper.jsonl.gz.b64", "980eeb37864063cdc521985a974b9b8507596b0d16eb37744870dccc429e863d")[0]
	for _, mutation := range []string{"anchor_precision", "queue_removed", "width", "clearing", "unexpected_commons", "state", "connected", "sequence", "tick", "settled", "sheep", "coordinate"} {
		t.Run(mutation, func(t *testing.T) {
			changed := traceJSON(t, baseline).(map[string]any)
			p := changed["players"].([]any)[0].(map[string]any)
			layout := changed["layout"].(map[string]any)
			shore := layout["shore"].(map[string]any)
			switch mutation {
			case "anchor_precision":
				a := p["route"].([]any)[0].(map[string]any)
				v, _ := a["x"].(json.Number).Float64()
				a["x"] = json.Number(strconv.FormatFloat(v+1e-13, 'g', -1, 64))
			case "queue_removed":
				delete(p, "route")
			case "width":
				shore["half_width"] = json.Number("3.6000000000001")
			case "clearing":
				shore["clearings"].([]any)[0].(map[string]any)["radius"] = json.Number("5.2000000000001")
			case "unexpected_commons":
				layout["commons"] = nil
			case "state":
				p["state"] = "idle"
			case "connected":
				p["connected"] = false
			case "sequence":
				p["seq"] = json.Number("2")
			case "tick":
				changed["tick"] = json.Number("2")
			case "settled":
				changed["settled"] = json.Number("1")
			case "sheep":
				changed["sheep"].([]any)[0].(map[string]any)["state"] = "nibbling"
			case "coordinate":
				pos := p["position"].(map[string]any)
				v, _ := pos["x"].(json.Number).Float64()
				pos["x"] = json.Number(strconv.FormatFloat(v+2e-12, 'g', -1, 64))
			}
			if err := compareOrchardTrace(changed, baseline, "$"); err == nil {
				t.Fatal("changed Juniper reference accepted")
			}
		})
	}
}
