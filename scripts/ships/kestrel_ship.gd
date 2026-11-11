class_name KestrelShip
extends Ship
## ICV Kestrel: the vertical-slice derelict. Three compartments in a line:
##
##   Docking Airlock (z 0..5)  ->  Main Corridor (z -14.4..-0.4)  ->  Engineering (z -24.8..-14.8)
##
## What happened here is told by the wreck itself: something punched through
## the Engineering hull, the coolant line beside it burst, the surge cooked the
## distribution panel, and the crew left in the escape pod. Somebody tried to
## patch the hole first; their empty sealant canister is still drifting by the
## Engineering door.

const WALL := Color(0.36, 0.39, 0.41)
const FLOOR := Color(0.19, 0.2, 0.21)
const CEILING := Color(0.25, 0.26, 0.27)
const TRIM := Color(0.13, 0.14, 0.15)
const GOOD := Color(0.45, 1.0, 0.6)
const WARN := Color(1.0, 0.75, 0.3)
const BAD := Color(1.0, 0.38, 0.28)
const TEAL := Color(0.45, 0.95, 0.85)

var airlock: Compartment
var corridor: Compartment
var engineering: Compartment
var airlock_door: Door
var engineering_door: Door
var panel: PowerPanel
var breach: HullBreach
var airlock_station: ControlStation
var life_station: ControlStation
var gravity_station: ControlStation
var terminal: ControlStation

var _wall: Material
var _floor: Material
var _ceiling: Material
var _trim: Material
var _pipe: Material
var _rings: Array[Node3D] = []
var _ring_mat: StandardMaterial3D
var _ring_speed := 0.0
var _grav_hum: AudioStreamPlayer3D
var _fan: AudioStreamPlayer3D
var _airlock_hiss: AudioStreamPlayer3D
var _vents: Array[CPUParticles3D] = []
var _boarded := false


func _build() -> void:
	ship_name = "ICV Kestrel"
	_wall = ShipMaterials.hull(WALL, Vector2(1.4, 0.93), 0.55)
	_floor = ShipMaterials.hull(FLOOR, Vector2(0.7, 0.7), 0.75, 0.7, 0.5, 0.0)
	_ceiling = ShipMaterials.hull(CEILING, Vector2(1.4, 1.4), 0.4, 0.5, 0.6)
	_trim = ShipMaterials.metal(TRIM, 0.55, 0.75)
	_pipe = ShipMaterials.metal(Color(0.42, 0.4, 0.36), 0.45, 0.8)

	airlock = add_compartment("Airlock", AABB(Vector3(-2, 0, 0), Vector3(4, 3, 5)), false, ShipSystems.NOMINAL_KPA)
	corridor = add_compartment("Main Corridor", AABB(Vector3(-1.5, 0, -14.4), Vector3(3, 2.8, 14)), true)
	engineering = add_compartment("Engineering", AABB(Vector3(-5, 0, -24.8), Vector3(10, 4, 10)), true)
	systems.gravity_compartment = engineering
	spawn_position = Vector3(0, 1.55, 3.6)
	spawn_yaw = 0.0
	_power_origin = Vector3(-5.0, 1.45, -18.2)

	_build_airlock()
	_build_corridor()
	_build_engineering()
	_build_contract()


# =================================================================================
# Airlock
# =================================================================================

