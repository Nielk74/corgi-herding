package game

import (
	"errors"
	"math"
	"sort"
)

type Shelf struct {
	Center Vec2    `json:"center"`
	Radius float64 `json:"radius"`
}

type Ridge struct {
	Spine     []Vec2  `json:"spine"`
	HalfWidth float64 `json:"half_width"`
	Shelves   []Shelf `json:"shelves"`
	Rest      Shelf   `json:"rest"`
}

func canonicalRidge() *Ridge {
	return &Ridge{Spine: []Vec2{{-10, 0}, {-2, -5}, {5, 1}, {11, 4}}, HalfWidth: 3.6,
		Shelves: []Shelf{{Vec2{-10, 0}, 6.2}, {Vec2{-2, -5}, 4.8}, {Vec2{11, 4}, 5.2}}, Rest: Shelf{Vec2{11, 4}, 4.6}}
}

func (r *Ridge) equal(other *Ridge) bool {
	if r == nil || other == nil {
		return r == other
	}
	if r.HalfWidth != other.HalfWidth || r.Rest != other.Rest || len(r.Spine) != len(other.Spine) || len(r.Shelves) != len(other.Shelves) {
		return false
	}
	for i, p := range r.Spine {
		if p != other.Spine[i] {
			return false
		}
	}
	for i, s := range r.Shelves {
		if s != other.Shelves[i] {
			return false
		}
	}
	return true
}

func nearestOnSegment(p, a, b Vec2) Vec2 {
	delta := b.Sub(a)
	u := math.Max(0, math.Min(1, dot(p.Sub(a), delta)/dot(delta, delta)))
	return a.Add(delta.Mul(u))
}

func inShelf(p Vec2, s Shelf) bool { d := p.Sub(s.Center); return dot(d, d) <= s.Radius*s.Radius }

func CloudWalkable(p Vec2, ridge Ridge) bool {
	if !p.Valid() {
		return false
	}
	for _, s := range ridge.Shelves {
		if inShelf(p, s) {
			return true
		}
	}
	for i := 1; i < len(ridge.Spine); i++ {
		d := p.Sub(nearestOnSegment(p, ridge.Spine[i-1], ridge.Spine[i]))
		if dot(d, d) <= ridge.HalfWidth*ridge.HalfWidth {
			return true
		}
	}
	return false
}

type cloudInterval struct{ lo, hi float64 }

// Circle intersections are closed intervals on from+t*(to-from), t in [0,1].
// Exact endpoint membership pins a root to 0/1; this does not inflate geometry.
func cloudCircleInterval(from, to Vec2, s Shelf) (cloudInterval, bool) {
	d := to.Sub(from)
	o := from.Sub(s.Center)
	a := dot(d, d)
	if a == 0 {
		return cloudInterval{0, 1}, inShelf(from, s)
	}
	b := dot(o, d)
	c := dot(o, o) - s.Radius*s.Radius
	discriminant := b*b - a*c
	if discriminant < 0 {
		return cloudInterval{}, false
	}
	root := math.Sqrt(discriminant)
	lo, hi := math.Max(0, (-b-root)/a), math.Min(1, (-b+root)/a)
	if inShelf(from, s) {
		lo = 0
	}
	if inShelf(to, s) {
		hi = 1
	}
	return cloudInterval{lo, hi}, lo <= hi
}

func cloudSlab(origin, delta, minimum, maximum float64, interval *cloudInterval) bool {
	if delta == 0 {
		return origin >= minimum && origin <= maximum
	}
	a, b := (minimum-origin)/delta, (maximum-origin)/delta
	if a > b {
		a, b = b, a
	}
	interval.lo = math.Max(interval.lo, a)
	interval.hi = math.Min(interval.hi, b)
	return interval.lo <= interval.hi
}

func cross(a, b Vec2) float64 { return a.X*b.Y - a.Y*b.X }

