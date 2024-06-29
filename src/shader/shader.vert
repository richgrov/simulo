#version 450

vec2 positions[] = vec2[](
    vec2(0.0, -0.5),
    vec2(0.5, 0.5),
    vec2(-0.5, 0.5),
    vec2(0.2, 0.5),
    vec2(0.5, -1.0),
    vec2(0.4, 1.0),
    vec2(-1.0, 0.4),
    vec2(-0.2, -0.5),
    vec2(0.0, 0.0)
);

vec3 colors[] = vec3[](
    vec3(1.0, 0.9, 0.9),
    vec3(1.0, 0.6, 0.6),
    vec3(1.0, 0.3, 0.3),
    vec3(0.9, 1.0, 0.6),
    vec3(0.6, 1.0, 0.9),
    vec3(0.3, 1.0, 0.3),
    vec3(0.3, 0.9, 1.0),
    vec3(1.0, 0.6, 1.0),
    vec3(0.9, 0.6, 1.0)
);

layout(location = 0) out vec3 pass_color;

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    pass_color = colors[gl_VertexIndex];
}
