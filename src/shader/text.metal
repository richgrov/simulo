#include <metal_stdlib>

using namespace metal;

struct UiVertex {
	simd::float3 pos;
	simd::float2 uv;
};

struct OutVertex {
	simd::float4 pos [[position]];
	simd::float2 uv;
};

vertex OutVertex vertex_main(uint vert_id [[vertex_id]], constant UiVertex* vertices, constant simd::float4x4 *transform) {
	OutVertex out;
	out.pos = transform[0] * simd::float4(vertices[vert_id].pos, 1.0);
	out.uv = vertices[vert_id].uv;
	return out;
}

fragment float4 fragment_main(OutVertex vert [[stage_in]], constant simd::float3 *color, texture2d<float> texture [[texture(0)]]) {
	constexpr sampler tex_sampler(mag_filter::linear, min_filter::linear);

	return texture.sample(tex_sampler, vert.uv).x * float4(color[0], 1.0);
}

vertex OutVertex vertex_main2(uint vert_id [[vertex_id]], constant UiVertex* vertices) {
	OutVertex out;
	out.pos = simd::float4(vertices[vert_id].pos, 1.0);
	out.uv = vertices[vert_id].uv;
	return out;
}

fragment float4 fragment_main2(float4 vertex_out [[stage_in]]) {
	return float4(1.0, 1.0, 1.0, 1.0);
}