func cloudRectangleInterval(from, to, a, b Vec2, width float64) (cloudInterval, bool) {
	axis := b.Sub(a)
	length2 := dot(axis, axis)
	side := width * math.Sqrt(length2)
	origin, delta := from.Sub(a), to.Sub(from)
	f, g := dot(origin, axis), cross(origin, axis)
	df, dg := dot(delta, axis), cross(delta, axis)
	interval := cloudInterval{0, 1}
	if !cloudSlab(f, df, 0, length2, &interval) || !cloudSlab(g, dg, -side, side, &interval) {
		return cloudInterval{}, false
	}
	if f >= 0 && f <= length2 && g >= -side && g <= side {
		interval.lo = 0
	}
	f, g = f+df, g+dg
	if f >= 0 && f <= length2 && g >= -side && g <= side {
		interval.hi = 1
	}
	return interval, interval.lo <= interval.hi
}

// CloudVisible checks analytical coverage of the ENTIRE segment by the union,
// never point samples. Bounds are convex, so valid endpoints also bound the chord.
func CloudVisible(from, to Vec2, ridge Ridge) bool {
	if !CloudWalkable(from, ridge) || !CloudWalkable(to, ridge) {
		return false
	}
	if from == to {
		return true
	}
	intervals := make([]cloudInterval, 0, 13)
	for _, s := range ridge.Shelves {
		if interval, ok := cloudCircleInterval(from, to, s); ok {
			intervals = append(intervals, interval)
		}
	}
	for _, point := range ridge.Spine {
		if interval, ok := cloudCircleInterval(from, to, Shelf{point, ridge.HalfWidth}); ok {
			intervals = append(intervals, interval)
		}
	}
	for i := 1; i < len(ridge.Spine); i++ {
		if interval, ok := cloudRectangleInterval(from, to, ridge.Spine[i-1], ridge.Spine[i], ridge.HalfWidth); ok {
			intervals = append(intervals, interval)
		}
	}
	sort.Slice(intervals, func(i, j int) bool {
		if intervals[i].lo == intervals[j].lo {
			return intervals[i].hi > intervals[j].hi
		}
		return intervals[i].lo < intervals[j].lo
	})
	covered := 0.0
	for _, interval := range intervals {
		if interval.lo > covered {
			return false
		}
		covered = math.Max(covered, interval.hi)
		if covered >= 1 {
			return true
		}
	}
	return false
}

// Exactly six nodes: spine0..3, start4, target5. Like Oasis, retain chosen anchors
// rather than choosing a different route on every snapshot or duplicate command.
func CloudRoute(from, target Vec2, ridge Ridge) []Vec2 {
	if CloudVisible(from, target, ridge) {
		return nil
	}
	var nodes [6]Vec2
	copy(nodes[:4], ridge.Spine)
	nodes[4], nodes[5] = from, target
	var distances [6]float64
	var previous [6]int
	var visited [6]bool
	for i := range nodes {
		distances[i], previous[i] = math.Inf(1), -1
	}
	distances[4] = 0
	for step := 0; step < len(nodes); step++ {
		current := -1
		for i := range nodes {
			if !visited[i] && (current < 0 || distances[i] < distances[current]-1e-9) {
				current = i
			}
		}
		if current < 0 || math.IsInf(distances[current], 1) {
			return nil
		}
		if current == 5 {
			break
		}
		visited[current] = true
		for next := range nodes {
			if visited[next] || !CloudVisible(nodes[current], nodes[next], ridge) {
				continue
			}
			candidate := distances[current] + nodes[next].Sub(nodes[current]).Len()
			if candidate < distances[next]-1e-9 {
				distances[next], previous[next] = candidate, current
			}
		}
	}
	var reversed []Vec2
	for at := previous[5]; at != 4; at = previous[at] {
		if at < 0 || len(reversed) >= 4 {
			return nil
		}
		reversed = append(reversed, nodes[at])
	}
	route := make([]Vec2, len(reversed))
	for i := range reversed {
		route[i] = reversed[len(reversed)-1-i]
	}
	return route
}

func (w *World) planRoute(from, target Vec2) []Vec2 {
	if w.Layout.Ridge != nil {
		return CloudRoute(from, target, *w.Layout.Ridge)
	}
	return RockRoute(from, target, *w.Layout.RockPass)
}

