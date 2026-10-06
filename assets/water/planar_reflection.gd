extends Node
## Sea of Thieves (Rare), SIGGRAPH 2018: mirrored planar capture and Snell's window.

const CAPTURE_EXCLUDED_LAYER := 1 << 1
const CAPTURE_SCALE := 0.5

@onready var source_camera := get_node("../Camera") as Camera3D
@onready var water := get_node("../Water") as VisualInstance3D

var capture_viewport: SubViewport
var capture_camera: Camera3D

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

	capture_viewport = SubViewport.new()
	capture_viewport.name = "PlanarReflectionViewport"
	capture_viewport.world_3d = get_viewport().world_3d
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(capture_viewport)

	capture_camera = Camera3D.new()
	capture_camera.name = "PlanarReflectionCamera"
	capture_camera.current = true
	capture_camera.cull_mask = source_camera.cull_mask & ~CAPTURE_EXCLUDED_LAYER
	capture_viewport.add_child(capture_camera)
	RenderingServer.global_shader_parameter_set(&"planar_reflection", capture_viewport.get_texture())

func _process(_delta: float) -> void:
	_update_capture_size()
	_copy_camera_projection()
	var plane_y := water.global_position.y
	if source_camera.global_position.y < plane_y:
		# From underwater, capture the above-water view for the refracted Snell cone.
		capture_camera.global_transform = source_camera.global_transform
	else:
		capture_camera.global_transform = reflected_transform(source_camera.global_transform, plane_y)

func _update_capture_size() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	var target_size := Vector2i(maxi(2, int(visible_size.x * CAPTURE_SCALE)), maxi(2, int(visible_size.y * CAPTURE_SCALE)))
	if capture_viewport.size != target_size:
		capture_viewport.size = target_size

func _copy_camera_projection() -> void:
	capture_camera.projection = source_camera.projection
	capture_camera.fov = source_camera.fov
	capture_camera.size = source_camera.size
	capture_camera.near = source_camera.near
	capture_camera.far = source_camera.far
	capture_camera.keep_aspect = source_camera.keep_aspect
	capture_camera.h_offset = source_camera.h_offset
	capture_camera.v_offset = source_camera.v_offset
	capture_camera.frustum_offset = source_camera.frustum_offset

func _set_capture_excluded_layer(node: Node) -> void:
	# ponytail: visibility layers cull submerged objects; partial clipping needs matching shader materials.
	if node is VisualInstance3D:
		node.layers = CAPTURE_EXCLUDED_LAYER
	for child in node.get_children():
		_set_capture_excluded_layer(child)

func _exit_tree() -> void:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	RenderingServer.global_shader_parameter_set(&"planar_reflection", ImageTexture.create_from_image(image))
