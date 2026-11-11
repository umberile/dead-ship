class_name ShipSystems
extends Node
## Authoritative state of a ship's core systems and the dependencies between
## them. Controls (breakers, levers, repairs) write the *inputs* below; every
## physics tick the controller derives each system's state from those inputs
## and from the simulated atmosphere, and emits signals when something changes.
##
## Dependency chain, each with a mechanical reason:
##   POWER       needs the distribution panel repaired and the breaker closed.
##   LIGHTING    needs power; faulted circuits leave it degraded.
##   ATMOSPHERE  pumps need power; a compartment cannot hold pressure while
##               its hull is breached (the air simply leaves).
##   GRAVITY     needs power, and its field coils are air-cooled, so an
##               interlock holds it off until Engineering has enough pressure.
##
## Because states are derived, not scripted, things also fail consistently:
## open the breaker again and lights, pumps and gravity all drop out.

enum State { OFFLINE, STANDBY, BLOCKED, DEGRADED, ONLINE }

const POWER := &"power"
const LIGHTING := &"lighting"
const ATMOSPHERE := &"atmosphere"
const GRAVITY := &"gravity"
const SYSTEM_IDS: Array[StringName] = [POWER, LIGHTING, ATMOSPHERE, GRAVITY]
const SYSTEM_NAMES := {
	POWER: "MAIN POWER",
	LIGHTING: "LIGHTING",
	ATMOSPHERE: "ATMOSPHERE",
	GRAVITY: "GRAVITY",
}

const NOMINAL_KPA := 101.3
## Pressure at which a compartment counts as breathable / restored.
const HABITABLE_KPA := 95.0
## Gravity coil cooling interlock: engages above the first value, trips below
## the second (hysteresis so it cannot chatter).
const GRAVITY_ENGAGE_KPA := 60.0
const GRAVITY_TRIP_KPA := 45.0
## kPa per second delivered to each vented compartment by life support.
const FILL_RATE := 9.0
## Fraction of pressure lost per second through a fully open breach.
const LEAK_RATE := 3.0
## Equalisation rate through a fully open door.
const DOOR_FLOW := 2.5
const AIRLOCK_PUMP_RATE := 17.0

signal system_changed(id: StringName, state: State)
signal power_changed(online: bool)
signal gravity_changed(active: bool)

# --- Inputs (written by controls and repairs) --------------------------------
var panel_repaired := false
var breaker_closed := false
var life_support_on := false
var gravity_switch_on := false
## Number of lighting circuits still faulted.
var lighting_faults := 0

# --- Registered by the ship ---------------------------------------------------
var compartments: Array[Compartment] = []
var doors: Array[Door] = []
## Compartment housing the gravity generator.
var gravity_compartment: Compartment

var _states := {}
var _status := {}
var _gravity_latched := false


func _ready() -> void:
	for id in SYSTEM_IDS:
		_states[id] = State.OFFLINE
		_status[id] = ""
	_evaluate(true)


func get_state(id: StringName) -> State:
	return _states.get(id, State.OFFLINE)


## Short human-readable status, e.g. "BREAKER OPEN" or "43 kPa - LEAK".
func get_status(id: StringName) -> String:
	return _status.get(id, "")


func is_power_online() -> bool:
	return _states[POWER] == State.ONLINE


func is_gravity_active() -> bool:
	return _states[GRAVITY] == State.ONLINE


func are_pumps_running() -> bool:
	return is_power_online() and life_support_on


## Lowest pressure across all compartments.
func get_min_pressure() -> float:
	var p := NOMINAL_KPA
	for c in compartments:
		p = minf(p, c.pressure)
	return p if not compartments.is_empty() else 0.0


func is_leaking() -> bool:
	for c in compartments:
		if c.is_breached():
			return true
	return false


func is_atmosphere_restored() -> bool:
	return _states[ATMOSPHERE] == State.ONLINE


func _physics_process(delta: float) -> void:
	_simulate_atmosphere(delta)
	_evaluate(false)


# --- Atmosphere ------------------------------------------------------------------

