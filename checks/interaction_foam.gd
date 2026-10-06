extends SceneTree
## Run with a RenderingDevice renderer (not --headless):
## godot --path . --script res://checks/interaction_foam.gd --audio-driver Dummy

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(1))
	_run.call_deferred()

func _read_texture(viewport: SubViewport) -> Image:
	RenderingServer.force_draw()
	await process_frame
	return viewport.get_texture().get_image()

func _sample(image: Image, uv: Vector2, radius := 2) -> float:
	var center := Vector2i(uv * Vector2(image.get_size()))
	var result := 0.0
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				result = maxf(result, image.get_pixel(x, y).r)
	return result

func _run() -> void:
	root.size = Vector2i(640, 640)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.name = 'Camera'
	camera.position = Vector3(0.0, 10.0, -25.0)
	camera.current = true
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var water := MeshInstance3D.new()
	water.name = 'Water'
	water.mesh = PlaneMesh.new()
	water.layers = 2
	scene.add_child(water)
	var interaction := Node.new()
	interaction.name = 'InteractionFoam'
	interaction.set_script(load('res://assets/water/interaction_foam.gd'))
	interaction.set('top_down_extent', 16.0)
	scene.add_child(interaction)

	# A top face exactly at sea level is a repeatable opaque depth contact.
	var target := MeshInstance3D.new()
	target.name = 'WaterlineProbe'
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 1.0, 4.0)
	target.mesh = box
	target.position = Vector3(6.0, -0.5, -21.0)
	var target_material := StandardMaterial3D.new()
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target.material_override = target_material
	scene.add_child(target)
	for frame in 10:
		await process_frame

	var source_image := await _read_texture(interaction.top_down_viewport)
	var history_image := await _read_texture(interaction.history_viewports[interaction._write_index ^ 1])
	var source_uv := Vector2(0.6875, 0.625) # world (6, -21) in the 32 m camera-centered window
	assert(_sample(source_image, source_uv) > 0.5, 'Top-down depth source must mark the opaque waterline contact at its world-plane UV.')
	assert(_sample(history_image, source_uv) > 0.25, 'History buffer must accumulate the contact at the same world-plane UV.')

	# Remove the source, move the window, and verify that history follows the fixed world point.
	target.queue_free()
	camera.global_position.x = 8.0
	camera.global_position.z = -21.0
	for frame in 6:
		await process_frame
	var moved_image := await _read_texture(interaction.history_viewports[interaction._write_index ^ 1])
	var moved_uv := Vector2(0.4375, 0.5)
	assert(_sample(moved_image, moved_uv) > 0.1, 'History must remain aligned after the camera-centered window moves.')
	print('PASS: top-down depth contact, history accumulation, and camera-window reprojection at matching world-plane UVs.')
	quit()
