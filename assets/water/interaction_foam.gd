extends Node
## Global contract: texture R is foam; center is world XZ; extent is half-width
## in meters; strength is the shader multiplier. Sample with
## (world_xz - center) / (2.0 * extent) + 0.5.
## Reference: Rare's Sea of Thieves SIGGRAPH 2018 talk describes camera-centered
## depth comparisons and progressively blurred feedback; this uses aligned
## above- and below-water camera-centered captures with one world-plane history.

const DEPTH_SHADER := preload('res://assets/shaders/spatial/interaction_depth.gdshader')
const HISTORY_SHADER := preload('res://assets/shaders/canvas/interaction_history.gdshader')

@export var camera_path: NodePath = ^'../Camera'
@export var water_path: NodePath = ^'../Water'
@export_range(0.25, 1.0, 0.05) var resolution_scale := 0.5
@export_range(0.05, 2.0, 0.05) var intersection_width := 0.45
@export_range(0.25, 8.0, 0.25) var submerged_interaction_depth := 3.0
@export_range(0.5, 30.0, 0.5) var trail_half_life := 8.0
@export_range(0.0, 4.0, 0.05) var blur_pixels := 1.25
@export var current_velocity := Vector2(0.35, 0.0)
@export_range(0.0, 2.0, 0.05) var foam_strength := 1.0
@export_range(16.0, 1024.0, 16.0) var top_down_extent := 256.0

var camera: Camera3D
var water: MeshInstance3D
var top_down_viewport: SubViewport
var submerged_viewport: SubViewport
var history_viewports: Array[SubViewport] = []
var history_materials: Array[ShaderMaterial] = []
var top_down_camera: Camera3D
var top_down_material: ShaderMaterial
var submerged_camera: Camera3D
var submerged_material: ShaderMaterial
var _write_index := 0
var _previous_center := Vector2.ZERO
var _has_previous_center := false

func _ready() -> void:
	camera = get_node(camera_path)
	water = get_node(water_path)
	# Reserve layer 2 for water and spray; default-layer hulls and islands enter the depth source.
	# ponytail: only nearest opaque surfaces are captured; dedicated hull layers if deck occlusion matters.
	water.layers = 2
	var spray := water.get_node_or_null('WaterSprayEmitter') as GeometryInstance3D
	if spray:
		spray.layers = 2
	_make_top_down_viewport()
	_make_history_viewports()
	get_viewport().size_changed.connect(_resize_buffers)
	_resize_buffers()
	_sync_camera()
	RenderingServer.global_shader_parameter_set(&'interaction_foam_texture', history_viewports[0].get_texture())
	RenderingServer.global_shader_parameter_set(&'interaction_foam_strength', foam_strength)

func _process(delta: float) -> void:
	_sync_camera()
	var center := Vector2(camera.global_position.x, camera.global_position.z)
	var waterline := water.global_position.y
	top_down_material.set_shader_parameter(&'waterline', waterline)
	top_down_material.set_shader_parameter(&'intersection_width', intersection_width)
	submerged_material.set_shader_parameter(&'waterline', waterline)
	submerged_material.set_shader_parameter(&'intersection_width', intersection_width)
	submerged_material.set_shader_parameter(&'submerged_interaction_depth', submerged_interaction_depth)
	submerged_material.set_shader_parameter(&'capture_submerged', true)

	var output_index := _write_index
	var input_index := 1 - output_index
	var material := history_materials[output_index]
	material.set_shader_parameter(&'contact_mask', top_down_viewport.get_texture())
	material.set_shader_parameter(&'submerged_mask', submerged_viewport.get_texture())
	material.set_shader_parameter(&'previous_history', history_viewports[input_index].get_texture())
	material.set_shader_parameter(&'current_center', center)
	material.set_shader_parameter(&'previous_center', _previous_center)
	material.set_shader_parameter(&'extent', top_down_extent)
	material.set_shader_parameter(&'current_velocity', current_velocity)
	material.set_shader_parameter(&'delta', minf(delta, 0.1))
	material.set_shader_parameter(&'half_life', trail_half_life)
	material.set_shader_parameter(&'blur_pixels', blur_pixels)
	material.set_shader_parameter(&'history_valid', _has_previous_center)
	history_viewports[output_index].render_target_update_mode = SubViewport.UPDATE_ALWAYS
	history_viewports[input_index].render_target_update_mode = SubViewport.UPDATE_DISABLED
	RenderingServer.global_shader_parameter_set(&'interaction_foam_texture', history_viewports[output_index].get_texture())
	RenderingServer.global_shader_parameter_set(&'interaction_foam_center', center)
	RenderingServer.global_shader_parameter_set(&'interaction_foam_extent', top_down_extent)
	RenderingServer.global_shader_parameter_set(&'interaction_foam_strength', foam_strength)
	_previous_center = center
	_has_previous_center = true
	_write_index = input_index

