use glam::{Vec2, Mat4, Vec3};
use miniquad::{BufferType, Buffer, Context, Bindings, Pipeline, VertexAttribute, VertexFormat, BufferLayout, UniformDesc, UniformType};

#[repr(C)]
struct Vertex {
    pos: Vec2,
    uv: Vec2,
}

#[repr(C)]
struct Uniforms {
    u_mvp: Mat4,
}

pub struct Scene {
    pipeline: Pipeline,
    bindings: Bindings,
}

impl Scene {
    pub fn new(ctx: &mut Context) -> Scene {
        let vertices = Buffer::immutable(ctx, BufferType::VertexBuffer, &[
            Vertex { pos: Vec2 { x: 0., y: 0. }, uv: Vec2 { x: 0., y: 0. } },
            Vertex { pos: Vec2 { x: 1., y: -0. }, uv: Vec2 { x: 1., y: 0. } },
            Vertex { pos: Vec2 { x: 1., y: 1. }, uv: Vec2 { x: 1., y: 1. } },
            Vertex { pos: Vec2 { x: -0., y: 1. }, uv: Vec2 { x: 0., y: 1. } },
        ]);
        let indices = Buffer::immutable(ctx, BufferType::IndexBuffer, &[0, 1, 2, 2, 3, 0]);

        let image = image::load_from_memory(include_bytes!("../res/default.png")).unwrap();
        let texture = miniquad::Texture::from_rgba8(
            ctx,
            image.width() as u16,
            image.height() as u16,
            &image.to_rgba8()
        );
        texture.set_filter(ctx, miniquad::FilterMode::Nearest);

        let bindings = Bindings {
            vertex_buffers: vec![vertices],
            index_buffer: indices,
            images: vec![texture],
        };

        let shader = miniquad::Shader::new(
            ctx,
            include_str!("../res/text.vsh"),
            include_str!("../res/text.fsh"),
            miniquad::ShaderMeta {
                images: vec!["tex".to_string()],
                uniforms: miniquad::UniformBlockLayout {
                    uniforms: vec![UniformDesc::new("u_mvp", UniformType::Mat4)],
                },
            },
        ).unwrap();

        let pipeline = Pipeline::new(
            ctx,
            &[BufferLayout::default()],
            &[
                VertexAttribute::new("pos", VertexFormat::Float2),
                VertexAttribute::new("uv", VertexFormat::Float2),
            ],
            shader,
        );

        Scene { pipeline, bindings }
    }
}

impl miniquad::EventHandler for Scene {
    fn update(&mut self, _ctx: &mut miniquad::Context) {
    }

    fn draw(&mut self, ctx: &mut miniquad::Context) {
        let (width, height) = ctx.screen_size();
        let projection = Mat4::orthographic_rh(0., width, height, 0., -1., 1.);
        let view = Mat4::IDENTITY;
        let model = Mat4::from_scale(Vec3::new(500., 500., 1.));

        ctx.begin_default_pass(Default::default());

        ctx.apply_pipeline(&self.pipeline);
        ctx.apply_bindings(&self.bindings);

        let mvp = projection * view * model;
        ctx.apply_uniforms(&Uniforms {
            u_mvp: mvp,
        });
        ctx.draw(0, 6, 1);

        ctx.end_render_pass();
        ctx.commit_frame();
    }
}

fn main() {
    miniquad::start(miniquad::conf::Conf {
        window_title: "golden".to_owned(),
        ..Default::default()
    }, |ctx| Box::new(Scene::new(ctx)));
}

