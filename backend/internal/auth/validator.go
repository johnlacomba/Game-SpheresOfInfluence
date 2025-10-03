package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var ErrInvalidToken = errors.New("invalid token")

// Validator validates Cognito JWTs using the JWKS endpoint.
type Validator struct {
	issuer       string
	audience     string
	jwksURL      string
	client       *http.Client
	mu           sync.RWMutex
	keys         map[string]*rsa.PublicKey
	lastRefresh  time.Time
	refreshEvery time.Duration
}

type jwksResponse struct {
	Keys []jwk `json:"keys"`
}

type jwk struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Alg string `json:"alg"`
	Use string `json:"use"`
	N   string `json:"n"`
	E   string `json:"e"`
}

func NewValidator(region, userPoolID, audience string) (*Validator, error) {
	if region == "" || userPoolID == "" {
		return nil, errors.New("region and userPoolID are required")
	}

	issuer := fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s", region, userPoolID)
	jwksURL := fmt.Sprintf("%s/.well-known/jwks.json", issuer)

	v := &Validator{
		issuer:       issuer,
		audience:     audience,
		jwksURL:      jwksURL,
		client:       &http.Client{Timeout: 10 * time.Second},
		keys:         make(map[string]*rsa.PublicKey),
		refreshEvery: time.Hour,
	}

	if err := v.refreshKeys(context.Background()); err != nil {
		return nil, err
	}

	return v, nil
}

func (v *Validator) Validate(tokenString string) (*jwt.Token, jwt.MapClaims, error) {
	if tokenString == "" {
		return nil, nil, ErrInvalidToken
	}

	keyFunc := func(token *jwt.Token) (interface{}, error) {
		kidValue, ok := token.Header["kid"].(string)
		if !ok {
			return nil, ErrInvalidToken
		}

		key, err := v.keyForKid(kidValue)
		if err != nil {
			return nil, err
		}

		return key, nil
	}

	opts := []jwt.ParserOption{jwt.WithIssuer(v.issuer)}
	if v.audience != "" {
		opts = append(opts, jwt.WithAudience(v.audience))
	}

	token, err := jwt.Parse(tokenString, keyFunc, opts...)
	if err != nil {
		return nil, nil, err
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, nil, ErrInvalidToken
	}

	return token, claims, nil
}

func (v *Validator) keyForKid(kid string) (*rsa.PublicKey, error) {
	v.mu.RLock()
	key, ok := v.keys[kid]
	last := v.lastRefresh
	v.mu.RUnlock()

	if ok {
		return key, nil
	}

	// attempt refresh if keys might be stale
	if time.Since(last) > v.refreshEvery {
		if err := v.refreshKeys(context.Background()); err != nil {
			return nil, err
		}
	}

	v.mu.RLock()
	defer v.mu.RUnlock()

	key, ok = v.keys[kid]
	if !ok {
		return nil, fmt.Errorf("unknown key id: %s", kid)
	}

	return key, nil
}

func (v *Validator) refreshKeys(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.jwksURL, nil)
	if err != nil {
		return err
	}

	resp, err := v.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to fetch jwks: %s", resp.Status)
	}

	var body jwksResponse
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return err
	}

	keys := make(map[string]*rsa.PublicKey)
	for _, key := range body.Keys {
		if key.Kty != "RSA" {
			continue
		}
		pub, err := jwkToPublicKey(key)
		if err != nil {
			return err
		}
		keys[key.Kid] = pub
	}

	if len(keys) == 0 {
		return errors.New("no valid keys found in JWKS")
	}

	v.mu.Lock()
	defer v.mu.Unlock()

	v.keys = keys
	v.lastRefresh = time.Now()

	return nil
}

func jwkToPublicKey(key jwk) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
	if err != nil {
		return nil, fmt.Errorf("failed to decode modulus: %w", err)
	}

	eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
	if err != nil {
		return nil, fmt.Errorf("failed to decode exponent: %w", err)
	}

	exp := 0
	for _, b := range eBytes {
		exp = exp<<8 | int(b)
	}
	if exp == 0 {
		return nil, errors.New("invalid exponent in jwk")
	}

	return &rsa.PublicKey{
		N: new(big.Int).SetBytes(nBytes),
		E: exp,
	}, nil
}
