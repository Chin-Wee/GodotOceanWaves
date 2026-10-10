extends SceneTree
## Phase-aligned FFT / Gerstner capture and timing on the visible rendering device.

const CASCADE_COUNT := 3
const FIXED_SEED := Vector2i(1234, 5678)
const TARGET_TIME := 120.0
const CAPTURE_SECONDS := 4.0
const RUN_ORDER := [0, 1, 1, 0]

var output := 'user://gerstner-parity/modes20/' + RenderingServer.get_current_rendering_method() + '-' + RenderingServer.get_current_rendering_driver_name()
var scene: Node3D
var water: MeshInstance3D
var camera: Camera3D
var spray: GPUParticles3D
var matching_camera: Transform3D

func _initialize() -> void:
	_run.call_deferred()

func _prepare_scene() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.always_on_top = true
	scene = load('res://main.tscn').instantiate()
	scene.should_render_imgui = false
	root.add_child(scene)
	for frame in 3: await process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	water = scene.water
	water.set_process(false)
	camera = scene.camera
	camera.set_process(false)
	camera.enable_camera_movement = false
	matching_camera = camera.global_transform
	spray = scene.get_node('Water/WaterSprayEmitter')
	spray.use_fixed_seed = true
	spray.seed = 1234
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print('VALIDATION: renderer=%s driver=%s GPU=%s resolution=1920x1080 map=%dx%d mesh_quality=%s updates_per_second=%s camera=%s seed=%s' % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), water.map_size, water.map_size,
		'High' if water.mesh_quality == water.MeshQuality.HIGH else 'Low', water.updates_per_second,
		str(matching_camera), str(FIXED_SEED)])

func _set_mode(algorithm: int) -> WaveGenerator:
	if water.wave_generator: water.wave_generator.set_process(false)
	if water.wave_algorithm == algorithm:
		water._setup_wave_generator()
	else:
		water.wave_algorithm = algorithm
	var generator: WaveGenerator = water.wave_generator
	generator.set_process(false)
	for index in CASCADE_COUNT:
		var params: WaveCascadeParameters = water.parameters[index]
		params.spectrum_seed = FIXED_SEED + Vector2i(index * 17, index * 31)
		params.should_generate_spectrum = true
		params.time = TARGET_TIME + PI * index - CAPTURE_SECONDS
		params.whitecap = 0.65 if index == 0 else params.whitecap
	water.time = 0.0
	water.next_update_time = 0.0
	camera.global_transform = matching_camera
	spray.restart()
	return generator

func _advance(generator: WaveGenerator, delta: float) -> void:
	water._update_water(delta)
	for cascade in CASCADE_COUNT:
		generator._process(0.0)

func _capture_image(name: String) -> Image:
	for frame in 8: await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	assert(image.get_size() == Vector2i(1920, 1080), 'Unexpected viewport size: %s' % image.get_size())
	var path := ProjectSettings.globalize_path(output.path_join(name + '.png'))
	assert(image.save_png(path) == OK, 'Could not save ' + path)
	print('CAPTURE: ', path)
	return image

func _read_cascade_metrics(bytes: PackedByteArray, cascade: int) -> Dictionary:
	var area: int = water.map_size * water.map_size
	var expected_bytes: int = CASCADE_COUNT * area * 64
	assert(bytes.size() == expected_bytes, 'Unexpected synthesis buffer readback size: %d' % bytes.size())
	var height_squared := 0.0
	var horizontal_squared := 0.0
	var slope_squared := 0.0
	var horizontal_gradient_squared := 0.0
	var breaking_pixels := 0
	var whitecap: float = water.parameters[cascade].whitecap
	var cascade_base: int = cascade * area * 64
	var output_base: int = cascade_base + area * 32
	for pixel in area:
		var height_offset: int = output_base + pixel * 8
		var horizontal_offset: int = output_base + area * 8 + pixel * 8
		var normal_offset: int = output_base + area * 16 + pixel * 8
		var jacobian_offset: int = output_base + area * 24 + pixel * 8
		var dx := bytes.decode_float(height_offset)
		var height := bytes.decode_float(height_offset + 4)
		var dz := bytes.decode_float(horizontal_offset)
		var dhy_dx := bytes.decode_float(horizontal_offset + 4)
		var dhy_dz := bytes.decode_float(normal_offset)
		var dhx_dx := bytes.decode_float(normal_offset + 4)
		var dhz_dz := bytes.decode_float(jacobian_offset)
		var dhz_dx := bytes.decode_float(jacobian_offset + 4)
		var jacobian := (1.0 + dhx_dx) * (1.0 + dhz_dz) - dhz_dx * dhz_dx
		if jacobian < whitecap: breaking_pixels += 1
		height_squared += height * height
		horizontal_squared += dx * dx + dz * dz
		slope_squared += dhy_dx * dhy_dx + dhy_dz * dhy_dz
		horizontal_gradient_squared += dhx_dx * dhx_dx + dhz_dz * dhz_dz + 2.0 * dhz_dx * dhz_dx
	var area_f := float(water.map_size * water.map_size)
	return {
		'height_rms_m': sqrt(height_squared / area_f),
		'horizontal_rms_m': sqrt(horizontal_squared / area_f),
		'vertical_slope_rms': sqrt(slope_squared / area_f),
		'horizontal_gradient_rms': sqrt(horizontal_gradient_squared / area_f),
		'breaking_coverage': breaking_pixels / area_f,
	}

