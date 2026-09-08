package game

import "sync"

// Only these server-authored recipes may back a world. Cached adjacency is
// immutable, built once per landscape, and never accepted from JSON. Callers
// receive independent geometry slices; an existing herd cannot mutate another.
var regionRecipes = map[string]struct {
	version int
	load    func() *Region
}{
	LandscapeAlpineValley: {7, cachedRegion(canonicalRegion)},
	LandscapeDryWash:      {8, cachedRegion(canonicalDryWashRegion)},
}

func cachedRegion(build func() *Region) func() *Region {
	return sync.OnceValue(func() *Region {
		r := build()
		if err := r.ValidateGeometry(); err != nil {
			panic("invalid server-authored region: " + err.Error())
		}
		r.graph = compileRegionGraph(*r)
		return r
	})
}

func registeredRegion(landscape string) (int, *Region) {
	entry, ok := regionRecipes[landscape]
	if !ok {
		return 0, nil
	}
	return entry.version, entry.load().clone()
}

func canonicalDryWashRegion() *Region {
	r := &Region{RecipeID: "dry_wash_01", Bounds: Bounds{Vec2{-72, -96}, Vec2{72, 96}},
		Anchors:   []Vec2{{-38, 68}, {-10, 43}, {13, 14}, {-9, -12}, {-25, -40}, {2, -63}, {32, -76}, {-51, 40}, {22, 57}, {46, 24}, {47, -5}, {-39, 0}, {-48, -18}, {-51, -57}},
		Corridors: []RegionCorridor{{0, 1, 14}, {1, 2, 16}, {2, 3, 15}, {3, 4, 13}, {4, 5, 12}, {5, 6, 11}, {0, 7, 12}, {1, 8, 14}, {2, 9, 14}, {9, 10, 12}, {3, 11, 12}, {11, 12, 11}, {4, 13, 11}},
	}
	for i, radius := range []float64{22, 22, 26, 17, 22, 16, 18, 15, 19, 18, 16, 21, 15, 16} {
		r.Clearings = append(r.Clearings, Shelf{r.Anchors[i], radius})
	}
	return r
}
