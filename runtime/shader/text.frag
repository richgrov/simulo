#version 450

layout(location = 0) in vec4 pass_color;
layout(location = 1) in vec2 pass_tex_coord;

layout(binding = 1) uniform sampler2D u_texture;

layout(location = 0) out vec4 out_color;

void main() {
    out_color = texture(u_texture, pass_tex_coord) * pass_color;
}
