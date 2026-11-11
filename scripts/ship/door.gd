class_name Door
extends Node3D
## Heavy two-leaf sliding bulkhead door. The node sits on the floor at the
## centre of the doorway, with local Z along the passage.
##
## * Unpowered doors must be cranked by hand (hold interact); powered doors
##   run on their motors.
## * A closed door will not open against a pressure difference: the pressure
##   holds the leaves in their seals. Equalise the two compartments first.
## * While open, the door lets air flow between its two compartments.

signal moved(open: bool)

const PRESSURE_LOCK_KPA := 10.0
const MANUAL_SPEED := 0.45
const MOTOR_SPEED := 1.3
const CRANK_HOLD := 1.2

@export var door_name := "Bulkhead door"
@export var width := 1.6
@export var height := 2.3
@export var thickness := 0.2

var compartment_a: Compartment
var compartment_b: Compartment
var powered := false
## 0 = shut, 1 = fully open.
var open_fraction := 0.0
var target_open := 0.0

var _leaves: Array[AnimatableBody3D] = []
var _interactable: Interactable
var _lamps: Array[StandardMaterial3D] = []
var _motor: AudioStreamPlayer3D
var _ratchet_timer := 0.0


func _ready() -> void:
	_build()
	_apply_position()


func is_open() -> bool:
	return open_fraction > 0.9


func get_pressure_delta() -> float:
	if compartment_a == null or compartment_b == null:
		return 0.0
	return absf(compartment_a.pressure - compartment_b.pressure)


## Starts the door partly open and stuck there (it still cranks normally).
func set_ajar(fraction: float) -> void:
	open_fraction = fraction
	target_open = fraction
	if is_inside_tree():
		_apply_position()


func open() -> void:
	target_open = 1.0


func close() -> void:
	target_open = 0.0


func _is_pressure_locked() -> bool:
	return open_fraction < 0.05 and get_pressure_delta() > PRESSURE_LOCK_KPA


func _blocked(_player: Player) -> String:
	if target_open < 0.5 and _is_pressure_locked():
		return "%s: pressure lock (%d kPa across the seals). Equalise first." % [door_name, int(get_pressure_delta())]
	return ""


func _on_interacted(_player: Player) -> void:
	target_open = 0.0 if target_open > 0.5 else 1.0
	Sfx.play_at(&"clunk", global_position + Vector3(0, 1.2, 0), -3.0, 0.8)


func _physics_process(delta: float) -> void:
	var opening := target_open > 0.5
	_interactable.hold_time = 0.0 if powered else CRANK_HOLD
	if powered:
		_interactable.prompt = "Close door" if opening else "Open door"
	else:
		_interactable.prompt = "Crank door shut" if opening else "Crank door open"
	_interactable.status = _status_text()

	var lamp_color := Color(0.3, 1.0, 0.45) if powered else Color(1.0, 0.65, 0.15)
	if _is_pressure_locked():
		lamp_color = Color(1.0, 0.15, 0.1)
	for lamp in _lamps:
		lamp.emission = lamp_color

	if is_equal_approx(open_fraction, target_open):
		if _motor.playing:
			_motor.stop()
		return
	var was_open := is_open()
	open_fraction = move_toward(open_fraction, target_open, (MOTOR_SPEED if powered else MANUAL_SPEED) * delta)
	_apply_position()
	if powered:
		if not _motor.playing:
			_motor.play()
	else:
		_ratchet_timer -= delta
		if _ratchet_timer <= 0.0:
			_ratchet_timer = 0.11
			Sfx.play_at(&"ratchet", _motor.global_position, -4.0, randf_range(0.85, 1.1))
	if is_equal_approx(open_fraction, target_open):
		Sfx.play_at(&"clunk", _motor.global_position, 0.0, 0.7)
		moved.emit(is_open())
	elif was_open != is_open():
		moved.emit(is_open())


func _status_text() -> String:
	if _is_pressure_locked():
		return "PRESSURE LOCK  %d kPa" % int(get_pressure_delta())
	if open_fraction > 0.05 and open_fraction < 0.9 and is_equal_approx(open_fraction, target_open):
		return "JAMMED PARTLY OPEN"
	return "MOTORS LIVE" if powered else "NO POWER - MANUAL CRANK"


func _apply_position() -> void:
	var travel := (width * 0.5 - 0.07) * open_fraction
	_leaves[0].position.x = -width * 0.25 - travel
	_leaves[1].position.x = width * 0.25 + travel


func _build() -> void:
	var leaf_mat := ShipMaterials.hull(Color(0.33, 0.35, 0.37), Vector2(0.8, 0.77), 0.7, 0.6, 0.5)
	var leaf_size := Vector3(width * 0.5, height, thickness)
	_interactable = Interactable.new()
	_interactable.display_name = door_name
	_interactable.blocked_check = _blocked
	_interactable.interacted.connect(_on_interacted)
	add_child(_interactable)

	for side in [-1.0, 1.0]:
		var leaf := AnimatableBody3D.new()
		leaf.collision_layer = Layers.WORLD
		leaf.collision_mask = 0
		leaf.sync_to_physics = false
		leaf.position = Vector3(side * width * 0.25, height * 0.5, 0)
		var mesh := BoxMesh.new()
		mesh.size = leaf_size
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = leaf_mat
		leaf.add_child(mi)
		var shape := BoxShape3D.new()
		shape.size = leaf_size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		leaf.add_child(cs)
		# Hazard band and a grab bar on both faces.
		for face in [-1.0, 1.0]:
			var band := ShipKit.box(leaf, Vector3(leaf_size.x, 0.16, 0.012), Vector3(0, -height * 0.5 + 0.9, face * (thickness * 0.5 + 0.004)), ShipMaterials.hazard(), false)
			band.name = "Band"
			ShipKit.box(leaf, Vector3(0.05, 0.5, 0.05), Vector3(-side * (leaf_size.x * 0.5 - 0.12), 0.1, face * (thickness * 0.5 + 0.03)), ShipMaterials.metal(Color(0.7, 0.7, 0.72), 0.3), false)
		add_child(leaf)
		_interactable.link(leaf)
		_leaves.append(leaf)

	# Indicator lamps above the doorway, one per side.
	for face in [-1.0, 1.0]:
		var lamp := ShipMaterials.glow(Color(1.0, 0.65, 0.15), 2.4)
		_lamps.append(lamp)
		ShipKit.box(self, Vector3(0.5, 0.06, 0.04), Vector3(0, height + 0.14, face * 0.23), lamp, false)

	_motor = Sfx.make_loop(&"door_loop", self, -6.0)
	_motor.position = Vector3(0, height * 0.6, 0)
