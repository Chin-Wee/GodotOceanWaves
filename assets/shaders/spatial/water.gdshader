shader_type spatial;
render_mode world_vertex_coords, shadows_disabled;
/**
 * Sea of Thieves (Rare, SIGGRAPH '18): choppiness peak scattering, artist-authored foam,
 * and a closest-point-on-sphere sun highlight. Fresh-to-aged HF/LF switching follows the parity sheet.
 * Source: https://history.siggraph.org/wp-content/uploads/2022/09/2018-Talks-Ang_The-Technical-Art-of-Sea-of-Thieves.pdf
 */

#define MAX_CASCADES 8    // I am unsure how to generalize this.
#define REFLECTANCE  0.02 // Reflectance from air to water (eta=1.33).

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;

uniform float roughness : hint_range(0.0, 1.0) = 0.4; // Direct sun highlights.
uniform float reflection_roughness : hint_range(0.0, 1.0) = 0.4; // Sky reflections.
uniform vec4 crest_color : source_color = vec4(0.219608, 0.729412, 0.760784, 1.0);
uniform float crest_scattering_strength : hint_range(0.0, 2.0) = 0.0;
uniform float trough_light_strength : hint_range(0.0, 1.0) = 1.0; // Art-directed trough occlusion.
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0; // Global normal strength
uniform sampler2D foam_hf_pattern : source_color, repeat_enable;
uniform sampler2D foam_lf_pattern : repeat_enable;
uniform float foam_hf_scale : hint_range(0.01, 1.0) = 0.28;
uniform float foam_lf_scale : hint_range(0.001, 0.1) = 0.02;
uniform float sun_angular_radius : hint_range(0.0, 0.2) = 0.04;

group_uniforms cascade_data;
uniform vec4 map_scales[MAX_CASCADES];               // Scales for displacement/normal maps. Packed: [uv scale, displacement scale, normal scale]
global uniform uint num_cascades;
global uniform sampler2DArray displacements;         // Each layer represents one wave cascade.
global uniform sampler2DArray normals : hint_normal; // Each layer represents one wave cascade.
global uniform sampler2DArray foam_states;            // R=total persistent foam, G=fresh breaking injection.

varying float wave_height;
varying float foam_factor;
varying float fresnel;
varying float trough_visibility;
varying float peak_mask;

void vertex() {
	UV = VERTEX.xz;

	// Read displacements from displacement maps.
	vec3 displacement = vec3(0);
	peak_mask = 0.0;
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		vec4 wave = texture(displacements, vec3(UV*scales.xy, float(i)));
		displacement += wave.xyz * scales.z;
		peak_mask = max(peak_mask, wave.a);
	}
	VERTEX += displacement; // Keep world-space wave height independent of freecam position.
	wave_height = displacement.y;
}

/** Filter weights for a cubic B-spline. */
vec4 cubic_weights(float a) {
	float a2 = a*a;
	float a3 = a2*a;
	
	float w0 =-a3     + a2*3.0 - a*3.0 + 1.0;
	float w1 = a3*3.0 - a2*6.0         + 4.0;
	float w2 =-a3*3.0 + a2*3.0 + a*3.0 + 1.0;
	float w3 = a3;
	return vec4(w0, w1, w2, w3) / 6.0;
}

/** Performs bicubic B-spline filtering on the provided sampler. */
// Source: https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-20-fast-third-order-texture-filtering
vec4 texture_bicubic(in sampler2DArray sampler, in vec3 uvw) {
	vec2 dims = vec2(textureSize(sampler, 0).xy);
	vec2 dims_inv = 1.0 / dims;
	uvw.xy = uvw.xy*dims + 0.5;
	
	vec2 fuv = fract(uvw.xy);
	vec4 wx = cubic_weights(fuv.x);
	vec4 wy = cubic_weights(fuv.y);

	vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy)*dims_inv.xxyy;
	vec2 w = g.xz / (g.xz + g.yw);
    return mix(
		mix(texture(sampler, vec3(h.yw, uvw.z)), texture(sampler, vec3(h.xw, uvw.z)), w.x),
		mix(texture(sampler, vec3(h.yz, uvw.z)), texture(sampler, vec3(h.xz, uvw.z)), w.x), w.y); 
}

void fragment() {
	float map_size = float(textureSize(normals, 0).x);
	// Read the filtered surface gradient and persistent/fresh foam states.
	vec3 gradient = vec3(0);
	vec2 foam_state = vec2(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		vec3 coords = vec3(UV*scales.xy, float(i));
		float ppm = map_size * min(scales.x, scales.y); // Pixels per meter
		// Mix between bicubic and bilinear filtering depending on the world space pixels per meter.
		// This is dependent on the tile size as well as displacement/normal map resolution.
		gradient += mix(texture_bicubic(normals, coords), texture(normals, coords), min(1.0, ppm*0.1)).xyw * vec3(scales.ww, 1.0);
		vec2 state = texture(foam_states, coords).rg;
		foam_state = max(foam_state, state);
	}
	float freshness = clamp(foam_state.y / max(foam_state.x, 1e-4), 0.0, 1.0);
	float foam_hf = texture(foam_hf_pattern, UV*foam_hf_scale).a;
	float foam_lf = smoothstep(0.2, 0.8, texture(foam_lf_pattern, UV*foam_lf_scale).r);
	// The parity sheet's age model keeps fresh foam detailed and lets aged foam broaden.
	float breakup = mix(foam_lf, foam_hf, smoothstep(0.05, 0.85, freshness));
	foam_factor = smoothstep(0.05, 0.95, foam_state.x * mix(0.5, 1.0, breakup));
	ALBEDO = max(mix(water_color.rgb, foam_color.rgb, foam_factor), vec3(1e-4));

	gradient *= normal_strength;
	NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;

	float sun_roughness = mix(clamp(roughness, 0.02, 1.0), 0.85, foam_factor);
	float dot_nv = clamp(dot(VIEW, NORMAL), 0.0, 1.0);
	fresnel = mix(pow(1.0 - dot_nv, 5.0*exp(-2.69*sun_roughness)) / (1.0 + 22.7*pow(sun_roughness, 1.5)), 1.0, REFLECTANCE);
	ROUGHNESS = mix(clamp(reflection_roughness, 0.02, 1.0), 0.85, foam_factor);
	trough_visibility = mix(clamp(trough_light_strength, 0.0, 1.0), 1.0, smoothstep(-1.5, 0.75, wave_height));
	AO = trough_visibility; // Native ambient occlusion; the cyan transmitted light remains independent.
}

