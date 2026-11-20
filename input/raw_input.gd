class_name RawInput
extends RefCounted
# One device's raw state for one frame, before any mapping.
# Keyboard and controller readers both produce this same record.
# Sticks are floats from -1 to 1 with stick up = +Y (flip Godot's joypad Y before storing).
# This is input-layer data only; floats are fine here because it never enters sim/.

var left_stick: Vector2 = Vector2.ZERO
var right_stick: Vector2 = Vector2.ZERO
var held: Dictionary = {}   # source id (int) -> true, for every digital source held

# Convenience for tests: build a record from source id strings.
# Fails loudly on a bad string so typos in tests don't pass silently.
static func make(left: Vector2, right: Vector2, held_source_strings: Array) -> RawInput:
	var r: RawInput = RawInput.new()
	r.left_stick = left
	r.right_stick = right
	for s in held_source_strings:
		var id: int = SourceId.from_str(s)
		assert(id != SourceId.INVALID, "RawInput.make: bad source string '%s'" % s)
		r.held[id] = true
	return r

func is_held(source_id: int) -> bool:
	return held.has(source_id)
