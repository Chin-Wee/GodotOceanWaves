extends SceneTree
## Run with Godot --path . --script res://checks/panel_input.gd.

class PanelProbe extends "res://main.gd":
	var spray_rect := Rect2()
	var displacement_rect := Rect2()

	func imgui_text_tooltip(title: String, tooltip: String) -> void:
		if title == 'Wave Resolution:   ':
			# The preceding item is the actual Sea Spray checkbox.
			spray_rect = Rect2(ImGui.GetItemRectMin(), ImGui.GetItemRectSize())
		elif title == 'Choppiness:        ':
			displacement_rect = Rect2(ImGui.GetItemRectMin(), ImGui.GetItemRectSize())
		super.imgui_text_tooltip(title, tooltip)

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(1))
	call_deferred('_check_panel')

func _frames(count := 3) -> void:
	for frame in count:
		await process_frame

func _mouse(position: Vector2, pressed := false, button := 0) -> void:
	var event: InputEventMouse
	if button:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.pressed = pressed
		event = click
	else:
		event = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)

func _check_panel() -> void:
	if not OS.get_cmdline_args().has('--embedded'):
		root.get_node('ImGuiRoot')._use_local_input()
	var scene = load('res://main.tscn').instantiate()
	scene.set_script(PanelProbe)
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	scene.water.map_size = 128
	await _frames(30)
	var position: Vector2 = scene.spray_rect.get_center()
	_mouse(position)
	await _frames()
	assert(ImGui.GetMousePos().is_equal_approx(position), 'Panel must receive viewport-local mouse coordinates.')
	assert(not scene.camera.enable_camera_movement, 'Hovering the panel must block freecam.')
	var spray = scene.get_node('Water/WaterSprayEmitter')
	var before: bool = spray.visible
	_mouse(position, true, MOUSE_BUTTON_LEFT)
	await _frames()
	_mouse(position, false, MOUSE_BUTTON_LEFT)
	await _frames()
	assert(spray.visible != before, 'Clicking the actual panel checkbox must change the scene.')
	_mouse(position, true, MOUSE_BUTTON_LEFT)
	await _frames()
	_mouse(position, false, MOUSE_BUTTON_LEFT)
	await _frames()
	assert(spray.visible == before, 'Repeated panel clicks must work.')
	var params = scene.water.parameters[0]
	var displacement_before: float = params.displacement_scale
	var slider: Rect2 = scene.displacement_rect
	position = slider.position + slider.size * Vector2(0.25, 0.5)
	_mouse(position)
	await _frames()
	_mouse(position, true, MOUSE_BUTTON_LEFT)
	await _frames()
	position = slider.position + slider.size * Vector2(0.75, 0.5)
	_mouse(position)
	await _frames()
	_mouse(position, false, MOUSE_BUTTON_LEFT)
	await _frames()
	assert(not is_equal_approx(params.displacement_scale, displacement_before), 'Dragging the panel slider must update wave parameters.')
	var camera_position: Vector3 = scene.camera.position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	scene.camera._process(0.1)
	assert(scene.camera.position.is_equal_approx(camera_position), 'Panel capture must suppress movement keys.')
	_mouse(Vector2(900, 500))
	await _frames()
	assert(scene.camera.enable_camera_movement, 'Moving off the panel must restore freecam.')
	scene.camera._process(0.1)
	assert(not scene.camera.position.is_equal_approx(camera_position), 'Freecam movement must remain available.')
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	scene.camera.enable_camera_movement = false
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	scene.camera._input(release)
	assert(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, 'Panel capture must not trap the cursor.')
	print('PASS: embedded panel coordinates, repeated clicks, slider editing, and freecam input capture.')
	quit()
