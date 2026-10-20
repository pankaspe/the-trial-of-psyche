// The seam between two skies as the world turns over (render.backdrop_roll),
// joined to the sky, ridges and clouds shaders when they load: the sky going
// away rolls off, the one coming rolls in, and where they meet the backdrop
// breaks into small diamond tiles (the diorama's cells far off), each going
// over on its own a little before or after its neighbours, the old dropping,
// the new rising into place.
uniform vec4 tiles; // x the seam (screen uv, y down), y 1 the sky coming / -1 the one going (fading) / -2 the one going, kept whole / 0 none, z the screen's aspect, w the seam's half width (screen uv; < 0: the sky coming is above it)
uniform vec4 rect;  // this rectangle in screen uv: x0, y0, width, height (y down)

const float TILES_DOWN = 15.0; // tiles across the screen's height
const float TILE_DROP = 0.02; // how far a tile moves as it goes or comes (screen heights)

float tile_hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

// Moves `uv` (this rectangle's) as the tile it falls in goes or comes, and
// returns how much of this backdrop shows there.
float tile_turn(inout vec2 uv) {
    if (tiles.y == 0.0) {
        return 1.0;
    }
    vec2 s = rect.xy + uv * rect.zw;
    vec2 p = vec2(s.x * tiles.z, s.y) * TILES_DOWN;
    vec2 cell = floor(vec2(p.x * 0.5 + p.y, -p.x * 0.5 + p.y)); // a diamond lattice
    float cy = (cell.x + cell.y + 1.0) * 0.5 / TILES_DOWN; // the tile's middle, screen uv
    float d = (cy - tiles.x) / tiles.w; // -1 .. 1 across the seam, toward the sky coming
    if (tiles.y == -1.0) {
        d += 0.15; // the old clouds and ranges go with their tiles, a hair early
    }
    float k = smoothstep(0.42, 0.58, 0.5 + 0.5 * d + 0.5 * (tile_hash(cell) - 0.5));
    float moved = (tiles.y > 0.0 ? 1.0 - k : k) * TILE_DROP * sign(tiles.w);
    uv.y -= moved / max(rect.w, 1e-4);
    return tiles.y > 0.0 ? k : (tiles.y == -1.0 ? 1.0 - k : 1.0);
}

