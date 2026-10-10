#[compute]
#version 460
/** Combines tiled spectral energy into the per-cascade RMS target. */

layout(local_size_x = 256) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer PartialEnergy { float partial_values[]; };
layout(std430, set = 0, binding = 1) restrict writeonly buffer CascadeEnergy { float energy_values[]; };

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	uint partial_count;
};

shared float partial_sum[256];

void main() {
	const uint lane = gl_LocalInvocationID.x;
	float sum = 0.0;
	for (uint index = lane; index < partial_count; index += gl_WorkGroupSize.x) {
		sum += partial_values[cascade_index * partial_count + index];
	}
	partial_sum[lane] = sum;
	barrier();
	for (uint stride = gl_WorkGroupSize.x >> 1U; stride > 0U; stride >>= 1U) {
		if (lane < stride) partial_sum[lane] += partial_sum[lane + stride];
		barrier();
	}
	if (lane == 0U) {
		energy_values[cascade_index] = partial_sum[0];
	}
}
