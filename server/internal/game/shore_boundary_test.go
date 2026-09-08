package game

import (
	"encoding/json"
	"math"
	"math/rand"
	"os"
	"testing"
)

func shoreBoundaryPoints() []Vec2 {
	s := *canonicalShore()
	var points []Vec2
	add := func(p Vec2) {
		if ShoreWalkable(p, s) {
			points = append(points, p)
		}
	}
	margins := []float64{0, 1e-12, 1e-9, 1e-6, .001, .03}
	for _, c := range s.Clearings {
		for angle := 0; angle < 72; angle++ {
			a := float64(angle) * math.Pi / 36
			for _, m := range margins {
				add(c.Center.Add(Vec2{math.Cos(a), math.Sin(a)}.Mul(c.Radius - m)))
			}
		}
	}
	for i := 1; i < len(s.Path); i++ {
		a, b := s.Path[i-1], s.Path[i]
		d := b.Sub(a)
		normal := Vec2{-d.Y, d.X}.Unit()
		for _, u := range []float64{0, .000001, .01, .2, .5, .8, .99, .999999, 1} {
			for _, sign := range []float64{-1, 1} {
				for _, m := range margins {
					add(a.Add(d.Mul(u)).Add(normal.Mul(sign * (s.HalfWidth - m))))
				}
			}
		}
	}
	return append(points, s.Path...)
}

func TestShoreBoundaryConnectivityAndMotion(t *testing.T) {
	w := shoreWorld(t)
	s := *w.Layout.Shore
	points := shoreBoundaryPoints()
	rng := rand.New(rand.NewSource(13013))
	for i, p := range points {
		visible := 0
		for _, anchor := range s.Path {
			if ShoreVisible(p, anchor, s) {
				visible++
			}
		}
		if visible == 0 {
			t.Fatalf("legal boundary point has no visible anchor #%d p=%#.17g", i, p)
		}
	}
	for trial := 0; trial < 2500; trial++ {
		from, target := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		route := ShoreRoute(from, target, s)
		if !validShoreRoute(from, target, route, s) || (!ShoreVisible(from, target, s) && len(route) == 0) {
			t.Fatalf("unroutable legal pair from=%#.17g target=%#.17g route=%v", from, target, route)
		}
		p := from
		for tick := 0; tick < 650 && p.Sub(target).Len() > .08; tick++ {
			before := p
			p = w.moveOnShore(p, target, 4, &route)
			if !ShoreVisible(before, p, s) || p.Sub(before).Len() > 4.0/TickRate+1e-8 {
				t.Fatalf("unsafe motion from=%#.17g target=%#.17g step=%#.17g->%#.17g", from, target, before, p)
			}
		}
		if p.Sub(target).Len() > .08 {
			t.Fatalf("stalled boundary route from=%#.17g target=%#.17g p=%#.17g route=%v", from, target, p, route)
		}
	}
	t.Logf("%d boundary points and2500 actual motion routes passed", len(points))
}

func TestShoreBoundaryWholeSegmentAndSymmetry(t *testing.T) {
	s := *canonicalShore()
	points := shoreBoundaryPoints()
	rng := rand.New(rand.NewSource(13130))
	visible := 0
	margin := func(p Vec2) float64 {
		best := math.Inf(-1)
		for _, c := range s.Clearings {
			best = math.Max(best, c.Radius-math.Hypot(p.X-c.Center.X, p.Y-c.Center.Y))
		}
		for i := 1; i < len(s.Path); i++ {
			a, b := s.Path[i-1], s.Path[i]
			dx, dy := b.X-a.X, b.Y-a.Y
			u := math.Max(0, math.Min(1, ((p.X-a.X)*dx+(p.Y-a.Y)*dy)/(dx*dx+dy*dy)))
			best = math.Max(best, s.HalfWidth-math.Hypot(p.X-a.X-u*dx, p.Y-a.Y-u*dy))
		}
		return best
	}
	worst := 0.0
	for trial := 0; trial < 20000; trial++ {
		a, b := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		if ShoreVisible(a, b, s) != ShoreVisible(b, a, s) {
			t.Fatalf("asymmetric visibility a=%#.17g b=%#.17g", a, b)
		}
		if !ShoreVisible(a, b, s) {
			continue
		}
		visible++
		for i := 0; i <= 200; i++ {
			p := a.Add(b.Sub(a).Mul(float64(i) / 200))
			m := margin(p)
			worst = math.Min(worst, m)
			if m < -1e-10 {
				t.Fatalf("visible segment crosses dry boundary by %.17g a=%#.17g b=%#.17g p=%#.17g", -m, a, b, p)
			}
		}
	}
	t.Logf("20000 random pairs, %d visible checked at201 independent distance probes each; minimum signed margin %g", visible, worst)
}

