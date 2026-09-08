package game

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
)

func oasisWorld(t *testing.T) *World {
	t.Helper()
	w := herderWorld(t)
	w.Landscape, w.Layout = LandscapeOasis, LayoutForLandscape(LandscapeOasis)
	return w
}

func stepOasisChecked(t *testing.T, w *World) {
	t.Helper()
	previous := w.Clone()
	w.Step()
	assertWalkableWorld(t, w)
	if err := w.ValidateNavigation(); err != nil {
		t.Fatalf("tick%d: %v world=%+v dogs=%+v players=%+v", w.Tick, err, w, w.Dogs, w.Players)
	}
	check := func(before, after Vec2, speed float64) {
		if after.Sub(before).Len() > speed/TickRate+1e-8 {
			t.Fatal("Oasis actor exceeded speed or teleported")
		}
		if !RockVisible(before, after, *w.Layout.RockPass) {
			t.Fatalf("Oasis actor cut through rock: %v -> %v", before, after)
		}
	}
	for i, p := range w.Players {
		check(previous.Players[i].Position, p.Position, 4)
	}
	for i, d := range w.Dogs {
		check(previous.Dogs[i].Position, d.Position, 4.6)
	}
	for i, s := range w.Sheep {
		check(previous.Sheep[i].Position, s.Position, 2.6)
	}
}

func TestOasisBothRoutesBothDirectionsAndSharedDogs(t *testing.T) {
	for _, sign := range []float64{-1, 1} {
		w := oasisWorld(t)
		for leg, target := range []Vec2{{-8, sign}, {11, sign}, {-10, sign}, {0, sign * 3.41}, {-9, -sign * 4}} {
			for i, id := range []string{"a", "b"} {
				if err := w.Apply(id, Input{Type: "move", Seq: uint64(leg + 1), Target: &target}); err != nil {
					t.Fatal(err)
				}
				if err := w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[(i+leg)%2], Command: "go", Target: &target}); err != nil {
					t.Fatal(err)
				}
			}
			passedSide := false
			arrived := false
			for tick := 0; tick < 500; tick++ {
				stepOasisChecked(t, w)
				passedSide = passedSide || w.Players[0].Position.Y*sign > 3.4
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
				t.Fatalf("route sign%g leg%d stuck: players=%+v dogs=%+v", sign, leg, w.Players, w.Dogs)
			}
			if (leg == 1 || leg == 2) && !passedSide {
				t.Fatalf("did not use selected bypass sign%g leg%d", sign, leg)
			}
		}
		if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err == nil || w.GateOpen {
			t.Fatal("Oasis acquired a phantom gate")
		}
		if !w.Walkable(Vec2{6, 8}) || !w.Walkable(Vec2{0, 8}) || w.Walkable(Vec2{3.3, 0}) {
			t.Fatal("Oasis retained old river/fence or omitted rock")
		}
	}
}

func TestRockRoutesNearBoundaryAndAroundRing(t *testing.T) {
	w := oasisWorld(t)
	for i := 0; i < 24; i++ {
		angle := float64(i) * math.Pi / 12
		for j := 0; j < 24; j++ {
			a := float64(j) * math.Pi / 12
			p := Vec2{math.Cos(angle) * 3.401, math.Sin(angle) * 3.401}
			target := Vec2{math.Cos(a) * 8, math.Sin(a) * 8}
			var route []Vec2
			for tick := 0; tick < 300 && p.Sub(target).Len() > .08; tick++ {
				before := p
				p = w.moveWithRoute(p, target, 4, &route)
				if !w.Walkable(p) || !RockVisible(before, p, *w.Layout.RockPass) || p.Sub(before).Len() > 4.0/TickRate+1e-8 {
					t.Fatal("unsafe near-boundary route")
				}
			}
			if p.Sub(target).Len() > .08 {
				t.Fatalf("boundary route stalled from angle%d toward%d at%v route%v", i, j, p, route)
			}
		}
	}
}

func TestRepeatedRockTargetsRetainRouteAndChangesRemainSafe(t *testing.T) {
	w := oasisWorld(t)
	target := Vec2{10, 0}
	if err := w.Apply("a", Input{Type: "move", Seq: 1, Target: &target}); err != nil {
		t.Fatal(err)
	}
	if err := w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target}); err != nil {
		t.Fatal(err)
	}
	for tick := 0; tick < 50; tick++ {
		pRoute := append([]Vec2(nil), w.Players[0].Route...)
		dRoute := append([]Vec2(nil), w.Dogs[0].Route...)
		_ = w.Apply("a", Input{Type: "move", Seq: uint64(tick + 2), Target: &target})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target})
		if !reflect.DeepEqual(pRoute, w.Players[0].Route) || !reflect.DeepEqual(dRoute, w.Dogs[0].Route) {
			t.Fatal("duplicate target replanned its chosen bypass")
		}
		stepOasisChecked(t, w)
	}
	copy := w.Clone()
	if len(copy.Players[0].Route) > 0 {
		copy.Players[0].Route[0].X = 99
	}
	copy.Layout.RockPass.Radius = 0
	if err := w.ValidateNavigation(); err != nil || w.Layout.RockPass.Radius != 3.4 {
		t.Fatal("mutable route/rock aliased snapshot")
	}
	for seq, target := range []Vec2{{-8, 7}, {7, 7}, {-8, -7}, {7, -7}} {
		_ = w.Apply("a", Input{Type: "move", Seq: uint64(seq + 100), Target: &target})
		_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "come"})
		for tick := 0; tick < 150; tick++ {
			stepOasisChecked(t, w)
		}
	}
}

func TestRockPredictionFixtures(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/rock-routes.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Name   string `json:"name"`
		From   Vec2   `json:"from"`
		Target Vec2   `json:"target"`
		Route  []int  `json:"route"`
	}
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	for _, fixture := range fixtures {
		actual := RockRoute(fixture.From, fixture.Target, *LayoutForLandscape(LandscapeOasis).RockPass)
		if len(actual) != len(fixture.Route) {
			t.Fatalf("%s route=%v expected indices=%v", fixture.Name, actual, fixture.Route)
		}
		for i, index := range fixture.Route {
			if actual[i] != rockAnchors[index] {
				t.Fatalf("%s anchor%d got%v expected%v", fixture.Name, i, actual[i], rockAnchors[index])
			}
		}
	}
}

func TestRockSheepSteeringFollowsPressureRatherThanPasture(t *testing.T) {
	rock := *LayoutForLandscape(LandscapeOasis).RockPass
	if got := rockSheepSteering(Vec2{3.5, 0}, Vec2{}, 1, rock); got != (Vec2{}) {
		t.Fatal("rock introduced autonomous pasture attraction")
	}
	for _, direction := range []float64{-1, 1} {
		p := Vec2{-direction * 3.6, 0}
		for _, side := range []float64{-1, 1} {
			v := rockSheepSteering(p, Vec2{direction * .8, side * .2}, 1, rock)
			if v.Y*side <= 0 {
				t.Fatalf("pressure side%g not retained: %v", side, v)
			}
			if dot(v, p.Unit()) < -.25 {
				t.Fatalf("inward pressure was not redirected around rock: %v", v)
			}
		}
	}
}