float smith_masking_shadowing(in float cos_theta, in float alpha) {
	float a = cos_theta / (alpha * sqrt(max(1.0 - cos_theta*cos_theta, 1e-8))); // Approximate: 1.0 / (alpha * tan(acos(cos_theta)))
	float a_sq = a*a;
	return a < 1.6 ? (1.0 - 1.259*a + 0.396*a_sq) / (3.535*a + 2.181*a_sq) : 0.0;
}

// Source: https://github.com/godotengine/godot/blob/7b56111c297f24304eb911fe75082d8cdc3d4141/drivers/gles3/shaders/scene.glsl#L995
float ggx_distribution(in float cos_theta, in float alpha) {
	float a_sq = alpha*alpha;
	float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
	return a_sq / (PI * d*d);
}

void light() {
	vec3 sun_direction = normalize(LIGHT);
	vec3 reflection_direction = normalize(reflect(-VIEW, NORMAL));
	float sun_cos_angle = clamp(dot(sun_direction, reflection_direction), -1.0, 1.0);
	float sun_radius = clamp(sun_angular_radius, 0.0, 0.2);
	vec3 sun_tangent = reflection_direction - sun_direction*sun_cos_angle;
	vec3 area_sun = reflection_direction;
	// Closest direction on the sun's angular sphere to the ideal specular reflection.
	if (sun_cos_angle < cos(sun_radius) && length(sun_tangent) > 1e-5) {
		area_sun = normalize(sun_direction*cos(sun_radius) + normalize(sun_tangent)*sin(sun_radius));
	}
	vec3 halfway = (area_sun + VIEW) / max(length(area_sun + VIEW), 1e-4);
	float dot_nl = clamp(dot(NORMAL, LIGHT), 2e-5, 1.0);
	float area_dot_nl = clamp(dot(NORMAL, area_sun), 2e-5, 1.0);
	float dot_nv = clamp(dot(NORMAL, VIEW), 2e-5, 1.0);
	float sun_roughness = mix(clamp(roughness, 0.02, 1.0), 0.85, foam_factor);

	// --- SPECULAR ---
	float alpha = max(sun_roughness*sun_roughness, 0.002); // Perceptual roughness to GGX width, as in Godot's built-in model.
	float light_mask = smith_masking_shadowing(dot_nl, alpha);
	float area_light_mask = smith_masking_shadowing(area_dot_nl, alpha);
	float view_mask = smith_masking_shadowing(dot_nv, alpha);
	float microfacet_distribution = ggx_distribution(clamp(dot(NORMAL, halfway), 0.0, 1.0), alpha);
	float sun_fresnel = mix(REFLECTANCE, 1.0, pow(1.0 - clamp(dot(VIEW, halfway), 0.0, 1.0), 5.0));
	float geometric_attenuation = 1.0 / (1.0 + area_light_mask + view_mask);
	SPECULAR_LIGHT += sun_fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1) * ATTENUATION * LIGHT_COLOR;

	// --- DIFFUSE ---
	const vec3 sss_modifier = vec3(0.9,1.15,0.85); // Subsurface scattering produces a 'greener' color.
	float sun_scatter = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 4.0) * pow(clamp(0.5 - 0.5 * dot(LIGHT, NORMAL), 0.0, 1.0), 3.0);
	float sss_near = 0.5*pow(dot_nv, 2.0);
	float lambertian = 0.5*dot_nl;
	// Sea of Thieves: the normalized FFT choppiness mask drives peak transmission.
	float crest_scatter = peak_mask * sqrt(1.0 - dot_nv) * sqrt(sun_scatter) * crest_scattering_strength;
	// Godot multiplies DIFFUSE_LIGHT by ALBEDO; cancel it here to keep cyan independent of the deep tint.
	DIFFUSE_LIGHT += crest_color.rgb / max(ALBEDO, vec3(1e-4)) * crest_scatter * (1.0 - foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
	// Foam color is already in ALBEDO. LIGHT_COLOR includes PI; use Lambertian diffuse for foam.
	float sss_peak = peak_mask * sun_scatter * crest_scattering_strength;
	DIFFUSE_LIGHT += mix((sss_peak + sss_near) * sss_modifier / (1.0 + light_mask) + lambertian, vec3(dot_nl / PI), foam_factor) * trough_visibility * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}
