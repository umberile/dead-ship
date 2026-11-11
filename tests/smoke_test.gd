extends Node
## Headless end-to-end test: boots the real game scene and plays the whole
## recovery contract through the same components the player uses, checking the
## system dependency chain along the way.
##
## Run with:
##   godot --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn
## Exit code 0 = pass, 1 = one or more checks failed.

const MAIN := preload("res://scenes/main.tscn")
const DT := 1.0 / 60.0

var ship: KestrelShip
var player: Player
var _failures := 0
var _checks := 0


func _ready() -> void:
	var main := MAIN.instantiate()
	add_child(main)
	await _frames(5)
	ship = Game.ship as KestrelShip
	player = Game.player
	if ship == null or player == null:
		print("FAIL: game did not boot")
		get_tree().quit(1)
		return
	await _run()
	print("\nSMOKE TEST %s: %d/%d checks passed" % ["FAILED" if _failures else "PASSED", _checks - _failures, _checks])
	get_tree().quit(1 if _failures else 0)


func _run() -> void:
	var sys := ship.systems
	var contract := ship.contract

	_section("Boot state")
	_check(player.zero_g, "player starts in zero-g")
	_check(not sys.is_power_online(), "power starts offline")
	_check(sys.get_state(ShipSystems.GRAVITY) == ShipSystems.State.OFFLINE, "gravity starts offline")
	_check(ship.airlock.pressure > 100.0 and ship.corridor.pressure < 1.0, "airlock pressurised, ship in vacuum")
	_check(ship.airlock_door._blocked(player) != "", "inner door is pressure-locked")
	_check(contract.get_current().id == &"board", "first objective is boarding")
	_check(ship.grime.size() == 8 and ship.debris_total == 16, "level content present (%d grime, %d debris)" % [ship.grime.size(), ship.debris_total])

	_section("Zero-g movement")
	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	_check(player.global_position.z < start.z - 0.3, "thrust moves the player forward")
	var coast := player.velocity.length()
	await _frames(30)
	_check(player.velocity.length() > coast * 0.8, "player coasts with inertia (%.2f -> %.2f m/s)" % [coast, player.velocity.length()])
	Input.action_press("thrust_up")
	await _frames(20)
	Input.action_release("thrust_up")
	_check(player.velocity.y > 0.5, "vertical thrust works in zero-g")
	Input.action_press("roll_right")
	await _frames(20)
	Input.action_release("roll_right")
	_check(not player._is_levelled(), "roll changes orientation")
	Input.action_press("sprint")
	await _frames(90)
	Input.action_release("sprint")
	_check(player.velocity.length() < 0.1, "stabilise brakes to a stop")
	_check(player._is_levelled(), "stabilise re-levels the view")

	_section("Airlock")
	ship.airlock_station.lever.interactable.interact(player)
	_check(ship.airlock.pump_mode == -1, "cycle lever starts evacuation")
	await _wait(func() -> bool: return ship.airlock.pressure < 1.0, 12.0)
	_check(ship.airlock.pressure < 1.0, "airlock evacuates")
	_check(ship.airlock_door._blocked(player) == "", "pressure lock releases once equalised")
	ship.airlock_door._on_interacted(player)
	await _wait(func() -> bool: return ship.airlock_door.is_open(), 6.0)
	_check(ship.airlock_door.is_open(), "inner door cranks open")
	_check(ship.airlock_station.lever.interactable.get_blocked_reason(player) != "", "airlock lever interlocked while door is open")
	_teleport(Vector3(0, 1.4, -3.0))
	await _frames(20)
	_check(contract.get_objective(&"board").done, "boarding objective completes")

	_section("Carry and dispose")
	var panel_debris := _find_debris("Ceiling panel")
	panel_debris.interactable.interact(player)
	_check(player.interactor.carried == panel_debris, "debris can be picked up")
	await _frames(40)
	_check(panel_debris.global_position.distance_to(player.camera.global_position) < 2.0, "carried debris follows the player")
	player.interactor.throw()
	_check(player.interactor.carried == null and panel_debris.linear_velocity.length() > 3.0, "debris can be thrown")
	await _deposit(panel_debris, ship.containers[1])
	_check(panel_debris.is_collected and ship.debris_collected == 1, "waste reclaimer accepts junk")
	var tin := _find_debris("Ration tin")
	tin.global_position = _mouth(ship.containers[0])
	tin.linear_velocity = Vector3.ZERO
	await _frames(40)
	_check(not tin.is_collected, "salvage locker rejects junk")

	_section("Engineering door")
	_check(ship.engineering_door.open_fraction > 0.1 and not ship.engineering_door.is_open(), "engineering door starts jammed ajar")
	ship.engineering_door._on_interacted(player)
	await _wait(func() -> bool: return ship.engineering_door.is_open(), 6.0)
	_check(ship.engineering_door.is_open(), "engineering door cranks open")

	_section("Power")
	var splicer := player.tool_belt.get_tool(&"splicer")
	_check(ship.panel.breaker.interactable.get_blocked_reason(player) != "", "breaker refuses to latch on a faulted panel")
	_check(sys.get_life_support_lock() != "", "life support locked without power")
	for feed in ship.panel.feeds:
		_check(not feed.interactable.accepts_tool(&"scrubber"), "bus feed ignores the wrong tool")
		await _work(feed.interactable, splicer, feed.global_position, func() -> bool: return feed.is_repaired, 8.0)
		_check(feed.is_repaired, "%s spliced" % feed.label)
	var before := ship.debris_total
	ship.panel.socket.interactable.interact(player)
	await _frames(5)
	_check(ship.debris_total == before + 1, "pulling the burnt fuse creates disposable junk")
	_check(not ship.panel.is_repaired, "panel still faulted without a fuse")
	var fuse := _find_part(&"fuse")
	player.interactor.pick_up(fuse)
	_check(ship.panel.socket.interactable.accepts_item(fuse), "socket accepts the fuse cartridge")
	ship.panel.socket.interactable.insert_item(player, fuse)
	await _frames(5)
	_check(ship.panel.is_repaired and sys.panel_repaired, "panel repaired")
	_check(sys.get_state(ShipSystems.POWER) == ShipSystems.State.STANDBY, "power in standby until breaker closes")
	ship.panel.breaker.interactable.interact(player)
	await _frames(5)
	_check(sys.is_power_online(), "closing the breaker restores power")
	_check(sys.get_state(ShipSystems.LIGHTING) == ShipSystems.State.DEGRADED, "lighting degraded by corridor faults")
	_check(ship.engineering_door.powered, "doors receive power")
	await _frames(150)
	_check(_light_mode(&"engineering") == ShipLight.Mode.ON, "engineering lights on")
	_check(_light_mode(&"corridor_a") == ShipLight.Mode.FAULT, "corridor lights flicker on faulted circuit")

	_section("Atmosphere and breach")
	_check(sys.get_gravity_lock() != "", "gravity interlocked in vacuum")
	ship.life_station.lever.interactable.interact(player)
	_check(sys.are_pumps_running(), "life support pumps start")
	await _frames(480)
	_check(ship.engineering.pressure < 25.0, "breached compartment cannot hold pressure (%.1f kPa)" % ship.engineering.pressure)
	_check(sys.get_state(ShipSystems.ATMOSPHERE) == ShipSystems.State.DEGRADED, "atmosphere reports the leak")
	var sealer := player.tool_belt.get_tool(&"sealer")
	var angle := [0.0]
	var half := false
	for i in 1500:
		angle[0] += 0.03
		var pos := ship.breach.to_global(Vector3(cos(angle[0]), sin(angle[0]), 0.0) * 0.4)
		ship.breach.interactable.apply_tool(sealer, pos, Vector3.LEFT, DT)
		await get_tree().physics_frame
		if not half and ship.breach.seal_fraction > 0.3:
			half = true
			_check(not ship.breach.is_sealed and ship.breach.get_leak_factor() < 0.75, "sealing is progressive (%.0f%%)" % (ship.breach.seal_fraction * 100.0))
		if ship.breach.is_sealed:
			break
	_check(ship.breach.is_sealed, "breach sealed")
	await _wait(func() -> bool: return sys.is_atmosphere_restored(), 60.0)
	_check(sys.is_atmosphere_restored(), "ship repressurises (%.0f kPa min)" % sys.get_min_pressure())
	_check(ship.airlock.pressure > 90.0, "airlock equalises through the open door")

	_section("Gravity")
	_teleport(Vector3(-1.5, 2.6, -17.8))
	await _frames(10)
	var flask := _find_debris("Cracked flask")
	_check(sys.get_gravity_lock() == "", "cooling interlock clears with atmosphere")
	ship.gravity_station.lever.interactable.interact(player)
	await _frames(5)
	_check(sys.is_gravity_active(), "gravity field engages")
	await _frames(200)
	_check(not player.zero_g, "player switches to walking")
	_check(player.is_on_floor() and absf(player.global_position.y - 0.875) < 0.08, "player stands on the deck (y=%.2f)" % player.global_position.y)
	_check(absf(player.camera.global_position.y - 1.595) < 0.1, "eye height is standing height (%.2f)" % player.camera.global_position.y)
	_check(flask.global_position.y < 0.3, "loose debris falls to the deck (y=%.2f)" % flask.global_position.y)
	var before_walk := player.global_position
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(before_walk) > 1.0 and absf(player.global_position.y - 0.875) < 0.08, "walking works")
	await _frames(20)
	_check(player.velocity.length() < 0.1, "walking stops without input")
	ship.gravity_station.lever.interactable.interact(player)
	await _frames(30)
	_check(player.zero_g and not sys.is_gravity_active(), "gravity can be switched off again")
	ship.gravity_station.lever.interactable.interact(player)
	await _frames(120)
	_check(not player.zero_g and player.is_on_floor(), "and back on")

	_section("Lighting")
	for point in ship.repair_points:
		if not point.is_repaired:
			await _work(point.interactable, splicer, point.global_position, func() -> bool: return point.is_repaired, 8.0)
	await _frames(5)
	_check(sys.get_state(ShipSystems.LIGHTING) == ShipSystems.State.ONLINE, "lighting nominal after junction repairs")
	_check(_light_mode(&"corridor_a") == ShipLight.Mode.ON, "corridor lights steady")

	_section("Cleaning")
	var first := ship.grime[0]
	first.scrub(first.global_position, 0.3, 0.5)
	_check(first.get_clean_fraction() > 0.0 and first.get_clean_fraction() < 0.5 and not first.is_clean, "scrubbing is incremental (%.1f%%)" % (first.get_clean_fraction() * 100.0))
	for g in ship.grime:
		var y := -g.size.y * 0.5
		while y <= g.size.y * 0.5 and not g.is_clean:
			var x := -g.size.x * 0.5
			while x <= g.size.x * 0.5 and not g.is_clean:
				g.scrub(g.to_global(Vector3(x, y, 0)), 0.3, 1.0)
				x += 0.2
			y += 0.2
		await get_tree().physics_frame
	_check(ship.is_all_clean(), "all grime scrubbed")
	_check(not first.interactable.enabled, "clean surfaces stop being targets")

	_section("Debris and salvage")
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d.is_cleanup_item():
			await _deposit(d, ship.containers[0] if d.category == Debris.Category.SALVAGE else ship.containers[1])
	_check(ship.get_debris_remaining() == 0, "all debris disposed (%d/%d)" % [ship.debris_collected, ship.debris_total])
	_check(contract.salvage_recovered == 4 and contract.salvage_recovered_value == 2250, "salvage value recorded (%d cr)" % contract.salvage_recovered_value)

	_section("Dependencies hold when things break")
	ship.panel.breaker.interactable.interact(player)
	await _frames(10)
	_check(not sys.is_power_online() and not sys.is_gravity_active() and not sys.are_pumps_running(), "opening the breaker drops power, gravity and pumps")
	contract.refresh()
	_check(not contract.is_ready_for_signoff(), "contract not signable with power off")
	_check(ship.terminal.screen_body.get_child(1).get_blocked_reason(player) != "", "terminal rejects an early report")
	ship.panel.breaker.interactable.interact(player)
	await _frames(30)
	_check(sys.is_power_online() and sys.is_gravity_active(), "closing it brings everything back")

	_section("Sign-off")
	contract.refresh()
	_check(contract.is_ready_for_signoff(), "all objectives complete (%d/%d)" % [contract.get_done_count(), contract.objectives.size()])
	var result := [{}]
	Game.contract_completed.connect(func(summary: Dictionary) -> void: result[0] = summary, CONNECT_ONE_SHOT)
	(ship.terminal.screen_body.get_child(1) as Interactable).interact(player)
	await _frames(10)
	_check(contract.is_complete, "report filed")
	_check(result[0].get("total", 0) == 6450, "payout computed (%s cr)" % result[0].get("total", "?"))
	_check(Game.hud._complete.visible, "completion screen shown")


