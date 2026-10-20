#version 330
// A sea of clouds under the palace: soft drifting noise, opaque at the bottom,
// fading out toward the top of the rectangle. `shift` slides it when the
// diorama turns, so the clouds seem to stay in the world.

in vec2 fragTexCoord;

uniform float light_amount;
uniform float shift;
uniform float time;
uniform vec3 tint;
uniform float density;
uniform vec3 crest_color; // sunlight on the crests (black at night)
uniform float lava;       // 0 .. 1: a sea of lava instead
uniform float front;      // 1: the layer drawn in front of the diorama


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
    float shown = tile_turn(uv);
    vec2 p = vec2(uv.x * 5.0 + shift + time * 0.012, uv.y * 3.0);
    float n = fbm(p) * 0.65 + fbm(p * 2.3 - vec2(time * 0.02, 0.0)) * 0.35;
    // billows: brighter crests on top of each cloud
    float crest = smoothstep(0.45, 0.8, n);
    float body = smoothstep(0.25, 0.75, n + uv.y * 0.6 - 0.25);
    float fade = smoothstep(0.0, 0.55, uv.y);
    vec3 col = tint * (0.7 + crest * 0.9);
    col += vec3(0.5, 0.32, 0.15) * crest * light_amount * 0.35;
    col += crest_color * crest;
    float a = body * fade * density;
    if (lava > 0.0) {
        // a sea of lava: a dark crust broken by glowing veins and molten pools,
        // in perspective (finer toward the horizon), flowing slowly, breathing
        float d = 1.0 / (0.22 + uv.y);
        vec2 q = vec2((uv.x - 0.5) * 3.2 * d + shift * 0.6, 2.2 * d);
        float n1 = fbm(q + vec2(time * 0.012, time * 0.02));
        float n2 = fbm(q * 1.7 + vec2(-time * 0.018, 0.0) + n1 * 1.5);
        float w = fwidth(n2) + 0.025;
        float vein = 1.0 - smoothstep(0.0, w, abs(n2 - 0.5));
        float pool = smoothstep(0.6, 0.78, n1);
        float pulse = 0.78 + 0.22 * sin(time * 1.1 + n1 * 14.0);
        vec3 crust = vec3(0.06, 0.015, 0.012) * (0.6 + 0.8 * n2);
        vec3 hot = mix(vec3(0.95, 0.24, 0.03), vec3(1.0, 0.72, 0.28), pool);
        vec3 lc = mix(crust, hot, clamp(max(vein * 0.85, pool) * pulse, 0.0, 1.0));
        lc = mix(lc, vec3(0.55, 0.12, 0.04), (1.0 - smoothstep(0.0, 0.5, uv.y)) * 0.5); // the heat haze far off
        col = mix(col, lc, lava);
        // in front of the diorama only its lowest edge: a sea lies under it, never over it
        float from = front > 0.5 ? 0.62 : 0.0;
        a = mix(a, smoothstep(from, from + 0.25, uv.y) * density, lava);
    }
    finalColor = vec4(col, a * shown);
}
