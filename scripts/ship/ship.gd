class_name Ship
extends Node3D
## Base class for a recoverable vessel.
##
## A concrete ship (see scripts/ships/) overrides `_build()` to construct its
## interior with the `add_*` helpers below and to define its contract. This
## class owns everything ships have in common: the systems controller, the
## gravity field, the world environment, and the code that turns system state
## changes into things the player can see and hear.

const BASE_AMBIENT := 0.03
const POWERED_AMBIENT := 0.2

@export var ship_name := "Unnamed vessel"

var systems: ShipSystems
var contract: Contract
var spawn_position := Vector3.ZERO
var spawn_yaw := 0.0

var compartments: Array[Compartment] = []
var doors: Array[Door] = []
var lights: Array[ShipLight] = []
var grime: Array[GrimeSurface] = []
var repair_points: Array[RepairPoint] = []
var breaches: Array[HullBreach] = []
var containers: Array[DepositContainer] = []
var stations: Array[ControlStation] = []
## circuit id -> RepairPoints that must be fixed for that circuit to work.
var circuit_faults := {}

var debris_total := 0
var debris_collected := 0

var _gravity_area: Area3D
var _environment: Environment
var _ambient_target := BASE_AMBIENT
var _hums: Array[AudioStreamPlayer3D] = []
var _hum_level := 0.0
var _bounds := AABB()
var _safety_timer := 0.0
var _power_origin := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"ship")
	systems = ShipSystems.new()
	systems.name = "Systems"
	add_child(systems)
	contract = Contract.new()
	contract.name = "Contract"
	add_child(contract)

	_build_environment()
	_build()
	_finish_build()

	systems.power_changed.connect(_on_power_changed)
	systems.gravity_changed.connect(_on_gravity_changed)
	systems.system_changed.connect(_on_system_changed)
	contract.objective_completed.connect(_on_objective_completed)
	contract.ready_for_signoff.connect(_on_ready_for_signoff)
	_refresh_lights(false)


## Override: build the interior and define the contract.
func _build() -> void:
	pass


# --- Queries --------------------------------------------------------------------

func get_compartment_at(world_pos: Vector3) -> Compartment:
	var p := to_local(world_pos)
	for c in compartments:
		if c.contains(p):
			return c
	return null


func has_gravity_at(world_pos: Vector3) -> bool:
	return systems.is_gravity_active() and _bounds.grow(0.5).has_point(to_local(world_pos))


func get_pressure_at(world_pos: Vector3) -> float:
	var c := get_compartment_at(world_pos)
	return c.pressure if c else 0.0


func get_debris_remaining() -> int:
	return debris_total - debris_collected


## 0..1 across every grime patch aboard, weighted by how dirty each was.
func get_clean_fraction() -> float:
	var initial := 0.0
	var remaining := 0.0
	for g in grime:
		initial += g.get_initial_amount()
		remaining += g.get_remaining_amount()
	return 1.0 if initial <= 0.0 else 1.0 - remaining / initial


func is_all_clean() -> bool:
	for g in grime:
		if not g.is_clean:
			return false
	return true


func get_lighting_faults() -> int:
	var n := 0
	for circuit in circuit_faults:
		for point: RepairPoint in circuit_faults[circuit]:
			if not point.is_repaired:
				n += 1
	return n


func is_circuit_faulted(circuit: StringName) -> bool:
	for point: RepairPoint in circuit_faults.get(circuit, []):
		if not point.is_repaired:
			return true
	return false


## World-space markers for the suit scanner: everything still needing work.
func get_scan_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d and not d.is_collected and not d.is_carried:
			match d.category:
				Debris.Category.JUNK:
					out.append({"position": d.global_position, "label": "DEBRIS", "color": Color(1.0, 0.72, 0.25)})
				Debris.Category.SALVAGE:
					out.append({"position": d.global_position, "label": "SALVAGE", "color": Color(0.45, 0.95, 0.85)})
				Debris.Category.PART:
					out.append({"position": d.global_position, "label": "PART", "color": Color(0.7, 0.8, 1.0)})
	for g in grime:
		if not g.is_clean:
			out.append({"position": g.global_position, "label": "GRIME", "color": Color(0.75, 0.6, 0.45)})
	for r in repair_points:
		if not r.is_repaired:
			out.append({"position": r.global_position, "label": "FAULT", "color": Color(1.0, 0.4, 0.3)})
	for b in breaches:
		if not b.is_sealed:
			out.append({"position": b.global_position, "label": "BREACH", "color": Color(1.0, 0.4, 0.3)})
	return out


