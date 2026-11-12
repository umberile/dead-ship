class_name HullBreach
extends Node3D
## A hole through the hull. Mounted on a wall with local +Z pointing into the
## compartment.
##
## The sealer closes it sector by sector: the player has to work around the rim
## and the sealant visibly creeps inward wherever the tool is held. While any
## of it is open the compartment leaks (see ShipSystems), air visibly streams
## out, and loose objects get tugged toward the hole.

signal sealed(breach: HullBreach)

const SHADER := preload("res://shaders/breach.gdshader")
const SECTORS := 12
const AUTO_FINISH := 0.94

@export var radius := 0.75
@export var seal_rate := 1.25
@export var pull_strength := 5.0

var is_sealed := false
var seal_fraction := 0.0
## Pressure of the compartment this breach vents (set by the ship each tick).
var compartment_pressure := 0.0
var interactable: Interactable

var _sectors := PackedFloat32Array()
var _material: ShaderMaterial
var _heat := 0.0
var _vent: CPUParticles3D
var _hiss: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"breach")
	_sectors.resize(SECTORS)
	_sectors.fill(0.0)

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 2
	_material.set_shader_parameter(&"sectors", _sectors)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(radius, radius) * 2.0
	var quad := MeshInstance3D.new()
	quad.mesh = mesh
	quad.material_override = _material
	quad.position.z = 0.008
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)

	# Torn plating curled inward around the rim.
	var torn := ShipMaterials.metal(Color(0.12, 0.12, 0.13), 0.7, 0.7)
	for i in 9:
		var a := TAU * i / 9.0 + 0.3 * sin(i * 2.7)
		var r := radius * (0.56 + 0.07 * sin(i * 1.9))
		var petal := ShipKit.box(self, Vector3(0.2, 0.012, 0.16 + 0.05 * sin(i * 3.1)), Vector3(cos(a) * r, sin(a) * r, 0.05), torn, false)
		petal.basis = Basis(Vector3.BACK, a + PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(55.0 + 14.0 * sin(i * 4.3)))

	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 1.5, radius * 1.5, 0.08)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.z = 0.05
	var body := StaticBody3D.new()
	body.collision_layer = Layers.INTERACT
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)

	interactable = Interactable.new()
	interactable.display_name = "Hull breach"
	interactable.description = "Punched clean through the pressure hull. Edges curl inward: something hit from outside."
	interactable.tool_id = &"sealer"
	interactable.tool_verb = "Seal"
	interactable.needs_work = true
	interactable.progress = 0.0
	interactable.status = "OPEN TO VACUUM"
	interactable.tool_applied.connect(_on_tool_applied)
	body.add_child(interactable)

	_build_vent()
	_hiss = Sfx.make_loop(&"hiss_loop", self, -40.0, 5.0)
	_hiss.play()


## How much of the hole is still open, 0..1. Drives the leak rate.
func get_leak_factor() -> float:
	return 0.0 if is_sealed else 1.0 - seal_fraction


func _on_tool_applied(tool: Tool, pos: Vector3, _normal: Vector3, delta: float) -> void:
	apply_sealant(pos, seal_rate * tool.power * delta)


## Lays sealant on the part of the rim nearest `world_pos`.
func apply_sealant(world_pos: Vector3, amount: float) -> void:
	if is_sealed:
		return
	var lp := to_local(world_pos)
	var fa := (atan2(lp.y, lp.x) / TAU + 0.5) * SECTORS
	# Aiming at the middle of the hole spreads the bead more thinly all round.
	var centre := 1.0 - clampf(Vector2(lp.x, lp.y).length() / (radius * 0.35), 0.0, 1.0)
	var reach := lerpf(1.7, SECTORS * 0.5, centre)
	for i in SECTORS:
		var d := absf(fposmod(fa - i + SECTORS * 0.5, float(SECTORS)) - SECTORS * 0.5)
		var w := maxf(0.0, 1.0 - d / reach) * lerpf(1.0, 0.45, centre)
		if w > 0.0:
			_sectors[i] = minf(1.0, _sectors[i] + amount * w)
	_heat = 1.0
	_refresh()


## Instantly closes the breach (used by tests and debug tooling).
func seal_all() -> void:
	if is_sealed:
		return
	_sectors.fill(1.0)
	_refresh()


func _refresh() -> void:
	var sum := 0.0
	for v in _sectors:
		sum += v
	seal_fraction = sum / SECTORS
	if seal_fraction >= AUTO_FINISH:
		_sectors.fill(1.0)
		seal_fraction = 1.0
	_material.set_shader_parameter(&"sectors", _sectors)
	interactable.progress = seal_fraction
	interactable.status = "SEALING  %d%%" % int(seal_fraction * 100.0)
	if seal_fraction >= 1.0:
		is_sealed = true
		interactable.needs_work = false
		interactable.display_name = "Hull patch"
		interactable.description = "Cured sealant over the breach. Ugly, but it holds pressure."
		interactable.status = "SEALED"
		Sfx.play_at(&"clunk", global_position, 0.0, 1.2)
		Sfx.play_ui(&"chime", -6.0)
		sealed.emit(self)


func _physics_process(delta: float) -> void:
	_heat = maxf(0.0, _heat - delta * 0.9)
	_material.set_shader_parameter(&"heat", _heat)

	var venting := clampf(compartment_pressure / 20.0, 0.0, 1.0) * get_leak_factor()
	_vent.emitting = venting > 0.02
	_vent.speed_scale = 0.6 + venting
	_hiss.volume_db = lerpf(_hiss.volume_db, linear_to_db(maxf(venting, 0.001)) - 2.0, minf(1.0, delta * 6.0))
	if venting <= 0.02:
		return
	# Escaping air drags loose objects toward the hole.
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d == null or d.is_carried or d.is_collected:
			continue
		var offset := global_position - d.global_position
		var dist := offset.length()
		if dist < 7.0 and dist > 0.4:
			d.sleeping = false
			d.apply_central_force(offset / dist * pull_strength * venting * d.mass / (1.0 + dist * dist * 0.25))


func _build_vent() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = mat
	_vent = CPUParticles3D.new()
	_vent.mesh = quad
	_vent.emitting = false
	_vent.amount = 70
	_vent.lifetime = 0.7
	_vent.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_vent.emission_sphere_radius = 1.1
	_vent.gravity = Vector3.ZERO
	_vent.initial_velocity_min = 0.0
	_vent.initial_velocity_max = 0.2
	_vent.radial_accel_min = -9.0
	_vent.radial_accel_max = -6.0
	_vent.scale_amount_min = 0.5
	_vent.scale_amount_max = 1.6
	_vent.color = Color(0.8, 0.88, 0.95, 0.35)
	_vent.position.z = 0.15
	_vent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_vent)
