#[compute]
#version 460
/** Selects one spectrum representative per log k band and wind-relative sector. */

#define MODE_COUNT 120
#define ANGULAR_SECTOR_COUNT 4
#define RADIAL_BAND_COUNT (MODE_COUNT / ANGULAR_SECTOR_COUNT)
#define RECORD_SIZE (MODE_COUNT * 2)
#define PI (3.141592653589793)
#define MAX_CELL_AMPLIFICATION 128.0
#define MIN_CELL_ENERGY_FRACTION 1e-7

layout(local_size_x = 256) in;

layout(rgba32f, set = 0, binding = 0) restrict readonly uniform image2DArray spectrum;
layout(std430, set = 0, binding = 1) restrict buffer ModeBuffer { uint modes[]; };

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	vec2 tile_length;
	float wind_angle;
};

shared float candidate_scores[256];
shared uint candidate_indices[256];
shared float cell_energy[256];
shared uint selected_indices[MODE_COUNT];
shared float selected_scores[MODE_COUNT];
shared float selected_energies[MODE_COUNT];

void main() {
	const uint lane = gl_LocalInvocationID.x;
	const ivec2 dims = imageSize(spectrum).xy;
	const uint map_size = uint(dims.x);
	const uint map_area = map_size * map_size;
	const uint record = cascade_index * RECORD_SIZE;
	const vec2 dk = 2.0 * PI / tile_length;
	const float min_k = min(dk.x, dk.y);
	const float max_k = length(vec2(dims) * 0.5 * dk);
	const float log_k_range = log(max_k / min_k);

	for (int slot = 0; slot < MODE_COUNT; ++slot) {
		float best_score = -1.0;
		uint best_index = 0xFFFFFFFFU;
		float lane_energy = 0.0;
		int radial_band = slot / ANGULAR_SECTOR_COUNT;
		int angular_sector = slot % ANGULAR_SECTOR_COUNT;

		for (uint flat_index = lane; flat_index < map_area; flat_index += gl_WorkGroupSize.x) {
			ivec2 id = ivec2(int(flat_index % map_size), int(flat_index / map_size));
			ivec2 mirror = (dims - id) % dims;
			uint mirror_flat = uint(mirror.y) * map_size + uint(mirror.x);
			if (flat_index >= mirror_flat) continue;

			vec2 k_vec = (vec2(id) - vec2(dims) * 0.5) * dk;
			float k = length(k_vec);
			if (k < min_k * 0.5) continue;
			int mode_band = min(int(floor(log(k / min_k) / log_k_range * float(RADIAL_BAND_COUNT))), RADIAL_BAND_COUNT - 1);
			if (mode_band != radial_band) continue;

			vec4 h0 = imageLoad(spectrum, ivec3(id, int(cascade_index)));
			float score = 2.0 * (dot(h0.xy, h0.xy) + dot(h0.zw, h0.zw));
			float theta = atan(k_vec.x, k_vec.y);
			float wind_offset = 0.5 * atan(sin(2.0 * (theta - wind_angle)), cos(2.0 * (theta - wind_angle)));
			int mode_sector = clamp(int(floor((wind_offset + PI * 0.5) / (PI / float(ANGULAR_SECTOR_COUNT)))), 0, ANGULAR_SECTOR_COUNT - 1);
			if (mode_sector != angular_sector) continue;
			lane_energy += score;

			bool neighbor = false;
			for (int i = 0; i < slot; ++i) {
				uint selected = selected_indices[i];
				if (selected == 0xFFFFFFFFU) continue;
				ivec2 selected_id = ivec2(int(selected % map_size), int(selected / map_size));
				if (max(abs(id.x - selected_id.x), abs(id.y - selected_id.y)) <= 1) {
					neighbor = true;
					break;
				}
			}
			if (!neighbor && score > best_score) {
				best_score = score;
				best_index = flat_index;
			}
		}

		candidate_scores[lane] = best_score;
		candidate_indices[lane] = best_index;
		cell_energy[lane] = lane_energy;
		barrier();
		for (uint stride = gl_WorkGroupSize.x >> 1U; stride > 0U; stride >>= 1U) {
			if (lane < stride) {
				uint other = lane + stride;
				if (candidate_scores[other] > candidate_scores[lane]) {
					candidate_scores[lane] = candidate_scores[other];
					candidate_indices[lane] = candidate_indices[other];
				}
				cell_energy[lane] += cell_energy[other];
			}
			barrier();
		}

		if (lane == 0U) {
			selected_indices[slot] = candidate_indices[0];
			selected_scores[slot] = max(candidate_scores[0], 0.0);
			selected_energies[slot] = cell_energy[0];
		}
		barrier();
	}

	if (lane == 0U) {
		float total_energy = 0.0;
		for (int slot = 0; slot < MODE_COUNT; ++slot) total_energy += selected_energies[slot];
		for (int slot = 0; slot < MODE_COUNT; ++slot) {
			uint selected = selected_indices[slot];
			float energy = selected_energies[slot];
			float score = selected_scores[slot];
			float fraction = energy / max(total_energy, 1e-20);
			if (selected == 0xFFFFFFFFU || score <= 1e-20 || fraction < MIN_CELL_ENERGY_FRACTION) {
				modes[record + uint(slot) * 2U] = 0xFFFFFFFFU;
				modes[record + uint(slot) * 2U + 1U] = floatBitsToUint(0.0);
				continue;
			}
			float mode_scale = min(sqrt(energy / score), MAX_CELL_AMPLIFICATION);
			modes[record + uint(slot) * 2U] = selected;
			modes[record + uint(slot) * 2U + 1U] = floatBitsToUint(mode_scale);
		}
	}
}
