extends SceneTree

const REFLECTION := preload("res://assets/water/planar_reflection.gd")

func _initialize() -> void:
	var critical_cosine := sqrt(1.0 - 1.0 / (1.333 * 1.333))
	assert(REFLECTION.snell_discriminant(1.0) > 0.0)
	assert(REFLECTION.snell_discriminant(critical_cosine - 0.01) < 0.0)
	assert(REFLECTION.snell_discriminant(critical_cosine + 0.01) > 0.0)
	print("Snell window critical-angle check passed.")
	quit()
