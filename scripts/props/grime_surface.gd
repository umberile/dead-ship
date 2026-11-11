class_name GrimeSurface
extends Node3D
## A flat patch of grime that is scrubbed away progressively.
##
## The node lies in its local XY plane facing +Z. Dirt is stored as a small
## greyscale mask which the scrubber paints into; a shader draws the grime
## wherever the mask is non-zero, so every pass of the tool visibly removes
## material. Cheap: one quad, one small texture, no render targets.

signal cleaned(surface: GrimeSurface)

const SHADER := preload("res://shaders/grime.gdshader")
const PX_PER_M := 40.0
## Below this fraction of the original dirt the rest lifts off by itself, so
## the player never has to hunt for the last invisible speck.
const AUTO_FINISH := 0.05

@export var size := Vector2(2.0, 2.0)
@export var grime_seed := 1
@export_range(0.2, 1.0) var density := 1.0
@export var surface_name := "Grime"
@export_multiline var note := ""
@export var color_a := Color(0.07, 0.06, 0.05)
@export var color_b := Color(0.19, 0.15, 0.1)

var is_clean := false
var interactable: Interactable

var _w := 0
var _h := 0
var _mask: PackedByteArray
var _image: Image
var _texture: ImageTexture
var _initial := 1
var _remaining := 1
var _dirty := false
var _material: ShaderMaterial
var _body: StaticBody3D
var _quad: MeshInstance3D


func _ready() -> void:
	add_to_group(&"grime")
	_w = clampi(int(size.x * PX_PER_M), 16, 192)
	_h = clampi(int(size.y * PX_PER_M), 16, 192)
	_generate_mask()
	_image = Image.create_from_data(_w, _h, false, Image.FORMAT_L8, _mask)
	_texture = ImageTexture.create_from_image(_image)

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 1
	_material.set_shader_parameter(&"mask", _texture)
	_material.set_shader_parameter(&"size_m", size)
	_material.set_shader_parameter(&"seed", float(grime_seed) * 3.71)
	_material.set_shader_parameter(&"color_a", color_a)
	_material.set_shader_parameter(&"color_b", color_b)

	var mesh := QuadMesh.new()
	mesh.size = size
	_quad = MeshInstance3D.new()
	_quad.mesh = mesh
	_quad.material_override = _material
	_quad.position.z = 0.004
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)

	# Ray-only collider so the scrubber can find the patch without it blocking
	# movement or debris.
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.03)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.z = 0.012
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.INTERACT
	_body.collision_mask = 0
	_body.add_child(cs)
	add_child(_body)

	interactable = Interactable.new()
	interactable.display_name = surface_name
	interactable.description = note
	interactable.tool_id = &"scrubber"
	interactable.tool_verb = "Scrub"
	interactable.needs_work = true
	interactable.progress = 0.0
	interactable.tool_applied.connect(_on_tool_applied)
	_body.add_child(interactable)


func get_initial_amount() -> float:
	return float(_initial)


func get_remaining_amount() -> float:
	return 0.0 if is_clean else float(_remaining)


func get_clean_fraction() -> float:
	return 1.0 if is_clean else 1.0 - float(_remaining) / float(_initial)


func _on_tool_applied(tool: Tool, pos: Vector3, _normal: Vector3, delta: float) -> void:
	scrub(pos, 0.3, 4.2 * tool.power * delta)


## Removes grime in a soft circle around `world_pos`. `amount` is the fraction
## of full-thickness dirt removed at the centre of the brush.
func scrub(world_pos: Vector3, radius: float, amount: float) -> void:
	if is_clean:
		return
	var lp := to_local(world_pos)
	var cx := (lp.x / size.x + 0.5) * _w
	var cy := (0.5 - lp.y / size.y) * _h
	var rx := radius / size.x * _w
	var ry := radius / size.y * _h
	var cut_max := amount * 255.0
	var removed := 0
	for y in range(maxi(0, int(cy - ry)), mini(_h, int(cy + ry) + 1)):
		var dy := (y + 0.5 - cy) / ry
		for x in range(maxi(0, int(cx - rx)), mini(_w, int(cx + rx) + 1)):
			var dx := (x + 0.5 - cx) / rx
			var d2 := dx * dx + dy * dy
			if d2 >= 1.0:
				continue
			var idx := y * _w + x
			var v := _mask[idx]
			if v == 0:
				continue
			var nv := maxi(0, v - int(cut_max * (1.0 - d2)) - 1)
			removed += v - nv
			_mask[idx] = nv
	if removed == 0:
		return
	_remaining -= removed
	_dirty = true
	interactable.progress = get_clean_fraction()
	if float(_remaining) <= float(_initial) * AUTO_FINISH:
		_finish()


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_image.set_data(_w, _h, false, Image.FORMAT_L8, _mask)
		_texture.update(_image)


## Instantly cleans the whole patch (used by tests and debug tooling).
func clean_all() -> void:
	if not is_clean:
		_finish()


func _finish() -> void:
	is_clean = true
	_remaining = 0
	interactable.progress = 1.0
	interactable.needs_work = false
	interactable.enabled = false
	_body.collision_layer = 0
	Sfx.play_at(&"sparkle", global_position, -4.0)
	# Let the last traces lift away, with a brief clean sheen over the panel.
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter(&"fade", v), 1.0, 0.0, 0.45)
	tween.tween_callback(_quad.hide)
	_flash()
	cleaned.emit(self)


func _flash() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.5, 0.95, 0.85, 0.16)
	var mesh := QuadMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.z = 0.006
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tween.tween_callback(mi.queue_free)


func _generate_mask() -> void:
	var blotch := FastNoiseLite.new()
	blotch.seed = grime_seed * 7919 + 13
	blotch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	blotch.frequency = 0.03
	blotch.fractal_octaves = 4
	var streak := FastNoiseLite.new()
	streak.seed = grime_seed * 104729 + 7
	streak.frequency = 0.09
	_mask = PackedByteArray()
	_mask.resize(_w * _h)
	var total := 0
	var edge_x := maxf(3.0, _w * 0.14)
	var edge_y := maxf(3.0, _h * 0.14)
	for y in _h:
		for x in _w:
			var n := blotch.get_noise_2d(x, y) * 0.5 + 0.5
			var s := streak.get_noise_2d(x * 2.5, y * 0.35) * 0.5 + 0.5
			var v := clampf((n - 0.3) * 3.0 + (s - 0.5) * 0.5, 0.0, 1.0) * density
			# Feather the border so the patch has no visible rectangle.
			var ex := clampf(minf(x, _w - 1 - x) / edge_x, 0.0, 1.0)
			var ey := clampf(minf(y, _h - 1 - y) / edge_y, 0.0, 1.0)
			v *= smoothstep(0.0, 1.0, minf(ex, ey))
			var byte := int(v * 255.0)
			_mask[y * _w + x] = byte
			total += byte
	_initial = maxi(1, total)
	_remaining = _initial
