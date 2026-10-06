#version 330
// Post, the last step: the scene with its bloom, light shafts from the sun,
// tilt-shift, a painted look, then the grade (exposure, tone curve, contrast,
// saturation, lift/gain), chromatic fringes, vignette and grain.
// Every effect is off at 0, so one shader serves every style.

in vec2 fragTexCoord;

uniform sampler2D texture0;  // the scene
uniform sampler2D bloom_tex; // its bright parts, blurred wide
uniform sampler2D soft_tex;  // the whole scene, blurred
uniform vec2 resolution;
uniform float time;

uniform float bloom;
uniform float rays;          // light shafts from `sun`
uniform vec2 sun;            // screen uv
uniform float tilt;          // tilt-shift: blur away from the band in focus...
uniform float focus;         // ...at this screen height (uv): where Psyche is
uniform float orton;         // a dreamy glow: the blurred scene screened over it
uniform float paint;         // > 0: brush strokes (Kuwahara)
uniform float ink;           // dark outlines on the edges
uniform float paper;         // paper texture
uniform float exposure;
uniform float tonemap;       // 0 none .. 1 filmic (ACES)
uniform float contrast;
uniform float saturation;
uniform vec3 lift;           // colour added in the shadows
uniform vec3 gain;           // colour multiplied in the lights
uniform float chroma;        // fringe width in pixels at the edges
uniform float vignette;
uniform float grain;

out vec4 finalColor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 aces(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// Kuwahara: the flattest of four squares around the pixel gives its colour,
// so surfaces turn into flat strokes and the edges stay sharp.
vec3 kuwahara(vec2 uv, int r) {
    vec2 px = 1.0 / resolution;
    vec3 best = vec3(0.0);
    float best_var = 1e9;
    for (int q = 0; q < 4; q++) {
        vec2 o = vec2(q == 0 || q == 2 ? -1.0 : 0.0, q < 2 ? -1.0 : 0.0) * float(r);
        vec3 m = vec3(0.0);
        vec3 s = vec3(0.0);
        float n = 0.0;
        for (int y = 0; y <= r; y++) {
            for (int x = 0; x <= r; x++) {
                vec3 c = texture(texture0, uv + (o + vec2(float(x), float(y))) * px).rgb;
                m += c;
                s += c * c;
                n += 1.0;
            }
        }
        m /= n;
        s = abs(s / n - m * m);
        float v = s.r + s.g + s.b;
        if (v < best_var) {
            best_var = v;
            best = m;
        }
    }
    return best;
}

void main() {
    vec2 uv = fragTexCoord;
    vec2 px = 1.0 / resolution;
    vec2 from_mid = uv - 0.5;

    vec3 col;
    if (chroma > 0.0) {
        vec2 off = from_mid * length(from_mid) * chroma * 2.0 * px;
        col = vec3(texture(texture0, uv + off).r, texture(texture0, uv).g, texture(texture0, uv - off).b);
    } else {
        col = texture(texture0, uv).rgb;
    }
    if (paint > 0.0) {
        col = mix(col, kuwahara(uv, int(paint)), 1.0);
    }
    vec3 soft = texture(soft_tex, uv).rgb;
    if (tilt > 0.0) {
        float d = abs(uv.y - focus);
        col = mix(col, soft, smoothstep(0.1, 0.38, d) * tilt);
    }
    if (ink > 0.0) {
        float l00 = luma(texture(texture0, uv + px * vec2(-1.0, -1.0)).rgb);
        float l10 = luma(texture(texture0, uv + px * vec2(1.0, -1.0)).rgb);
        float l01 = luma(texture(texture0, uv + px * vec2(-1.0, 1.0)).rgb);
        float l11 = luma(texture(texture0, uv + px * vec2(1.0, 1.0)).rgb);
        float e = length(vec2(l00 + l01 - l10 - l11, l00 + l10 - l01 - l11));
        col *= 1.0 - ink * smoothstep(0.12, 0.3, e);
    }
    if (orton > 0.0) {
        col = 1.0 - (1.0 - col) * (1.0 - soft * orton);
    }
    col += texture(bloom_tex, uv).rgb * bloom;
    if (rays > 0.0) {
        // light shafts: the bright parts smeared toward the sun
        vec2 step = (sun - uv) / 40.0;
        vec2 p = uv;
        float decay = 1.0;
        vec3 shafts = vec3(0.0);
        for (int i = 0; i < 40; i++) {
            p += step;
            shafts += texture(bloom_tex, p).rgb * decay;
            decay *= 0.95;
        }
        col += shafts / 40.0 * rays * 3.0;
    }

    col *= exposure;
    col = mix(col, aces(col * 1.25), tonemap);
    col = (col - 0.5) * contrast + 0.5;
    col = mix(vec3(luma(col)), col, saturation);
    col = max(col, 0.0);
    col = col * gain + lift * (1.0 - col);
    if (paper > 0.0) {
        float fibre = noise(uv * resolution * 0.35) * 0.5 + noise(uv * resolution * 0.08) * 0.5;
        float blot = noise(uv * vec2(6.0, 4.0));
        col *= 1.0 - paper * (0.12 * fibre + 0.1 * blot);
    }
    float vig = smoothstep(0.35, 0.95, length(from_mid * vec2(resolution.x / resolution.y * 0.75, 1.0)) * 1.3);
    col *= 1.0 - vignette * vig;
    col += (hash(uv * resolution + fract(time) * 91.7) - 0.5) * grain;
    finalColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
