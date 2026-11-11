class_name Contract
extends Node
## A recovery contract: an ordered list of objectives plus the payout terms.
## The ship that owns the contract supplies the objectives; this class only
## tracks them, so different ships and contract types can reuse it.

signal objective_completed(objective: Objective)
signal objective_reopened(objective: Objective)
signal ready_for_signoff
signal completed(summary: Dictionary)

@export var contract_id := "RC-0000"
@export var vessel_name := "Unknown vessel"
@export var client := ""
@export var base_fee := 0

var objectives: Array[Objective] = []
var is_complete := false
var elapsed := 0.0
var salvage_recovered := 0
var salvage_recovered_value := 0
var salvage_scrapped := 0
var salvage_total := 0
var salvage_total_value := 0

var _poll := 0.0
var _was_ready := false


func add_objective(objective: Objective) -> Objective:
	objectives.append(objective)
	return objective


func get_objective(id: StringName) -> Objective:
	for o in objectives:
		if o.id == id:
			return o
	return null


## First objective still open, or null when everything is done.
func get_current() -> Objective:
	for o in objectives:
		if not o.done:
			return o
	return null


func get_done_count() -> int:
	var n := 0
	for o in objectives:
		if o.done:
			n += 1
	return n


## True when every objective is satisfied and the report can be filed.
func is_ready_for_signoff() -> bool:
	return get_current() == null


func _process(delta: float) -> void:
	if is_complete:
		return
	elapsed += delta
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		refresh()


## Re-evaluates every objective now.
func refresh() -> void:
	for o in objectives:
		var now: bool = o.check.call() if o.check.is_valid() else false
		if o.sticky and o.done:
			continue
		if now and not o.done:
			o.done = true
			objective_completed.emit(o)
		elif not now and o.done:
			o.done = false
			objective_reopened.emit(o)
	var ready := is_ready_for_signoff()
	if ready and not _was_ready:
		ready_for_signoff.emit()
	_was_ready = ready


## Files the report. Returns false if work is still outstanding.
func sign_off() -> bool:
	refresh()
	if is_complete or not is_ready_for_signoff():
		return false
	is_complete = true
	var summary := {
		"contract_id": contract_id,
		"vessel": vessel_name,
		"client": client,
		"elapsed": elapsed,
		"base_fee": base_fee,
		"salvage_recovered": salvage_recovered,
		"salvage_total": salvage_total,
		"salvage_value": salvage_recovered_value,
		"salvage_scrapped": salvage_scrapped,
		"total": base_fee + salvage_recovered_value,
	}
	completed.emit(summary)
	Game.contract_completed.emit(summary)
	return true
