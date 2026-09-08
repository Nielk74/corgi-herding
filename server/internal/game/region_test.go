package game

import (
	"encoding/json"
	"math"
	"math/rand"
	"os"
	"reflect"
	"slices"
	"testing"
)

func TestRegionCanonicalGeometrySpawnsBoundsAndClone(t *testing.T) {
	w := regionWorld(t)
	r := *w.Layout.Region
	data, err := os.ReadFile("../../../protocol/alpine-valley-region.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture Region
	if err = json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	if !r.equal(&fixture) {
		t.Fatal("recipe JSON differs from authoritative geometry")
	}
	if len(r.Anchors) != 16 || len(r.Corridors) != 26 || len(r.Clearings) != 16 || r.Bounds != (Bounds{Vec2{-72, -96}, Vec2{72, 96}}) {
		t.Fatal("candidate changed")
	}
	if err = r.ValidateGeometry(); err != nil {
		t.Fatal(err)
	}
	if (Vec2{-48, 74}).Valid() || !w.ValidPoint(Vec2{-48, 74}) {
		t.Fatal("new bounds leaked into legacy Vec2.Valid")
	}
	for _, legacy := range []string{LandscapeAlpine, LandscapeCactus, LandscapeLarch, LandscapeOrchard, LandscapeOasis, LandscapeCloud, LandscapeJuniper, LandscapeBellflower} {
		old := NewForLandscape("ABCDEF", legacy)
		_ = old.AddPlayer("a", "a")
		if old.ValidPoint(Vec2{18, 0}) || old.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{18, 0}}) == nil {
			t.Fatal("old input bounds widened", legacy)
		}
		if !old.SupportsLayout(7) {
			t.Fatal("new client lost old world", legacy)
		}
	}
	for _, cap := range []int{-1, 0, 1, 2, 3, 4, 5, 6, 8, 99} {
		if w.SupportsLayout(cap) {
			t.Fatal("unsupported region capability", cap)
		}
	}
	copy := w.Clone()
	copy.Layout.Region.Anchors[0].X++
	copy.Layout.Region.Corridors[0].HalfWidth++
	copy.Layout.Region.Clearings[0].Radius++
	copy.Layout.Region.Bounds.Min.X++
	if !w.Layout.Region.equal(&fixture) {
		t.Fatal("region clone aliases live layout")
	}
	for _, s := range w.Sheep {
		for _, d := range w.Dogs {
			if s.Position.Sub(d.Position).Len() < 4.1 {
				t.Fatal("initial dog pressure")
			}
		}
	}
	for _, p := range []Vec2{{72.001, 0}, {0, 96.001}, {0, -96.001}, {72, 96}, {math.NaN(), 0}, {math.Inf(1), 0}} {
		if RegionWalkable(p, r) || RegionVisible(p, r.Anchors[0], r) || RegionVisible(r.Anchors[0], p, r) {
			t.Fatal("invalid endpoint accepted", p)
		}
	}
	if !RegionWalkable(Vec2{44, -96}, r) || RegionWalkable(Vec2{44, math.Nextafter(-96, math.Inf(-1))}, r) {
		t.Fatal("strict region/bounds edge changed")
	}
}

func TestRegionGraphCacheMatchesExactVisibility(t *testing.T) {
	r := *regionWorld(t).Layout.Region
	uncached := r
	uncached.graph = nil
	blocked := 0
	for i, a := range r.Anchors {
		for j, b := range r.Anchors {
			if i != j && r.graph.visible[i][j] != RegionVisible(a, b, r) {
				t.Fatal("cached edge differs", i, j)
			}
			if !reflect.DeepEqual(RegionRoute(a, b, r), RegionRoute(a, b, uncached)) {
				t.Fatal("cached planner differs", i, j)
			}
			if !RegionVisible(a, b, r) {
				blocked++
			}
		}
	}
	if blocked == 0 {
		t.Fatal("fixture never exercises graph navigation")
	}
	for _, e := range r.Corridors {
		if !r.graph.visible[e.A][e.B] {
			t.Fatal("declared capsule not navigable")
		}
	}
	t.Logf("%d directed anchor pairs require a route", blocked)
}

