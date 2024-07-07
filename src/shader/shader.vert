#version 450

layout(location = 0) in vec2 pos;

layout(binding = 0) uniform ModelViewProjection {
    mat3 mvp;
    vec3 color;
} u;

layout(location = 0) out vec3 pass_color;

void main() {
    gl_Position = vec4(u.mvp * vec3(pos, 1.0), 1.0);
    pass_color = u.color;
}
