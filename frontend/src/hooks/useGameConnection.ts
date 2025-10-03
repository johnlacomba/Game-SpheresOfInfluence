import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { buildWebSocketUrl, getConfig } from '../config';
import type { GameSnapshot, Player } from '../types';

interface GameConnectionState {
  snapshot: GameSnapshot | null;
  player: Player | null;
  connecting: boolean;
  error?: string;
}

const initialState: GameConnectionState = {
  snapshot: null,
  player: null,
  connecting: false,
};

type IncomingMessage =
  | {
      type: 'welcome';
      player: Player;
      snapshot: GameSnapshot;
    }
  | {
      type: 'snapshot';
      snapshot: GameSnapshot;
    };

function parseMessage(payload: string): IncomingMessage | null {
  try {
    const data = JSON.parse(payload);
    if ((data as IncomingMessage).type === 'welcome') {
      return data as IncomingMessage;
    }
    if ((data as IncomingMessage).type === 'snapshot') {
      return data as IncomingMessage;
    }
  } catch (error) {
    console.error('Failed to parse message', error);
  }
  return null;
}

export function useGameConnection(token?: string) {
  const { backendBaseUrl, debugPlayerId } = useConfigMemo();
  const [state, setState] = useState<GameConnectionState>(initialState);
  const wsRef = useRef<WebSocket | null>(null);
  const tokenRef = useRef<string | undefined>(token);
  const debugPlayerRef = useRef<string | undefined>(debugPlayerId);

  useEffect(() => {
    tokenRef.current = token;
  }, [token]);

  useEffect(() => {
    debugPlayerRef.current = debugPlayerId;
  }, [debugPlayerId]);

  const registerPlayer = useCallback(async () => {
    const currentToken = tokenRef.current;
    const debugPlayer = debugPlayerRef.current;

    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (currentToken) {
      headers.Authorization = `Bearer ${currentToken}`;
    } else if (debugPlayer) {
      headers['X-Debug-Player'] = debugPlayer;
    }

  const playerUrl = new URL('/api/player', backendBaseUrl);
  const response = await fetch(playerUrl.toString(), {
      method: 'GET',
      headers,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(text || `Registration failed with status ${response.status}`);
    }

    const player = (await response.json()) as Player;
    return player;
  }, [backendBaseUrl]);

  useEffect(() => {
    let isMounted = true;
    let socket: WebSocket | null = null;

    async function connect() {
      if (!tokenRef.current && !debugPlayerRef.current) {
  setState((prev: GameConnectionState) => ({ ...prev, error: 'No authentication token available', connecting: false }));
        return;
      }

  setState({ snapshot: null, player: null, connecting: true, error: undefined });

      try {
        const player = await registerPlayer();
        if (!isMounted) {
          return;
        }

  setState((prev: GameConnectionState) => ({ ...prev, player }));

        const wsUrl = buildWebSocketUrl(tokenRef.current, debugPlayerRef.current);
        socket = new WebSocket(wsUrl);
        wsRef.current = socket;

        socket.onopen = () => {
          if (!isMounted) {
            return;
          }
          setState((prev: GameConnectionState) => ({ ...prev, connecting: false, error: undefined }));
        };

        socket.onmessage = (event) => {
          const message = parseMessage(event.data);
          if (!message) {
            return;
          }
          if (!isMounted) {
            return;
          }

          if (message.type === 'welcome') {
            setState({ snapshot: message.snapshot, player: message.player, connecting: false });
            return;
          }

          if (message.type === 'snapshot') {
            setState((prev: GameConnectionState) => ({ ...prev, snapshot: message.snapshot }));
          }
        };

        socket.onerror = (event) => {
          console.error('WebSocket error', event);
          if (!isMounted) {
            return;
          }
          setState((prev: GameConnectionState) => ({ ...prev, error: 'Connection error', connecting: false }));
        };

        socket.onclose = () => {
          if (!isMounted) {
            return;
          }
          setState((prev: GameConnectionState) => ({ ...prev, connecting: false }));
        };
      } catch (error) {
        console.error('Failed to connect', error);
        if (!isMounted) {
          return;
        }
  setState((prev: GameConnectionState) => ({ ...prev, error: (error as Error).message, connecting: false }));
      }
    }

    connect();

    return () => {
      isMounted = false;
      if (socket) {
        socket.close();
      }
    };
  }, [registerPlayer, token]);

  const disconnect = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
  }, []);

  return {
    ...state,
    disconnect,
  };
}

function useConfigMemo() {
  return useMemo(() => getConfig(), []);
}
