package game

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"testing"
)

func snakeRegion() Region {
	r := Region{RecipeID: "test_snake", Bounds: Bounds{Vec2{-60, -100}, Vec2{60, 100}}}
	for i := 0; i < 32; i++ {
		x := -40.0
		if i%4 == 1 || i%4 == 2 {
			x = 40
		}
		r.Anchors = append(r.Anchors, Vec2{x, -90 + float64(i/2)*6})
		if i > 0 {
			r.Corridors = append(r.Corridors, RegionCorridor{i - 1, i, 1.25 + float64(i%3)*.125})
		}
	}
	r.graph = compileRegionGraph(r)
	return r
}

func TestRegionVariableWidthsAndMoreThanSixRetainedAnchors(t *testing.T) {
	r := snakeRegion()
	if err := r.ValidateGeometry(); err != nil {
		t.Fatal(err)
	}
	from, target := r.Anchors[0], r.Anchors[31]
	route := RegionRoute(from, target, r)
	if len(route) <= 6 || len(route) > 32 || !validRegionRoute(from, target, route, r) {
		t.Fatal("large retained graph not exercised", route)
	}
	w := &World{Layout: &Layout{Version: 7, Region: &r}}
	p := from
	count := 0
	initialCount := len(route)
	for ; count < 9000 && p.Sub(target).Len() > .08; count++ {
		before := p
		p = w.moveOnRegion(p, target, 4, &route)
		if !RegionVisible(before, p, r) || p.Sub(before).Len() > .20000001 {
			t.Fatal("unsafe long variable-width route")
		}
	}
	if p.Sub(target).Len() > .08 {
		t.Fatal("long graph route stalled", p, route)
	}
	t.Logf("%d retained anchors,variable widths,full route in%d ticks", initialCount, count)
}

func TestRegionWholeChordRejectsNotchAndExplicitBounds(t *testing.T) {
	r := Region{RecipeID: "test_u", Bounds: Bounds{Vec2{-22, -3}, Vec2{22, 33}}, Anchors: []Vec2{{-20, 0}, {-20, 30}, {20, 30}, {20, 0}}, Corridors: []RegionCorridor{{0, 1, 4}, {1, 2, 4}, {2, 3, 4}}}
	if err := r.ValidateGeometry(); err != nil {
		t.Fatal(err)
	}
	if !RegionWalkable(Vec2{-20, 0}, r) || !RegionWalkable(Vec2{20, 0}, r) || RegionVisible(Vec2{-20, 0}, Vec2{20, 0}, r) {
		t.Fatal("endpoint-only shortcut across notch")
	}
	if RegionWalkable(Vec2{-23, 0}, r) || RegionVisible(Vec2{-22, 0}, Vec2{-23, 0}, r) || !RegionVisible(Vec2{-22, 0}, Vec2{-20, 0}, r) {
		t.Fatal("dry capsule ignored world bounds")
	}
	if !RegionVisible(Vec2{-20, 0}, Vec2{-20, 0}, r) || RegionVisible(Vec2{0, 0}, Vec2{0, 0}, r) {
		t.Fatal("zero length segment lost strict membership")
	}
}

