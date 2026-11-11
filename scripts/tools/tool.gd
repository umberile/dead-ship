class_name Tool
extends Node3D
## Base class for a handheld tool.
##
## A tool does not know what it is working on: the Interactor finds a target
## whose Interactable accepts this tool's `tool_id` and forwards the work to it.
## The tool itself only owns its view model and its work feedback (particles,
## light, sound). New tools are added by subclassing and overriding the
## `_build_model` / `_configure_*` hooks.

@export var tool_id: StringName = &""
@export var tool_name := "Tool"
## Work-rate multiplier passed on to targets (future upgrades hook in here).
@export var power := 1.0

var working := false

var _model: Node3D
var _fx: Node3D
var _particles: CPUParticles3D
var _light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _rest := Vector3(0.3, -0.25, -0.58)
var _equip_t := 0.0
var _time := 0.0
var _light_energy := 0.0


func _ready() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_build_model(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_fx()
	visible = false


# --- Hooks for subclasses ----------------------------------------------------

func _build_model(_root: Node3D) -> void:
	pass


func _configure_particles(_p: CPUParticles3D, _mat: StandardMaterial3D) -> void:
	pass


func _loop_sound() -> StringName:
	return &""


func _work_light() -> Color:
	return Color(0, 0, 0, 0)  # alpha 0 = no light


## Extra per-frame model motion while working.
func _animate_work(_model_root: Node3D, _t: float) -> void:
	pass


# --- Shared behaviour --------------------------------------------------------

func equip() -> void:
	visible = true
	_equip_t = 0.0


func unequip() -> void:
	set_working(false, Vector3.ZERO, Vector3.UP)
	visible = false


func set_working(on: bool, pos: Vector3, normal: Vector3) -> void:
	if on:
		_fx.global_position = pos + normal * 0.04
		_particles.direction = normal
	if on == working:
		return
	working = on
	_particles.emitting = on
	if _light:
		_light.visible = on
	if _audio and _audio.stream:
		if on:
			_audio.pitch_scale = randf_range(0.95, 1.05)
			_audio.play()
		else:
			_audio.stop()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_equip_t = minf(1.0, _equip_t + delta * 5.0)
	var raise := (1.0 - _equip_t) * (1.0 - _equip_t)
	var pos := _rest + Vector3(0, -0.35 * raise, 0)
	pos.y += sin(_time * 1.3) * 0.004
	_model.rotation = Vector3.ZERO
	if working:
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.0025
		pos.z -= 0.05
		_animate_work(_model, _time)
		if _light:
			_light.light_energy = _light_energy * randf_range(0.55, 1.0)
	_model.position = _model.position.lerp(pos, minf(1.0, delta * 14.0))


func _build_fx() -> void:
	_fx = Node3D.new()
	_fx.name = "WorkFx"
	_fx.top_level = true
	add_child(_fx)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	quad.material = mat

	_particles = CPUParticles3D.new()
	_particles.mesh = quad
	_particles.emitting = false
	_particles.amount = 24
	_particles.lifetime = 0.45
	_particles.local_coords = false
	_particles.spread = 55.0
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 0.6
	_particles.initial_velocity_max = 1.8
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	_particles.color_ramp = ramp
	_configure_particles(_particles, mat)
	_fx.add_child(_particles)

	var light_color := _work_light()
	if light_color.a > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = Color(light_color.r, light_color.g, light_color.b)
		_light_energy = light_color.a
		_light.light_energy = _light_energy
		_light.omni_range = 3.5
		_light.visible = false
		_light.position = Vector3(0, 0, 0)
		_fx.add_child(_light)

	if _loop_sound() != &"":
		_audio = Sfx.make_loop(_loop_sound(), _fx, -5.0)


## Small helper for building primitive view models.
static func part(root: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot_deg := Vector3.ZERO,
		emission := 0.0, metallic := 0.3, roughness := 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	mi.material_override = m
	root.add_child(mi)
	return mi


static func box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl_mesh(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	return m
