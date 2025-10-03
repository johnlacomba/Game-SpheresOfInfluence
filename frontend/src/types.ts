export type TileType = 'normal' | 'core' | 'resource';

export interface Position {
  x: number;
  y: number;
}

export interface Tile {
  position: Position;
  ownerId?: string;
  type: TileType;
  hasResource: boolean;
  coreBorder: boolean;
  resourceBase: boolean;
}

export interface Player {
  id: string;
  color: string;
  corePositions: Position[];
  resourceCount: number;
  joinedAtTick: number;
}

export interface Resource {
  id: string;
  ownerId?: string;
  position: Position;
}

export interface GameSnapshot {
  tick: number;
  width: number;
  height: number;
  players: Record<string, Player>;
  tiles: Tile[];
  resources: Resource[];
}
