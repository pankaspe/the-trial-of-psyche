#version 330
// Palace pieces and figures.
// The face orientation gives Kenney's three tones (left / right / top) as a
// light map t, which is re-coloured:
//   dark: flat moonlit palette, no depth cue -> illusions read as real joins;
//   lamp: warm light around Psyche plus a strong depth cue -> the joins fall apart.
// Blocks get their masonry courses and marble bevels procedurally.

in vec3 fragWorld;
in vec3 fragLocal;
in vec3 fragNormal;

uniform float light_amount;  // 0..1, lamp intensity
uniform float flicker;
uniform vec3 lamp_pos;       // world
uniform float lamp_radius;   // world units
uniform vec2 view_right;     // world xy direction that points right on screen
uniform vec3 depth_axis;     // world gradient of the painter's depth
uniform float depth_min;
uniform float depth_max;
uniform float mist_top;      // screen px from the top
uniform float mist_bottom;
uniform float screen_height;

// per piece
uniform float material;      // 0 marble, 1 masonry, 2 foliage, 3 bronze, 4 psyche, 5 cupid, 6 mourner, 7 lawn,
                             // 8 phantom, 9 rock (palette 7 grass, 8 earth, 9 phantom)
uniform float detail;        // 0 none, 1 marble block, 2 masonry block
uniform float hidden;        // 1: visible only in the lamp light, glowing gold; 2: the same, a faint ghost
uniform float alpha;
uniform float shade_soft;    // width of the left/right tone blend (curved figures)
uniform float glow;          // figures: inner light

out vec4 finalColor;

const vec3 MIST = vec3(0.07, 0.07, 0.17);
const float T_LEFT = 0.075;
const float T_RIGHT = 0.625;
const float T_TOP = 0.9;

vec3 ramp(vec3 a, vec3 b, vec3 c, float t) {
    return mix(mix(a, b, smoothstep(0.0, 0.55, t)), c, smoothstep(0.55, 1.0, t));
}

