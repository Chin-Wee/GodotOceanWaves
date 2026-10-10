#[compute]
#version 460
/** Replaces only the FFT/IFFT synthesis, writing its existing spatial buffer layout. */

#define PI           (3.141592653589793)
#define G            (9.81)
#define MODE_COUNT   120U
#define RECORD_SIZE  (MODE_COUNT * 2U)
#define NUM_SPECTRA  (4U)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) restrict readonly uniform image2DArray spectrum;
layout(std430, set = 0, binding = 1) restrict buffer FFTBuffer { vec2 data[]; };
layout(std430, set = 0, binding = 2) restrict readonly buffer ModeBuffer { uint modes[]; };
layout(std430, set = 0, binding = 3) restrict readonly buffer CascadeEnergy { float target_energy[]; };

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	float time;
	vec2 tile_length;
	float depth;
	float choppiness;
};

vec2 mul_complex(vec2 a, vec2 b) {
	return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

float dispersion_relation(float k) {
	return sqrt(G * k * tanh(k * depth));
}

#define DATA_OUT(id, layer) (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 + NUM_SPECTRA*map_size*map_size + (layer)*map_size*map_size + (id).y*map_size + (id).x])

void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);
	const uint record = cascade_index * RECORD_SIZE;
	const uint mode_base = record;
	const vec2 dk = 2.0 * PI / tile_length;
	const vec2 pixel_fraction = vec2(id.xy) / float(map_size);
	const float sign_shift = -2.0 * float((id.x & 1) ^ (id.y & 1)) + 1.0;

	vec2 k_vectors[MODE_COUNT];
	vec2 heights[MODE_COUNT];
	vec2 heights_i[MODE_COUNT];
	float selected_energy = 0.0;

	for (uint i = 0U; i < MODE_COUNT; ++i) {
		uint flat_index = modes[mode_base + i * 2U];
		if (flat_index == 0xFFFFFFFFU) {
			k_vectors[i] = vec2(0.0);
			heights[i] = vec2(0.0);
			heights_i[i] = vec2(0.0);
			continue;
		}

		ivec2 wave_id = ivec2(int(flat_index % map_size), int(flat_index / map_size));
		vec2 k_vec = (vec2(wave_id) - float(map_size) * 0.5) * dk;
		float k = length(k_vec) + 1e-6;
		float omega = dispersion_relation(k);
		vec2 modulation = vec2(cos(omega * time), sin(omega * time));
		vec4 h0 = imageLoad(spectrum, ivec3(wave_id, int(cascade_index)));
		vec2 h = mul_complex(h0.xy, modulation) + mul_complex(h0.zw, vec2(modulation.x, -modulation.y));
		float mode_scale = uintBitsToFloat(modes[mode_base + i * 2U + 1U]);
		k_vectors[i] = k_vec;
		heights[i] = h * mode_scale;
		heights_i[i] = vec2(-h.y, h.x) * mode_scale;
		selected_energy += 2.0 * dot(heights[i], heights[i]);
	}
	float amplitude_scale = sqrt(target_energy[cascade_index] / max(selected_energy, 1e-8));

	float height = 0.0;
	float displacement_x = 0.0;
	float displacement_z = 0.0;
	float dhy_dx = 0.0;
	float dhy_dz = 0.0;
	float dhx_dx = 0.0;
	float dhz_dz = 0.0;
	float dhz_dx = 0.0;

	for (uint i = 0U; i < MODE_COUNT; ++i) {
		vec2 k_vec = k_vectors[i];
		float k = length(k_vec);
		if (k <= 0.0) continue;
		uint flat_index = modes[mode_base + i * 2U];
		if (flat_index == 0xFFFFFFFFU) continue;
		// The existing FFT transposes between its two 1D passes and skips the final
		// transpose, so stored spatial X/Y correspond to source spectrum Y/X.
		vec2 centered_frequency = vec2(flat_index % map_size, flat_index / map_size) - float(map_size) * 0.5;
		float phase = 2.0 * PI * dot(centered_frequency, pixel_fraction.yx);
		vec2 phase_factor = vec2(cos(phase), sin(phase));
		vec2 h = heights[i] * amplitude_scale;
		vec2 h_inv = heights_i[i] * amplitude_scale;
		vec2 k_unit = k_vec / k;
		vec2 hx = h_inv * k_unit.y * choppiness;
		vec2 hz = h_inv * k_unit.x * choppiness;
		vec2 grad_y_x = h_inv * k_vec.y;
		vec2 grad_y_z = h_inv * k_vec.x;
		vec2 grad_x_x = -h * k_vec.y * k_unit.y * choppiness;
		vec2 grad_z_z = -h * k_vec.x * k_unit.x * choppiness;
		vec2 grad_z_x = -h * k_vec.y * k_unit.x * choppiness;

		height += 2.0 * mul_complex(h, phase_factor).x;
		displacement_x += 2.0 * mul_complex(hx, phase_factor).x;
		displacement_z += 2.0 * mul_complex(hz, phase_factor).x;
		dhy_dx += 2.0 * mul_complex(grad_y_x, phase_factor).x;
		dhy_dz += 2.0 * mul_complex(grad_y_z, phase_factor).x;
		dhx_dx += 2.0 * mul_complex(grad_x_x, phase_factor).x;
		dhz_dz += 2.0 * mul_complex(grad_z_z, phase_factor).x;
		dhz_dx += 2.0 * mul_complex(grad_z_x, phase_factor).x;
	}

	DATA_OUT(id, 0U) = vec2(displacement_x, height) * sign_shift;
	DATA_OUT(id, 1U) = vec2(displacement_z, dhy_dx) * sign_shift;
	DATA_OUT(id, 2U) = vec2(dhy_dz, dhx_dx) * sign_shift;
	DATA_OUT(id, 3U) = vec2(dhz_dz, dhz_dx) * sign_shift;
}