# --- Construction helpers --------------------------------------------------------

func add_compartment(display_name: String, bounds: AABB, vented: bool, pressure := 0.0) -> Compartment:
	var c := Compartment.new()
	c.name = display_name.validate_node_name()
	c.display_name = display_name
	c.bounds = bounds
	c.vented = vented
	c.pressure = pressure
	add_child(c)
	compartments.append(c)
	return c


func add_door(door_name: String, pos: Vector3, a: Compartment, b: Compartment) -> Door:
	var d := Door.new()
	d.name = door_name.validate_node_name()
	d.door_name = door_name
	d.compartment_a = a
	d.compartment_b = b
	d.position = pos
	add_child(d)
	doors.append(d)
	return d


func add_light(parent: Node3D, pos: Vector3, facing: Vector3, circuit: StringName, energy := 2.0,
		light_range := 8.5, shadows := true) -> ShipLight:
	var l := ShipLight.new()
	l.circuit = circuit
	l.energy = energy
	l.light_range = light_range
	l.cast_shadows = shadows
	parent.add_child(l)
	ShipKit.place(l, pos, facing)
	lights.append(l)
	return l


func add_emergency_light(parent: Node3D, pos: Vector3, facing: Vector3) -> ShipLight:
	var l := ShipLight.new()
	l.is_emergency = true
	l.color = Color(1.0, 0.12, 0.06)
	l.energy = 0.5
	l.light_range = 5.0
	l.cast_shadows = true  # otherwise the red glow leaks through bulkheads
	l.fixture_size = Vector3(0.22, 0.12, 0.07)
	parent.add_child(l)
	ShipKit.place(l, pos, facing)
	lights.append(l)
	return l


func add_grime(parent: Node3D, surface_name: String, pos: Vector3, facing: Vector3, size: Vector2,
		grime_seed: int, note := "", density := 1.0) -> GrimeSurface:
	var g := GrimeSurface.new()
	g.name = "Grime%d" % grime.size()
	g.surface_name = surface_name
	g.note = note
	g.size = size
	g.grime_seed = grime_seed
	g.density = density
	parent.add_child(g)
	ShipKit.place(g, pos, facing)
	g.cleaned.connect(_on_grime_cleaned)
	grime.append(g)
	return g


func add_repair_point(parent: Node3D, label: String, pos: Vector3, facing: Vector3,
		circuit: StringName = &"") -> RepairPoint:
	var r := RepairPoint.new()
	r.label = label
	parent.add_child(r)
	ShipKit.place(r, pos, facing)
	register_repair_point(r, circuit)
	return r


func register_repair_point(point: RepairPoint, circuit: StringName = &"") -> void:
	repair_points.append(point)
	if circuit != &"":
		if not circuit_faults.has(circuit):
			circuit_faults[circuit] = []
		circuit_faults[circuit].append(point)
		point.repaired.connect(func(_p: RepairPoint) -> void: _refresh_lights(false))


func add_breach(parent: Node3D, pos: Vector3, facing: Vector3, compartment: Compartment) -> HullBreach:
	var b := HullBreach.new()
	parent.add_child(b)
	ShipKit.place(b, pos, facing)
	compartment.breaches.append(b)
	breaches.append(b)
	b.sealed.connect(func(_b: HullBreach) -> void: Game.notify("Hull breach sealed", &"good"))
	return b


func add_container(parent: Node3D, kind: DepositContainer.Kind, pos: Vector3, yaw_deg := 0.0) -> DepositContainer:
	var c := DepositContainer.new()
	c.kind = kind
	if kind == DepositContainer.Kind.SALVAGE:
		c.title = "SALVAGE LOCKER"
		c.accepted = [Debris.Category.SALVAGE]
		c.accent = Color(0.3, 0.85, 0.75)
	else:
		c.title = "WASTE RECLAIM"
		c.accepted = [Debris.Category.JUNK, Debris.Category.SALVAGE]
	c.position = pos
	c.rotation_degrees.y = yaw_deg
	parent.add_child(c)
	c.deposited.connect(_on_deposited)
	containers.append(c)
	return c


