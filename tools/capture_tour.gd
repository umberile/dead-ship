extends Node
## Developer tool: boots the game, walks a camera through the ship in several
## restoration states and saves screenshots. Used to check lighting and layout
## without a human at the keyboard.
##
##   godot --path . res://tools/capture_tour.tscn -- --out=/some/dir [--only=name,name]
##
## Needs a display (use xvfb-run on a headless machine).

const MAIN := preload("res://scenes/main.tscn")

var ship: KestrelShip
var player: Player
var _out := "user://tour"
var _only := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(MAIN.instantiate())
	await _frames(4)
	ship = Game.ship as KestrelShip
	player = Game.player
	player.input_enabled = false
	Game.hud._intro.visible = false
	Game.hud._help_left = 0.0
	await _tour()
	get_tree().quit()


func _tour() -> void:
	# --- Derelict state ---
	await _shot("01_airlock_start", Vector3(0, 1.55, 3.6), Vector3(0, 1.3, -0.2))
	await _shot("02_airlock_console", Vector3(-0.6, 1.5, 1.6), Vector3(-2.0, 1.35, 1.25))
	ship.airlock.pressure = 0.0
	ship.airlock_door.open_fraction = 1.0
	ship.airlock_door.target_open = 1.0
	ship.airlock_door._apply_position()
	await _shot("03_corridor_dark", Vector3(0, 1.5, -0.8), Vector3(0, 1.3, -14.0))
	await _shot("04_corridor_grime", Vector3(0.6, 1.5, -6.2), Vector3(-1.5, 1.3, -7.6))
	await _shot("05_corridor_debris", Vector3(0.3, 1.5, -1.6), Vector3(0.3, 1.6, -3.2))
	await _shot("06_eng_door_ajar", Vector3(0, 1.5, -11.5), Vector3(0, 1.3, -14.6))
	ship.engineering_door.open_fraction = 1.0
	ship.engineering_door.target_open = 1.0
	ship.engineering_door._apply_position()
	await _shot("07_engineering_dark", Vector3(0, 1.7, -15.4), Vector3(0, 1.6, -21.3))
	await _shot("08_power_panel_dead", Vector3(-3.2, 1.5, -18.2), Vector3(-5.0, 1.45, -18.2))
	await _shot("09_breach_open", Vector3(3.0, 1.8, -20.4), Vector3(5.0, 1.9, -21.2))
	player.tool_belt.equip(1)
	for i in 120:
		var a := 2.2 + i * 0.012
		ship.breach.apply_sealant(ship.breach.to_global(Vector3(cos(a), sin(a), 0) * 0.45), 0.03)
	await _shot("10_breach_half_sealed", Vector3(3.3, 1.9, -21.0), Vector3(5.0, 1.9, -21.2))
	player.tool_belt.equip(0)
	var g := ship.grime[0]
	for i in 60:
		g.scrub(g.to_global(Vector3(-0.8 + i * 0.025, 0.25 + 0.3 * sin(i * 0.4), 0)), 0.3, 0.2)
	await _shot("11_grime_half_scrubbed", Vector3(0.7, 1.5, -7.6), Vector3(-1.5, 1.35, -7.6))

	# --- Power back ---
	for feed in ship.panel.feeds:
		feed.add_progress(1.0)
	ship.panel.socket.state = PartSocket.State.FILLED
	ship.panel.socket._apply_state()
	ship.panel._on_step_done()
	ship.panel.breaker.set_on(true, true)
	await _frames(150)
	await _shot("12_engineering_powered", Vector3(0, 1.7, -15.4), Vector3(0, 1.6, -21.3))
	await _shot("13_corridor_flicker", Vector3(0, 1.5, -0.8), Vector3(0, 1.3, -14.0))
	await _shot("14_power_panel_live", Vector3(-3.2, 1.5, -18.2), Vector3(-5.0, 1.45, -18.2))

	# --- Fully restored ---
	ship.breach.seal_all()
	ship.life_station.lever.set_on(true, true)
	for c in ship.compartments:
		c.pressure = ShipSystems.NOMINAL_KPA
	await _frames(10)
	ship.gravity_station.lever.set_on(true, true)
	for point in ship.repair_points:
		point.add_progress(1.0)
	for surface in ship.grime:
		surface.clean_all()
	for node in get_tree().get_nodes_in_group(&"debris"):
		var d := node as Debris
		if d.is_cleanup_item():
			d.collect(d.global_position)
			ship._on_deposited(d, ship.containers[0] if d.category == Debris.Category.SALVAGE else ship.containers[1])
	await _frames(240)
	await _shot("15_engineering_restored", Vector3(0, 1.6, -15.4), Vector3(0, 1.6, -21.3))
	await _shot("16_gravity_console", Vector3(0.2, 1.6, -17.6), Vector3(0, 1.3, -19.25))
	await _shot("17_breach_sealed", Vector3(3.3, 1.7, -20.6), Vector3(5.0, 1.9, -21.2))
	await _shot("18_corridor_restored", Vector3(0, 1.6, -0.8), Vector3(0, 1.3, -14.0))
	await _shot("19_corridor_from_eng", Vector3(0, 1.6, -13.6), Vector3(0, 1.4, 0.0))
	await _shot("20_airlock_terminal", Vector3(0.6, 1.6, 2.0), Vector3(2.0, 1.4, 1.25))
	ship.contract.refresh()
	ship.contract.sign_off()
	await _frames(120)
	await _shot("21_contract_complete", Vector3(0.6, 1.6, 2.0), Vector3(2.0, 1.4, 1.25))


func _shot(shot_name: String, eye: Vector3, target: Vector3) -> void:
	if not _only.is_empty() and not _only.has(shot_name.substr(0, 2)):
		return
	var body_y := eye.y if player.zero_g else eye.y - Player.EYE_OFFSET_WALK
	player.global_position = Vector3(eye.x, body_y, eye.z)
	player.velocity = Vector3.ZERO
	var d := (target - eye).normalized()
	player.set_look(atan2(-d.x, -d.z), asin(d.y))
	player.reset_interpolation()
	await _frames(14)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("saved ", shot_name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
