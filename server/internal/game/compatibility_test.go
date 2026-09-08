package game

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"reflect"
	"regexp"
	"sort"
	"testing"
)

// These traces were captured before adding Orchard. Rounding removes irrelevant
// platform math last-bit differences while preserving all gameplay state/events.
func TestExistingLandscapeSimulationTraces(t *testing.T) {
	expected := map[string]string{
		LandscapeAlpine: "2cbbeb2aef2c339f869b0baac0b9adbabf7c381c714b0d06863c4dd131b9b5aa",
		LandscapeCactus: "675c3e86d62ebb91c42432ad91e329699982d1655586a73605fbdd223f2fefb6",
		LandscapeLarch:  "83a545051ca6e0e2518274a70efce2316ea50f8702c9b673f1ceaafb55d67821",
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

// The old rounded Orchard hash depended on JSON -0 versus 0 at tick 69. Compare
// all 700 complete build 7 snapshots instead: discrete state and structure remain
// exact, while only continuous actor coordinates tolerate platform last bits.
// Measured build 7 arm64/amd64 maximum divergence was 3.552713678800501e-14.
// This 1e-12 bound is substantially stricter than the old 1e-6 quantization.
const orchardTraceTolerance = 1e-12

var traceCoordinatePath = regexp.MustCompile(`^\$\.(players|dogs)\[[0-9]+\]\.(position|target)\.[xy]$|^\$\.sheep\[[0-9]+\]\.(position|velocity)\.[xy]$`)

func TestOrchardBuild7PortableTrace(t *testing.T) {
	baseline := loadOrchardBuild7Trace(t)
	w := herderWorld(t)
	w.Landscape, w.Layout = LandscapeOrchard, LayoutForLandscape(LandscapeOrchard)
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
		if err := compareOrchardTrace(traceJSON(t, w.Clone()), baseline[tick], "$"); err != nil {
			t.Fatalf("build 7 Orchard behavior changed at tick %d: %v", w.Tick, err)
		}
	}
}

func loadOrchardBuild7Trace(t *testing.T) []any {
	t.Helper()
	return loadCompressedTrace(t, "testdata/build7-orchard.jsonl.gz.b64", "7e49ebeb9c95cb9f42d19db90734de0c2fc510b9081b173a5a76b6430de3dba4")
}

func loadCompressedTrace(t *testing.T, path, checksum string) []any {
	t.Helper()
	encoded, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	compressed := base64.NewDecoder(base64.StdEncoding, bytes.NewReader(encoded))
	reader, err := gzip.NewReader(compressed)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	data, err := io.ReadAll(io.LimitReader(reader, 2<<20))
	if err != nil {
		t.Fatal(err)
	}
	if sum := fmt.Sprintf("%x", sha256.Sum256(data)); sum != checksum {
		t.Fatalf("%s reference provenance/checksum changed: %s", path, sum)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber() // Sequences/ticks must remain exact, including beyond 2^53.
	var snapshots []any
	for {
		var snapshot any
		if err := decoder.Decode(&snapshot); err == io.EOF {
			break
		} else if err != nil {
			t.Fatal(err)
		}
		snapshots = append(snapshots, snapshot)
	}
	if len(snapshots) != 700 {
		t.Fatalf("incomplete %s reference: %d snapshots", path, len(snapshots))
	}
	return snapshots
}

func traceJSON(t *testing.T, value any) any {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	var decoded any
	if err = decoder.Decode(&decoded); err != nil {
		t.Fatal(err)
	}
	return decoded
}

func compareOrchardTrace(actual, expected any, path string) error {
	switch want := expected.(type) {
	case map[string]any:
		got, ok := actual.(map[string]any)
		if !ok || len(got) != len(want) {
			return fmt.Errorf("%s object fields changed", path)
		}
		keys := make([]string, 0, len(want))
		for key := range want {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			value, exists := got[key]
			if !exists {
				return fmt.Errorf("%s.%s field missing", path, key)
			}
			if err := compareOrchardTrace(value, want[key], path+"."+key); err != nil {
				return err
			}
		}
	case []any:
		got, ok := actual.([]any)
		if !ok || len(got) != len(want) {
			return fmt.Errorf("%s array changed", path)
		}
		for i := range want {
			if err := compareOrchardTrace(got[i], want[i], fmt.Sprintf("%s[%d]", path, i)); err != nil {
				return err
			}
		}
	case json.Number:
		got, ok := actual.(json.Number)
		if !ok {
			return fmt.Errorf("%s number type changed", path)
		}
		if traceCoordinatePath.MatchString(path) {
			a, aErr := got.Float64()
			b, bErr := want.Float64()
			if aErr != nil || bErr != nil || math.IsNaN(a) || math.IsInf(a, 0) || math.Abs(a-b) > orchardTraceTolerance {
				return fmt.Errorf("%s coordinate changed: got %s want %s (bound %g)", path, got, want, orchardTraceTolerance)
			}
		} else if got != want {
			return fmt.Errorf("%s exact number changed: got %s want %s", path, got, want)
		}
	default:
		if !reflect.DeepEqual(actual, expected) {
			return fmt.Errorf("%s state changed: got %v want %v", path, actual, expected)
		}
	}
	return nil
}

func TestOrchardTraceComparisonRejectsBehaviorMutations(t *testing.T) {
	baseline := loadOrchardBuild7Trace(t)[0]
	for _, tc := range []struct {
		name   string
		mutate func(map[string]any)
	}{
		{"state", func(w map[string]any) { w["sheep"].([]any)[0].(map[string]any)["state"] = "fleeing" }},
		{"feeding_progress", func(w map[string]any) { traceForage(w)["remaining_ticks"] = json.Number("79") }},
		{"feeding_satiation", func(w map[string]any) { traceForage(w)["satiated"] = true }},
		{"feeding_zone", func(w map[string]any) { traceForage(w)["zone_id"] = "changed" }},
		{"sequence", func(w map[string]any) {
			w["players"].([]any)[0].(map[string]any)["seq"] = json.Number("9007199254740993")
		}},
		{"tick", func(w map[string]any) { w["tick"] = json.Number("2") }},
		{"layout_tiny_change", func(w map[string]any) {
			w["layout"].(map[string]any)["forage"].(map[string]any)["radius"] = json.Number("2.2000000000001")
		}},
		{"position_outside_tolerance", func(w map[string]any) { shiftTraceCoordinate(w, "players", "position", 2e-12) }},
		{"velocity_outside_tolerance", func(w map[string]any) { shiftTraceCoordinate(w, "sheep", "velocity", 2e-12) }},
		{"target_outside_tolerance", func(w map[string]any) { shiftTraceCoordinate(w, "dogs", "target", 2e-12) }},
		{"unknown_field", func(w map[string]any) { w["players"].([]any)[0].(map[string]any)["route"] = []any{} }},
		{"missing_field", func(w map[string]any) { delete(w, "gate_open") }},
		{"missing_sheep", func(w map[string]any) { w["sheep"] = w["sheep"].([]any)[:9] }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			changed := traceJSON(t, baseline).(map[string]any)
			tc.mutate(changed)
			if err := compareOrchardTrace(changed, baseline, "$"); err == nil {
				t.Fatal("changed behavior accepted by portable trace comparison")
			}
		})
	}
	changed := traceJSON(t, baseline).(map[string]any)
	shiftTraceCoordinate(changed, "players", "position", 1e-13)
	if err := compareOrchardTrace(changed, baseline, "$"); err != nil {
		t.Fatalf("bounded floating-point noise rejected: %v", err)
	}
	if err := compareOrchardTrace(json.Number("-0"), json.Number("0"), "$.players[0].position.x"); err != nil {
		t.Fatal("signed coordinate zero rejected")
	}
	if err := compareOrchardTrace(json.Number("9007199254740993"), json.Number("9007199254740992"), "$.players[0].seq"); err == nil {
		t.Fatal("integer comparison lost precision beyond 2^53")
	}
}

func traceForage(w map[string]any) map[string]any {
	for _, entry := range w["sheep"].([]any) {
		if forage, ok := entry.(map[string]any)["forage"].(map[string]any); ok {
			return forage
		}
	}
	panic("build 7 first-snapshot fixture unexpectedly lacks forage")
}

func shiftTraceCoordinate(w map[string]any, kind, vector string, amount float64) {
	coordinate := w[kind].([]any)[0].(map[string]any)[vector].(map[string]any)
	n, _ := coordinate["x"].(json.Number).Float64()
	coordinate["x"] = json.Number(fmt.Sprintf("%.17g", n+amount))
}