void palette(float m, float t, out vec3 night, out vec3 warm) {
    if (m < 0.5) {          // marble
        night = ramp(vec3(0.055, 0.065, 0.16), vec3(0.19, 0.25, 0.47), vec3(0.56, 0.65, 0.88), t);
        warm = ramp(vec3(0.30, 0.13, 0.08), vec3(0.80, 0.50, 0.27), vec3(0.97, 0.88, 0.68), t);
    } else if (m < 1.5) {   // masonry: darker, violet in the night
        night = ramp(vec3(0.04, 0.035, 0.11), vec3(0.13, 0.14, 0.32), vec3(0.34, 0.37, 0.62), t);
        warm = ramp(vec3(0.20, 0.08, 0.05), vec3(0.55, 0.32, 0.17), vec3(0.78, 0.58, 0.38), t);
    } else if (m < 2.5) {   // foliage
        night = ramp(vec3(0.02, 0.05, 0.07), vec3(0.06, 0.17, 0.22), vec3(0.22, 0.42, 0.48), t);
        warm = ramp(vec3(0.05, 0.08, 0.03), vec3(0.22, 0.32, 0.12), vec3(0.52, 0.62, 0.28), t);
    } else if (m < 3.5) {   // bronze
        night = ramp(vec3(0.05, 0.05, 0.10), vec3(0.24, 0.24, 0.38), vec3(0.65, 0.66, 0.82), t);
        warm = ramp(vec3(0.25, 0.10, 0.02), vec3(0.85, 0.50, 0.12), vec3(1.0, 0.86, 0.45), t);
    } else if (m < 4.5) {   // Psyche: pale ivory with a lilac shadow
        night = mix(vec3(0.30, 0.27, 0.52), vec3(0.98, 0.93, 0.90), t);
        warm = mix(vec3(0.42, 0.26, 0.30), vec3(1.0, 0.92, 0.82), t);
    } else if (m < 5.5) {   // Cupid: a figure of light
        night = mix(vec3(0.55, 0.30, 0.10), vec3(1.0, 0.86, 0.55), t);
        warm = night;
    } else if (m < 6.5) {   // the mourners of the prologue: dark veils
        night = mix(vec3(0.07, 0.06, 0.13), vec3(0.36, 0.33, 0.48), t);
        warm = mix(vec3(0.16, 0.09, 0.07), vec3(0.62, 0.45, 0.34), t);
    } else if (m < 7.5) {   // grass: blue-green under the moon
        night = ramp(vec3(0.02, 0.06, 0.07), vec3(0.08, 0.22, 0.21), vec3(0.30, 0.52, 0.43), t);
        warm = ramp(vec3(0.06, 0.08, 0.02), vec3(0.28, 0.38, 0.10), vec3(0.62, 0.72, 0.30), t);
    } else if (m < 8.5) {   // earth: brown, cooled by the moon
        night = ramp(vec3(0.05, 0.035, 0.06), vec3(0.18, 0.12, 0.14), vec3(0.42, 0.31, 0.28), t);
        warm = ramp(vec3(0.16, 0.08, 0.03), vec3(0.45, 0.28, 0.14), vec3(0.70, 0.50, 0.30), t);
    } else {                // phantom: paler and colder than marble; the lamp does not warm it
        night = ramp(vec3(0.09, 0.12, 0.24), vec3(0.28, 0.38, 0.60), vec3(0.72, 0.82, 1.0), t);
        warm = night * vec3(0.75, 0.8, 0.9);
    }
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 1 on a line of half-width w at `pos`, anti-aliased.
float line(float x, float pos, float w) {
    float aa = fwidth(x);
    return 1.0 - smoothstep(w, w + aa, abs(x - pos));
}

// Horizontal courses and staggered vertical joints on a side face.
float courses(float u, float z, float z0, float z1, float n) {
    const float W = 0.006;
    float tone = 1.0;
    for (float k = 1.0; k < n; k += 1.0) {
        tone = min(tone, mix(1.0, 0.84, line(z, z0 + (z1 - z0) * k / n, W)));
    }
    float c = floor((z - z0) / (z1 - z0) * n);
    if (c >= 0.0 && c < n) {
        float j;
        if (mod(c, 2.0) < 0.5) {
            j = line(u, 0.5, W);
        } else {
            j = max(line(u, 0.25, W), line(u, 0.75, W));
        }
        tone = min(tone, mix(1.0, 0.84, j));
    }
    return tone;
}

void main() {
    vec3 n = normalize(fragNormal);
    vec3 L = fragLocal;

    // Kenney's light map from the face orientation, relative to the view
    float side = mix(T_LEFT, T_RIGHT, smoothstep(-shade_soft, shade_soft, dot(n.xy, view_right)));
    float t = mix(side, T_TOP, smoothstep(0.5, 0.9, n.z));

    float tone = 1.0;
    if (detail > 0.5) {
        if (n.z > 0.5) {
            if (detail < 1.5) {
                // marble: a bevelled slab; back edges catch the light, front edges are shaded
                const float I = 0.07;
                const float W = 0.006;
                vec2 toward = normalize(depth_axis.xy);
                float inx = step(I - 0.01, L.x) * step(L.x, 1.0 - I + 0.01);
                float iny = step(I - 0.01, L.y) * step(L.y, 1.0 - I + 0.01);
                tone = mix(tone, dot(vec2(-1.0, 0.0), toward) > 0.0 ? 0.88 : 1.07, line(L.x, I, W) * iny);
                tone = mix(tone, dot(vec2(1.0, 0.0), toward) > 0.0 ? 0.88 : 1.07, line(L.x, 1.0 - I, W) * iny);
                tone = mix(tone, dot(vec2(0.0, -1.0), toward) > 0.0 ? 0.88 : 1.07, line(L.y, I, W) * inx);
                tone = mix(tone, dot(vec2(0.0, 1.0), toward) > 0.0 ? 0.88 : 1.07, line(L.y, 1.0 - I, W) * inx);
            }
        } else if (n.z > -0.5) {
            float u = abs(n.x) > 0.5 ? L.y : L.x;
            if (detail < 1.5) {
                // marble: a cornice just under the top edge, two courses below
                tone = mix(courses(u, L.z, 0.0, 0.9, 2.0), 1.13, line(L.z, 0.9, 0.006));
            } else {
                tone = courses(u, L.z, 0.0, 1.0, 3.0);
            }
        }
    }
    float m = material;
    if (material > 8.5) {
        // living rock: earth in rough, slanted strata with a few dark seams
        m = 8.0;
        float u = abs(n.x) > 0.5 ? L.y : L.x;
        float z = L.z + 0.06 * sin(u * 9.0 + floor(fragWorld.z) * 2.3) + 0.03 * sin(u * 23.0);
        float band = floor(z * 4.0);
        tone *= 0.9 + 0.12 * hash(vec2(band, floor(fragWorld.x + fragWorld.y)));
        tone *= mix(1.0, 0.78, line(fract(z * 4.0), 0.5, 0.03));
        if (n.z > 0.5) {
            tone *= 0.9 + 0.15 * hash(floor(L.xy * 9.0));
        }
    } else if (material > 7.5) {
        // phantom: faint bands of mist drift across the stone
        m = 9.0;
        tone *= 0.94 + 0.06 * sin(L.z * 31.0 + (L.x + L.y) * 7.0);
    } else if (material > 6.5) {
        // lawn: grass on top and in a ragged fringe under the edge, earth below
        float fringe = 0.84 - 0.05 * abs(sin(L.x * 23.0 + L.y * 17.0));
        m = (n.z > 0.5 || (n.z > -0.5 && L.z > fringe)) ? 7.0 : 8.0;
        if (n.z > 0.5) {
            tone *= 0.88 + 0.2 * hash(floor(L.xy * 16.0));
        }
    }
    float lum = (t * 0.40 + 0.16) * tone;
    t = clamp((lum - 0.16) / 0.40, 0.0, 1.0);

    float dist = distance(fragWorld, lamp_pos);
    float lit = clamp(light_amount * (1.0 - smoothstep(lamp_radius * 0.3, lamp_radius, dist)) * flicker, 0.0, 1.0);

    vec3 night;
    vec3 warm;
    palette(m, t, night, warm);
    vec3 col = mix(night, warm, lit);
    if (material < 3.5 || material > 6.5) {
        // under the lamp the eye adapts: what is far from the flame sinks into the dark
        col *= mix(1.0, 0.55, light_amount * (1.0 - lit));
        // true depth, visible only in the light
        float dn = clamp((dot(fragWorld, depth_axis) - depth_min) / max(depth_max - depth_min, 1.0), 0.0, 1.0);
        col *= mix(1.0, mix(0.42, 1.08, dn), light_amount);
    } else {
        col += vec3(0.98, 0.93, 0.90) * glow;
    }
    // the foot of the palace sinks into the sea of mist
    float sy = screen_height - gl_FragCoord.y;
    col = mix(col, MIST, smoothstep(mist_top, mist_bottom, sy) * 0.85);

    float a = alpha;
    if (material > 7.5 && material < 8.5) {
        // what the light unmasks: the phantom grows thin near the flame
        a *= mix(1.0, 0.3, lit);
    }
    if (hidden > 0.5) {
        // revealed by the lamp only: glowing gold
        col = ramp(vec3(0.30, 0.13, 0.08), vec3(0.80, 0.50, 0.27), vec3(0.97, 0.88, 0.68), t) * 1.25 + vec3(0.25, 0.15, 0.02);
        a *= clamp(lit * 1.4, 0.0, 1.0);
        if (hidden > 1.5) {
            // a veiled stone: a thin golden ghost, brighter on its edges
            vec3 e = min(L, 1.0 - L);
            float edge = 1.0 - smoothstep(0.0, 0.08, min(min(max(e.x, e.y), max(e.y, e.z)), max(e.x, e.z)));
            a *= 0.28 + 0.6 * edge;
        }
    }
    if (a < 0.003) {
        discard;
    }
    finalColor = vec4(col, a);
}
