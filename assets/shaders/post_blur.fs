#version 330
// Post: a separable gaussian blur, 9 taps along `dir` (in source pixels).

in vec2 fragTexCoord;

uniform sampler2D texture0;
uniform vec2 texel;
uniform vec2 dir;

out vec4 finalColor;

void main() {
    const float W[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec2 step = texel * dir;
    vec3 c = texture(texture0, fragTexCoord).rgb * W[0];
    for (int i = 1; i < 5; i++) {
        c += texture(texture0, fragTexCoord + step * float(i)).rgb * W[i];
        c += texture(texture0, fragTexCoord - step * float(i)).rgb * W[i];
    }
    finalColor = vec4(c, 1.0);
}
