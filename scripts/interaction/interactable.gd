class_name Interactable
extends Node
## Reusable interaction component.
##
## Add one as a child of any CollisionObject3D (or link it to several colliders
## with `link()`), then configure it and listen to its signals. The player's
## Interactor finds it by raycast and never needs to know what the object is.
##
## One component can expose up to three kinds of affordance:
##   * an action on the interact key (`prompt`, optional `hold_time`)
##   * tool work with the use key (`tool_id`, `needs_work`, `progress`)
##   * a socket for a carried item (`accepted_item`)
## plus `display_name` / `description` / `status`, which are shown whenever the
## player looks at the object (inspection).

signal interacted(player: Player)
signal tool_applied(tool: Tool, position: Vector3, normal: Vector3, delta: float)
signal item_inserted(player: Player, item: RigidBody3D)

@export var display_name := ""
@export_multiline var description := ""
## Verb shown for the interact key. Empty means "nothing to operate here".
@export var prompt := ""
## Seconds the interact key must be held. 0 = instant.
@export var hold_time := 0.0
@export var enabled := true

@export_group("Tool work")
## Id of the tool that can work on this target (see Tool.tool_id).
@export var tool_id: StringName = &""
@export var tool_verb := "Use"

@export_group("Item socket")
## Debris.item_id this socket accepts from the player's hands.
@export var accepted_item: StringName = &""
@export var insert_prompt := "Insert"

## Short live state line, e.g. "SEALED 40%". Shown instead of the description.
var status := ""
## True while there is still work for the tool to do.
var needs_work := false
## 0..1 while the object has measurable progress, otherwise negative.
var progress := -1.0
## Optional `func(player) -> String`. A non-empty result blocks the action and
## is shown to the player as the reason.
var blocked_check := Callable()


## Returns the Interactable attached or linked to a collider, if any.
static func find(collider: Object) -> Interactable:
	var node := collider as Node
	if node == null:
		return null
	if node.has_meta(&"interactable"):
		return node.get_meta(&"interactable") as Interactable
	for child in node.get_children():
		if child is Interactable:
			return child
	return null


## Makes an additional collider resolve to this component.
func link(collider: Node) -> void:
	collider.set_meta(&"interactable", self)


func has_action() -> bool:
	return prompt != ""


func get_blocked_reason(player: Player) -> String:
	if blocked_check.is_valid():
		return str(blocked_check.call(player))
	return ""


func interact(player: Player) -> void:
	interacted.emit(player)


func accepts_tool(id: StringName) -> bool:
	return needs_work and tool_id != &"" and id == tool_id


func apply_tool(tool: Tool, position: Vector3, normal: Vector3, delta: float) -> void:
	tool_applied.emit(tool, position, normal, delta)


func accepts_item(item: RigidBody3D) -> bool:
	if accepted_item == &"" or item == null:
		return false
	return item is Debris and (item as Debris).item_id == accepted_item


func insert_item(player: Player, item: RigidBody3D) -> void:
	item_inserted.emit(player, item)
