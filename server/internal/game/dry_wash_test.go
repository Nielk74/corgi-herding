package game

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"os"
	"reflect"
	"slices"
	"sync"
	"testing"
)

func TestDryWashCanonicalRegistrySpawnsAndIndependentCache(t *testing.T) {
	w := dryWashWorld(t)
	r := w.Layout.Region
	data, err := os.ReadFile("../../../protocol/dry-wash-region.json")
	if err != nil {
		t.Fatal(err)
	}
	if fmt.Sprintf("%x", sha256.Sum256(data)) != "a17b3f8734cf8aed2377986077bf6104fcb96d9535fdf6b7725dc08725b25f54" {
		t.Fatal("approved geometry file changed")
	}
	var fixture Region
	if err = json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	if !r.equal(&fixture) || len(r.Anchors) != 14 || len(r.Corridors) != 13 || len(r.Clearings) != 14 || w.Layout.Version != 8 {
		t.Fatal("noncanonical dry wash")
	}
	for i, p := range w.Players {
		if p.Position != (Vec2{-44 + float64(i)*3, 79}) {
			t.Fatal("herder spawn changed")
		}
	}
	for i, d := range w.Dogs {
		if d.Position != (Vec2{-43 + float64(i)*3, 76.8}) {
			t.Fatal("dog spawn changed")
		}
	}
	for i, s := range w.Sheep {
		if s.Position != (Vec2{-39.7 + float64(i%3), 66.4 + float64(i/3)*1.05}) {
			t.Fatal("sheep spawn changed")
		}
		for _, d := range w.Dogs {
			if s.Position.Sub(d.Position).Len() < 4.1 {
				t.Fatal("spawn dog pressure")
			}
		}
	}
	for cap := -1; cap <= 9; cap++ {
		if w.SupportsLayout(cap) != (cap == 8) {
			t.Fatal("capability accepted", cap)
		}
	}
	if w.SupportsLayout(99) {
		t.Fatal("unknown capability accepted")
	}
	_, alpine := registeredRegion(LandscapeAlpineValley)
	if r.graph == nil || r.graph == alpine.graph {
		t.Fatal("recipe caches not independent")
	}
	copy := w.Clone()
	if copy.Layout.Region.graph != r.graph {
		t.Fatal("clone rebuilt immutable graph")
	}
	copy.Layout.Region.Anchors[0].X++
	copy.Layout.Region.Corridors[0].HalfWidth++
	copy.Layout.Region.Clearings[0].Radius++
	copy.Layout.Region.Bounds.Min.X++
	if !r.equal(&fixture) || copy.ValidateLayout() == nil {
		t.Fatal("mutable clone accepted/aliased canonical")
	}
	var wg sync.WaitGroup
	for i := 0; i < 32; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, other := registeredRegion(LandscapeDryWash)
			if !other.equal(r) || other.graph != r.graph {
				t.Error("registry mismatch")
			}
			other.Anchors[0].X++
		}()
	}
	wg.Wait()
	_, unchanged := registeredRegion(LandscapeDryWash)
	if !unchanged.equal(&fixture) {
		t.Fatal("registry geometry mutated")
	}
	if version, unknown := registeredRegion("untrusted"); version != 0 || unknown != nil {
		t.Fatal("arbitrary recipe registered")
	}
}

func TestDryWashBothHerdersAndDogsAllAnchorsRetargetAndQuiet(t *testing.T) {
	w := dryWashWorld(t)
	targets := slices.Clone(w.Layout.Region.Anchors)
	reverse := slices.Clone(targets)
	slices.Reverse(reverse)
	targets = append(targets, reverse...)
	for leg, target := range targets {
		for _, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(leg + 1), Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		for i, dog := range []string{"mochi", "maple"} {
			sendHerdDog(t, w, []string{"a", "b"}[(i+leg)%2], dog, target)
		}
		for tick := 0; tick < 2200; tick++ {
			stepRegionChecked(t, w)
			if w.Players[0].State == "idle" && w.Players[1].State == "idle" && w.Dogs[0].State == "attentive" && w.Dogs[1].State == "attentive" {
				break
			}
		}
		for _, p := range w.Players {
			if p.Position.Sub(target).Len() > .08 || p.State != "idle" || len(p.Route) > 0 {
				t.Fatal("herder route stalled", leg, p)
			}
		}
		for _, d := range w.Dogs {
			if d.Position.Sub(target).Len() > .15 || len(d.Route) > 0 {
				t.Fatal("dog route stalled", leg, d)
			}
		}
	}
	for turn := 0; turn < 100; turn++ {
		target := w.Layout.Region.Anchors[(turn*5)%14]
		for _, id := range []string{"a", "b"} {
			if err := w.Apply(id, Input{Type: "move", Seq: uint64(100 + turn), Target: &target}); err != nil {
				t.Fatal(err)
			}
		}
		goDog, comeDog := "mochi", "maple"
		if turn%2 != 0 {
			goDog, comeDog = comeDog, goDog
		}
		sendHerdDog(t, w, []string{"a", "b"}[(turn/2)%2], goDog, target)
		if err := w.Apply([]string{"a", "b"}[(turn/2+1)%2], Input{Type: "command", DogID: comeDog, Command: "come"}); err != nil {
			t.Fatal(err)
		}
		for tick := 0; tick < 7; tick++ {
			stepRegionChecked(t, w)
		}
	}
	for _, id := range []string{"a", "b"} {
		if err := w.Apply(id, Input{Type: "interact", Action: "sit"}); err != nil {
			t.Fatal(err)
		}
	}
	for _, dog := range []string{"mochi", "maple"} {
		if err := w.Apply("a", Input{Type: "command", DogID: dog, Command: "stay"}); err != nil {
			t.Fatal(err)
		}
	}
	before := w.Clone()
	for tick := 0; tick < 40; tick++ {
		stepRegionChecked(t, w)
	}
	for i, p := range w.Players {
		if p.Position != before.Players[i].Position || len(p.Route) > 0 {
			t.Fatal("sit moved")
		}
	}
	for i, d := range w.Dogs {
		if d.Position != before.Dogs[i].Position || len(d.Route) > 0 {
			t.Fatal("stay moved")
		}
	}
}

