#[compute]
#version 460
/** Compresses the existing 120-mode basis into 20 tensor-matched representatives. */

#define MODE_COUNT 20
#define SOURCE_MODE_COUNT 120
#define ANGULAR_SECTOR_COUNT 4
#define SOURCE_RADIAL_BAND_COUNT (SOURCE_MODE_COUNT / ANGULAR_SECTOR_COUNT)
#define RADIAL_GROUP_COUNT (MODE_COUNT / ANGULAR_SECTOR_COUNT)
#define RADIAL_GROUP_SIZE (SOURCE_RADIAL_BAND_COUNT / RADIAL_GROUP_COUNT)
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
shared uint selected_indices[SOURCE_MODE_COUNT];
shared float selected_scores[SOURCE_MODE_COUNT];
shared float selected_cell_energies[SOURCE_MODE_COUNT];

void main() {
	const uint lane = gl_LocalInvocationID.x;
	const ivec2 dims = imageSize(spectrum).xy;
	const uint map_size = uint(dims.x);
	const uint map_area = map_size * map_size;
	const uint record = cascade_index * uint(RECORD_SIZE);
	const vec2 dk = 2.0 * PI / tile_length;
	const float min_k = min(dk.x, dk.y);
	const float max_k = length(vec2(dims) * 0.5 * dk);
	const float log_k_range = log(max_k / min_k);

	// Reproduce the source 120-mode selector before compressing its measured output.
	for (int source_slot = 0; source_slot < SOURCE_MODE_COUNT; ++source_slot) {
		float best_score = -1.0;
		uint best_index = 0xFFFFFFFFU;
		float lane_energy = 0.0;
		int radial_band = source_slot / ANGULAR_SECTOR_COUNT;
		int angular_sector = source_slot % ANGULAR_SECTOR_COUNT;

		for (uint flat_index = lane; flat_index < map_area; flat_index += gl_WorkGroupSize.x) {
			ivec2 id = ivec2(int(flat_index % map_size), int(flat_index / map_size));
			ivec2 mirror = (dims - id) % dims;
			uint mirror_flat = uint(mirror.y) * map_size + uint(mirror.x);
			if (flat_index >= mirror_flat) continue;

			vec2 k_vec = (vec2(id) - vec2(dims) * 0.5) * dk;
			float k = length(k_vec);
			if (k < min_k * 0.5) continue;
			int mode_band = min(int(floor(log(k / min_k) / log_k_range * float(SOURCE_RADIAL_BAND_COUNT))), SOURCE_RADIAL_BAND_COUNT - 1);
			if (mode_band != radial_band) continue;

			vec4 h0 = imageLoad(spectrum, ivec3(id, int(cascade_index)));
			float score = 2.0 * (dot(h0.xy, h0.xy) + dot(h0.zw, h0.zw));
			float theta = atan(k_vec.x, k_vec.y);
			float wind_offset = 0.5 * atan(sin(2.0 * (theta - wind_angle)), cos(2.0 * (theta - wind_angle)));
			int mode_sector = clamp(int(floor((wind_offset + PI * 0.5) / (PI / float(ANGULAR_SECTOR_COUNT)))), 0, ANGULAR_SECTOR_COUNT - 1);
			if (mode_sector != angular_sector) continue;
			lane_energy += score;

			bool neighbor = false;
			for (int i = 0; i < source_slot; ++i) {
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
			selected_indices[source_slot] = candidate_indices[0];
			selected_scores[source_slot] = max(candidate_scores[0], 0.0);
			selected_cell_energies[source_slot] = cell_energy[0];
		}
		barrier();
	}

	if (lane == 0U) {
		float total_cell_energy = 0.0;
		for (int i = 0; i < SOURCE_MODE_COUNT; ++i) total_cell_energy += selected_cell_energies[i];

		for (int output_slot = 0; output_slot < MODE_COUNT; ++output_slot) {
			int radial_group = output_slot / ANGULAR_SECTOR_COUNT;
			int angular_sector = output_slot % ANGULAR_SECTOR_COUNT;
			float target_m0 = 0.0;
			float target_m2 = 0.0;
			vec3 target_directional_tensor = vec3(0.0);

			for (int subband = 0; subband < RADIAL_GROUP_SIZE; ++subband) {
				int source_band = radial_group * RADIAL_GROUP_SIZE + subband;
				int source_slot = source_band * ANGULAR_SECTOR_COUNT + angular_sector;
				uint selected = selected_indices[source_slot];
				float score = selected_scores[source_slot];
				float cell_energy_value = selected_cell_energies[source_slot];
				float fraction = cell_energy_value / max(total_cell_energy, 1e-20);
				if (selected == 0xFFFFFFFFU || score <= 1e-20 || fraction < MIN_CELL_ENERGY_FRACTION) continue;

				float source_scale = min(sqrt(cell_energy_value / score), MAX_CELL_AMPLIFICATION);
				float mode_energy = score * source_scale * source_scale;
				ivec2 wave_id = ivec2(int(selected % map_size), int(selected / map_size));
				vec2 k_vec = (vec2(wave_id) - float(map_size) * 0.5) * dk;
				float k_squared = dot(k_vec, k_vec);
				target_m0 += mode_energy;
				target_m2 += mode_energy * k_squared;
				target_directional_tensor += mode_energy * vec3(k_vec.x * k_vec.x, k_vec.x * k_vec.y, k_vec.y * k_vec.y);
			}

			float best_cost = 1e30;
			float best_radial_error = 1e30;
			float best_score = 0.0;
			uint best_index = 0xFFFFFFFFU;
			if (target_m0 > 1e-20 && target_m2 > 1e-20) {
				vec3 target_tensor_per_energy = target_directional_tensor / target_m0;
				float target_k_squared = target_m2 / target_m0;
				float cost_scale = max(target_k_squared * target_k_squared, 1e-20);

				for (int subband = 0; subband < RADIAL_GROUP_SIZE; ++subband) {
					int source_band = radial_group * RADIAL_GROUP_SIZE + subband;
					int source_slot = source_band * ANGULAR_SECTOR_COUNT + angular_sector;
					uint selected = selected_indices[source_slot];
					float score = selected_scores[source_slot];
					float cell_energy_value = selected_cell_energies[source_slot];
					float fraction = cell_energy_value / max(total_cell_energy, 1e-20);
					if (selected == 0xFFFFFFFFU || score <= 1e-20 || fraction < MIN_CELL_ENERGY_FRACTION) continue;

					ivec2 wave_id = ivec2(int(selected % map_size), int(selected / map_size));
					vec2 k_vec = (vec2(wave_id) - float(map_size) * 0.5) * dk;
					float k_squared = dot(k_vec, k_vec);
					vec3 candidate_tensor = vec3(k_vec.x * k_vec.x, k_vec.x * k_vec.y, k_vec.y * k_vec.y);
					vec3 tensor_error = candidate_tensor - target_tensor_per_energy;
					float cost = (tensor_error.x * tensor_error.x + 2.0 * tensor_error.y * tensor_error.y + tensor_error.z * tensor_error.z) / cost_scale;
					float radial_error = abs(k_squared - target_k_squared);
					if (cost < best_cost || (cost == best_cost && (radial_error < best_radial_error || (radial_error == best_radial_error && score > best_score)))) {
						best_cost = cost;
						best_radial_error = radial_error;
						best_score = score;
						best_index = selected;
					}
				}
			}

			uint output_offset = record + uint(output_slot) * 2U;
			if (best_index == 0xFFFFFFFFU || best_score <= 1e-20 || target_m0 <= 1e-20) {
				modes[output_offset] = 0xFFFFFFFFU;
				modes[output_offset + 1U] = floatBitsToUint(0.0);
				continue;
			}

			// Match the 120-mode group's M0 and k^2 directional tensor as closely as one
			// representative allows; the six independent phases and rank-2 spread are lost.
			float mode_scale = sqrt(target_m0 / best_score);
			modes[output_offset] = best_index;
			modes[output_offset + 1U] = floatBitsToUint(mode_scale);
		}
	}
}
