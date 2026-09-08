package game

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"os"
	"reflect"
	"testing"
)

func TestCommonsCanonicalAdapterSpawnsAndClone(t *testing.T) {
	w := commonsWorld(t)
	c := *w.Layout.Commons
	if w.Layout.Version != 6 || w.Layout.Shore != nil || w.Layout.Ridge != nil || w.Layout.RockPass != nil || w.Layout.Forage != nil || w.Layout.GateY != 0 || w.Layout.BridgeY != 0 {
		t.Fatal("inherited geometry")
	}
	expected := []int{0, 1, 2, 3, 2, 1, 4, 5}
	adapter := c.shore()
	declared := map[[2]int]bool{}
	seen := map[[2]int]bool{}
	edgeKey := func(a, b int) [2]int {
		if a > b {
			a, b = b, a
		}
		return [2]int{a, b}
	}
	for _, e := range c.Corridors {
		declared[edgeKey(e[0], e[1])] = true
	}
	for i, index := range expected {
		if adapter.Path[i] != c.Anchors[index] {
			t.Fatal("adapter order drift")
		}
		if i > 0 {
			key := edgeKey(expected[i-1], index)
			if !declared[key] {
				t.Fatal("invented terrain edge", key)
			}
			seen[key] = true
		}
	}
	if !reflect.DeepEqual(declared, seen) {
		t.Fatal("lost declared edge")
	}
	// Flattening the six unique anchors would create a phantom 3->4 capsule.
	phantom := Shore{Path: c.Anchors, HalfWidth: c.HalfWidth, Clearings: c.Clearings}
	if !ShoreWalkable(Vec2{7, 0}, phantom) || CommonsWalkable(Vec2{7, 0}, c) {
		t.Fatal("fork divider disappeared")
	}
	if CommonsVisible(Vec2{10, -6}, Vec2{10, 6}, c) {
		t.Fatal("cross-branch shortcut")
	}
	for _, p := range w.Players {
		if !inShelf(p.Position, c.Clearings[0]) {
			t.Fatal("herder outside central meadow")
		}
	}
	for _, d := range w.Dogs {
		if !inShelf(d.Position, c.Clearings[0]) {
			t.Fatal("dog outside central meadow")
		}
	}
	for _, s := range w.Sheep {
		if !inShelf(s.Position, c.Clearings[0]) {
			t.Fatal("sheep outside central meadow")
		}
	}
	for i, id := range []string{"a", "b"} {
		if err := w.Apply(id, Input{Type: "interact", Action: "pet", DogID: []string{"mochi", "maple"}[i]}); err != nil {
			t.Fatal("spawn prevents affection", err)
		}
	}
	clone := w.Clone()
	clone.Layout.Commons.Anchors[0].X = 99
	clone.Layout.Commons.Corridors[0][0] = 99
	clone.Layout.Commons.Clearings[0].Radius = 99
	if !w.Layout.Equal(LayoutForLandscape(LandscapeBellflower)) || clone.ValidateLayout() == nil {
		t.Fatal("mutable canonical layout")
	}
	for _, p := range []Vec2{{7, 0}, {18, 0}, {0, 12}, {math.NaN(), 0}, {math.Inf(1), 0}} {
		if w.Walkable(p) || CommonsVisible(p, Vec2{-5, 0}, c) || CommonsVisible(Vec2{-5, 0}, p, c) || len(CommonsRoute(p, Vec2{-5, 0}, c)) != 0 {
			t.Fatal("invalid endpoint accepted", p)
		}
	}
}

