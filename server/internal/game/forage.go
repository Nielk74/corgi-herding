package game

import "errors"

// Windfall is one small detour for at most two individual sheep over the herd's
// lifetime. Their assignment and partially completed nibble never reset.
func (w *World) assignForagers() {
	zone := w.Layout.Forage
	assigned := 0
	for _, s := range w.Sheep {
		if s.Forage != nil {
			assigned++
		}
	}
	for assigned < 2 {
		nearest := -1
		distance := zone.Radius + 2.5
		for i, s := range w.Sheep {
			if s.Forage != nil || s.State != "grazing" || !w.forageCalm(s.Position) {
				continue
			}
			candidate := s.Position.Sub(zone.Center).Len()
			if candidate < distance {
				nearest, distance = i, candidate
			}
		}
		if nearest < 0 {
			return
		}
		w.Sheep[nearest].Forage = &SheepForage{ZoneID: zone.ID, RemainingTicks: ForageNibbleTicks}
		assigned++
	}
}

func (w *World) forageCalm(p Vec2) bool {
	for _, dog := range w.Dogs {
		if dog.Position.Sub(p).Len() < 4.1 {
			return false
		}
	}
	for _, player := range w.Players {
		if player.Position.Sub(p).Len() < 2 {
			return false
		}
	}
	return true
}

// ValidateForage rejects invented zones, impossible progress, and extra
// reservations before an actor can resume a checkpoint.
func (w *World) ValidateForage() error {
	assigned := 0
	for _, s := range w.Sheep {
		active := s.State == "foraging" || s.State == "nibbling"
		if s.Forage == nil {
			if active {
				return errors.New("active forage state lacks saved progress")
			}
			continue
		}
		assigned++
		f := s.Forage
		if w.Layout.Forage == nil || f.ZoneID != w.Layout.Forage.ID || f.RemainingTicks < 0 || f.RemainingTicks > ForageNibbleTicks || f.Satiated != (f.RemainingTicks == 0) {
			return errors.New("invalid saved sheep forage progress")
		}
		if f.Satiated && active {
			return errors.New("satiated sheep cannot still be foraging")
		}
		if active && s.Position.Sub(w.Layout.Forage.Center).Len() > w.Layout.Forage.Radius+2.7 {
			return errors.New("active forager is outside its saved zone")
		}
		if s.State == "nibbling" && s.Position.Sub(w.Layout.Forage.Center).Len() > w.Layout.Forage.Radius*.65+.1 {
			return errors.New("nibbling sheep is outside the windfall")
		}
	}
	if assigned > 2 {
		return errors.New("too many saved windfall foragers")
	}
	return nil
}
