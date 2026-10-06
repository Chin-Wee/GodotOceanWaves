extends SceneTree

func _initialize() -> void:
	var water := FileAccess.get_file_as_string('res://assets/shaders/spatial/water.gdshader')
	var spray := FileAccess.get_file_as_string('res://assets/shaders/spatial/sea_spray_particle.gdshader')
	var material := FileAccess.get_file_as_string('res://assets/water/mat_water.tres')
	assert(water.contains('global uniform sampler2DArray foam_states'))
	assert(water.contains('peak_mask = max(peak_mask, wave.a)'))
	assert(water.contains('foam_state.y / max(foam_state.x'))
	assert(water.contains('sin(sun_radius)'))
	assert(spray.contains('texture(foam_states, vec3(START_POS.xz*map_scales[i].xy, float(i))).g'))
	assert(not spray.contains('gradient.z'))
	assert(material.contains('shader_parameter/foam_pattern = ExtResource("2_foam_pattern")'))
	print('PASS: Sea of Thieves water shader consumes peak/fresh foam, authored breakup and area sun; spray uses fresh foam only')
	quit()
