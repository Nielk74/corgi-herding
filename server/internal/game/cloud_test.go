package game

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
)

func cloudWorld(t *testing.T) *World {
	t.Helper()
	w := herderWorld(t)
	w.Landscape, w.Layout = LandscapeCloud, LayoutForLandscape(LandscapeCloud)
	return w
}

func stepCloudChecked(t *testing.T, w *World) {
	t.Helper()
	before := w.Clone()
	w.Step()
	if err := w.ValidateNavigation(); err != nil {
		t.Fatalf("tick%d invalid Cloud navigation: %v players=%+v dogs=%+v", w.Tick, err, w.Players, w.Dogs)
	}
	check := func(a, b Vec2, speed float64) {
		if b.Sub(a).Len() > speed/TickRate+1e-8 {
			t.Fatal("Cloud speed/teleport violation")
		}
		if !CloudVisible(a, b, *w.Layout.Ridge) {
			t.Fatalf("Cloud actor crossed void: %v -> %v", a, b)
		}
	}
	for i, p := range w.Players {
		check(before.Players[i].Position, p.Position, 4)
	}
	for i, d := range w.Dogs {
		check(before.Dogs[i].Position, d.Position, 4.6)
	}
	for i, s := range w.Sheep {
		check(before.Sheep[i].Position, s.Position, 2.6)
	}
}

func TestCloudCanonicalGeometryAndAnalyticVoidRejection(t *testing.T) {
	w := cloudWorld(t)
	r := *w.Layout.Ridge
	if err := w.ValidateLayout(); err != nil {
		t.Fatal(err)
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(err)
	}
	if w.SupportsLayout(3) || !w.SupportsLayout(4) || w.SupportsLayout(5) || w.SupportsLayout(99) {
		t.Fatal("Cloud capability mismatch")
	}
	from, to := Vec2{-10, 6}, Vec2{11, 9}
	if !w.Walkable(from) || !w.Walkable(to) || CloudVisible(from, to, r) {
		t.Fatal("endpoint-only test missed a chord across void")
	}
	if !CloudVisible(Vec2{-16.19, 0}, Vec2{-3.81, 0}, r) {
		t.Fatal("closed starting shelf chord rejected")
	}
	if w.Walkable(Vec2{-10, 6.21}) || w.Walkable(Vec2{0, 8}) || w.Walkable(Vec2{17, 11}) {
		t.Fatal("void is traversable")
	}
	for i := 1; i < len(r.Spine); i++ {
		if !CloudVisible(r.Spine[i-1], r.Spine[i], r) {
			t.Fatal("spine capsule is disconnected")
		}
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err == nil {
		t.Fatal("Cloud acquired phantom gate")
	}
	copy := w.Clone()
	copy.Layout.Ridge.Spine[0].X = 0
	copy.Layout.Ridge.Shelves[0].Radius = 0
	if err := w.ValidateLayout(); err != nil {
		t.Fatal("mutable ridge escaped its clone")
	}
}

func TestCloudBothHerdersAndDogsRoundTrips(t *testing.T) {
	w := cloudWorld(t)
	for leg, target := range []Vec2{{11, 4}, {-10, 0}, {-2, -5}, {15, 6}, {-10, 6}, {11, 9}, {-16, 0}, {-2, -9.7}, {5, 1}, {-10, 0}} {
		for i, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(leg + 1), Target: &target}); err != nil {
				t.Fatal(err)
			}
			if err := w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[(i+leg)%2], Command: "go", Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		arrived := false
		for tick := 0; tick < 550; tick++ {
			stepCloudChecked(t, w)
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
			t.Fatalf("Cloud leg%d target%v stalled players=%+v dogs=%+v", leg, target, w.Players, w.Dogs)
		}
	}
}

func TestCloudEveryPointHasSafeBoundedAnchorRoute(t *testing.T) {
	w := cloudWorld(t)
	r := *w.Layout.Ridge
	var points []Vec2
	for x := -16.0; x <= 16; x += 2 {
		for y := -10.0; y <= 10; y += 2 {
			p := Vec2{x, y}
			if CloudWalkable(p, r) {
				points = append(points, p)
			}
		}
	}
	for i, from := range points {
		for j, target := range points {
			if i == j {
				continue
			}
			p := from
			var route []Vec2
			for tick := 0; tick < 450 && p.Sub(target).Len() > .08; tick++ {
				before := p
				p = w.moveOnRidge(p, target, 4, &route)
				if !CloudVisible(before, p, r) || p.Sub(before).Len() > 4.0/TickRate+1e-8 {
					t.Fatal("unsafe Cloud route step")
				}
			}
			if p.Sub(target).Len() > .08 {
				t.Fatalf("Cloud route stalled %v->%v at%v queue%v", from, target, p, route)
			}
		}
	}
	t.Logf("validated %d ordered Cloud grid routes", len(points)*(len(points)-1))
}

