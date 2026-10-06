extends SceneTree
## Foam masks: inspected sea_spray.png alpha for fresh HF breakup; seamless FastNoiseLite noise for aged LF.

func _initialize() -> void:
	var water := FileAccess.get_file_as_string('res://assets/shaders/spatial/water.gdshader')
	var spray := FileAccess.get_file_as_string('res://assets/shaders/spatial/sea_spray_particle.gdshader')
	var material := load('res://assets/water/mat_water.tres') as ShaderMaterial
	assert(water.contains('global uniform sampler2DArray foam_states'))
	assert(water.contains('peak_mask = max(peak_mask, wave.a)'))
	assert(water.contains('foam_state.y / max(foam_state.x'))
	assert(water.contains('foam_hf_pattern') and water.contains('foam_lf_pattern'))
	assert(water.contains('sin(sun_radius)'))
	assert(spray.contains('texture(foam_states, vec3(START_POS.xz*map_scales[i].xy, float(i))).g'))
	assert(not spray.contains('gradient.z'))
	var hf_pattern := material.get_shader_parameter('foam_hf_pattern') as Texture2D
	var lf_pattern := material.get_shader_parameter('foam_lf_pattern') as NoiseTexture2D
	assert(hf_pattern.resource_path == 'res://assets/water/sea_spray.png')
	assert(lf_pattern != null and lf_pattern.seamless and lf_pattern.noise is FastNoiseLite)
	print('PASS: Sea of Thieves water shader consumes peak/fresh foam, authored breakup and area sun; spray uses fresh foam only')
	quit()
