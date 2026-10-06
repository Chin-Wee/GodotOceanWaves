@tool
extends Node3D

const SEA_PRESETS := preload('res://assets/water/sea_presets.gd')

## Applied when running the scene. Runtime sliders can still override the preset.
@export_enum('Scene Defaults', 'Daylight Ocean') var sea_preset := 1
@export_enum('Calm', 'Normal', 'Storm') var sea_state := 1

var clipmap_tile_size := 1.0 # Not the smallest tile size, but one that reduces the amount of vertex jitter.
var previous_tile := Vector3i.MAX
var should_render_imgui := not Engine.is_editor_hint()
var _scene_preset : Dictionary
var _sea_state_baseline: Array[Dictionary] = []

@onready var viewport : Variant = Engine.get_singleton(&'EditorInterface').get_editor_viewport_3d(0) if Engine.is_editor_hint() else get_viewport()
@onready var camera : Variant = viewport.get_camera_3d()
@onready var water := $Water

# References to various parameters (for imgui)
@onready var _camera_fov := [camera.fov]
@onready var _updates_per_second := [water.updates_per_second]
@onready var _water_color := [water.water_color.r, water.water_color.g, water.water_color.b]
@onready var _foam_color := [water.foam_color.r, water.foam_color.g, water.foam_color.b]
@onready var _is_sea_spray_visible := [$Water/WaterSprayEmitter.visible]

func _init() -> void:
	if Engine.is_editor_hint(): return
	if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if Engine.is_embedded_in_editor(): return
	DisplayServer.window_set_size(DisplayServer.screen_get_size() * 0.75)
	DisplayServer.window_set_position(DisplayServer.screen_get_size() * 0.25 / 2.0)

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_scene_preset = _capture_scene_preset()
	_apply_sea_preset(sea_preset if sea_preset in [0, 1] else 0)

func _capture_scene_preset() -> Dictionary:
	var snapshot := {
		'water_color': water.water_color, 'foam_color': water.foam_color,
		'material': {}, 'environment': {}, 'sun': {}, 'cascades': [],
		'sky': $Environment.environment.sky.duplicate(true),
		'camera': {'transform': camera.transform, 'fov': camera.fov},
		'spray_visible': $Water/WaterSprayEmitter.visible,
		'fog_volume_visible': $FogVolume.visible,
	}
	var reference : Dictionary = SEA_PRESETS.PRESETS[0]
	for uniform in reference.material:
		snapshot.material[uniform] = water.material_override.get_shader_parameter(uniform)
	for property in reference.environment:
		snapshot.environment[property] = $Environment.environment.get(property)
	for property in reference.sun:
		snapshot.sun[property] = $Sun.get(property)
	for params in water.parameters:
		snapshot.cascades.append(params.duplicate())
	return snapshot

func _apply_sea_preset(index : int) -> void:
	if index < 0 or index > SEA_PRESETS.PRESETS.size(): return
	var preset : Dictionary = _scene_preset if index == 0 else SEA_PRESETS.PRESETS[index - 1]
	var cascades : Array[WaveCascadeParameters] = []
	for definition in preset.cascades:
		if definition is WaveCascadeParameters:
			cascades.append(definition.duplicate())
		else:
			var params := WaveCascadeParameters.new()
			for property in definition:
				params.set(property, definition[property])
			cascades.append(params)
	water.rng.seed = 1234
	water.time = 0.0
	water.next_update_time = 0.0
	water.parameters = cascades
	water.water_color = preset.water_color
	water.foam_color = preset.foam_color
	for uniform in preset.material:
		water.material_override.set_shader_parameter(uniform, preset.material[uniform])
	for property in preset.environment:
		$Environment.environment.set(property, preset.environment[property])
	for property in preset.sun:
		$Sun.set(property, preset.sun[property])
	$Environment.environment.sky = preset.sky.duplicate(true)
	camera.transform = _scene_preset.camera.transform
	camera.fov = preset.camera.fov
	if index != 0:
		camera.position.y = preset.camera.height
		camera.rotation.x = deg_to_rad(preset.camera.pitch_degrees)
	_camera_fov[0] = camera.fov
	$Water/WaterSprayEmitter.visible = preset.spray_visible
	$FogVolume.visible = preset.get('fog_volume_visible', false)
	sea_preset = index
	_capture_sea_state_baseline()
	_apply_sea_state(sea_state)
	_water_color = [water.water_color.r, water.water_color.g, water.water_color.b]
	_foam_color = [water.foam_color.r, water.foam_color.g, water.foam_color.b]
	_is_sea_spray_visible[0] = preset.spray_visible

