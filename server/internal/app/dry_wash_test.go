package app

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"corgiherding/server/internal/game"
)

func TestDryWashHTTPRejectsArbitraryGeometryAndJoinOverride(t *testing.T) {
	s, h := newTestServer(t, t.TempDir(), 10)
	for _, body := range []string{
		`{"name":"Ada","landscape":"dry_wash","layout":{"version":8}}`,
		`{"name":"Ada","landscape":"dry_wash","region":{"recipe_id":"untrusted"}}`,
		`{"name":"Ada","landscape":"dry_wash_01"}`,
	} {
		post(t, h.URL+"/api/herds", body, 400)
	}
	if len(s.herds) != 0 {
		t.Fatal("bad create allocated a world")
	}
	var a, b credentials
	if err := json.Unmarshal(post(t, h.URL+"/api/herds", `{"name":"Ada","landscape":"dry_wash"}`, 201), &a); err != nil {
		t.Fatal(err)
	}
	post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea","landscape":"alpine_valley"}`, 400)
	if err := json.Unmarshal(post(t, h.URL+"/api/herds/"+a.Code+"/join", `{"name":"Bea"}`, 201), &b); err != nil {
		t.Fatal(err)
	}
	if a.PlayerID == b.PlayerID || b.Code != a.Code || len(s.find(a.Code).state.Load().World.Players) != 2 {
		t.Fatal("invalid join consumed or replaced a slot")
	}
	if !s.find(a.Code).state.Load().World.Layout.Equal(game.LayoutForLandscape(game.LandscapeDryWash)) {
		t.Fatal("join replaced canonical world")
	}
}

func TestRegionMixedCheckpointKeepsSeparateCanonicalRecipes(t *testing.T) {
	cp := regionCheckpointForLandscape(t, game.LandscapeAlpineValley)
	dry := regionCheckpointForLandscape(t, game.LandscapeDryWash).Herds[0]
	dry.World.Code = "FEDCBA"
	cp.Herds = append(cp.Herds, dry)
	data, err := json.Marshal(cp)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if err = os.WriteFile(filepath.Join(dir, "herds.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	s, _ := newTestServer(t, dir, 10)
	for _, saved := range cp.Herds {
		loaded := s.find(saved.World.Code).state.Load()
		before, _ := json.Marshal(saved.World)
		after, _ := json.Marshal(loaded.World)
		if !bytes.Equal(before, after) || !reflect.DeepEqual(loaded.Secrets, saved.Secrets) {
			t.Fatal("mixed recipe load changed saved state or credentials")
		}
	}
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	restarted, _ := newTestServer(t, dir, 10)
	for _, saved := range cp.Herds {
		loaded := restarted.find(saved.World.Code).state.Load()
		before, _ := json.Marshal(saved.World)
		after, _ := json.Marshal(loaded.World)
		if !bytes.Equal(before, after) || !reflect.DeepEqual(loaded.Secrets, saved.Secrets) {
			t.Fatal("mixed recipe resave/restart remapped an old herd")
		}
	}
}
