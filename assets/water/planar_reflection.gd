extends Node
## Sea of Thieves (Rare), SIGGRAPH 2018: mirrored planar capture and Snell's window.

const CAPTURE_EXCLUDED_LAYER := 1 << 1
const REFLECTION_CLIP_LAYER := 1 << 20
const CAPTURE_SCALE := 0.5
const REFLECTION_CLIP_SHADER := preload('res://assets/shaders/spatial/reflection_clip.gdshader')

@onready var source_camera := get_node("../Camera") as Camera3D
@onready var water := get_node("../Water") as VisualInstance3D

var capture_viewport: SubViewport
var capture_camera: Camera3D
var sky_viewport: SubViewport
var sky_camera: Camera3D
var clip_material: ShaderMaterial

static func reflected_transform(source: Transform3D, plane_y: float) -> Transform3D:
	var basis := source.basis.orthonormalized()
	var mirrored_basis := Basis(
		Vector3(-basis.x.x, basis.x.y, -basis.x.z),
		Vector3(basis.y.x, -basis.y.y, basis.y.z),
		Vector3(basis.z.x, -basis.z.y, basis.z.z)
	)
	return Transform3D(mirrored_basis, Vector3(source.origin.x, 2.0 * plane_y - source.origin.y, source.origin.z))

static func snell_discriminant(cos_incident: float, water_ior: float = 1.333) -> float:
	return 1.0 - water_ior * water_ior * (1.0 - cos_incident * cos_incident)

func _ready() -> void:
	# The main camera includes layer 2; the capture camera excludes water and submerged visuals on it.
	_set_capture_excluded_layer(water)
	source_camera.cull_mask |= CAPTURE_EXCLUDED_LAYER
	source_camera.cull_mask &= ~REFLECTION_CLIP_LAYER

	capture_viewport = SubViewport.new()
	capture_viewport.name = "PlanarReflectionViewport"
	capture_viewport.world_3d = get_viewport().world_3d
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(capture_viewport)

	capture_camera = Camera3D.new()
	capture_camera.name = "PlanarReflectionCamera"
	capture_camera.current = true
	capture_camera.cull_mask = (source_camera.cull_mask & ~CAPTURE_EXCLUDED_LAYER) | REFLECTION_CLIP_LAYER
	capture_viewport.add_child(capture_camera)
	var clip_quad := MeshInstance3D.new()
	clip_quad.name = 'WaterlineClipPass'
	var clip_mesh := QuadMesh.new()
	clip_mesh.size = Vector2(2.0, 2.0)
	clip_quad.mesh = clip_mesh
	clip_quad.layers = REFLECTION_CLIP_LAYER
	clip_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clip_quad.extra_cull_margin = 100000.0
	clip_material = ShaderMaterial.new()
	clip_material.shader = REFLECTION_CLIP_SHADER
	clip_material.render_priority = 127
	clip_quad.material_override = clip_material
	capture_camera.add_child(clip_quad)

	# Matching sky-only capture gives clipped pixels the same camera's clear-sky view.
	# ponytail: clipped pixels cannot reveal another object behind them; per-material clipping is the upgrade for that overlap.
	sky_viewport = SubViewport.new()
	sky_viewport.name = 'PlanarReflectionSkyViewport'
	sky_viewport.world_3d = get_viewport().world_3d
	sky_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sky_viewport)
	sky_camera = Camera3D.new()
	sky_camera.name = 'PlanarReflectionSkyCamera'
	sky_camera.current = true
	sky_camera.cull_mask = 0
	sky_viewport.add_child(sky_camera)
	clip_material.set_shader_parameter(&'sky_texture', sky_viewport.get_texture())
	RenderingServer.global_shader_parameter_set(&"planar_reflection", capture_viewport.get_texture())

func _process(_delta: float) -> void:
	# InteractionFoam removes its capture layers after this node's _ready has built the camera.
	var capture_mask := (source_camera.cull_mask & ~CAPTURE_EXCLUDED_LAYER) | REFLECTION_CLIP_LAYER
	if capture_camera.cull_mask != capture_mask:
		capture_camera.cull_mask = capture_mask
	_update_capture_size()
	_copy_camera_projection(capture_camera)
	var plane_y := water.global_position.y
	clip_material.set_shader_parameter(&'waterline', plane_y)
	if source_camera.global_position.y < plane_y:
		# From underwater, capture the above-water view for the refracted Snell cone.
		capture_camera.global_transform = source_camera.global_transform
	else:
		capture_camera.global_transform = reflected_transform(source_camera.global_transform, plane_y)
	sky_camera.global_transform = capture_camera.global_transform
	_copy_camera_projection(sky_camera)

func _update_capture_size() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	var target_size := Vector2i(maxi(2, int(visible_size.x * CAPTURE_SCALE)), maxi(2, int(visible_size.y * CAPTURE_SCALE)))
	if capture_viewport.size != target_size:
		capture_viewport.size = target_size
		sky_viewport.size = target_size

func _copy_camera_projection(target: Camera3D) -> void:
	target.projection = source_camera.projection
	target.fov = source_camera.fov
	target.size = source_camera.size
	target.near = source_camera.near
	target.far = source_camera.far
	target.keep_aspect = source_camera.keep_aspect
	target.h_offset = source_camera.h_offset
	target.v_offset = source_camera.v_offset
	target.frustum_offset = source_camera.frustum_offset

func _set_capture_excluded_layer(node: Node) -> void:
	# Visibility layers exclude water; the depth pass clips crossing objects at the waterline.
	if node is VisualInstance3D:
		node.layers = CAPTURE_EXCLUDED_LAYER
	for child in node.get_children():
		_set_capture_excluded_layer(child)

func _exit_tree() -> void:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	RenderingServer.global_shader_parameter_set(&"planar_reflection", ImageTexture.create_from_image(image))
