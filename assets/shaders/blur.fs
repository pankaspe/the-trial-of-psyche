#version 330
// One pass of a gaussian blur along `dir` (texels of the source): the world
// going out of focus between two levels, run across then down, on a small copy.

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec2 dir;

out vec4 finalColor;

void main() {
    // nine taps folded into five by the bilinear filter
    vec3 c = texture(texture0, fragTexCoord).rgb * 0.2270270270;
    vec2 d1 = dir * 1.3846153846;
    vec2 d2 = dir * 3.2307692308;
    c += texture(texture0, fragTexCoord + d1).rgb * 0.3162162162;
    c += texture(texture0, fragTexCoord - d1).rgb * 0.3162162162;
    c += texture(texture0, fragTexCoord + d2).rgb * 0.0702702703;
    c += texture(texture0, fragTexCoord - d2).rgb * 0.0702702703;
    finalColor = vec4(c, 1.0) * fragColor;
}
