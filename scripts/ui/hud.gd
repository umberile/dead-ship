class_name Hud
extends CanvasLayer
## Minimal suit HUD. Everything is built in code from a handful of labels:
##   top-left     current objective (+ full task list while scanning)
##   top-right    ship system status and local environment
##   centre       reticle, contextual prompt, hold/work progress
##   bottom-right equipped tool / carried item
## plus toasts, the pause and help overlays, and the contract completion screen.

const AMBER := Color(1.0, 0.72, 0.25)
const TEAL := Color(0.45, 0.95, 0.85)
const RED := Color(1.0, 0.4, 0.32)
const GREEN := Color(0.5, 1.0, 0.6)
const DIM := Color(0.6, 0.66, 0.7)
const WHITE := Color(0.92, 0.95, 0.96)
const SCAN_TIME := 7.0
const STATE_COLORS := {
	ShipSystems.State.OFFLINE: RED,
	ShipSystems.State.STANDBY: AMBER,
	ShipSystems.State.BLOCKED: RED,
	ShipSystems.State.DEGRADED: AMBER,
	ShipSystems.State.ONLINE: GREEN,
}

var _root: Control
var _reticle: Reticle
var _markers: Markers
var _objective_title: Label
var _objective_hint: Label
var _checklist: VBoxContainer
var _system_labels := {}
var _env_label: Label
var _tool_labels: Array[Label] = []
var _tool_hint: Label
var _prompt_name: Label
var _prompt_detail: Label
var _prompt_action: Label
var _prompt_tool: Label
var _work_box: Control
var _work_bar: ProgressBar
var _work_label: Label
var _toasts: VBoxContainer
var _help: Control
var _pause: Control
var _intro: ColorRect
var _complete: Control
var _complete_text: Label

var _scan_left := 0.0
var _help_left := 22.0
var _intro_t := 0.0
var _complete_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	Game.notification_posted.connect(_on_notification)
	Game.contract_completed.connect(_on_contract_completed)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_scanning() -> bool:
	return _scan_left > 0.0


# --- Input --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _complete.visible:
		if event.is_action_pressed("confirm"):
			Game.restart()
		elif event is InputEventKey and event.pressed:
			if event.physical_keycode == KEY_C:
				_complete.visible = false
			elif event.physical_keycode == KEY_Q:
				get_tree().quit()
		return
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
	elif get_tree().paused:
		if event is InputEventKey and event.pressed:
			if event.physical_keycode == KEY_R:
				Game.restart()
			elif event.physical_keycode == KEY_Q:
				get_tree().quit()
	elif event.is_action_pressed("scan"):
		_scan_left = SCAN_TIME
		Sfx.play_ui(&"scan", -6.0)
	elif event.is_action_pressed("help"):
		_help_left = 0.0 if _help.visible else 3600.0


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


# --- Per-frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_intro(delta)
	_update_toasts(delta)
	var player := Game.player
	var ship := Game.ship
	if player == null or ship == null or get_tree().paused:
		return
	_scan_left = maxf(0.0, _scan_left - delta)
	_help_left = maxf(0.0, _help_left - delta)
	_help.visible = _help_left > 0.0
	_update_objective(ship)
	_update_systems(ship, player)
	_update_tools(player)
	_update_prompt(player)
	_reticle.queue_redraw()
	_markers.queue_redraw()


func _update_objective(ship: Ship) -> void:
	var contract := ship.contract
	var current := contract.get_current()
	if contract.is_complete:
		_objective_title.text = "Contract complete"
		_objective_hint.text = "%s is back in service." % ship.ship_name
	elif current == null:
		_objective_title.text = "File the recovery report"
		_objective_hint.text = "Contract terminal, east wall of the airlock."
	else:
		var progress := current.get_progress_text()
		_objective_title.text = current.title if progress == "" else "%s   [%s]" % [current.title, progress]
		_objective_hint.text = current.hint
	_objective_title.add_theme_color_override(&"font_color", GREEN if current == null else WHITE)

	_checklist.visible = is_scanning()
	if not _checklist.visible:
		return
	for i in contract.objectives.size():
		var o := contract.objectives[i]
		var line := _checklist.get_child(i) as Label
		var progress := o.get_progress_text()
		line.text = "%s %s%s" % ["[x]" if o.done else "[ ]", o.title, "" if progress == "" else "  %s" % progress]
		line.add_theme_color_override(&"font_color", GREEN if o.done else (WHITE if o == current else DIM))