func TestRegionBothHerdersDogsAllAnchorsRetargetAndQuietStop(t *testing.T) {
	w := regionWorld(t)
	targets := slices.Clone(w.Layout.Region.Anchors)
	targets = append(targets, Vec2{44, -95.9}, Vec2{-68.9, -10})
	reverse := slices.Clone(targets)
	slices.Reverse(reverse)
	targets = append(targets, reverse...)
	for leg, target := range targets {
		for _, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(leg + 1), Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		for i, dog := range []string{"mochi", "maple"} {
			sendHerdDog(t, w, []string{"a", "b"}[i], dog, target)
		}
		for tick := 0; tick < 2200; tick++ {
			stepRegionChecked(t, w)
			if w.Players[0].State == "idle" && w.Players[1].State == "idle" && w.Dogs[0].State == "attentive" && w.Dogs[1].State == "attentive" {
				break
			}
		}
		for _, p := range w.Players {
			if p.Position.Sub(target).Len() > .08 || p.State != "idle" || len(p.Route) > 0 {
				t.Fatal("herder failed large route", leg, p)
			}
		}
		for _, d := range w.Dogs {
			if d.Position.Sub(target).Len() > .15 || len(d.Route) > 0 {
				t.Fatal("corgi failed large route", leg, d)
			}
		}
	}
	for turn := 0; turn < 100; turn++ {
		target := w.Layout.Region.Anchors[(turn*7)%16]
		if err := w.Apply("a", Input{Type: "move", Seq: uint64(100 + turn), Target: &target}); err != nil {
			t.Fatal(err)
		}
		sendHerdDog(t, w, "b", "mochi", target)
		if err := w.Apply("a", Input{Type: "command", DogID: "maple", Command: "come"}); err != nil {
			t.Fatal(err)
		}
		for tick := 0; tick < 7; tick++ {
			stepRegionChecked(t, w)
		}
	}
	for _, id := range []string{"a", "b"} {
		_ = w.Apply(id, Input{Type: "interact", Action: "sit"})
	}
	for _, dog := range []string{"mochi", "maple"} {
		_ = w.Apply("a", Input{Type: "command", DogID: dog, Command: "stay"})
	}
	before := w.Clone()
	for tick := 0; tick < 40; tick++ {
		stepRegionChecked(t, w)
	}
	for i, p := range w.Players {
		if p.Position != before.Players[i].Position || len(p.Route) != 0 {
			t.Fatal("sit did not stop")
		}
	}
	for i, d := range w.Dogs {
		if d.Position != before.Dogs[i].Position || len(d.Route) != 0 {
			t.Fatal("stay did not stop")
		}
	}
}

func regionBoundaryPoints(r Region) []Vec2 {
	points := []Vec2{}
	for _, c := range r.Clearings {
		for angle := 0; angle < 72; angle++ {
			theta := float64(angle) * math.Pi / 36
			p := c.Center.Add(Vec2{math.Cos(theta), math.Sin(theta)}.Mul(c.Radius))
			if RegionWalkable(p, r) {
				points = append(points, p)
			}
		}
	}
	for _, e := range r.Corridors {
		a, b := r.Anchors[e.A], r.Anchors[e.B]
		axis := b.Sub(a).Unit()
		normal := Vec2{-axis.Y, axis.X}
		for _, u := range []float64{0, .000001, .01, .2, .5, .8, .99, .999999, 1} {
			for _, side := range []float64{-1, 1} {
				p := a.Add(b.Sub(a).Mul(u)).Add(normal.Mul(e.HalfWidth * side))
				if RegionWalkable(p, r) {
					points = append(points, p)
				}
			}
		}
	}
	return points
}