func _build_airlock() -> void:
	var r := _room("AirlockRoom")
	ShipKit.box(r, Vector3(4.8, 0.3, 5.8), Vector3(0, -0.15, 2.5), _floor)
	ShipKit.box(r, Vector3(4.8, 0.3, 5.8), Vector3(0, 3.15, 2.5), _ceiling)
	ShipKit.box(r, Vector3(0.4, 3.0, 5.0), Vector3(-2.2, 1.5, 2.5), _wall)
	ShipKit.box(r, Vector3(0.4, 3.0, 5.0), Vector3(2.2, 1.5, 2.5), _wall)
	ShipKit.box(r, Vector3(4.8, 3.0, 0.4), Vector3(0, 1.5, 5.2), _wall)
	_doorway_wall(r, -0.2, 2.4, 3.0)
	for x in [-1.94, 1.94]:
		for z in [0.06, 4.94]:
			ShipKit.box(r, Vector3(0.12, 3.0, 0.12), Vector3(x, 1.5, z), _trim, false)

	# Outer hatch: sealed to the player's shuttle for the whole contract.
	ShipKit.box(r, Vector3(1.9, 2.5, 0.14), Vector3(0, 1.25, 4.93), ShipMaterials.hull(Color(0.3, 0.32, 0.34), Vector2(0.95, 0.83), 0.6))
	for x in [-1.03, 1.03]:
		ShipKit.box(r, Vector3(0.14, 2.6, 0.2), Vector3(x, 1.3, 4.9), ShipMaterials.hazard(), false)
	ShipKit.box(r, Vector3(2.2, 0.14, 0.2), Vector3(0, 2.6, 4.9), ShipMaterials.hazard(), false)
	ShipKit.cylinder(r, 0.3, 0.06, Vector3(0, 1.65, 4.85), _trim, Vector3.BACK)
	ShipKit.cylinder(r, 0.24, 0.07, Vector3(0, 1.65, 4.85), ShipMaterials.glow(Color(0.35, 0.55, 0.8), 0.5), Vector3.BACK)
	ShipKit.stencil(r, "DOCKING COLLAR", Vector3(0, 2.8, 5.0), Vector3.FORWARD, 0.1)
	var seal := ShipKit.readout(r, "SEAL ENGAGED  -  SHUTTLE UMBILICAL OK", Vector3.ZERO, 0.045, GOOD)
	ShipKit.place(seal, Vector3(0, 0.55, 4.855), Vector3.FORWARD)

	ShipKit.stencil(r, "ICV KESTREL   -   DECK 1", Vector3(0, 2.72, 0.0), Vector3.BACK, 0.1)
	ShipKit.box(r, Vector3(2.0, 0.012, 0.45), Vector3(0, 0.006, 0.34), ShipMaterials.hazard(), false)

	# EVA stowage along the west wall.
	ShipKit.box(r, Vector3(0.5, 2.1, 1.6), Vector3(-1.75, 1.05, 3.9), ShipMaterials.hull(Color(0.22, 0.3, 0.3), Vector2(0.53, 2.2), 0.5, 0.3, 0.6))
	ShipKit.stencil(r, "EVA STOWAGE", Vector3(-1.5, 1.85, 3.9), Vector3.RIGHT, 0.07)
	ShipKit.cylinder(r, 0.06, 5.0, Vector3(1.72, 2.82, 2.5), _pipe, Vector3.BACK)
	ShipKit.cylinder(r, 0.035, 5.0, Vector3(1.55, 2.88, 2.5), ShipMaterials.metal(Color(0.5, 0.2, 0.12), 0.5), Vector3.BACK)

	# The airlock runs off the shuttle's umbilical, so it is lit from the start.
	add_light(r, Vector3(0, 3.0, 1.3), Vector3.DOWN, &"external", 1.5, 7.0)
	add_light(r, Vector3(0, 3.0, 3.8), Vector3.DOWN, &"external", 1.5, 7.0, false)

	airlock_door = add_door("Airlock inner door", Vector3(0, 0, -0.2), airlock, corridor)

	airlock_station = ControlStation.new()
	airlock_station.title = "AIRLOCK CYCLE"
	airlock_station.pedestal = false
	airlock_station.lever_label = "Airlock cycle"
	airlock_station.lever_off_prompt = "Evacuate chamber"
	airlock_station.lever_on_prompt = "Pressurise chamber"
	add_station(r, airlock_station, Vector3(-2.0, 1.35, 1.25), Vector3.RIGHT)
	airlock_station.set_powered(true)
	airlock_station.lever.note = "Pumps the chamber down to match the ship, or back up to shuttle pressure."
	airlock_station.lever.interactable.description = airlock_station.lever.note
	airlock_station.lever.lock_check = func(_p: Player) -> String:
		return "Airlock cycle: close the inner door first" if airlock_door.open_fraction > 0.03 else ""
	airlock_station.lever.toggled.connect(func(on: bool) -> void:
		airlock.pump_mode = -1 if on else 1)
	_airlock_hiss = Sfx.make_loop(&"hiss_loop", airlock_station, -8.0)

	terminal = ControlStation.new()
	terminal.title = "RECOVERY CONTRACT"
	terminal.pedestal = false
	terminal.has_lever = false
	add_station(r, terminal, Vector3(2.0, 1.4, 1.25), Vector3.LEFT)
	terminal.set_powered(true)
	var report := Interactable.new()
	report.display_name = "Contract terminal"
	report.description = "Uplink to the recovery office. File the report here when the work is done."
	report.prompt = "File recovery report"
	report.blocked_check = func(_p: Player) -> String:
		var current := contract.get_current()
		return "Report rejected: \"%s\" is still outstanding" % current.title if current else ""
	report.interacted.connect(func(_p: Player) -> void: contract.sign_off())
	terminal.screen_body.add_child(report)

	add_container(r, DepositContainer.Kind.SALVAGE, Vector3(1.25, 0, 4.15), 180.0)


# =================================================================================
# Main corridor
# =================================================================================

