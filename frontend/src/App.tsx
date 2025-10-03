import { Authenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';
import { Auth } from 'aws-amplify';
import { useEffect, useState } from 'react';
import { GameBoard } from './components/GameBoard';
import { useGameConnection } from './hooks/useGameConnection';
import { getConfig } from './config';
import type { GameSnapshot, Player } from './types';

interface SessionInfo {
  token?: string;
  username?: string;
}

function GameView({ signOut }: { signOut?: () => void }) {
  const [session, setSession] = useState<SessionInfo>({});
  const [loadingSession, setLoadingSession] = useState(false);
  const config = getConfig();

  useEffect(() => {
    let cancelled = false;

    async function loadSession() {
      setLoadingSession(true);
      try {
        const authSession = await Auth.currentSession();
        if (cancelled) {
          return;
        }
        const idToken = authSession.getIdToken();
        const token = idToken.getJwtToken();
        const username = (idToken.payload?.['cognito:username'] as string | undefined) ?? undefined;
        setSession({ token, username });
      } catch (error) {
        console.warn('No active Cognito session', error);
        setSession({});
      } finally {
        if (!cancelled) {
          setLoadingSession(false);
        }
      }
    }

    loadSession();
    return () => {
      cancelled = true;
    };
  }, []);

  const { snapshot, player, connecting, error } = useGameConnection(session.token);
  const debugMode = !session.token && !!config.debugPlayerId;

  return (
    <div className="game-layout">
      <aside className="panel">
        <div className="status-bar">
          <div>
            <h2>Players</h2>
            <p>Tick: {snapshot?.tick ?? '--'}</p>
            {player ? <p>Logged in as {player.id}</p> : null}
            {session.username ? <p>Cognito user: {session.username}</p> : null}
            {debugMode ? <p>Developer player: {config.debugPlayerId}</p> : null}
          </div>
          {signOut ? (
            <button type="button" onClick={signOut} disabled={loadingSession || connecting}>
              Sign out
            </button>
          ) : null}
        </div>

        <PlayersPanel players={snapshot?.players} me={player} />

        {error ? <div className="error-banner">{error}</div> : null}
        {connecting ? <div className="connection-status">Connecting...</div> : null}
      </aside>

      <section className="game-board-wrapper">
        {snapshot ? <GameBoard snapshot={snapshot} /> : <div className="connection-status">Waiting for game data…</div>}
      </section>
    </div>
  );
}

function PlayersPanel({ players, me }: { players?: Record<string, Player>; me: Player | null }) {
  if (!players || Object.keys(players).length === 0) {
    return <p>No players connected yet.</p>;
  }

  const entries = Object.values(players).sort((a, b) => b.resourceCount - a.resourceCount);

  return (
    <div className="players-grid">
      {entries.map((player) => {
        const isMe = me?.id === player.id;
        return (
          <div key={player.id} className="player-card">
            <strong>
              <span className="player-swatch" style={{ backgroundColor: player.color }} />
              {player.id} {isMe ? '(You)' : ''}
            </strong>
            <span>Resources: {player.resourceCount}</span>
            <span>Cores: {player.corePositions.length}</span>
            <span>Joined at tick {player.joinedAtTick}</span>
          </div>
        );
      })}
    </div>
  );
}

function AuthenticatedApp() {
  return (
    <Authenticator>
      {({ signOut }) => (
        <div className="app-shell">
          <header>
            <h1>Game: Spheres of Influence</h1>
            <p>Claim, spread, and harvest resources across a living grid.</p>
          </header>
          <GameView signOut={signOut} />
        </div>
      )}
    </Authenticator>
  );
}

export default function App() {
  const { cognitoAppClientId } = getConfig();

  if (!cognitoAppClientId) {
    return (
      <div className="app-shell">
        <header>
          <h1>Game: Spheres of Influence</h1>
          <p>Developer mode (Cognito disabled). Provide VITE_DEBUG_PLAYER_ID to simulate a player.</p>
        </header>
        <GameView />
      </div>
    );
  }

  return <AuthenticatedApp />;
}
