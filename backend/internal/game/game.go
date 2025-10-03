package game

import (
	"errors"
	"fmt"
	"math/rand"
	"sync"
	"time"
)

type TileType string

type Position struct {
	X int `json:"x"`
	Y int `json:"y"`
}

type Tile struct {
	Position     Position `json:"position"`
	OwnerID      string   `json:"ownerId,omitempty"`
	Type         TileType `json:"type"`
	HasResource  bool     `json:"hasResource"`
	CoreBorder   bool     `json:"coreBorder"`
	ResourceBase bool     `json:"resourceBase"`
}

type Player struct {
	ID            string     `json:"id"`
	Color         string     `json:"color"`
	CorePositions []Position `json:"corePositions"`
	ResourceCount int        `json:"resourceCount"`
	JoinedAtTick  int64      `json:"joinedAtTick"`
}

type Resource struct {
	ID       string   `json:"id"`
	OwnerID  string   `json:"ownerId,omitempty"`
	Position Position `json:"position"`
}

type GameSnapshot struct {
	Tick      int64             `json:"tick"`
	Width     int               `json:"width"`
	Height    int               `json:"height"`
	Players   map[string]Player `json:"players"`
	Tiles     []Tile            `json:"tiles"`
	Resources []Resource        `json:"resources"`
}

type Game struct {
	mu             sync.RWMutex
	width          int
	height         int
	players        map[string]*Player
	tiles          map[string]*Tile
	resourceTiles  map[string]bool
	resources      map[string]*Resource
	resourceByPos  map[string]string
	pendingSpreads map[string]spreadBucket
	tick           int64
	rng            *rand.Rand
	subscribers    map[int]chan GameSnapshot
	nextSubscriber int
	colorPool      []string
	nextResourceID int
}

type spreadBucket map[string]map[string]Position

const (
	TileNormal   TileType = "normal"
	TileCore     TileType = "core"
	TileResource TileType = "resource"
)

var (
	errNoAvailableCore = errors.New("no available tiles for core placement")
)

func NewGame(width, height, resourceBases int) *Game {
	return NewGameWithRand(width, height, resourceBases, rand.New(rand.NewSource(time.Now().UnixNano())))
}

func NewGameWithRand(width, height, resourceBases int, rng *rand.Rand) *Game {
	tiles := make(map[string]*Tile, width*height)
	for x := 0; x < width; x++ {
		for y := 0; y < height; y++ {
			pos := Position{X: x, Y: y}
			tiles[posKey(pos)] = &Tile{
				Position: pos,
				Type:     TileNormal,
			}
		}
	}

	g := &Game{
		width:          width,
		height:         height,
		players:        make(map[string]*Player),
		tiles:          tiles,
		resourceTiles:  make(map[string]bool),
		resources:      make(map[string]*Resource),
		resourceByPos:  make(map[string]string),
		pendingSpreads: make(map[string]spreadBucket),
		rng:            rng,
		subscribers:    make(map[int]chan GameSnapshot),
		colorPool: []string{
			"#ff4f4f", "#4f83ff", "#4fff73", "#ff4fbd", "#ffb84f",
			"#9b59ff", "#4ffff4", "#ffd24f", "#2ecc71", "#e74c3c",
		},
	}

	g.seedResourceTiles(resourceBases)

	return g
}

func posKey(pos Position) string {
	return fmt.Sprintf("%d:%d", pos.X, pos.Y)
}

func (g *Game) seedResourceTiles(count int) {
	if count <= 0 {
		return
	}
	available := make([]Position, 0, len(g.tiles))
	for _, tile := range g.tiles {
		available = append(available, tile.Position)
	}

	for i := 0; i < count && len(available) > 0; i++ {
		idx := g.rng.Intn(len(available))
		choice := available[idx]
		key := posKey(choice)
		tile := g.tiles[key]
		tile.Type = TileResource
		tile.ResourceBase = true

		available[idx] = available[len(available)-1]
		available = available[:len(available)-1]
		g.resourceTiles[key] = true
	}
}

