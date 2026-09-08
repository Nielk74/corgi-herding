package game

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"math"
	"slices"
	"sort"
)

const (
	MaxRegionAnchors   = 32
	MaxRegionCorridors = 64
	MaxRegionClearings = 32
)

// Bounds belongs to a new immutable recipe. Vec2.Valid remains the legacy
// 34x22 contract; widening it would also widen old saves and old inputs.
type Bounds struct {
	Min Vec2 `json:"min"`
	Max Vec2 `json:"max"`
}

func finitePoint(p Vec2) bool {
	return !math.IsNaN(p.X) && !math.IsNaN(p.Y) && !math.IsInf(p.X, 0) && !math.IsInf(p.Y, 0)
}

func (b Bounds) Contains(p Vec2) bool {
	return finitePoint(p) && p.X >= b.Min.X && p.X <= b.Max.X && p.Y >= b.Min.Y && p.Y <= b.Max.Y
}

type RegionCorridor struct {
	A         int     `json:"a"`
	B         int     `json:"b"`
	HalfWidth float64 `json:"half_width"`
}

func (e *RegionCorridor) UnmarshalJSON(data []byte) error {
	var fields struct {
		A         *int     `json:"a"`
		B         *int     `json:"b"`
		HalfWidth *float64 `json:"half_width"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&fields); err != nil {
		return err
	}
	if fields.A == nil || fields.B == nil || fields.HalfWidth == nil {
		return errors.New("region corridor requires a, b and half_width")
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("invalid region corridor JSON")
	}
	e.A, e.B, e.HalfWidth = *fields.A, *fields.B, *fields.HalfWidth
	return nil
}

// Region is a bounded explicit graph of dry capsules and broad meadow disks.
// Corridors define terrain, not compulsory paths: any wholly dry chord is legal.
// The unexported navigation cache is immutable, never serialized or supplied by
// a client, and is shared only by exact deep clones of the same recipe.
type Region struct {
	RecipeID  string           `json:"recipe_id"`
	Bounds    Bounds           `json:"bounds"`
	Anchors   []Vec2           `json:"anchors"`
	Corridors []RegionCorridor `json:"corridors"`
	Clearings []Shelf          `json:"clearings"`
	graph     *regionGraph
}

func canonicalRegion() *Region {
	r := &Region{RecipeID: "alpine_valley_01", Bounds: Bounds{Vec2{-72, -96}, Vec2{72, 96}},
		Anchors:   []Vec2{{-42, 64}, {-25, 43}, {-32, 16}, {-8, -10}, {10, -40}, {30, -63}, {44, -78}, {-7, 60}, {-50, 40}, {4, 24}, {-51, -10}, {19, -6}, {-24, -40}, {44, -36}, {3, -68}, {34, 8}},
		Corridors: []RegionCorridor{{0, 1, 10}, {1, 2, 10}, {2, 3, 10}, {3, 4, 10}, {4, 5, 10}, {5, 6, 10}, {0, 7, 10}, {7, 1, 10}, {0, 8, 10}, {8, 2, 10}, {1, 9, 10}, {9, 3, 10}, {2, 10, 10}, {10, 3, 10}, {10, 12, 10}, {3, 11, 10}, {11, 4, 10}, {3, 12, 10}, {12, 4, 10}, {12, 14, 10}, {4, 13, 10}, {13, 5, 10}, {4, 14, 10}, {14, 5, 10}, {9, 15, 10}, {15, 11, 10}}}
	for i, center := range r.Anchors {
		radius := 18.0
		if i == 3 {
			radius = 22
		} else if i == 9 || i == 11 {
			radius = 20
		}
		r.Clearings = append(r.Clearings, Shelf{center, radius})
	}
	return r
}

func (r *Region) equal(other *Region) bool {
	if r == nil || other == nil {
		return r == other
	}
	return r.RecipeID == other.RecipeID && r.Bounds == other.Bounds && slices.Equal(r.Anchors, other.Anchors) && slices.Equal(r.Corridors, other.Corridors) && slices.Equal(r.Clearings, other.Clearings)
}

func (r Region) clone() *Region {
	r.Anchors = slices.Clone(r.Anchors)
	r.Corridors = slices.Clone(r.Corridors)
	r.Clearings = slices.Clone(r.Clearings)
	return &r
}

// ValidateGeometry bounds every allocation and rejects disconnected recipes.
// The World additionally requires exact canonical recipe equality before loading.
func (r Region) ValidateGeometry() error {
	if len(r.RecipeID) == 0 || len(r.RecipeID) > 64 || len(r.Anchors) < 2 || len(r.Anchors) > MaxRegionAnchors || len(r.Corridors) < 1 || len(r.Corridors) > MaxRegionCorridors || len(r.Clearings) > MaxRegionClearings {
		return errors.New("invalid region recipe size")
	}
	b := r.Bounds
	if !finitePoint(b.Min) || !finitePoint(b.Max) || b.Min.X >= b.Max.X || b.Min.Y >= b.Max.Y || b.Max.X-b.Min.X > 256 || b.Max.Y-b.Min.Y > 256 || math.Abs(b.Min.X) > 512 || math.Abs(b.Min.Y) > 512 || math.Abs(b.Max.X) > 512 || math.Abs(b.Max.Y) > 512 {
		return errors.New("invalid region bounds")
	}
	seen := map[Vec2]bool{}
	for _, p := range r.Anchors {
		if !b.Contains(p) || seen[p] {
			return errors.New("invalid region anchor")
		}
		seen[p] = true
	}
	edges := map[[2]int]bool{}
	for _, e := range r.Corridors {
		if e.A < 0 || e.A >= len(r.Anchors) || e.B < 0 || e.B >= len(r.Anchors) || e.A == e.B || math.IsNaN(e.HalfWidth) || e.HalfWidth <= 0 || e.HalfWidth > 64 {
			return errors.New("invalid region corridor")
		}
		delta := r.Anchors[e.B].Sub(r.Anchors[e.A])
		lengthSquared := regionDot(delta, delta)
		if lengthSquared == 0 || math.IsNaN(lengthSquared) || math.IsInf(lengthSquared, 0) {
			return errors.New("region corridor has unrepresentable squared length")
		}
		key := [2]int{min(e.A, e.B), max(e.A, e.B)}
		if edges[key] {
			return errors.New("duplicate region corridor")
		}
		edges[key] = true
	}
	for _, c := range r.Clearings {
		if !b.Contains(c.Center) || !seen[c.Center] || math.IsNaN(c.Radius) || c.Radius <= 0 || c.Radius > 64 {
			return errors.New("invalid region clearing")
		}
	}
	connected := make([]bool, len(r.Anchors))
	connected[0] = true
	for changed := true; changed; {
		changed = false
		for _, e := range r.Corridors {
			if connected[e.A] != connected[e.B] {
				connected[e.A], connected[e.B], changed = true, true, true
			}
		}
	}
	for _, yes := range connected {
		if !yes {
			return errors.New("disconnected region graph")
		}
	}
	return nil
}

func regionCapsuleContains(p Vec2, r Region, e RegionCorridor) bool {
	d := p.Sub(regionNearest(p, r.Anchors[e.A], r.Anchors[e.B]))
	return regionDot(d, d) <= e.HalfWidth*e.HalfWidth
}

func RegionWalkable(p Vec2, r Region) bool {
	if !r.Bounds.Contains(p) {
		return false
	}
	for _, c := range r.Clearings {
		if regionInDisk(p, c) {
			return true
		}
	}
	for _, e := range r.Corridors {
		if regionCapsuleContains(p, r, e) {
			return true
		}
	}
	return false
}

// Bounds are convex. Strict endpoint containment plus an entire dry-union chord
// therefore proves a segment inside both the union and the rectangular bounds.
func RegionVisible(from, to Vec2, r Region) bool {
	if !RegionWalkable(from, r) || !RegionWalkable(to, r) {
		return false
	}
	if from == to {
		return true
	}
	for _, c := range r.Clearings {
		if regionInDisk(from, c) && regionInDisk(to, c) {
			return true
		}
	}
	for _, e := range r.Corridors {
		if regionCapsuleContains(from, r, e) && regionCapsuleContains(to, r, e) {
			return true
		}
	}
	return regionCoverage(from, to, r) && regionCoverage(to, from, r)
}

// Closed analytic intervals use v7's explicit multiply/add rounding and bounds.
// Clearings first; each declared edge contributes A disk, B disk, slab.
func regionCoverage(from, to Vec2, r Region) bool {
	intervals := make([]cloudInterval, 0, len(r.Clearings)+3*len(r.Corridors))
	addCircle := func(c Shelf) {
		if v, ok := regionCircleInterval(from, to, c); ok {
			intervals = append(intervals, v)
		}
	}
	for _, c := range r.Clearings {
		addCircle(c)
	}
	for _, e := range r.Corridors {
		a, b := r.Anchors[e.A], r.Anchors[e.B]
		addCircle(Shelf{a, e.HalfWidth})
		addCircle(Shelf{b, e.HalfWidth})
		if v, ok := regionRectangleInterval(from, to, a, b, e.HalfWidth); ok {
			intervals = append(intervals, v)
		}
	}
	sort.Slice(intervals, func(i, j int) bool {
		if intervals[i].lo == intervals[j].lo {
			return intervals[i].hi > intervals[j].hi
		}
		return intervals[i].lo < intervals[j].lo
	})
	covered := 0.0
	for _, v := range intervals {
		if v.lo > covered {
			return false
		}
		covered = math.Max(covered, v.hi)
		if covered >= 1 {
			return true
		}
	}
	return false
}

type regionGraph struct {
	visible [MaxRegionAnchors][MaxRegionAnchors]bool
}

func compileRegionGraph(r Region) *regionGraph {
	g := &regionGraph{}
	for i, a := range r.Anchors {
		for j := i + 1; j < len(r.Anchors); j++ {
			g.visible[i][j] = RegionVisible(a, r.Anchors[j], r)
			g.visible[j][i] = g.visible[i][j]
		}
	}
	return g
}

// Static anchor LOS is cached per immutable recipe, never recalculated per frame.
// The two moving endpoints add at most 2*N LOS checks; Dijkstra's ordering and
// 1e-9 cost ties match all existing routed landscapes. Target is not retained.
func RegionRoute(from, target Vec2, r Region) []Vec2 {
	if !RegionWalkable(from, r) || !RegionWalkable(target, r) || RegionVisible(from, target, r) {
		return nil
	}
	n := len(r.Anchors)
	g := r.graph
	if g == nil {
		g = compileRegionGraph(r)
	}
	var nodes [MaxRegionAnchors + 2]Vec2
	copy(nodes[:], r.Anchors)
	nodes[n], nodes[n+1] = from, target
	var links [MaxRegionAnchors + 2][MaxRegionAnchors + 2]bool
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			links[i][j] = g.visible[i][j]
		}
		links[n][i] = RegionVisible(from, nodes[i], r)
		links[i][n] = links[n][i]
		links[n+1][i] = RegionVisible(target, nodes[i], r)
		links[i][n+1] = links[n+1][i]
	}
	var distances [MaxRegionAnchors + 2]float64
	var previous [MaxRegionAnchors + 2]int
	var visited [MaxRegionAnchors + 2]bool
	for i := 0; i < n+2; i++ {
		distances[i], previous[i] = math.Inf(1), -1
	}
	distances[n] = 0
	for step := 0; step < n+2; step++ {
		current := -1
		for i := 0; i < n+2; i++ {
			if !visited[i] && (current < 0 || distances[i] < distances[current]-1e-9) {
				current = i
			}
		}
		if current < 0 || math.IsInf(distances[current], 1) {
			return nil
		}
		if current == n+1 {
			break
		}
		visited[current] = true
		for next := 0; next < n+2; next++ {
			if visited[next] || !links[current][next] {
				continue
			}
			candidate := distances[current] + nodes[next].Sub(nodes[current]).Len()
			if candidate < distances[next]-1e-9 {
				distances[next], previous[next] = candidate, current
			}
		}
	}
	var route []Vec2
	for at := previous[n+1]; at != n; at = previous[at] {
		if at < 0 || len(route) >= n {
			return nil
		}
		route = append(route, nodes[at])
	}
	slices.Reverse(route)
	return route
}

func (w *World) moveOnRegion(p, target Vec2, speed float64, route *[]Vec2) Vec2 {
	r := *w.Layout.Region
	for len(*route) > 0 && p.Sub((*route)[0]).Len() <= .08 {
		*route = (*route)[1:]
	}
	if RegionVisible(p, target, r) {
		*route = nil
	} else if len(*route) == 0 || !RegionVisible(p, (*route)[0], r) || !RegionVisible((*route)[len(*route)-1], target, r) {
		*route = RegionRoute(p, target, r)
	}
	waypoint := target
	if len(*route) > 0 {
		waypoint = (*route)[0]
	}
	delta := waypoint.Sub(p)
	return terrainStep(p, delta.Unit().Mul(math.Min(delta.Len(), speed/TickRate)), false, *w.Layout)
}

func regionClearing(p Vec2, r Region) bool {
	for _, c := range r.Clearings {
		if regionInDisk(p, c) {
			return true
		}
	}
	return false
}

// Only local pressure/edge response, at the same physical scale as old animals.
// The outer bounds also supply an edge normal where they clip a dry primitive.
func regionSheepSteering(p, velocity Vec2, fear float64, r Region) Vec2 {
	margin := math.Inf(-1)
	inward := Vec2{}
	consider := func(c Vec2, radius float64) {
		d := c.Sub(p)
		m := radius - d.Len()
		if m > margin {
			margin, inward = m, d.Unit()
		}
	}
	for _, c := range r.Clearings {
		consider(c.Center, c.Radius)
	}
	for _, e := range r.Corridors {
		consider(regionNearest(p, r.Anchors[e.A], r.Anchors[e.B]), e.HalfWidth)
	}
	for _, edge := range []struct {
		margin float64
		normal Vec2
	}{{p.X - r.Bounds.Min.X, Vec2{1, 0}}, {r.Bounds.Max.X - p.X, Vec2{-1, 0}}, {p.Y - r.Bounds.Min.Y, Vec2{0, 1}}, {r.Bounds.Max.Y - p.Y, Vec2{0, -1}}} {
		if edge.margin < margin {
			margin, inward = edge.margin, edge.normal
		}
	}
	if margin >= 1.3 {
		return velocity
	}
	proximity := math.Max(0, math.Min(1, (1.3-margin)/1.3))
	outward := -regionDot(velocity, inward)
	if outward > 0 {
		velocity = velocity.Add(inward.Mul(outward * proximity))
		if fear > .08 {
			tangent := Vec2{-inward.Y, inward.X}
			if regionDot(velocity, tangent) < 0 {
				tangent = tangent.Mul(-1)
			}
			velocity = velocity.Add(tangent.Mul(outward * proximity * .9))
		}
	}
	return velocity.Add(inward.Mul(proximity * .12))
}

func validRegionRoute(position, target Vec2, route []Vec2, r Region) bool {
	if len(route) > len(r.Anchors) {
		return false
	}
	seen := map[Vec2]bool{}
	for _, p := range route {
		if !slices.Contains(r.Anchors, p) || p == target || seen[p] || !RegionVisible(position, p, r) {
			return false
		}
		seen[p], position = true, p
	}
	return RegionVisible(position, target, r)
}

func (w *World) validateRegionNavigation() error {
	if w.GateOpen || w.Settled != 0 {
		return errors.New("gate or objective in quiet region")
	}
	r := *w.Layout.Region
	for _, p := range w.Players {
		if !slices.Contains([]string{"idle", "walking", "sitting", "petting"}, p.State) || !RegionWalkable(p.Position, r) || !RegionWalkable(p.Target, r) || !validRegionRoute(p.Position, p.Target, p.Route, r) || (len(p.Route) > 0 && p.State != "walking") {
			return errors.New("invalid saved region herder")
		}
	}
	for _, d := range w.Dogs {
		if !slices.Contains([]string{"wander", "go", "come", "stay", "attentive", "happy"}, d.State) || !slices.Contains([]string{"", "go", "come", "stay"}, d.Command) || !RegionWalkable(d.Position, r) || !RegionWalkable(d.Target, r) || !validRegionRoute(d.Position, d.Target, d.Route, r) || (len(d.Route) > 0 && d.Command == "stay") {
			return errors.New("invalid saved region corgi")
		}
	}
	for _, s := range w.Sheep {
		if !slices.Contains([]string{"grazing", "walking", "fleeing"}, s.State) || !finitePoint(s.Velocity) || s.Velocity.Len() > 2.60000001 || !RegionWalkable(s.Position, r) {
			return errors.New("saved sheep outside region")
		}
	}
	return nil
}

func (w *World) ValidPoint(p Vec2) bool {
	if w.Layout != nil && w.Layout.Region != nil {
		return w.Layout.Region.Bounds.Contains(p)
	}
	return p.Valid()
}
