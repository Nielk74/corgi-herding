package game

import (
	"errors"
	"math"
)

// Shore is a dry crescent beside a lake, not a second ridge or a finish region.
// LakeSide is presentation relative to the ordered path; collision is the union.
type Shore struct {
	Path      []Vec2  `json:"path"`
	HalfWidth float64 `json:"half_width"`
	Clearings []Shelf `json:"clearings"`
	LakeSide  string  `json:"lake_side"`
}

func canonicalShore() *Shore {
	return &Shore{Path: []Vec2{{-11, 2}, {-8, -3}, {-3, -6}, {4, -6}, {9, -2}, {11, 4}}, HalfWidth: 3.6,
		Clearings: []Shelf{{Vec2{-11, 2}, 5.2}, {Vec2{-1, -6}, 4.5}, {Vec2{11, 4}, 4.8}}, LakeSide: "left"}
}

func (s *Shore) equal(other *Shore) bool {
	if s == nil || other == nil {
		return s == other
	}
	if s.LakeSide != other.LakeSide {
		return false
	}
	a, b := s.corridor(), other.corridor()
	return a.equal(&b)
}

// The existing analytic capsule-union math accepts any finite ordered path.
// This read-only adapter reuses it without modifying Cloud's geometry/arithmetic.
func (s Shore) corridor() Ridge {
	return Ridge{Spine: s.Path, HalfWidth: s.HalfWidth, Shelves: s.Clearings}
}

func ShoreWalkable(p Vec2, shore Shore) bool       { return CloudWalkable(p, shore.corridor()) }
func ShoreVisible(from, to Vec2, shore Shore) bool { return CloudVisible(from, to, shore.corridor()) }

// Eight fixed nodes: path0..5, start6, target7. Retain at most six anchors.
func ShoreRoute(from, target Vec2, shore Shore) []Vec2 {
	if ShoreVisible(from, target, shore) {
		return nil
	}
	var nodes [8]Vec2
	copy(nodes[:6], shore.Path)
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
			if visited[next] || !ShoreVisible(nodes[current], nodes[next], shore) {
				continue
			}
			candidate := distances[current] + nodes[next].Sub(nodes[current]).Len()
			if candidate < distances[next]-1e-9 {
				distances[next], previous[next] = candidate, current
			}
		}
	}
	var reversed []Vec2
	for at := previous[7]; at != 6; at = previous[at] {
		if at < 0 || len(reversed) >= 6 {
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

func (w *World) moveOnShore(p, target Vec2, speed float64, route *[]Vec2) Vec2 {
	shore := *w.Layout.Shore
	for len(*route) > 0 && p.Sub((*route)[0]).Len() <= .08 {
		*route = (*route)[1:]
	}
	if ShoreVisible(p, target, shore) {
		*route = nil
	} else if len(*route) == 0 || !ShoreVisible(p, (*route)[0], shore) || !ShoreVisible((*route)[len(*route)-1], target, shore) {
		*route = ShoreRoute(p, target, shore)
	}
	waypoint := target
	if len(*route) > 0 {
		waypoint = (*route)[0]
	}
	delta := waypoint.Sub(p)
	return terrainStep(p, delta.Unit().Mul(math.Min(delta.Len(), speed/TickRate)), false, *w.Layout)
}

func validShoreRoute(position, target Vec2, route []Vec2, shore Shore) bool {
	if len(route) > 6 {
		return false
	}
	seen := make(map[Vec2]bool, len(route))
	for _, point := range route {
		canonical := false
		for _, anchor := range shore.Path {
			if point == anchor {
				canonical = true
				break
			}
		}
		if !canonical || point == target || seen[point] || !ShoreVisible(position, point, shore) {
			return false
		}
		seen[point], position = true, point
	}
	return len(route) == 0 || ShoreVisible(position, target, shore)
}

func (w *World) validateShoreNavigation() error {
	if w.GateOpen || w.Settled != 0 {
		return errors.New("gate or objective in quiet Juniper Shore")
	}
	shore := *w.Layout.Shore
	for _, p := range w.Players {
		if !ShoreWalkable(p.Position, shore) || !ShoreWalkable(p.Target, shore) || !validShoreRoute(p.Position, p.Target, p.Route, shore) || (len(p.Route) > 0 && p.State != "walking") {
			return errors.New("invalid saved herder shore navigation")
		}
	}
	for _, d := range w.Dogs {
		if !ShoreWalkable(d.Position, shore) || !ShoreWalkable(d.Target, shore) || !validShoreRoute(d.Position, d.Target, d.Route, shore) || (len(d.Route) > 0 && d.Command == "stay") {
			return errors.New("invalid saved corgi shore navigation")
		}
	}
	for _, s := range w.Sheep {
		if !ShoreWalkable(s.Position, shore) {
			return errors.New("saved sheep is outside shore")
		}
	}
	return nil
}