func (g *Game) AddPlayer(id string) (*Player, error) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if p, ok := g.players[id]; ok {
		return clonePlayer(p), nil
	}

	color := g.nextColor()

	pos, err := g.randomAvailableCorePositionLocked()
	if err != nil {
		return nil, err
	}

	player := &Player{
		ID:            id,
		Color:         color,
		CorePositions: []Position{pos},
		JoinedAtTick:  g.tick,
	}
	g.players[id] = player

	tile := g.tiles[posKey(pos)]
	tile.Type = TileCore
	tile.OwnerID = id
	tile.CoreBorder = true

	return clonePlayer(player), nil
}

func (g *Game) AddPlayerAt(id string, pos Position, color string) (*Player, error) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if _, exists := g.players[id]; exists {
		return nil, fmt.Errorf("player %s already exists", id)
	}

	if !g.isInBounds(pos) {
		return nil, fmt.Errorf("position %+v out of bounds", pos)
	}

	tkey := posKey(pos)
	tile := g.tiles[tkey]
	if tile.Type == TileCore && tile.OwnerID != "" {
		return nil, fmt.Errorf("tile %s already contains a core", tkey)
	}

	if color == "" {
		color = g.nextColor()
	}

	player := &Player{
		ID:            id,
		Color:         color,
		CorePositions: []Position{pos},
		JoinedAtTick:  g.tick,
	}
	g.players[id] = player

	tile.Type = TileCore
	tile.OwnerID = id
	tile.CoreBorder = true

	return clonePlayer(player), nil
}

func (g *Game) nextColor() string {
	used := make(map[string]bool)
	for _, p := range g.players {
		used[p.Color] = true
	}

	available := make([]string, 0, len(g.colorPool))
	for _, c := range g.colorPool {
		if !used[c] {
			available = append(available, c)
		}
	}

	if len(available) == 0 {
		return fmt.Sprintf("#%06x", g.rng.Intn(0xffffff))
	}

	return available[g.rng.Intn(len(available))]
}

func (g *Game) randomAvailableCorePositionLocked() (Position, error) {
	candidates := make([]Position, 0)
	for _, tile := range g.tiles {
		if tile.Type == TileCore || tile.CoreBorder || tile.Type == TileResource {
			continue
		}
		candidates = append(candidates, tile.Position)
	}
	if len(candidates) == 0 {
		return Position{}, errNoAvailableCore
	}
	pos := candidates[g.rng.Intn(len(candidates))]
	return pos, nil
}

func (g *Game) isInBounds(pos Position) bool {
	return pos.X >= 0 && pos.Y >= 0 && pos.X < g.width && pos.Y < g.height
}

func (g *Game) neighbors(pos Position) []Position {
	result := make([]Position, 0, 8)
	for dx := -1; dx <= 1; dx++ {
		for dy := -1; dy <= 1; dy++ {
			if dx == 0 && dy == 0 {
				continue
			}
			next := Position{X: pos.X + dx, Y: pos.Y + dy}
			if g.isInBounds(next) {
				result = append(result, next)
			}
		}
	}
	return result
}

func (g *Game) Tick() GameSnapshot {
	g.mu.Lock()
	g.tick++

	incoming := make(map[string]spreadBucket, len(g.pendingSpreads))
	for key, bucket := range g.pendingSpreads {
		incoming[key] = cloneSpreadBucket(bucket)
	}

	g.applyCoreSpreadsLocked(incoming)
	nextSpreads := g.resolveSpreadsLocked(incoming)
	g.pendingSpreads = nextSpreads

	distanceMaps := g.buildDistanceMapsLocked()
	g.handleResourcesLocked(distanceMaps)

	snapshot := g.snapshotLocked()
	subscribers := g.cloneSubscribersLocked()
	g.mu.Unlock()

	for _, ch := range subscribers {
		select {
		case ch <- snapshot:
		default:
		}
	}

	return snapshot
}

