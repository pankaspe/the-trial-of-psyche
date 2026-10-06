#version 330
// Post, step 1: half the size, keeping only what is brighter than `threshold`
// (soft knee). Threshold 0 keeps everything: a plain downsample.

in vec2 fragTexCoord;

uniform sampler2D texture0;
uniform vec2 texel;      // one source pixel in uv
uniform float threshold;

out vec4 finalColor;

void main() {
    vec2 uv = fragTexCoord;
    vec3 c = texture(texture0, uv + texel * vec2(-0.5, -0.5)).rgb
        + texture(texture0, uv + texel * vec2(0.5, -0.5)).rgb
        + texture(texture0, uv + texel * vec2(-0.5, 0.5)).rgb
        + texture(texture0, uv + texel * vec2(0.5, 0.5)).rgb;
    c *= 0.25;
    float l = max(c.r, max(c.g, c.b));
    const float KNEE = 0.12;
    float soft = clamp(l - threshold + KNEE, 0.0, 2.0 * KNEE);
    soft = soft * soft / (4.0 * KNEE + 1e-4);
    float keep = max(soft, l - threshold) / max(l, 1e-4);
    finalColor = vec4(c * keep, 1.0);
}
