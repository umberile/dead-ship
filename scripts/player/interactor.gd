class_name Interactor
extends Node
## Raycast-driven interaction for the player: focus tracking, the interact key
## (tap and hold), tool use, and carrying loose objects.

signal carried_changed(body: RigidBody3D)

@export var reach := 3.2
@export var hold_distance := 1.2
@export var throw_speed := 6.5
@export var carry_stiffness := 14.0
@export var max_carry_mass := 60.0

var player: Player
## What the player is looking at (null if nothing interactable is in reach).
var focus: Interactable
var focus_position := Vector3.ZERO
var focus_normal := Vector3.UP
var carried: RigidBody3D
## 0..1 progress of the current hold-to-interact, for the HUD.
var hold_fraction := 0.0
var tool_working := false

var _hold_target: Interactable
var _hold_time := 0.0


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_update_focus()
	if player.input_enabled:
		_update_interact(delta)
		_update_use(delta)
	else:
		_set_tool_working(false)
	_update_carry(delta)


func _update_focus() -> void:
	var cam := player.camera
	var from := cam.global_position
	var to := from - cam.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.PROPS | Layers.INTERACT)
	var exclude: Array[RID] = [player.get_rid()]
	if carried:
		exclude.append(carried.get_rid())
	query.exclude = exclude
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	focus = null
	if hit.is_empty():
		return
	focus_position = hit.position
	focus_normal = hit.normal
	var found := Interactable.find(hit.collider)
	if found and found.enabled:
		focus = found


func _update_interact(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		_hold_target = null
		if carried:
			if focus and focus.accepts_item(carried):
				focus.insert_item(player, carried)
			else:
				drop()
		elif focus and focus.has_action():
			var reason := focus.get_blocked_reason(player)
			if reason != "":
				Sfx.play_ui(&"buzz", -8.0)
				Game.notify(reason, &"warn")
			elif focus.hold_time > 0.0:
				_hold_target = focus
				_hold_time = 0.0
			else:
				focus.interact(player)
	elif Input.is_action_pressed("interact") and _hold_target:
		if focus != _hold_target or focus.get_blocked_reason(player) != "":
			_hold_target = null
		else:
			_hold_time += delta
			if _hold_time >= _hold_target.hold_time:
				var target := _hold_target
				_hold_target = null
				target.interact(player)
	else:
		_hold_target = null
	hold_fraction = _hold_time / _hold_target.hold_time if _hold_target else 0.0


func _update_use(delta: float) -> void:
	var tool := player.tool_belt.current
	var working := false
	if carried:
		if Input.is_action_just_pressed("use_tool"):
			throw()
	elif tool and focus and Input.is_action_pressed("use_tool") and focus.accepts_tool(tool.tool_id):
		focus.apply_tool(tool, focus_position, focus_normal, delta)
		working = true
	_set_tool_working(working)


func _set_tool_working(working: bool) -> void:
	tool_working = working
	var tool := player.tool_belt.current
	if tool:
		tool.set_working(working, focus_position, focus_normal)


# --- Carrying ----------------------------------------------------------------

func pick_up(body: RigidBody3D) -> void:
	if carried or body == null:
		return
	if body.mass > max_carry_mass:
		Game.notify("Too heavy to carry", &"warn")
		return
	carried = body
	body.sleeping = false
	body.add_collision_exception_with(player)
	player.add_collision_exception_with(body)
	if body is Debris:
		(body as Debris).is_carried = true
	Sfx.play_ui(&"pickup", -6.0)
	carried_changed.emit(carried)


## Lets go of the carried object and returns it (null if hands were empty).
func drop() -> RigidBody3D:
	var body := carried
	if body == null:
		return null
	carried = null
	if is_instance_valid(body):
		body.remove_collision_exception_with(player)
		player.remove_collision_exception_with(body)
		body.linear_velocity = player.velocity
		if body is Debris:
			(body as Debris).is_carried = false
	carried_changed.emit(null)
	return body


func throw() -> void:
	var body := drop()
	if body == null:
		return
	var dir := -player.camera.global_basis.z
	body.linear_velocity = player.velocity + dir * throw_speed
	body.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	# Newton's third law: with nothing to brace against, throwing pushes back.
	if player.zero_g:
		player.velocity -= dir * throw_speed * body.mass / player.suit_mass
	Sfx.play_ui(&"whoosh", -8.0)


func _update_carry(_delta: float) -> void:
	if carried == null:
		return
	if not is_instance_valid(carried) or carried.is_queued_for_deletion():
		carried = null
		carried_changed.emit(null)
		return
	var cam := player.camera
	var target := cam.global_position - cam.global_basis.z * hold_distance - cam.global_basis.y * 0.12
	var offset := target - carried.global_position
	if offset.length() > 2.8:
		drop()  # wedged behind something; let go rather than drag it through walls
		return
	carried.linear_velocity = (offset * carry_stiffness + player.velocity).limit_length(14.0)
	carried.angular_velocity *= 0.85
