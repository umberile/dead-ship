class_name ToolBelt
extends Node
## Owns the player's tools and handles switching between them. Tools are
## interchangeable: anything extending Tool can be added with `add_tool`.

signal tool_changed(tool: Tool)

var player: Player
var tools: Array[Tool] = []
var current: Tool
var current_index := -1


func setup(p: Player) -> void:
	player = p
	add_tool(ScrubberTool.new())
	add_tool(SealerTool.new())
	add_tool(SplicerTool.new())
	equip(0)
	player.interactor.carried_changed.connect(_on_carried_changed)


func add_tool(tool: Tool) -> void:
	tool.name = tool.tool_name.replace(" ", "")
	player.tool_mount.add_child(tool)
	tools.append(tool)


func equip(index: int) -> void:
	if index < 0 or index >= tools.size() or index == current_index:
		return
	if current:
		current.unequip()
	current_index = index
	current = tools[index]
	if player.interactor.carried == null:
		current.equip()
	Sfx.play_ui(&"click", -10.0, 1.3)
	tool_changed.emit(current)


## 1-based slot number of the tool with this id, or 0 if the player lacks it.
func get_slot(tool_id: StringName) -> int:
	for i in tools.size():
		if tools[i].tool_id == tool_id:
			return i + 1
	return 0


func get_tool(tool_id: StringName) -> Tool:
	var slot := get_slot(tool_id)
	return tools[slot - 1] if slot > 0 else null


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.input_enabled or tools.is_empty():
		return
	if event.is_action_pressed("tool_1"):
		equip(0)
	elif event.is_action_pressed("tool_2"):
		equip(1)
	elif event.is_action_pressed("tool_3"):
		equip(2)
	elif event.is_action_pressed("tool_next"):
		equip((current_index + 1) % tools.size())
	elif event.is_action_pressed("tool_prev"):
		equip((current_index - 1 + tools.size()) % tools.size())


func _on_carried_changed(body: RigidBody3D) -> void:
	# Hands are full while carrying: stow the tool.
	if current == null:
		return
	if body:
		current.unequip()
	else:
		current.equip()
