#version 330
// The sky behind the level: a gradient from the zenith to the horizon, stars,
// the sun or the moon with its halo, drifting haze. The colours come from the
// setting. `horizon` is where the sea of clouds meets the sky (screen uv), so
// the gradient follows the camera; `shift` pans the stars a little when the
// diorama turns. Warms while the lamp burns.

in vec2 fragTexCoord;

uniform float light_amount;
uniform float shift;
uniform float time;
uniform float aspect;  // width / height
uniform float horizon; // screen uv y of the horizon
uniform vec3 sky_top;
uniform vec3 sky_mid;
uniform vec3 sky_horizon;
uniform vec2 orb_pos;  // x in screen uv, y as a fraction of the horizon height
uniform float orb_radius;
uniform vec3 orb_color;
uniform vec3 halo_color;
uniform float halo_width;
uniform float stars;
uniform vec3 haze;
uniform float night_clouds; // 0 none .. 1 dark clouds drifting across the moon

// The drifting night clouds: soft ellipses around the moon's height (the first
// three cross the moon; render/setting.odin `moon_cover` mirrors them).
const int CLOUDS = 6;
const float C_SPEED[6] = float[](0.009, 0.007, 0.011, 0.005, 0.006, 0.004);
const float C_PHASE[6] = float[](0.10, 0.55, 0.85, 0.30, 0.70, 0.20);
const float C_DY[6] = float[](0.0, -0.02, 0.025, -0.13, 0.15, 0.3);
const float C_W[6] = float[](0.22, 0.17, 0.2, 0.28, 0.22, 0.32);
const float C_H[6] = float[](0.07, 0.06, 0.075, 0.06, 0.055, 0.07);
// each cloud is three lobes: offsets (in its own width / height) and sizes
const vec2 LOBE[3] = vec2[](vec2(-0.55, 0.15), vec2(0.0, -0.3), vec2(0.5, 0.1));
const float LOBE_S[3] = float[](0.7, 1.0, 0.75);

float cloud(vec2 uv, vec2 c, float w, float h, float rag) {
    float d = 0.0;
    for (int j = 0; j < 3; j++) {
        vec2 o = c + vec2(LOBE[j].x * w / aspect, LOBE[j].y * h);
        vec2 e = vec2((uv.x - o.x) * aspect / (w * LOBE_S[j]), (uv.y - o.y) / (h * LOBE_S[j]));
        d = max(d, smoothstep(1.0, 0.25, dot(e, e) + rag));
    }
    return d;
}

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
    float y = uv.y / max(horizon, 0.05); // 0 zenith .. 1 horizon
    vec3 col = mix(sky_top, sky_mid, smoothstep(0.0, 0.6, y));
    col = mix(col, sky_horizon, smoothstep(0.35, 1.0, y));

    // stars, drifting with the turn of the palace; fewer toward the horizon
    vec2 suv = uv + vec2(shift * 0.06, 0.0);
    vec2 grid = suv * vec2(160.0, 90.0);
    vec2 cell = floor(grid);
    float h = hash(cell);
    if (h > 0.982) {
        vec2 c = cell + vec2(hash(cell + 3.1), hash(cell + 7.7));
        float d = length(grid - c);
        float tw = 0.55 + 0.45 * sin(time * (1.0 + h * 3.0) + h * 40.0);
        float fade = stars < 0.99 ? stars * smoothstep(0.6, 0.0, y) : 1.0 - uv.y * 0.8;
        col += vec3(0.75, 0.8, 1.0) * smoothstep(0.2, 0.0, d) * tw * fade * (1.0 - light_amount * 0.6);
    }
    // the orb, with a wide halo
    vec2 mp = vec2(orb_pos.x - shift * 0.03, orb_pos.y * horizon);
    vec2 dv = (uv - mp) * vec2(aspect, 1.0);
    float md = length(dv);
    float disc = smoothstep(orb_radius + 0.003, orb_radius - 0.003, md);
    float spots = stars > 0.99 ? noise(dv * 60.0) * 0.12 + noise(dv * 140.0) * 0.06 : 0.0;
    col = mix(col, orb_color - spots, disc * (1.0 - light_amount * 0.35));
    col += halo_color * exp(-md * halo_width) * (1.0 - light_amount * 0.4);
    // night clouds: they cover the moon and its halo, their edges lit silver
    if (night_clouds > 0.0) {
        float dens = 0.0;
        for (int i = 0; i < CLOUDS; i++) {
            float cx = fract(C_PHASE[i] + time * C_SPEED[i]) * 1.9 - 0.45 - shift * 0.03;
            float rag = (noise(uv * vec2(12.0, 26.0) + vec2(time * 0.03 + float(i) * 7.0, float(i))) - 0.5) * 0.9
                + (noise(uv * vec2(40.0, 80.0) + float(i) * 3.0) - 0.5) * 0.3;
            dens = max(dens, cloud(uv, vec2(cx, mp.y + C_DY[i]), C_W[i], C_H[i], rag));
        }
        // grey-blue in the moonlight, paler near the moon, a silver lining on the edges
        float shade = mix(0.75, 1.0, smoothstep(0.0, 0.8, dens));
        vec3 body = (sky_mid * 1.5 + vec3(0.025, 0.027, 0.045)) * shade;
        float rim = dens * (1.0 - dens) * 4.0;
        float lit = exp(-md * 6.0) * (0.3 + rim);
        col = mix(col, body + orb_color * 0.4 * lit, dens * 0.94 * night_clouds);
    }
    // drifting haze bands, low in the sky
    float m = noise(uv * vec2(3.0, 6.0) + vec2(time * 0.015 + shift * 0.1, 0.0)) * 0.6
        + noise(uv * vec2(7.0, 12.0) - vec2(time * 0.02, 0.0)) * 0.4;
    col += haze * m * smoothstep(0.35, 1.0, y);
    // the lamp warms the air
    col = mix(col, col * vec3(1.6, 1.1, 0.7) + vec3(0.04, 0.02, 0.0), light_amount * 0.5);
    finalColor = vec4(col, 1.0);
}
