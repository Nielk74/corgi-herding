package game

import (
	"math"
	"testing"
)

func shoreWorld(t *testing.T) *World {
	t.Helper()
	w := NewForLandscape("ABCDEF", LandscapeJuniper)
	for _, id := range []string{"a", "b"} {
		if err := w.AddPlayer(id, id); err != nil {
			t.Fatal(err)
		}
		w.Player(id).Connected = true
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(err)
	}
	return w
}

func stepShoreChecked(t *testing.T, w *World) {
	t.Helper()
	before := w.Clone()
	w.Step()
	if len(w.Players) != 2 || len(w.Dogs) != 2 || len(w.Sheep) != 10 {
		t.Fatal("Juniper actor counts changed")
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatalf("tick %d: %v", w.Tick, err)
	}
	check := func(a, b Vec2, speed float64) {
		if b.Sub(a).Len() > speed/TickRate+1e-8 || !ShoreVisible(a, b, *w.Layout.Shore) {
			t.Fatalf("tick %d unsafe shore step %v -> %v speed %g", w.Tick, a, b, speed)
		}
	}
	for i, p := range w.Players {
		check(before.Players[i].Position, p.Position, 4)
	}
	for i, d := range w.Dogs {
		check(before.Dogs[i].Position, d.Position, 4.6)
	}
	for i, s := range w.Sheep {
		if s.ID != before.Sheep[i].ID {
			t.Fatal("Juniper replaced a sheep")
		}
		check(before.Sheep[i].Position, s.Position, 2.6)
	}
}

func shorePressureTarget(w *World, indices []int, goal Vec2, lateral float64) Vec2 {
	// Reuse the test's legitimate target-selection strategy, not actor positions.
	copy := *w
	layout := *w.Layout
	r := w.Layout.Shore.corridor()
	layout.Ridge = &r
	copy.Layout = &layout
	return cloudPressureTarget(&copy, indices, goal, lateral)
}

func TestShoreTenSheepOutAndBackFromNormalSpawns(t *testing.T) {
	w := shoreWorld(t)
	all := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	for leg, goals := range [][]Vec2{{{-8, -3}, {-3, -6}, {4, -6}, {9, -2}, {11, 4}}, {{9, -2}, {4, -6}, {-3, -6}, {-8, -3}, {-11, 2}}} {
		phase, finished := 0, false
		for tick := 0; tick < 8000; tick++ {
			if phase < len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4.0) {
				phase++
			}
			if tick%10 == 0 {
				for i, dog := range []string{"mochi", "maple"} {
					sendHerdDog(t, w, []string{"a", "b"}[(i+leg+phase)%2], dog, shorePressureTarget(w, all, goals[phase], float64(i*2-1)*1.2))
				}
			}
			stepShoreChecked(t, w)
			if phase == len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4.3) {
				finished = true
				t.Logf("Juniper leg %d all ten arrived tick %d", leg, w.Tick)
				break
			}
		}
		if !finished {
			t.Fatalf("Juniper leg %d stalled phase %d sheep %+v dogs %+v", leg, phase, w.Sheep, w.Dogs)
		}
	}
}

func TestShoreNormalFlockSplitsAndBothDogsRetrieve(t *testing.T) {
	w := shoreWorld(t)
	groups := [][]int{{0, 1, 2, 3, 4}, {5, 6, 7, 8, 9}}
	split := false
	for tick := 0; tick < 2500; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				sendHerdDog(t, w, []string{"a", "b"}[i], dog, shorePressureTarget(w, groups[i], []Vec2{{-10, -3}, {-10, 6}}[i], 0))
			}
		}
		stepShoreChecked(t, w)
		minY, maxY := 11.0, -11.0
		for _, s := range w.Sheep {
			minY = math.Min(minY, s.Position.Y)
			maxY = math.Max(maxY, s.Position.Y)
		}
		if maxY-minY > 7.5 && w.Sheep[0].Group != w.Sheep[9].Group {
			split = true
			t.Logf("Juniper real split tick %d spread %g", w.Tick, maxY-minY)
			break
		}
	}
	if !split {
		t.Fatalf("Juniper flock did not separate: %+v", w.Sheep)
	}
	groups = [][]int{{}, {}}
	for i, s := range w.Sheep {
		side := 0
		if s.Position.Y > 1 {
			side = 1
		}
		groups[side] = append(groups[side], i)
	}
	if len(groups[0]) == 0 || len(groups[1]) == 0 {
		t.Fatal("no two spatial flocks")
	}
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{-15.5, 0}})
	_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-15.5, 2}})
	phases := [2]int{}
	goals := []Vec2{{-8, -3}, {-3, -6}, {4, -6}, {9, -2}, {11, 4}}
	for tick := 0; tick < 12000; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				if phases[i] < len(goals)-1 && cloudGroupNear(w, groups[i], goals[phases[i]], 3.3) {
					phases[i]++
				}
				// A real split can divide again. A herder naturally goes back for
				// the most distant straggler, not an empty center between groups.
				farthest, distance := groups[i][0], -1.0
				for _, index := range groups[i] {
					if d := w.Sheep[index].Position.Sub(goals[phases[i]]).Len(); d > distance {
						farthest, distance = index, d
					}
				}
				local := []int{}
				for _, index := range groups[i] {
					if w.Sheep[index].Position.Sub(w.Sheep[farthest].Position).Len() < 3.5 {
						local = append(local, index)
					}
				}
				sendHerdDog(t, w, []string{"b", "a"}[i], dog, shorePressureTarget(w, local, goals[phases[i]], 0))
			}
		}
		stepShoreChecked(t, w)
		if cloudGroupNear(w, []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, Vec2{11, 4}, 4.3) {
			t.Logf("Juniper split flock retrieved tick %d", w.Tick)
			return
		}
	}
	t.Fatalf("Juniper retrieval stalled phases %v sheep %+v dogs %+v", phases, w.Sheep, w.Dogs)
}
