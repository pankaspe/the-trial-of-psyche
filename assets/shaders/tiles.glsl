// The backdrop breaking into tiles as the world turns over (render.backdrop_roll),
// joined to the sky, ridges and clouds shaders when they load: diamond tiles,
// as the diorama's cells look far off, each going from the sky turning away to
// the one coming in a wave across the screen, the old tiles dropping a little,
// the new rising into place.
uniform vec4 tiles; // x how far the wave has gone (0..1), y 1 the sky coming / -1 the one going / 0 none, z the screen's aspect, w 1 the wave rises from the bottom / -1 it falls from the top
uniform vec4 rect;  // this rectangle in screen uv: x0, y0, width, height (y down)

const float TILES_DOWN = 7.0; // tiles across the screen's height
const float TILE_DROP = 0.035; // how far a tile moves as it goes or comes (screen heights)

float tile_hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

// Moves `uv` (this rectangle's) as the tile it falls in goes or comes, and
// returns how much of this backdrop shows there (the sky going away stays
// whole under the one coming).
float tile_turn(inout vec2 uv) {
    if (tiles.y == 0.0) {
        return 1.0;
    }
    vec2 s = rect.xy + uv * rect.zw;
    vec2 p = vec2(s.x * tiles.z, s.y) * TILES_DOWN;
    vec2 cell = floor(vec2(p.x * 0.5 + p.y, -p.x * 0.5 + p.y)); // a diamond lattice
    float cy = (cell.x + cell.y + 1.0) * 0.5 / TILES_DOWN; // the tile's middle, screen uv
    float from = clamp(tiles.w > 0.0 ? 1.0 - cy : cy, 0.0, 1.0);
    float at = from * 0.7 + tile_hash(cell) * 0.15;
    float k = smoothstep(at, at + 0.15, tiles.x);
    float moved = (tiles.y > 0.0 ? 1.0 - k : k) * TILE_DROP * tiles.w;
    uv.y -= moved / max(rect.w, 1e-4);
    return tiles.y > 0.0 ? k : 1.0;
}

