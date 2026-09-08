package game

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
)

func TestShoreCanonicalSpawnsBoundariesAndCloning(t *testing.T) {
	w := shoreWorld(t)
	s := *w.Layout.Shore
	if err := w.ValidateLayout(); err != nil {
		t.Fatal(err)
	}
	if w.Layout.Version != 5 || w.Layout.BridgeY != 0 || w.Layout.GateY != 0 || w.Layout.Ridge != nil || w.Layout.RockPass != nil || w.Layout.Forage != nil || w.Settled != 0 {
		t.Fatal("Juniper inherited old geometry or a finish")
	}
	for _, cap := range []int{0, 1, 2, 3, 4, 6, 99, -1} {
		if w.SupportsLayout(cap) {
			t.Fatalf("accepted cap %d", cap)
		}
	}
	if !w.SupportsLayout(5) {
		t.Fatal("cap5 rejected")
	}
	for i, p := range w.Players {
		if p.Position != (Vec2{-14, float64(i) * 3}) || p.Target != p.Position {
			t.Fatal("wrong new herder spawn")
		}
	}
	for i, p := range []Vec2{{-12.2, -1}, {-12.2, 2}} {
		if w.Dogs[i].Position != p || w.Dogs[i].Target != p {
			t.Fatal("wrong new dog spawn")
		}
	}
	for i, sheep := range w.Sheep {
		if sheep.Position != (Vec2{-10.7 + float64(i%3), -.4 + float64(i/3)*1.05}) {
			t.Fatal("wrong new sheep spawn")
		}
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "pet", DogID: "mochi"}); err != nil {
		t.Fatal("spawn should permit quiet petting", err)
	}
	if err := w.Apply("b", Input{Type: "interact", Action: "pet", DogID: "maple"}); err != nil {
		t.Fatal("second herder cannot pet", err)
	}
	if !ShoreWalkable(Vec2{-16.2, 2}, s) || ShoreWalkable(Vec2{-16.200001, 2}, s) {
		t.Fatal("closed clearing boundary mismatch")
	}
	if !ShoreWalkable(Vec2{2, -2.400001}, s) || ShoreWalkable(Vec2{2, -2.399999}, s) {
		t.Fatal("capsule edge mismatch")
	}
	for _, p := range []Vec2{{0, 2}, {0, 8}, {-17.1, 2}, {11, 11}, {math.NaN(), 0}, {math.Inf(1), 0}} {
		if w.Walkable(p) || ShoreVisible(Vec2{-11, 2}, p, s) || ShoreVisible(p, Vec2{-11, 2}, s) || len(ShoreRoute(p, Vec2{-11, 2}, s)) != 0 {
			t.Fatalf("invalid endpoint %v accepted", p)
		}
	}
	if !w.Walkable(Vec2{-11, 2}) || !w.Walkable(Vec2{11, 4}) || ShoreVisible(Vec2{-11, 2}, Vec2{11, 4}, s) {
		t.Fatal("lake shortcut accepted")
	}
	for i := 1; i < len(s.Path); i++ {
		if !ShoreVisible(s.Path[i-1], s.Path[i], s) {
			t.Fatal("disconnected path")
		}
	}
	if !validShoreRoute(Vec2{-14, 0}, Vec2{12, 4}, s.Path, s) {
		t.Fatal("six safe canonical anchors should be accepted")
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err == nil {
		t.Fatal("phantom gate")
	}
	before := w.Clone()
	for _, in := range []Input{{Type: "move", Seq: 1, Target: &Vec2{0, 2}}, {Type: "command", DogID: "mochi", Command: "go", Target: &Vec2{0, 2}}} {
		if err := w.Apply("a", in); err == nil || !reflect.DeepEqual(w, before) {
			t.Fatal("invalid target mutated world")
		}
	}
	copy := w.Clone()
	copy.Layout.Shore.Path[0].X = 0
	copy.Layout.Shore.Clearings[0].Radius = 0
	if err := w.ValidateLayout(); err != nil {
		t.Fatal("clone altered canonical source")
	}
	if err := copy.ValidateLayout(); err == nil {
		t.Fatal("mutated canonical copy accepted")
	}
}

