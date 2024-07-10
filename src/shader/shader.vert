#version 450

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 tex_coord;

layout(binding = 0) uniform Uniforms {
    mat3 mvp;
    vec3 color;
} u;

layout(location = 0) out vec3 pass_color;
layout(location = 1) out vec2 pass_tex_coord;

void main() {
    gl_Position = vec4(u.mvp * vec3(pos, 1.0), 1.0);
    pass_color = u.color;
    pass_tex_coord = tex_coord;
}
