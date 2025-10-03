package game

import (
	"math/rand"
	"testing"
)

func TestCoreSpreadClaimsAdjacentTiles(t *testing.T) {
	rng := rand.New(rand.NewSource(42))
	g := NewGameWithRand(8, 8, 0, rng)

	corePos := Position{X: 3, Y: 3}
	player, err := g.AddPlayerAt("player-1", corePos, "#123456")
	if err != nil {
		t.Fatalf("failed to add player: %v", err)
	}

	g.Tick()

	neighbors := g.neighbors(corePos)
	for _, nb := range neighbors {
		tile := g.tiles[posKey(nb)]
		if tile.OwnerID != player.ID {
			t.Fatalf("expected neighbor %v to be owned by %s, got %s", nb, player.ID, tile.OwnerID)
		}
	}
}

func TestResourceMovementTowardsCore(t *testing.T) {
	rng := rand.New(rand.NewSource(99))
	g := NewGameWithRand(5, 5, 0, rng)

	resourcePos := Position{X: 2, Y: 2}
	key := posKey(resourcePos)
	tile := g.tiles[key]
	tile.Type = TileResource
	tile.ResourceBase = true
	g.resourceTiles[key] = true

	player, err := g.AddPlayerAt("player-1", Position{X: 0, Y: 0}, "#abcdef")
	if err != nil {
		t.Fatalf("failed to add player: %v", err)
	}

	// Run ticks until the resource is consumed
	for i := 0; i < 12; i++ {
		g.Tick()
	}

	if playerState, ok := g.players[player.ID]; ok {
		if playerState.ResourceCount == 0 {
			t.Fatalf("expected player to collect at least one resource")
		}
	} else {
		t.Fatalf("player disappeared from game state")
	}
}
