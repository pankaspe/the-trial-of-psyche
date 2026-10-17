#version 330
// The dark between two levels, where the last one broke up: threads of ink
// curling slowly about the middle of the screen, a far galaxy turning in it
// (a band of violet dust and motes of gold). `amount` is how far it reaches
// (the middle under the ending card, the whole screen at 1); `open` parts it
// from the middle out as the next level rises, a ring of gold on its edge.

in vec2 fragTexCoord;

uniform float time;
uniform float aspect;
uniform float amount;
uniform float open;

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

mat2 turn(float a) {
    return mat2(cos(a), -sin(a), sin(a), cos(a));
}

void main() {
    vec2 uv = fragTexCoord;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    float r = length(p * vec2(0.6, 1.0)); // wider than tall, like the card

    // the ink curls slowly about the middle, faster near it
    vec2 q = turn(time * 0.05 + 0.25 / (r + 0.3)) * p * 2.2;
    vec2 warp = vec2(fbm(q + vec2(0.0, time * 0.03)), fbm(q + vec2(5.2, -time * 0.025)));
    float f = fbm(q + warp * 1.6);

    // its frayed edge: the dark reaches out, then parts from the middle
    float fray = (f - 0.5) * 0.45;
    float reach = amount * 1.4;
    float dark = smoothstep(reach + fray, reach + fray - 0.3, r);
    float hole = open * 2.0 - 0.25;
    dark *= smoothstep(hole + fray - 0.3, hole + fray, r);

    // threads: the ridges of the warped noise, brightest along the edge
    float ridge = 1.0 - abs(2.0 * fbm(q * 1.7 + warp * 2.3) - 1.0);
    float thread = pow(ridge, 10.0);
    float rim = smoothstep(0.0, 0.5, dark) * smoothstep(1.0, 0.45, dark);
    vec3 ink = vec3(0.018, 0.014, 0.035);
    vec3 col = ink + vec3(0.34, 0.29, 0.46) * thread * (0.12 + 0.88 * rim);
    col += vec3(0.85, 0.62, 0.38) * pow(ridge, 26.0) * 0.35 * rim;

    // the galaxy: a band of dust across the dark, turning slowly
    vec2 gp = turn(time * 0.02 - 0.45) * p;
    float band = exp(-pow((gp.y + 0.06 * sin(gp.x * 2.0 + time * 0.05)) / 0.16, 2.0));
    float dust = fbm(gp * 3.0 + warp * 0.8 + vec2(time * 0.01, 0.0));
    col += vec3(0.36, 0.28, 0.56) * smoothstep(0.3, 0.75, dust) * band * 0.9;
    col += vec3(0.95, 0.8, 0.6) * exp(-r * 6.0) * band * 0.18; // its bright heart, behind the text

    // motes of gold turning in the dark, thicker in the band
    vec2 s = turn(time * 0.07 + 0.9 / (r + 0.35)) * p * 26.0;
    vec2 cell = floor(s);
    float m = hash(cell);
    if (m > 0.9 - 0.12 * band) {
        vec2 at = cell + vec2(hash(cell + 1.3), hash(cell + 4.1));
        float twinkle = 0.55 + 0.45 * sin(time * (1.0 + 2.0 * m) + m * 40.0);
        float around = smoothstep(0.18, 0.42, r);
        col += vec3(1.0, 0.82, 0.5) * smoothstep(0.14, 0.0, length(s - at)) * twinkle * around * 0.9;
    }

    // the ring of gold on the edge that parts the dark, through its threads
    float ring = 0.0;
    if (open > 0.0 && open < 1.0) {
        ring = exp(-pow((r - hole - fray + 0.1) / 0.035, 2.0)) * smoothstep(0.0, 0.08, open) * (1.0 - open);
    }
    vec3 gold = vec3(1.0, 0.8, 0.46) * (0.8 + 1.6 * pow(ridge, 3.0));
    float a = clamp(max(dark * 0.97, ring * 0.75), 0.0, 1.0);
    col = mix(col, gold, ring * (1.0 - dark * 0.5));
    finalColor = vec4(col, a);
}