func _update_systems(ship: Ship, player: Player) -> void:
	for id in ShipSystems.SYSTEM_IDS:
		var label := _system_labels[id] as Label
		label.text = ship.systems.get_status(id)
		label.add_theme_color_override(&"font_color", STATE_COLORS[ship.systems.get_state(id)])
	_env_label.text = "SUIT  %3d kPa  %s  LAMP %s" % [
		int(round(player.ambient_pressure)),
		"0.0 G" if player.zero_g else "1.0 G",
		"ON" if player.flashlight.visible else "OFF"]


func _update_tools(player: Player) -> void:
	var belt := player.tool_belt
	var carried := player.interactor.carried
	for i in _tool_labels.size():
		var active := i == belt.current_index and carried == null
		_tool_labels[i].add_theme_color_override(&"font_color", AMBER if active else DIM)
	if carried:
		var item: String = (carried as Debris).item_name if carried is Debris else str(carried.name)
		_tool_hint.text = "CARRYING: %s    [LMB] throw   [E] drop" % item.to_upper()
		_tool_hint.add_theme_color_override(&"font_color", TEAL)
	else:
		_tool_hint.text = "[1-3 / wheel] switch tool"
		_tool_hint.add_theme_color_override(&"font_color", DIM)


func _update_prompt(player: Player) -> void:
	var it := player.interactor
	var focus := it.focus
	_reticle.has_focus = focus != null
	_reticle.hold = it.hold_fraction
	_prompt_name.text = ""
	_prompt_detail.text = ""
	_prompt_action.text = ""
	_prompt_tool.text = ""
	_work_box.visible = false
	if focus == null:
		return

	_prompt_name.text = focus.display_name.to_upper()
	_prompt_detail.text = focus.status if focus.status != "" else focus.description

	# Interact key.
	if it.carried:
		if focus.accepts_item(it.carried):
			_prompt_action.text = "[E] %s" % focus.insert_prompt
			_prompt_action.add_theme_color_override(&"font_color", AMBER)
	elif focus.has_action():
		var reason := focus.get_blocked_reason(player)
		if reason != "":
			_prompt_action.text = "LOCKED"
			_prompt_action.add_theme_color_override(&"font_color", RED)
			_prompt_detail.text = reason
		else:
			_prompt_action.text = "%s %s" % ["[HOLD E]" if focus.hold_time > 0.0 else "[E]", focus.prompt]
			_prompt_action.add_theme_color_override(&"font_color", AMBER)

	# Tool work.
	if focus.needs_work and focus.tool_id != &"" and it.carried == null:
		var belt := player.tool_belt
		if belt.current and belt.current.tool_id == focus.tool_id:
			_prompt_tool.text = "[LMB] %s" % focus.tool_verb
			_prompt_tool.add_theme_color_override(&"font_color", TEAL)
		else:
			var needed := belt.get_tool(focus.tool_id)
			if needed:
				_prompt_tool.text = "Needs the %s  [%d]" % [needed.tool_name, belt.get_slot(focus.tool_id)]
			else:
				_prompt_tool.text = "Needs a tool you do not carry"
			_prompt_tool.add_theme_color_override(&"font_color", DIM)

	if focus.progress >= 0.0 and (focus.needs_work or it.tool_working):
		_work_box.visible = true
		_work_bar.value = focus.progress * 100.0
		_work_label.text = "%s   %d%%" % [focus.display_name.to_upper(), int(focus.progress * 100.0)]


# --- Toasts ---------------------------------------------------------------------------

func _on_notification(text: String, kind: StringName) -> void:
	var label := _label(text.to_upper(), 16, {&"good": GREEN, &"warn": RED}.get(kind, WHITE))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_meta(&"life", 4.5)
	_toasts.add_child(label)
	while _toasts.get_child_count() > 4:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()


func _update_toasts(delta: float) -> void:
	for child in _toasts.get_children():
		var life: float = child.get_meta(&"life") - delta
		child.set_meta(&"life", life)
		(child as Label).modulate.a = clampf(life, 0.0, 1.0)
		if life <= 0.0:
			child.queue_free()


# --- Intro and completion ----------------------------------------------------------------

func _update_intro(delta: float) -> void:
	if not _intro.visible:
		return
	_intro_t += delta
	_intro.modulate.a = 1.0 - smoothstep(3.0, 5.5, _intro_t)
	if _intro_t > 5.5:
		_intro.visible = false