func _capture_sea_state_baseline() -> void:
	_sea_state_baseline.clear()
	for params: WaveCascadeParameters in water.parameters:
		_sea_state_baseline.append({
			'displacement_scale': params.displacement_scale,
			'choppiness': params.choppiness,
			'foam_amount': params.foam_amount,
			'whitecap': params.whitecap,
		})

func _apply_sea_state(index: int) -> void:
	if index < 0 or index >= SEA_PRESETS.SEA_STATES.size(): return
	sea_state = index
	var state: Dictionary = SEA_PRESETS.SEA_STATES[index]
	var normal: Dictionary = SEA_PRESETS.SEA_STATES[1]
	var foam_scale: float = state.foam_amount / maxf(normal.foam_amount, 0.001)
	for i in mini(water.parameters.size(), _sea_state_baseline.size()):
		var params: WaveCascadeParameters = water.parameters[i]
		var baseline: Dictionary = _sea_state_baseline[i]
		params.displacement_scale = baseline.displacement_scale * state.wave_amplitude_scale
		params.choppiness = baseline.choppiness * state.choppiness_scale
		params.foam_amount = baseline.foam_amount * foam_scale
		params.whitecap = clampf(baseline.whitecap + state.whitecap - normal.whitecap, 0.0, 2.0)
		params.foam_decay = state.foam_decay
		params.foam_dispersion = state.foam_dispersion
	water.material_override.set_shader_parameter('foam_texture_blend', state.foam_texture_blend)

func _process(delta : float) -> void:
	if not Engine.is_editor_hint():
		if should_render_imgui:
			_render_imgui()
		var io = ImGui.GetIO()
		camera.enable_camera_movement = not should_render_imgui or not (io.WantCaptureMouse or io.WantCaptureKeyboard)

func _physics_process(delta: float) -> void:
	# Shift water mesh whenever player moves into a new tile.
	var tile := (Vector3(camera.global_position.x, 0.0, camera.global_position.z) / clipmap_tile_size).ceil()
	if not tile.is_equal_approx(previous_tile):
		water.global_position = tile * clipmap_tile_size
		previous_tile = tile

	# Vary audio samples based on total wind speed across all cascades.
	var total_wind_speed := 0.0
	for params in water.parameters:
		total_wind_speed += params.wind_speed
	$OceanAudioPlayer.volume_db = lerpf(-30.0, 15.0, minf(total_wind_speed/15.0, 1.0))
	$WindAudioPlayer.volume_db = lerpf(5.0, -30.0, minf(total_wind_speed/15.0, 1.0))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&'toggle_imgui'):
		should_render_imgui = not should_render_imgui
	elif event.is_action_pressed(&'toggle_fullscreen'):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED else DisplayServer.WINDOW_MODE_WINDOWED)
	elif event.is_action_pressed(&'ui_cancel'):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func imgui_text_tooltip(title : String, tooltip : String) -> void:
	ImGui.Text(title); if ImGui.IsItemHovered() and not tooltip.is_empty(): ImGui.SetTooltip(tooltip)

