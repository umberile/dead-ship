extends Node
## Autoload `Game`: a small registry for the objects every system needs to find
## (player, ship, contract, HUD) plus a message bus for player-facing notices.
## Gameplay rules live on the ship and contract, not here.

signal notification_posted(text: String, kind: StringName)
signal contract_completed(summary: Dictionary)

var player: Player
var ship: Ship
var contract: Contract
var hud: Hud


## Shows a short toast on the HUD. `kind` is &"info", &"good" or &"warn".
func notify(text: String, kind: StringName = &"info") -> void:
	notification_posted.emit(text, kind)


func restart() -> void:
	get_tree().paused = false
	player = null
	ship = null
	contract = null
	hud = null
	get_tree().reload_current_scene()
