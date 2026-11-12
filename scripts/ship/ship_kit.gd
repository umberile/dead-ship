class_name ShipKit
## Construction helpers for building ship interiors out of primitives.
## Everything is placed in the local space of `parent`, which must be unscaled.

## Returns (creating on demand) the StaticBody3D that holds `parent`'s colliders.
static func collision_body(parent: Node3D) -> StaticBody3D:
	var body := parent.get_node_or_null(^"Collision") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		parent.add_child(body)
	return body


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos
		collision_body(parent).add_child(cs)
	return mi


## Cylinder whose length runs along `axis` (Vector3.RIGHT, UP or BACK).
static func cylinder(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material,
		axis := Vector3.UP, collide := false, segments := 14) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = _axis_rotation(axis)
	parent.add_child(mi)
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = length
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos
		cs.rotation = mi.rotation
		collision_body(parent).add_child(cs)
	return mi


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 28
	mesh.ring_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Painted stencil text (lit by the scene, so it is dark when the ship is).
static func stencil(parent: Node3D, text: String, pos: Vector3, facing: Vector3, height := 0.12,
		color := Color(0.82, 0.82, 0.76)) -> Label3D:
	var l := _label(text, height, color)
	l.shaded = true
	parent.add_child(l)
	place(l, pos + facing * 0.006, facing)
	return l


## Self-lit display text for screens and indicators.
static func readout(parent: Node3D, text: String, pos: Vector3, height := 0.035,
		color := Color(0.45, 0.95, 0.85)) -> Label3D:
	var l := _label(text, height, color)
	l.shaded = false
	l.position = pos
	parent.add_child(l)
	return l


static func _label(text: String, height: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = height / 48.0
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return l


## Scenery the player can look at and read about but not operate. `shape`
## should hug the visible object so it never hides loose items from the ray.
static func inspectable(parent: Node3D, display_name: String, description: String, shape: Shape3D,
		pos: Vector3) -> Interactable:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.collision_layer = Layers.INTERACT
	body.collision_mask = 0
	body.position = pos
	body.add_child(cs)
	parent.add_child(body)
	var it := Interactable.new()
	it.display_name = display_name
	it.description = description
	body.add_child(it)
	return it


static func box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


static func cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


## Orients `node` so its local +Z points along `facing` (out of the surface it
## is mounted on) and moves it to `pos`.
static func place(node: Node3D, pos: Vector3, facing: Vector3) -> void:
	var b: Basis
	if absf(facing.y) > 0.99:
		b = Basis(Vector3.RIGHT, -signf(facing.y) * PI * 0.5)
	else:
		b = Basis.looking_at(-facing, Vector3.UP)
	node.transform = Transform3D(b, pos)


static func _axis_rotation(axis: Vector3) -> Vector3:
	if absf(axis.x) > 0.5:
		return Vector3(0, 0, PI * 0.5)
	if absf(axis.z) > 0.5:
		return Vector3(PI * 0.5, 0, 0)
	return Vector3.ZERO
