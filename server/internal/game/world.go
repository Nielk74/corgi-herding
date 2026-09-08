// Package game is the platform-independent authoritative meadow simulation.
package game

import (
	"errors"
	"fmt"
	"math"
)

const TickRate = 20

const (
	LandscapeAlpine       = "alpine"
	LandscapeCactus       = "cactus"
	LandscapeLarch        = "larch"
	LandscapeOrchard      = "orchard"
	LandscapeOasis        = "oasis"
	LandscapeCloud        = "cloud"
	LandscapeJuniper      = "juniper"
	LandscapeBellflower   = "bellflower"
	LandscapeAlpineValley = "alpine_valley"
	LandscapeDryWash      = "dry_wash"
)

func ValidLandscape(landscape string) bool {
	return landscape == LandscapeAlpine || landscape == LandscapeCactus || landscape == LandscapeLarch || landscape == LandscapeOrchard || landscape == LandscapeOasis || landscape == LandscapeCloud || landscape == LandscapeJuniper || landscape == LandscapeBellflower || landscape == LandscapeAlpineValley || landscape == LandscapeDryWash
}

// Layout is immutable herd geometry. Version 1 retains the original bounds,
// river/fence X coordinates and opening widths, varying only opening centers.
type Layout struct {
	Version  int         `json:"version"`
	BridgeY  float64     `json:"bridge_y"`
	GateY    float64     `json:"gate_y"`
	Forage   *ForageZone `json:"forage,omitempty"`
	RockPass *RockPass   `json:"rock_pass,omitempty"`
	Ridge    *Ridge      `json:"ridge,omitempty"`
	Shore    *Shore      `json:"shore,omitempty"`
	Commons  *Commons    `json:"commons,omitempty"`
	Region   *Region     `json:"region,omitempty"`
}

type RockPass struct {
	Center Vec2    `json:"center"`
	Radius float64 `json:"radius"`
}

type ForageZone struct {
	ID     string  `json:"id"`
	Center Vec2    `json:"center"`
	Radius float64 `json:"radius"`
}

func (l *Layout) Equal(other *Layout) bool {
	if l == nil || other == nil {
		return l == other
	}
	if l.Version != other.Version || l.BridgeY != other.BridgeY || l.GateY != other.GateY {
		return false
	}
	if l.Forage == nil || other.Forage == nil {
		if l.Forage != other.Forage {
			return false
		}
	} else if *l.Forage != *other.Forage {
		return false
	}
	if l.RockPass == nil || other.RockPass == nil {
		if l.RockPass != other.RockPass {
			return false
		}
	} else if *l.RockPass != *other.RockPass {
		return false
	}
	return l.Ridge.equal(other.Ridge) && l.Shore.equal(other.Shore) && l.Commons.equal(other.Commons) && l.Region.equal(other.Region)
}

func LayoutForLandscape(landscape string) *Layout {
	layout := &Layout{Version: 1}
	if landscape == LandscapeLarch {
		layout.BridgeY, layout.GateY = -4, 4
	} else if landscape == LandscapeOrchard {
		layout.Version, layout.BridgeY, layout.GateY = 2, 3, 2
		layout.Forage = &ForageZone{ID: "windfall", Center: Vec2{-7, -5}, Radius: 2.2}
	} else if landscape == LandscapeOasis {
		layout.Version = 3
		layout.RockPass = &RockPass{Center: Vec2{}, Radius: 3.4}
	} else if landscape == LandscapeCloud {
		layout.Version, layout.Ridge = 4, canonicalRidge()
	} else if landscape == LandscapeJuniper {
		layout.Version, layout.Shore = 5, canonicalShore()
	} else if landscape == LandscapeBellflower {
		layout.Version, layout.Commons = 6, canonicalCommons()
	} else if version, region := registeredRegion(landscape); region != nil {
		layout.Version, layout.Region = version, region
	}
	return layout
}

func (w *World) ValidateLayout() error {
	if w.Layout == nil || w.Layout.Version < 1 || w.Layout.Version > 8 {
		return errors.New("unsupported saved layout version")
	}
	canonical := LayoutForLandscape(w.Landscape)
	if !ValidLandscape(w.Landscape) || !w.Layout.Equal(canonical) {
		return errors.New("saved layout does not match its landscape version")
	}
	if w.Layout.Region != nil {
		if err := w.Layout.Region.ValidateGeometry(); err != nil {
			return err
		}
		w.Layout.Region.graph = canonical.Region.graph
	}
	return nil
}