func _simulate_atmosphere(delta: float) -> void:
	var pumping := are_pumps_running()
	for c in compartments:
		if pumping and c.vented:
			c.pressure += FILL_RATE * delta
		if c.pump_mode != 0:
			c.pressure += AIRLOCK_PUMP_RATE * c.pump_mode * delta
			if (c.pump_mode < 0 and c.pressure <= 0.0) or (c.pump_mode > 0 and c.pressure >= NOMINAL_KPA):
				c.pump_mode = 0
		var leak := c.get_leak_factor()
		if leak > 0.0:
			c.pressure -= c.pressure * minf(1.0, LEAK_RATE * leak * delta)
		c.pressure = clampf(c.pressure, 0.0, NOMINAL_KPA)
		for b in c.breaches:
			b.compartment_pressure = c.pressure

	# Air flows through open doors until both sides match (volume-weighted).
	for d in doors:
		if d.open_fraction < 0.03 or d.compartment_a == null or d.compartment_b == null:
			continue
		var a := d.compartment_a
		var b := d.compartment_b
		var va := a.get_volume()
		var vb := b.get_volume()
		var settle := (a.pressure * va + b.pressure * vb) / (va + vb)
		var t := 1.0 - exp(-DOOR_FLOW * d.open_fraction * delta)
		a.pressure = lerpf(a.pressure, settle, t)
		b.pressure = lerpf(b.pressure, settle, t)


# --- State derivation ---------------------------------------------------------------

func _evaluate(silent: bool) -> void:
	var was_power: bool = _states[POWER] == State.ONLINE
	var was_gravity: bool = _states[GRAVITY] == State.ONLINE

	# Power.
	if not panel_repaired:
		_set_state(POWER, State.OFFLINE, "DISTRIBUTION FAULT", silent)
	elif not breaker_closed:
		_set_state(POWER, State.STANDBY, "BREAKER OPEN", silent)
	else:
		_set_state(POWER, State.ONLINE, "NOMINAL", silent)
	var power: bool = _states[POWER] == State.ONLINE

	# Lighting.
	if not power:
		_set_state(LIGHTING, State.OFFLINE, "EMERGENCY BATTERY", silent)
	elif lighting_faults > 0:
		_set_state(LIGHTING, State.DEGRADED, "%d CIRCUIT FAULT%s" % [lighting_faults, "" if lighting_faults == 1 else "S"], silent)
	else:
		_set_state(LIGHTING, State.ONLINE, "NOMINAL", silent)

	# Atmosphere.
	var p := get_min_pressure()
	var leaking := is_leaking()
	var kpa := "%d kPa" % int(round(p))
	if p >= HABITABLE_KPA and not leaking:
		_set_state(ATMOSPHERE, State.ONLINE, kpa, silent)
	elif power and life_support_on:
		if leaking:
			_set_state(ATMOSPHERE, State.DEGRADED, "%s - HULL LEAK" % kpa, silent)
		else:
			_set_state(ATMOSPHERE, State.STANDBY, "%s - PRESSURISING" % kpa, silent)
	elif p < 2.0:
		_set_state(ATMOSPHERE, State.OFFLINE, "VACUUM", silent)
	else:
		_set_state(ATMOSPHERE, State.DEGRADED, "%s - PUMPS OFF" % kpa, silent)

	# Gravity.
	var cooling := gravity_compartment.pressure if gravity_compartment else 0.0
	if cooling >= GRAVITY_ENGAGE_KPA:
		_gravity_latched = true
	elif cooling < GRAVITY_TRIP_KPA:
		_gravity_latched = false
	if not power:
		_set_state(GRAVITY, State.OFFLINE, "NO POWER", silent)
	elif not _gravity_latched:
		_set_state(GRAVITY, State.BLOCKED, "COIL COOLING INTERLOCK", silent)
	elif not gravity_switch_on:
		_set_state(GRAVITY, State.STANDBY, "READY", silent)
	else:
		_set_state(GRAVITY, State.ONLINE, "1.0 G", silent)

	if silent:
		return
	if power != was_power:
		power_changed.emit(power)
	var gravity: bool = _states[GRAVITY] == State.ONLINE
	if gravity != was_gravity:
		gravity_changed.emit(gravity)


func _set_state(id: StringName, state: State, status: String, silent: bool) -> void:
	_status[id] = status
	if _states[id] == state:
		return
	_states[id] = state
	if not silent:
		system_changed.emit(id, state)


# --- Lock reasons for controls ---------------------------------------------------

## Why the life-support pumps cannot be switched on right now ("" = they can).
func get_life_support_lock() -> String:
	if not is_power_online():
		return "Life support: no power to the pumps"
	return ""


## Why the gravity generator cannot be engaged right now ("" = it can).
func get_gravity_lock() -> String:
	if not is_power_online():
		return "Gravity generator: no power"
	if not _gravity_latched:
		return "Gravity generator: coil cooling interlock. Needs %d kPa in %s" % [
			int(GRAVITY_ENGAGE_KPA), gravity_compartment.display_name if gravity_compartment else "the compartment"]
	return ""