func TestCommonsSharedRoutesAndExactBoundaryBits(t *testing.T) {
	c := *canonicalCommons()
	for _, file := range []struct {
		name  string
		count int
	}{{"commons-routes.json", 32}, {"commons-boundaries.json", 20}} {
		data, err := os.ReadFile("../../../protocol/" + file.name)
		if err != nil {
			t.Fatal(err)
		}
		var fixtures []struct {
			Name       string            `json:"name"`
			From       Vec2              `json:"from"`
			Target     Vec2              `json:"target"`
			Visible    bool              `json:"visible"`
			Route      []int             `json:"route"`
			FromBits   map[string]string `json:"from_bits"`
			TargetBits map[string]string `json:"target_bits"`
		}
		if err = json.Unmarshal(data, &fixtures); err != nil {
			t.Fatal(err)
		}
		if len(fixtures) != file.count {
			t.Fatal("incomplete fixtures")
		}
		for _, f := range fixtures {
			if CommonsVisible(f.From, f.Target, c) != f.Visible || CommonsVisible(f.Target, f.From, c) != f.Visible {
				t.Fatal("fixture visibility", f.Name)
			}
			if file.name == "commons-boundaries.json" {
				for i, p := range []Vec2{f.From, f.Target} {
					bits := []map[string]string{f.FromBits, f.TargetBits}[i]
					if bits["x"] != fmt.Sprintf("%016x", math.Float64bits(p.X)) || bits["y"] != fmt.Sprintf("%016x", math.Float64bits(p.Y)) {
						t.Fatal("IEEE754 fixture/JSON mismatch", f.Name)
					}
				}
				continue
			}
			got := []int{}
			for _, p := range CommonsRoute(f.From, f.Target, c) {
				for i, a := range c.Anchors {
					if p == a {
						got = append(got, i)
					}
				}
			}
			if !reflect.DeepEqual(got, f.Route) {
				t.Fatal("fixture route", f.Name, got, f.Route)
			}
		}
	}
}

func commonsBoundaryPoints() []Vec2 {
	c := *canonicalCommons()
	var points []Vec2
	add := func(p Vec2) {
		if CommonsWalkable(p, c) {
			points = append(points, p)
		}
	}
	for _, disk := range c.Clearings {
		for angle := 0; angle < 72; angle++ {
			a := float64(angle) * math.Pi / 36
			for _, m := range []float64{0, 1e-12, 1e-9, 1e-6, .01} {
				add(disk.Center.Add(Vec2{math.Cos(a), math.Sin(a)}.Mul(disk.Radius - m)))
			}
		}
	}
	for _, e := range c.Corridors {
		a, b := c.Anchors[e[0]], c.Anchors[e[1]]
		d := b.Sub(a)
		n := Vec2{-d.Y, d.X}.Unit()
		for _, u := range []float64{0, .001, .2, .5, .8, .999, 1} {
			for _, sign := range []float64{-1, 1} {
				for _, m := range []float64{0, 1e-12, 1e-9, 1e-6, .01} {
					add(a.Add(d.Mul(u)).Add(n.Mul(sign * (c.HalfWidth - m))))
				}
			}
		}
	}
	return append(points, c.Anchors...)
}

func TestCommonsBoundaryConnectivitySymmetryAndSafeMotion(t *testing.T) {
	w := commonsWorld(t)
	c := *w.Layout.Commons
	points := commonsBoundaryPoints()
	rng := rand.New(rand.NewSource(14631))
	for _, p := range points {
		connected := false
		for _, a := range c.Anchors {
			if CommonsVisible(p, a, c) {
				connected = true
				break
			}
		}
		if !connected {
			t.Fatalf("legal point stranded: %#.17g", p)
		}
	}
	for trial := 0; trial < 20000; trial++ {
		a, b := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		if CommonsVisible(a, b, c) != CommonsVisible(b, a, c) {
			t.Fatalf("asymmetric %#.17g %#.17g", a, b)
		}
	}
	for trial := 0; trial < 2500; trial++ {
		from, target := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		route := CommonsRoute(from, target, c)
		if !validCommonsRoute(from, target, route, c) || (!CommonsVisible(from, target, c) && len(route) == 0) {
			t.Fatal("legal points disconnected")
		}
		p := from
		for tick := 0; tick < 650 && p.Sub(target).Len() > .08; tick++ {
			before := p
			p = w.moveOnCommons(p, target, 4, &route)
			if !CommonsVisible(before, p, c) || p.Sub(before).Len() > 4.0/TickRate+1e-8 {
				t.Fatal("unsafe boundary step")
			}
		}
		if p.Sub(target).Len() > .08 {
			t.Fatalf("stalled route %#.17g -> %#.17g at %#.17g", from, target, p)
		}
	}
	t.Logf("%d legal boundary points,20000 symmetric pairs,2500 actual safe routes", len(points))
}

