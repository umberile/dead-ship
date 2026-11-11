class_name Player
extends CharacterBody3D
## First-person recovery technician.
##
## Two movement states, selected by the gravity the ship reports at the
## player's position:
##   * Zero-g: six-degree-of-freedom suit thrusters with real inertia. The body
##     collapses to a ball around the head so orientation never snags on walls.
##   * Gravity: conventional grounded walking with a standing capsule.
##
## Look uses a "rollable frame": yaw/pitch are measured against a reference
## frame that the roll keys rotate. That gives full 6DOF orientation without
## the slow roll drift of naive local-axis mouselook, which keeps long
## cleaning sessions comfortable.

signal movement_mode_changed(zero_g: bool)

const WALK_HEIGHT := 1.75
const WALK_RADIUS := 0.35
const FLOAT_HEIGHT := 0.84
const FLOAT_RADIUS := 0.42
const EYE_OFFSET_WALK := 0.72
const STAND_TIME := 0.6
const ALIGN_TIME := 0.7
const GRAVITY := 9.8

@export var mouse_sensitivity := 0.0022
## Mass used for throw recoil and for shoving loose objects.
@export var suit_mass := 110.0

@export_group("Walking")
@export var walk_speed := 3.6
@export var sprint_speed := 5.6
@export var ground_accel := 38.0
@export var air_accel := 6.0
@export var jump_velocity := 4.3

@export_group("Zero-G")
@export var thrust_accel := 5.0
@export var max_float_speed := 5.0
## Fraction of velocity bled off per second by the suit's auto-trim. Low, so
## the player genuinely coasts.
@export var passive_drag := 0.1
@export var brake_decel := 7.5
@export var roll_speed := 1.5
@export var bounce := 0.3

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var tool_mount: Node3D = $Head/Camera3D/ToolMount
@onready var interactor: Interactor = $Interactor
@onready var tool_belt: ToolBelt = $ToolBelt
@onready var _capsule: CapsuleShape3D = ($CollisionShape3D as CollisionShape3D).shape

var zero_g := true
var input_enabled := true
## Pressure (kPa) of the compartment the player is in.
var ambient_pressure := 0.0

var _frame := Basis.IDENTITY
var _yaw := 0.0
var _pitch := 0.0
var _align_from := Quaternion.IDENTITY
var _align_t := 1.0
## 0 = floating ball, 1 = standing capsule.
var _form := 0.0
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _thrust_level := 0.0
var _step_distance := 0.0
var _was_on_floor := false
var _thruster: AudioStreamPlayer
var _suit_hum: AudioStreamPlayer


func _ready() -> void:
	add_to_group(&"player")
	interactor.player = self
	tool_belt.setup(self)
	motion_mode = MOTION_MODE_FLOATING
	_apply_form()
	reset_interpolation()
	_thruster = Sfx.make_ui_loop(&"thruster_loop", self, -60.0)
	_thruster.play()
	_suit_hum = Sfx.make_ui_loop(&"suit_loop", self, -24.0)
	_suit_hum.play()


## Sets the view direction (radians), levelled to the ship.
func set_look(yaw: float, pitch: float) -> void:
	_frame = Basis.IDENTITY
	_yaw = yaw
	_pitch = pitch
	_align_t = 1.0


## Call after teleporting so the camera does not sweep across the level.
func reset_interpolation() -> void:
	_prev_pos = global_position
	_curr_pos = global_position
	_update_head()


func get_look_basis() -> Basis:
	return _frame * Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.5, 1.5)
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		Sfx.play_ui(&"click", -8.0)


func _physics_process(delta: float) -> void:
	_sample_environment()
	_update_form(delta)
	if zero_g:
		_move_float(delta)
	else:
		_move_walk(delta)
	_prev_pos = _curr_pos
	_curr_pos = global_position


func _process(delta: float) -> void:
	_align_t = minf(1.0, _align_t + delta / ALIGN_TIME)
	_update_head()
	_thruster.volume_db = lerpf(_thruster.volume_db, lerpf(-60.0, -17.0, _thrust_level), minf(1.0, delta * 12.0))


func _update_head() -> void:
	var target := get_look_basis()
	var b := target
	if _align_t < 1.0:
		b = Basis(_align_from.slerp(target.get_rotation_quaternion(), smoothstep(0.0, 1.0, _align_t)))
	var pos := _prev_pos.lerp(_curr_pos, Engine.get_physics_interpolation_fraction())
	head.global_transform = Transform3D(b, pos + Vector3(0, _form * EYE_OFFSET_WALK, 0))


# --- Environment and body shape ------------------------------------------------

func _sample_environment() -> void:
	var gravity_here := false
	ambient_pressure = 0.0
	if Game.ship:
		gravity_here = Game.ship.has_gravity_at(global_position)
		ambient_pressure = Game.ship.get_pressure_at(global_position)
	if gravity_here == zero_g:
		_set_zero_g(not gravity_here)