func _render_imgui() -> void:
	var fps := Engine.get_frames_per_second()
	var mesh_quality_keys : Array = water.MeshQuality.keys()

	ImGui.Begin(' ', [], ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoMove)
	ImGui.SetWindowPos(Vector2(20, 20))
	ImGui.SeparatorText('OceanWaves')
	ImGui.Text('FPS:                %d (%s)' % [fps, '%.2fms' % (1.0 / fps*1e3)])
	imgui_text_tooltip('Sea Preset:        ', 'Re-select a preset to reset your manual tweaks.\nWave resolution, mesh quality and update rate are controlled separately.'); ImGui.SameLine()
	var preset_name : String = 'Scene Defaults' if sea_preset == 0 else SEA_PRESETS.PRESETS[sea_preset - 1].name
	if ImGui.BeginCombo('##sea_preset', preset_name):
		for preset_index in range(SEA_PRESETS.PRESETS.size() + 1):
			var label : String = 'Scene Defaults' if preset_index == 0 else SEA_PRESETS.PRESETS[preset_index - 1].name
			if ImGui.Selectable(label): _apply_sea_preset(preset_index)
		ImGui.EndCombo()
	if sea_preset != 0: ImGui.Text(SEA_PRESETS.PRESETS[sea_preset - 1].description)
	imgui_text_tooltip('Sea State:         ', 'Scales wave height and choppiness, then tunes Jacobian foam persistence.'); ImGui.SameLine()
	if ImGui.BeginCombo('##sea_state', SEA_PRESETS.SEA_STATES[sea_state].name):
		for state_index in SEA_PRESETS.SEA_STATES.size():
			var state_name: String = SEA_PRESETS.SEA_STATES[state_index].name
			if ImGui.Selectable(state_name): _apply_sea_state(state_index)
		ImGui.EndCombo()
	ImGui.Text('Enable Sea Spray:  '); ImGui.SameLine(); if ImGui.Checkbox('##sea_spray_checkbox', _is_sea_spray_visible): $Water/WaterSprayEmitter.visible = _is_sea_spray_visible[0]
	imgui_text_tooltip('Wave Resolution:   ', 'The resolution of the displacement/normal maps used for each wave cascade.\nThis is also the FFT input size.'); ImGui.SameLine()
	if ImGui.BeginCombo('##resolution', '%dx%d' % [water.map_size, water.map_size]):
		for resolution in [128, 256, 512, 1024]:
			if ImGui.Selectable('%dx%d' % [resolution, resolution]):
				water.map_size = resolution
		ImGui.EndCombo()
	ImGui.Text('Wave Mesh Quality: '); ImGui.SameLine();
	if ImGui.BeginCombo('##mesh_quality', '%s' % mesh_quality_keys[water.mesh_quality].capitalize()):
		for mesh_quality in len(water.MeshQuality):
			if ImGui.Selectable('%s' % mesh_quality_keys[mesh_quality].capitalize()):
				water.mesh_quality = mesh_quality
				clipmap_tile_size = 1.0 if mesh_quality == water.MeshQuality.HIGH else 4.0
		ImGui.EndCombo()
	imgui_text_tooltip('Updates per Second:', 'Denotes how many times wave spectrums will be updated per second.\n(0 is uncapped)'); ImGui.SameLine(); if ImGui.SliderFloat('##update_rate', _updates_per_second, 0, 60): water.updates_per_second = _updates_per_second[0]
	ImGui.Text('Water Color:       '); ImGui.SameLine(); if ImGui.ColorButtonEx('##water_color_button', water.water_color, ImGui.ColorEditFlags_Float, Vector2(ImGui.GetColumnWidth(), ImGui.GetFrameHeight())): ImGui.OpenPopup('water_color_picker')
	if ImGui.BeginPopup('water_color_picker'):
		if ImGui.ColorPicker3('##water_color_picker', _water_color, ImGui.ColorEditFlags_Float | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_DisplayHex):
			water.water_color = Color(_water_color[0], _water_color[1], _water_color[2])
		ImGui.EndPopup()
	ImGui.Text('Foam Color:        '); ImGui.SameLine(); if ImGui.ColorButtonEx('##foam_color_button', water.foam_color, ImGui.ColorEditFlags_Float, Vector2(ImGui.GetColumnWidth(), ImGui.GetFrameHeight())): ImGui.OpenPopup('foam_color_picker')
	if ImGui.BeginPopup('foam_color_picker'):
		if ImGui.ColorPicker3('##foam_color_picker', _foam_color, ImGui.ColorEditFlags_Float | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_DisplayHex):
			water.foam_color = Color(_foam_color[0], _foam_color[1], _foam_color[2])
		ImGui.EndPopup()

	ImGui.SeparatorText('Wave Parameters')
	if ImGui.BeginTabBar('##cascades'):
		for i in len(water.parameters):
			var params : WaveCascadeParameters = water.parameters[i]
			if ImGui.BeginTabItem('Cascade %d' % (i + 1)):
				imgui_text_tooltip('Tile Length:       ', 'Denotes the distance the cascade\'s tile should cover (in meters).'); ImGui.SameLine(); if ImGui.InputFloat2('##tile_length', params._tile_length): params.tile_length = Vector2(params._tile_length[0], params._tile_length[1])
				imgui_text_tooltip('Displacement Scale:', ''); ImGui.SameLine(); if ImGui.SliderFloat('##displacement_scale', params._displacement_scale, 0, 2): params.displacement_scale = params._displacement_scale[0]
				imgui_text_tooltip('Choppiness:        ', 'Horizontal FFT displacement. Higher values sharpen wave crests without increasing height.'); ImGui.SameLine(); if ImGui.SliderFloat('##choppiness', params._choppiness, 0, 2): params.choppiness = params._choppiness[0]
				imgui_text_tooltip('Normal Scale:      ', ''); ImGui.SameLine(); if ImGui.SliderFloat('##normal_scale', params._normal_scale, 0, 2): params.normal_scale = params._normal_scale[0]
				ImGui.Dummy(Vector2(0,0)); ImGui.Separator(); ImGui.Dummy(Vector2(0,0))
				imgui_text_tooltip('Wind Speed:        ', 'Denotes the average wind speed above the water (in meters per second).\nIncreasing makes waves steeper and more \'chaotic\'.'); ImGui.SameLine(); if ImGui.DragFloat('##wind_speed', params._wind_speed): params.wind_speed = params._wind_speed[0]
				imgui_text_tooltip('Wind Direction:    ', ''); ImGui.SameLine(); if ImGui.SliderAngle('##wind_direction', params._wind_direction): params.wind_direction = rad_to_deg(params._wind_direction[0])
				imgui_text_tooltip('Fetch Length:      ', 'Denotes the distance from shoreline (in kilometers).\nIncreasing makes waves steeper, but reduces their \'choppiness\'.'); ImGui.SameLine(); if ImGui.DragFloat('##fetch_length', params._fetch_length): params.fetch_length = params._fetch_length[0]
				imgui_text_tooltip('Swell:             ', 'Modifies waves to clump in a more elongated, parallel manner.'); ImGui.SameLine(); if ImGui.SliderFloat('##swell', params._swell, 0, 2): params.swell = params._swell[0]
				imgui_text_tooltip('Spread:            ', 'Modifies how much wind and swell affect the direction of the waves.'); ImGui.SameLine(); if ImGui.SliderFloat('##spread', params._spread, 0, 1): params.spread = params._spread[0]
				imgui_text_tooltip('Detail:            ', 'Modifies the attenuation of high frequency waves.'); ImGui.SameLine(); if ImGui.SliderFloat('##detail', params._detail, 0, 1): params.detail = params._detail[0]
				ImGui.Dummy(Vector2(0,0)); ImGui.Separator(); ImGui.Dummy(Vector2(0,0))
				imgui_text_tooltip('Whitecap:          ', 'Jacobian threshold for fresh breaking foam.'); ImGui.SameLine(); if ImGui.SliderFloat('##white_cap', params._whitecap, 0, 2): params.whitecap = params._whitecap[0]
				imgui_text_tooltip('Foam Amount:       ', ''); ImGui.SameLine(); if ImGui.SliderFloat('##foam_amount', params._foam_amount, 0, 10): params.foam_amount = params._foam_amount[0]
				imgui_text_tooltip('Foam Decay:        ', 'Controls persistence of total foam coverage.'); ImGui.SameLine(); if ImGui.SliderFloat('##foam_decay', params._foam_decay, 0, 5): params.foam_decay = params._foam_decay[0]
				imgui_text_tooltip('Foam Dispersion:   ', 'Controls the progressive feedback blur spread.'); ImGui.SameLine(); if ImGui.SliderFloat('##foam_dispersion', params._foam_dispersion, 0, 10): params.foam_dispersion = params._foam_dispersion[0]
				ImGui.EndTabItem()
		ImGui.EndTabBar()

	ImGui.SeparatorText('Camera')
	ImGui.Text('Camera Position:    %+.2v' % camera.global_position)
	ImGui.Text('Camera FOV:        '); ImGui.SameLine(); if ImGui.SliderFloat('##fov_float', _camera_fov, 20, 170): camera.fov = _camera_fov[0]

	ImGui.Dummy(Vector2(0,0)); ImGui.Separator(); ImGui.Dummy(Vector2(0,0))
	ImGui.PushStyleColor(ImGui.Col_Text, Color.WEB_GRAY);
	ImGui.Text('Press %s-H to toggle GUI visibility!' % ['Cmd' if OS.get_name() == 'macOS' else 'Ctrl']);
	ImGui.Text('Press %s-F to toggle fullscreen!' % ['Cmd' if OS.get_name() == 'macOS' else 'Ctrl']);
	ImGui.PopStyleColor()
	ImGui.End()
