package game

import (
	"math"
	"testing"
)

// Choose a legitimate accessible dog target near the desired pressure position.
// This moves no actor: dogs must still walk the full authoritative route there.
func cloudPressureTarget(w *World, indices []int, goal Vec2, lateral float64) Vec2 {
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
	best, distance := Vec2{}, math.Inf(1)
	consider := func(c Vec2, r float64) {
		d := desired.Sub(c)
		candidate := desired
		if d.Len() > r-.15 {
			candidate = c.Add(d.Unit().Mul(r - .15))
		}
		if gap := candidate.Sub(desired).Len(); gap < distance {
			best, distance = candidate, gap
		}
	}
	ridge := *w.Layout.Ridge
	for _, s := range ridge.Shelves {
		consider(s.Center, s.Radius)
	}
	for i := 1; i < len(ridge.Spine); i++ {
		consider(nearestOnSegment(desired, ridge.Spine[i-1], ridge.Spine[i]), ridge.HalfWidth)
	}
	return best
}

func cloudGroupNear(w *World, indices []int, goal Vec2, radius float64) bool {
	for _, i := range indices {
		if w.Sheep[i].Position.Sub(goal).Len() > radius {
			return false
		}
	}
	return true
}

func TestCloudTenSheepUpAndBackFromNormalSpawns(t *testing.T) {
	w := cloudWorld(t)
	all := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{-14, 3}})
	_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-14, -3}})
	for leg, goals := range [][]Vec2{{{-2, -5}, {5, 1}, {11, 4}}, {{5, 1}, {-2, -5}, {-10, 0}}} {
		phase := 0
		finished := false
		for tick := 0; tick < 6000; tick++ {
			if phase < len(goals)-1 && cloudGroupNear(w, all, goals[phase], 4.5) {
				phase++
			}
			if tick%10 == 0 {
				for i, dog := range []string{"mochi", "maple"} {
					sendHerdDog(t, w, []string{"a", "b"}[(i+leg+phase)%2], dog, cloudPressureTarget(w, all, goals[phase], float64(i*2-1)*1.2))
				}
			}
			stepCloudChecked(t, w)
			if phase == len(goals)-1 && ((leg == 0 && w.Settled == 10) || (leg == 1 && cloudGroupNear(w, all, Vec2{-10, 0}, 4.6))) {
				finished = true
				t.Logf("Cloud leg%d all ten sheep arrived at tick%d", leg, w.Tick)
				break
			}
		}
		if !finished {
			t.Fatalf("Cloud leg%d stalled phase%d settled%d sheep=%+v dogs=%+v", leg, phase, w.Settled, w.Sheep, w.Dogs)
		}
	}
	if w.Settled != 0 {
		t.Fatal("return to starting shelf retained remote rest count")
	}
}

func TestCloudDogCreatedSplitFlockCanReuniteUphill(t *testing.T) {
	w := cloudWorld(t)
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{-15, 0}})
	_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-14, -3}})
	groups := [][]int{{0, 1, 2, 3, 4}, {5, 6, 7, 8, 9}}
	split := false
	for tick := 0; tick < 2000; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				sendHerdDog(t, w, []string{"a", "b"}[i], dog, cloudPressureTarget(w, groups[i], Vec2{-9.5, float64(i*2-1) * 4.8}, 0))
			}
		}
		stepCloudChecked(t, w)
		minY, maxY := 11.0, -11.0
		for _, s := range w.Sheep {
			minY = math.Min(minY, s.Position.Y)
			maxY = math.Max(maxY, s.Position.Y)
		}
		if maxY-minY > 8 && w.Sheep[0].Group != w.Sheep[9].Group {
			split = true
			t.Logf("Cloud flock split at tick%d spread%g", w.Tick, maxY-minY)
			break
		}
	}
	if !split {
		t.Fatalf("normal-spawn Cloud flock never split: %+v", w.Sheep)
	}
	groups = [][]int{{}, {}}
	for i, s := range w.Sheep {
		side := 0
		if s.Position.Y > 0 {
			side = 1
		}
		groups[side] = append(groups[side], i)
	}
	if len(groups[0]) == 0 || len(groups[1]) == 0 {
		t.Fatal("no two actual spatial flocks")
	}
	phases := [2]int{}
	goals := []Vec2{{-2, -5}, {5, 1}, {11, 4}}
	for tick := 0; tick < 10000; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				if phases[i] < len(goals)-1 && cloudGroupNear(w, groups[i], goals[phases[i]], 3.3) {
					phases[i]++
				}
				sendHerdDog(t, w, []string{"b", "a"}[i], dog, cloudPressureTarget(w, groups[i], goals[phases[i]], 0))
			}
		}
		stepCloudChecked(t, w)
		if w.Settled == 10 {
			t.Logf("Cloud split flock reunited uphill at tick%d", w.Tick)
			return
		}
	}
	t.Fatalf("split Cloud flock could not be retrieved phases%v settled%d sheep=%+v dogs=%+v", phases, w.Settled, w.Sheep, w.Dogs)
}
