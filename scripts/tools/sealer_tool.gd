class_name SealerTool
extends Tool
## Arc sealer: lays down and cures hull sealant. Works on HullBreach targets.


func _init() -> void:
	tool_id = &"sealer"
	tool_name = "Arc Sealer"


func _build_model(root: Node3D) -> void:
	part(root, box_mesh(Vector3(0.07, 0.1, 0.26)), Vector3(0, 0, 0.06), Color(0.8, 0.66, 0.12), Vector3.ZERO, 0.0, 0.1, 0.65)
	part(root, box_mesh(Vector3(0.045, 0.12, 0.05)), Vector3(0, -0.09, 0.14), Color(0.1, 0.1, 0.11))
	part(root, cyl_mesh(0.04, 0.2), Vector3(0, 0.085, 0.08), Color(0.55, 0.57, 0.6), Vector3(90, 0, 0), 0.0, 0.8, 0.35)
	part(root, cyl_mesh(0.016, 0.16), Vector3(0, 0, -0.14), Color(0.2, 0.21, 0.22), Vector3(90, 0, 0), 0.0, 0.8, 0.4)
	part(root, cyl_mesh(0.02, 0.03), Vector3(0, 0, -0.225), Color(1.0, 0.5, 0.12), Vector3(90, 0, 0), 2.0)


func _configure_particles(p: CPUParticles3D, mat: StandardMaterial3D) -> void:
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p.amount = 36
	p.lifetime = 0.4
	p.spread = 65.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.2
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.9
	p.color = Color(1.0, 0.6, 0.2, 1.0)


func _loop_sound() -> StringName:
	return &"seal_loop"


func _work_light() -> Color:
	return Color(1.0, 0.55, 0.2, 1.6)