func _make_top_down_viewport() -> void:
	top_down_viewport = SubViewport.new()
	top_down_viewport.name = 'TopDownDepthSource'
	top_down_viewport.world_3d = get_viewport().world_3d
	top_down_viewport.transparent_bg = true
	top_down_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(top_down_viewport)
	top_down_camera = Camera3D.new()
	top_down_camera.name = 'TopDownCamera'
	top_down_camera.current = true
	top_down_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_down_camera.size = top_down_extent * 2.0
	top_down_viewport.add_child(top_down_camera)
	var quad := MeshInstance3D.new()
	quad.name = 'TopDownContactPass'
	quad.mesh = QuadMesh.new()
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 100000.0
	top_down_material = ShaderMaterial.new()
	top_down_material.shader = DEPTH_SHADER
	top_down_material.render_priority = 127
	quad.material_override = top_down_material
	top_down_camera.add_child(quad)
	# A second aligned capture sees hull undersides hidden from the top-down camera.
	submerged_viewport = SubViewport.new()
	submerged_viewport.name = 'SubmergedDepthSource'
	submerged_viewport.world_3d = get_viewport().world_3d
	submerged_viewport.transparent_bg = true
	submerged_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(submerged_viewport)
	submerged_camera = Camera3D.new()
	submerged_camera.name = 'SubmergedCamera'
	submerged_camera.current = true
	submerged_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	submerged_camera.size = top_down_extent * 2.0
	submerged_viewport.add_child(submerged_camera)
	var submerged_quad := MeshInstance3D.new()
	submerged_quad.name = 'SubmergedContactPass'
	submerged_quad.mesh = QuadMesh.new()
	submerged_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	submerged_quad.extra_cull_margin = 100000.0
	submerged_material = ShaderMaterial.new()
	submerged_material.shader = DEPTH_SHADER
	submerged_material.render_priority = 127
	submerged_material.set_shader_parameter(&'capture_submerged', true)
	submerged_quad.material_override = submerged_material
	submerged_camera.add_child(submerged_quad)

func _make_history_viewports() -> void:
	for index in 2:
		var viewport := SubViewport.new()
		viewport.name = 'InteractionHistory%d' % index
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		viewport.transparent_bg = false
		add_child(viewport)
		var rect := ColorRect.new()
		rect.name = 'HistoryPass'
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = HISTORY_SHADER
		rect.material = material
		viewport.add_child(rect)
		history_viewports.append(viewport)
		history_materials.append(material)

func _resize_buffers() -> void:
	if not top_down_viewport or history_viewports.size() != 2:
		return
	var viewport_size: Vector2i = get_viewport().size
	var side := maxi(int(mini(viewport_size.x, viewport_size.y) * resolution_scale), 128)
	top_down_viewport.size = Vector2i(side, side)
	submerged_viewport.size = Vector2i(side, side)
	for viewport in history_viewports:
		viewport.size = Vector2i(side, side)

func _sync_camera() -> void:
	top_down_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)),
		Vector3(camera.global_position.x, water.global_position.y + 512.0, camera.global_position.z)
	)
	top_down_camera.size = top_down_extent * 2.0
	top_down_camera.near = 0.1
	top_down_camera.far = 1024.0
	top_down_camera.cull_mask = camera.cull_mask & ~water.layers
	submerged_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)),
		Vector3(camera.global_position.x, water.global_position.y - 512.0, camera.global_position.z)
	)
	submerged_camera.size = top_down_extent * 2.0
	submerged_camera.near = 0.1
	submerged_camera.far = 1024.0
	submerged_camera.cull_mask = camera.cull_mask & ~water.layers

func _exit_tree() -> void:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	RenderingServer.global_shader_parameter_set(&'interaction_foam_texture', ImageTexture.create_from_image(image))
