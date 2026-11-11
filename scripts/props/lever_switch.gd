class_name LeverSwitch
extends Node3D
## A chunky two-position lever. Mounted with local +Z pointing out of the
## surface. Knows nothing about what it controls: listen to `toggled`, and set
## `lock_check` to refuse operation with a reason.

signal toggled(on: bool)

@export var label := "Switch"
@export var prompt_on := "Switch off"
@export var prompt_off := "Switch on"
@export_multiline var note := ""

var is_on := false
var interactable: Interactable
## Optional `func(player) -> String`; non-empty text blocks the lever.
var lock_check := Callable():
	set(value):
		lock_check = value
		if interactable:
			interactable.blocked_check = value

var _pivot: Node3D
var _lamp: StandardMaterial3D

const ANGLE_OFF := deg_to_rad(48.0)
const ANGLE_ON := deg_to_rad(132.0)


func _ready() -> void:
	_build()
	_refresh()


## Sets the lever without the interaction side effects (no signal unless asked).
func set_on(value: bool, emit := false, animate := true) -> void:
	if value == is_on:
		return
	is_on = value
	_refresh()
	var target := ANGLE_ON if is_on else ANGLE_OFF
	if animate and is_inside_tree():
		var tween := create_tween()
		tween.tween_property(_pivot, "rotation:x", target, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play_at(&"clunk", global_position, -1.0, 1.15 if is_on else 0.95)
	else:
		_pivot.rotation.x = target
	if emit:
		toggled.emit(is_on)


func _on_interacted(_player: Player) -> void:
	set_on(not is_on, true)


func _refresh() -> void:
	interactable.prompt = prompt_on if is_on else prompt_off
	_lamp.emission = Color(0.3, 1.0, 0.45) if is_on else Color(1.0, 0.25, 0.15)
	_lamp.albedo_color = _lamp.emission.darkened(0.6)


func _build() -> void:
	ShipKit.box(self, Vector3(0.2, 0.34, 0.05), Vector3(0, 0, 0.025), ShipMaterials.metal(Color(0.17, 0.18, 0.19), 0.55, 0.7), false)
	ShipKit.box(self, Vector3(0.05, 0.24, 0.012), Vector3(0, 0, 0.054), ShipMaterials.paint(Color(0.02, 0.02, 0.02), 1.0), false)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0, 0.05)
	_pivot.rotation.x = ANGLE_OFF
	add_child(_pivot)
	ShipKit.box(_pivot, Vector3(0.03, 0.2, 0.03), Vector3(0, 0.1, 0), ShipMaterials.metal(Color(0.6, 0.62, 0.65), 0.3, 0.9), false)
	ShipKit.box(_pivot, Vector3(0.12, 0.05, 0.05), Vector3(0, 0.21, 0), ShipMaterials.paint(Color(0.75, 0.1, 0.06), 0.5), false)

	_lamp = ShipMaterials.glow(Color(1.0, 0.25, 0.15), 2.2)
	ShipKit.box(self, Vector3(0.035, 0.035, 0.02), Vector3(0, 0.215, 0.03), _lamp, false)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.26, 0.46, 0.28)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.z = 0.14
	var body := StaticBody3D.new()
	body.collision_layer = Layers.INTERACT
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)

	interactable = Interactable.new()
	interactable.display_name = label
	interactable.description = note
	interactable.blocked_check = lock_check
	interactable.interacted.connect(_on_interacted)
	body.add_child(interactable)