func _build_corridor() -> void:
	var r := _room("CorridorRoom")
	ShipKit.box(r, Vector3(3.8, 0.3, 14.0), Vector3(0, -0.15, -7.4), _floor)
	ShipKit.box(r, Vector3(3.8, 0.3, 14.0), Vector3(0, 2.95, -7.4), _ceiling)
	ShipKit.box(r, Vector3(0.4, 2.8, 14.0), Vector3(-1.7, 1.4, -7.4), _wall)
	ShipKit.box(r, Vector3(0.4, 2.8, 14.0), Vector3(1.7, 1.4, -7.4), _wall)

	# Structural ribs.
	for z in [-0.62, -3.4, -6.2, -9.0, -11.8, -14.18]:
		for side in [-1.0, 1.0]:
			ShipKit.box(r, Vector3(0.12, 2.8, 0.22), Vector3(side * 1.44, 1.4, z), _trim, false)
		ShipKit.box(r, Vector3(3.0, 0.14, 0.22), Vector3(0, 2.73, z), _trim, false)
	# Kick plates, conduit rails, centre deck plating.
	var kick := ShipMaterials.hull(Color(0.2, 0.21, 0.22), Vector2(0.7, 0.4), 0.8)
	for side in [-1.0, 1.0]:
		ShipKit.box(r, Vector3(0.03, 0.36, 14.0), Vector3(side * 1.485, 0.18, -7.4), kick, false)
		ShipKit.box(r, Vector3(0.05, 0.07, 14.0), Vector3(side * 1.475, 1.02, -7.4), _trim, false)
	ShipKit.box(r, Vector3(1.3, 0.012, 14.0), Vector3(0, 0.006, -7.4), ShipMaterials.hull(Color(0.13, 0.135, 0.14), Vector2(0.325, 0.5), 0.8, 0.8, 0.45, 0.0), false)
	# Overhead services.
	ShipKit.cylinder(r, 0.075, 14.0, Vector3(1.15, 2.56, -7.4), _pipe, Vector3.BACK)
	ShipKit.cylinder(r, 0.045, 14.0, Vector3(0.95, 2.62, -7.4), ShipMaterials.metal(Color(0.5, 0.2, 0.12), 0.5), Vector3.BACK)
	ShipKit.cylinder(r, 0.06, 14.0, Vector3(-1.2, 2.58, -7.4), ShipMaterials.metal(Color(0.2, 0.3, 0.4), 0.5), Vector3.BACK)
	ShipKit.box(r, Vector3(0.3, 0.04, 14.0), Vector3(-0.75, 2.7, -7.4), _trim, false)

	ShipKit.stencil(r, "<< ENGINEERING          AIRLOCK >>", Vector3(1.5, 2.08, -4.95), Vector3.LEFT, 0.09)
	ShipKit.stencil(r, "ENGINEERING", Vector3(0, 2.63, -14.4), Vector3.BACK, 0.11, Color(0.9, 0.75, 0.3))
	ShipKit.box(r, Vector3(2.0, 0.012, 0.45), Vector3(0, 0.007, -14.05), ShipMaterials.hazard(), false)

	add_light(r, Vector3(0, 2.8, -2.0), Vector3.DOWN, &"corridor_a", 1.9, 7.5, false)
	add_light(r, Vector3(0, 2.8, -4.8), Vector3.DOWN, &"corridor_a", 1.9, 7.5)
	add_light(r, Vector3(0, 2.8, -7.6), Vector3.DOWN, &"corridor_b", 1.9, 7.5, false)
	add_light(r, Vector3(0, 2.8, -10.4), Vector3.DOWN, &"corridor_b", 1.9, 7.5)
	add_light(r, Vector3(0, 2.8, -13.0), Vector3.DOWN, &"corridor_b", 1.9, 7.5, false)
	add_emergency_light(r, Vector3(1.5, 2.3, -1.5), Vector3.LEFT)
	add_emergency_light(r, Vector3(-1.5, 2.3, -12.9), Vector3.RIGHT)

	_junction_box(r, Vector3(-1.5, 1.45, -4.1), Vector3.RIGHT, "Lighting junction A", &"corridor_a")
	_junction_box(r, Vector3(1.5, 1.45, -9.9), Vector3.LEFT, "Lighting junction B", &"corridor_b")

	# Escape pod berth: the pod is gone.
	var pod := Node3D.new()
	r.add_child(pod)
	ShipKit.place(pod, Vector3(-1.5, 0, -10.4), Vector3.RIGHT)
	ShipKit.box(pod, Vector3(1.3, 2.0, 0.08), Vector3(0, 1.05, 0.04), ShipMaterials.hull(Color(0.3, 0.31, 0.32), Vector2(1.3, 2.0), 0.6), false)
	ShipKit.cylinder(pod, 0.52, 0.06, Vector3(0, 1.1, 0.09), _trim, Vector3.BACK, false, 20)
	ShipKit.cylinder(pod, 0.42, 0.07, Vector3(0, 1.1, 0.09), ShipMaterials.paint(Color(0.01, 0.01, 0.012), 0.2), Vector3.BACK, false, 20)
	ShipKit.box(pod, Vector3(1.3, 0.1, 0.1), Vector3(0, 2.1, 0.05), ShipMaterials.hazard(), false)
	ShipKit.stencil(pod, "ESCAPE POD 2", Vector3(0, 1.82, 0.08), Vector3.BACK, 0.09)
	ShipKit.box(pod, Vector3(0.5, 0.1, 0.02), Vector3(0, 0.34, 0.09), ShipMaterials.glow(Color(1.0, 0.15, 0.1), 1.2), false)
	ShipKit.readout(pod, "POD LAUNCHED", Vector3(0, 0.34, 0.105), 0.05, Color(1, 0.85, 0.8))

	_vent(r, Vector3(0.55, 2.8, -6.9), Vector3.DOWN)

	add_grime(r, "Bulkhead grime", Vector3(-1.5, 1.35, -7.6), Vector3.RIGHT, Vector2(2.5, 2.1), 11,
			"Weeks of condensate and dust, baked on when the heating failed.")
	add_grime(r, "Bulkhead grime", Vector3(1.5, 1.3, -2.0), Vector3.LEFT, Vector2(2.3, 2.0), 23,
			"Greasy handprints under the dirt. Someone braced here in a hurry.")
	add_grime(r, "Deck grime", Vector3(0, 0.014, -11.0), Vector3.UP, Vector2(2.4, 2.6), 37,
			"Tracked in from Engineering.")
	add_grime(r, "Soot streaks", Vector3(1.5, 1.4, -13.0), Vector3.LEFT, Vector2(2.1, 2.2), 41,
			"Smoke blew through here from Engineering before the air ran out.")

	add_container(r, DepositContainer.Kind.WASTE, Vector3(0.95, 0, -7.6), -90.0)

	engineering_door = add_door("Engineering door", Vector3(0, 0, -14.6), corridor, engineering)
	engineering_door.set_ajar(0.22)

	# Loose debris.
	_junk(Debris.make_box("Ceiling panel", Vector3(0.9, 0.04, 0.6), Color(0.4, 0.42, 0.44), 300.0), Vector3(0.3, 1.7, -3.0),
			"Shaken loose from the overhead.")
	_junk(Debris.make_cylinder("Cable offcut", 0.07, 0.7, Color(0.1, 0.09, 0.08), 500.0, 0.0, 0.9), Vector3(-0.6, 0.9, -5.4))
	_junk(Debris.make_cylinder("Ration tin", 0.06, 0.12, Color(0.6, 0.55, 0.4), 900.0, 0.8, 0.35), Vector3(-0.5, 1.3, -5.9),
			"Half eaten. Whoever opened it did not come back for it.")
	_junk(Debris.make_box("Vent cover", Vector3(0.5, 0.03, 0.5), Color(0.3, 0.31, 0.33), 400.0), Vector3(-0.7, 2.1, -9.3))
	_junk(Debris.make_box("Mag-boot", Vector3(0.14, 0.16, 0.32), Color(0.15, 0.15, 0.17), 600.0, 0.2, 0.8), Vector3(0.2, 0.5, -12.2),
			"Just the one.")
	var canister := _junk(Debris.make_cylinder("Sealant canister", 0.07, 0.32, Color(0.8, 0.66, 0.12), 700.0, 0.3, 0.6), Vector3(0.7, 1.5, -13.4),
			"Empty. Somebody tried to patch the hull by hand and ran out.")
	canister.add_visual(Tool.cyl_mesh(0.025, 0.08), Vector3(0, 0.2, 0), Color(0.12, 0.12, 0.13))

	var slate := _salvage(Debris.make_box("Data slate", Vector3(0.22, 0.02, 0.3), Color(0.08, 0.09, 0.1), 2000.0, 0.3, 0.3), Vector3(-0.4, 1.2, -10.9), 350,
			"Ship's maintenance log. The recovery office pays for these.")
	slate.add_visual(Tool.box_mesh(Vector3(0.18, 0.004, 0.24)), Vector3(0, 0.012, 0), Color(0.3, 0.8, 0.9), 0.2, 0.3, 0.8)


