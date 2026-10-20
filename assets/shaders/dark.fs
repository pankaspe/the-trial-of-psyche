#version 330
// Dark matter between two skies as the world turns over: a band of ink across
// the screen along the seam where one sky gives way to the other, its edges
// frayed, threads curling slowly in it, the brightest along its rims, a few
// motes of gold drifting like a far galaxy (once the dark between the levels).

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

    // the ink drifts along the seam, curling (stretched across it: its
    // threads run long, from one sky into the other)
    vec2 q = vec2(p.x * 2.6 + time * 0.04, p.y * 0.42);
    vec2 warp = vec2(fbm(q + vec2(0.0, time * 0.05)), fbm(q + vec2(5.2, -time * 0.04)));
    float f = fbm(q + warp * 1.6);

    // its frayed edges
    float fray = (f - 0.5) * 0.9;
    float r = abs(p.y);
    float dark = smoothstep(1.0 + fray, 0.55 + fray, r);

    // threads: the ridges of the warped noise, brightest toward the rims
    float ridge = 1.0 - abs(2.0 * fbm(q * 1.7 + warp * 2.3) - 1.0);
    float thread = pow(ridge, 10.0);
    float rim = smoothstep(0.0, 0.5, dark) * smoothstep(1.0, 0.45, dark);
    vec3 ink = vec3(0.018, 0.014, 0.035);
    vec3 col = ink + vec3(0.34, 0.29, 0.46) * thread * (0.15 + 0.85 * rim);
    col += vec3(0.85, 0.62, 0.38) * pow(ridge, 26.0) * 0.35 * rim;
    // past the ink the brightest threads reach on into both skies, fading
    float reach = pow(ridge, 16.0) * smoothstep(2.6, 0.9, r) * (1.0 - dark);
    col = mix(col, vec3(0.66, 0.54, 1.0), reach);

    // motes of gold drifting in it
    vec2 s = vec2(p.x * 26.0 - time * 0.6, p.y * w * 26.0);
    vec2 cell = floor(s);
    float m = hash(cell);
    if (m > 0.9) {
        vec2 at = cell + vec2(hash(cell + 1.3), hash(cell + 4.1));
        float twinkle = 0.55 + 0.45 * sin(time * (1.0 + 2.0 * m) + m * 40.0);
        col += vec3(1.0, 0.82, 0.5) * smoothstep(0.14, 0.0, length(s - at)) * twinkle * dark * 0.9;
    }
    finalColor = vec4(col, clamp(max(dark * 0.9, reach * 0.8), 0.0, 1.0) * step(1e-4, line.y));
}
