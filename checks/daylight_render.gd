extends SceneTree
## Full-quality, matched-camera A/B timings. Add -- --capture for fixed-time PNG comparisons.
## Run without --headless, with --disable-vsync, and no other GPU workload.

var output := 'user://daylight-validation/' + RenderingServer.get_current_rendering_method() + '-' + RenderingServer.get_current_rendering_driver_name()

func _initialize() -> void:
	_run.call_deferred()

func _save(name : String) -> Image:
	for frame in 8: await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	assert(image.get_size() == Vector2i(1920, 1080), str(image.get_size()))
	assert(image.save_png(output.path_join(name + '.png')) == OK)
	print('CAPTURE: ', name)
	return image

func _check_freecam_look(scene : Node3D, reference : Image) -> void:
	var camera : Camera3D = scene.camera
	var transform := camera.transform
	var samples : Array = []
	for y in range(650, 1000, 30):
		for x in range(100, 1820, 30):
			var pixel := Vector2i(x, y)
			samples.append([pixel, camera.project_position(pixel, 100.0)])
	camera.rotation += Vector3(deg_to_rad(-6), deg_to_rad(7), 0)
	var changed : Image = await _save('daylight-foam-freecam-look')
	var error := 0.0
	var count := 0
	for sample in samples:
		var projected := Vector2i(camera.unproject_position(sample[1]).round())
		if not Rect2i(Vector2i.ZERO, changed.get_size()).has_point(projected): continue
		error += absf(reference.get_pixelv(sample[0]).r - changed.get_pixelv(projected).r)
		count += 1
	assert(count > 400)
	assert(error/count < 0.025, 'Looking around must retain foam on the same world-space crests')
	camera.transform = transform
	print('PASS: freecam look reprojection, foam mean pixel error ', error/count)

func _capture(scene : Node3D, matching_camera : Transform3D) -> void:
	var water : MeshInstance3D = scene.water
	water.set_process(false)
	for index in [0, 1]:
		scene._apply_sea_preset(index)
		scene.camera.transform = matching_camera
		water.wave_generator.set_process(false)
		var spray : GPUParticles3D = scene.get_node('Water/WaterSprayEmitter')
		spray.use_fixed_seed = true
		spray.seed = 1234
		spray.restart()
		for step in 480:
			# Exact 60 Hz simulation, completing all three cascades before the next frame.
			water._update_water(1.0/60.0)
			for cascade in 3: water.wave_generator._process(0.0)
			await process_frame
			if step + 1 in [240, 360, 480]:
				var prefix := 'original' if index == 0 else 'daylight'
				await _save(prefix + '-' + str((step + 1)/60))
				# Diagnostic only: display existing foam alpha without lighting or grading.
				var shader : Shader = water.material_override.shader
				var mask_shader := Shader.new()
				mask_shader.code = shader.code.replace('world_vertex_coords, shadows_disabled', 'world_vertex_coords, unshaded, fog_disabled').replace('ALBEDO = max(mix(water_color.rgb, foam_color.rgb, foam_factor), vec3(1e-4));', 'ALBEDO = vec3(foam_factor);')
				water.material_override.shader = mask_shader
				var grading : bool = scene.get_node('Environment').environment.adjustment_enabled
				scene.get_node('Environment').environment.adjustment_enabled = false
				spray.visible = false
				var mask : Image = await _save(prefix + '-foam-' + str((step + 1)/60))
				if index == 1 and step + 1 == 240: await _check_freecam_look(scene, mask)
				water.material_override.shader = shader
				scene.get_node('Environment').environment.adjustment_enabled = grading
				spray.visible = true
		if index == 1:
			scene.set_process(false)
			spray.visible = false # Isolate frozen water lighting from TIME-driven spray variation.
			var lit_image : Image = await _save('daylight-light-control')
			water.material_override.set_shader_parameter('crest_scattering_strength', 0.0)
			var no_crest : Image = await _save('daylight-no-crest')
			assert(lit_image.get_data() != no_crest.get_data(), 'Crest scattering must change the render')
			water.material_override.set_shader_parameter('crest_scattering_strength', 0.65)
			water.material_override.set_shader_parameter('roughness', 0.0)
			water.material_override.set_shader_parameter('reflection_roughness', 0.0)
			scene.camera.rotation.x = deg_to_rad(-1.0)
			await _save('daylight-grazing-min-roughness')
			scene.camera.transform = matching_camera
			water.material_override.set_shader_parameter('roughness', 0.25)
			water.material_override.set_shader_parameter('reflection_roughness', 0.20)
			scene.get_node('Sun').light_energy = 0.0
			var no_sun : Image = await _save('daylight-no-sun')
			scene.get_node('Sun').light_color = Color.RED
			scene.get_node('Sun').light_energy = 1.0
			var red_sun : Image = await _save('daylight-red-sun')
			assert(no_sun.get_data() != red_sun.get_data(), 'Sun energy and color must change the render')
			scene.get_node('Sun').light_color = scene.SEA_PRESETS.PRESETS[0].sun.light_color
			scene.get_node('Sun').rotation_degrees = scene.SEA_PRESETS.PRESETS[0].sun.rotation_degrees + Vector3(0, 180, 0)
			var front_lit : Image = await _save('daylight-front-lit')
			water.material_override.set_shader_parameter('crest_scattering_strength', 0.0)
			var front_lit_no_crest : Image = await _save('daylight-front-lit-no-crest')
			assert(front_lit.get_data() == front_lit_no_crest.get_data(), 'Crest contribution must vanish without backlighting')
			print('PASS: rendered crest contribution, directional suppression and sunlight response')

