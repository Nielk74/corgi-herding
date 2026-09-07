// Package game is the platform-independent authoritative meadow simulation.
package game

import (
	"errors"
	"fmt"
	"math"
)

const TickRate = 20

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
}

type Dog struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Position Vec2   `json:"position"`
	Target   Vec2   `json:"target"`
	State    string `json:"state"`
	Command  string `json:"command"`
	Caller   string `json:"caller,omitempty"`
}

type Sheep struct {
	ID       string `json:"id"`
	Position Vec2   `json:"position"`
	Velocity Vec2   `json:"velocity"`
	State    string `json:"state"`
	Group    int    `json:"group"`
}

type World struct {
	Type     string   `json:"type"`
	Tick     uint64   `json:"tick"`
	Code     string   `json:"code"`
	GateOpen bool     `json:"gate_open"`
	Settled  int      `json:"settled"`
	Players  []Player `json:"players"`
	Dogs     []Dog    `json:"dogs"`
	Sheep    []Sheep  `json:"sheep"`
}

type Input struct {
	Type     string `json:"type"`
	Seq      uint64 `json:"seq,omitempty"`
	Target   *Vec2  `json:"target,omitempty"`
	DogID    string `json:"dog_id,omitempty"`
	Command  string `json:"command,omitempty"`
	Action   string `json:"action,omitempty"`
	PlayerID string `json:"player_id,omitempty"`
	Token    string `json:"token,omitempty"`
}

func New(code string) *World {
	w := &World{Type: "snapshot", Code: code, Players: []Player{}, Dogs: []Dog{
		{ID: "mochi", Name: "Mochi", Position: Vec2{-11, -2}, Target: Vec2{-11, -2}, State: "wander"},
		{ID: "maple", Name: "Maple", Position: Vec2{-11, 2}, Target: Vec2{-11, 2}, State: "wander"},
	}}
	for i := 0; i < 10; i++ {
		w.Sheep = append(w.Sheep, Sheep{ID: fmt.Sprintf("s%d", i+1), Position: Vec2{-7 + float64(i%3)*1.15, -2 + float64(i/3)*1.15}, State: "grazing"})
	}
	return w
}

func (w *World) Clone() *World {
	n := *w
	n.Players = append([]Player{}, w.Players...)
	n.Dogs = append([]Dog{}, w.Dogs...)
	n.Sheep = append([]Sheep{}, w.Sheep...)
	return &n
}

