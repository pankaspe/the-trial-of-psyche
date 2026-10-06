#version 330
// The veil between the levels: a luminous space Psyche crosses on Zephyr's
// wind. Deep violet at the edges, a golden light at the centre, slow clouds
// turning about it, wisps of wind streaming down (she is rising).

in vec2 fragTexCoord;

uniform float time;
uniform float aspect;
uniform float alpha;

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
    vec2 p = (uv - vec2(0.5, 0.45)) * vec2(aspect, 1.0);
    float r = length(p);

    vec3 edge = vec3(0.05, 0.04, 0.14);
    vec3 mid = vec3(0.32, 0.20, 0.46);
    vec3 glow = vec3(1.0, 0.86, 0.62);
    vec3 col = mix(mid, edge, smoothstep(0.2, 1.0, r));
    col = mix(col, glow, exp(-r * 4.5) * 0.9);

    // clouds turning slowly about the light, more slowly far from it (a spiral)
    float turn = time * 0.06 + 0.35 / (r + 0.25);
    vec2 q = mat2(cos(turn), -sin(turn), sin(turn), cos(turn)) * p * 2.4;
    float c = fbm(q + vec2(0.0, time * 0.04));
    float c2 = fbm(q * 2.1 - vec2(time * 0.05, 0.0));
    vec3 rose = vec3(0.95, 0.62, 0.70);
    col = mix(col, rose * (0.55 + 0.6 * c2), smoothstep(0.45, 0.8, c) * 0.5 * smoothstep(0.05, 0.4, r));

    // wisps of wind streaming down
    float lane = floor(uv.x * 70.0);
    float h = hash(vec2(lane, 3.0));
    float y = fract(uv.y * (0.6 + h) - time * (0.5 + h * 0.9) + h * 7.0);
    float wisp = smoothstep(0.0, 0.03, y) * smoothstep(0.3, 0.03, y) * step(0.78, h);
    float thin = 1.0 - smoothstep(0.0, 0.35, abs(fract(uv.x * 70.0) - 0.5));
    col += vec3(1.0, 0.92, 0.8) * wisp * thin * 0.35;

    // a few motes of light
    vec2 g = uv * vec2(aspect, 1.0) * 30.0 + vec2(0.0, -time * 1.5);
    vec2 cell = floor(g);
    float m = hash(cell);
    if (m > 0.93) {
        vec2 cpos = cell + vec2(hash(cell + 1.3), hash(cell + 4.1));
        col += glow * smoothstep(0.12, 0.0, length(g - cpos)) * 0.8;
    }
    finalColor = vec4(col, alpha);
}
