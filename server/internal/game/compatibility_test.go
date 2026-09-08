package game

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"math"
	"testing"
)

// These traces were captured before adding Orchard. Rounding removes irrelevant
// platform math last-bit differences while preserving all gameplay state/events.
func TestExistingLandscapeSimulationTraces(t *testing.T) {
	expected := map[string]string{
		LandscapeAlpine:  "2cbbeb2aef2c339f869b0baac0b9adbabf7c381c714b0d06863c4dd131b9b5aa",
		LandscapeCactus:  "675c3e86d62ebb91c42432ad91e329699982d1655586a73605fbdd223f2fefb6",
		LandscapeLarch:   "83a545051ca6e0e2518274a70efce2316ea50f8702c9b673f1ceaafb55d67821",
		LandscapeOrchard: "5f1dbe8e7a57443d0882a82ee31fe8739398ae1242397ff18a7516dd051a422c",
	}
	for landscape, want := range expected {
		t.Run(landscape, func(t *testing.T) {
			w := herderWorld(t)
			w.Landscape = landscape
			w.Layout = LayoutForLandscape(landscape)
			hash := sha256.New()
			for tick := 0; tick < 700; tick++ {
				switch tick {
				case 0:
					_ = w.Apply("a", Input{Type: "move", Seq: 1, Target: &Vec2{0, w.Layout.BridgeY}})
				case 110:
					_ = w.Apply("a", Input{Type: "move", Seq: 2, Target: &Vec2{5.4, w.Layout.GateY}})
				case 250:
					_ = w.Apply("a", Input{Type: "interact", Action: "gate"})
				case 260:
					_ = w.Apply("a", Input{Type: "move", Seq: 3, Target: &Vec2{11, 5}})
				case 300:
					_ = w.Apply("b", Input{Type: "command", DogID: "mochi", Command: "come"})
				case 340:
					_ = w.Apply("a", Input{Type: "command", DogID: "maple", Command: "go", Target: &Vec2{3, 4}})
				case 500:
					_ = w.Apply("a", Input{Type: "move", Seq: 4, Target: &Vec2{-9, -7}})
				}
				w.Step()
				snapshot := w.Clone()
				for i := range snapshot.Players {
					snapshot.Players[i].Position = roundTrace(snapshot.Players[i].Position)
					snapshot.Players[i].Target = roundTrace(snapshot.Players[i].Target)
				}
				for i := range snapshot.Dogs {
					snapshot.Dogs[i].Position = roundTrace(snapshot.Dogs[i].Position)
					snapshot.Dogs[i].Target = roundTrace(snapshot.Dogs[i].Target)
				}
				for i := range snapshot.Sheep {
					snapshot.Sheep[i].Position = roundTrace(snapshot.Sheep[i].Position)
					snapshot.Sheep[i].Velocity = roundTrace(snapshot.Sheep[i].Velocity)
				}
				data, err := json.Marshal(snapshot)
				if err != nil {
					t.Fatal(err)
				}
				_, _ = hash.Write(data)
			}
			got := hex.EncodeToString(hash.Sum(nil))
			if got != want {
				t.Fatalf("existing landscape behavior changed: got %s want %s", got, want)
			}
		})
	}
}

func roundTrace(v Vec2) Vec2 { return Vec2{math.Round(v.X*1e6) / 1e6, math.Round(v.Y*1e6) / 1e6} }