func TestShoreBoundaryRepeatedRetargetsAndQuietStops(t *testing.T) {
	w := shoreWorld(t)
	rng := rand.New(rand.NewSource(13513))
	goals := []Vec2{{-11, 2}, {-8, -3}, {-3, -6}, {4, -6}, {9, -2}, {11, 4}, {-15, 2}, {14, 6}, {2, -8}}
	for turn := 0; turn < 120; turn++ {
		target := goals[rng.Intn(len(goals))]
		for i, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(turn + 1), Target: &target}); err != nil {
				t.Fatal(err)
			}
			command := "go"
			if turn%3 == 0 {
				command = "come"
			}
			if err := w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[i], Command: command, Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		for tick := 0; tick < 25; tick++ {
			stepShoreChecked(t, w)
		}
	}
	target := Vec2{11, 4}
	for i, id := range []string{"a", "b"} {
		_ = w.Apply(id, Input{Type: "move", Seq: 999, Target: &target})
		_ = w.Apply(id, Input{Type: "command", DogID: []string{"mochi", "maple"}[i], Command: "go", Target: &target})
	}
	for tick := 0; tick < 650; tick++ {
		stepShoreChecked(t, w)
	}
	for _, p := range w.Players {
		if p.Position.Sub(target).Len() > .08 || p.State != "idle" || len(p.Route) != 0 {
			t.Fatal("retargeted herder stalled", p)
		}
	}
	for _, d := range w.Dogs {
		if d.Position.Sub(target).Len() > .15 || d.State != "attentive" || len(d.Route) != 0 {
			t.Fatal("retargeted dog stalled", d)
		}
	}
	t.Log("120 normal-spawn retarget rounds, moving Come callers, then final quiet arrivals passed")
}

func TestShoreBoundarySharedLiteralRegressions(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/shore-boundaries.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Name    string `json:"name"`
		From    Vec2   `json:"from"`
		Target  Vec2   `json:"target"`
		Visible bool   `json:"visible"`
	}
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 14 {
		t.Fatal("incomplete boundary fixtures")
	}
	w := shoreWorld(t)
	s := *w.Layout.Shore
	for _, f := range fixtures {
		if ShoreVisible(f.From, f.Target, s) != f.Visible || ShoreVisible(f.Target, f.From, s) != f.Visible {
			t.Fatalf("%s boundary visibility differs", f.Name)
		}
		if !f.Visible {
			continue
		}
		p := f.From
		var route []Vec2
		for tick := 0; tick < 300 && p.Sub(f.Target).Len() > .08; tick++ {
			before := p
			p = w.moveOnShore(p, f.Target, 4, &route)
			if !ShoreVisible(before, p, s) || p.Sub(before).Len() > 4.0/TickRate+1e-8 {
				t.Fatal("unsafe boundary movement")
			}
		}
		if p.Sub(f.Target).Len() > .08 {
			t.Fatalf("%s boundary route stalled at %v", f.Name, p)
		}
	}
}
