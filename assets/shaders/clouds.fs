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
    vec2 p = vec2(uv.x * 5.0 + shift + time * 0.012, uv.y * 3.0);
    float n = fbm(p) * 0.65 + fbm(p * 2.3 - vec2(time * 0.02, 0.0)) * 0.35;
    // billows: brighter crests on top of each cloud
    float crest = smoothstep(0.45, 0.8, n);
    float body = smoothstep(0.25, 0.75, n + uv.y * 0.6 - 0.25);
    float fade = smoothstep(0.0, 0.55, uv.y);
    vec3 col = tint * (0.7 + crest * 0.9);
    col += vec3(0.5, 0.32, 0.15) * crest * light_amount * 0.35;
    finalColor = vec4(col, body * fade * density);
}
