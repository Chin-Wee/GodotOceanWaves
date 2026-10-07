extends SceneTree

const REFLECTION := preload("res://assets/water/planar_reflection.gd")

func _initialize() -> void:
	var critical_cosine := sqrt(1.0 - 1.0 / (1.333 * 1.333))
	assert(REFLECTION.snell_discriminant(1.0) > 0.0)
	assert(REFLECTION.snell_discriminant(critical_cosine - 0.01) < 0.0)
	assert(REFLECTION.snell_discriminant(critical_cosine + 0.01) > 0.0)
	var source := Transform3D(Basis.from_euler(Vector3(0.2, -0.6, 0.1)), Vector3(3.0, -2.0, 5.0))
	var tir := REFLECTION.tir_transform(source, 0.5)
	var source_forward := -source.basis.z
	var tir_forward := -tir.basis.z
	var expected_forward := Vector3(source_forward.x, -source_forward.y, source_forward.z)
	assert(tir_forward.is_equal_approx(expected_forward), 'TIR camera must reflect rays across the water plane')
	assert(is_equal_approx(tir.origin.y, 2.0 * 0.5 - source.origin.y), 'TIR camera must mirror its origin across the waterline')
	assert(tir.basis.determinant() > 0.99, 'TIR camera basis must remain right-handed')
	print("Snell window and total-internal-reflection camera checks passed.")
	quit()
