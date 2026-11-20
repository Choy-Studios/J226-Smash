class_name KeyboardReader
extends Node
# Tracks which keyboard sources are held, using key events.
# Events (not polling) are used because only events report left vs right Shift/Alt.
# Add this as a child node somewhere in the match scene.
# Each sim tick, call snapshot() and put the result in RawInput.held.

var _held: Dictionary = {}   # source id -> true (specific left/right ids when known)

func _input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or key_event.echo:
		return
	var id: int = SourceId.id_from_key_event(key_event)
	if id == SourceId.INVALID:
		return
	if key_event.pressed:
		_held[id] = true
	else:
		_held.erase(id)

# Stuck keys are a real problem: releasing a key while the window is unfocused
# sends no event. Clear everything whenever focus is lost.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_held.clear()

# A copy of what is held right now. Left/right keys also appear as their generic
# version, so a binding to "key:Shift" matches either Shift key.
func snapshot() -> Dictionary:
	var out: Dictionary = _held.duplicate()
	for id in _held:
		out[SourceId.generic_of(id)] = true
	return out