func _capture_variant(algorithm: int) -> Dictionary:
	var label := 'fft' if algorithm == 0 else 'gerstner-20-per-cascade'
	var generator := _set_mode(algorithm)
	await process_frame
	for step in int(CAPTURE_SECONDS * 60.0):
		_advance(generator, 1.0 / 60.0)
		await process_frame
	var buffer_bytes: PackedByteArray = generator.context.device.buffer_get_data(generator.descriptors[&'fft_buffer'].rid)
	var metrics: Array = []
	for cascade in CASCADE_COUNT:
		metrics.append(_read_cascade_metrics(buffer_bytes, cascade))
	print('METRICS ', label, ': ', JSON.stringify(metrics))
	var image := await _capture_image(label)
	return {'name': label, 'metrics': metrics, 'image': image}

func _measure_variant(algorithm: int, run_index: int) -> Dictionary:
	var label := 'FFT' if algorithm == 0 else 'Gerstner-20-per-cascade'
	var generator := _set_mode(algorithm)
	await process_frame
	for step in 120:
		_advance(generator, 1.0 / 60.0)
		await process_frame
	scene.set_process(true)
	water.set_process(true)
	generator.set_process(true)
	var viewport := root.get_viewport_rid()
	var frames := 0
	var frame_ms: Array[float] = []
	var gpu_ms := 0.0
	var cpu_ms := 0.0
	var timing_updates := 0
	var previous_timing := Vector2(-1.0, -1.0)
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 5_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - previous) / 1000.0)
		previous = now
		frames += 1
		var timing := Vector2(RenderingServer.viewport_get_measured_render_time_cpu(viewport), RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		if timing != previous_timing: timing_updates += 1
		previous_timing = timing
		cpu_ms += timing.x
		gpu_ms += timing.y
	frame_ms.sort()
	var result := {
		'algorithm': label, 'run': run_index, 'frames': frames,
		'mean_frame_ms': (previous - start) / 1000.0 / frames,
		'p95_frame_ms': frame_ms[mini(frames - 1, int(frames * 0.95))],
		'viewport_cpu_ms': cpu_ms / frames, 'viewport_gpu_ms': gpu_ms / frames,
		'gpu_timing_reliable': timing_updates > frames / 2 and gpu_ms > 0.0,
	}
	if not result.gpu_timing_reliable:
		push_warning('GPU viewport timing is stale or unavailable; use frame timing only')
	print('TIMING: ', JSON.stringify(result))
	generator.set_process(false)
	water.set_process(false)
	scene.set_process(false)
	return result

func _run() -> void:
	await _prepare_scene()
	assert(water.wave_algorithm == 0, 'FFT must remain the default algorithm')
	assert(water.map_size == 1024 and water.mesh_quality == water.MeshQuality.HIGH)
	assert(water.updates_per_second == 60.0)
	var captures: Array = []
	for algorithm in [0, 1]: captures.append(await _capture_variant(algorithm))
	var fft_image: Image = captures[0].image.duplicate()
	var gerstner_image: Image = captures[1].image.duplicate()
	fft_image.convert(Image.FORMAT_RGBA8)
	gerstner_image.convert(Image.FORMAT_RGBA8)
	var side_by_side := Image.create(3840, 1080, false, Image.FORMAT_RGBA8)
	side_by_side.blit_rect(fft_image, Rect2i(Vector2i.ZERO, fft_image.get_size()), Vector2i.ZERO)
	side_by_side.blit_rect(gerstner_image, Rect2i(Vector2i.ZERO, gerstner_image.get_size()), Vector2i(1920, 0))
	var comparison_path := ProjectSettings.globalize_path(output.path_join('fft-left-gerstner-right.png'))
	assert(side_by_side.save_png(comparison_path) == OK)
	print('COMPARISON: ', comparison_path)
	var benchmark_results: Array = []
	for run_index in RUN_ORDER.size():
		benchmark_results.append(await _measure_variant(RUN_ORDER[run_index], run_index))
	var capture_summary: Array = []
	for capture in captures:
		capture_summary.append({'algorithm': capture.name, 'cascades': capture.metrics})
	var benchmark := {
		'engine': Engine.get_version_info().string,
		'gpu': RenderingServer.get_video_adapter_name(),
		'renderer': RenderingServer.get_current_rendering_method(),
		'driver': RenderingServer.get_current_rendering_driver_name(),
		'resolution': '1920x1080', 'map_size': water.map_size,
		'mesh_quality': 'High', 'updates_per_second': water.updates_per_second,
		'camera': str(matching_camera), 'seed': str(FIXED_SEED),
		'capture_times': 'cascade i at 120 + PI*i seconds after 4.000s fixed-step warmup',
		'capture_rms': capture_summary,
		'benchmark_runs': benchmark_results,
	}
	var timing_path := ProjectSettings.globalize_path(output.path_join('benchmark.json'))
	var file := FileAccess.open(timing_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(benchmark, '\t'))
	print('BENCHMARK: ', timing_path)
	print('OUTPUT: ', ProjectSettings.globalize_path(output))
	scene.queue_free()
	for frame in 8: await process_frame
	quit()
