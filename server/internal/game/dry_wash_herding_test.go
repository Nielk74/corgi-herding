package game

import "testing"

func dryWashWorld(t *testing.T) *World {
	t.Helper()
	w := NewForLandscape("ABCDEF", LandscapeDryWash)
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

// All ten start at the public new-world spawns. Only normal shared-dog
// commands drive them; every tick checks IDs, complete dry chords and speeds.
func TestDryWashNormalTenSheepWashAndBothBranchReturns(t *testing.T) {
	w := dryWashWorld(t)
	a := w.Layout.Region.Anchors
	for _, leg := range []struct {
		name    string
		indices []int
	}{
		{"main wash outward", []int{1, 2, 3, 4, 5, 6}},
		{"main wash return", []int{5, 4, 3, 2, 1, 0}},
		{"eastern terrace outward", []int{1, 8, 1, 2, 9, 10}},
		{"eastern terrace return", []int{9, 2, 1, 0}},
		{"western benches outward", []int{7, 0, 1, 2, 3, 11, 12, 11, 3, 4, 13}},
		{"western benches return", []int{4, 3, 2, 1, 0}},
	} {
		var goals []Vec2
		for _, i := range leg.indices {
			goals = append(goals, a[i])
		}
		guideRegionGroup(t, w, goals, leg.name)
	}
	for i, dog := range []string{"mochi", "maple"} {
		sendHerdDog(t, w, []string{"a", "b"}[i], dog, Vec2{-45 + float64(i)*6, 80})
	}
	for tick := 0; tick < 500; tick++ {
		stepRegionChecked(t, w)
	}
	for _, s := range w.Sheep {
		if s.State != "grazing" {
			t.Fatalf("not quiet after dog retreat: %+v", s)
		}
	}
}

func TestDryWashNormalFlockSplitsAndBothDogsRetrieve(t *testing.T) {
	w := dryWashWorld(t)
	goals := []Vec2{w.Layout.Region.Anchors[7], w.Layout.Region.Anchors[1]}
	groups := [][]int{{}, {}}
	split := false
	for tick := 0; tick < 12000; tick++ {
		if tick%10 == 0 {
			groups = [][]int{{}, {}}
			for index, s := range w.Sheep {
				side := 0
				if s.Position.X >= -38.2 {
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
			t.Logf("actual %d+%d dry-wash branch split tick%d", len(groups[0]), len(groups[1]), w.Tick)
			break
		}
	}
	if !split {
		t.Fatalf("no actual branch split: groups%v sheep%+v dogs%+v", groups, w.Sheep, w.Dogs)
	}
	goal := w.Layout.Region.Anchors[0]
	for tick := 0; tick < 12000; tick++ {
		// Once both actual branch groups are in the broad home clearing,
		// coordinate the dogs behind the combined flock. Continuing opposing
		// independent pressure here scatters neighbouring sheep, as in play.
		if cloudGroupNear(w, []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, goal, 12) {
			guideRegionGroup(t, w, []Vec2{goal}, "split common-clearing regroup")
			for _, sheep := range w.Sheep {
				if sheep.Group != w.Sheep[0].Group {
					t.Fatal("close flock still split", sheep.ID)
				}
			}
			t.Logf("actual dry-wash split recovered tick%d", w.Tick)
			return
		}
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				farthest, distance := groups[i][0], -1.0
				for _, index := range groups[i] {
					if d := w.Sheep[index].Position.Sub(goal).Len(); d > distance {
						farthest, distance = index, d
					}
				}
				var local []int
				for _, index := range groups[i] {
					if w.Sheep[index].Position.Sub(w.Sheep[farthest].Position).Len() < 3.5 {
						local = append(local, index)
					}
				}
				sendHerdDog(t, w, []string{"b", "a"}[i], dog, regionPressureTarget(w, local, goal, 0))
			}
		}
		stepRegionChecked(t, w)
	}
	t.Fatalf("split recovery stalled: sheep%+v dogs%+v", w.Sheep, w.Dogs)
}