func (w *World) AddPlayer(id, name string) error {
	if len(w.Players) >= 2 {
		return errors.New("this herd already has two herders")
	}
	p := Vec2{-13, -1.5 + float64(len(w.Players))*3}
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
		if in.Seq == 0 || in.Target == nil || !in.Target.Valid() {
			return errors.New("move needs a positive sequence and a target inside the meadow")
		}
		if in.Seq <= p.Seq {
			return nil
		}
		if !Walkable(*in.Target, w.GateOpen) {
			return errors.New("choose somewhere on dry land")
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
		switch in.Command {
		case "come":
			d.Target = p.Position
		case "stay":
			d.Target = d.Position
		case "go":
			if in.Target == nil || !in.Target.Valid() || !Walkable(*in.Target, w.GateOpen) {
				return errors.New("choose a dry-land destination for the corgi")
			}
			d.Target = *in.Target
		default:
			return errors.New("unknown dog command")
		}
		d.Command, d.Caller, d.State = in.Command, playerID, in.Command
	case "interact":
		switch in.Action {
		case "gate":
			if p.Position.Sub(Vec2{6, 0}).Len() > 3 {
				return errors.New("walk closer to the gate")
			}
			// Once opened, the gate stays open so animals cannot become trapped in it.
			w.GateOpen = true
		case "sit":
			p.Target, p.State = p.Position, "sitting"
		case "pet":
			for i := range w.Dogs {
				d := &w.Dogs[i]
				if d.ID == in.DogID && d.Position.Sub(p.Position).Len() <= 2.5 {
					d.State, d.Command, d.Target = "happy", "stay", d.Position
					p.Target, p.State = p.Position, "petting"
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
	if !p.Valid() {
		return false
	}
	if math.Abs(p.X) < 1.5 && math.Abs(p.Y) > 1.85 {
		return false
	}
	if math.Abs(p.X-6) < 0.18 && (!gateOpen || math.Abs(p.Y) > 1.8) {
		return false
	}
	return true
}

// terrainStep is also used for flock forces; every small step is collision checked.
func terrainStep(p, delta Vec2, gateOpen bool) Vec2 {
	pieces := max(1, int(math.Ceil(delta.Len()/0.08)))
	delta = delta.Mul(1 / float64(pieces))
	for i := 0; i < pieces; i++ {
		n := p.Add(delta)
		if Walkable(n, gateOpen) {
			p = n
			continue
		}
		n = p.Add(Vec2{delta.X, 0})
		if Walkable(n, gateOpen) {
			p = n
		}
		n = p.Add(Vec2{0, delta.Y})
		if Walkable(n, gateOpen) {
			p = n
		}
	}
	return p
}

// Waypoints route both people and dogs onto the bridge before crossing water.
func waypoint(p, target Vec2, gateOpen bool) Vec2 {
	if p.X < -1.5 && target.X > -1.5 {
		if math.Abs(p.Y) > 1.4 {
			return Vec2{-2.1, 0}
		}
		if target.X < 1.5 {
			return target
		}
		return Vec2{2.1, 0}
	}
	if p.X > 1.5 && target.X < 1.5 {
		if math.Abs(p.Y) > 1.4 {
			return Vec2{2.1, 0}
		}
		if target.X > -1.5 {
			return target
		}
		return Vec2{-2.1, 0}
	}
	if math.Abs(p.X) <= 1.5 {
		if math.Abs(target.X) <= 1.5 {
			return target
		}
		if target.X >= 0 {
			return Vec2{2.1, 0}
		}
		return Vec2{-2.1, 0}
	}
	if (p.X < 6 && target.X > 6) || (p.X > 6 && target.X < 6) {
		side := -1.0
		if p.X > 6 {
			side = 1
		}
		if !gateOpen || math.Abs(p.Y) > 1.4 {
			return Vec2{6 + side*0.6, 0}
		}
		return Vec2{6 - side*0.6, 0}
	}
	return target
}

func moveTo(p, target Vec2, speed float64, gateOpen bool) Vec2 {
	d := waypoint(p, target, gateOpen).Sub(p)
	return terrainStep(p, d.Unit().Mul(math.Min(d.Len(), speed/TickRate)), gateOpen)
}

func (w *World) Step() {
	w.Tick++
	for i := range w.Players {
		p := &w.Players[i]
		if !p.Connected || p.State != "walking" {
			continue
		}
		p.Position = moveTo(p.Position, p.Target, 4, w.GateOpen)
		if p.Position.Sub(p.Target).Len() < 0.08 {
			p.State = "idle"
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
					continue
				}
			}
		case "stay":
			continue
		case "go":
			if d.Position.Sub(d.Target).Len() < 0.15 {
				d.State = "attentive"
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
				if Walkable(candidate, w.GateOpen) {
					d.Target = candidate
				}
			}
		}
		d.Position = moveTo(d.Position, d.Target, 4.6, w.GateOpen)
	}
	w.stepSheep()
}

func (w *World) stepSheep() {
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
		// Near water/fence, nervous sheep seek the visible opening, then cross.
		if p.X > -4.5 && p.X < -1.5 && velocity.X > 0.06 && fear > 0.08 {
			velocity.Y += -p.Y * 0.8
		}
		if p.X > 1.5 && p.X < 4.5 && velocity.X < -0.06 && fear > 0.08 {
			velocity.Y += -p.Y * 0.8
		}
		if p.X > 3 && p.X < 6 && velocity.X > 0.06 && fear > 0.08 {
			velocity.Y += -p.Y * 0.8
		}
		if math.Abs(p.X) < 1.8 {
			velocity.Y += -p.Y * 0.8
		}
		if p.X > 8 && fear < 0.08 {
			velocity = velocity.Mul(0.28)
			s.State = "grazing"
		}
		if velocity.Len() > 2.6 {
			velocity = velocity.Unit().Mul(2.6)
		}
		s.Position = terrainStep(p, velocity.Mul(1.0/TickRate), w.GateOpen)
		s.Velocity = s.Position.Sub(p).Mul(TickRate)
		if s.Position.X > 8 {
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
