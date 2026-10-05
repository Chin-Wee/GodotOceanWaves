extends SceneTree
## Run with a RenderingDevice renderer (not --headless):
## godot --path . --script res://checks/sea_presets.gd

func _initialize() -> void:
	_run.call_deferred()

func _make_scene(initial_preset := 0) -> Node3D:
	var scene : Node3D = load('res://main.tscn').instantiate()
	if initial_preset >= 0: scene.sea_preset = initial_preset
	scene.get_node('Water').map_size = 128
	scene.get_node('Water').mesh_quality = 0
	scene.get_node('Water').updates_per_second = 30.0
	scene.get_node('Water/WaterSprayEmitter').amount = 256
	scene.get_node('Water/WaterSprayEmitter').process_material.set_shader_parameter('num_particles', 256)
	for audio in ['OceanAudioPlayer', 'WindAudioPlayer']: scene.get_node(audio).autoplay = false
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
		assert(water.parameters[i]._choppiness == [water.parameters[i].choppiness])
		assert(water.parameters[i]._foam_crest_bias == [water.parameters[i].foam_crest_bias])
	assert(water.water_color == preset.water_color)
	assert(water.foam_color == preset.foam_color)
	assert(scene._water_color == [preset.water_color.r, preset.water_color.g, preset.water_color.b])
	assert(scene._foam_color == [preset.foam_color.r, preset.foam_color.g, preset.foam_color.b])
	assert(scene._is_sea_spray_visible[0] == preset.spray_visible)
	assert(scene.get_node('Water/WaterSprayEmitter').visible == preset.spray_visible)
	for uniform in preset.material:
		assert(_matches(water.material_override.get_shader_parameter(uniform), preset.material[uniform]))
	for property in preset.environment:
		assert(_matches(scene.get_node('Environment').environment.get(property), preset.environment[property]), property)
	for property in preset.sun:
		if property == 'rotation_degrees':
			assert(scene.get_node('Sun').rotation_degrees.is_equal_approx(preset.sun[property]))
		else:
			assert(_matches(scene.get_node('Sun').get(property), preset.sun[property]), property)
	assert(scene.get_node('Environment').environment.sky.sky_material.panorama == preset.sky.sky_material.panorama)
	assert(scene.get_node('Environment').environment.sky.sky_material.energy_multiplier == preset.sky.sky_material.energy_multiplier)
	assert(preset.sky.sky_material is PanoramaSkyMaterial)
	assert(preset.sky.sky_material.panorama.get_width() == 4096)
	assert(is_equal_approx(scene.camera.position.y, preset.camera.height))
	assert(is_equal_approx(scene.camera.rotation.x, deg_to_rad(preset.camera.pitch_degrees)))
	assert(is_equal_approx(scene.camera.rotation.y, scene._scene_preset.camera.transform.basis.get_euler().y))
	assert(is_equal_approx(scene.camera.fov, preset.camera.fov))
	assert(scene._camera_fov[0] == scene.camera.fov)
	assert(water.map_size == 128 and water.mesh_quality == 0 and water.updates_per_second == 30.0)
	assert(scene.get_node('Water/WaterSprayEmitter').amount == 256)
	assert(not scene.get_node('FogVolume').visible)
	return true

