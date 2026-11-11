class_name PowerPanel
extends Node3D
## Main power distribution panel. Mounted with local +Z pointing out of the wall.
##
## Repair procedure (any order):
##   1. Splice both severed bus feeds (Splicer).
##   2. Pull the burnt fuse and seat a replacement cartridge.
## Only then will the main breaker latch. The panel reports `repaired` and
## `breaker_toggled`; the ship decides what those mean for its systems.

signal repaired
signal breaker_toggled(closed: bool)
signal debris_spawned(debris: Debris)

var feeds: Array[RepairPoint] = []
var socket: PartSocket
var breaker: LeverSwitch
var is_repaired := false

var _status: Label3D


func _ready() -> void:
	_build()
	_refresh()


func get_steps_done() -> int:
	var n := 0
	for f in feeds:
		if f.is_repaired:
			n += 1
	if socket.is_filled():
		n += 1
	return n


func get_steps_total() -> int:
	return feeds.size() + 1


func _on_step_done(_source: Variant = null) -> void:
	_refresh()
	if not is_repaired and get_steps_done() == get_steps_total():
		is_repaired = true
		Game.notify("Distribution panel repaired - breaker ready", &"good")
		repaired.emit()
		_refresh()


func _breaker_lock(_player: Player) -> String:
	if is_repaired:
		return ""
	return "Breaker will not latch: distribution fault (%d/%d repairs done)" % [get_steps_done(), get_steps_total()]


func _refresh() -> void:
	if _status == null:
		return
	var lines := PackedStringArray()
	for i in feeds.size():
		lines.append("BUS %s   %s" % [char(65 + i), "OK" if feeds[i].is_repaired else "OPEN CIRCUIT"])
	lines.append("FUSE F1 %s" % ("OK" if socket.is_filled() else "FAULT"))
	if not is_repaired:
		lines.append("** DISTRIBUTION FAULT **")
		_status.modulate = Color(1.0, 0.35, 0.25)
	elif breaker.is_on:
		lines.append("MAIN BUS LIVE")
		_status.modulate = Color(0.45, 1.0, 0.6)
	else:
		lines.append("READY - CLOSE BREAKER")
		_status.modulate = Color(1.0, 0.75, 0.3)
	_status.text = "\n".join(lines)


func _build() -> void:
	var casing := ShipMaterials.hull(Color(0.5, 0.42, 0.2), Vector2(0.7, 0.9), 0.75, 0.3, 0.65)
	ShipKit.box(self, Vector3(1.5, 1.9, 0.26), Vector3(0, 0, 0.13), casing)
	ShipKit.box(self, Vector3(1.3, 1.7, 0.02), Vector3(0, 0, 0.265), ShipMaterials.paint(Color(0.05, 0.05, 0.055), 0.9), false)
	# The cabinet door hangs open on its hinges.
	var door := ShipKit.box(self, Vector3(0.66, 1.7, 0.03), Vector3(-1.02, 0, 0.5), casing, false)
	door.rotation.y = deg_to_rad(-62.0)
	ShipKit.box(self, Vector3(1.5, 0.12, 0.3), Vector3(0, 1.0, 0.15), ShipMaterials.hazard(), false)
	ShipKit.stencil(self, "MAIN DISTRIBUTION", Vector3(0, 1.17, 0.0), Vector3.BACK, 0.1)
	ShipKit.stencil(self, "DANGER  440V", Vector3(0.33, -0.72, 0.275), Vector3.BACK, 0.06, Color(0.9, 0.3, 0.2))

	# Heavy cabling in from the ceiling.
	var cable := ShipMaterials.rubber(Color(0.08, 0.08, 0.085))
	for x in [-0.45, -0.25, 0.3]:
		ShipKit.cylinder(self, 0.035, 1.6, Vector3(x, 1.75, 0.1), cable)

	for i in 2:
		var feed := RepairPoint.new()
		feed.label = "Bus feed %s" % char(65 + i)
		feed.note = "Conductor burnt clean through. Still live on the supply side."
		feed.energized = true
		feed.position = Vector3(-0.33, 0.5 - i * 0.42, 0.275)
		feed.repaired.connect(_on_step_done)
		add_child(feed)
		feeds.append(feed)

	socket = PartSocket.new()
	socket.position = Vector3(-0.33, -0.48, 0.275)
	socket.filled.connect(_on_step_done)
	socket.old_part_removed.connect(func(_s: PartSocket, d: Debris) -> void: debris_spawned.emit(d))
	add_child(socket)

	breaker = LeverSwitch.new()
	breaker.label = "Main breaker"
	breaker.prompt_off = "Close breaker"
	breaker.prompt_on = "Open breaker"
	breaker.note = "Feeds every circuit aboard."
	breaker.position = Vector3(0.33, -0.2, 0.275)
	add_child(breaker)
	breaker.lock_check = _breaker_lock
	breaker.toggled.connect(func(on: bool) -> void:
		_refresh()
		breaker_toggled.emit(on))

	ShipKit.box(self, Vector3(0.52, 0.36, 0.02), Vector3(0.33, 0.45, 0.275), ShipMaterials.paint(Color(0.01, 0.012, 0.014), 0.3), false)
	_status = ShipKit.readout(self, "", Vector3(0.33, 0.45, 0.29), 0.036)
