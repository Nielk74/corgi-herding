package game

import (
	"math"
	"testing"
)

func herderWorld(t *testing.T) *World {
	t.Helper()
	w := New("ABCDEF")
	if err := w.AddPlayer("a", "A"); err != nil {
		t.Fatal(err)
	}
	if err := w.AddPlayer("b", "B"); err != nil {
		t.Fatal(err)
	}
	w.Players[0].Connected = true
	w.Players[1].Connected = true
	return w
}

func TestBridgeGateAndMovementSequence(t *testing.T) {
	w := herderWorld(t)
	w.Players[0].Position = Vec2{-13, -8}
	target := Vec2{10, 8}
	if err := w.Apply("a", Input{Type: "move", Seq: 2, Target: &target}); err != nil {
		t.Fatal(err)
	}
	stale := Vec2{-15, -8}
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &stale})
	if w.Players[0].Target != target {
		t.Fatal("out-of-order input changed target")
	}
	for i := 0; i < 250; i++ {
		old := w.Players[0].Position
		w.Step()
		p := w.Players[0].Position
		if !Walkable(p, w.GateOpen) {
			t.Fatalf("walked through water/fence: %+v", p)
		}
		if p.Sub(old).Len() > 4.0/TickRate+1e-8 {
			t.Fatal("player exceeded authoritative speed")
		}
	}
	if w.Players[0].Position.X < 4 || w.Players[0].Position.X >= 6 {
		t.Fatalf("expected wait near closed gate, got %+v", w.Players[0].Position)
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 150; i++ {
		w.Step()
		if !Walkable(w.Players[0].Position, true) {
			t.Fatal("invalid terrain")
		}
	}
	if w.Players[0].Position.Sub(target).Len() > 0.1 {
		t.Fatalf("did not reach destination: %+v", w.Players[0])
	}
}

func TestSharedCommandsAndGentleInteractions(t *testing.T) {
	w := herderWorld(t)
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err == nil {
		t.Fatal("remote gate interaction accepted")
	}
	if err := w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "come"}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 50; i++ {
		w.Step()
	}
	if w.Dogs[0].Position.Sub(w.Players[0].Position).Len() > 1.3 {
		t.Fatal("corgi did not come")
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "pet", DogID: "mochi"}); err != nil {
		t.Fatal(err)
	}
	if w.Dogs[0].State != "happy" {
		t.Fatal("no pet feedback")
	}
	if err := w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "stay"}); err != nil {
		t.Fatal("second herder could not command shared dog")
	}
	p := w.Dogs[0].Position
	for i := 0; i < 30; i++ {
		w.Step()
	}
	if w.Dogs[0].Position != p {
		t.Fatal("stay moved dog")
	}
	if err := w.Apply("b", Input{Type: "interact", Action: "sit"}); err != nil {
		t.Fatal(err)
	}
	if w.Players[1].State != "sitting" {
		t.Fatal("sit did not settle herder")
	}
	target := Vec2{3, 3}
	w.GateOpen = true
	if err := w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &target}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 150; i++ {
		w.Step()
	}
	if w.Dogs[0].Position.Sub(target).Len() > 0.16 {
		t.Fatalf("dog failed bridge route: %+v", w.Dogs[0])
	}
}

func TestSheepPressureClusteringAndTerrain(t *testing.T) {
	w := herderWorld(t)
	w.Dogs[0].Position = Vec2{-8, 0}
	w.Dogs[0].Command = "stay"
	w.Dogs[1].Position = Vec2{-8, 2}
	w.Dogs[1].Command = "stay"
	w.Sheep[0].Position = Vec2{-6, 0}
	start := w.Sheep[0].Position
	for i := 0; i < 20; i++ {
		w.Step()
	}
	if w.Sheep[0].Position.X <= start.X {
		t.Fatal("dog pressure did not move sheep away")
	}
	w.Sheep[9].Position = Vec2{13, 8}
	w.cluster()
	if w.Sheep[0].Group == w.Sheep[9].Group {
		t.Fatal("stray was not a separate flock")
	}
	for i := 0; i < 1000; i++ {
		w.Step()
		for _, s := range w.Sheep {
			if !Walkable(s.Position, w.GateOpen) {
				t.Fatalf("sheep escaped walkable world: %+v", s)
			}
		}
	}
}

