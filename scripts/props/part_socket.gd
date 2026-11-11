class_name PartSocket
extends Node3D
## A socket for a replaceable component (here: a fuse cartridge).
##
## Starts with a dead part seated in it. The player pulls the dead part (which
## becomes loose junk), then carries a serviceable replacement over and seats
## it. Mounted with local +Z pointing out of the surface.

signal old_part_removed(socket: PartSocket, debris: Debris)
signal filled(socket: PartSocket)

enum State { BURNT, EMPTY, FILLED }

@export var part_id: StringName = &"fuse"
@export var part_name := "fuse cartridge"
@export var socket_name := "Fuse socket F1"

var state := State.BURNT
var interactable: Interactable

var _part_mesh: MeshInstance3D
var _stripe: MeshInstance3D


func _ready() -> void:
	_build()
	_apply_state()


func is_filled() -> bool:
	return state == State.FILLED


func _on_interacted(_player: Player) -> void:
	if state != State.BURNT:
		return
	state = State.EMPTY
	_apply_state()
	Sfx.play_at(&"clunk", global_position, -4.0, 1.5)
	var d := Debris.make_cylinder("Burnt fuse", 0.04, 0.16, Color(0.05, 0.045, 0.04), 2500.0, 0.2, 0.9)
	d.description = "Cooked. The casing is blistered and it smells of ozone even through the suit filters."
	get_tree().current_scene.add_child(d)
	d.global_transform = Transform3D(global_basis, to_global(Vector3(0, 0, 0.22)))
	d.linear_velocity = global_basis.z * 0.7
	d.angular_velocity = Vector3(1.5, 0.4, 0.8)
	old_part_removed.emit(self, d)


func _on_item_inserted(player: Player, item: RigidBody3D) -> void:
	if state != State.EMPTY:
		return
	player.interactor.drop()
	item.queue_free()
	state = State.FILLED
	_apply_state()
	Sfx.play_at(&"clunk", global_position, 0.0, 1.1)
	Sfx.play_ui(&"chime", -9.0, 1.2)
	filled.emit(self)


func _apply_state() -> void:
	_part_mesh.visible = state != State.EMPTY
	_stripe.visible = state == State.FILLED
	var mat := _part_mesh.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.04, 0.035, 0.03) if state == State.BURNT else Color(0.75, 0.76, 0.78)
	interactable.prompt = ""
	interactable.accepted_item = &""
	match state:
		State.BURNT:
			interactable.status = "FUSE BURNT OUT"
			interactable.prompt = "Pull burnt fuse"
		State.EMPTY:
			interactable.status = "EMPTY - needs a %s" % part_name
			interactable.accepted_item = part_id
			interactable.insert_prompt = "Seat %s" % part_name
		State.FILLED:
			interactable.status = "FUSE OK"


func _build() -> void:
	ShipKit.box(self, Vector3(0.16, 0.26, 0.05), Vector3(0, 0, 0.025), ShipMaterials.metal(Color(0.16, 0.17, 0.18), 0.6, 0.6), false)
	ShipKit.box(self, Vector3(0.1, 0.2, 0.01), Vector3(0, 0, 0.052), ShipMaterials.paint(Color(0.02, 0.02, 0.02), 1.0), false)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = 0.16
	mesh.radial_segments = 12
	_part_mesh = MeshInstance3D.new()
	_part_mesh.mesh = mesh
	_part_mesh.position = Vector3(0, 0, 0.07)
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.4
	mat.roughness = 0.5
	_part_mesh.material_override = mat
	add_child(_part_mesh)
	_stripe = ShipKit.box(self, Vector3(0.085, 0.03, 0.03), Vector3(0, 0, 0.095), ShipMaterials.glow(Color(1.0, 0.65, 0.15), 1.8), false)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 0.3, 0.14)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.z = 0.07
	var body := StaticBody3D.new()
	body.collision_layer = Layers.INTERACT
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)

	interactable = Interactable.new()
	interactable.display_name = socket_name
	interactable.interacted.connect(_on_interacted)
	interactable.item_inserted.connect(_on_item_inserted)
	body.add_child(interactable)
