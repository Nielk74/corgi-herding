package game

import (
	"math"
	"testing"
)

func regionWorld(t *testing.T) *World {
	t.Helper()
	w := NewForLandscape("ABCDEF", LandscapeAlpineValley)
	for _, id := range []string{"a", "b"} {
		if err := w.AddPlayer(id, id); err != nil {
			t.Fatal(err)
		}
		w.Player(id).Connected = true
	}
	if err := w.ValidateLayout(); err != nil {
		t.Fatal(err)
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(err)
	}
	return w
}

func stepRegionChecked(t *testing.T, w *World) {
	t.Helper()
	before := w.Clone()
	w.Step()
	if len(w.Players) != 2 || len(w.Dogs) != 2 || len(w.Sheep) != 10 || w.Settled != 0 {
		t.Fatal("region actors or quiet state changed")
	}
	if err := w.ValidateNavigation(); err != nil {
		t.Fatal(w.Tick, err)
	}
	check := func(a, b Vec2, speed float64) {
		if b.Sub(a).Len() > speed/TickRate+1e-8 || !RegionVisible(a, b, *w.Layout.Region) {
			t.Fatalf("tick%d unsafe region movement %v -> %v", w.Tick, a, b)
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

// Select an ordinary legal dog destination, never alter actor coordinates.
func regionPressureTarget(w *World, indices []int, goal Vec2, lateral float64) Vec2 {
	center := Vec2{}
	for _, i := range indices {
		center = center.Add(w.Sheep[i].Position)
	}
	center = center.Mul(1 / float64(len(indices)))
	direction := goal.Sub(center).Unit()
	back := 0.0
	for _, i := range indices {
		back = math.Min(back, dot(w.Sheep[i].Position.Sub(center), direction))
	}
	desired := center.Add(direction.Mul(back - 2)).Add(Vec2{-direction.Y, direction.X}.Mul(lateral))
	r := *w.Layout.Region
	best, distance := Vec2{}, math.Inf(1)
	consider := func(c Vec2, radius float64) {
		delta := desired.Sub(c)
		candidate := desired
		if delta.Len() > radius-.15 {
			candidate = c.Add(delta.Unit().Mul(radius - .15))
		}
		candidate.X = math.Max(r.Bounds.Min.X+.15, math.Min(r.Bounds.Max.X-.15, candidate.X))
		candidate.Y = math.Max(r.Bounds.Min.Y+.15, math.Min(r.Bounds.Max.Y-.15, candidate.Y))
		if !RegionWalkable(candidate, r) {
			return
		}
		if gap := candidate.Sub(desired).Len(); gap < distance {
			best, distance = candidate, gap
		}
	}
	for _, c := range r.Clearings {
		consider(c.Center, c.Radius)
	}
	for _, e := range r.Corridors {
		consider(nearestOnSegment(desired, r.Anchors[e.A], r.Anchors[e.B]), e.HalfWidth)
	}
	return best
}

func guideRegionGroup(t *testing.T, w *World, goals []Vec2, label string) {
	t.Helper()
	all := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	phase := 0
	start := w.Tick
	phaseStart := start
	for tick := 0; tick < 30000; tick++ {
		if phase < len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4) {
			t.Logf("%s waypoint%d all ten tick%d (%d ticks)", label, phase, w.Tick, w.Tick-phaseStart)
			phase++
			phaseStart = w.Tick
		}
		if w.Tick-phaseStart > 8000 {
			t.Fatalf("%s stalled phase%d sheep%+v dogs%+v", label, phase, w.Sheep, w.Dogs)
		}
		if tick%10 == 0 {
			indices := all
			if w.Tick-phaseStart > 600 {
				farthest, distance := 0, -1.0
				for _, index := range all {
					if d := w.Sheep[index].Position.Sub(goals[phase]).Len(); d > distance {
						farthest, distance = index, d
					}
				}
				indices = nil
				for _, index := range all {
					if w.Sheep[index].Position.Sub(w.Sheep[farthest].Position).Len() < 3.5 {
						indices = append(indices, index)
					}
				}
			}
			for i, dog := range []string{"mochi", "maple"} {
				sendHerdDog(t, w, []string{"a", "b"}[(i+phase)%2], dog, regionPressureTarget(w, indices, goals[phase], float64(i*2-1)*1.2))
			}
		}
		stepRegionChecked(t, w)
		if phase == len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4.3) {
			t.Logf("%s all ten tick%d (%d ticks)", label, w.Tick, w.Tick-start)
			return
		}
	}
	t.Fatalf("%s bounded journey exhausted", label)
}

func TestRegionNormalTenSheepLongValleyAndLoops(t *testing.T) {
	w := regionWorld(t)
	a := w.Layout.Region.Anchors
	for _, leg := range []struct {
		name    string
		indices []int
	}{
		{"main valley outward", []int{1, 2, 3, 4, 5, 6}},
		{"western return loop", []int{5, 14, 12, 10, 2, 8, 0}},
		{"eastern outward loop", []int{7, 1, 9, 15, 11, 4, 13, 5, 6}},
		{"main valley return", []int{5, 4, 3, 2, 1, 0}},
	} {
		goals := []Vec2{}
		for _, i := range leg.indices {
			goals = append(goals, a[i])
		}
		guideRegionGroup(t, w, goals, leg.name)
	}
	for i, dog := range []string{"mochi", "maple"} {
		sendHerdDog(t, w, []string{"a", "b"}[i], dog, Vec2{-53 + float64(i)*6, 76})
	}
	for tick := 0; tick < 500; tick++ {
		stepRegionChecked(t, w)
	}
	for _, s := range w.Sheep {
		if s.State != "grazing" {
			t.Fatalf("not quiet after ordinary retreat: %+v", s)
		}
	}
}

func TestRegionNormalFlockSplitsAcrossMeadowsAndBothDogsRetrieve(t *testing.T) {
	w := regionWorld(t)
	goals := []Vec2{w.Layout.Region.Anchors[8], w.Layout.Region.Anchors[7]}
	groups := [][]int{{}, {}}
	split := false
	for tick := 0; tick < 12000; tick++ {
		if tick%10 == 0 {
			groups = [][]int{{}, {}}
			for index, s := range w.Sheep {
				side := 0
				if s.Position.X >= -43 {
					side = 1
				}
				groups[side] = append(groups[side], index)
			}
			for i, dog := range []string{"mochi", "maple"} {
				if len(groups[i]) > 0 {
					sendHerdDog(t, w, []string{"a", "b"}[i], dog, regionPressureTarget(w, groups[i], goals[i], 0))
				}
			}
		}
		stepRegionChecked(t, w)
		if len(groups[0]) >= 2 && len(groups[1]) >= 2 && cloudGroupNear(w, groups[0], goals[0], 4.3) && cloudGroupNear(w, groups[1], goals[1], 4.3) && w.Sheep[groups[0][0]].Group != w.Sheep[groups[1][0]].Group {
			split = true
			t.Logf("actual %d+%d separated meadows split tick%d", len(groups[0]), len(groups[1]), w.Tick)
			break
		}
	}
	if !split {
		t.Fatalf("no actual branch split: groups%v sheep%+v dogs%+v", groups, w.Sheep, w.Dogs)
	}
	// Preserve the actual split membership; each human commands a different shared
	// dog to bring its distant local sheep home. Neither sheep nor dogs are reset.
	goal := w.Layout.Region.Anchors[0]
	for tick := 0; tick < 12000; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				farthest, distance := groups[i][0], -1.0
				for _, index := range groups[i] {
					if d := w.Sheep[index].Position.Sub(goal).Len(); d > distance {
						farthest, distance = index, d
					}
				}
				local := []int{}
				for _, index := range groups[i] {
					if w.Sheep[index].Position.Sub(w.Sheep[farthest].Position).Len() < 3.5 {
						local = append(local, index)
					}
				}
				sendHerdDog(t, w, []string{"b", "a"}[i], dog, regionPressureTarget(w, local, goal, 0))
			}
		}
		stepRegionChecked(t, w)
		if cloudGroupNear(w, []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, goal, 4.3) && w.Sheep[0].Group == w.Sheep[9].Group {
			t.Logf("actual split recovered tick%d", w.Tick)
			return
		}
	}
	t.Fatalf("split recovery stalled: sheep%+v dogs%+v", w.Sheep, w.Dogs)
}
