package game

import (
	"math"
	"testing"
)

func orchardWorld(t *testing.T) *World {
	t.Helper()
	w := herderWorld(t)
	w.Landscape = LandscapeOrchard
	w.Layout = LayoutForLandscape(LandscapeOrchard)
	return w
}

func quietOrchard(t *testing.T) *World {
	t.Helper()
	w := orchardWorld(t)
	for i := range w.Dogs {
		w.Dogs[i].Position = Vec2{-16, float64(i*18 - 9)}
		w.Dogs[i].Target = w.Dogs[i].Position
		w.Dogs[i].Command = "stay"
	}
	return w
}

func TestWindfallIsTwoSheepOneBriefPersistentDistraction(t *testing.T) {
	w := quietOrchard(t)
	sawApproach, sawNibble := false, false
	for tick := 0; tick < 1000; tick++ {
		w.Step()
		assertWalkableWorld(t, w)
		assigned, active := 0, 0
		for _, s := range w.Sheep {
			if s.Forage != nil {
				assigned++
			}
			if s.State == "foraging" {
				sawApproach = true
				active++
			}
			if s.State == "nibbling" {
				sawNibble = true
				active++
			}
			if s.Forage != nil && s.Forage.Satiated && (s.Forage.RemainingTicks != 0 || s.State == "nibbling" || s.State == "foraging") {
				t.Fatal("satiated sheep returned for more food")
			}
		}
		if assigned > 2 || active > 2 {
			t.Fatal("windfall attracted more than two sheep")
		}
		if err := w.ValidateForage(); err != nil {
			t.Fatal(err)
		}
	}
	satiated := 0
	for _, s := range w.Sheep {
		if s.Forage != nil && s.Forage.Satiated {
			satiated++
		}
	}
	if !sawApproach || !sawNibble || satiated != 2 {
		t.Fatalf("expected approach, brief nibble and two permanently satisfied sheep: approach=%t nibble=%t satiated=%d", sawApproach, sawNibble, satiated)
	}
}

func TestDogPressureCancelsNibblingWithoutResettingProgress(t *testing.T) {
	w := quietOrchard(t)
	selected := -1
	for tick := 0; tick < 500; tick++ {
		w.Step()
		for i, s := range w.Sheep {
			if s.State == "nibbling" && s.Forage.RemainingTicks < ForageNibbleTicks-8 {
				selected = i
				break
			}
		}
		if selected >= 0 {
			break
		}
	}
	if selected < 0 {
		t.Fatal("test sheep never started nibbling")
	}
	sheep := &w.Sheep[selected]
	remaining := sheep.Forage.RemainingTicks
	w.Dogs[0].Position = sheep.Position.Add(Vec2{-1, 0})
	before := sheep.Position
	w.Step()
	if sheep.State == "nibbling" || sheep.State == "foraging" || sheep.Forage.RemainingTicks != remaining {
		t.Fatal("dog pressure failed to immediately stop feeding and retain progress")
	}
	if sheep.Position.X <= before.X {
		t.Fatal("feeding suppressed dog-avoidance movement")
	}
	w.Dogs[0].Position = Vec2{-16, -9}
	for tick := 0; tick < 600; tick++ {
		w.Step()
	}
	if !sheep.Forage.Satiated || sheep.Forage.RemainingTicks != 0 {
		t.Fatal("interrupted nibble never resumed and finished")
	}
	copy := w.Clone()
	copy.Sheep[selected].Forage.Satiated = false
	copy.Layout.Forage.Center.X = 0
	if !w.Sheep[selected].Forage.Satiated || w.Layout.Forage.Center.X != -7 {
		t.Fatal("mutable forage state leaked through a snapshot clone")
	}
}

