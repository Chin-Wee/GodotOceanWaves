extends RefCounted
## Sea of Thieves' production approach: original FFT geometry with art-directed crest light and foam.
## Colors are authored in sRGB, like the Water node's color controls.

const PRESETS := [
	{
		'name': 'Daylight Ocean',
		'description': 'Blue troughs, cyan crests and sparse whitecaps.',
		'water_color': Color('#06495F'),
		'foam_color': Color('#E9EFE5'),
		'material': {
			'roughness': 0.25, 'reflection_roughness': 0.20, 'normal_strength': 1.0,
			'trough_light_strength': 0.4, 'crest_color': Color('#38BAC2'), 'crest_scattering_strength': 0.65,
		},
		'spray_visible': true,
		'fog_volume_visible': false,
		'camera': {'height': 2.5, 'pitch_degrees': -12.0, 'fov': 75.0},
		'environment': {
			'fog_enabled': true, 'fog_mode': Environment.FOG_MODE_DEPTH, 'volumetric_fog_enabled': false,
			'fog_light_color': Color('#A6D4DD'), 'fog_sun_scatter': 0.05,
			'fog_depth_begin': 200.0, 'fog_depth_end': 800.0, 'fog_depth_curve': 1.0,
			'fog_aerial_perspective': 0.2, 'fog_sky_affect': 0.0,
			'adjustment_enabled': true, 'adjustment_brightness': 1.0,
			'adjustment_contrast': 1.05, 'adjustment_saturation': 1.1,
		},
		'sun': {
			# Panorama sun core: u=0.6045, v=0.2367 in Godot's equirectangular mapping.
			'rotation_degrees': Vector3(-47.4, -37.6, 0),
			'light_color': Color('#FFF9EB'), 'light_energy': 1.0,
			'sky_mode': DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY,
		},
		'sky': preload('res://assets/daylight_sky.tres'),
		'cascades': [
			{'tile_length': Vector2(88, 88), 'displacement_scale': 1.0, 'choppiness': 1.25, 'normal_scale': 1.0,
			 'wind_speed': 10.0, 'wind_direction': 20.0, 'fetch_length': 150.0,
			 'swell': 0.8, 'spread': 0.2, 'detail': 1.0, 'whitecap': 0.35, 'foam_amount': 5.0, 'foam_crest_bias': 1.0},
			{'tile_length': Vector2(57, 57), 'displacement_scale': 0.75, 'choppiness': 1.15, 'normal_scale': 1.0,
			 'wind_speed': 5.0, 'wind_direction': 15.0, 'fetch_length': 150.0,
			 'swell': 0.8, 'spread': 0.4, 'detail': 1.0, 'whitecap': 0.5, 'foam_amount': 0.0, 'foam_crest_bias': 0.0},
			{'tile_length': Vector2(16, 16), 'displacement_scale': 0.0, 'choppiness': 1.0, 'normal_scale': 0.25,
			 'wind_speed': 20.0, 'wind_direction': 20.0, 'fetch_length': 550.0,
			 'swell': 0.8, 'spread': 0.4, 'detail': 1.0, 'whitecap': 0.25, 'foam_amount': 0.0, 'foam_crest_bias': 0.0},
		],
	},
]
