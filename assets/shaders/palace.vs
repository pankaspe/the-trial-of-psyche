#version 330
// Palace pieces and figures. The mesh is in cell-local space (0..1 for a
// block); matModel places it in the world (z up).

in vec3 vertexPosition;
in vec3 vertexNormal;

uniform mat4 mvp;
uniform mat4 matModel;

out vec3 fragWorld;
out vec3 fragLocal;
out vec3 fragNormal;

void main() {
    vec4 w = matModel * vec4(vertexPosition, 1.0);
    fragWorld = w.xyz;
    fragLocal = vertexPosition;
    fragNormal = normalize(mat3(matModel) * vertexNormal);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
