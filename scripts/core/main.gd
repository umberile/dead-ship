extends Node3D
## Entry point: puts a ship, the player and the HUD together.
## Swap `ship_scene` to load a different vessel/contract.

@export var ship_scene: PackedScene
@export var player_scene: PackedScene
@export var hud_scene: PackedScene


func _ready() -> void:
	var ship := ship_scene.instantiate() as Ship
	add_child(ship)
	Game.ship = ship
	Game.contract = ship.contract

	var player := player_scene.instantiate() as Player
	add_child(player)
	player.global_position = ship.to_global(ship.spawn_position)
	player.set_look(ship.spawn_yaw, 0.0)
	player.reset_interpolation()
	Game.player = player

	var hud := hud_scene.instantiate() as Hud
	add_child(hud)
	Game.hud = hud