func _on_contract_completed(summary: Dictionary) -> void:
	if _complete_shown:
		return
	_complete_shown = true
	var secs := int(summary.get("elapsed", 0.0))
	var lines := PackedStringArray([
		"RECOVERY CONTRACT %s  -  COMPLETE" % summary.get("contract_id", ""),
		"",
		"%s  RECOMMISSIONED" % str(summary.get("vessel", "")).to_upper(),
		"Power, atmosphere, gravity and lighting restored.",
		"",
		"Time on site ............ %02d:%02d" % [secs / 60, secs % 60],
		"Contract fee ............ %5d cr" % summary.get("base_fee", 0),
		"Salvage stowed (%d/%d) .... %5d cr" % [summary.get("salvage_recovered", 0), summary.get("salvage_total", 0), summary.get("salvage_value", 0)],
	])
	if summary.get("salvage_scrapped", 0) > 0:
		lines.append("Salvage scrapped ........ %5d item(s), no payout" % summary.get("salvage_scrapped", 0))
	lines.append("")
	lines.append("TOTAL PAYOUT ............ %5d cr" % summary.get("total", 0))
	lines.append("")
	lines.append("[ENTER] New contract     [C] Stay aboard     [Q] Quit")
	_complete_text.text = "\n".join(lines)
	Sfx.play_ui(&"complete", -2.0)
	_complete.modulate.a = 0.0
	_complete.visible = true
	create_tween().tween_property(_complete, "modulate:a", 1.0, 1.2)


# --- Construction -------------------------------------------------------------------------

