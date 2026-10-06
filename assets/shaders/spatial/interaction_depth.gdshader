shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float waterline = 0.0;
uniform float intersection_width = 0.45;
uniform float submerged_interaction_depth = 3.0;
uniform bool capture_submerged = false;

float interaction_at_height(float height) {
	if (capture_submerged) {
		float depth_below_water = waterline - height;
		if (depth_below_water > 0.0) {
			return 1.0 - smoothstep(0.0, submerged_interaction_depth, depth_below_water);
		}
		return 0.0;
	}
	return 1.0 - smoothstep(0.0, intersection_width, abs(height - waterline));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
	float contact = 0.0;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	if (depth < 0.99999) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
		vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float height = world.y / world.w;
		contact = interaction_at_height(height);
	}
	#else
	if (depth > 0.00001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float height = world.y / world.w;
		contact = interaction_at_height(height);
	}
	#endif
	ALBEDO = vec3(contact);
	ALPHA = 1.0;
}