func TestRejectInvalidCommands(t *testing.T) {
	w := herderWorld(t)
	invalid := []Input{
		{Type: "move", Seq: 1},
		{Type: "move", Seq: 1, Target: &Vec2{20, 0}},
		{Type: "move", Seq: 1, Target: &Vec2{0, 8}},
		{Type: "move", Seq: 1, Target: &Vec2{math.NaN(), 0}},
		{Type: "command", DogID: "mochi", Command: "attack"},
		{Type: "command", DogID: "unknown", Command: "come"},
		{Type: "command", DogID: "mochi", Command: "go", Target: &Vec2{0, 8}},
		{Type: "interact", Action: "pet", DogID: "unknown"},
		{Type: "input"},
	}
	for _, input := range invalid {
		if err := w.Apply("a", input); err == nil {
			t.Errorf("accepted invalid input: %+v", input)
		}
	}
	if err := w.AddPlayer("c", "C"); err == nil {
		t.Fatal("third herder accepted")
	}
}

func TestDestinationOnBridge(t *testing.T) {
	w := herderWorld(t)
	target := Vec2{0, 1}
	if err := w.Apply("a", Input{Type: "move", Seq: 1, Target: &target}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 200; i++ {
		w.Step()
	}
	if w.Players[0].Position.Sub(target).Len() > 0.1 {
		t.Fatalf("failed target on bridge: %+v", w.Players[0].Position)
	}
}

func TestFlockCanCrossBridgeAndOpenGate(t *testing.T) {
	w := herderWorld(t)
	w.GateOpen = true
	w.Players[0].Position = Vec2{-16, -9}
	w.Players[1].Position = Vec2{-16, 9}
	for tick := 0; tick < 4000; tick++ {
		if tick%10 == 0 {
			back := 17.0
			centerY := 0.0
			for _, s := range w.Sheep {
				back = math.Min(back, s.Position.X)
				centerY += s.Position.Y / float64(len(w.Sheep))
			}
			for i, id := range []string{"mochi", "maple"} {
				target := Vec2{math.Max(-16, back-2), math.Max(-10, math.Min(10, centerY+float64(i*2-1)*1.2))}
				if !Walkable(target, true) {
					target.Y = 0
				}
				_ = w.Apply("a", Input{Type: "command", DogID: id, Command: "go", Target: &target})
			}
		}
		w.Step()
		if w.Settled == 10 {
			return
		}
	}
	t.Fatalf("flock failed to pass bridge and open gate: settled=%d sheep=%+v dogs=%+v", w.Settled, w.Sheep, w.Dogs)
}

func larchWorld(t *testing.T) *World {
	t.Helper()
	w := herderWorld(t)
	w.Landscape = LandscapeLarch
	w.Layout = LayoutForLandscape(LandscapeLarch)
	return w
}

func TestLarchOpeningsAndRoundTripNavigation(t *testing.T) {
	w := larchWorld(t)
	if w.Walkable(Vec2{0, 0}) || !w.Walkable(Vec2{0, -4}) || w.Walkable(Vec2{6, 4}) {
		t.Fatal("incorrect offset bridge or closed gate collision")
	}
	if err := w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{0, 0}}); err == nil {
		t.Fatal("old centered bridge destination accepted in Larch")
	}
	if err := w.Apply("a", Input{Type: "command", DogID: "mochi", Command: "go", Target: &Vec2{0, 0}}); err == nil {
		t.Fatal("dog accepted a destination in water")
	}
	// Every step begins at the ordinary spawn, including approaching the gate.
	target := Vec2{5.4, 4}
	if err := w.Apply("a", Input{Type: "move", Seq: 2, Target: &target}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 260; i++ {
		w.Step()
		assertWalkableWorld(t, w)
	}
	if w.Players[0].Position.Sub(target).Len() > .1 {
		t.Fatalf("failed approach to offset gate: %+v", w.Players[0])
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err != nil {
		t.Fatal(err)
	}
	if !w.Walkable(Vec2{6, 4}) || w.Walkable(Vec2{6, 0}) {
		t.Fatal("opening offset did not persist after gate opened")
	}
	for seq, destination := range []Vec2{{12, -6}, {0, -3}, {-10, 5}, {11, 7}, {-12, -7}} {
		if err := w.Apply("a", Input{Type: "move", Seq: uint64(seq + 3), Target: &destination}); err != nil {
			t.Fatal(err)
		}
		if err := w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "go", Target: &destination}); err != nil {
			t.Fatal(err)
		}
		for i := 0; i < 400; i++ {
			w.Step()
			assertWalkableWorld(t, w)
		}
		if w.Players[0].Position.Sub(destination).Len() > .1 || w.Dogs[0].Position.Sub(destination).Len() > .16 {
			t.Fatalf("failed two-way offset route to %+v: player=%+v dog=%+v", destination, w.Players[0], w.Dogs[0])
		}
	}
}