func add_station(parent: Node3D, station: ControlStation, pos: Vector3, facing: Vector3) -> ControlStation:
	parent.add_child(station)
	ShipKit.place(station, pos, facing)
	stations.append(station)
	return station


## Places a loose object in the ship and counts it toward the cleanup total.
func add_debris(d: Debris, pos: Vector3, adrift := 1.0) -> Debris:
	add_child(d)
	d.position = pos
	d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	d.home = d.global_transform
	d.set_adrift(adrift)
	register_debris(d)
	return d


## Counts an already-placed object (e.g. a part pulled out of a socket).
func register_debris(d: Debris) -> void:
	if d.is_cleanup_item():
		debris_total += 1
	if d.category == Debris.Category.SALVAGE:
		contract.salvage_total += 1
		contract.salvage_total_value += d.value


# --- Environment -------------------------------------------------------------------

func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0, 0, 0)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.55, 0.65, 0.8)
	_environment.ambient_light_energy = BASE_AMBIENT
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_white = 6.0
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.7
	_environment.glow_bloom = 0.08
	_environment.glow_hdr_threshold = 1.1
	# SSAO and volumetric haze exist only in Forward+; the OpenGL fallback
	# simply goes without them.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		_environment.ssao_enabled = true
		_environment.ssao_radius = 0.8
		_environment.ssao_intensity = 1.6
		# Haze only exists where there is air: it fades in as the ship repressurises.
		_environment.volumetric_fog_enabled = true
		_environment.volumetric_fog_density = 0.0
		_environment.volumetric_fog_albedo = Color(0.8, 0.86, 0.92)
		_environment.volumetric_fog_length = 40.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = _environment
	add_child(world_env)


func _finish_build() -> void:
	systems.compartments = compartments
	systems.doors = doors
	systems.lighting_faults = get_lighting_faults()

	_bounds = AABB()
	for i in compartments.size():
		_bounds = compartments[i].bounds if i == 0 else _bounds.merge(compartments[i].bounds)

	# One gravity field for the whole interior. Rigid bodies inside obey it
	# automatically, so loose objects float or fall with the ship's systems.
	var shape := BoxShape3D.new()
	shape.size = _bounds.size + Vector3.ONE * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = _bounds.get_center()
	_gravity_area = Area3D.new()
	_gravity_area.name = "GravityField"
	_gravity_area.collision_layer = 0
	_gravity_area.collision_mask = Layers.PROPS
	_gravity_area.monitorable = false
	_gravity_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	_gravity_area.gravity_direction = Vector3.DOWN
	_gravity_area.gravity = 0.0
	_gravity_area.linear_damp_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	_gravity_area.linear_damp = 0.03
	_gravity_area.angular_damp_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	_gravity_area.angular_damp = 0.03
	_gravity_area.add_child(cs)
	add_child(_gravity_area)

	for c in compartments:
		var hum := Sfx.make_loop(&"hum_loop", self, -60.0, 6.0)
		hum.position = c.bounds.get_center()
		_hums.append(hum)


# --- Per-frame ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Air resistance: debris coasts forever in vacuum, settles in atmosphere.
	var air := clampf(systems.get_min_pressure() / ShipSystems.NOMINAL_KPA, 0.0, 1.0)
	_gravity_area.linear_damp = lerpf(0.03, 0.35, air)
	_gravity_area.angular_damp = lerpf(0.03, 0.5, air)

	_safety_timer -= delta
	if _safety_timer <= 0.0:
		_safety_timer = 1.0
		_recover_lost_debris()


