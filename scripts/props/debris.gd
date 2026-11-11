class_name Debris
extends RigidBody3D
## A loose physical object the player can carry: junk to dispose of, salvage
## worth recovering, or a spare part needed for a repair.
##
## Gravity is not handled here. The ship's gravity Area3D overrides gravity for
## every body inside it, so debris floats or falls with the ship's systems.

enum Category { JUNK, SALVAGE, PART }

signal collected(debris: Debris)

@export var item_name := "Debris"
@export_multiline var description := ""
@export var category := Category.JUNK
## Recovery value in credits (salvage only).
@export var value := 0
## Identifies parts for sockets, e.g. &"fuse".
@export var item_id: StringName = &""

var is_carried := false
var is_collected := false
var interactable: Interactable
var visual: Node3D
var home := Transform3D.IDENTITY

var _impact_cooldown := 0.0


func _init() -> void:
	collision_layer = Layers.PROPS
	collision_mask = Layers.WORLD | Layers.PROPS | Layers.PLAYER
	contact_monitor = true
	max_contacts_reported = 3
	continuous_cd = true
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)


func _ready() -> void:
	add_to_group(&"debris")
	home = global_transform
	interactable = Interactable.new()
	interactable.display_name = item_name
	interactable.description = description if description != "" else _default_description()
	interactable.prompt = "Pick up"
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)


## Counts toward the contract's cleanup total?
func is_cleanup_item() -> bool:
	return category != Category.PART


## Gives the object a slow drift and tumble, as if it has been floating for weeks.
func set_adrift(strength := 1.0) -> void:
	linear_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06 * strength
	angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.35 * strength


## Pulls the object into a container and removes it from the world.
func collect(into: Vector3) -> void:
	if is_collected:
		return
	is_collected = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	interactable.enabled = false
	remove_from_group(&"debris")
	collected.emit(self)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", into, 0.22)
	tween.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.22)
	tween.chain().tween_callback(queue_free)


func _on_interacted(player: Player) -> void:
	player.interactor.pick_up(self)


func _on_body_entered(_other: Node) -> void:
	if _impact_cooldown > 0.0 or is_collected:
		return
	var speed := linear_velocity.length()
	if speed < 0.7:
		return
	_impact_cooldown = 0.18
	Sfx.play_at(&"impact", global_position, clampf(-22.0 + speed * 4.0, -22.0, -3.0),
			randf_range(0.7, 1.25) * clampf(2.2 / (0.6 + mass * 0.4), 0.6, 1.6))


func _default_description() -> String:
	match category:
		Category.SALVAGE:
			return "Recoverable equipment. Stow it in a salvage locker."
		Category.PART:
			return "Serviceable ship component."
	return "Scrap. Feed it to a waste reclaimer."


# --- Builders ------------------------------------------------------------------

static func make_box(item: String, size: Vector3, color: Color, density := 400.0,
		metallic := 0.5, roughness := 0.6) -> Debris:
	var d := Debris.new()
	d.item_name = item
	d.name = item.validate_node_name()
	var shape := BoxShape3D.new()
	shape.size = size
	d._add_shape(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	d.add_visual(mesh, Vector3.ZERO, color, metallic, roughness)
	d.mass = clampf(size.x * size.y * size.z * density, 0.3, 40.0)
	return d


static func make_cylinder(item: String, radius: float, height: float, color: Color, density := 400.0,
		metallic := 0.5, roughness := 0.55) -> Debris:
	var d := Debris.new()
	d.item_name = item
	d.name = item.validate_node_name()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	d._add_shape(shape)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	d.add_visual(mesh, Vector3.ZERO, color, metallic, roughness)
	d.mass = clampf(PI * radius * radius * height * density, 0.3, 40.0)
	return d


## Adds an extra decorative mesh (no collision) to the object.
func add_visual(mesh: Mesh, pos: Vector3, color: Color, metallic := 0.5, roughness := 0.6,
		emission := 0.0, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	visual.add_child(mi)
	return mi


func _add_shape(shape: Shape3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
