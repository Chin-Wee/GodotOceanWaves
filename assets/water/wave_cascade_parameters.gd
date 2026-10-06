@tool
class_name WaveCascadeParameters extends Resource

signal scale_changed

## Denotes the distance the cascade's tile should cover (in meters).
@export var tile_length := Vector2(50, 50) :
	set(value): tile_length = value; should_generate_spectrum = true; _tile_length = [value.x, value.y]; scale_changed.emit()
@export_range(0, 2) var displacement_scale := 1.0 : # Note: This should be reduced as the number of cascades increases to avoid *too* much detail!
	set(value): displacement_scale = value; _displacement_scale = [displacement_scale]; scale_changed.emit()
## Horizontal FFT displacement: larger values sharpen crests without increasing wave height.
@export_range(0, 2) var choppiness := 1.0 :
	set(value): choppiness = value; _choppiness = [value]

@export_range(0, 2) var normal_scale := 1.0 : # Note: This should be reduced as the number of cascades increases to avoid *too* much detail!
	set(value): normal_scale = value; _normal_scale = [normal_scale]; scale_changed.emit()

## Denotes the average wind speed above the water (in meters per second). Increasing makes waves steeper and more 'chaotic'.
@export var wind_speed := 20.0 :
	set(value): wind_speed = max(0.0001, value); should_generate_spectrum = true; _wind_speed = [wind_speed]
@export_range(-360, 360) var wind_direction := 0.0 :
	set(value): wind_direction = value; should_generate_spectrum = true; _wind_direction = [deg_to_rad(value)]
## Denotes the distance from shoreline (in kilometers). Increasing makes waves steeper, but reduces their 'choppiness'.
@export var fetch_length := 550.0 :
	set(value): fetch_length = max(0.0001, value); should_generate_spectrum = true; _fetch_length = [fetch_length]
@export_range(0, 2) var swell := 0.8 :
	set(value): swell = value; should_generate_spectrum = true; _swell = [value]
## Modifies how much wind and swell affect the direction of the waves.
@export_range(0, 1) var spread := 0.2 :
	set(value): spread = value; should_generate_spectrum = true; _spread = [value]
## Modifies the attenuation of high frequency waves.
@export_range(0, 1) var detail := 1.0 :
	set(value): detail = value; should_generate_spectrum = true; _detail = [value]

## Modifies how steep a wave needs to be before foam can accumulate.
@export_range(0, 2) var whitecap := 0.5 : # Lower the Jacobian threshold for sparser foam; raise it for more breaking.
	set(value): whitecap = value; _whitecap = [value]

@export_range(0, 10) var foam_amount := 5.0 :
	set(value): foam_amount = value; _foam_amount = [value]
@export_range(0, 5, 0.01) var foam_decay := 0.35 :
	set(value): foam_decay = value; _foam_decay = [value]
@export_range(0, 10, 0.01) var foam_dispersion := 3.0 :
	set(value): foam_dispersion = value; _foam_dispersion = [value]

var spectrum_seed := Vector2i.ZERO
var should_generate_spectrum := true

var time : float

# References to wave cascade parameters (for imgui). The actual parameters won't
# reflect these values unless manually synced!
var _tile_length := [tile_length.x, tile_length.y]
var _displacement_scale := [displacement_scale]
var _choppiness := [choppiness]
var _normal_scale := [normal_scale]
var _wind_speed := [wind_speed]
var _wind_direction := [deg_to_rad(wind_direction)]
var _fetch_length := [fetch_length]
var _swell := [swell]
var _detail := [detail]
var _spread := [spread]
var _whitecap := [whitecap]
var _foam_amount := [foam_amount]
var _foam_decay := [foam_decay]
var _foam_dispersion := [foam_dispersion]