func _junction_box(parent: Node3D, pos: Vector3, facing: Vector3, label: String, circuit: StringName) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	ShipKit.place(holder, pos, facing)
	ShipKit.box(holder, Vector3(0.56, 0.44, 0.05), Vector3(0, 0, 0.025), ShipMaterials.hull(Color(0.3, 0.32, 0.3), Vector2(0.56, 0.44), 0.7), false)
	var cover := ShipKit.box(holder, Vector3(0.5, 0.38, 0.015), Vector3(0.18, -0.36, 0.09), ShipMaterials.metal(Color(0.33, 0.34, 0.33), 0.6), false)
	cover.rotation = Vector3(0.5, 0.2, 0.9)
	var cable := ShipMaterials.rubber(Color(0.09, 0.08, 0.08))
	ShipKit.cylinder(holder, 0.022, 1.3, Vector3(-0.2, 0.86, 0.04), cable)
	ShipKit.cylinder(holder, 0.022, 1.3, Vector3(0.2, 0.86, 0.04), cable)
	ShipKit.stencil(holder, label.to_upper(), Vector3(0, 0.27, 0.0), Vector3.BACK, 0.045)
	var point := add_repair_point(holder, label, Vector3(0, 0, 0.05), Vector3.BACK, circuit)
	point.note = "Feeds the corridor lights on this side. Scorched by the same surge that took the main panel."
	point.interactable.description = point.note


# =================================================================================
# Engineering
# =================================================================================

