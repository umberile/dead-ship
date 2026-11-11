class_name RepairPoint
extends Node3D
## A severed electrical connection that is spliced back together with the
## Splicer. Mounted with local +Z pointing out of the surface.
##
## Reused for the power panel's bus feeds and the corridor lighting junctions.

signal repaired(point: RepairPoint)

@export var label := "Severed conduit"
@export_multiline var note := "Burnt through. Needs splicing."
## Seconds of continuous tool work needed.
@export var work_time := 2.6
## Live connections arc and spark while broken.
@export var energized := false:
	set(value):
		energized = value
		_spark_timer = randf_range(0.2, 1.5)

var is_repaired := false
var progress := 0.0
var interactable: Interactable

var _broken: Node3D
var _fixed: Node3D
var _led: MeshInstance3D
var _sparks: CPUParticles3D
var _flash: OmniLight3D
var _spark_timer := 1.0


func _ready() -> void:
	add_to_group(&"repair_point")
	_build()


func _on_tool_applied(tool: Tool, _pos: Vector3, _normal: Vector3, delta: float) -> void:
	add_progress(delta * tool.power / work_time)


func add_progress(amount: float) -> void:
	if is_repaired:
		return
	progress = minf(1.0, progress + amount)
	interactable.progress = progress
	interactable.status = "SPLICING  %d%%" % int(progress * 100.0)
	if progress >= 1.0:
		_finish()


func _finish() -> void:
	is_repaired = true
	_broken.visible = false
	_fixed.visible = true
	_flash.visible = false
	(_led.material_override as StandardMaterial3D).emission = Color(0.3, 1.0, 0.45)
	(_led.material_override as StandardMaterial3D).albedo_color = Color(0.1, 0.4, 0.15)
	interactable.needs_work = false
	interactable.status = "CONNECTION RESTORED"
	Sfx.play_at(&"click", global_position, 0.0, 0.8)
	Sfx.play_ui(&"chime", -9.0, 1.2)
	repaired.emit(self)


func _process(delta: float) -> void:
	if _flash.visible:
		_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 30.0)
		if _flash.light_energy <= 0.0:
			_flash.visible = false
	if is_repaired or not energized:
		return
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = randf_range(0.25, 2.4)
		_sparks.restart()
		_sparks.emitting = true
		_flash.light_energy = randf_range(2.0, 4.5)
		_flash.visible = true
		Sfx.play_at(&"spark", global_position, -7.0, randf_range(0.8, 1.3))


func _build() -> void:
	var dark := ShipMaterials.metal(Color(0.1, 0.1, 0.11), 0.6, 0.6)
	var cable := ShipMaterials.rubber(Color(0.12, 0.1, 0.09))
	var copper := ShipMaterials.metal(Color(0.75, 0.42, 0.2), 0.35, 1.0)

	ShipKit.box(self, Vector3(0.34, 0.14, 0.02), Vector3(0, 0, 0.01), dark, false)
	ShipKit.cylinder(self, 0.022, 0.11, Vector3(-0.11, 0, 0.045), cable, Vector3.RIGHT)
	ShipKit.cylinder(self, 0.022, 0.11, Vector3(0.11, 0, 0.045), cable, Vector3.RIGHT)

	_broken = Node3D.new()
	add_child(_broken)
	var stub_a := ShipKit.cylinder(_broken, 0.009, 0.05, Vector3(-0.045, 0.008, 0.05), copper, Vector3.RIGHT)
	stub_a.rotation.y = 0.5
	var stub_b := ShipKit.cylinder(_broken, 0.009, 0.05, Vector3(0.045, -0.01, 0.055), copper, Vector3.RIGHT)
	stub_b.rotation.y = -0.4
	ShipKit.box(_broken, Vector3(0.12, 0.1, 0.004), Vector3(0, 0, 0.022), ShipMaterials.paint(Color(0.015, 0.012, 0.01), 1.0), false)

	_fixed = Node3D.new()
	_fixed.visible = false
	add_child(_fixed)
	ShipKit.cylinder(_fixed, 0.03, 0.13, Vector3(0, 0, 0.045), ShipMaterials.paint(Color(0.9, 0.55, 0.1), 0.5), Vector3.RIGHT)

	_led = ShipKit.box(self, Vector3(0.022, 0.022, 0.012), Vector3(0.14, 0.05, 0.022), ShipMaterials.glow(Color(1.0, 0.2, 0.12), 2.0), false)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.38, 0.2, 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.z = 0.05
	var body := StaticBody3D.new()
	body.collision_layer = Layers.INTERACT
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)

	interactable = Interactable.new()
	interactable.display_name = label
	interactable.description = note
	interactable.tool_id = &"splicer"
	interactable.tool_verb = "Splice"
	interactable.needs_work = true
	interactable.progress = 0.0
	interactable.tool_applied.connect(_on_tool_applied)
	body.add_child(interactable)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	quad.material = mat
	_sparks = CPUParticles3D.new()
	_sparks.mesh = quad
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.amount = 18
	_sparks.lifetime = 0.5
	_sparks.direction = Vector3(0, 0, 1)
	_sparks.spread = 70.0
	_sparks.gravity = Vector3.ZERO
	_sparks.initial_velocity_min = 0.8
	_sparks.initial_velocity_max = 3.0
	_sparks.color = Color(0.65, 0.85, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 0.6, 0.2, 0))
	_sparks.color_ramp = ramp
	_sparks.position.z = 0.06
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.6, 0.8, 1.0)
	_flash.omni_range = 7.0
	_flash.position.z = 0.25
	_flash.visible = false
	add_child(_flash)
