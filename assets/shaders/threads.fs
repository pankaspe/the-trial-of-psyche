#version 330
// The dark between two levels, where the last one broke up, cut low-poly like
// the world: a mosaic of flat triangles of ink, threads of light along their
// edges, a far galaxy of small diamonds turning in it. `amount` is how far it
// reaches from the middle (under the ending card; the whole screen at 1);
// `open` parts it from `center` (where Psyche comes down in the next level),
// the facets on the edge of the opening a crack of gold.

in vec2 fragTexCoord;

uniform float time;
uniform float aspect;
uniform float amount;
uniform float open;
uniform vec2 center; // screen uv the dark opens from

out vec4 finalColor;

const float FACETS = 15.0; // rows of triangles over the screen's height

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += noise(p) * a;
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

mat2 turn(float a) {
    return mat2(cos(a), -sin(a), sin(a), cos(a));
}

// The triangle of the mosaic under screen point s (in facet units): its
// centroid (an id for the whole facet) and the distance to its nearest edge.
void facet(vec2 s, out vec2 mid, out float edge) {
    float shift = mod(floor(s.y), 2.0) > 0.5 ? 0.5 : 0.0;
    float row = floor(s.y);
    float x = s.x + shift;
    float col = floor(x);
    vec2 f = vec2(fract(x), fract(s.y));
    float d1 = abs(2.0 * f.x - f.y) / 2.236;
    float d2 = abs(2.0 * (1.0 - f.x) - f.y) / 2.236;
    if (f.y <= 2.0 * f.x && f.y <= 2.0 * (1.0 - f.x)) {
        mid = vec2(col + 0.5, row + 0.333);
        edge = min(f.y, min(d1, d2));
    } else {
        mid = vec2(col + (f.x < 0.5 ? 0.0 : 1.0), row + 0.667);
        edge = min(1.0 - f.y, min(d1, d2));
    }
    mid.x -= shift;
}

void main() {
    vec2 uv = fragTexCoord;
    vec2 s = uv * vec2(aspect, 1.0) * FACETS;
    vec2 mid;
    float edge;
    facet(s, mid, edge);
    vec2 m = mid / FACETS; // the facet's centroid, in screen units (x times aspect)
    float jitter = hash(mid * 0.37 + 3.1);

    // each facet is dark or not as a whole: the dark reaches out from the
    // middle, then opens from where she comes down
    float r = length((m - vec2(0.5 * aspect, 0.5)) * vec2(0.6, 1.0)) + (jitter - 0.5) * 0.08;
    float dark = amount > 0.999 ? 1.0 : step(r, amount * 1.4 - 0.05);
    float rh = length((m - center * vec2(aspect, 1.0)) * vec2(0.6, 1.0)) + (jitter - 0.5) * 0.08;
    float hole = open * 2.2 - 0.12;
    float outside = step(hole, rh);
    // the crack of gold: the facets just outside the opening
    float crack = open > 0.0 && open < 1.0 ? step(rh, hole + 0.04) * outside : 0.0;
    dark *= outside;

    // the ink: a flat tone per facet, slowly changing
    vec2 q = turn(time * 0.03) * (m - 0.5) * 3.0;
    float n = fbm(q + vec2(time * 0.04, -time * 0.03));
    float level = clamp(floor(n * 5.2) - 1.0, 0.0, 3.0);
    vec3 col = mix(vec3(0.05, 0.043, 0.094), vec3(0.149, 0.125, 0.275), level / 3.0);
    // threads of light along a few of the facets' edges, where a second,
    // finer ink runs on a ridge; the other edges barely darker
    float fine = fbm(m * 9.0 + vec2(time * 0.05, time * 0.02));
    float ridge = 1.0 - abs(2.0 * fine - 1.0);
    float line = smoothstep(0.03, 0.0, edge);
    col = mix(col, col * 0.8, line * 0.4);
    col = mix(col, vec3(0.62, 0.56, 0.82), line * smoothstep(0.93, 0.985, ridge) * 0.55);

    // the galaxy: a band of small diamonds across the dark, turning slowly
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    vec2 gp = turn(time * 0.015 - 0.45) * p;
    float band = exp(-pow(gp.y / 0.17, 2.0));
    vec2 g = gp * 60.0;
    vec2 cell = floor(g);
    float h = hash(cell + 11.0);
    if (h > 0.985 - 0.09 * band) {
        vec2 at = cell + 0.25 + 0.5 * vec2(hash(cell + 1.3), hash(cell + 4.1));
        vec2 d = abs(g - at);
        float size = 0.12 + 0.18 * hash(cell + 7.7);
        float diamond = step(d.x * 1.4 + d.y, size);
        float twinkle = 0.55 + 0.45 * sin(time * (0.8 + 2.0 * h) + h * 40.0);
        vec3 tone = hash(cell + 2.2) > 0.35 ? vec3(1.0, 0.84, 0.55) : vec3(0.75, 0.68, 1.0);
        col = mix(col, tone, diamond * twinkle * smoothstep(0.12, 0.3, length(p * vec2(0.6, 1.0))));
    }

    // the crack: facets of dull gold leaf, their edges bright, fading as it opens
    float fade = smoothstep(0.0, 0.06, open) * (1.0 - open);
    vec3 leaf = mix(vec3(0.42, 0.3, 0.16), vec3(0.62, 0.46, 0.24), jitter);
    vec3 gold = mix(leaf, vec3(1.0, 0.85, 0.52), line);
    col = mix(col, gold, crack);
    finalColor = vec4(col, max(dark * 0.97, crack * fade * mix(0.7, 1.0, line)));
}