func (w *World) SupportsLayout(version int) bool {
	return (version >= 1 && version <= 8 && w.Layout.Version <= version) || (version == 0 && w.Layout.Version == 1 && w.Layout.BridgeY == 0 && w.Layout.GateY == 0)
}

type Vec2 struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

func (a Vec2) Add(b Vec2) Vec2    { return Vec2{a.X + b.X, a.Y + b.Y} }
func (a Vec2) Sub(b Vec2) Vec2    { return Vec2{a.X - b.X, a.Y - b.Y} }
func (a Vec2) Mul(n float64) Vec2 { return Vec2{a.X * n, a.Y * n} }
func (a Vec2) Len() float64       { return math.Hypot(a.X, a.Y) }
func (a Vec2) Unit() Vec2 {
	if n := a.Len(); n > 0.0001 {
		return a.Mul(1 / n)
	}
	return Vec2{}
}
func (a Vec2) Valid() bool {
	return !math.IsNaN(a.X) && !math.IsNaN(a.Y) && !math.IsInf(a.X, 0) && !math.IsInf(a.Y, 0) && a.X >= -17 && a.X <= 17 && a.Y >= -11 && a.Y <= 11
}

type Player struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Position  Vec2   `json:"position"`
	Target    Vec2   `json:"target"`
	Seq       uint64 `json:"seq"`
	State     string `json:"state"`
	Connected bool   `json:"connected"`
	Route     []Vec2 `json:"route,omitempty"`
}

type Dog struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Position Vec2   `json:"position"`
	Target   Vec2   `json:"target"`
	State    string `json:"state"`
	Command  string `json:"command"`
	Caller   string `json:"caller,omitempty"`
	Route    []Vec2 `json:"route,omitempty"`
}

type Sheep struct {
	ID       string       `json:"id"`
	Position Vec2         `json:"position"`
	Velocity Vec2         `json:"velocity"`
	State    string       `json:"state"`
	Group    int          `json:"group"`
	Forage   *SheepForage `json:"forage,omitempty"`
}

const ForageNibbleTicks = 4 * TickRate

type SheepForage struct {
	ZoneID         string `json:"zone_id"`
	RemainingTicks int    `json:"remaining_ticks"`
	Satiated       bool   `json:"satiated"`
}

type World struct {
	Type      string   `json:"type"`
	Tick      uint64   `json:"tick"`
	Code      string   `json:"code"`
	Landscape string   `json:"landscape"`
	Layout    *Layout  `json:"layout"`
	GateOpen  bool     `json:"gate_open"`
	Settled   int      `json:"settled"`
	Players   []Player `json:"players"`
	Dogs      []Dog    `json:"dogs"`
	Sheep     []Sheep  `json:"sheep"`
}

type Input struct {
	Type          string `json:"type"`
	Seq           uint64 `json:"seq,omitempty"`
	Target        *Vec2  `json:"target,omitempty"`
	DogID         string `json:"dog_id,omitempty"`
	Command       string `json:"command,omitempty"`
	Action        string `json:"action,omitempty"`
	PlayerID      string `json:"player_id,omitempty"`
	Token         string `json:"token,omitempty"`
	LayoutVersion int    `json:"layout_version,omitempty"`
}

func New(code string) *World {
	w := &World{Type: "snapshot", Code: code, Landscape: LandscapeAlpine, Layout: LayoutForLandscape(LandscapeAlpine), Players: []Player{}, Dogs: []Dog{
		{ID: "mochi", Name: "Mochi", Position: Vec2{-11, -2}, Target: Vec2{-11, -2}, State: "wander"},
		{ID: "maple", Name: "Maple", Position: Vec2{-11, 2}, Target: Vec2{-11, 2}, State: "wander"},
	}}
	for i := 0; i < 10; i++ {
		w.Sheep = append(w.Sheep, Sheep{ID: fmt.Sprintf("s%d", i+1), Position: Vec2{-7 + float64(i%3)*1.15, -2 + float64(i/3)*1.15}, State: "grazing"})
	}
	return w
}

