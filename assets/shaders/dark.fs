#version 330
// Dark matter between two skies as the world turns over: a band of ink across
// the screen along the seam where one sky gives way to the other, its edges
// frayed and flowing, tendrils of the same ink reaching from it into both
// skies like smoke, a few motes of gold drifting in it (once the dark between
// the levels).

in vec2 fragTexCoord;

uniform float time;
uniform float aspect;
uniform vec2 line; // x the seam (screen uv, y down), y the band's half height (screen uv; 0: none)

out vec4 finalColor;

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
    for (int i = 0; i < 5; i++) {
        v += noise(p) * a;
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = fragTexCoord;
    float w = max(line.y, 1e-4);
    // across the band: 0 on the seam, 1 at its edges
    vec2 p = vec2(uv.x * aspect, (uv.y - line.x) / w);
    float t = time;

    // the ink flows along the seam, folding over itself
    vec2 q = vec2(p.x * 2.2 + t * 0.07, p.y * 0.8);
    vec2 warp = vec2(fbm(q + vec2(0.0, t * 0.11)), fbm(q + vec2(5.2, -t * 0.09)));
    float f = fbm(q + warp * 1.8 + vec2(t * 0.03, 0.0));

    // its edges soft and moving
    float fray = (f - 0.5) * 0.55;
    float r = abs(p.y);
    float dark = smoothstep(1.0 + fray, 0.3 + fray, r);

    // a faint sheen where the ink folds, no colour of its own
    float ridge = 1.0 - abs(2.0 * fbm(q * 1.7 + warp * 2.3) - 1.0);
    vec3 ink = vec3(0.02, 0.016, 0.03);
    vec3 col = ink + vec3(0.07) * pow(ridge, 12.0);

    // tendrils of the same ink: the level lines of a slow flow field, long
    // soft curves running across the seam from one sky into the other, a
    // thin core in a haze of smoke (measured in pixels), drawn here and there
    // along their length, the ink running along them
    float across = uv.y - line.x; // screen heights from the seam
    vec2 fp = vec2(uv.x * aspect * 3.2, across * 1.1);
    vec2 fw = vec2(fbm(fp * 0.9 + vec2(t * 0.05, -t * 0.04)), fbm(fp * 0.9 + vec2(3.7, t * 0.06)));
    float field = fbm(fp + fw * 1.2 + vec2(-t * 0.04, t * 0.03)) * 5.0;
    float lines = fract(field);
    float px = min(lines, 1.0 - lines) / max(fwidth(field), 1e-5); // pixels to the nearest line
    float width = 0.9 + 1.0 * fbm(fp * 2.0 + t * 0.15);
    float core = exp(-pow(px / width, 2.0));
    float halo = exp(-pow(px / (width * 6.0), 2.0)) * 0.35;
    float lit = smoothstep(0.36, 0.68, fbm(vec2(floor(field) * 3.1 + fp.y * 2.5 - t * 0.5, fp.x * 0.3)));
    float near = smoothstep(0.26, 0.04, abs(across)) * smoothstep(0.0, 0.3, line.y / 0.07);
    float reach = clamp((core + halo) * lit * near, 0.0, 1.0);
    col = mix(col, ink, reach);

    // motes of gold drifting in it
    vec2 s = vec2(p.x * 26.0 - t * 0.6, p.y * w * 26.0);
    vec2 cell = floor(s);
    float m = hash(cell);
    if (m > 0.9) {
        vec2 at = cell + vec2(hash(cell + 1.3), hash(cell + 4.1));
        float twinkle = 0.55 + 0.45 * sin(t * (1.0 + 2.0 * m) + m * 40.0);
        col += vec3(1.0, 0.82, 0.5) * smoothstep(0.14, 0.0, length(s - at)) * twinkle * dark * 0.9;
    }
    float a = max(dark * 0.88, clamp(reach, 0.0, 1.0) * 0.85);
    finalColor = vec4(col, a * step(1e-4, line.y));
}
