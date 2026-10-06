#version 330
// Far mountain ranges in three layers, far to near, standing on the sea of
// clouds. Each layer is a panorama that closes on itself over a full turn of
// the diorama (`shift`, in quarter turns): the far ranges move less on screen,
// the near ones more. Slopes facing the orb catch its light on the crest.

in vec2 fragTexCoord;

uniform float light_amount;
uniform float shift;
uniform float aspect;
uniform float horizon;     // screen uv y where the clouds begin
uniform vec2 orb_pos;      // as in the sky
uniform vec3 color_far;
uniform vec3 color_mid;
uniform vec3 color_near;
uniform vec3 rim;
uniform vec3 halo_color;
uniform float halo_width;
uniform vec3 haze;

out vec4 finalColor;

const float TAU = 6.2831853;

// A range: peaks from folded sines, periodic over a full turn. Each
// octave's number of peaks per turn is an integer and not all are even, so
// the four views show four different stretches of the panorama.
float range(float th, float seed, int octaves) {
    float h = 0.0;
    float amp = 1.0;
    float total = 0.0;
    for (int i = 0; i < octaves; i++) {
        float k = float(i == 0 ? 3 : i == 1 ? 5 : i == 2 ? 9 : i == 3 ? 14 : i == 4 ? 23 : 37);
        float p = abs(sin(0.5 * k * th + seed * (1.7 + float(i))));
        float r = 1.0 - p;
        h += amp * r * sqrt(r);
        total += amp;
        amp *= 0.48;
    }
    return h / total;
}

float theta(float x, float span) {
    return (x - 0.5) * aspect * span + shift * TAU * 0.25;
}

// Height of a layer at screen x (fraction of the screen height above its base).
float layer(float x, float span, float seed, float amp) {
    return amp * range(theta(x, span), seed, 6);
}

vec3 shade(vec3 base, float x, float y, float top, float span, float seed, float amp, float bottom) {
    // the broad slope (low octaves only): which way the mountain faces
    float e = 0.03; // wide: the light turns softly over the peaks
    float hl = amp * range(theta(x - e, span), seed, 3);
    float hr = amp * range(theta(x + e, span), seed, 3);
    float slope = (hr - hl) / (2.0 * e);
    float toward = clamp((orb_pos.x - shift * 0.03 - x) * 6.0, -1.0, 1.0);
    float lit = smoothstep(0.0, 1.0, clamp(0.5 + slope * toward * 0.8, 0.0, 1.0));
    vec3 col = base * (0.86 + 0.24 * lit);
    // a warm rim just under the crest on the lit side
    float crest = 1.0 - smoothstep(0.0, 0.02, y - top);
    col += rim * crest * lit * 0.3;
    // the foot of each range dissolves in the haze of the clouds
    col = mix(col, haze, smoothstep(top, bottom, y) * 0.85);
    return col;
}

void main() {
    vec2 uv = fragTexCoord;
    float x = uv.x;
    float y = uv.y;
    float b0 = horizon - 0.02;
    float b1 = horizon + 0.03;
    float b2 = horizon + 0.08;
    float t0 = b0 - 0.05 - layer(x, 3.0, 0.3, 0.22);
    float t1 = b1 - 0.03 - layer(x, 1.7, 2.1, 0.17);
    float t2 = b2 - 0.02 - layer(x, 1.0, 4.7, 0.12);
    vec3 col;
    if (y > t2) {
        col = shade(color_near, x, y, t2, 1.0, 4.7, 0.12, b2 + 0.1);
    } else if (y > t1) {
        col = shade(color_mid, x, y, t1, 1.7, 2.1, 0.17, b1 + 0.1);
    } else if (y > t0) {
        col = shade(color_far, x, y, t0, 3.0, 0.3, 0.22, b0 + 0.1);
        // the far range stands in the orb's glow
        vec2 dv = (uv - vec2(orb_pos.x - shift * 0.03, orb_pos.y * horizon)) * vec2(aspect, 1.0);
        col += halo_color * exp(-length(dv) * halo_width) * 0.5;
    } else {
        discard;
    }
    col = mix(col, col * vec3(1.4, 1.1, 0.8), light_amount * 0.4);
    finalColor = vec4(col, 1.0);
}
