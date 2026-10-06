shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D sky_texture : repeat_disable, filter_nearest;
uniform float waterline = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 color = texture(scene_color, SCREEN_UV).rgb;
	float depth = texture(scene_depth, SCREEN_UV).r;
	bool has_geometry = false;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	has_geometry = depth < 0.99999;
	ndc.z = depth * 2.0 - 1.0;
	#else
	has_geometry = depth > 0.00001;
	#endif
	if (has_geometry) {
		vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		if (world.y / world.w < waterline) {
			color = texture(sky_texture, SCREEN_UV).rgb;
		}
	}
	ALBEDO = color;
	ALPHA = 1.0;
}
