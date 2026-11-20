class_name JoypadReader
# Polls one controller. No node needed; call these once per sim tick.
# Only sources that appear in the compiled bindings are read.

const AXIS_PRESS_THRESHOLD: float = 0.5   # trigger/axis counts as "pressed" past this

static func read_held(device: int, compiled: CompiledBindings) -> Dictionary:
	var held: Dictionary = {}
	for source_id in compiled.sources():
		var kind: int = SourceId.kind_of(source_id)
		var code: int = SourceId.code_of(source_id)
		if kind == SourceId.KIND_JOY_BUTTON:
			if Input.is_joy_button_pressed(device, code as JoyButton):
				held[source_id] = true
		elif kind == SourceId.KIND_JOY_AXIS_POS:
			if Input.get_joy_axis(device, code as JoyAxis) > AXIS_PRESS_THRESHOLD:
				held[source_id] = true
		elif kind == SourceId.KIND_JOY_AXIS_NEG:
			if Input.get_joy_axis(device, code as JoyAxis) < -AXIS_PRESS_THRESHOLD:
				held[source_id] = true
	return held

# Godot reports stick up as NEGATIVE Y. The whole project uses up = +Y, so flip it here
# and nowhere else.
static func left_stick(device: int) -> Vector2:
	return Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		-Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))

static func right_stick(device: int) -> Vector2:
	return Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		-Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
