class_name ScrubberTool
extends Tool
## Powered surface scrubber. Works on GrimeSurface targets.

var _head: Node3D


func _init() -> void:
	tool_id = &"scrubber"
	tool_name = "Scrubber"


func _build_model(root: Node3D) -> void:
	part(root, box_mesh(Vector3(0.05, 0.05, 0.3)), Vector3(0, 0, 0.08), Color(0.13, 0.14, 0.15))
	part(root, box_mesh(Vector3(0.07, 0.075, 0.1)), Vector3(0, 0.0, 0.2), Color(0.85, 0.42, 0.08), Vector3.ZERO, 0.0, 0.1, 0.7)
	_head = Node3D.new()
	_head.position = Vector3(0, 0, -0.1)
	root.add_child(_head)
	part(_head, box_mesh(Vector3(0.2, 0.05, 0.1)), Vector3.ZERO, Color(0.85, 0.42, 0.08), Vector3.ZERO, 0.0, 0.1, 0.7)
	part(_head, box_mesh(Vector3(0.21, 0.03, 0.03)), Vector3(0, 0, -0.06), Color(0.86, 0.87, 0.82), Vector3.ZERO, 0.0, 0.0, 1.0)
	part(_head, box_mesh(Vector3(0.012, 0.012, 0.012)), Vector3(0.07, 0.03, 0.02), Color(0.3, 1.0, 0.6), Vector3.ZERO, 2.5)


func _configure_particles(p: CPUParticles3D, _mat: StandardMaterial3D) -> void:
	p.amount = 28
	p.lifetime = 0.5
	p.spread = 70.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.1
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.4
	p.color = Color(0.5, 0.45, 0.38, 0.7)


func _loop_sound() -> StringName:
	return &"scrub_loop"


func _animate_work(_root: Node3D, t: float) -> void:
	_head.position.x = sin(t * 31.0) * 0.022
	_head.rotation.z = sin(t * 31.0) * 0.06
