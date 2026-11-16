extends SceneTree
## Run with a RenderingDevice renderer, not --headless.

func _initialize() -> void:
	_run.call_deferred()

func _matches(actual: Variant, expected: Variant) -> bool:
	if expected is float: return is_equal_approx(actual, expected)
	if expected is Color or expected is Vector2 or expected is Vector3: return actual.is_equal_approx(expected)
	return actual == expected

func _check_daylight(scene: Node3D) -> void:
	var preset: Dictionary = scene.SEA_PRESETS.DAYLIGHT_OCEAN
	var states: Array = scene.SEA_PRESETS.SEA_STATES
	var state: Dictionary = states[scene.sea_state]
	var normal: Dictionary = states[1]
	var water: MeshInstance3D = scene.get_node('Water')
	var camera: Camera3D = scene.get_node('Camera')
	var environment: Environment = scene.get_node('Environment').environment
	var sun: DirectionalLight3D = scene.get_node('Sun')
	assert(preset.name == 'Daylight Ocean')
	assert(water.parameters.size() == preset.cascades.size())
	for i in preset.cascades.size():
		for property in preset.cascades[i]:
			var expected: Variant = preset.cascades[i][property]
			match property:
				'displacement_scale': expected *= state.wave_amplitude_scale
				'choppiness': expected *= state.choppiness_scale
				'foam_amount': expected *= state.foam_amount / normal.foam_amount
				'whitecap': expected = clampf(expected + state.whitecap - normal.whitecap, 0.0, 2.0)
				'foam_decay': expected = state.foam_decay
				'foam_dispersion': expected = state.foam_dispersion
			assert(_matches(water.parameters[i].get(property), expected), property)
		assert(water.parameters[i]._tile_length == [water.parameters[i].tile_length.x, water.parameters[i].tile_length.y])
		assert(water.parameters[i]._choppiness == [water.parameters[i].choppiness])
	assert(water.water_color == preset.water_color and water.foam_color == preset.foam_color)
	assert(water.scale.is_equal_approx(Vector3(0.052, 1.0, 0.052)))
	for uniform in preset.material:
		assert(_matches(water.material_override.get_shader_parameter(uniform), preset.material[uniform]), uniform)
	for property in preset.environment:
		assert(_matches(environment.get(property), preset.environment[property]), property)
	for property in preset.sun:
		if property == 'rotation_degrees':
			assert(sun.rotation_degrees.is_equal_approx(preset.sun[property]))
		else:
			assert(_matches(sun.get(property), preset.sun[property]), property)
	assert(environment.sky.sky_material.panorama == preset.sky.sky_material.panorama)
	assert(scene.get_node('Water/WaterSprayEmitter').visible == preset.spray_visible)
	if not scene.is_inside_tree():
		assert(scene.get_node('Water/WaterSprayEmitter').scale.is_equal_approx(Vector3(15, 15, 15)))
	assert(not scene.get_node('FogVolume').visible)
	assert(is_equal_approx(camera.position.y, preset.camera.height))
	assert(is_equal_approx(camera.rotation.x, deg_to_rad(preset.camera.pitch_degrees)))
	assert(is_equal_approx(camera.fov, preset.camera.fov))
	if scene.sea_state == 2:
		assert(is_equal_approx(water.parameters[0].displacement_scale, 0.844))
		assert(is_equal_approx(water.parameters[0].choppiness, 0.927))
		assert(is_equal_approx(water.parameters[0].foam_amount, 8.0))
		assert(is_equal_approx(water.parameters[0].whitecap, 0.65))

func _run() -> void:
	var scene: Node3D = load('res://main.tscn').instantiate()
	for audio in ['OceanAudioPlayer', 'WindAudioPlayer']: scene.get_node(audio).autoplay = false
	scene.get_node('Water').map_size = 128
	scene.get_node('Water').mesh_quality = 0
	scene.get_node('Water').updates_per_second = 30.0
	scene.get_node('Water/WaterSprayEmitter').amount = 256
	scene.get_node('Water/WaterSprayEmitter').process_material.set_shader_parameter('num_particles', 256)
	_check_daylight(scene) # The saved scene itself must already be Daylight Ocean + Storm.
	root.add_child(scene)
	assert(scene.sea_state == 2, 'Daylight Ocean should start in Storm state')
	_check_daylight(scene)
	var spray: GPUParticles3D = scene.get_node('Water/WaterSprayEmitter')
	assert(is_equal_approx(spray.scale.x * scene.water.scale.x, 15.0) and is_equal_approx(spray.scale.z * scene.water.scale.z, 15.0), 'Clipmap scaling must preserve the spray footprint')
	var generator: WaveGenerator = scene.water.wave_generator
	for state_index in scene.SEA_PRESETS.SEA_STATES.size():
		scene._apply_sea_state(state_index)
		_check_daylight(scene)
	assert(scene.water.wave_generator == generator, 'Changing sea state must retain the wave generator')
	scene._apply_sea_state(2)
	_check_daylight(scene)
	print('PASS: Daylight Ocean is the sole preset, editor/runtime startup uses it, Storm is default, sea-state controls remain stable')
	scene.queue_free()
	for frame in 3: await process_frame
	quit()