// NewForLandscape applies only new-world spawns. Checkpoint loading never calls it.
func NewForLandscape(code, landscape string) *World {
	w := New(code)
	w.Landscape, w.Layout = landscape, LayoutForLandscape(landscape)
	if landscape == LandscapeAlpineValley {
		for i, p := range []Vec2{{-47, 71.8}, {-44, 71.8}} {
			w.Dogs[i].Position, w.Dogs[i].Target = p, p
		}
		for i := range w.Sheep {
			w.Sheep[i].Position = Vec2{-44.7 + float64(i%3), 62.4 + float64(i/3)*1.05}
		}
	} else if landscape == LandscapeDryWash {
		for i, p := range []Vec2{{-43, 76.8}, {-40, 76.8}} {
			w.Dogs[i].Position, w.Dogs[i].Target = p, p
		}
		for i := range w.Sheep {
			w.Sheep[i].Position = Vec2{-39.7 + float64(i%3), 66.4 + float64(i/3)*1.05}
		}
	} else if landscape == LandscapeJuniper {
		for i, p := range []Vec2{{-12.2, -1}, {-12.2, 2}} {
			w.Dogs[i].Position, w.Dogs[i].Target = p, p
		}
		for i := range w.Sheep {
			w.Sheep[i].Position = Vec2{-10.7 + float64(i%3), -.4 + float64(i/3)*1.05}
		}
	} else if landscape == LandscapeBellflower {
		for i, p := range []Vec2{{-8.2, -2}, {-8.2, 1}} {
			w.Dogs[i].Position, w.Dogs[i].Target = p, p
		}
		for i := range w.Sheep {
			w.Sheep[i].Position = Vec2{-6.7 + float64(i%3), -.4 + float64(i/3)*1.05}
		}
	}
	return w
}

func (w *World) Clone() *World {
	n := *w
	if w.Layout != nil {
		layout := *w.Layout
		if w.Layout.Forage != nil {
			zone := *w.Layout.Forage
			layout.Forage = &zone
		}
		if w.Layout.RockPass != nil {
			rock := *w.Layout.RockPass
			layout.RockPass = &rock
		}
		if w.Layout.Ridge != nil {
			ridge := *w.Layout.Ridge
			ridge.Spine = append([]Vec2(nil), ridge.Spine...)
			ridge.Shelves = append([]Shelf(nil), ridge.Shelves...)
			layout.Ridge = &ridge
		}
		if w.Layout.Shore != nil {
			shore := *w.Layout.Shore
			shore.Path = append([]Vec2(nil), shore.Path...)
			shore.Clearings = append([]Shelf(nil), shore.Clearings...)
			layout.Shore = &shore
		}
		if w.Layout.Commons != nil {
			commons := *w.Layout.Commons
			commons.Anchors = append([]Vec2(nil), commons.Anchors...)
			commons.Corridors = make([][]int, len(w.Layout.Commons.Corridors))
			for i, edge := range w.Layout.Commons.Corridors {
				commons.Corridors[i] = append([]int(nil), edge...)
			}
			commons.Clearings = append([]Shelf(nil), commons.Clearings...)
			layout.Commons = &commons
		}
		if w.Layout.Region != nil {
			layout.Region = w.Layout.Region.clone()
		}
		n.Layout = &layout
	}
	n.Players = append([]Player{}, w.Players...)
	n.Dogs = append([]Dog{}, w.Dogs...)
	for i := range n.Players {
		n.Players[i].Route = append([]Vec2(nil), n.Players[i].Route...)
	}
	for i := range n.Dogs {
		n.Dogs[i].Route = append([]Vec2(nil), n.Dogs[i].Route...)
	}
	n.Sheep = append([]Sheep{}, w.Sheep...)
	for i := range n.Sheep {
		if n.Sheep[i].Forage != nil {
			state := *n.Sheep[i].Forage
			n.Sheep[i].Forage = &state
		}
	}
	return &n
}

