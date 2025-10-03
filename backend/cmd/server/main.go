package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"

	"github.com/johnlacomba/game-spheres-of-influence/backend/internal/auth"
	"github.com/johnlacomba/game-spheres-of-influence/backend/internal/game"
)

type contextKey string

const (
	playerIDContextKey contextKey = "playerID"
	claimsContextKey   contextKey = "claims"
)

type server struct {
	game       *game.Game
	validator  *auth.Validator
	skipAuth   bool
	upgrader   websocket.Upgrader
	corsOrigin string
}

type wsMessage struct {
	Type     string             `json:"type"`
	Player   *game.Player       `json:"player,omitempty"`
	Snapshot *game.GameSnapshot `json:"snapshot,omitempty"`
}

func main() {
	logger := log.New(os.Stdout, "", log.LstdFlags|log.Lmicroseconds)

	width := getEnvInt("GAME_WIDTH", 64)
	height := getEnvInt("GAME_HEIGHT", 64)
	resourceTiles := getEnvInt("GAME_RESOURCE_TILES", (width*height)/10)
	tickMS := getEnvInt("GAME_TICK_MS", 1000)

	skipAuth := strings.EqualFold(os.Getenv("ALLOW_INSECURE_AUTH"), "true")
	cognitoRegion := os.Getenv("COGNITO_REGION")
	userPoolID := os.Getenv("COGNITO_USER_POOL_ID")
	clientID := os.Getenv("COGNITO_APP_CLIENT_ID")

	var validator *auth.Validator
	var err error
	if !skipAuth {
		validator, err = auth.NewValidator(cognitoRegion, userPoolID, clientID)
		if err != nil {
			logger.Fatalf("failed to initialise validator: %v", err)
		}
		logger.Printf("Cognito auth enabled (region=%s, userPool=%s)", cognitoRegion, userPoolID)
	} else {
		logger.Printf("WARNING: authentication disabled (ALLOW_INSECURE_AUTH=true)")
	}

	g := game.NewGame(width, height, resourceTiles)

	srv := &server{
		game:      g,
		validator: validator,
		skipAuth:  skipAuth,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				return true
			},
		},
		corsOrigin: os.Getenv("CORS_ALLOWED_ORIGIN"),
	}

	mux := http.NewServeMux()
	mux.Handle("/health", srv.cors(srv.handleHealth()))
	mux.Handle("/api/player", srv.cors(srv.withAuth(http.HandlerFunc(srv.handlePlayer))))
	mux.Handle("/api/state", srv.cors(srv.withAuth(http.HandlerFunc(srv.handleState))))
	mux.Handle("/ws", srv.withWebsocketAuth(http.HandlerFunc(srv.handleWebsocket)))

	addr := ":" + getEnv("PORT", "8080")

	go srv.runTicker(time.Duration(tickMS) * time.Millisecond)

	logger.Printf("server listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		logger.Fatalf("server error: %v", err)
	}
}

func (s *server) runTicker(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		s.game.Tick()
	}
}

func (s *server) withAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, err := s.authenticateRequest(r)
		if err != nil {
			writeError(w, http.StatusUnauthorized, err)
			return
		}
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *server) withWebsocketAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, err := s.authenticateWebsocket(r)
		if err != nil {
			writeError(w, http.StatusUnauthorized, err)
			return
		}
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *server) authenticateRequest(r *http.Request) (context.Context, error) {
	if s.skipAuth {
		player := r.Header.Get("X-Debug-Player")
		if player == "" {
			player = "debug-" + strconv.FormatInt(time.Now().UnixNano(), 10)
		}

		ctx := context.WithValue(r.Context(), playerIDContextKey, player)
		return ctx, nil
	}

	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return nil, errors.New("missing Authorization header")
	}

	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return nil, errors.New("invalid Authorization header")
	}

	_, claims, err := s.validator.Validate(parts[1])
	if err != nil {
		return nil, err
	}

	subject, _ := claims["sub"].(string)
	if subject == "" {
		return nil, errors.New("token missing subject")
	}

	ctx := context.WithValue(r.Context(), playerIDContextKey, subject)
	ctx = context.WithValue(ctx, claimsContextKey, claims)
	return ctx, nil
}

func (s *server) authenticateWebsocket(r *http.Request) (context.Context, error) {
	if s.skipAuth {
		player := r.URL.Query().Get("playerId")
		if player == "" {
			player = "debug-" + strconv.FormatInt(time.Now().UnixNano(), 10)
		}

		return context.WithValue(r.Context(), playerIDContextKey, player), nil
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		return nil, errors.New("missing token query parameter")
	}

	_, claims, err := s.validator.Validate(token)
	if err != nil {
		return nil, err
	}

	subject, _ := claims["sub"].(string)
	if subject == "" {
		return nil, errors.New("token missing subject")
	}

	ctx := context.WithValue(r.Context(), playerIDContextKey, subject)
	ctx = context.WithValue(ctx, claimsContextKey, claims)
	return ctx, nil
}

func (s *server) handleHealth() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
}

func (s *server) handlePlayer(w http.ResponseWriter, r *http.Request) {
	playerID := r.Context().Value(playerIDContextKey).(string)

	player, err := s.game.AddPlayer(playerID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	writeJSON(w, http.StatusOK, player)
}

func (s *server) handleState(w http.ResponseWriter, r *http.Request) {
	snapshot := s.game.CurrentSnapshot()
	writeJSON(w, http.StatusOK, snapshot)
}

func (s *server) handleWebsocket(w http.ResponseWriter, r *http.Request) {
	playerID := r.Context().Value(playerIDContextKey).(string)

	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("failed to upgrade websocket: %v", err)
		return
	}
	defer conn.Close()

	player, err := s.game.AddPlayer(playerID)
	if err != nil {
		_ = conn.WriteJSON(map[string]string{"error": err.Error()})
		return
	}

	welcome := wsMessage{
		Type:     "welcome",
		Player:   player,
		Snapshot: ptrSnapshot(s.game.CurrentSnapshot()),
	}

	if err := conn.WriteJSON(welcome); err != nil {
		log.Printf("failed to send welcome: %v", err)
		return
	}

	updates, unsubscribe := s.game.Subscribe(2)
	defer unsubscribe()

	done := make(chan struct{})

	go func() {
		defer close(done)
		for {
			if _, _, err := conn.NextReader(); err != nil {
				return
			}
		}
	}()

	for {
		select {
		case snapshot, ok := <-updates:
			if !ok {
				return
			}
			message := wsMessage{Type: "snapshot", Snapshot: &snapshot}
			if err := conn.WriteJSON(message); err != nil {
				log.Printf("failed to write snapshot: %v", err)
				return
			}
		case <-done:
			return
		}
	}
}

func (s *server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := s.corsOrigin
		if origin == "" {
			origin = "*"
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Debug-Player")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Credentials", "true")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed to write json: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]string{"error": err.Error()})
}

func ptrSnapshot(snapshot game.GameSnapshot) *game.GameSnapshot {
	return &snapshot
}

func getEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func getEnvInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	i, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return i
}