func (g *Game) applyCoreSpreadsLocked(incoming map[string]spreadBucket) {
	for _, player := range g.players {
		for _, core := range player.CorePositions {
			for _, nb := range g.neighbors(core) {
				g.addSpread(incoming, posKey(nb), player.ID, core)
			}
		}
	}
}

func (g *Game) resolveSpreadsLocked(incoming map[string]spreadBucket) map[string]spreadBucket {
	nextSpreads := make(map[string]spreadBucket)

	for key, bucket := range incoming {
		tile := g.tiles[key]
		if tile == nil {
			continue
		}

		var topPlayer string
		var topCount int
		var contested bool

		for playerID, origins := range bucket {
			count := len(origins)
			if count == 0 {
				continue
			}
			if count > topCount {
				topCount = count
				topPlayer = playerID
				contested = false
			} else if count == topCount && playerID != topPlayer {
				contested = true
			}
		}

		ownerBefore := tile.OwnerID
		if topCount > 0 && !contested {
			tile.OwnerID = topPlayer
		}

		if tile.Type == TileCore {
			tile.OwnerID = ownerBefore
		}

		if tile.OwnerID == "" {
			continue
		}

		ownerOrigins := bucket[tile.OwnerID]
		if len(ownerOrigins) == 0 {
			continue
		}

		for _, origin := range ownerOrigins {
			for _, nb := range g.neighbors(tile.Position) {
				if nb.X == origin.X && nb.Y == origin.Y {
					continue
				}
				g.addSpread(nextSpreads, posKey(nb), tile.OwnerID, tile.Position)
			}
		}
	}

	return nextSpreads
}

func cloneSpreadBucket(bucket spreadBucket) spreadBucket {
	if bucket == nil {
		return nil
	}

	clone := make(spreadBucket, len(bucket))
	for playerID, origins := range bucket {
		copyOrigins := make(map[string]Position, len(origins))
		for key, pos := range origins {
			copyOrigins[key] = pos
		}
		clone[playerID] = copyOrigins
	}
	return clone
}

func (g *Game) addSpread(storage map[string]spreadBucket, key string, playerID string, from Position) {
	bucket, ok := storage[key]
	if !ok {
		bucket = make(spreadBucket)
		storage[key] = bucket
	}

	origins, ok := bucket[playerID]
	if !ok {
		origins = make(map[string]Position)
		bucket[playerID] = origins
	}

	origins[posKey(from)] = from
}

func (g *Game) handleResourcesLocked(distanceMaps map[string]map[string]int) {
	// Spawn resources
	for key := range g.resourceTiles {
		if _, has := g.resourceByPos[key]; !has {
			g.nextResourceID++
			resID := fmt.Sprintf("res-%d", g.nextResourceID)
			resource := &Resource{
				ID:       resID,
				Position: g.tiles[key].Position,
			}
			g.resources[resID] = resource
			g.resourceByPos[key] = resID
		}
	}

	// Move resources
	for id, res := range g.resources {
		key := posKey(res.Position)
		tile := g.tiles[key]
		if tile == nil {
			continue
		}

		tileOwner := tile.OwnerID
		if tileOwner == "" {
			continue
		}

		distances := distanceMaps[tileOwner]
		if len(distances) == 0 {
			continue
		}

		res.OwnerID = tileOwner

		dist := distances[key]
		if dist <= 0 {
			// Resource has reached a core
			player := g.players[tileOwner]
			if player != nil {
				player.ResourceCount++
			}
			delete(g.resources, id)
			delete(g.resourceByPos, key)
			continue
		}

		nextPos, ok := g.nextStepTowards(res.Position, distances)
		if !ok {
			continue
		}

		nextKey := posKey(nextPos)
		if _, blocked := g.resourceByPos[nextKey]; blocked {
			continue
		}

		delete(g.resourceByPos, key)
		res.Position = nextPos
		g.resourceByPos[nextKey] = id
	}

	g.refreshTileResourceFlagsLocked()
}

