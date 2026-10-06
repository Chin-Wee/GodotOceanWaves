shader_type canvas_item;

uniform sampler2D contact_mask : repeat_disable, filter_linear;
uniform sampler2D previous_history : repeat_disable, filter_linear;
uniform vec2 current_center;
uniform vec2 previous_center;
uniform vec2 current_velocity = vec2(0.35, 0.0);
uniform float extent = 256.0;
uniform float delta = 0.016;
uniform float half_life = 8.0;
uniform float blur_pixels = 1.25;
uniform bool history_valid = false;

void fragment() {
	float current_contact = texture(contact_mask, UV).r;
	float inherited = 0.0;
	if (history_valid) {
		vec2 world_xz = current_center + (UV - 0.5) * (extent * 2.0) - current_velocity * delta;
		vec2 old_uv = (world_xz - previous_center) / (extent * 2.0) + 0.5;
		if (all(greaterThanEqual(old_uv, vec2(0.0))) && all(lessThanEqual(old_uv, vec2(1.0)))) {
			vec2 texel = blur_pixels / vec2(textureSize(previous_history, 0));
			// ponytail: five-tap cross blur is cheap but anisotropic; widen the kernel if artifacts matter.
			float blurred = texture(previous_history, old_uv).r * 0.4;
			blurred += texture(previous_history, old_uv + vec2(texel.x, 0.0)).r * 0.15;
			blurred += texture(previous_history, old_uv - vec2(texel.x, 0.0)).r * 0.15;
			blurred += texture(previous_history, old_uv + vec2(0.0, texel.y)).r * 0.15;
			blurred += texture(previous_history, old_uv - vec2(0.0, texel.y)).r * 0.15;
			inherited = blurred * exp(-0.69314718 * delta / max(half_life, 0.001));
		}
	}
	float foam = max(current_contact, inherited);
	COLOR = vec4(vec3(foam), 1.0);
}