func TestRegionBoundaryConnectivitySymmetryAndWholeMotion(t *testing.T) {
	w := regionWorld(t)
	r := *w.Layout.Region
	points := regionBoundaryPoints(r)
	rng := rand.New(rand.NewSource(703))
	for _, p := range points {
		connected := false
		for _, a := range r.Anchors {
			if RegionVisible(p, a, r) {
				connected = true
				break
			}
		}
		if !connected {
			t.Fatalf("legal boundary stranded %#.17g", p)
		}
	}
	for trial := 0; trial < 10000; trial++ {
		a, b := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		if RegionVisible(a, b, r) != RegionVisible(b, a, r) {
			t.Fatalf("asymmetric %.17g %.17g", a, b)
		}
	}
	for trial := 0; trial < 300; trial++ {
		from, target := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		route := RegionRoute(from, target, r)
		p := from
		for tick := 0; tick < 2200 && p.Sub(target).Len() > .08; tick++ {
			before := p
			p = w.moveOnRegion(p, target, 4, &route)
			if p.Sub(before).Len() > 4.0/TickRate+1e-8 || !RegionVisible(before, p, r) {
				t.Fatalf("unsafe boundary motion %#.17g -> %#.17g", before, p)
			}
		}
		if p.Sub(target).Len() > .08 {
			t.Fatalf("stalled boundary route %#.17g -> %#.17g at %#.17g route%v", from, target, p, route)
		}
	}
	t.Logf("%d legal boundary points,10000 symmetric pairs,300 full routes", len(points))
}

type regionFixture struct {
	Name    string `json:"name"`
	From    Vec2   `json:"from"`
	Target  Vec2   `json:"target"`
	Visible bool   `json:"visible"`
	Route   []int  `json:"route"`
}

func assertRegionFixture(t *testing.T, r Region, f regionFixture) {
	t.Helper()
	if RegionVisible(f.From, f.Target, r) != f.Visible || RegionVisible(f.Target, f.From, r) != f.Visible {
		t.Fatal("shared visibility changed", f.Name)
	}
	route := RegionRoute(f.From, f.Target, r)
	indices := []int{}
	for _, p := range route {
		indices = append(indices, slices.Index(r.Anchors, p))
	}
	if !slices.Equal(indices, f.Route) {
		t.Fatal("shared route changed", f.Name, indices, f.Route)
	}
	if RegionWalkable(f.From, r) && RegionWalkable(f.Target, r) {
		if len(route) == 0 && !f.Visible {
			t.Fatal("legal fixture has no route", f.Name)
		}
		p := f.From
		w := &World{Layout: &Layout{Version: 7, Region: &r}}
		for tick := 0; tick < 2200 && p.Sub(f.Target).Len() > .08; tick++ {
			before := p
			p = w.moveOnRegion(p, f.Target, 4, &route)
			if !RegionVisible(before, p, r) || p.Sub(before).Len() > .20000001 {
				t.Fatal("unsafe shared route", f.Name)
			}
		}
		if p.Sub(f.Target).Len() > .08 {
			t.Fatal("shared route stalled", f.Name)
		}
	} else if len(route) > 0 {
		t.Fatal("invalid endpoint planned", f.Name)
	}
}

func TestRegionSharedRoutes(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/region-routes.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []regionFixture
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 64 {
		t.Fatal("missing shared routes")
	}
	r := *regionWorld(t).Layout.Region
	for _, f := range fixtures {
		assertRegionFixture(t, r, f)
	}
}

func TestRegionSameDiskRoundingIndependentOfInlining(t *testing.T) {
	w := regionWorld(t)
	r := *w.Layout.Region
	p, target := Vec2{16.855752193730787, 39.320888862379562}, Vec2{8.7059123529411764, 32.823513411764708}
	if !RegionWalkable(p, r) || !RegionVisible(p, target, r) || !RegionVisible(target, p, r) {
		t.Fatal("identical closed-disk membership differs between call sites")
	}
	route := RegionRoute(p, target, r)
	for tick := 0; tick < 70 && p.Sub(target).Len() > .08; tick++ {
		before := p
		p = w.moveOnRegion(p, target, 4, &route)
		if p == before || !RegionVisible(before, p, r) {
			t.Fatal("legal disk boundary stalled")
		}
	}
	if p.Sub(target).Len() > .08 {
		t.Fatal("did not finish regression chord")
	}
}