func (w *World) moveOnRidge(p, target Vec2, speed float64, route *[]Vec2) Vec2 {
	ridge := *w.Layout.Ridge
	for len(*route) > 0 && p.Sub((*route)[0]).Len() <= .08 {
		*route = (*route)[1:]
	}
	if CloudVisible(p, target, ridge) {
		*route = nil
	} else if len(*route) == 0 || !CloudVisible(p, (*route)[0], ridge) || !CloudVisible((*route)[len(*route)-1], target, ridge) {
		*route = CloudRoute(p, target, ridge)
	}
	waypoint := target
	if len(*route) > 0 {
		waypoint = (*route)[0]
	}
	delta := waypoint.Sub(p)
	return terrainStep(p, delta.Unit().Mul(math.Min(delta.Len(), speed/TickRate)), false, *w.Layout)
}

func ridgeShelf(p Vec2, ridge Ridge) bool {
	for _, s := range ridge.Shelves {
		if inShelf(p, s) {
			return true
		}
	}
	return false
}

// The deepest containing primitive supplies a conservative local edge margin.
// This is edge avoidance only: neither the spine's end nor rest area attracts sheep.
func cloudSheepSteering(p, velocity Vec2, fear float64, ridge Ridge) Vec2 {
	margin := math.Inf(-1)
	inward := Vec2{}
	consider := func(center Vec2, radius float64) {
		d := center.Sub(p)
		m := radius - d.Len()
		if m > margin {
			margin, inward = m, d.Unit()
		}
	}
	for _, s := range ridge.Shelves {
		consider(s.Center, s.Radius)
	}
	for i := 1; i < len(ridge.Spine); i++ {
		consider(nearestOnSegment(p, ridge.Spine[i-1], ridge.Spine[i]), ridge.HalfWidth)
	}
	if margin >= 1.3 {
		return velocity
	}
	proximity := math.Max(0, math.Min(1, (1.3-margin)/1.3))
	outward := -dot(velocity, inward)
	if outward > 0 {
		velocity = velocity.Add(inward.Mul(outward * proximity))
		if fear > .08 {
			tangent := Vec2{-inward.Y, inward.X}
			if dot(velocity, tangent) < 0 {
				tangent = tangent.Mul(-1)
			}
			velocity = velocity.Add(tangent.Mul(outward * proximity * .9))
		}
	}
	return velocity.Add(inward.Mul(proximity * .12))
}

func validCloudRoute(position, target Vec2, route []Vec2, ridge Ridge) bool {
	if len(route) > 4 {
		return false
	}
	seen := make(map[Vec2]bool, len(route))
	for _, point := range route {
		canonical := false
		for _, anchor := range ridge.Spine {
			if point == anchor {
				canonical = true
				break
			}
		}
		if !canonical || point == target || seen[point] || !CloudVisible(position, point, ridge) {
			return false
		}
		seen[point], position = true, point
	}
	return len(route) == 0 || CloudVisible(position, target, ridge)
}

func (w *World) validateCloudNavigation() error {
	if w.GateOpen {
		return errors.New("gate in a gateless cloud pasture")
	}
	ridge := *w.Layout.Ridge
	for _, p := range w.Players {
		if !CloudWalkable(p.Position, ridge) || !CloudWalkable(p.Target, ridge) || !validCloudRoute(p.Position, p.Target, p.Route, ridge) || (len(p.Route) > 0 && p.State != "walking") {
			return errors.New("invalid saved herder ridge navigation")
		}
	}
	for _, d := range w.Dogs {
		if !CloudWalkable(d.Position, ridge) || !CloudWalkable(d.Target, ridge) || !validCloudRoute(d.Position, d.Target, d.Route, ridge) || (len(d.Route) > 0 && d.Command == "stay") {
			return errors.New("invalid saved corgi ridge navigation")
		}
	}
	for _, s := range w.Sheep {
		if !CloudWalkable(s.Position, ridge) {
			return errors.New("saved sheep is outside ridge")
		}
	}
	return nil
}