func TestDryWashBoundaryConnectivityCachedVisibilityAndSpeed(t *testing.T) {
	w := dryWashWorld(t)
	r := *w.Layout.Region
	uncached := r
	uncached.graph = nil
	blocked := 0
	for i, a := range r.Anchors {
		for j, b := range r.Anchors {
			if i != j && r.graph.visible[i][j] != RegionVisible(a, b, r) {
				t.Fatal("cached edge mismatch", i, j)
			}
			if !reflect.DeepEqual(RegionRoute(a, b, r), RegionRoute(a, b, uncached)) {
				t.Fatal("cache changed route", i, j)
			}
			if !RegionVisible(a, b, r) {
				blocked++
			}
		}
	}
	if blocked != 100 {
		t.Fatal("whole-segment branches changed", blocked)
	}
	for _, e := range r.Corridors {
		if !RegionVisible(r.Anchors[e.A], r.Anchors[e.B], r) {
			t.Fatal("declared capsule not covered", e)
		}
	}
	points := regionBoundaryPoints(r)
	for _, p := range points {
		connected := false
		for _, a := range r.Anchors {
			if RegionVisible(p, a, r) {
				connected = true
				break
			}
		}
		if !connected {
			t.Fatalf("strict legal boundary stranded %.17g", p)
		}
	}
	rng := rand.New(rand.NewSource(808))
	for i := 0; i < 3000; i++ {
		from, target := points[rng.Intn(len(points))], points[rng.Intn(len(points))]
		if RegionVisible(from, target, r) != RegionVisible(target, from, r) {
			t.Fatalf("asymmetric boundary %.17g %.17g", from, target)
		}
		if i >= 200 {
			continue
		}
		route := RegionRoute(from, target, r)
		if !validRegionRoute(from, target, route, r) {
			t.Fatal("unsafe boundary queue", from, target)
		}
		p := from
		for tick := 0; tick < 2200 && p.Sub(target).Len() > .08; tick++ {
			before := p
			p = w.moveOnRegion(p, target, 4, &route)
			if !RegionVisible(before, p, r) || p.Sub(before).Len() > .20000001 {
				t.Fatal("boundary motion unsafe")
			}
		}
		if p.Sub(target).Len() > .08 {
			t.Fatalf("boundary route stalled %.17g -> %.17g at %.17g", from, target, p)
		}
	}
	for _, p := range []Vec2{{-72, 96}, {73, 0}, {0, 97}, {math.NaN(), 0}, {math.Inf(1), 0}} {
		if RegionVisible(p, r.Anchors[0], r) || RegionVisible(r.Anchors[0], p, r) || RegionWalkable(p, r) || len(RegionRoute(p, r.Anchors[0], r)) > 0 {
			t.Fatal("invalid endpoint accepted", p)
		}
	}
	// Both endpoints are legal; their western/eastern shortcut crosses dry void.
	if RegionVisible(r.Anchors[10], r.Anchors[12], r) {
		t.Fatal("endpoint-only cross-wash shortcut")
	}
	t.Logf("%d exact legal boundaries; 3000 symmetric pairs; 200 complete boundary walks", len(points))
}

func TestDryWashSharedRoutesAndIEEEBoundaries(t *testing.T) {
	r := *dryWashWorld(t).Layout.Region
	for _, name := range []string{"routes", "boundaries"} {
		data, err := os.ReadFile("../../../protocol/dry-wash-" + name + ".json")
		if err != nil {
			t.Fatal(err)
		}
		var fixtures []regionBoundaryFixture
		if err = json.Unmarshal(data, &fixtures); err != nil {
			t.Fatal(err)
		}
		want := 64
		if name == "boundaries" {
			want = 36
		}
		if len(fixtures) != want {
			t.Fatal("missing dry-wash fixtures", name, len(fixtures))
		}
		for _, f := range fixtures {
			if name == "boundaries" {
				bits := func(p Vec2) regionBits {
					return regionBits{fmt.Sprintf("%016x", math.Float64bits(p.X)), fmt.Sprintf("%016x", math.Float64bits(p.Y))}
				}
				if bits(f.From) != f.FromBits || bits(f.Target) != f.TargetBits {
					t.Fatal("decimal/IEEE mismatch", f.Name)
				}
			}
			assertRegionFixture(t, r, f.regionFixture)
		}
	}
}
