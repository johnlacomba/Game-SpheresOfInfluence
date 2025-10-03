import { useMemo } from 'react';
import type { CSSProperties, ReactNode } from 'react';
import type { GameSnapshot, Player, Tile } from '../types';
import './GameBoard.css';

interface GameBoardProps {
  snapshot: GameSnapshot;
}

type TileMap = Map<string, Tile>;

function buildTileMap(tiles: Tile[]): TileMap {
  const map = new Map<string, Tile>();
  for (const tile of tiles) {
    map.set(`${tile.position.x}:${tile.position.y}`, tile);
  }
  return map;
}

function getTileOwnerColor(tile: Tile | undefined, players: Record<string, Player>): string {
  if (tile?.ownerId && players[tile.ownerId]) {
    return players[tile.ownerId].color;
  }
  if (tile?.resourceBase) {
    return '#1f2937';
  }
  return '#0f172a';
}

export function GameBoard({ snapshot }: GameBoardProps) {
  const tileMap = useMemo(() => buildTileMap(snapshot.tiles), [snapshot.tiles]);
  const { width, height, players } = snapshot;

  const cells = useMemo(() => {
  const rendered: ReactNode[] = [];
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const key = `${x}:${y}`;
        const tile = tileMap.get(key);
        const ownerColor = getTileOwnerColor(tile, players);
        const classes = ['tile-cell'];
        if (tile?.coreBorder) {
          classes.push('tile-core');
        }
        if (tile?.resourceBase) {
          classes.push('tile-resource-base');
        }

        rendered.push(
          <div
            key={key}
            className={classes.join(' ')}
            style={{ backgroundColor: ownerColor }}
            data-coords={`${x},${y}`}
          >
            {tile?.hasResource ? <span className="resource-pill" /> : null}
          </div>
        );
      }
    }
    return rendered;
  }, [height, width, tileMap, players]);

  const gridStyle: CSSProperties = useMemo(
    () => ({
      gridTemplateColumns: `repeat(${width}, minmax(0, 1fr))`,
      gridTemplateRows: `repeat(${height}, minmax(0, 1fr))`,
    }),
    [width, height]
  );

  return (
    <div className="game-board" style={gridStyle} role="grid" aria-label="game board">
      {cells}
    </div>
  );
}