func (g *Game) refreshTileResourceFlagsLocked() {
	for key, tile := range g.tiles {
		_, has := g.resourceByPos[key]
		tile.HasResource = has
	}
}

func (g *Game) nextStepTowards(current Position, distances map[string]int) (Position, bool) {
	currentDist, ok := distances[posKey(current)]
	if !ok {
		return Position{}, false
	}

	best := current
	bestDist := currentDist

	for dx := -1; dx <= 1; dx++ {
		for dy := -1; dy <= 1; dy++ {
			if dx == 0 && dy == 0 {
				continue
			}
			next := Position{X: current.X + dx, Y: current.Y + dy}
			if !g.isInBounds(next) {
				continue
			}
			nextKey := posKey(next)
			nextDist, ok := distances[nextKey]
			if !ok {
				continue
			}
			if nextDist < bestDist {
				bestDist = nextDist
				best = next
			}
		}
	}

	if bestDist >= currentDist {
		return Position{}, false
	}

	return best, true
}

func (g *Game) buildDistanceMapsLocked() map[string]map[string]int {
	result := make(map[string]map[string]int, len(g.players))
	queue := make([]Position, 0)

	for id, player := range g.players {
		distances := make(map[string]int, g.width*g.height)

		queue = queue[:0]
		for _, core := range player.CorePositions {
			key := posKey(core)
			distances[key] = 0
			queue = append(queue, core)
		}

		for len(queue) > 0 {
			current := queue[0]
			queue = queue[1:]
			currentDist := distances[posKey(current)]

			for _, nb := range g.neighbors(current) {
				key := posKey(nb)
				if _, seen := distances[key]; seen {
					continue
				}
				distances[key] = currentDist + 1
				queue = append(queue, nb)
			}
		}

		result[id] = distances
	}

	return result
}

func (g *Game) snapshotLocked() GameSnapshot {
	tiles := make([]Tile, 0, len(g.tiles))
	for _, tile := range g.tiles {
		tiles = append(tiles, *tile)
	}

	players := make(map[string]Player, len(g.players))
	for id, player := range g.players {
		players[id] = *player
	}

	resources := make([]Resource, 0, len(g.resources))
	for _, res := range g.resources {
		resources = append(resources, *res)
	}

	return GameSnapshot{
		Tick:      g.tick,
		Width:     g.width,
		Height:    g.height,
		Players:   players,
		Tiles:     tiles,
		Resources: resources,
	}
}

func (g *Game) cloneSubscribersLocked() []chan GameSnapshot {
	chs := make([]chan GameSnapshot, 0, len(g.subscribers))
	for _, ch := range g.subscribers {
		chs = append(chs, ch)
	}
	return chs
}

func (g *Game) Subscribe(buffer int) (<-chan GameSnapshot, func()) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if buffer <= 0 {
		buffer = 1
	}

	id := g.nextSubscriber
	g.nextSubscriber++

	ch := make(chan GameSnapshot, buffer)
	g.subscribers[id] = ch

	return ch, func() {
		g.mu.Lock()
		defer g.mu.Unlock()
		if ch, ok := g.subscribers[id]; ok {
			close(ch)
			delete(g.subscribers, id)
		}
	}
}

func (g *Game) CurrentSnapshot() GameSnapshot {
	g.mu.RLock()
	defer g.mu.RUnlock()

	return g.snapshotLocked()
}

func (g *Game) Player(id string) (*Player, bool) {
	g.mu.RLock()
	defer g.mu.RUnlock()

	player, ok := g.players[id]
	if !ok {
		return nil, false
	}
	copy := *player
	return &copy, true
}

func clonePlayer(p *Player) *Player {
	copy := *p
	copy.CorePositions = append([]Position(nil), p.CorePositions...)
	return &copy
}