func _check_restoration(scene : Node3D) -> bool:
	# Restore after manual tweaks; the original snapshot must remain independent.
	scene.water.parameters[0].wind_speed = 100.0
	scene.water.parameters[0].choppiness = 0.0
	scene.water.parameters[0].foam_crest_bias = 0.5
	scene.water.water_color = Color.RED
	scene.water.foam_color = Color.BLACK
	scene.camera.position = Vector3(40, 50, 60)
	scene.camera.rotation = Vector3.ZERO
	scene.camera.fov = 100.0
	for uniform in scene._scene_preset.material:
		scene.water.material_override.set_shader_parameter(uniform, Color.RED if scene._scene_preset.material[uniform] is Color else 0.9)
	scene.get_node('Environment').environment.sky.sky_material.energy_multiplier = 4.0
	scene.get_node('Environment').environment.fog_depth_end = 50.0
	scene.get_node('Sun').light_energy = 3.0
	scene.get_node('Sun').rotation = Vector3.ZERO
	scene.get_node('Water/WaterSprayEmitter').visible = false
	scene.get_node('FogVolume').visible = false
	scene._apply_sea_preset(0)
	for i in scene._scene_preset.cascades.size():
		for property in scene.SEA_PRESETS.PRESETS[0].cascades[0]:
			assert(scene.water.parameters[i].get(property) == scene._scene_preset.cascades[i].get(property), property)
	assert(scene.water.water_color == scene._scene_preset.water_color)
	assert(scene.water.foam_color == scene._scene_preset.foam_color)
	assert(scene.get_node('Environment').environment.sky.sky_material.panorama == scene._scene_preset.sky.sky_material.panorama)
	assert(scene.get_node('Environment').environment.sky.sky_material.energy_multiplier == scene._scene_preset.sky.sky_material.energy_multiplier)
	for property in scene._scene_preset.environment:
		assert(_matches(scene.get_node('Environment').environment.get(property), scene._scene_preset.environment[property]), property)
	assert(scene.get_node('FogVolume').visible == scene._scene_preset.fog_volume_visible)
	assert(scene.camera.transform.is_equal_approx(scene._scene_preset.camera.transform))
	assert(scene.camera.fov == scene._scene_preset.camera.fov)
	assert(scene._camera_fov[0] == scene.camera.fov)
	assert(scene._water_color == [scene.water.water_color.r, scene.water.water_color.g, scene.water.water_color.b])
	assert(scene._foam_color == [scene.water.foam_color.r, scene.water.foam_color.g, scene.water.foam_color.b])
	for invalid in [-1, 2]:
		scene._apply_sea_preset(invalid)
		assert(scene.sea_preset == 0)
	for uniform in scene._scene_preset.material:
		assert(_matches(scene.water.material_override.get_shader_parameter(uniform), scene._scene_preset.material[uniform]))
	for property in scene._scene_preset.sun:
		assert(_matches(scene.get_node('Sun').get(property), scene._scene_preset.sun[property]), property)
	assert(scene.get_node('Water/WaterSprayEmitter').visible == scene._scene_preset.spray_visible)
	return true

func _run() -> void:
	var scene := _make_scene()
	var seeds : Array = []
	for params in scene.water.parameters: seeds.append(params.spectrum_seed)
	for repetition in 3:
		scene._apply_sea_preset(1)
		assert(_check_preset(scene, 1))
		for i in seeds.size():
			assert(scene.water.parameters[i].spectrum_seed == seeds[i])
			assert(is_equal_approx(scene.water.parameters[i].time, 120.0 + PI*i))
		assert(scene.water.time == 0.0 and scene.water.next_update_time == 0.0)
		for frame in 12: await process_frame
		assert(_check_restoration(scene))
		for i in seeds.size(): assert(scene.water.parameters[i].spectrum_seed == seeds[i])
		for frame in 12: await process_frame
	print('PASS: repeated Daylight switching, seeded waves, colors, camera and full restoration; invalid selections ignored')
	scene.queue_free()
	for frame in 3: await process_frame
	scene = _make_scene(-1)
	assert(_check_preset(scene, 1))
	for frame in 12: await process_frame
	print('PASS: Daylight startup; original FFT/mesh/cadence/particle settings preserved')
	var generator : WaveGenerator = scene.water.wave_generator
	var seeds_before : Array = []
	for params in scene.water.parameters: seeds_before.append(params.spectrum_seed)
	var time_before : float = scene.water.time
	var wave_time_before : float = scene.water.parameters[0].time
	scene.camera.enable_camera_movement = true
	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.keycode = KEY_W
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var position_before : Vector3 = scene.camera.position
	scene.camera._process(0.1)
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert(not scene.camera.position.is_equal_approx(position_before), 'Freecam WASD must remain active')
	scene.camera.position += Vector3(180, 40, -90)
	scene.camera.rotation += Vector3(-0.3, 0.5, 0)
	for frame in 12: await process_frame
	assert(scene.water.wave_generator == generator, 'Moving freecam must not recreate the wave field')
	assert(scene.water.time > time_before and scene.water.parameters[0].time > wave_time_before)
	for i in seeds_before.size(): assert(scene.water.parameters[i].spectrum_seed == seeds_before[i])
	var code : String = scene.water.material_override.shader.code
	assert(not code.contains('CAMERA_POSITION_WORLD') and not code.contains('length(VERTEX.xz)'))
	assert(code.contains('VERTEX += displacement;') and code.contains('gradient *= normal_strength;'))
	print('PASS: freecam movement; animated world-anchored waves retain generator and seeds')
	scene.queue_free()
	for frame in 3: await process_frame
	quit()