func _set_zero_g(value: bool) -> void:
	zero_g = value
	if zero_g:
		# Feet leave the deck: shrink to a ball centred on the head so the
		# view does not move.
		global_position.y += _form * EYE_OFFSET_WALK
		_form = 0.0
		_apply_form()
		_prev_pos = global_position
		_curr_pos = global_position
		motion_mode = MOTION_MODE_FLOATING
	else:
		motion_mode = MOTION_MODE_GROUNDED
		_relevel()
	movement_mode_changed.emit(zero_g)


## While gravity is on, grow from the floating ball into a standing capsule.
## The body is lowered as the eye offset rises so the camera stays put unless
## the floor gets in the way (in which case the player simply stands up).
func _update_form(delta: float) -> void:
	if zero_g or _form >= 1.0:
		return
	var next := minf(1.0, _form + delta / STAND_TIME)
	var drop := (next - _form) * EYE_OFFSET_WALK
	_form = next
	_apply_form()
	move_and_collide(Vector3(0, -drop, 0))


func _apply_form() -> void:
	_capsule.radius = lerpf(FLOAT_RADIUS, WALK_RADIUS, _form)
	_capsule.height = lerpf(FLOAT_HEIGHT, WALK_HEIGHT, _form)


## Blend the view back to ship-level, keeping the direction being looked in.
func _relevel() -> void:
	var current := head.global_basis.orthonormalized()
	var f := -current.z
	_align_from = current.get_rotation_quaternion()
	_align_t = 0.0
	_frame = Basis.IDENTITY
	_yaw = atan2(-f.x, -f.z)
	_pitch = clampf(asin(clampf(f.y, -1.0, 1.0)), -1.5, 1.5)


func _is_levelled() -> bool:
	return _frame.is_equal_approx(Basis.IDENTITY)


# --- Movement ------------------------------------------------------------------

func _move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _move_walk(delta: float) -> void:
	var input := _move_input()
	var dir := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y)
	var sprinting := input_enabled and Input.is_action_pressed("sprint")
	var target := dir * (sprint_speed if sprinting else walk_speed)
	var accel := ground_accel if is_on_floor() else air_accel
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor():
		if input_enabled and Input.is_action_just_pressed("thrust_up"):
			velocity.y = jump_velocity
	else:
		velocity.y -= GRAVITY * delta
	_thrust_level = 0.0

	var pre := velocity
	move_and_slide()
	_push_bodies(pre)

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and pre.y < -2.0:
		Sfx.play_at(&"footstep", _feet_position(), 2.0, 0.7)
	_was_on_floor = on_floor
	if on_floor:
		_step_distance += Vector2(velocity.x, velocity.z).length() * delta
		if _step_distance > 2.1:
			_step_distance = 0.0
			Sfx.play_at(&"footstep", _feet_position(), -5.0, randf_range(0.9, 1.1))


func _move_float(delta: float) -> void:
	var b := get_look_basis()
	var input := _move_input()
	var lift := Input.get_axis("thrust_down", "thrust_up") if input_enabled else 0.0
	var thrust := b.x * input.x + b.z * input.y + b.y * lift
	if thrust.length_squared() > 1.0:
		thrust = thrust.normalized()
	velocity += thrust * thrust_accel * delta

	var braking := input_enabled and Input.is_action_pressed("sprint")
	if braking:
		# Stabilise: kill drift and, if rolled, come back level with the deck.
		velocity = velocity.move_toward(Vector3.ZERO, brake_decel * delta)
		if not _is_levelled() and _align_t >= 1.0:
			_relevel()
	elif thrust == Vector3.ZERO:
		velocity *= maxf(0.0, 1.0 - passive_drag * delta)
	velocity = velocity.limit_length(max_float_speed)
	_thrust_level = clampf(thrust.length() + (0.6 if braking and velocity.length() > 0.2 else 0.0), 0.0, 1.0)

	var roll := Input.get_axis("roll_left", "roll_right") if input_enabled else 0.0
	if roll != 0.0:
		_frame = (Basis(-b.z, roll * roll_speed * delta) * _frame).orthonormalized()

	var pre := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		var vn := pre.dot(n)
		if vn < -0.4:
			velocity -= n * vn * bounce  # push off instead of sticking to the wall
			if vn < -1.6:
				Sfx.play_at(&"footstep", global_position - n * FLOAT_RADIUS, -4.0, 0.8)
	_push_bodies(pre)


## Transfers some momentum to loose rigid bodies the player ran into.
func _push_bodies(pre_velocity: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb == null:
			continue
		var into := -pre_velocity.dot(c.get_normal())
		if into <= 0.05:
			continue
		var impulse := -c.get_normal() * into * minf(rb.mass, 25.0) * 0.9
		rb.apply_impulse(impulse, c.get_position() - rb.global_position)


func _feet_position() -> Vector3:
	return global_position - Vector3(0, _capsule.height * 0.5, 0)
