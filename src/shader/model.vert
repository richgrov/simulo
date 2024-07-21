#version 450

layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 normal;

layout(binding = 0) uniform Uniforms {
    mat4 mvp;
    vec3 color;
} u;

layout(location = 0) out vec3 pass_color;

void main() {
    gl_Position = u.mvp * vec4(pos, 1.0);
    pass_color = u.color;
}