func (w *World) AddPlayer(id, name string) error {
	if len(w.Players) >= 2 {
		return errors.New("this herd already has two herders")
	}
	p := Vec2{-13, -1.5 + float64(len(w.Players))*3}
	if w.Landscape == LandscapeAlpineValley {
		p = Vec2{-48 + float64(len(w.Players))*3, 74}
	} else if w.Landscape == LandscapeDryWash {
		p = Vec2{-44 + float64(len(w.Players))*3, 79}
	} else if w.Landscape == LandscapeJuniper {
		p = Vec2{-14, float64(len(w.Players)) * 3}
	} else if w.Landscape == LandscapeBellflower {
		p = Vec2{-10, -1 + float64(len(w.Players))*3}
	}
	w.Players = append(w.Players, Player{ID: id, Name: name, Position: p, Target: p, State: "idle"})
	return nil
}

func (w *World) Player(id string) *Player {
	for i := range w.Players {
		if w.Players[i].ID == id {
			return &w.Players[i]
		}
	}
	return nil
}

func (w *World) Apply(playerID string, in Input) error {
	p := w.Player(playerID)
	if p == nil {
		return errors.New("unknown herder")
	}
	switch in.Type {
	case "move":
		if in.Seq == 0 || in.Target == nil || !w.ValidPoint(*in.Target) {
			return errors.New("move needs a positive sequence and a target inside the meadow")
		}
		if in.Seq <= p.Seq {
			return nil
		}
		if !w.Walkable(*in.Target) {
			return errors.New("choose somewhere on dry land")
		}
		if (w.Layout.RockPass != nil || w.Layout.Ridge != nil || w.Layout.Shore != nil || w.Layout.Commons != nil || w.Layout.Region != nil) && p.Target != *in.Target {
			p.Route = w.planRoute(p.Position, *in.Target)
		}
		p.Seq, p.Target, p.State = in.Seq, *in.Target, "walking"
	case "command":
		var d *Dog
		for i := range w.Dogs {
			if w.Dogs[i].ID == in.DogID {
				d = &w.Dogs[i]
				break
			}
		}
		if d == nil {
			return errors.New("unknown corgi")
		}
		oldTarget := d.Target
		switch in.Command {
		case "come":
			d.Target = p.Position
		case "stay":
			d.Target = d.Position
		case "go":
			if in.Target == nil || !w.ValidPoint(*in.Target) || !w.Walkable(*in.Target) {
				return errors.New("choose a dry-land destination for the corgi")
			}
			d.Target = *in.Target
		default:
			return errors.New("unknown dog command")
		}
		d.Command, d.Caller, d.State = in.Command, playerID, in.Command
		if w.Layout.RockPass != nil || w.Layout.Ridge != nil || w.Layout.Shore != nil || w.Layout.Commons != nil || w.Layout.Region != nil {
			if in.Command == "stay" {
				d.Route = nil
			} else if oldTarget != d.Target {
				d.Route = w.planRoute(d.Position, d.Target)
			}
		}
	case "interact":
		switch in.Action {
		case "gate":
			if w.Layout.RockPass != nil || w.Layout.Ridge != nil || w.Layout.Shore != nil || w.Layout.Commons != nil || w.Layout.Region != nil {
				return errors.New("there is no gate in this open pasture")
			}
			if p.Position.Sub(Vec2{6, w.Layout.GateY}).Len() > 3 {
				return errors.New("walk closer to the gate")
			}
			// Once opened, the gate stays open so animals cannot become trapped in it.
			w.GateOpen = true
		case "sit":
			p.Target, p.State = p.Position, "sitting"
			p.Route = nil
		case "pet":
			for i := range w.Dogs {
				d := &w.Dogs[i]
				if d.ID == in.DogID && d.Position.Sub(p.Position).Len() <= 2.5 {
					d.State, d.Command, d.Target = "happy", "stay", d.Position
					p.Target, p.State = p.Position, "petting"
					p.Route, d.Route = nil, nil
					return nil
				}
			}
			return errors.New("walk closer to that corgi")
		default:
			return errors.New("unknown interaction")
		}
	default:
		return errors.New("unknown message type")
	}
	return nil
}

// Walkable describes the same bridge and fence used by the client diorama.
func Walkable(p Vec2, gateOpen bool) bool {
	return walkable(p, gateOpen, Layout{Version: 1})
}

func (w *World) Walkable(p Vec2) bool { return walkable(p, w.GateOpen, *w.Layout) }