func _build_engineering() -> void:
	var r := _room("EngineeringRoom")
	var wall := ShipMaterials.hull(Color(0.33, 0.35, 0.35), Vector2(1.67, 1.0), 0.65)
	ShipKit.box(r, Vector3(10.8, 0.3, 10.8), Vector3(0, -0.15, -19.8), _floor)
	ShipKit.box(r, Vector3(10.8, 0.3, 10.8), Vector3(0, 4.15, -19.8), _ceiling)
	ShipKit.box(r, Vector3(0.4, 4.0, 10.0), Vector3(-5.2, 2.0, -19.8), wall)
	ShipKit.box(r, Vector3(0.4, 4.0, 10.0), Vector3(5.2, 2.0, -19.8), wall)
	ShipKit.box(r, Vector3(10.8, 4.0, 0.4), Vector3(0, 2.0, -25.0), wall)
	_doorway_wall(r, -14.6, 5.4, 4.0, wall)

	# Frames and overhead structure.
	for z in [-16.6, -19.17, -23.6]:
		ShipKit.box(r, Vector3(0.14, 4.0, 0.3), Vector3(-4.93, 2.0, z), _trim, false)
	for z in [-20.1, -22.3, -24.2]:
		ShipKit.box(r, Vector3(0.14, 4.0, 0.3), Vector3(4.93, 2.0, z), _trim, false)
	for x in [-2.3, 1.1]:
		ShipKit.box(r, Vector3(0.3, 4.0, 0.14), Vector3(x, 2.0, -24.73), _trim, false)
	for z in [-17.3, -19.8, -22.3]:
		ShipKit.box(r, Vector3(10.0, 0.22, 0.3), Vector3(0, 3.89, z), _trim, false)
	ShipKit.box(r, Vector3(0.9, 0.5, 10.0), Vector3(-3.0, 3.53, -19.8), ShipMaterials.hull(Color(0.3, 0.31, 0.3), Vector2(1.25, 0.5), 0.6))
	ShipKit.cylinder(r, 0.09, 10.0, Vector3(1.4, 3.66, -19.8), _pipe, Vector3.BACK)
	ShipKit.cylinder(r, 0.06, 10.0, Vector3(1.75, 3.7, -19.8), ShipMaterials.metal(Color(0.5, 0.2, 0.12), 0.5), Vector3.BACK)
	ShipKit.box(r, Vector3(3.6, 0.012, 3.6), Vector3(0, 0.006, -21.3), ShipMaterials.hazard(), false)
	ShipKit.stencil(r, "CAUTION   GRAVITY FIELD COILS", Vector3(0, 0.02, -18.95), Vector3.UP, 0.12, Color(0.9, 0.75, 0.3))

	add_light(r, Vector3(-2.3, 4.0, -17.5), Vector3.DOWN, &"engineering", 2.5, 10.0)
	add_light(r, Vector3(2.5, 4.0, -17.5), Vector3.DOWN, &"engineering", 2.5, 10.0, false)
	add_light(r, Vector3(-2.3, 4.0, -22.4), Vector3.DOWN, &"engineering", 2.5, 10.0, false)
	add_light(r, Vector3(2.5, 4.0, -22.4), Vector3.DOWN, &"engineering", 2.5, 10.0)
	add_emergency_light(r, Vector3(-5.0, 3.0, -15.7), Vector3.RIGHT)
	add_emergency_light(r, Vector3(5.0, 3.1, -23.4), Vector3.LEFT)

	_build_gravity_generator(r, Vector3(0, 0, -21.3))
	_build_power_panel(r)
	_build_life_support(r)
	_build_breach_area(r)

	# Workbench, crates, a tipped parts bin.
	ShipKit.box(r, Vector3(2.4, 0.9, 0.8), Vector3(-3.6, 0.45, -24.3), ShipMaterials.hull(Color(0.27, 0.28, 0.3), Vector2(0.8, 0.9), 0.7))
	ShipKit.box(r, Vector3(2.5, 0.05, 0.86), Vector3(-3.6, 0.925, -24.3), ShipMaterials.metal(Color(0.5, 0.5, 0.52), 0.35), false)
	ShipKit.box(r, Vector3(2.2, 1.0, 0.04), Vector3(-3.6, 1.9, -24.78), ShipMaterials.paint(Color(0.35, 0.22, 0.1), 0.8), false)
	ShipKit.stencil(r, "RETURN TOOLS TO BOARD", Vector3(-3.6, 2.52, -24.8), Vector3.BACK, 0.06)
	var crate := ShipMaterials.hull(Color(0.32, 0.36, 0.28), Vector2(0.45, 0.4), 0.7, 0.2, 0.7)
	ShipKit.box(r, Vector3(0.9, 0.8, 0.9), Vector3(-4.4, 0.4, -22.6), crate)
	ShipKit.box(r, Vector3(0.8, 0.7, 0.8), Vector3(-4.35, 1.15, -22.55), crate)
	var bin := Node3D.new()
	bin.position = Vector3(-2.7, 0.0, -16.3)
	bin.rotation_degrees = Vector3(0, 30, 0)
	r.add_child(bin)
	ShipKit.box(bin, Vector3(0.9, 0.05, 0.6), Vector3(0, 0.025, 0), crate)
	ShipKit.box(bin, Vector3(0.9, 0.5, 0.05), Vector3(0, 0.25, -0.3), crate)
	ShipKit.box(bin, Vector3(0.05, 0.5, 0.6), Vector3(-0.45, 0.25, 0), crate)
	ShipKit.box(bin, Vector3(0.05, 0.5, 0.6), Vector3(0.45, 0.25, 0), crate)
	ShipKit.stencil(bin, "SPARES", Vector3(0, 0.3, -0.325), Vector3.FORWARD, 0.08)

	add_grime(r, "Electrical soot", Vector3(-5.0, 1.6, -20.7), Vector3.RIGHT, Vector2(2.6, 2.4), 53,
			"Fans out from the distribution panel. The panel burned for a while.", 1.0)
	add_grime(r, "Coolant residue", Vector3(2.6, 0.014, -19.6), Vector3.UP, Vector2(3.0, 3.0), 67,
			"Sprayed from the burst line and froze where it landed.")
	add_grime(r, "Bulkhead grime", Vector3(-0.6, 1.8, -24.8), Vector3.BACK, Vector2(3.0, 2.4), 71)
	add_grime(r, "Coolant spatter", Vector3(5.0, 1.55, -18.6), Vector3.LEFT, Vector2(2.4, 2.2), 83,
			"Blast pattern from the burst coolant line.")

	_junk(Debris.make_box("Hull fragment", Vector3(0.5, 0.05, 0.4), Color(0.2, 0.2, 0.21), 900.0, 0.8, 0.5), Vector3(3.6, 1.8, -20.4),
			"Edges melted smooth. Whatever came through was moving fast.")
	_junk(Debris.make_cylinder("Ruptured pipe", 0.07, 0.9, Color(0.42, 0.4, 0.36), 500.0, 0.8, 0.45), Vector3(3.2, 2.6, -22.0),
			"Split along its length from inside.")
	_junk(Debris.make_cylinder("Burnt cable", 0.04, 0.6, Color(0.04, 0.035, 0.03), 800.0, 0.0, 1.0), Vector3(-3.8, 1.2, -17.4))
	_junk(Debris.make_box("Bent grating", Vector3(0.7, 0.04, 0.7), Color(0.25, 0.26, 0.27), 350.0), Vector3(-1.2, 2.8, -18.0))
	_junk(Debris.make_cylinder("Cracked flask", 0.08, 0.26, Color(0.3, 0.5, 0.55), 500.0, 0.1, 0.2), Vector3(1.6, 0.8, -17.2))
	_junk(Debris.make_box("Insulation chunk", Vector3(0.35, 0.25, 0.3), Color(0.6, 0.55, 0.4), 60.0, 0.0, 1.0), Vector3(0.8, 3.1, -23.0))

	var pump := _salvage(Debris.make_box("Coolant pump", Vector3(0.3, 0.26, 0.4), Color(0.2, 0.35, 0.5), 450.0, 0.5, 0.5), Vector3(-2.2, 1.0, -22.8), 900,
			"Sheared off its mounts but the impeller turns freely. Worth recovering.")
	pump.add_visual(Tool.cyl_mesh(0.1, 0.16), Vector3(0, 0, 0.26), Color(0.6, 0.6, 0.62), 0.9, 0.3, 0.0, Vector3(90, 0, 0))
	var case := _salvage(Debris.make_box("Tool case", Vector3(0.44, 0.14, 0.3), Color(0.7, 0.2, 0.1), 300.0, 0.1, 0.6), Vector3(-3.1, 1.6, -17.2), 400,
			"Latched and intact.")
	case.add_visual(Tool.box_mesh(Vector3(0.16, 0.03, 0.03)), Vector3(0, 0.085, 0), Color(0.1, 0.1, 0.1))
	var cell := _salvage(Debris.make_cylinder("Power cell", 0.09, 0.28, Color(0.3, 0.32, 0.34), 900.0, 0.8, 0.4), Vector3(2.2, 1.4, -16.4), 600,
			"Still holding charge.")
	cell.add_visual(Tool.cyl_mesh(0.092, 0.05), Vector3.ZERO, Color(0.3, 1.0, 0.6), 0.2, 0.4, 1.5)

	# The replacement fuse the power panel needs, spilled from the spares bin.
	var fuse := Debris.make_cylinder("Fuse cartridge", 0.04, 0.16, Color(0.75, 0.76, 0.78), 2500.0, 0.6, 0.35)
	fuse.category = Debris.Category.PART
	fuse.item_id = &"fuse"
	fuse.description = "Type-C main bus fuse, unused. Fits the distribution panel."
	fuse.add_visual(Tool.cyl_mesh(0.042, 0.04), Vector3.ZERO, Color(1.0, 0.65, 0.15), 0.2, 0.4, 1.6)
	add_debris(fuse, Vector3(-2.2, 0.9, -16.9), 0.5)


