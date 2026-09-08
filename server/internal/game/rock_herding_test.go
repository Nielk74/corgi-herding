package game

import (
	"math"
	"testing"
)

// This driver only issues ordinary targets. Every actor begins at the shipped
// spawn and remains governed by ordinary speed, rock collision and animal AI.
func herdDogTarget(w *World, indices []int, goal Vec2, lateral float64) Vec2 {
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
	target := center.Add(direction.Mul(back - 2.0)).Add(Vec2{-direction.Y, direction.X}.Mul(lateral))
	if target.Len() < 3.6 {
		target = target.Unit().Mul(3.6)
	}
	target.X = math.Max(-16.5, math.Min(16.5, target.X))
	target.Y = math.Max(-10.5, math.Min(10.5, target.Y))
	return target
}

func sendHerdDog(t *testing.T, w *World, player, dog string, target Vec2) {
	t.Helper()
	if err := w.Apply(player, Input{Type: "command", DogID: dog, Command: "go", Target: &target}); err != nil {
		t.Fatalf("driver target%v: %v", target, err)
	}
}

func TestOasisTenSheepThroughEitherDryPass(t *testing.T) {
	for _, sign := range []float64{-1, 1} {
		w := oasisWorld(t)
		_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{-16, -10}})
		_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-16, 10}})
		all := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
		phase := 0
		for tick := 0; tick < 5000; tick++ {
			minY, minX := 11.0, 17.0
			for _, s := range w.Sheep {
				minY = math.Min(minY, s.Position.Y*sign)
				minX = math.Min(minX, s.Position.X)
			}
			if phase == 0 && minY > 4.6 {
				phase = 1
			}
			if phase == 1 && minX > 5 {
				phase = 2
			}
			goal := []Vec2{{-6, sign * 6.8}, {7, sign * 6.8}, {13, sign * 3}}[phase]
			if tick%10 == 0 {
				for i, dog := range []string{"mochi", "maple"} {
					sendHerdDog(t, w, []string{"a", "b"}[(i+phase)%2], dog, herdDogTarget(w, all, goal, float64(i*2-1)*1.2))
				}
			}
			stepOasisChecked(t, w)
			if w.Settled == 10 {
				if phase != 2 {
					t.Fatal("herding skipped the requested pass")
				}
				t.Logf("all ten sheep through sign%g pass at tick%d", sign, w.Tick)
				break
			}
		}
		if w.Settled != 10 {
			t.Fatalf("sign%g stalled phase%d settled%d sheep=%+v dogs=%+v", sign, phase, w.Settled, w.Sheep, w.Dogs)
		}
	}
}

func TestOasisSplitFlockCanBeRetrievedByBothDogs(t *testing.T) {
	w := oasisWorld(t)
	_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{-16, -10}})
	_ = w.Apply("b", Input{Type: "move", Seq: 1, Target: &Vec2{-16, 10}})
	groups := [][]int{{0, 1, 2, 3, 4}, {5, 6, 7, 8, 9}}
	split := false
	for tick := 0; tick < 1500; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				sendHerdDog(t, w, []string{"a", "b"}[i], dog, herdDogTarget(w, groups[i], Vec2{-6, float64(i*2-1) * 8}, 0))
			}
		}
		stepOasisChecked(t, w)
		minY, maxY := -11.0, 11.0
		for _, i := range groups[0] {
			maxY = math.Min(maxY, w.Sheep[i].Position.Y)
		}
		for _, i := range groups[1] {
			minY = math.Max(minY, w.Sheep[i].Position.Y)
		}
		if minY-maxY > 9 && w.Sheep[0].Group != w.Sheep[9].Group {
			split = true
			break
		}
	}
	if !split {
		t.Fatalf("normal-spawn flock did not split: %+v", w.Sheep)
	}
	// Retrieve each actual spatial group along its nearby pass, then regroup in
	// the same east pasture. Assignment is spatial, not a change to sheep state.
	groups = [][]int{{}, {}}
	for i, s := range w.Sheep {
		side := 0
		if s.Position.Y > 0 {
			side = 1
		}
		groups[side] = append(groups[side], i)
	}
	if len(groups[0]) == 0 || len(groups[1]) == 0 {
		t.Fatal("split did not create two retrievable sides")
	}
	for tick := 0; tick < 7000; tick++ {
		if tick%10 == 0 {
			for i, dog := range []string{"mochi", "maple"} {
				minX, minY := 17.0, 11.0
				sign := float64(i*2 - 1)
				for _, j := range groups[i] {
					minX = math.Min(minX, w.Sheep[j].Position.X)
					minY = math.Min(minY, w.Sheep[j].Position.Y*sign)
				}
				goal := Vec2{13, sign * 3}
				if minX < 5 {
					goal = Vec2{7, sign * 6.8}
				}
				if minX < -3.4 && minY < 4.6 {
					goal = Vec2{-6, sign * 6.8}
				}
				sendHerdDog(t, w, []string{"b", "a"}[i], dog, herdDogTarget(w, groups[i], goal, 0))
			}
		}
		stepOasisChecked(t, w)
		if w.Settled == 10 {
			t.Logf("split flock reunited in pasture at tick%d", w.Tick)
			return
		}
	}
	t.Fatalf("split retrieval stalled: settled%d sheep=%+v dogs=%+v", w.Settled, w.Sheep, w.Dogs)
}
