class_name DepositContainer
extends Node3D
## An open-topped hopper that swallows loose objects of the categories it
## accepts. A magnetic intake pulls nearby debris in, so it works whether the
## player drops things into it under gravity or lobs them across the room in
## zero-g.

signal deposited(debris: Debris, container: DepositContainer)

enum Kind { WASTE, SALVAGE }

@export var kind := Kind.WASTE
@export var title := "WASTE RECLAIM"
@export var bin_size := Vector3(1.0, 0.9, 0.9)
@export var accepted: Array[Debris.Category] = [Debris.Category.JUNK]
@export var accent := Color(0.85, 0.55, 0.1)
@export var intake_radius := 1.2
@export var intake_force := 9.0

var count := 0

var _area: Area3D
var _counter: Label3D
var _mouth := Vector3.ZERO
var _reject_cooldown := {}


func _ready() -> void:
	_build()


func accepts(debris: Debris) -> bool:
	return debris.category in accepted


func _build() -> void:
	var s := bin_size
	var wall := 0.06
	var body_mat := ShipMaterials.paint(Color(0.2, 0.22, 0.24), 0.6)
	var accent_mat := ShipMaterials.paint(accent, 0.6)
	ShipKit.box(self, Vector3(s.x, wall, s.z), Vector3(0, wall * 0.5, 0), body_mat)
	ShipKit.box(self, Vector3(wall, s.y, s.z), Vector3(-s.x * 0.5 + wall * 0.5, s.y * 0.5, 0), body_mat)
	ShipKit.box(self, Vector3(wall, s.y, s.z), Vector3(s.x * 0.5 - wall * 0.5, s.y * 0.5, 0), body_mat)
	ShipKit.box(self, Vector3(s.x, s.y, wall), Vector3(0, s.y * 0.5, -s.z * 0.5 + wall * 0.5), body_mat)
	ShipKit.box(self, Vector3(s.x, s.y, wall), Vector3(0, s.y * 0.5, s.z * 0.5 - wall * 0.5), body_mat)
	# Rim.
	for side in [-1.0, 1.0]:
		ShipKit.box(self, Vector3(s.x + 0.08, 0.07, 0.1), Vector3(0, s.y, side * (s.z * 0.5 - 0.02)), accent_mat, false)
		ShipKit.box(self, Vector3(0.1, 0.07, s.z + 0.08), Vector3(side * (s.x * 0.5 - 0.02), s.y, 0), accent_mat, false)
	# Glowing intake at the bottom.
	var glow := ShipMaterials.glow(accent, 1.6)
	ShipKit.box(self, Vector3(s.x - 0.2, 0.02, s.z - 0.2), Vector3(0, wall + 0.02, 0), glow, false)

	ShipKit.stencil(self, title, Vector3(0, s.y * 0.62, s.z * 0.5), Vector3.BACK, 0.085, Color(0.9, 0.88, 0.8))
	_counter = ShipKit.readout(self, "", Vector3(0, s.y * 0.36, s.z * 0.5 + 0.008), 0.05, accent.lightened(0.3))
	_update_counter()

	_mouth = Vector3(0, s.y * 0.55, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(s.x - wall * 2.0, s.y + 0.25, s.z - wall * 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, s.y * 0.5 + 0.1, 0)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Layers.PROPS
	_area.monitorable = false
	_area.add_child(cs)
	add_child(_area)


func _physics_process(delta: float) -> void:
	for key in _reject_cooldown.keys():
		_reject_cooldown[key] -= delta
		if _reject_cooldown[key] <= 0.0:
			_reject_cooldown.erase(key)

	var mouth := to_global(_mouth)
	var top := to_global(Vector3(0, bin_size.y + 0.15, 0))
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d == null or d.is_carried or d.is_collected or not accepts(d):
			continue
		var offset := top - d.global_position
		var dist := offset.length()
		if dist < intake_radius and dist > 0.05:
			d.sleeping = false
			d.apply_central_force(offset / dist * intake_force * d.mass * (1.0 - dist / intake_radius))

	for body in _area.get_overlapping_bodies():
		var d := body as Debris
		if d == null or d.is_carried or d.is_collected:
			continue
		if accepts(d):
			count += 1
			_update_counter()
			Sfx.play_at(&"thunk", mouth, -2.0, randf_range(0.9, 1.1))
			deposited.emit(d, self)
			d.collect(mouth - Vector3(0, bin_size.y * 0.4, 0))
		elif not _reject_cooldown.has(d.get_instance_id()):
			_reject_cooldown[d.get_instance_id()] = 1.0
			d.linear_velocity = (global_basis.y * 2.2 + global_basis.z * 1.4)
			Sfx.play_at(&"buzz", mouth, -6.0)
			Game.notify("%s: %s rejected" % [title, d.item_name], &"warn")


func _update_counter() -> void:
	_counter.text = "%02d STOWED" % count