func _benchmark(scene : Node3D, matching_camera : Transform3D) -> void:
	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var results : Array = []
	# Reverse the second pair to expose ordering/thermal bias.
	for index in [0, 1, 1, 0]:
		scene._apply_sea_preset(index)
		scene.camera.transform = matching_camera
		await create_timer(4.0).timeout
		var frames := 0
		var frame_ms : Array[float] = []
		var gpu_ms := 0.0
		var cpu_ms := 0.0
		var timestamp_updates := 0
		var previous_timing := Vector2(-1, -1)
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec() - start < 10000000:
			await process_frame
			var now := Time.get_ticks_usec()
			frame_ms.append((now - previous)/1000.0)
			previous = now
			frames += 1
			var timing := Vector2(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid), RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
			if timing != previous_timing: timestamp_updates += 1
			previous_timing = timing
			cpu_ms += timing.x
			gpu_ms += timing.y
		frame_ms.sort()
		var result := {
			'preset': index, 'frames': frames, 'mean_frame_ms': (previous - start)/1000.0/frames,
			'p95_frame_ms': frame_ms[int(frames*0.95)],
			'viewport_cpu_ms': cpu_ms/frames, 'viewport_gpu_ms': gpu_ms/frames,
			'draw_calls': Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			'render_timing_reliable': timestamp_updates > frames/2 and gpu_ms > 0.0,
		}
		if not result.render_timing_reliable: push_warning('Unavailable/stale GPU timings; keep the game window visible before comparing performance')
		results.append(result)
		print('TIMING: ', JSON.stringify(result))
	var file := FileAccess.open(output.path_join('timings-' + RenderingServer.get_current_rendering_method() + '.json'), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		'engine': Engine.get_version_info().string, 'gpu': RenderingServer.get_video_adapter_name(),
		'renderer': RenderingServer.get_current_rendering_method(), 'driver': RenderingServer.get_current_rendering_driver_name(),
		'resolution': '1920x1080', 'fft_resolution': scene.water.map_size, 'mesh_quality': scene.water.mesh_quality,
		'updates_per_second': scene.water.updates_per_second, 'particles': scene.get_node('Water/WaterSprayEmitter').amount,
		'seed': 1234, 'camera': str(matching_camera), 'samples': results,
	}, '\t'))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var scene : Node3D = load('res://main.tscn').instantiate()
	scene.should_render_imgui = false
	for audio in ['OceanAudioPlayer', 'WindAudioPlayer']: scene.get_node(audio).autoplay = false
	root.add_child(scene)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.always_on_top = true # Keep the test viewport visible while collecting GPU timings.
	var reflection = scene.get_node('PlanarReflection')
	reflection._process(0.0)
	assert((reflection.capture_camera.cull_mask & ((1 << 18) | (1 << 19))) == 0)
	assert((reflection.capture_camera.cull_mask & (1 << 20)) != 0)
	scene.camera.set_process(false)
	var matching_camera : Transform3D = scene.camera.transform
	assert(scene.water.map_size == 1024 and scene.water.mesh_quality == 1)
	assert(scene.water.updates_per_second == 60.0)
	assert(scene.get_node('Water/WaterSprayEmitter').amount == 32768)
	print('VALIDATION: 1920x1080; FFT 1024; High mesh; 60 Hz; 32768 particles; seed 1234; camera ', matching_camera)
	if OS.get_cmdline_user_args().has('--capture'):
		await _capture(scene, matching_camera)
	else:
		await _benchmark(scene, matching_camera)
	print('OUTPUT: ', ProjectSettings.globalize_path(output))
	scene.queue_free()
	for frame in 8: await process_frame
	quit()
