#[compute]
#version 460
/** Selects one moment-matched spectrum representative per grouped log-k band and sector. */

#define MODE_COUNT 20
#define ANGULAR_SECTOR_COUNT 4
#define SOURCE_MODE_COUNT 120
#define SOURCE_RADIAL_BAND_COUNT (SOURCE_MODE_COUNT / ANGULAR_SECTOR_COUNT)
#define RADIAL_GROUP_SIZE 6
#define RADIAL_BAND_COUNT (SOURCE_RADIAL_BAND_COUNT / RADIAL_GROUP_SIZE)
#define RECORD_SIZE (MODE_COUNT * 2)
#define PI (3.141592653589793)

layout(local_size_x = 256) in;

layout(rgba32f, set = 0, binding = 0) restrict readonly uniform image2DArray spectrum;
layout(std430, set = 0, binding = 1) restrict buffer ModeBuffer { uint modes[]; };

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	vec2 tile_length;
	float wind_angle;
};

shared float candidate_scores[256];
shared float candidate_distances[256];
shared uint candidate_indices[256];
shared float cell_energy[256];
shared float cell_second_moment[256];
shared float effective_wavenumber;
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
		float lane_energy = 0.0;
		float lane_second_moment = 0.0;
		int radial_band = slot / ANGULAR_SECTOR_COUNT;
		int angular_sector = slot % ANGULAR_SECTOR_COUNT;

		// Accumulate M0=sum(E) and M2=sum(E*k^2) over six source bands.
		for (uint flat_index = lane; flat_index < map_area; flat_index += gl_WorkGroupSize.x) {
			ivec2 id = ivec2(int(flat_index % map_size), int(flat_index / map_size));
			ivec2 mirror = (dims - id) % dims;
			uint mirror_flat = uint(mirror.y) * map_size + uint(mirror.x);
			if (flat_index >= mirror_flat) continue;

			vec2 k_vec = (vec2(id) - vec2(dims) * 0.5) * dk;
			float k = length(k_vec);
			if (k < min_k * 0.5) continue;
			int source_band = min(int(floor(log(k / min_k) / log_k_range * float(SOURCE_RADIAL_BAND_COUNT))), SOURCE_RADIAL_BAND_COUNT - 1);
			if (source_band / RADIAL_GROUP_SIZE != radial_band) continue;

			vec4 h0 = imageLoad(spectrum, ivec3(id, int(cascade_index)));
			float score = 2.0 * (dot(h0.xy, h0.xy) + dot(h0.zw, h0.zw));
			float theta = atan(k_vec.x, k_vec.y);
			float wind_offset = 0.5 * atan(sin(2.0 * (theta - wind_angle)), cos(2.0 * (theta - wind_angle)));
			int mode_sector = clamp(int(floor((wind_offset + PI * 0.5) / (PI / float(ANGULAR_SECTOR_COUNT)))), 0, ANGULAR_SECTOR_COUNT - 1);
			if (mode_sector != angular_sector) continue;
			lane_energy += score;
			lane_second_moment += score * k * k;
		}

		cell_energy[lane] = lane_energy;
		cell_second_moment[lane] = lane_second_moment;
		barrier();
		for (uint stride = gl_WorkGroupSize.x >> 1U; stride > 0U; stride >>= 1U) {
			if (lane < stride) {
				uint other = lane + stride;
				cell_energy[lane] += cell_energy[other];
				cell_second_moment[lane] += cell_second_moment[other];
			}
			barrier();
		}

		if (lane == 0U) {
			effective_wavenumber = sqrt(cell_second_moment[0] / max(cell_energy[0], 1e-20));
		}
		barrier();

		// A single bin at k_eff with this M0 best matches energy and slope coarseness;
		// interference among the six merged bands' independent phases is necessarily lost.
		float best_distance = 1e30;
		float best_score = 0.0;
		uint best_index = 0xFFFFFFFFU;
		for (uint flat_index = lane; flat_index < map_area; flat_index += gl_WorkGroupSize.x) {
			ivec2 id = ivec2(int(flat_index % map_size), int(flat_index / map_size));
			ivec2 mirror = (dims - id) % dims;
			uint mirror_flat = uint(mirror.y) * map_size + uint(mirror.x);
			if (flat_index >= mirror_flat) continue;

			vec2 k_vec = (vec2(id) - vec2(dims) * 0.5) * dk;
			float k = length(k_vec);
			if (k < min_k * 0.5) continue;
			int source_band = min(int(floor(log(k / min_k) / log_k_range * float(SOURCE_RADIAL_BAND_COUNT))), SOURCE_RADIAL_BAND_COUNT - 1);
			if (source_band / RADIAL_GROUP_SIZE != radial_band) continue;

			float theta = atan(k_vec.x, k_vec.y);
			float wind_offset = 0.5 * atan(sin(2.0 * (theta - wind_angle)), cos(2.0 * (theta - wind_angle)));
			int mode_sector = clamp(int(floor((wind_offset + PI * 0.5) / (PI / float(ANGULAR_SECTOR_COUNT)))), 0, ANGULAR_SECTOR_COUNT - 1);
			if (mode_sector != angular_sector) continue;

			vec4 h0 = imageLoad(spectrum, ivec3(id, int(cascade_index)));
			float score = 2.0 * (dot(h0.xy, h0.xy) + dot(h0.zw, h0.zw));
			if (score <= 1e-20) continue;
			float distance = abs(k - effective_wavenumber);
			if (distance < best_distance || (distance == best_distance && score > best_score)) {
				best_distance = distance;
				best_score = score;
				best_index = flat_index;
			}
		}

		candidate_distances[lane] = best_distance;
		candidate_scores[lane] = best_score;
		candidate_indices[lane] = best_index;
		barrier();
		for (uint stride = gl_WorkGroupSize.x >> 1U; stride > 0U; stride >>= 1U) {
			if (lane < stride) {
				uint other = lane + stride;
				if (candidate_distances[other] < candidate_distances[lane] || (candidate_distances[other] == candidate_distances[lane] && candidate_scores[other] > candidate_scores[lane])) {
					candidate_distances[lane] = candidate_distances[other];
					candidate_scores[lane] = candidate_scores[other];
					candidate_indices[lane] = candidate_indices[other];
				}
			}
			barrier();
		}

		if (lane == 0U) {
			selected_indices[slot] = candidate_indices[0];
			selected_scores[slot] = candidate_scores[0];
			selected_energies[slot] = cell_energy[0];
		}
		barrier();
	}

	if (lane == 0U) {
		for (int slot = 0; slot < MODE_COUNT; ++slot) {
			uint selected = selected_indices[slot];
			float energy = selected_energies[slot];
			float score = selected_scores[slot];
			if (selected == 0xFFFFFFFFU || score <= 1e-20 || energy <= 1e-20) {
				modes[record + uint(slot) * 2U] = 0xFFFFFFFFU;
				modes[record + uint(slot) * 2U + 1U] = floatBitsToUint(0.0);
				continue;
			}
			float mode_scale = sqrt(energy / score);
			modes[record + uint(slot) * 2U] = selected;
			modes[record + uint(slot) * 2U + 1U] = floatBitsToUint(mode_scale);
		}
	}
}
