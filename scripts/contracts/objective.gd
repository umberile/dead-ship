class_name Objective
extends RefCounted
## One line of a recovery contract. Completion is polled through `check`, so
## objectives stay decoupled from whatever they are watching.

var id: StringName
var title := ""
## One-line nudge shown under the title while this is the current objective.
var hint := ""
## `func() -> bool`.
var check := Callable()
## Optional `func() -> String`, e.g. "3/5" or "62%".
var progress := Callable()
## Sticky objectives stay complete once achieved (e.g. "board the ship").
## Others follow the live state, so breaking something un-ticks it.
var sticky := false
var done := false


func _init(p_id: StringName, p_title: String, p_check: Callable, p_hint := "",
		p_progress := Callable(), p_sticky := false) -> void:
	id = p_id
	title = p_title
	check = p_check
	hint = p_hint
	progress = p_progress
	sticky = p_sticky


func get_progress_text() -> String:
	return str(progress.call()) if progress.is_valid() else ""