func TestCommonsBothHerdersDogsRetargetComeAndQuietArrival(t *testing.T) {
	w := commonsWorld(t)
	goals := []Vec2{{10, -6}, {10, 6}, {-5, 0}, {14, -8}, {14, 8}, {-10, -1}}
	for turn, target := range goals {
		for i, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(turn + 1), Target: &target}); err != nil {
				t.Fatal(err)
			}
			sendHerdDog(t, w, id, []string{"mochi", "maple"}[i], target)
		}
		for tick := 0; tick < 500; tick++ {
			stepCommonsChecked(t, w)
		}
		for _, p := range w.Players {
			if p.Position.Sub(target).Len() > .08 || p.State != "idle" || len(p.Route) != 0 {
				t.Fatal("herder did not quietly arrive")
			}
		}
		for _, d := range w.Dogs {
			if d.Position.Sub(target).Len() > .15 || d.State != "attentive" || len(d.Route) != 0 {
				t.Fatal("dog did not quietly arrive")
			}
		}
	}
	rng := rand.New(rand.NewSource(61431))
	for turn := 0; turn < 120; turn++ {
		target := goals[rng.Intn(len(goals))]
		for i, id := range []string{"a", "b"} {
			_ = w.Apply(id, Input{Type: "move", Seq: uint64(turn + 100), Target: &target})
			command := "go"
			if turn%3 == 0 {
				command = "come"
			}
			if err := w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[i], Command: command, Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		for tick := 0; tick < 25; tick++ {
			stepCommonsChecked(t, w)
		}
	}
	for i, id := range []string{"a", "b"} {
		_ = w.Apply(id, Input{Type: "interact", Action: "sit"})
		_ = w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[i], Command: "stay"})
	}
	before := w.Clone()
	for tick := 0; tick < 40; tick++ {
		stepCommonsChecked(t, w)
	}
	for i, p := range w.Players {
		if p.Position != before.Players[i].Position || len(p.Route) != 0 {
			t.Fatal("sit moved")
		}
	}
	for i, d := range w.Dogs {
		if d.Position != before.Dogs[i].Position || len(d.Route) != 0 {
			t.Fatal("stay moved")
		}
	}
}

func TestCommonsEveryClearingSupportsNaturalQuietGrazing(t *testing.T) {
	for _, sign := range []float64{-1, 1} {
		w := commonsWorld(t)
		guideCommonsGroup(t, w, []Vec2{{4, sign * 4}, {10, sign * 6}}, "quiet branch approach")
		sendHerdDog(t, w, "a", "mochi", Vec2{-10, -3})
		sendHerdDog(t, w, "b", "maple", Vec2{-10, 3})
		for tick := 0; tick < 400; tick++ {
			stepCommonsChecked(t, w)
		}
		for _, s := range w.Sheep {
			if s.State != "grazing" {
				t.Fatal("branch did not settle quietly", s)
			}
		}
		guideCommonsGroup(t, w, []Vec2{{4, sign * 4}, {0, 0}, {-5, 0}}, "quiet central return")
		sendHerdDog(t, w, "a", "mochi", Vec2{10, -6})
		sendHerdDog(t, w, "b", "maple", Vec2{10, 6})
		for tick := 0; tick < 400; tick++ {
			stepCommonsChecked(t, w)
		}
		for _, s := range w.Sheep {
			if s.State != "grazing" {
				t.Fatal("central meadow did not settle quietly", s)
			}
		}
	}
	c := *canonicalCommons()
	for _, clearing := range c.Clearings {
		if cloudSheepSteering(clearing.Center, Vec2{}, 0, c.shore().corridor()) != (Vec2{}) {
			t.Fatal("automatic destination attraction")
		}
	}
}
