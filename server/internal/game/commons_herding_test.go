package game

import "testing"

func commonsWorld(t *testing.T) *World {
	t.Helper()
	w := NewForLandscape("ABCDEF", LandscapeBellflower)
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

func stepCommonsChecked(t *testing.T, w *World) {
	t.Helper()
	before := w.Clone()
	w.Step()
	if len(w.Players) != 2 || len(w.Dogs) != 2 || len(w.Sheep) != 10 || w.Settled != 0 {
		t.Fatal("commons actors or quiet state changed")
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(w.Tick, err)
	}
	check := func(a, b Vec2, speed float64) {
		if b.Sub(a).Len() > speed/TickRate+1e-8 || !CommonsVisible(a, b, *w.Layout.Commons) {
			t.Fatalf("tick%d unsafe commons movement %v -> %v", w.Tick, a, b)
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
			t.Fatal("replaced sheep")
		}
		check(before.Sheep[i].Position, s.Position, 2.6)
	}
}

func commonsPressureTarget(w *World, indices []int, goal Vec2, lateral float64) Vec2 {
	copy := *w
	layout := *w.Layout
	r := w.Layout.Commons.shore().corridor()
	layout.Ridge = &r
	copy.Layout = &layout
	return cloudPressureTarget(&copy, indices, goal, lateral)
}

func guideCommonsGroup(t *testing.T, w *World, goals []Vec2, label string) {
	t.Helper()
	all := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	phase := 0
	start := w.Tick
	for tick := 0; tick < 8000; tick++ {
		if phase < len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4) {
			phase++
		}
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				sendHerdDog(t, w, []string{"a", "b"}[(i+phase)%2], dog, commonsPressureTarget(w, all, goals[phase], float64(i*2-1)*1.2))
			}
		}
		stepCommonsChecked(t, w)
		if phase == len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4.3) {
			t.Logf("%s all ten reached tick%d (%d ticks)", label, w.Tick, w.Tick-start)
			return
		}
	}
	t.Fatalf("%s stalled phase%d sheep%+v dogs%+v", label, phase, w.Sheep, w.Dogs)
}

func TestCommonsAllTenBothBranchesOutBackAndAcross(t *testing.T) {
	w := commonsWorld(t)
	for _, leg := range []struct {
		name  string
		goals []Vec2
	}{
		{"central to sunny", []Vec2{{4, -4}, {10, -6}}},
		{"sunny to central", []Vec2{{4, -4}, {0, 0}, {-5, 0}}},
		{"central to hollow", []Vec2{{4, 4}, {10, 6}}},
		{"hollow to central", []Vec2{{4, 4}, {0, 0}, {-5, 0}}},
		{"central to sunny again", []Vec2{{4, -4}, {10, -6}}},
		{"sunny across to hollow", []Vec2{{4, -4}, {0, 0}, {4, 4}, {10, 6}}},
		{"hollow across to sunny", []Vec2{{4, 4}, {0, 0}, {4, -4}, {10, -6}}},
	} {
		guideCommonsGroup(t, w, leg.goals, leg.name)
	}
}

func TestCommonsNormalFlockSplitBetweenBranchesAndRecovered(t *testing.T) {
	w := commonsWorld(t)
	groups := [][]int{{0, 1, 2, 3, 4}, {5, 6, 7, 8, 9}}
	phases := [2]int{}
	goals := [][]Vec2{{{0, -3.5}, {4, -4}, {10, -6}}, {{0, 3.5}, {4, 4}, {10, 6}}}
	split := false
	for tick := 0; tick < 8000; tick++ {
		if tick%10 == 0 {
			// Work with the sheep actually on each side, not permanent artificial
			// five-sheep assignments when an individual crosses the fork.
			groups = [][]int{{}, {}}
			for index, s := range w.Sheep {
				side := 0
				if s.Position.Y >= 0 {
					side = 1
				}
				groups[side] = append(groups[side], index)
			}
			for i, dog := range []string{"mochi", "maple"} {
				if len(groups[i]) == 0 {
					continue
				}
				if phases[i] < 2 && cloudGroupNear(w, groups[i], goals[i][phases[i]], 3.3) {
					phases[i]++
				}
				sendHerdDog(t, w, []string{"a", "b"}[i], dog, commonsPressureTarget(w, groups[i], goals[i][phases[i]], 0))
			}
		}
		stepCommonsChecked(t, w)
		if phases[0] == 2 && phases[1] == 2 && len(groups[0]) >= 2 && len(groups[1]) >= 2 && cloudGroupNear(w, groups[0], Vec2{10, -6}, 4.3) && cloudGroupNear(w, groups[1], Vec2{10, 6}, 4.3) && w.Sheep[groups[0][0]].Group != w.Sheep[groups[1][0]].Group {
			t.Logf("actual %d+%d branch split tick%d", len(groups[0]), len(groups[1]), w.Tick)
			split = true
			break
		}
	}
	if !split {
		t.Fatalf("no real branch split phases%v sheep%+v dogs%+v", phases, w.Sheep, w.Dogs)
	}
	phases = [2]int{}
	goals = [][]Vec2{{{4, -4}, {0, -1.5}, {-5, 0}}, {{4, 4}, {0, 1.5}, {-5, 0}}}
	for tick := 0; tick < 10000; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				if phases[i] < 2 && cloudGroupNear(w, groups[i], goals[i][phases[i]], 3.3) {
					phases[i]++
				}
				farthest, distance := groups[i][0], -1.0
				for _, index := range groups[i] {
					if d := w.Sheep[index].Position.Sub(goals[i][phases[i]]).Len(); d > distance {
						farthest, distance = index, d
					}
				}
				local := []int{}
				for _, index := range groups[i] {
					if w.Sheep[index].Position.Sub(w.Sheep[farthest].Position).Len() < 3.5 {
						local = append(local, index)
					}
				}
				sendHerdDog(t, w, []string{"b", "a"}[i], dog, commonsPressureTarget(w, local, goals[i][phases[i]], 0))
			}
		}
		stepCommonsChecked(t, w)
		if phases[0] == 2 && phases[1] == 2 && cloudGroupNear(w, []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, Vec2{-5, 0}, 4.3) && w.Sheep[0].Group == w.Sheep[9].Group {
			t.Logf("actual split recovered centrally tick%d", w.Tick)
			return
		}
	}
	t.Fatalf("split recovery stalled phases%v sheep%+v dogs%+v", phases, w.Sheep, w.Dogs)
}
