class_name ShipLight
extends Node3D
## A light fixture wired to one of the ship's lighting circuits. Mounted with
## local +Z pointing out of the surface.
##
## The ship sets a mode; the fixture handles the look: staggered warm-up when
## power returns, erratic flicker on a faulted circuit, and a slow red pulse
## for battery-backed emergency lamps.

enum Mode { OFF, ON, FAULT, EMERGENCY }

@export var circuit: StringName = &"main"
## Battery-backed emergency lamp: lit only while main lighting is down.
@export var is_emergency := false
@export var color := Color(1.0, 0.94, 0.84)
@export var energy := 2.0
@export var light_range := 8.5
@export var cast_shadows := true
@export var fixture_size := Vector3(0.9, 0.2, 0.06)

var mode := Mode.OFF

var _light: OmniLight3D
var _mat: StandardMaterial3D
var _level := 0.0
var _target := 0.0
var _delay := 0.0
var _warmup := 0.0
var _flicker_timer := 0.0
var _phase := 0.0


func _ready() -> void:
	_phase = randf() * TAU
	_mat = ShipMaterials.glow(color, 0.0)
	_mat.albedo_color = Color(0.25, 0.25, 0.24)
	ShipKit.box(self, fixture_size, Vector3(0, 0, fixture_size.z * 0.5), _mat, false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ShipKit.box(self, Vector3(fixture_size.x + 0.06, fixture_size.y + 0.06, 0.02), Vector3(0, 0, 0.01), ShipMaterials.metal(Color(0.12, 0.12, 0.13), 0.6), false)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = light_range
	_light.omni_attenuation = 1.1
	_light.shadow_enabled = cast_shadows
	_light.shadow_bias = 0.06
	_light.position.z = 0.3
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)
	_apply(0.0)


## `delay` staggers the switch-on so power visibly spreads through the ship.
func set_mode(new_mode: Mode, delay := 0.0) -> void:
	if new_mode == mode:
		return
	if new_mode == Mode.ON:
		_delay = delay
		_warmup = 0.5
	mode = new_mode


func _process(delta: float) -> void:
	match mode:
		Mode.OFF:
			_target = 0.0
		Mode.EMERGENCY:
			_target = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.0021 + _phase)
		Mode.FAULT:
			_flicker_timer -= delta
			if _flicker_timer <= 0.0:
				var lit := randf() < 0.3
				_target = randf_range(0.35, 1.0) if lit else randf_range(0.0, 0.04)
				_flicker_timer = randf_range(0.03, 0.2) if lit else randf_range(0.1, 1.1)
		Mode.ON:
			if _delay > 0.0:
				_delay -= delta
				_target = 0.0
			elif _warmup > 0.0:
				_warmup -= delta
				_target = 1.0 if randf() < 0.6 else 0.15
			else:
				_target = 1.0
	var rate := 40.0 if mode == Mode.FAULT or _warmup > 0.0 else 7.0
	var next := move_toward(_level, _target, rate * delta)
	if not is_equal_approx(next, _level):
		_apply(next)


func _apply(level: float) -> void:
	_level = level
	_light.light_energy = energy * level
	_light.visible = level > 0.01
	_mat.emission_energy_multiplier = level * 3.2