func TestRegionGeometryRejectsMalformedRecipes(t *testing.T) {
	cases := []struct {
		name string
		edit func(*Region)
	}{
		{"too_many_anchors", func(r *Region) { r.Anchors = make([]Vec2, 33) }},
		{"too_few_anchors", func(r *Region) { r.Anchors = r.Anchors[:1] }},
		{"too_many_edges", func(r *Region) { r.Corridors = make([]RegionCorridor, 65) }},
		{"too_many_clearings", func(r *Region) { r.Clearings = make([]Shelf, 33) }},
		{"zero_edge", func(r *Region) { r.Corridors[0].B = r.Corridors[0].A }},
		{"negative_edge", func(r *Region) { r.Corridors[0].A = -1 }},
		{"overflow_edge", func(r *Region) { r.Corridors[0].B = 32 }},
		{"reversed_duplicate_edge", func(r *Region) { r.Corridors = append(r.Corridors, RegionCorridor{1, 0, 10}) }},
		{"nan_width", func(r *Region) { r.Corridors[0].HalfWidth = math.NaN() }},
		{"inf_width", func(r *Region) { r.Corridors[0].HalfWidth = math.Inf(1) }},
		{"negative_width", func(r *Region) { r.Corridors[0].HalfWidth = -1 }},
		{"nan_anchor", func(r *Region) { r.Anchors[0].X = math.NaN() }},
		{"outside_anchor", func(r *Region) { r.Anchors[0].X = -73 }},
		{"duplicate_anchor", func(r *Region) { r.Anchors[1] = r.Anchors[0] }},
		{"isolated_anchor", func(r *Region) { r.Anchors = append(r.Anchors, Vec2{}) }},
		{"orphan_clearing", func(r *Region) { r.Clearings[0].Center = Vec2{0, 90} }},
		{"nan_radius", func(r *Region) { r.Clearings[0].Radius = math.NaN() }},
		{"zero_radius", func(r *Region) { r.Clearings[0].Radius = 0 }},
		{"inf_bounds", func(r *Region) { r.Bounds.Max.X = math.Inf(1) }},
		{"huge_bounds", func(r *Region) { r.Bounds = Bounds{Vec2{-512, -512}, Vec2{512, 512}} }},
		{"reversed_bounds", func(r *Region) { r.Bounds.Min.X = 100 }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := canonicalRegion()
			tc.edit(r)
			if r.ValidateGeometry() == nil {
				t.Fatal("malformed geometry accepted")
			}
		})
	}
}

func TestRegionGeometryRejectsUnderflowedEdgeLength(t *testing.T) {
	r := Region{RecipeID: "tiny_edge", Bounds: Bounds{Vec2{-1, -1}, Vec2{1, 1}}, Anchors: []Vec2{{0, 0}, {1e-200, 0}}, Corridors: []RegionCorridor{{0, 1, .5}}}
	if r.ValidateGeometry() == nil {
		t.Fatal("distinct anchors whose squared distance underflows must reject before division")
	}
	// This is an exact representability check, not a widened collision epsilon.
	r.Anchors[1].X = 1e-150
	if err := r.ValidateGeometry(); err != nil {
		t.Fatal("representable nonzero squared length should remain valid", err)
	}
}

type regionBits struct {
	X string `json:"x"`
	Y string `json:"y"`
}
type regionBoundaryFixture struct {
	regionFixture
	FromBits   regionBits `json:"from_bits"`
	TargetBits regionBits `json:"target_bits"`
}

func TestRegionSharedExactBoundaryBits(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/region-boundaries.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []regionBoundaryFixture
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 28 {
		t.Fatal("missing exact boundaries")
	}
	bits := func(p Vec2) regionBits {
		return regionBits{fmt.Sprintf("%016x", math.Float64bits(p.X)), fmt.Sprintf("%016x", math.Float64bits(p.Y))}
	}
	r := *regionWorld(t).Layout.Region
	for _, f := range fixtures {
		if bits(f.From) != f.FromBits || bits(f.Target) != f.TargetBits {
			t.Fatal("boundary decimal/IEEE754 disagreement", f.Name)
		}
		assertRegionFixture(t, r, f.regionFixture)
	}
}

func TestRegionSharedThirtyAnchorStress(t *testing.T) {
	data, err := os.ReadFile("../../../protocol/region-stress.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Region Region          `json:"region"`
		Cases  []regionFixture `json:"cases"`
	}
	if err = json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	r := snakeRegion()
	if !r.equal(&fixture.Region) || len(fixture.Cases) != 2 {
		t.Fatal("stress recipe changed")
	}
	for _, f := range fixture.Cases {
		route := RegionRoute(f.From, f.Target, r)
		if len(route) != 30 || len(f.Route) != 30 {
			t.Fatal("stress fixture lost long queue")
		}
		for i, p := range route {
			if p != r.Anchors[f.Route[i]] {
				t.Fatal("stress route changed", f.Name)
			}
		}
	}
}

func BenchmarkRegionCachedRoute(b *testing.B) {
	r := canonicalRegion()
	r.graph = compileRegionGraph(*r)
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		RegionRoute(Vec2{-48, 74}, r.Anchors[13], *r)
	}
}
func BenchmarkRegion32AnchorRoute(b *testing.B) {
	r := snakeRegion()
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		RegionRoute(r.Anchors[0], r.Anchors[31], r)
	}
}
