#version 330
// The seam of two skies as the world turns over: a thin line of dark matter
// across the screen where one sky gives way to the other, jagged like a
// range of mountains seen from both worlds (peaks rising into the sky above,
// their mirror hanging into the one below), and a web of veins of the same
// ink branching out from it into both skies, finer and fainter the further
// they reach (once the dark between the levels). One colour: the ink.

in vec2 fragTexCoord;

uniform float time;
uniform float aspect;
uniform vec2 line; // x the seam (screen uv, y down), y how high its peaks rise (screen uv; 0: none)

out vec4 finalColor;

const vec3 INK = vec3(0.02, 0.016, 0.03);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
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
    for (int i = 0; i < 5; i++) {
        v += noise(p) * a;
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// A range of peaks along x: sharp crests, smaller ones between (0 .. ~1).
float range(float x, float seed) {
    float h = 0.0;
    float a = 1.0;
    for (int i = 0; i < 5; i++) {
        float n = noise(vec2(x, seed + float(i) * 7.3));
        float r = 1.0 - abs(2.0 * n - 1.0);
        h += a * r * r;
        x *= 2.1;
        a *= 0.45;
    }
    return h * 0.62;
}

// How far `x` is from the nearest edge of a web of cells (their points
// drifting slowly): 0 on an edge.
float web(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    float f1 = 8.0;
    float f2 = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash2(n + g);
            o = 0.5 + 0.42 * sin(time * 0.25 + 6.2831 * o);
            float d = length(g + o - f);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    return f2 - f1;
}

// A line of the web, `px` pixels wide: 1 on it, a soft edge.
float vein(float e, float px) {
    float d = e / max(fwidth(e), 1e-5); // pixels from the edge
    return exp(-pow(d / px, 2.0));
}

void main() {
    vec2 uv = fragTexCoord;
    if (line.y <= 1e-4) {
        discard;
    }
    float t = time;
    float x = uv.x * aspect;
    float across = uv.y - line.x; // screen heights from the seam, down into the sky below

    // the ridge: a thin core, peaks above and their mirror below, slowly shifting
    float drift = t * 0.02;
    float up = line.y * (0.12 + range(x * 5.0 + drift, 1.0));
    float down = line.y * (0.12 + range(x * 5.0 + drift + 0.37, 4.0));
    float edge = across < 0.0 ? -across - up : across - down; // < 0 inside
    float aa = fwidth(across);
    float ridge = 1.0 - smoothstep(-aa, aa, edge);

    // the web: veins of ink branching from the ridge, finer and sparser away from it
    float reach = abs(across) / max(line.y, 1e-4); // in peak heights
    vec2 w = vec2(fbm(vec2(x * 3.0, across * 6.0) + t * 0.04), fbm(vec2(x * 3.0 + 5.2, across * 6.0) - t * 0.03));
    vec2 p = vec2(x * 7.0, across * 9.0) + (w - 0.5) * 1.6;
    float coarse = vein(web(p), 1.3) * smoothstep(5.5, 1.0, reach);
    float fine = vein(web(p * 2.3 + 11.0), 0.9) * smoothstep(3.0, 0.6, reach);
    // the veins come and go along their length, slowly
    float live = smoothstep(0.3, 0.6, fbm(vec2(x * 4.0, across * 5.0) + vec2(-t * 0.06, t * 0.05)));
    float veins = max(coarse * 0.85, fine * 0.6) * live;

    float a = max(ridge, veins) * smoothstep(0.0, 0.25, line.y / 0.035);
    finalColor = vec4(INK, a * 0.95);
}