func _build() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Menlo", "monospace"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0.85))
	theme.set_constant(&"shadow_offset_x", &"Label", 1)
	theme.set_constant(&"shadow_offset_y", &"Label", 1)

	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_markers = Markers.new()
	_markers.hud = self
	_markers.font = font
	_full_rect(_markers)
	_reticle = Reticle.new()
	_full_rect(_reticle)

	# Objective (top-left).
	var obj_panel := _panel(AMBER)
	obj_panel.position = Vector2(24, 24)
	obj_panel.custom_minimum_size = Vector2(470, 0)
	_root.add_child(obj_panel)
	var obj_box := VBoxContainer.new()
	obj_box.add_theme_constant_override(&"separation", 3)
	obj_panel.add_child(obj_box)
	var contract := Game.contract
	var header := "RECOVERY CONTRACT"
	if contract:
		header = "%s  //  %s  //  %s" % [contract.contract_id, contract.vessel_name.to_upper(), contract.client.to_upper()]
	obj_box.add_child(_label(header, 12, DIM))
	_objective_title = _label("", 18, WHITE)
	_objective_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_box.add_child(_objective_title)
	_objective_hint = _label("", 14, AMBER)
	_objective_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_box.add_child(_objective_hint)
	_checklist = VBoxContainer.new()
	_checklist.add_theme_constant_override(&"separation", 1)
	_checklist.visible = false
	obj_box.add_child(_checklist)
	if contract:
		for o in contract.objectives:
			_checklist.add_child(_label("", 13, DIM))

	# Ship systems (top-right).
	var sys_panel := _panel(TEAL)
	sys_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sys_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sys_panel.position = Vector2(-24, 24)
	sys_panel.custom_minimum_size = Vector2(360, 0)
	_root.add_child(sys_panel)
	var sys_box := VBoxContainer.new()
	sys_box.add_theme_constant_override(&"separation", 2)
	sys_panel.add_child(sys_box)
	sys_box.add_child(_label("SHIP SYSTEMS", 12, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 14)
	sys_box.add_child(grid)
	for id in ShipSystems.SYSTEM_IDS:
		grid.add_child(_label(ShipSystems.SYSTEM_NAMES[id], 14, DIM))
		var status := _label("", 14, WHITE)
		grid.add_child(status)
		_system_labels[id] = status
	_env_label = _label("", 13, DIM)
	sys_box.add_child(_env_label)

	# Tools (bottom-right).
	var tool_panel := _panel(AMBER)
	tool_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tool_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tool_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tool_panel.position = Vector2(-24, -24)
	_root.add_child(tool_panel)
	var tool_box := VBoxContainer.new()
	tool_panel.add_child(tool_box)
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override(&"separation", 18)
	tool_box.add_child(tool_row)
	if Game.player:
		var tools := Game.player.tool_belt.tools
		for i in tools.size():
			var l := _label("[%d] %s" % [i + 1, tools[i].tool_name.to_upper()], 16, DIM)
			tool_row.add_child(l)
			_tool_labels.append(l)
	_tool_hint = _label("", 12, DIM)
	tool_box.add_child(_tool_hint)

	# Contextual prompt (under the reticle).
	var prompt := VBoxContainer.new()
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.5
	prompt.anchor_bottom = 0.5
	prompt.offset_left = -320
	prompt.offset_right = 320
	prompt.offset_top = 38
	prompt.add_theme_constant_override(&"separation", 2)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(prompt)
	_prompt_name = _centered(_label("", 16, WHITE))
	_prompt_detail = _centered(_label("", 13, DIM))
	_prompt_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_action = _centered(_label("", 16, AMBER))
	_prompt_tool = _centered(_label("", 16, TEAL))
	for l in [_prompt_name, _prompt_detail, _prompt_action, _prompt_tool]:
		prompt.add_child(l)

	# Work progress (bottom centre).
	var work := VBoxContainer.new()
	work.anchor_left = 0.5
	work.anchor_right = 0.5
	work.anchor_top = 1.0
	work.anchor_bottom = 1.0
	work.offset_left = -200
	work.offset_right = 200
	work.offset_top = -120
	work.offset_bottom = -84
	work.visible = false
	_root.add_child(work)
	_work_box = work
	_work_label = _centered(_label("", 13, WHITE))
	work.add_child(_work_label)
	_work_bar = ProgressBar.new()
	_work_bar.show_percentage = false
	_work_bar.custom_minimum_size = Vector2(400, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.04, 0.05, 0.75)
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	_work_bar.add_theme_stylebox_override(&"background", bg)
	_work_bar.add_theme_stylebox_override(&"fill", fill)
	work.add_child(_work_bar)

	# Toasts (top centre).
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -400
	_toasts.offset_right = 400
	_toasts.offset_top = 96
	_toasts.add_theme_constant_override(&"separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)

	# Controls help (bottom-left).
	var help_panel := _panel(DIM)
	help_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_panel.position = Vector2(24, -24)
	_root.add_child(help_panel)
	help_panel.add_child(_label("\n".join(PackedStringArray([
		"WASD        move / thrust",
		"SPACE CTRL  jump / thrust up, down",
		"Z  C        roll (zero-g)",
		"SHIFT       sprint / stabilise (zero-g)",
		"E           interact, pick up, drop",
		"LMB         use tool / throw",
		"1 2 3       scrubber, sealer, splicer",
		"F           suit lamp",
		"TAB         scan + task list",
		"F1          toggle this help    ESC  pause",
	])), 13, DIM))
	_help = help_panel

	# Intro card.
	_intro = ColorRect.new()
	_intro.color = Color(0, 0, 0, 1)
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_rect(_intro)
	var intro_text := "RECOVERY CONTRACT"
	if contract:
		intro_text = "%s\n\nRECOVERY CONTRACT %s\n%s  -  adrift, no transponder, no crew aboard\n\nBoard her. Get her running. Leave her clean." % [
			contract.client.to_upper(), contract.contract_id, contract.vessel_name.to_upper()]
	var intro_label := _centered(_label(intro_text, 18, WHITE))
	intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro.add_child(intro_label)
	intro_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Pause.
	_pause = _overlay("PAUSED\n\n[ESC] Resume     [R] Restart contract     [Q] Quit", 20)
	# Completion.
	_complete = _overlay("", 18)
	_complete_text = _complete.get_meta(&"label") as Label
	_complete_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _panel(accent: Color) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.04, 0.5)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	style.border_width_left = 2
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _full_rect(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## A dimmed full-screen overlay with one centred panel of text. The text label
## is stored in the overlay's "label" meta.
func _overlay(text: String, size: int) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.visible = false
	_full_rect(dim)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _panel(AMBER)
	centre.add_child(panel)
	var label := _centered(_label(text, size, WHITE))
	panel.add_child(label)
	dim.set_meta(&"label", label)
	return dim


# --- Custom-drawn pieces ----------------------------------------------------------------

class Reticle:
	extends Control
	var has_focus := false
	var hold := 0.0

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 1.6, Color(1, 1, 1, 0.85))
		if has_focus:
			draw_arc(c, 9.0, 0.0, TAU, 32, Color(1.0, 0.72, 0.25, 0.75), 1.5, true)
		if hold > 0.0:
			draw_arc(c, 15.0, -PI * 0.5, -PI * 0.5 + TAU * hold, 40, Color(1.0, 0.72, 0.25), 3.0, true)


class Markers:
	extends Control
	var hud: Hud
	var font: Font

	func _draw() -> void:
		if hud == null or not hud.is_scanning() or Game.player == null or Game.ship == null:
			return
		var cam := Game.player.camera
		var fade := clampf(hud._scan_left, 0.0, 1.0)
		for t: Dictionary in Game.ship.get_scan_targets():
			var pos: Vector3 = t["position"]
			if cam.is_position_behind(pos):
				continue
			var p := cam.unproject_position(pos)
			var col: Color = t["color"]
			col.a = fade
			var d := 7.0
			draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]), col, 1.5, true)
			var text := "%s %dm" % [t["label"], int(round(cam.global_position.distance_to(pos)))]
			draw_string(font, p + Vector2(11, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