func walkable(p Vec2, gateOpen bool, layout Layout) bool {
	if layout.Region != nil {
		return RegionWalkable(p, *layout.Region)
	}
	if !p.Valid() {
		return false
	}
	if layout.Commons != nil {
		return CommonsWalkable(p, *layout.Commons)
	}
	if layout.Shore != nil {
		return ShoreWalkable(p, *layout.Shore)
	}
	if layout.Ridge != nil {
		return CloudWalkable(p, *layout.Ridge)
	}
	if layout.RockPass != nil {
		return p.Sub(layout.RockPass.Center).Len() >= layout.RockPass.Radius
	}
	if math.Abs(p.X) < 1.5 && math.Abs(p.Y-layout.BridgeY) > 1.85 {
		return false
	}
	if math.Abs(p.X-6) < 0.18 && (!gateOpen || math.Abs(p.Y-layout.GateY) > 1.8) {
		return false
	}
	return true
}

// terrainStep is also used for flock forces; every small step is collision checked.
func terrainStep(p, delta Vec2, gateOpen bool, layout Layout) Vec2 {
	pieces := max(1, int(math.Ceil(delta.Len()/0.08)))
	delta = delta.Mul(1 / float64(pieces))
	for i := 0; i < pieces; i++ {
		n := p.Add(delta)
		if terrainSegment(p, n, gateOpen, layout) {
			p = n
			continue
		}
		n = p.Add(Vec2{delta.X, 0})
		if terrainSegment(p, n, gateOpen, layout) {
			p = n
		}
		n = p.Add(Vec2{0, delta.Y})
		if terrainSegment(p, n, gateOpen, layout) {
			p = n
		}
	}
	return p
}

func terrainSegment(p, n Vec2, gateOpen bool, layout Layout) bool {
	if layout.Region != nil {
		return RegionVisible(p, n, *layout.Region)
	}
	if layout.Commons != nil {
		return CommonsVisible(p, n, *layout.Commons)
	}
	if layout.Shore != nil {
		return ShoreVisible(p, n, *layout.Shore)
	}
	if layout.Ridge != nil {
		return CloudVisible(p, n, *layout.Ridge)
	}
	return walkable(n, gateOpen, layout) && (layout.RockPass == nil || RockVisible(p, n, *layout.RockPass))
}

// Waypoints route both people and dogs onto the bridge before crossing water.
func waypoint(p, target Vec2, gateOpen bool, layout Layout) Vec2 {
	// On a return journey the fence comes before the river. This order matters
	// when their openings have different Y coordinates.
	if p.X > 6 && target.X < 6 {
		return gateWaypoint(p, gateOpen, layout)
	}
	if p.X < -1.5 && target.X > -1.5 {
		if math.Abs(p.Y-layout.BridgeY) > 1.4 {
			return Vec2{-2.1, layout.BridgeY}
		}
		if target.X < 1.5 {
			return target
		}
		return Vec2{2.1, layout.BridgeY}
	}
	if p.X > 1.5 && target.X < 1.5 {
		if math.Abs(p.Y-layout.BridgeY) > 1.4 {
			return Vec2{2.1, layout.BridgeY}
		}
		if target.X > -1.5 {
			return target
		}
		return Vec2{-2.1, layout.BridgeY}
	}
	if math.Abs(p.X) <= 1.5 {
		if math.Abs(target.X) <= 1.5 {
			return target
		}
		if target.X >= 0 {
			return Vec2{2.1, layout.BridgeY}
		}
		return Vec2{-2.1, layout.BridgeY}
	}
	if (p.X < 6 && target.X > 6) || (p.X > 6 && target.X < 6) {
		return gateWaypoint(p, gateOpen, layout)
	}
	return target
}

func gateWaypoint(p Vec2, gateOpen bool, layout Layout) Vec2 {
	side := -1.0
	if p.X > 6 {
		side = 1
	}
	if !gateOpen || math.Abs(p.Y-layout.GateY) > 1.4 {
		return Vec2{6 + side*0.6, layout.GateY}
	}
	return Vec2{6 - side*0.6, layout.GateY}
}

func (w *World) moveTo(p, target Vec2, speed float64) Vec2 {
	d := waypoint(p, target, w.GateOpen, *w.Layout).Sub(p)
	return terrainStep(p, d.Unit().Mul(math.Min(d.Len(), speed/TickRate)), w.GateOpen, *w.Layout)
}

