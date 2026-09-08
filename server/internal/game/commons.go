package game

import (
	"errors"
	"math"
	"slices"
)

// Commons is one broad meadow with two equally valid branches. Corridors are
// terrain edges, not required routing edges and not an ordered linear spine.
type Commons struct {
	Anchors   []Vec2  `json:"anchors"`
	Corridors [][]int `json:"corridors"`
	HalfWidth float64 `json:"half_width"`
	Clearings []Shelf `json:"clearings"`
}

func canonicalCommons() *Commons {
	return &Commons{Anchors: []Vec2{{-5, 0}, {0, 0}, {4, -4}, {10, -6}, {4, 4}, {10, 6}}, Corridors: [][]int{{0, 1}, {1, 2}, {2, 3}, {1, 4}, {4, 5}}, HalfWidth: 3.6, Clearings: []Shelf{{Vec2{-5, 0}, 7.2}, {Vec2{10, -6}, 4.8}, {Vec2{10, 6}, 4.8}}}
}

func (c *Commons) equal(other *Commons) bool {
	if c == nil || other == nil {
		return c == other
	}
	if len(c.Corridors) != len(other.Corridors) {
		return false
	}
	for i, edge := range c.Corridors {
		if !slices.Equal(edge, other.Corridors[i]) {
			return false
		}
	}
	return c.HalfWidth == other.HalfWidth && slices.Equal(c.Anchors, other.Anchors) && slices.Equal(c.Clearings, other.Clearings)
}

// Read-only canonical tree traversal: 0,1,2,3,2,1,4,5. Retracing two edges
// adds duplicate capsules, never a phantom connection between the branch ends.
// Every predicate and steering uses this same order, including reversed edges.
func (c Commons) shore() Shore {
	path := make([]Vec2, 0, 8)
	for _, index := range [...]int{0, 1, 2, 3, 2, 1, 4, 5} {
		path = append(path, c.Anchors[index])
	}
	return Shore{Path: path, HalfWidth: c.HalfWidth, Clearings: c.Clearings}
}

func CommonsWalkable(p Vec2, c Commons) bool       { return ShoreWalkable(p, c.shore()) }
func CommonsVisible(from, to Vec2, c Commons) bool { return ShoreVisible(from, to, c.shore()) }

// Six UNIQUE anchors, source6,target7. The repeated union traversal above is
// never used as the navigation graph's node list.
func CommonsRoute(from, target Vec2, c Commons) []Vec2 {
	if CommonsVisible(from, target, c) {
		return nil
	}
	var nodes [8]Vec2
	copy(nodes[:6], c.Anchors)
	nodes[6], nodes[7] = from, target
	var distances [8]float64
	var previous [8]int
	var visited [8]bool
	for i := range nodes {
		distances[i], previous[i] = math.Inf(1), -1
	}
	distances[6] = 0
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
		if current == 7 {
			break
		}
		visited[current] = true
		for next := range nodes {
			if visited[next] || !CommonsVisible(nodes[current], nodes[next], c) {
				continue
			}
			candidate := distances[current] + nodes[next].Sub(nodes[current]).Len()
			if candidate < distances[next]-1e-9 {
				distances[next], previous[next] = candidate, current
			}
		}
	}
	var reverse []Vec2
	for at := previous[7]; at != 6; at = previous[at] {
		if at < 0 || len(reverse) >= 6 {
			return nil
		}
		reverse = append(reverse, nodes[at])
	}
	route := make([]Vec2, len(reverse))
	for i := range reverse {
		route[i] = reverse[len(reverse)-1-i]
	}
	return route
}

func (w *World) moveOnCommons(p, target Vec2, speed float64, route *[]Vec2) Vec2 {
	c := *w.Layout.Commons
	for len(*route) > 0 && p.Sub((*route)[0]).Len() <= .08 {
		*route = (*route)[1:]
	}
	if CommonsVisible(p, target, c) {
		*route = nil
	} else if len(*route) == 0 || !CommonsVisible(p, (*route)[0], c) || !CommonsVisible((*route)[len(*route)-1], target, c) {
		*route = CommonsRoute(p, target, c)
	}
	waypoint := target
	if len(*route) > 0 {
		waypoint = (*route)[0]
	}
	delta := waypoint.Sub(p)
	return terrainStep(p, delta.Unit().Mul(math.Min(delta.Len(), speed/TickRate)), false, *w.Layout)
}

func validCommonsRoute(position, target Vec2, route []Vec2, c Commons) bool {
	if len(route) > 6 {
		return false
	}
	seen := map[Vec2]bool{}
	for _, point := range route {
		if !slices.Contains(c.Anchors, point) || point == target || seen[point] || !CommonsVisible(position, point, c) {
			return false
		}
		seen[point], position = true, point
	}
	return len(route) == 0 || CommonsVisible(position, target, c)
}

func (w *World) validateCommonsNavigation() error {
	if w.GateOpen || w.Settled != 0 {
		return errors.New("gate or objective in quiet Bellflower Commons")
	}
	c := *w.Layout.Commons
	for _, p := range w.Players {
		if !CommonsWalkable(p.Position, c) || !CommonsWalkable(p.Target, c) || !validCommonsRoute(p.Position, p.Target, p.Route, c) || (len(p.Route) > 0 && p.State != "walking") {
			return errors.New("invalid saved herder commons navigation")
		}
	}
	for _, d := range w.Dogs {
		if !CommonsWalkable(d.Position, c) || !CommonsWalkable(d.Target, c) || !validCommonsRoute(d.Position, d.Target, d.Route, c) || (len(d.Route) > 0 && d.Command == "stay") {
			return errors.New("invalid saved corgi commons navigation")
		}
	}
	for _, s := range w.Sheep {
		if !CommonsWalkable(s.Position, c) {
			return errors.New("saved sheep outside commons")
		}
	}
	return nil
}
