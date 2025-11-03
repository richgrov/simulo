#version 450

layout(location = 0) in vec3 pos;
layout(location = 1) in vec2 tex_coord;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec4 color;
} push_constants;

layout(location = 0) out vec4 pass_color;
layout(location = 1) out vec2 pass_tex_coord;

void main() {
    gl_Position = push_constants.mvp * vec4(pos, 1.0);
    pass_color = push_constants.color;
    pass_tex_coord = tex_coord;
}
