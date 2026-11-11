class_name SplicerTool
extends Tool
## Electrical splicer. Works on RepairPoint targets (severed conduits, junctions).


func _init() -> void:
	tool_id = &"splicer"
	tool_name = "Splicer"


func _build_model(root: Node3D) -> void:
	part(root, box_mesh(Vector3(0.04, 0.045, 0.26)), Vector3(0, 0, 0.06), Color(0.2, 0.22, 0.25))
	part(root, box_mesh(Vector3(0.05, 0.05, 0.09)), Vector3(0, 0, 0.16), Color(0.1, 0.3, 0.55), Vector3.ZERO, 0.0, 0.1, 0.8)
	part(root, box_mesh(Vector3(0.008, 0.008, 0.09)), Vector3(0.012, 0, -0.11), Color(0.8, 0.8, 0.85), Vector3.ZERO, 0.0, 0.9, 0.3)
	part(root, box_mesh(Vector3(0.008, 0.008, 0.09)), Vector3(-0.012, 0, -0.11), Color(0.8, 0.8, 0.85), Vector3.ZERO, 0.0, 0.9, 0.3)
	part(root, box_mesh(Vector3(0.03, 0.004, 0.05)), Vector3(0, 0.025, 0.02), Color(0.35, 0.9, 1.0), Vector3.ZERO, 1.8)


func _configure_particles(p: CPUParticles3D, mat: StandardMaterial3D) -> void:
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p.amount = 26
	p.lifetime = 0.3
	p.spread = 80.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.7
	p.color = Color(0.6, 0.85, 1.0, 1.0)


func _loop_sound() -> StringName:
	return &"zap_loop"


func _work_light() -> Color:
	return Color(0.55, 0.8, 1.0, 1.3)
