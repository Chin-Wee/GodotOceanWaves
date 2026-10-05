extends SceneTree
## Run with a RenderingDevice renderer (not --headless):
## godot --path . --script res://checks/sea_presets.gd

func _initialize() -> void:
	_run.call_deferred()

func _make_scene(initial_preset := 0) -> Node3D:
	var scene : Node3D = load('res://main.tscn').instantiate()
	scene.sea_preset = initial_preset
	scene.get_node('Water').map_size = 128
	scene.get_node('Water').mesh_quality = 0
	scene.get_node('Water').updates_per_second = 30.0
	scene.get_node('Water/WaterSprayEmitter').amount = 256
	root.add_child(scene)
	return scene

func _matches(actual : Variant, expected : Variant) -> bool:
	if expected is float: return is_equal_approx(actual, expected)
	if expected is Color or expected is Vector3: return actual.is_equal_approx(expected)
	return actual == expected

func _check_preset(scene : Node3D, index : int) -> bool:
	var preset : Dictionary = scene.SEA_PRESETS.PRESETS[index - 1]
	var water : MeshInstance3D = scene.get_node('Water')
	assert(water.parameters.size() == preset.cascades.size())
	for i in preset.cascades.size():
		for property in preset.cascades[i]:
			assert(water.parameters[i].get(property) == preset.cascades[i][property], property)
		assert(is_equal_approx(water.parameters[i]._wind_direction[0], deg_to_rad(water.parameters[i].wind_direction)))
		assert(water.parameters[i]._tile_length == [water.parameters[i].tile_length.x, water.parameters[i].tile_length.y])
	assert(water.water_color == preset.water_color)
	assert(water.foam_color == preset.foam_color)
	assert(scene._water_color == [preset.water_color.r, preset.water_color.g, preset.water_color.b])
	assert(scene._foam_color == [preset.foam_color.r, preset.foam_color.g, preset.foam_color.b])
	assert(scene._is_sea_spray_visible[0] == preset.spray_visible)
	assert(scene.get_node('Water/WaterSprayEmitter').visible == preset.spray_visible)
	for uniform in preset.material:
		assert(is_equal_approx(water.material_override.get_shader_parameter(uniform), preset.material[uniform]))
	for property in preset.environment:
		assert(_matches(scene.get_node('Environment').environment.get(property), preset.environment[property]), property)
	for property in preset.sun:
		if property == 'rotation_degrees':
			assert(scene.get_node('Sun').rotation_degrees.is_equal_approx(preset.sun[property]))
		else:
			assert(_matches(scene.get_node('Sun').get(property), preset.sun[property]), property)
	for property in preset.sky:
		assert(_matches(scene.get_node('Environment').environment.sky.sky_material.get(property), preset.sky[property]), property)
	assert(water.map_size == 128 and water.mesh_quality == 0 and water.updates_per_second == 30.0)
	assert(scene.get_node('Water/WaterSprayEmitter').amount == 256)
	assert(not scene.get_node('FogVolume').visible)
	return true

func _check_restoration(scene : Node3D) -> bool:
	# Restore after manual tweaks; the original snapshot must remain independent.
	scene.water.parameters[0].wind_speed = 100.0
	scene.water.water_color = Color.RED
	scene._apply_sea_preset(0)
	for i in scene._scene_preset.cascades.size():
		for property in scene.SEA_PRESETS.PRESETS[0].cascades[0]:
			assert(scene.water.parameters[i].get(property) == scene._scene_preset.cascades[i].get(property), property)
	assert(scene.water.water_color == scene._scene_preset.water_color)
	assert(scene.water.foam_color == scene._scene_preset.foam_color)
	assert(scene.get_node('Environment').environment.sky == scene._scene_preset.sky)
	for property in scene._scene_preset.environment:
		assert(_matches(scene.get_node('Environment').environment.get(property), scene._scene_preset.environment[property]), property)
	assert(scene.get_node('FogVolume').visible == scene._scene_preset.fog_volume_visible)
	scene._apply_sea_preset(-1)
	assert(scene.sea_preset == 0)
	for uniform in scene._scene_preset.material:
		assert(is_equal_approx(scene.water.material_override.get_shader_parameter(uniform), scene._scene_preset.material[uniform]))
	for property in scene._scene_preset.sun:
		assert(_matches(scene.get_node('Sun').get(property), scene._scene_preset.sun[property]), property)
	assert(scene.get_node('Water/WaterSprayEmitter').visible == scene._scene_preset.spray_visible)
	return true

func _run() -> void:
	var scene := _make_scene()
	for index in range(1, scene.SEA_PRESETS.PRESETS.size() + 1):
		scene._apply_sea_preset(index)
		if not _check_preset(scene, index):
			quit(1)
			return
		for frame in 12: await process_frame
		print('PASS: ', scene.SEA_PRESETS.PRESETS[index - 1].name)
	if not _check_restoration(scene):
		quit(1)
		return
	print('PASS: Scene Defaults restores original values after edits')
	scene.queue_free()
	for frame in 3: await process_frame

	scene = _make_scene(4)
	if not _check_preset(scene, 4):
		quit(1)
		return
	for frame in 12: await process_frame
	print('PASS: Inspector-selected startup preset')
	scene.queue_free()
	for frame in 3: await process_frame
	quit()
