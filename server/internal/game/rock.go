package game

import (
	"errors"
	"math"
)

// Fixed v3 anchors, clockwise in Godot's X/Z view: E, NE, N, NW, W, SW, S, SE.
// Use these literal values in prediction too, rather than platform trig calls.
var rockAnchors = [8]Vec2{
	{5.2, 0}, {3.676955262170047, 3.676955262170047}, {0, 5.2}, {-3.676955262170047, 3.676955262170047},
	{-5.2, 0}, {-3.676955262170047, -3.676955262170047}, {0, -5.2}, {3.676955262170047, -3.676955262170047},
}

func dot(a, b Vec2) float64 { return a.X*b.X + a.Y*b.Y }

// RockVisible checks the entire segment, not just its endpoints. No collision
// tolerance weakens the radius. Equal-distance planner ties use a separate epsilon.
func RockVisible(from, to Vec2, rock RockPass) bool {
	delta := to.Sub(from)
	u := 0.0
	if length2 := dot(delta, delta); length2 > 0 {
		u = math.Max(0, math.Min(1, dot(rock.Center.Sub(from), delta)/length2))
	}
	nearest := from.Add(delta.Mul(u)).Sub(rock.Center)
	return dot(nearest, nearest) >= rock.Radius*rock.Radius
}

// RockRoute is a bounded 10-node visibility graph: eight immutable anchors,
// source at index8 and destination at index9. It returns anchors only; Target
// remains authoritative separately. Once chosen this queue is retained by actors.
func RockRoute(from, target Vec2, rock RockPass) []Vec2 {
	if RockVisible(from, target, rock) {
		return nil
	}
	var nodes [10]Vec2
	for i, p := range rockAnchors {
		nodes[i] = rock.Center.Add(p)
	}
	nodes[8], nodes[9] = from, target
	var distances [10]float64
	var previous [10]int
	var visited [10]bool
	for i := range distances {
		distances[i], previous[i] = math.Inf(1), -1
	}
	distances[8] = 0
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
		if current == 9 {
			break
		}
		visited[current] = true
		for next := range nodes {
			if visited[next] || !RockVisible(nodes[current], nodes[next], rock) {
				continue
			}
			candidate := distances[current] + nodes[next].Sub(nodes[current]).Len()
			if candidate < distances[next]-1e-9 {
				distances[next], previous[next] = candidate, current
			}
		}
	}
	var reversed []Vec2
	for at := previous[9]; at != 8; at = previous[at] {
		if at < 0 || len(reversed) >= 8 {
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

func (w *World) moveWithRoute(p, target Vec2, speed float64, route *[]Vec2) Vec2 {
	if w.Layout.Commons != nil {
		return w.moveOnCommons(p, target, speed, route)
	}
	if w.Layout.Shore != nil {
		return w.moveOnShore(p, target, speed, route)
	}
	if w.Layout.Ridge != nil {
		return w.moveOnRidge(p, target, speed, route)
	}
	if w.Layout.RockPass == nil {
		return w.moveTo(p, target, speed)
	}
	rock := *w.Layout.RockPass
	for len(*route) > 0 && p.Sub((*route)[0]).Len() <= .08 {
		*route = (*route)[1:]
	}
	if RockVisible(p, target, rock) {
		*route = nil
	} else if len(*route) == 0 || !RockVisible(p, (*route)[0], rock) || !RockVisible((*route)[len(*route)-1], target, rock) {
		*route = RockRoute(p, target, rock)
	}
	waypoint := target
	if len(*route) > 0 {
		waypoint = (*route)[0]
	}
	delta := waypoint.Sub(p)
	return terrainStep(p, delta.Unit().Mul(math.Min(delta.Len(), speed/TickRate)), false, *w.Layout)
}

// Pressure still chooses the flock's destination. Near rock, remove the inward
// component and carry it into a tangent; no attraction to the east pasture exists.
func rockSheepSteering(p, velocity Vec2, fear float64, rock RockPass) Vec2 {
	away := p.Sub(rock.Center)
	distance := away.Len()
	if distance >= rock.Radius+1.3 {
		return velocity
	}
	normal := away.Unit()
	inward := dot(velocity, normal)
	if inward >= 0 {
		return velocity
	}
	proximity := math.Max(0, math.Min(1, (rock.Radius+1.3-distance)/1.3))
	tangent := Vec2{-normal.Y, normal.X}
	side := dot(velocity, tangent)
	if math.Abs(side) < .02 {
		// A head-on tie takes the positive-Y bypass. Actual off-center dog
		// pressure can choose either route, in either direction.
		if tangent.Y < 0 {
			tangent = tangent.Mul(-1)
		}
	} else if side < 0 {
		tangent = tangent.Mul(-1)
	}
	velocity = velocity.Sub(normal.Mul(inward * proximity))
	if fear > .08 {
		velocity = velocity.Add(tangent.Mul(-inward * proximity * .9))
	}
	return velocity.Add(normal.Mul(proximity * .12))
}

// ValidateNavigation runs before actors start. Version1/2 saves must not acquire
// route fields; v3 queues contain only unique canonical anchors and safe segments.
func (w *World) ValidateNavigation() error {
	if w.Layout.Commons != nil {
		return w.validateCommonsNavigation()
	}
	if w.Layout.Shore != nil {
		return w.validateShoreNavigation()
	}
	if w.Layout.Ridge != nil {
		return w.validateCloudNavigation()
	}
	if w.Layout.RockPass == nil {
		for _, p := range w.Players {
			if p.Route != nil {
				return errors.New("legacy herder has rock navigation")
			}
		}
		for _, d := range w.Dogs {
			if d.Route != nil {
				return errors.New("legacy corgi has rock navigation")
			}
		}
		return nil
	}
	if w.GateOpen {
		return errors.New("open gate in a gateless landscape")
	}
	for _, p := range w.Players {
		if !w.Walkable(p.Position) || !w.Walkable(p.Target) || !validRockRoute(p.Position, p.Target, p.Route, *w.Layout.RockPass) || (len(p.Route) > 0 && p.State != "walking") {
			return errors.New("invalid saved herder rock navigation")
		}
	}
	for _, d := range w.Dogs {
		if !w.Walkable(d.Position) || !w.Walkable(d.Target) || !validRockRoute(d.Position, d.Target, d.Route, *w.Layout.RockPass) || (len(d.Route) > 0 && d.Command == "stay") {
			return errors.New("invalid saved corgi rock navigation")
		}
	}
	for _, s := range w.Sheep {
		if !w.Walkable(s.Position) {
			return errors.New("saved sheep is inside rock")
		}
	}
	return nil
}

func validRockRoute(position, target Vec2, route []Vec2, rock RockPass) bool {
	if len(route) > 8 {
		return false
	}
	seen := make(map[Vec2]bool, len(route))
	for _, point := range route {
		canonical := false
		for _, anchor := range rockAnchors {
			if point == rock.Center.Add(anchor) {
				canonical = true
				break
			}
		}
		if !canonical || seen[point] || !RockVisible(position, point, rock) {
			return false
		}
		seen[point], position = true, point
	}
	return len(route) == 0 || RockVisible(position, target, rock)
}