func _process(delta: float) -> void:
	var player := Game.player
	var pressure := get_pressure_at(player.global_position) if player else 0.0
	Sfx.set_ambient_pressure(pressure)
	var air := clampf(pressure / ShipSystems.NOMINAL_KPA, 0.0, 1.0)
	_environment.volumetric_fog_density = lerpf(_environment.volumetric_fog_density, 0.012 * air, minf(1.0, delta * 2.0))
	_environment.ambient_light_energy = move_toward(_environment.ambient_light_energy, _ambient_target, delta * 0.12)

	_hum_level = move_toward(_hum_level, 1.0 if systems.is_power_online() else 0.0, delta * 0.6)
	for hum in _hums:
		hum.volume_db = linear_to_db(maxf(0.0001, _hum_level * 0.2))
		if _hum_level > 0.0 and not hum.playing:
			hum.play()
		elif _hum_level <= 0.0 and hum.playing:
			hum.stop()


## Anything that somehow leaves the hull is put back where it started, so the
## contract can always be finished.
func _recover_lost_debris() -> void:
	var limit := _bounds.grow(3.0)
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d and not d.is_carried and not limit.has_point(to_local(d.global_position)):
			d.global_transform = d.home
			d.linear_velocity = Vector3.ZERO
			d.angular_velocity = Vector3.ZERO


# --- Reactions to system changes ------------------------------------------------------

func _on_power_changed(online: bool) -> void:
	_ambient_target = POWERED_AMBIENT if online else BASE_AMBIENT
	for d in doors:
		d.powered = online
	_refresh_lights(true)
	Sfx.play_at(&"power_up" if online else &"power_down", to_global(_power_origin), 4.0)
	if online:
		Game.notify("Main power restored", &"good")
	else:
		Game.notify("Main power lost", &"warn")


func _on_gravity_changed(active: bool) -> void:
	_gravity_area.gravity = 9.8 if active else 0.0
	# Sleeping bodies do not notice a gravity change on their own.
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d and not d.is_collected:
			d.sleeping = false
			if not active:
				d.apply_central_impulse(Vector3(randf_range(-0.2, 0.2), randf_range(0.15, 0.5), randf_range(-0.2, 0.2)) * d.mass)
	if active:
		Game.notify("Artificial gravity online", &"good")
	else:
		Game.notify("Artificial gravity offline", &"warn")


func _on_system_changed(id: StringName, state: ShipSystems.State) -> void:
	if id == ShipSystems.LIGHTING and state == ShipSystems.State.ONLINE:
		Game.notify("Lighting circuits nominal", &"good")
	elif id == ShipSystems.ATMOSPHERE and state == ShipSystems.State.ONLINE:
		Game.notify("Atmosphere restored", &"good")


## Pushes the current power/circuit state into every fixture.
func _refresh_lights(stagger: bool) -> void:
	systems.lighting_faults = get_lighting_faults()
	var online := systems.is_power_online()
	var origin := to_global(_power_origin)
	for l in lights:
		if l.is_emergency:
			l.set_mode(ShipLight.Mode.OFF if online else ShipLight.Mode.EMERGENCY)
		elif l.circuit == &"external":
			l.set_mode(ShipLight.Mode.ON)
		elif not online:
			l.set_mode(ShipLight.Mode.OFF)
		elif is_circuit_faulted(l.circuit):
			l.set_mode(ShipLight.Mode.FAULT)
		else:
			# Light spreads outward from the distribution panel.
			var delay := l.global_position.distance_to(origin) * 0.09 if stagger else 0.0
			l.set_mode(ShipLight.Mode.ON, delay)


func _on_grime_cleaned(surface: GrimeSurface) -> void:
	Game.notify("%s scrubbed clean" % surface.surface_name, &"good")


func _on_deposited(d: Debris, container: DepositContainer) -> void:
	if d.is_cleanup_item():
		debris_collected += 1
	if d.category == Debris.Category.SALVAGE:
		if container.kind == DepositContainer.Kind.SALVAGE:
			contract.salvage_recovered += 1
			contract.salvage_recovered_value += d.value
			Game.notify("Salvage stowed: %s  (+%d cr)" % [d.item_name, d.value], &"good")
		else:
			contract.salvage_scrapped += 1
			Game.notify("%s scrapped - salvage value lost" % d.item_name, &"warn")


func _on_objective_completed(o: Objective) -> void:
	Sfx.play_ui(&"chime", -4.0)
	Game.notify("Objective complete: %s" % o.title, &"good")


func _on_ready_for_signoff() -> void:
	Game.notify("All work complete - file the recovery report", &"good")
