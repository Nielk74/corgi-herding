package game

import "math"

// Version 7 defines binary64 multiply THEN add/subtract, matching scalar Godot
// math. Go may otherwise fuse either product in x*x+y*y depending on inlining
// and register order, making the same closed disk disagree between call sites.
// Explicit conversions are rounding barriers guaranteed by the Go language:
// https://go.dev/ref/spec#Floating_point_operators
// This is not an epsilon, an inflated shape, or a change to v1-v6 arithmetic.
func regionDot(a, b Vec2) float64   { return float64(a.X*b.X) + float64(a.Y*b.Y) }
func regionCross(a, b Vec2) float64 { return float64(a.X*b.Y) - float64(a.Y*b.X) }

func regionNearest(p, a, b Vec2) Vec2 {
	axis := b.Sub(a)
	u := math.Max(0, math.Min(1, regionDot(p.Sub(a), axis)/regionDot(axis, axis)))
	return Vec2{a.X + float64(axis.X*u), a.Y + float64(axis.Y*u)}
}

func regionInDisk(p Vec2, c Shelf) bool {
	d := p.Sub(c.Center)
	return regionDot(d, d) <= float64(c.Radius*c.Radius)
}

// Same analytical closed intervals as v4, now with explicit v7 rounding at
// every potentially fused product. Keep the old helpers and old traces intact.
func regionCircleInterval(from, to Vec2, circle Shelf) (cloudInterval, bool) {
	d := to.Sub(from)
	o := from.Sub(circle.Center)
	a := regionDot(d, d)
	if a == 0 {
		return cloudInterval{0, 1}, regionInDisk(from, circle)
	}
	b := regionDot(o, d)
	c := regionDot(o, o) - float64(circle.Radius*circle.Radius)
	discriminant := float64(b*b) - float64(a*c)
	if discriminant < 0 {
		return cloudInterval{}, false
	}
	root := math.Sqrt(discriminant)
	lo, hi := math.Max(0, (-b-root)/a), math.Min(1, (-b+root)/a)
	if regionInDisk(from, circle) {
		lo = 0
	}
	if regionInDisk(to, circle) {
		hi = 1
	}
	return cloudInterval{lo, hi}, lo <= hi
}

func regionRectangleInterval(from, to, a, b Vec2, width float64) (cloudInterval, bool) {
	axis := b.Sub(a)
	length2 := regionDot(axis, axis)
	side := width * math.Sqrt(length2)
	origin, delta := from.Sub(a), to.Sub(from)
	f, g := regionDot(origin, axis), regionCross(origin, axis)
	df, dg := regionDot(delta, axis), regionCross(delta, axis)
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
