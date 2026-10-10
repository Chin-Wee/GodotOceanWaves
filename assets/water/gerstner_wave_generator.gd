extends "res://assets/water/wave_generator.gd"

# Architecture reference: Diablo IV uses Gerstner waves for deep water (GDC 2024).
# This variant keeps its existing spectrum, output maps, unpack and foam feedback.
# https://gdcvault.com/play/1034490/Technical-Artist-Summit-H2O-in
const MODE_COUNT := 120
const MODE_RECORD_SIZE := MODE_COUNT * 2

func init_gpu(num_cascades : int) -> void:
	super.init_gpu(num_cascades)
	var select_shader := context.load_shader('./assets/shaders/compute/gerstner_mode_select.glsl')
	var energy_shader := context.load_shader('./assets/shaders/compute/gerstner_energy.glsl')
	var energy_reduce_shader := context.load_shader('./assets/shaders/compute/gerstner_energy_reduce.glsl')
	var synthesis_shader := context.load_shader('./assets/shaders/compute/gerstner_synthesis.glsl')
	descriptors[&'gerstner_modes'] = context.create_storage_buffer(num_cascades * MODE_RECORD_SIZE * 4)
	var energy_partial_count := (map_size / 16) * (map_size / 16)
	descriptors[&'gerstner_energy_partials'] = context.create_storage_buffer(num_cascades * energy_partial_count * 4)
	descriptors[&'gerstner_energy'] = context.create_storage_buffer(num_cascades * 4)
	var select_set := context.create_descriptor_set([descriptors[&'spectrum'], descriptors[&'gerstner_modes']], select_shader)
	var energy_set := context.create_descriptor_set([descriptors[&'spectrum'], descriptors[&'gerstner_energy_partials']], energy_shader)
	var energy_reduce_set := context.create_descriptor_set([descriptors[&'gerstner_energy_partials'], descriptors[&'gerstner_energy']], energy_reduce_shader)
	var synthesis_set := context.create_descriptor_set([descriptors[&'spectrum'], descriptors[&'fft_buffer'], descriptors[&'gerstner_modes'], descriptors[&'gerstner_energy']], synthesis_shader)
	pipelines[&'gerstner_mode_select'] = context.create_pipeline([1, 1, 1], [select_set], select_shader)
	pipelines[&'gerstner_energy'] = context.create_pipeline([map_size/16, map_size/16, 1], [energy_set], energy_shader)
	pipelines[&'gerstner_energy_reduce'] = context.create_pipeline([1, 1, 1], [energy_reduce_set], energy_reduce_shader)
	pipelines[&'gerstner_synthesis'] = context.create_pipeline([map_size/16, map_size/16, 1], [synthesis_set], synthesis_shader)

func _update(compute_list : int, cascade_index : int, parameters : Array[WaveCascadeParameters]) -> void:
	var params := parameters[cascade_index]
	if params.should_generate_spectrum:
		var alpha := JONSWAP_alpha(params.wind_speed, params.fetch_length * 1e3)
		var omega := JONSWAP_peak_angular_frequency(params.wind_speed, params.fetch_length * 1e3)
		pipelines[&'spectrum_compute'].call(context, compute_list, RenderingContext.create_push_constant([params.spectrum_seed.x, params.spectrum_seed.y, params.tile_length.x, params.tile_length.y, alpha, omega, params.wind_speed, deg_to_rad(params.wind_direction), DEPTH, params.swell, params.detail, params.spread, cascade_index]))
		params.should_generate_spectrum = false
		context.compute_list_add_barrier(compute_list)
		pipelines[&'gerstner_mode_select'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, 0.0, params.tile_length.x, params.tile_length.y, deg_to_rad(params.wind_direction)]))
		context.compute_list_add_barrier(compute_list)

	var partial_count := (map_size / 16) * (map_size / 16)
	pipelines[&'gerstner_energy'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, params.time, params.tile_length.x, params.tile_length.y, DEPTH]))
	context.compute_list_add_barrier(compute_list)
	pipelines[&'gerstner_energy_reduce'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, partial_count]))
	context.compute_list_add_barrier(compute_list)
	pipelines[&'gerstner_synthesis'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, params.time, params.tile_length.x, params.tile_length.y, DEPTH, params.choppiness]))
	context.compute_list_add_barrier(compute_list)
	pipelines[&'fft_unpack'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, params.whitecap]))
	context.compute_list_add_barrier(compute_list)
	var foam_feedback_key := &'foam_feedback_a_to_b' if foam_state_index == 0 else &'foam_feedback_b_to_a'
	pipelines[foam_feedback_key].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, pass_delta, params.foam_amount * 7.5, params.foam_decay, params.foam_dispersion]))
	context.compute_list_add_barrier(compute_list)
	foam_state_index = 1 - foam_state_index
	foam_states_texture.texture_rd_rid = descriptors[&'foam_state_a' if foam_state_index == 0 else &'foam_state_b'].rid
	RenderingServer.global_shader_parameter_set(&'foam_states', foam_states_texture)