func (w *World) Step() {
	w.Tick++
	for i := range w.Players {
		p := &w.Players[i]
		if !p.Connected || p.State != "walking" {
			continue
		}
		p.Position = w.moveWithRoute(p.Position, p.Target, 4, &p.Route)
		if p.Position.Sub(p.Target).Len() < 0.08 {
			p.State = "idle"
			p.Route = nil
		}
	}
	for i := range w.Dogs {
		d := &w.Dogs[i]
		switch d.Command {
		case "come":
			if p := w.Player(d.Caller); p != nil {
				d.Target = p.Position
				if d.Position.Sub(d.Target).Len() < 1.2 {
					d.State = "attentive"
					d.Route = nil
					continue
				}
			}
		case "stay":
			continue
		case "go":
			if d.Position.Sub(d.Target).Len() < 0.15 {
				d.State = "attentive"
				d.Route = nil
				continue
			}
		default:
			// Gentle deterministic sniffing, with distinct tempos for both corgis.
			if (w.Tick+uint64(i)*50)%180 == 0 {
				phase := float64(w.Tick)*0.013 + float64(i)*2
				center := Vec2{-11, float64(i*4) - 2}
				if len(w.Players) > 0 {
					center = w.Players[i%len(w.Players)].Position
				}
				candidate := center.Add(Vec2{math.Cos(phase) * 2, math.Sin(phase) * 2})
				if w.Walkable(candidate) {
					d.Target = candidate
					d.Route = nil
				}
			}
		}
		d.Position = w.moveWithRoute(d.Position, d.Target, 4.6, &d.Route)
	}
	w.stepSheep()
}