func TestCloudRetainedRoutesAndChangedCommands(t *testing.T) {
	w := cloudWorld(t)
	target := Vec2{11, 4}
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &target})
	_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target})
	if len(w.Players[0].Route) == 0 {
		t.Fatal("fixture lacks retained anchors")
	}
	for tick := 0; tick < 30; tick++ {
		p, d := append([]Vec2(nil), w.Players[0].Route...), append([]Vec2(nil), w.Dogs[0].Route...)
		_ = w.Apply("a", Input{Type: "move", Seq: uint64(tick + 2), Target: &target})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target})
		if !reflect.DeepEqual(p, w.Players[0].Route) || !reflect.DeepEqual(d, w.Dogs[0].Route) {
			t.Fatal("duplicate Cloud target replanned")
		}
		stepCloudChecked(t, w)
	}
	_ = w.Apply("a", Input{Type: "interact", Action: "sit"})
	_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"})
	p, d := w.Players[0].Position, w.Dogs[0].Position
	for i := 0; i < 10; i++ {
		stepCloudChecked(t, w)
	}
	if w.Players[0].Position != p || w.Dogs[0].Position != d || len(w.Players[0].Route) > 0 || len(w.Dogs[0].Route) > 0 {
		t.Fatal("Cloud stop did not cancel movement")
	}
	for i, target := range []Vec2{{15, 4}, {-10, 5}, {-2, -9}, {11, 4}} {
		_ = w.Apply("a", Input{Type: "move", Seq: uint64(i + 100), Target: &target})
		_ = w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "come"})
		for tick := 0; tick < 220; tick++ {
			stepCloudChecked(t, w)
		}
	}
}

func TestCloudRestIsOnlyAQuietCounterAndAnyShelfCalms(t *testing.T) {
	w := cloudWorld(t)
	r := *w.Layout.Ridge
	for _, s := range r.Shelves {
		if !ridgeShelf(s.Center, r) {
			t.Fatal("missing quiet shelf")
		}
		if v := cloudSheepSteering(s.Center, Vec2{}, 0, r); v != (Vec2{}) {
			t.Fatal("rest area introduced automatic attraction")
		}
		quiet := cloudWorld(t)
		away := Vec2{11, 4}
		if s.Center == away {
			away = Vec2{-10, 0}
		}
		for i := range quiet.Dogs {
			quiet.Dogs[i].Position, quiet.Dogs[i].Target, quiet.Dogs[i].Command = away, away, "stay"
		}
		for i := range quiet.Players {
			quiet.Players[i].Position, quiet.Players[i].Target = away, away
		}
		for i := range quiet.Sheep {
			quiet.Sheep[i].Position, quiet.Sheep[i].Velocity = s.Center, Vec2{}
		}
		stepCloudChecked(t, quiet)
		for _, sheep := range quiet.Sheep {
			if sheep.State != "grazing" || sheep.Velocity.Len() > .1 {
				t.Fatal("a calm shelf does not let the flock rest")
			}
		}
		wantSettled := 0
		if s.Center == r.Rest.Center {
			wantSettled = 10
		}
		if quiet.Settled != wantSettled {
			t.Fatal("internal rest counter confused with all calm shelves")
		}
	}
	if inShelf(Vec2{-10, 0}, r.Rest) || !inShelf(Vec2{11, 4}, r.Rest) {
		t.Fatal("rest count covers wrong shelf")
	}
	// Predicate boundary is closed; geometry scalars are authoritative, not UI stats.
	if !inShelf(Vec2{11, 8.6}, r.Rest) || inShelf(Vec2{11, 8.61}, r.Rest) {
		t.Fatal("rest radius mismatch")
	}
	if math.Abs(r.HalfWidth-3.6) > 0 {
		t.Fatal("ridge width changed")
	}
}

func TestCloudPredictionFixtures(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/cloud-routes.json")
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
	r := *canonicalRidge()
	for _, f := range fixtures {
		if CloudVisible(f.From, f.Target, r) != f.Visible {
			t.Fatalf("%s visibility mismatch", f.Name)
		}
		actual := CloudRoute(f.From, f.Target, r)
		if len(actual) != len(f.Route) {
			t.Fatalf("%s got route%v wantindices%v", f.Name, actual, f.Route)
		}
		for i, index := range f.Route {
			if actual[i] != r.Spine[index] {
				t.Fatalf("%s anchor%d mismatch", f.Name, i)
			}
		}
	}
}
