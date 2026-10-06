#[compute]
#version 460
/**
 * Sea of Thieves by Rare uses feedback blur to disperse older foam.
 * R stores persistent foam; G stores the decaying fresh Jacobian injection.
 */

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rg16f, set = 0, binding = 0) restrict readonly uniform image2DArray foam_previous;
layout(r16f, set = 0, binding = 1) restrict readonly uniform image2DArray breaking_map;
layout(rg16f, set = 0, binding = 2) restrict writeonly uniform image2DArray foam_next;

layout(push_constant) restrict readonly uniform PushConstants {
	uint active_cascade;
	float delta;
	float growth_rate;
	float decay_rate;
	float dispersion_rate;
};

ivec2 wrap_pixel(ivec2 pixel, ivec2 size) {
	return (pixel + size) % size;
}

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 size = imageSize(foam_previous);
	if (any(greaterThanEqual(id, size))) return;
	if (uint(id.z) != active_cascade) {
		imageStore(foam_next, id, imageLoad(foam_previous, id));
		return;
	}

	const float kernel[3] = float[](0.25, 0.5, 0.25);
	float blurred_total = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 pixel = wrap_pixel(id.xy + ivec2(x, y), size.xy);
			blurred_total += imageLoad(foam_previous, ivec3(pixel, id.z)).r * kernel[x + 1] * kernel[y + 1];
		}
	}

	float center_total = imageLoad(foam_previous, id).r;
	float dispersion = 1.0 - exp(-max(dispersion_rate, 0.0) * delta);
	float decayed_total = mix(center_total, blurred_total, dispersion) * exp(-max(decay_rate, 0.0) * delta);
	float breaking = imageLoad(breaking_map, id).r;
	float fresh_injection = clamp(breaking * max(growth_rate, 0.0) * delta, 0.0, 1.0);
	float total = clamp(decayed_total + fresh_injection, 0.0, 1.0);

	// ponytail: fresh fades at 4x total decay (minimum 1/s); split this out per sea state if art needs it.
	float fresh_decay = exp(-max(decay_rate * 4.0, 1.0) * delta);
	float fresh = max(fresh_injection, imageLoad(foam_previous, id).g * fresh_decay);
	imageStore(foam_next, id, vec4(total, fresh, 0.0, 1.0));
}