func (w *World) stepSheep() {
	if w.Layout.Forage != nil {
		w.assignForagers()
	}
	previous := append([]Sheep(nil), w.Sheep...)
	w.Settled = 0
	for i := range w.Sheep {
		s := &w.Sheep[i]
		p := previous[i].Position
		cohesion, separation, alignment, pressure := Vec2{}, Vec2{}, Vec2{}, Vec2{}
		neighbors, fear := 0, 0.0
		for j, other := range previous {
			if i == j {
				continue
			}
			away := p.Sub(other.Position)
			distance := away.Len()
			if distance < 5 {
				cohesion = cohesion.Add(other.Position)
				alignment = alignment.Add(other.Velocity)
				neighbors++
			}
			if distance > 0.001 && distance < 1.1 {
				separation = separation.Add(away.Unit().Mul((1.1 - distance) * 1.8))
			}
		}
		if neighbors > 0 {
			cohesion = cohesion.Mul(1 / float64(neighbors)).Sub(p).Mul(0.1)
			alignment = alignment.Mul(0.15 / float64(neighbors))
		}
		for _, d := range w.Dogs {
			away := p.Sub(d.Position)
			distance := away.Len()
			if distance < 4.1 {
				force := (4.1 - distance) / 4.1
				pressure = pressure.Add(away.Unit().Mul(force * 3))
				fear = math.Max(fear, force)
			}
		}
		for _, herder := range w.Players {
			away := p.Sub(herder.Position)
			distance := away.Len()
			if distance < 2 {
				pressure = pressure.Add(away.Unit().Mul((2 - distance) * 0.65))
			}
		}
		phase := float64(w.Tick)*0.019 + float64(i)*2.39
		wander := Vec2{math.Cos(phase), math.Sin(phase * 0.73)}.Mul(0.08)
		velocity := cohesion.Add(separation).Add(alignment).Add(pressure).Add(wander)
		s.State = "grazing"
		if fear > 0.5 {
			s.State = "fleeing"
		} else if fear > 0.08 || velocity.Len() > 0.35 {
			s.State = "walking"
		}
		if w.Layout.Region != nil {
			velocity = regionSheepSteering(p, velocity, fear, *w.Layout.Region)
		} else if w.Layout.Commons != nil {
			velocity = cloudSheepSteering(p, velocity, fear, w.Layout.Commons.shore().corridor())
		} else if w.Layout.Shore != nil {
			velocity = cloudSheepSteering(p, velocity, fear, w.Layout.Shore.corridor())
		} else if w.Layout.Ridge != nil {
			velocity = cloudSheepSteering(p, velocity, fear, *w.Layout.Ridge)
		} else if w.Layout.RockPass != nil {
			velocity = rockSheepSteering(p, velocity, fear, *w.Layout.RockPass)
		} else {
			// Near water/fence, nervous sheep seek the visible opening, then cross.
			if p.X > -4.5 && p.X < -1.5 && velocity.X > 0.06 && fear > 0.08 {
				velocity.Y += (w.Layout.BridgeY - p.Y) * 0.8
			}
			if p.X > 1.5 && p.X < 4.5 && velocity.X < -0.06 && fear > 0.08 {
				velocity.Y += (w.Layout.BridgeY - p.Y) * 0.8
			}
			if p.X > 3 && p.X < 6 && velocity.X > 0.06 && fear > 0.08 {
				velocity.Y += (w.Layout.GateY - p.Y) * 0.8
			}
			if p.X > 6 && p.X < 9 && velocity.X < -0.06 && fear > 0.08 {
				velocity.Y += (w.Layout.GateY - p.Y) * 0.8
			}
			if math.Abs(p.X) < 1.8 {
				velocity.Y += (w.Layout.BridgeY - p.Y) * 0.8
			}
		}
		if w.Layout.Region != nil {
			if fear == 0 && regionClearing(p, *w.Layout.Region) {
				velocity = velocity.Mul(.28)
				s.State = "grazing"
			}
		} else if w.Layout.Commons != nil {
			if fear == 0 && ridgeShelf(p, w.Layout.Commons.shore().corridor()) {
				velocity = velocity.Mul(.28)
				s.State = "grazing"
			}
		} else if w.Layout.Shore != nil {
			if fear == 0 && ridgeShelf(p, w.Layout.Shore.corridor()) {
				velocity = velocity.Mul(.28)
				s.State = "grazing"
			}
		} else if w.Layout.Ridge != nil {
			if fear == 0 && ridgeShelf(p, *w.Layout.Ridge) {
				velocity = velocity.Mul(.28)
				s.State = "grazing"
			}
		} else if p.X > 8 && fear < 0.08 {
			velocity = velocity.Mul(0.28)
			s.State = "grazing"
		}
		if w.Layout.Forage != nil && s.Forage != nil && !s.Forage.Satiated && fear == 0 && w.forageCalm(p) {
			zone := w.Layout.Forage
			if p.Sub(zone.Center).Len() <= zone.Radius+2.5 {
				if p.Sub(zone.Center).Len() <= zone.Radius*0.65 {
					s.State = "nibbling"
					velocity = separation.Mul(0.1).Add(wander.Mul(0.1))
					s.Forage.RemainingTicks--
					if s.Forage.RemainingTicks == 0 {
						s.Forage.Satiated = true
						s.State = "grazing"
					}
				} else {
					s.State = "foraging"
					velocity = velocity.Mul(0.25).Add(zone.Center.Sub(p).Unit().Mul(0.55))
				}
			}
		}
		if velocity.Len() > 2.6 {
			velocity = velocity.Unit().Mul(2.6)
		}
		s.Position = terrainStep(p, velocity.Mul(1.0/TickRate), w.GateOpen, *w.Layout)
		s.Velocity = s.Position.Sub(p).Mul(TickRate)
		if w.Layout.Ridge != nil {
			if inShelf(s.Position, w.Layout.Ridge.Rest) {
				w.Settled++
			}
		} else if w.Layout.Shore == nil && w.Layout.Commons == nil && w.Layout.Region == nil && s.Position.X > 8 {
			w.Settled++
		}
	}
	w.cluster()
}

// Connected components preserve separate local flocks when sheep drift apart.
func (w *World) cluster() {
	seen := make([]bool, len(w.Sheep))
	group := 0
	for i := range w.Sheep {
		if seen[i] {
			continue
		}
		seen[i] = true
		queue := []int{i}
		for len(queue) > 0 {
			j := queue[0]
			queue = queue[1:]
			w.Sheep[j].Group = group
			for k := range w.Sheep {
				if !seen[k] && w.Sheep[j].Position.Sub(w.Sheep[k].Position).Len() < 4 {
					seen[k] = true
					queue = append(queue, k)
				}
			}
		}
		group++
	}
}
