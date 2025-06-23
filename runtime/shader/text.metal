#include <metal_stdlib>

using namespace metal;

struct UiVertex {
	simd::float3 pos;
	simd::float2 uv;
};

struct UiOut {
	simd::float4 pos [[position]];
	simd::float2 uv;
};

vertex UiOut vertex_main(uint vert_id [[vertex_id]], constant UiVertex* vertices, constant simd::float4x4 *transform) {
	UiOut out;
	out.pos = transform[0] * simd::float4(vertices[vert_id].pos, 1.0);
	out.uv = vertices[vert_id].uv;
	return out;
}

fragment float4 fragment_main(UiOut vert [[stage_in]], constant simd::float3 *color, texture2d<float> texture [[texture(0)]]) {
	constexpr sampler tex_sampler(mag_filter::linear, min_filter::linear);
	return texture.sample(tex_sampler, vert.uv) * float4(color[0], 1.0);
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

vertex MeshOut vertex_main2(uint vert_id [[vertex_id]], constant MeshVertex* vertices, constant simd::float4x4 *transform) {
	MeshOut out;
	float brightness = dot(sun, vertices[vert_id].normal);
	out.pos = transform[0] * simd::float4(vertices[vert_id].pos, 1.0);
	out.brightness = (brightness / 4) + 0.75;
	return out;
}

fragment float4 fragment_main2(MeshOut vert [[stage_in]], constant float3* color) {
	return float4(color[0] * vert.brightness, 1.0);
}
