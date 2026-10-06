extends SceneTree

const SEA_PRESETS := preload('res://assets/water/sea_presets.gd')

func _initialize() -> void:
	var unpack := FileAccess.get_file_as_string('res://assets/shaders/compute/fft_unpack.glsl')
	var feedback := FileAccess.get_file_as_string('res://assets/shaders/compute/foam_feedback.glsl')
	for shader_path in ['res://assets/shaders/compute/fft_unpack.glsl', 'res://assets/shaders/compute/foam_feedback.glsl']:
		var shader_file := load(shader_path) as RDShaderFile
		assert(shader_file != null and shader_file.get_spirv().get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE).size() > 0)
	assert(unpack.contains('float breaking = max(0.0, whitecap - jacobian);'))
	assert(unpack.contains('float peak_mask = chop_length / (1.0 + chop_length);'))
	assert(not unpack.contains('foam_crest_bias') and not unpack.contains('tip_coverage') and not unpack.contains('float crest'))
	assert(not unpack.contains('normal_map, id).a'))
	assert(feedback.contains('R stores persistent foam; G stores the decaying fresh Jacobian injection.'))
	assert(feedback.contains('imageStore(foam_next, id, vec4(total, fresh, 0.0, 1.0));'))
	assert(feedback.contains('if (uint(id.z) != active_cascade)'))
	assert(SEA_PRESETS.SEA_STATES.size() == 3 and SEA_PRESETS.SEA_STATES[0]['foam_amount'] == 0.0)
	for state in SEA_PRESETS.SEA_STATES:
		for key in ['wave_amplitude_scale', 'choppiness_scale', 'whitecap', 'foam_amount', 'foam_decay', 'foam_dispersion', 'foam_texture_blend']:
			assert(state.has(key), '%s sea state is missing %s' % [state['name'], key])
		assert(state['foam_texture_blend'] >= 0.0 and state['foam_texture_blend'] <= 1.0)

	assert(is_equal_approx(_breaking(-0.25, 0.35), 0.6))
	assert(_breaking(0.5, 0.35) == 0.0)
	assert(_peak_mask(0.0) == 0.0)
	assert(is_equal_approx(_peak_mask(1.0), 0.5))
	assert(_peak_mask(4.0) < 1.0)
	var total := _feedback(0.4, 0.5, 0.75, 0.3, 0.1)
	assert(total > 0.4 and total <= 1.0)
	assert(_feedback(0.4, 0.0, 0.75, 0.3, 0.1) < 0.4)
	print('PASS: Jacobian-only injection, bounded choppiness peak mask, RG feedback channels')
	quit()

static func _breaking(jacobian: float, threshold: float) -> float:
	return maxf(0.0, threshold - jacobian)

static func _peak_mask(choppiness_offset: float) -> float:
	return choppiness_offset / (1.0 + choppiness_offset)

static func _feedback(previous_total: float, breaking: float, growth_rate: float, decay_rate: float, delta: float) -> float:
	var injection := clampf(breaking * growth_rate * delta, 0.0, 1.0)
	return clampf(previous_total * exp(-decay_rate * delta) + injection, 0.0, 1.0)