# --- Helpers --------------------------------------------------------------------------

func _section(title: String) -> void:
	print("\n== %s" % title)


func _check(condition: bool, what: String) -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % what)
	else:
		_failures += 1
		print("  FAIL  %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(condition: Callable, seconds: float) -> void:
	for i in int(seconds * 60.0):
		if condition.call():
			return
		await get_tree().physics_frame


func _teleport(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.reset_interpolation()


## Applies a tool to a target every tick, as holding the use key would.
func _work(target: Interactable, tool: Tool, pos: Vector3, done: Callable, seconds: float) -> void:
	for i in int(seconds * 60.0):
		if done.call():
			return
		if target.accepts_tool(tool.tool_id):
			target.apply_tool(tool, pos, Vector3.UP, DT)
		await get_tree().physics_frame


func _mouth(container: DepositContainer) -> Vector3:
	return container.to_global(Vector3(0, container.bin_size.y + 0.1, 0))


func _deposit(d: Debris, container: DepositContainer) -> void:
	if d.is_carried:
		player.interactor.drop()
	d.global_position = _mouth(container)
	d.linear_velocity = Vector3.ZERO
	await _wait(func() -> bool: return d.is_collected, 3.0)


func _find_debris(item_name: String) -> Debris:
	for node in get_tree().get_nodes_in_group(&"debris"):
		if (node as Debris).item_name == item_name:
			return node
	return null


func _find_part(item_id: StringName) -> Debris:
	for node in get_tree().get_nodes_in_group(&"debris"):
		if (node as Debris).item_id == item_id:
			return node
	return null


func _light_mode(circuit: StringName) -> ShipLight.Mode:
	for l in ship.lights:
		if l.circuit == circuit:
			return l.mode
	return ShipLight.Mode.OFF
