#include <metal_stdlib>

using namespace metal;

struct UiVertex {
	simd::float3 pos;
	simd::float2 uv;
};

struct UiOut {
	simd::float4 pos [[position]];
	simd::float4 color;
	simd::float2 uv;
};

struct PushConstants {
	simd::float4x4 transform;
	simd::float4 color;
};

vertex UiOut vertex_main(uint vert_id [[vertex_id]], constant UiVertex* vertices, constant PushConstants *push_constants) {
	UiOut out;
	out.pos = push_constants[0].transform * simd::float4(vertices[vert_id].pos, 1.0);
	out.color = push_constants[0].color;
	out.uv = vertices[vert_id].uv;
	return out;
}

fragment float4 fragment_main(UiOut vert [[stage_in]], texture2d<float> texture [[texture(0)]]) {
	constexpr sampler tex_sampler(mag_filter::linear, min_filter::linear);
	return texture.sample(tex_sampler, vert.uv) * vert.color;
}

struct MeshVertex {
	simd::float3 pos;
	simd::float3 normal;
};

struct MeshOut {
	simd::float4 pos [[position]];
	float brightness;
};

constant const simd::float3 sun = simd::float3(1, 1, 1);

vertex MeshOut vertex_main2(uint vert_id [[vertex_id]], constant MeshVertex* vertices, constant PushConstants *push_constants) {
	MeshOut out;
	float brightness = dot(sun, vertices[vert_id].normal);
	out.pos = push_constants[0].transform * simd::float4(vertices[vert_id].pos, 1.0);
	out.brightness = (brightness / 4) + 0.75;
	return out;
}

fragment float4 fragment_main2(MeshOut vert [[stage_in]], constant float3* color) {
	return float4(color[0] * vert.brightness, 1.0);
}
