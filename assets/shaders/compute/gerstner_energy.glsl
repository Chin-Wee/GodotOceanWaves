#[compute]
#version 460
/** Reduces instantaneous seeded-spectrum energy over 16x16 tiles. */

#define PI (3.141592653589793)
#define G (9.81)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) restrict readonly uniform image2DArray spectrum;
layout(std430, set = 0, binding = 1) restrict writeonly buffer PartialEnergy { float values[]; };

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	float time;
	vec2 tile_length;
	float depth;
};

shared float energy_tile[256];

void main() {
	const ivec2 dims = imageSize(spectrum).xy;
	const uint map_size = uint(dims.x);
	const ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	const uint flat_index = uint(id.y) * map_size + uint(id.x);
	const ivec2 mirror = (dims - id) % dims;
	const uint mirror_index = uint(mirror.y) * map_size + uint(mirror.x);
	float energy = 0.0;
	if (flat_index < mirror_index) {
		vec2 k_vec = (vec2(id) - vec2(dims) * 0.5) * (2.0 * PI / tile_length);
		float k = length(k_vec) + 1e-6;
		float omega = sqrt(G * k * tanh(k * depth));
		vec2 modulation = vec2(cos(omega * time), sin(omega * time));
		vec4 h0 = imageLoad(spectrum, ivec3(id, int(cascade_index)));
		vec2 h = vec2(h0.x * modulation.x - h0.y * modulation.y, h0.x * modulation.y + h0.y * modulation.x)
			+ vec2(h0.z * modulation.x + h0.w * modulation.y, -h0.z * modulation.y + h0.w * modulation.x);
		energy = 2.0 * dot(h, h);
	}

	const uint lane = gl_LocalInvocationIndex;
	energy_tile[lane] = energy;
	barrier();
	for (uint stride = 128U; stride > 0U; stride >>= 1U) {
		if (lane < stride) energy_tile[lane] += energy_tile[lane + stride];
		barrier();
	}

	const uint groups_per_axis = gl_NumWorkGroups.x;
	const uint partial_index = cascade_index * groups_per_axis * gl_NumWorkGroups.y + gl_WorkGroupID.y * groups_per_axis + gl_WorkGroupID.x;
	if (lane == 0U) values[partial_index] = energy_tile[0];
}
