#version 330
// Night sky behind the palace: deep gradient, twinkling stars, the moon, low mist.
// `shift` pans it a little when the diorama turns. Warms while the lamp burns.

in vec2 fragTexCoord;

uniform float light_amount;
uniform float shift;
uniform float time;
uniform float aspect;  // width / height

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

void main() {
    vec2 uv = fragTexCoord;
    vec3 top = vec3(0.012, 0.015, 0.05);
    vec3 bottom = vec3(0.08, 0.07, 0.18);
    vec3 col = mix(top, bottom, smoothstep(0.0, 1.0, uv.y));

    // stars, drifting with the turn of the palace
    vec2 suv = uv + vec2(shift * 0.06, 0.0);
    vec2 grid = suv * vec2(160.0, 90.0);
    vec2 cell = floor(grid);
    float h = hash(cell);
    if (h > 0.982) {
        vec2 c = cell + vec2(hash(cell + 3.1), hash(cell + 7.7));
        float d = length(grid - c);
        float tw = 0.55 + 0.45 * sin(time * (1.0 + h * 3.0) + h * 40.0);
        col += vec3(0.75, 0.8, 1.0) * smoothstep(0.2, 0.0, d) * tw * (1.0 - uv.y * 0.8) * (1.0 - light_amount * 0.6);
    }
    // the moon, with a wide halo
    vec2 mp = vec2(0.80 - shift * 0.03, 0.2);
    vec2 dv = (uv - mp) * vec2(aspect, 1.0);
    float md = length(dv);
    float disc = smoothstep(0.052, 0.046, md);
    float spots = noise(dv * 60.0) * 0.12 + noise(dv * 140.0) * 0.06;
    col = mix(col, vec3(0.86, 0.88, 1.0) - spots, disc * (1.0 - light_amount * 0.35));
    col += vec3(0.3, 0.33, 0.55) * exp(-md * 9.0) * 0.35 * (1.0 - light_amount * 0.4);
    // drifting mist bands
    float m = noise(uv * vec2(3.0, 6.0) + vec2(time * 0.015 + shift * 0.1, 0.0)) * 0.6
        + noise(uv * vec2(7.0, 12.0) - vec2(time * 0.02, 0.0)) * 0.4;
    col += vec3(0.16, 0.16, 0.32) * m * smoothstep(0.35, 1.0, uv.y) * 0.55;
    // the lamp warms the air
    col = mix(col, col * vec3(1.6, 1.1, 0.7) + vec3(0.04, 0.02, 0.0), light_amount * 0.5);
    finalColor = vec4(col, 1.0);
}