func _build_gravity_generator(r: Node3D, pos: Vector3) -> void:
	var g := Node3D.new()
	g.name = "GravityGenerator"
	g.position = pos
	r.add_child(g)
	var dark := ShipMaterials.metal(Color(0.16, 0.17, 0.19), 0.5, 0.8)
	ShipKit.cylinder(g, 1.25, 0.4, Vector3(0, 0.2, 0), ShipMaterials.hull(Color(0.3, 0.31, 0.33), Vector2(0.8, 0.4), 0.6), Vector3.UP, true, 24)
	ShipKit.cylinder(g, 0.42, 3.2, Vector3(0, 2.0, 0), dark, Vector3.UP, true, 20)
	ShipKit.cylinder(g, 0.9, 0.4, Vector3(0, 3.8, 0), dark, Vector3.UP, true, 24)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		ShipKit.box(g, Vector3(0.1, 3.2, 0.1), Vector3(cos(a) * 1.05, 2.0, sin(a) * 1.05), _trim, false)
	_ring_mat = ShipMaterials.glow(TEAL, 0.0)
	_ring_mat.albedo_color = Color(0.22, 0.24, 0.26)
	_ring_mat.metallic = 0.8
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 1.15 + i * 0.85, 0)
		pivot.rotation = Vector3(0.12 * (i - 1), 0, 0.08 * (1 - i))
		g.add_child(pivot)
		ShipKit.torus(pivot, 0.68, 0.84, Vector3.ZERO, _ring_mat)
		ShipKit.box(pivot, Vector3(0.14, 0.2, 0.14), Vector3(0.76, 0, 0), dark, false)
		_rings.append(pivot)
	_grav_hum = Sfx.make_loop(&"grav_loop", g, -60.0, 6.0)
	_grav_hum.position = Vector3(0, 1.5, 0)

	gravity_station = ControlStation.new()
	gravity_station.title = "GRAVITY FIELD"
	gravity_station.lever_label = "Gravity field"
	gravity_station.lever_off_prompt = "Engage gravity field"
	gravity_station.lever_on_prompt = "Disengage gravity field"
	add_station(r, gravity_station, Vector3(0, 0, -19.25), Vector3.BACK)
	gravity_station.lever.lock_check = func(_p: Player) -> String: return systems.get_gravity_lock()
	gravity_station.lever.toggled.connect(func(on: bool) -> void:
		systems.gravity_switch_on = on)


func _build_power_panel(r: Node3D) -> void:
	panel = PowerPanel.new()
	panel.name = "PowerPanel"
	r.add_child(panel)
	ShipKit.place(panel, _power_origin, Vector3.RIGHT)
	for feed in panel.feeds:
		register_repair_point(feed)
	panel.repaired.connect(func() -> void: systems.panel_repaired = true)
	panel.breaker_toggled.connect(func(closed: bool) -> void: systems.breaker_closed = closed)
	panel.debris_spawned.connect(func(d: Debris) -> void:
		d.home = d.global_transform
		register_debris(d))


func _build_life_support(r: Node3D) -> void:
	var unit := ShipMaterials.hull(Color(0.28, 0.33, 0.36), Vector2(0.6, 0.73), 0.6)
	ShipKit.box(r, Vector3(1.2, 2.2, 1.8), Vector3(4.3, 1.1, -16.2), unit)
	ShipKit.cylinder(r, 0.5, 0.06, Vector3(3.69, 1.45, -16.2), _trim, Vector3.RIGHT, false, 20)
	ShipKit.cylinder(r, 0.42, 0.07, Vector3(3.69, 1.45, -16.2), ShipMaterials.paint(Color(0.02, 0.02, 0.025), 0.4), Vector3.RIGHT, false, 20)
	ShipKit.stencil(r, "ATMOSPHERE PLANT", Vector3(3.7, 0.55, -16.2), Vector3.LEFT, 0.08)
	ShipKit.cylinder(r, 0.16, 1.8, Vector3(4.3, 3.1, -16.2), _pipe, Vector3.UP)
	_fan = Sfx.make_loop(&"fan_loop", r, -60.0, 6.0)
	_fan.position = Vector3(3.8, 1.45, -16.2)

	life_station = ControlStation.new()
	life_station.title = "LIFE SUPPORT"
	life_station.pedestal = false
	life_station.lever_label = "Life support pumps"
	life_station.lever_off_prompt = "Start pumps"
	life_station.lever_on_prompt = "Stop pumps"
	add_station(r, life_station, Vector3(2.5, 1.4, -14.8), Vector3.FORWARD)
	life_station.lever.lock_check = func(_p: Player) -> String: return systems.get_life_support_lock()
	life_station.lever.toggled.connect(func(on: bool) -> void:
		systems.life_support_on = on)
	_vent(r, Vector3(2.5, 4.0, -19.9), Vector3.DOWN)
	_vent(r, Vector3(-1.2, 4.0, -17.0), Vector3.DOWN)


