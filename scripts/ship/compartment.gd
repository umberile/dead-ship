class_name Compartment
extends Node
## One pressure zone of a ship. Holds atmosphere state; ShipSystems simulates
## how it changes (pumps, leaks, flow through open doors).

@export var display_name := "Compartment"
## Interior volume in ship-local space.
@export var bounds := AABB()
## Has a life-support outlet, so the ship's pumps fill it directly.
@export var vented := false

## Absolute pressure in kPa.
var pressure := 0.0
## Local pump for self-contained compartments (the airlock):
## -1 evacuating, 0 idle, +1 filling.
var pump_mode := 0
var breaches: Array[HullBreach] = []


func get_volume() -> float:
	return maxf(1.0, bounds.size.x * bounds.size.y * bounds.size.z)


func contains(local_point: Vector3) -> bool:
	return bounds.grow(0.25).has_point(local_point)


## Combined open area of this compartment's breaches (0 = airtight).
func get_leak_factor() -> float:
	var total := 0.0
	for b in breaches:
		total += b.get_leak_factor()
	return total


func is_breached() -> bool:
	return get_leak_factor() > 0.0
