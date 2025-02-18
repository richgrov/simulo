#include <metal_stdlib>

using namespace metal;

vertex float4 vertex_main(uint vert_id [[vertex_id]], constant simd::float3* vertices) {
	return float4(vertices[vert_id][0], vertices[vert_id][1], vertices[vert_id][2], 1.0f);
}

fragment float4 fragment_main(float4 vertex_out [[stage_in]]) {
	return float4(1.0, 1.0, 1.0, 1.0);
}