func _build_breach_area(r: Node3D) -> void:
	breach = add_breach(r, Vector3(5.0, 1.9, -21.2), Vector3.LEFT, engineering)
	# The coolant line that ran past the impact point, burst open.
	var line := ShipMaterials.metal(Color(0.25, 0.4, 0.45), 0.5)
	ShipKit.cylinder(r, 0.08, 4.7, Vector3(4.86, 2.95, -17.2), line, Vector3.BACK)
	ShipKit.cylinder(r, 0.08, 2.6, Vector3(4.86, 2.95, -23.4), line, Vector3.BACK)
	var torn_a := ShipKit.cylinder(r, 0.08, 0.5, Vector3(4.72, 2.86, -19.75), line, Vector3.BACK)
	torn_a.rotation = Vector3(PI * 0.5 + 0.35, 0.5, 0)
	var torn_b := ShipKit.cylinder(r, 0.08, 0.45, Vector3(4.75, 2.8, -21.95), line, Vector3.BACK)
	torn_b.rotation = Vector3(PI * 0.5 - 0.4, -0.45, 0)
	# Coolant tanks.
	var tank := ShipMaterials.hull(Color(0.35, 0.4, 0.42), Vector2(1.0, 1.0), 0.6, 0.6, 0.45)
	for x in [3.9, 2.4]:
		ShipKit.cylinder(r, 0.65, 3.0, Vector3(x, 1.5, -23.8), tank, Vector3.UP, true, 20)
		ShipKit.cylinder(r, 0.68, 0.12, Vector3(x, 0.8, -23.8), _trim, Vector3.UP, false, 20)
		ShipKit.cylinder(r, 0.68, 0.12, Vector3(x, 2.3, -23.8), _trim, Vector3.UP, false, 20)
	ShipKit.stencil(r, "COOLANT", Vector3(3.15, 1.6, -23.14), Vector3.BACK, 0.12, Color(0.7, 0.85, 0.9))


# =================================================================================
# Contract
# =================================================================================

func _build_contract() -> void:
	contract.contract_id = "RC-0417"
	contract.vessel_name = ship_name
	contract.client = "Halcyon Reclamation"
	contract.base_fee = 4200

	contract.add_objective(Objective.new(&"board", "Cycle the airlock and board the derelict",
			func() -> bool: return _boarded,
			"Pull the AIRLOCK CYCLE lever, then crank the inner door open.", Callable(), true))
	contract.add_objective(Objective.new(&"panel", "Repair the power distribution panel",
			func() -> bool: return panel.is_repaired,
			"Engineering, west wall. Splice both bus feeds and replace the burnt fuse.",
			func() -> String: return "%d/%d" % [panel.get_steps_done(), panel.get_steps_total()]))
	contract.add_objective(Objective.new(&"power", "Restore main power",
			func() -> bool: return systems.is_power_online(),
			"Close the main breaker on the distribution panel."))
	contract.add_objective(Objective.new(&"breach", "Seal the hull breach",
			func() -> bool: return breach.is_sealed,
			"Engineering, east wall. Work the Arc Sealer around the rim.",
			func() -> String: return "%d%%" % int(breach.seal_fraction * 100.0)))
	contract.add_objective(Objective.new(&"atmosphere", "Repressurise the ship",
			func() -> bool: return systems.is_atmosphere_restored(),
			"Start the pumps at the LIFE SUPPORT console in Engineering.",
			func() -> String: return "%d kPa" % int(round(systems.get_min_pressure()))))
	contract.add_objective(Objective.new(&"gravity", "Bring artificial gravity online",
			func() -> bool: return systems.is_gravity_active(),
			"Engage the field at the GRAVITY FIELD console."))
	contract.add_objective(Objective.new(&"lighting", "Repair the corridor lighting circuits",
			func() -> bool: return systems.get_state(ShipSystems.LIGHTING) == ShipSystems.State.ONLINE,
			"Splice the two scorched junction boxes in the main corridor.",
			func() -> String: return "%d/%d" % [2 - get_lighting_faults(), 2]))
	contract.add_objective(Objective.new(&"debris", "Clear debris and stow salvage",
			func() -> bool: return get_debris_remaining() <= 0,
			"Junk to the WASTE RECLAIM in the corridor, salvage to the locker in the airlock.",
			func() -> String: return "%d/%d" % [debris_collected, debris_total]))
	contract.add_objective(Objective.new(&"grime", "Scrub the contaminated surfaces",
			func() -> bool: return is_all_clean(),
			"Use the Scrubber on every grime patch. Tab highlights what is left.",
			func() -> String: return "%d%%" % int(get_clean_fraction() * 100.0)))


# =================================================================================
# Per-frame presentation
# =================================================================================

func _physics_process(delta: float) -> void:
	super(delta)
	# The airlock pump cannot fight an open door: it cuts out.
	if airlock_door.open_fraction > 0.03:
		airlock.pump_mode = 0
	if not _boarded and Game.player:
		var here := get_compartment_at(Game.player.global_position)
		if here == corridor or here == engineering:
			_boarded = true


func _process(delta: float) -> void:
	super(delta)
	_update_stations()

	var gravity := systems.is_gravity_active()
	_ring_speed = move_toward(_ring_speed, 1.0 if gravity else 0.0, delta * 0.35)
	for i in _rings.size():
		_rings[i].rotate_object_local(Vector3.UP, _ring_speed * delta * (1.8 + i * 0.5) * (1.0 if i % 2 == 0 else -1.0))
	_ring_mat.emission_energy_multiplier = _ring_speed * 2.4
	_loop_level(_grav_hum, _ring_speed, 0.7)

	var pumping := systems.are_pumps_running()
	_loop_level(_fan, 1.0 if pumping else 0.0, 0.5, delta)
	var filling := pumping and systems.get_min_pressure() < ShipSystems.NOMINAL_KPA - 1.0
	for v in _vents:
		v.emitting = filling
	if airlock.pump_mode != 0 and not _airlock_hiss.playing:
		_airlock_hiss.play()
	elif airlock.pump_mode == 0 and _airlock_hiss.playing:
		_airlock_hiss.stop()
		Sfx.play_at(&"clunk", _airlock_hiss.global_position, -2.0, 1.3)