func TestShoreBothHerdersAndDogsRoundTripsAndStops(t *testing.T) {
	w := shoreWorld(t)
	for leg, target := range []Vec2{{11, 4}, {-11, 2}, {-1, -6}, {15.7, 4}, {-16.1, 2}, {11, 8.7}, {-3, -2.400001}, {4, -9.599999}, {-11, 2}} {
		for i, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(leg + 1), Target: &target}); err != nil {
				t.Fatal(err)
			}
			if err := w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[(i+leg)%2], Command: "go", Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		arrived := false
		for tick := 0; tick < 600; tick++ {
			stepShoreChecked(t, w)
			arrived = true
			for _, p := range w.Players {
				arrived = arrived && p.Position.Sub(target).Len() < .1
			}
			for _, d := range w.Dogs {
				arrived = arrived && d.Position.Sub(target).Len() < .16
			}
			if arrived {
				break
			}
		}
		if !arrived {
			t.Fatalf("shore leg %d stalled target %v players %+v dogs %+v", leg, target, w.Players, w.Dogs)
		}
	}
	target := Vec2{11, 4}
	_ = w.Apply("a", Input{Type: "move", Seq: 20, Target: &target})
	_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target})
	if len(w.Players[0].Route) == 0 {
		t.Fatal("missing retained route fixture")
	}
	for tick := 0; tick < 20; tick++ {
		p, d := append([]Vec2(nil), w.Players[0].Route...), append([]Vec2(nil), w.Dogs[0].Route...)
		_ = w.Apply("a", Input{Type: "move", Seq: uint64(21 + tick), Target: &target})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target})
		if !reflect.DeepEqual(p, w.Players[0].Route) || !reflect.DeepEqual(d, w.Dogs[0].Route) {
			t.Fatal("same-target route replanned")
		}
		stepShoreChecked(t, w)
	}
	_ = w.Apply("a", Input{Type: "interact", Action: "sit"})
	_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"})
	p, d := w.Players[0].Position, w.Dogs[0].Position
	for tick := 0; tick < 20; tick++ {
		stepShoreChecked(t, w)
	}
	if p != w.Players[0].Position || d != w.Dogs[0].Position || len(w.Players[0].Route) > 0 || len(w.Dogs[0].Route) > 0 {
		t.Fatal("stop failed")
	}
	for i, target := range []Vec2{{11, 4}, {-11, 2}, {4, -9}, {11, 4}} {
		_ = w.Apply("a", Input{Type: "move", Seq: uint64(100 + i), Target: &target})
		_ = w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "come"})
		_ = w.Apply("a", Input{Type: "command", DogID: "maple", Command: "come"})
		for tick := 0; tick < 400; tick++ {
			stepShoreChecked(t, w)
		}
		for _, dog := range w.Dogs {
			if dog.Position.Sub(w.Players[0].Position).Len() > 1.2 {
				t.Fatal("Come lost moving caller")
			}
		}
	}
}

func TestShoreEveryGridPairHasSafeBoundedRoute(t *testing.T) {
	w := shoreWorld(t)
	s := *w.Layout.Shore
	var points []Vec2
	for x := -16.0; x <= 16; x += 2 {
		for y := -10.0; y <= 10; y += 2 {
			if ShoreWalkable(Vec2{x, y}, s) {
				points = append(points, Vec2{x, y})
			}
		}
	}
	for i, from := range points {
		for j, target := range points {
			if i == j {
				continue
			}
			p := from
			route := ShoreRoute(from, target, s)
			if !validShoreRoute(from, target, route, s) {
				t.Fatalf("unsafe planned route %v->%v %v", from, target, route)
			}
			for tick := 0; tick < 500 && p.Sub(target).Len() > .08; tick++ {
				before := p
				p = w.moveOnShore(p, target, 4, &route)
				if !ShoreVisible(before, p, s) || p.Sub(before).Len() > 4.0/TickRate+1e-8 {
					t.Fatal("unsafe movement")
				}
			}
			if p.Sub(target).Len() > .08 {
				t.Fatalf("shore route stalled %v->%v at %v route %v", from, target, p, route)
			}
		}
	}
	t.Logf("validated %d ordered Juniper grid routes", len(points)*(len(points)-1))
}

func TestShoreClearingsStayQuietWithoutAttractionOrObjective(t *testing.T) {
	for _, clearing := range canonicalShore().Clearings {
		w := shoreWorld(t)
		r := w.Layout.Shore.corridor()
		if v := cloudSheepSteering(clearing.Center, Vec2{}, 0, r); v != (Vec2{}) {
			t.Fatal("clearing attraction")
		}
		away := Vec2{11, 4}
		if clearing.Center == away {
			away = Vec2{-11, 2}
		}
		for i := range w.Dogs {
			w.Dogs[i].Position, w.Dogs[i].Target, w.Dogs[i].Command = away, away, "stay"
		}
		for i := range w.Players {
			w.Players[i].Position, w.Players[i].Target = away, away
		}
		for i := range w.Sheep {
			w.Sheep[i].Position, w.Sheep[i].Velocity = clearing.Center, Vec2{}
		}
		stepShoreChecked(t, w)
		for _, sheep := range w.Sheep {
			if sheep.State != "grazing" || sheep.Velocity.Len() > .1 {
				t.Fatal("clearing does not permit rest")
			}
		}
		if w.Settled != 0 {
			t.Fatal("Juniper became a completion objective")
		}
	}
}

func TestShorePredictionFixtures(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/shore-routes.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Name    string `json:"name"`
		From    Vec2   `json:"from"`
		Target  Vec2   `json:"target"`
		Visible bool   `json:"visible"`
		Route   []int  `json:"route"`
	}
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 32 {
		t.Fatalf("want32 fixtures, got%d", len(fixtures))
	}
	s := *canonicalShore()
	for _, f := range fixtures {
		if ShoreVisible(f.From, f.Target, s) != f.Visible {
			t.Fatalf("%s visibility", f.Name)
		}
		actual := ShoreRoute(f.From, f.Target, s)
		if len(actual) != len(f.Route) {
			t.Fatalf("%s route %v expected %v", f.Name, actual, f.Route)
		}
		for i, index := range f.Route {
			if actual[i] != s.Path[index] {
				t.Fatalf("%s anchor%d", f.Name, i)
			}
		}
	}
}