func assertWalkableWorld(t *testing.T, w *World) {
	t.Helper()
	for _, p := range w.Players {
		if !w.Walkable(p.Position) {
			t.Fatalf("herder crossed blocked terrain: %+v", p)
		}
	}
	for _, d := range w.Dogs {
		if !w.Walkable(d.Position) {
			t.Fatalf("dog crossed blocked terrain: %+v", d)
		}
	}
	for _, s := range w.Sheep {
		if !w.Walkable(s.Position) {
			t.Fatalf("sheep crossed blocked terrain: %+v", s)
		}
	}
}

func TestAllTenSheepReachLarchPastureWithoutTeleporting(t *testing.T) {
	w := larchWorld(t)
	for _, id := range []string{"mochi", "maple"} {
		_ = w.Apply("a", Input{Type: "command", DogID: id, Command: "stay"})
	}
	gateApproach := Vec2{5.4, w.Layout.GateY}
	if err := w.Apply("a", Input{Type: "move", Seq: 1, Target: &gateApproach}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 260; i++ {
		w.Step()
		assertWalkableWorld(t, w)
	}
	if err := w.Apply("a", Input{Type: "interact", Action: "gate"}); err != nil {
		t.Fatal(err)
	}
	_ = w.Apply("a", Input{Type: "move", Seq: 2, Target: &Vec2{15, -8}})
	_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-16, 9}})
	for tick := 0; tick < 6000; tick++ {
		if tick%10 == 0 {
			back, centerY := 17.0, 0.0
			for _, sheep := range w.Sheep {
				back = math.Min(back, sheep.Position.X)
				centerY += sheep.Position.Y / 10
			}
			for i, id := range []string{"mochi", "maple"} {
				target := Vec2{math.Max(-16, back-2), math.Max(-10, math.Min(10, centerY+float64(i*2-1)*1.2))}
				// Once the last sheep is over, bring both dogs off the bridge;
				// staying in the channel would stop applying pressure to the turn.
				if back > 1.8 {
					target.X = math.Max(2.0, target.X)
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
		for i, sheep := range w.Sheep {
			if sheep.Position.Sub(previous.Sheep[i].Position).Len() > 2.6/TickRate+1e-8 {
				t.Fatal("sheep exceeded speed or teleported")
			}
		}
		for i, dog := range w.Dogs {
			if dog.Position.Sub(previous.Dogs[i].Position).Len() > 4.6/TickRate+1e-8 {
				t.Fatal("dog exceeded speed or teleported")
			}
		}
		if w.Settled == 10 {
			t.Logf("all ten sheep reached Larch pasture at tick %d", w.Tick)
			return
		}
	}
	t.Fatalf("offset herding did not settle all sheep: settled=%d sheep=%+v dogs=%+v", w.Settled, w.Sheep, w.Dogs)
}

func TestLayoutCloneAndValidation(t *testing.T) {
	w := larchWorld(t)
	copy := w.Clone()
	copy.Layout.GateY = 0
	if w.Layout.GateY != 4 {
		t.Fatal("snapshot layout aliases mutable world")
	}
	if copy.ValidateLayout() == nil {
		t.Fatal("accepted layout mismatch")
	}
	copy.Layout.Version = 99
	if copy.ValidateLayout() == nil {
		t.Fatal("accepted unknown layout version")
	}
	if !w.SupportsLayout(1) || w.SupportsLayout(0) || !w.SupportsLayout(2) || !w.SupportsLayout(3) || !w.SupportsLayout(4) || !w.SupportsLayout(5) || !w.SupportsLayout(6) || !w.SupportsLayout(7) || !w.SupportsLayout(8) || w.SupportsLayout(9) {
		t.Fatal("Larch capability validation failed")
	}
	if !herderWorld(t).SupportsLayout(0) {
		t.Fatal("legacy centered clients rejected")
	}
}