func _loop_level(player: AudioStreamPlayer3D, level: float, gain: float, delta := 0.0) -> void:
	var target := linear_to_db(maxf(0.0001, level * gain))
	player.volume_db = target if delta <= 0.0 else lerpf(player.volume_db, target, minf(1.0, delta * 3.0))
	if level > 0.001 and not player.playing:
		player.play()
	elif level <= 0.001 and player.playing and player.volume_db < -50.0:
		player.stop()


func _update_stations() -> void:
	var online := systems.is_power_online()
	life_station.set_powered(online)
	gravity_station.set_powered(online)

	# Airlock console.
	var state := "CHAMBER IDLE"
	var color := TEAL
	if airlock.pump_mode < 0:
		state = "EVACUATING..."
		color = WARN
	elif airlock.pump_mode > 0:
		state = "PRESSURISING..."
		color = WARN
	elif airlock_door.get_pressure_delta() > Door.PRESSURE_LOCK_KPA and airlock_door.open_fraction < 0.05:
		state = "INNER DOOR LOCKED"
		color = BAD
	elif airlock_door.open_fraction < 0.05:
		state = "INNER DOOR FREE"
		color = GOOD
	airlock_station.set_readout("CHAMBER  %3d kPa\nSHIP     %3d kPa\n%s" % [
			int(round(airlock.pressure)), int(round(corridor.pressure)), state], color)

	# Life support.
	var atmo := systems.get_state(ShipSystems.ATMOSPHERE)
	var atmo_note := "PUMPS RUNNING" if systems.are_pumps_running() else "PUMPS STOPPED"
	color = TEAL
	if engineering.is_breached() or corridor.is_breached():
		atmo_note = "HULL LEAK DETECTED"
		color = BAD
	elif atmo == ShipSystems.State.ONLINE:
		atmo_note = "ATMOSPHERE NOMINAL"
		color = GOOD
	life_station.set_readout("CORRIDOR    %3d kPa\nENGINEERING %3d kPa\n%s" % [
			int(round(corridor.pressure)), int(round(engineering.pressure)), atmo_note], color)

	# Gravity.
	var grav := systems.get_state(ShipSystems.GRAVITY)
	color = TEAL
	if grav == ShipSystems.State.BLOCKED:
		color = BAD
	elif grav == ShipSystems.State.ONLINE:
		color = GOOD
	elif grav == ShipSystems.State.STANDBY:
		color = WARN
	gravity_station.set_readout("FIELD: %s\nCOIL COOLING %3d kPa\n(MIN %d kPa)" % [
			systems.get_status(ShipSystems.GRAVITY), int(round(engineering.pressure)),
			int(ShipSystems.GRAVITY_ENGAGE_KPA)], color)

	# Contract terminal.
	if contract.is_complete:
		terminal.set_readout("%s\nREPORT FILED\nVESSEL RECOMMISSIONED" % contract.contract_id, GOOD)
	elif contract.is_ready_for_signoff():
		terminal.set_readout("%s\nALL TASKS COMPLETE\nREADY TO FILE REPORT" % contract.contract_id, GOOD)
	else:
		terminal.set_readout("%s  %s\nTASKS %d/%d COMPLETE\nWORK OUTSTANDING" % [
				contract.contract_id, ship_name.to_upper(), contract.get_done_count(), contract.objectives.size()], WARN)


# =================================================================================
# Helpers
# =================================================================================

func _room(room_name: String) -> Node3D:
	var r := Node3D.new()
	r.name = room_name
	add_child(r)
	return r


## A bulkhead across the ship at `z` with a standard doorway in the middle.
func _doorway_wall(parent: Node3D, z: float, half_width: float, wall_height: float, mat: Material = null) -> void:
	if mat == null:
		mat = _wall
	var side_w := half_width - 0.8
	for side in [-1.0, 1.0]:
		ShipKit.box(parent, Vector3(side_w, wall_height, 0.4), Vector3(side * (0.8 + side_w * 0.5), wall_height * 0.5, z), mat)
		ShipKit.box(parent, Vector3(0.12, 2.3, 0.46), Vector3(side * 0.86, 1.15, z), _trim, false)
	ShipKit.box(parent, Vector3(1.6, wall_height - 2.3, 0.4), Vector3(0, 2.3 + (wall_height - 2.3) * 0.5, z), mat)
	ShipKit.box(parent, Vector3(1.84, 0.12, 0.46), Vector3(0, 2.36, z), _trim, false)


## Life-support outlet: a grille that breathes mist while the pumps are filling.
func _vent(parent: Node3D, pos: Vector3, facing: Vector3) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	ShipKit.place(holder, pos, facing)
	ShipKit.box(holder, Vector3(0.6, 0.6, 0.04), Vector3(0, 0, 0.02), _trim, false)
	for i in 5:
		ShipKit.box(holder, Vector3(0.5, 0.03, 0.02), Vector3(0, -0.2 + i * 0.1, 0.045), ShipMaterials.metal(Color(0.4, 0.41, 0.42), 0.4), false)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = mat
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.emitting = false
	p.amount = 40
	p.lifetime = 1.6
	p.direction = Vector3(0, 0, 1)
	p.spread = 14.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.2
	p.damping_min = 0.6
	p.damping_max = 1.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.2
	p.color = Color(0.8, 0.88, 0.95, 0.16)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.position.z = 0.06
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	_vents.append(p)


func _junk(d: Debris, pos: Vector3, description := "") -> Debris:
	d.category = Debris.Category.JUNK
	if description != "":
		d.description = description
	return add_debris(d, pos)


func _salvage(d: Debris, pos: Vector3, value: int, description := "") -> Debris:
	d.category = Debris.Category.SALVAGE
	d.value = value
	if description != "":
		d.description = description
	return add_debris(d, pos)