func TestOrchardForageDoesNotPreventRetrievalAndPasture(t *testing.T) {
	w := orchardWorld(t)
	for i, id := range []string{"mochi", "maple"} {
		target := Vec2{-15, float64(i*18 - 9)}
		if err := w.Apply([]string{"a", "b"}[i], Input{Type: "command", DogID: id, Command: "go", Target: &target}); err != nil {
			t.Fatal(err)
		}
	}
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{-14, -3}})
	_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-14, 3}})
	sawNibble := false
	for tick := 0; tick < 1200 && !sawNibble; tick++ {
		w.Step()
		assertWalkableWorld(t, w)
		for _, s := range w.Sheep {
			sawNibble = sawNibble || s.State == "nibbling"
		}
	}
	if !sawNibble {
		t.Fatal("normal-spawn retrieval fixture never reached the actual windfall")
	}
	gate := Vec2{5.4, w.Layout.GateY}
	_ = w.Apply("a", Input{Type: "move", Seq: 2, Target: &gate})
	for tick := 0; tick < 260; tick++ {
		w.Step()
		assertWalkableWorld(t, w)
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err != nil {
		t.Fatal(err)
	}
	_ = w.Apply("a", Input{Type: "move", Seq: 3, Target: &Vec2{15, -8}})
	_ = w.Apply("b", Input{Type: "move", Seq: 2, Target: &Vec2{-16, 9}})
	for tick := 0; tick < 6000; tick++ {
		if tick%10 == 0 {
			back, centerY := 17.0, 0.0
			for _, s := range w.Sheep {
				back = math.Min(back, s.Position.X)
				centerY += s.Position.Y / 10
			}
			for i, id := range []string{"mochi", "maple"} {
				target := Vec2{math.Max(-16, back-2), math.Max(-10, math.Min(10, centerY+float64(i*2-1)*1.2))}
				if back > 1.8 {
					target.X = math.Max(2, target.X)
				}
				if math.Abs(target.X) < 1.5 {
					target.Y = w.Layout.BridgeY
				}
				if math.Abs(target.X-6) < .18 {
					target.Y = w.Layout.GateY
				}
				if err := w.Apply([]string{"a", "b"}[i], Input{Type: "command", DogID: id, Command: "go", Target: &target}); err != nil {
					t.Fatal(err)
				}
			}
		}
		previous := w.Clone()
		w.Step()
		assertWalkableWorld(t, w)
		for i, s := range w.Sheep {
			if s.Position.Sub(previous.Sheep[i].Position).Len() > 2.6/TickRate+1e-8 {
				t.Fatal("sheep teleported")
			}
		}
		for i, d := range w.Dogs {
			if d.Position.Sub(previous.Dogs[i].Position).Len() > 4.6/TickRate+1e-8 {
				t.Fatal("dog teleported")
			}
		}
		if w.Settled == 10 {
			t.Logf("all ten Orchard sheep reached pasture at tick %d", w.Tick)
			return
		}
	}
	t.Fatalf("Orchard sheep did not reach pasture: %+v", w.Sheep)
}

func TestOrchardCanonicalLayoutAndCapability(t *testing.T) {
	w := orchardWorld(t)
	if err := w.ValidateLayout(); err != nil {
		t.Fatal(err)
	}
	if w.Layout.Version != 2 || w.Layout.BridgeY != 3 || w.Layout.GateY != 2 || w.Layout.Forage.ID != "windfall" {
		t.Fatal("wrong Orchard geometry")
	}
	if w.SupportsLayout(0) || w.SupportsLayout(1) || !w.SupportsLayout(2) || !w.SupportsLayout(3) || !w.SupportsLayout(4) || !w.SupportsLayout(5) || !w.SupportsLayout(6) || w.SupportsLayout(7) {
		t.Fatal("incorrect Orchard capability support")
	}
	if !w.Walkable(Vec2{0, 3}) || w.Walkable(Vec2{0, 0}) {
		t.Fatal("incorrect Orchard bridge")
	}
	w.GateOpen = true
	if !w.Walkable(Vec2{6, 2}) || w.Walkable(Vec2{6, -2}) {
		t.Fatal("incorrect Orchard gate")
	}
}
