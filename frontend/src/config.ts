const DEFAULT_BACKEND = 'http://localhost:8080';

function normalizeBackendUrl(url?: string | null): string {
  if (!url) {
    return DEFAULT_BACKEND;
  }

  const trimmed = url.trim();
  if (!trimmed) {
    return DEFAULT_BACKEND;
  }

  try {
    const parsed = new URL(trimmed);
    let path = parsed.pathname;
    path = path.replace(/\/+$/, '');
    if (path.endsWith('/api')) {
      path = path.slice(0, -4);
    }
    if (!path) {
      path = '/';
    }
    parsed.pathname = path;
    parsed.search = '';
    parsed.hash = '';

    let result = parsed.toString();
    if (result.endsWith('/')) {
      result = result.slice(0, -1);
    }
    return result;
  } catch (error) {
    let normalized = trimmed.replace(/\/+$/, '');
    if (normalized.endsWith('/api')) {
      normalized = normalized.slice(0, -4);
    }
    return normalized || DEFAULT_BACKEND;
  }
}

export interface AppConfig {
  backendBaseUrl: string;
  cognitoRegion?: string;
  cognitoUserPoolId?: string;
  cognitoAppClientId?: string;
  debugPlayerId?: string;
}

let cachedConfig: AppConfig | null = null;

export function getConfig(): AppConfig {
  if (cachedConfig) {
    return cachedConfig;
  }

  const {
    VITE_BACKEND_URL,
    VITE_COGNITO_REGION,
    VITE_COGNITO_USER_POOL_ID,
    VITE_COGNITO_APP_CLIENT_ID,
    VITE_DEBUG_PLAYER_ID
  } = import.meta.env;

  cachedConfig = {
    backendBaseUrl: normalizeBackendUrl(VITE_BACKEND_URL as string | null),
    cognitoRegion: VITE_COGNITO_REGION as string | undefined,
    cognitoUserPoolId: VITE_COGNITO_USER_POOL_ID as string | undefined,
    cognitoAppClientId: VITE_COGNITO_APP_CLIENT_ID as string | undefined,
    debugPlayerId: VITE_DEBUG_PLAYER_ID as string | undefined
  };

  return cachedConfig;
}

export function buildWebSocketUrl(token?: string, debugPlayerId?: string): string {
  const { backendBaseUrl } = getConfig();
  const url = new URL(backendBaseUrl);
  url.pathname = '/ws';
  url.search = '';
  url.hash = '';
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';

  if (token) {
    url.searchParams.set('token', token);
  } else if (debugPlayerId) {
    url.searchParams.set('playerId', debugPlayerId);
  }

  return url.toString();
}
