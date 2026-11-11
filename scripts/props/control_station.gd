class_name ControlStation
extends Node3D
## A console with a status screen and (optionally) one lever. Used for the
## airlock controls, life support and the gravity generator. Mounted with
## local +Z pointing at the operator.
##
## The station is presentation only: whoever owns it pushes text into the
## screen with `set_readout` and reacts to `lever.toggled`.

@export var title := "CONTROL"
## Free-standing pedestal (origin on the floor) or wall plate (origin at centre).
@export var pedestal := true
@export var has_lever := true
@export var lever_label := "Switch"
@export var lever_on_prompt := "Switch off"
@export var lever_off_prompt := "Switch on"

var lever: LeverSwitch
var powered := false
## Collider covering the screen, for stations that want a screen interaction.
var screen_body: StaticBody3D

var _screen_mat: StandardMaterial3D
var _readout: Label3D
var _text := ""
var _color := Color(0.45, 0.95, 0.85)


func _ready() -> void:
	var y := 1.28 if pedestal else 0.0
	var dark := ShipMaterials.metal(Color(0.15, 0.16, 0.17), 0.55, 0.7)
	if pedestal:
		ShipKit.box(self, Vector3(0.7, 1.0, 0.36), Vector3(0, 0.5, -0.02), ShipMaterials.hull(Color(0.3, 0.32, 0.34), Vector2(0.35, 0.5), 0.6))
		ShipKit.box(self, Vector3(1.04, 0.62, 0.2), Vector3(0, y, 0.0), dark)
	else:
		ShipKit.box(self, Vector3(1.04, 0.62, 0.08), Vector3(0, y, 0.04), dark, false)
	var face := 0.1 if pedestal else 0.08

	_screen_mat = ShipMaterials.glow(Color(0.1, 0.4, 0.45), 0.0)
	_screen_mat.albedo_color = Color(0.01, 0.012, 0.014)
	var screen_x := -0.2 if has_lever else 0.0
	var screen_w := 0.56 if has_lever else 0.9
	ShipKit.box(self, Vector3(screen_w, 0.4, 0.02), Vector3(screen_x, y - 0.03, face + 0.008), _screen_mat, false)
	_readout = ShipKit.readout(self, "", Vector3(screen_x, y - 0.03, face + 0.022), 0.034)
	_readout.width = screen_w / _readout.pixel_size * 0.94
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.line_spacing = 2.0
	ShipKit.stencil(self, title, Vector3(0, y + 0.245, face), Vector3.BACK, 0.05)

	var shape := BoxShape3D.new()
	shape.size = Vector3(screen_w, 0.4, 0.06)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(screen_x, y - 0.03, face + 0.03)
	screen_body = StaticBody3D.new()
	screen_body.collision_layer = Layers.INTERACT
	screen_body.collision_mask = 0
	screen_body.add_child(cs)
	add_child(screen_body)

	if has_lever:
		lever = LeverSwitch.new()
		lever.label = lever_label
		lever.prompt_on = lever_on_prompt
		lever.prompt_off = lever_off_prompt
		lever.position = Vector3(0.33, y - 0.03, face)
		add_child(lever)
	_apply()


func set_powered(on: bool) -> void:
	if on == powered:
		return
	powered = on
	_apply()


func set_readout(text: String, color := Color(0.45, 0.95, 0.85)) -> void:
	if text == _text and color == _color:
		return
	_text = text
	_color = color
	_apply()


func _apply() -> void:
	if _readout == null:
		return
	_readout.visible = powered
	_readout.text = _text
	_readout.modulate = _color
	_screen_mat.emission_energy_multiplier = 0.35 if powered else 0.0
