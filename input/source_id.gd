class_name SourceId
# A physical input source (a key, a joypad button, a trigger) as one int.
#
# Runtime form : (kind << 32) | code
# Saved form   : strings like "key:K", "key_l:Shift", "joy_btn:A", "joy_axis+:TriggerLeft"
#
# Saved files use strings because Godot's enum numbers can change between versions,
# and a saved int could silently remap to a different key after an engine upgrade.
# Keyboard codes are PHYSICAL keycodes (key position), so layouts like "K beside L"
# keep their shape on non-QWERTY keyboards.

const INVALID: int = -1

const KIND_KEY: int = 1           # keyboard key, either side
const KIND_KEY_LEFT: int = 2      # left-side key only (Shift, Alt, Ctrl, Meta)
const KIND_KEY_RIGHT: int = 3     # right-side key only
const KIND_JOY_BUTTON: int = 4
const KIND_JOY_AXIS_POS: int = 5  # axis pushed positive, treated as a button (triggers)
const KIND_JOY_AXIS_NEG: int = 6  # axis pushed negative, treated as a button

const KIND_SHIFT: int = 32
const CODE_MASK: int = 0xFFFFFFFF  # special keys have codes around 4 million; need 32 bits

const _PREFIXES: Dictionary = {
	KIND_KEY: "key:",
	KIND_KEY_LEFT: "key_l:",
	KIND_KEY_RIGHT: "key_r:",
	KIND_JOY_BUTTON: "joy_btn:",
	KIND_JOY_AXIS_POS: "joy_axis+:",
	KIND_JOY_AXIS_NEG: "joy_axis-:",
}

# Joypad buttons are position-based in Godot: A is the bottom face button on any pad.
const _JOY_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LeftStick",
	JOY_BUTTON_RIGHT_STICK: "RightStick",
	JOY_BUTTON_LEFT_SHOULDER: "LeftShoulder",
	JOY_BUTTON_RIGHT_SHOULDER: "RightShoulder",
	JOY_BUTTON_DPAD_UP: "DpadUp",
	JOY_BUTTON_DPAD_DOWN: "DpadDown",
	JOY_BUTTON_DPAD_LEFT: "DpadLeft",
	JOY_BUTTON_DPAD_RIGHT: "DpadRight",
}

const _JOY_AXIS_NAMES: Dictionary = {
	JOY_AXIS_LEFT_X: "LeftX",
	JOY_AXIS_LEFT_Y: "LeftY",
	JOY_AXIS_RIGHT_X: "RightX",
	JOY_AXIS_RIGHT_Y: "RightY",
	JOY_AXIS_TRIGGER_LEFT: "TriggerLeft",
	JOY_AXIS_TRIGGER_RIGHT: "TriggerRight",
}

# --- Packing ---
static func make(kind: int, code: int) -> int:
	return (kind << KIND_SHIFT) | (code & CODE_MASK)

static func kind_of(id: int) -> int:
	return (id >> KIND_SHIFT) & 0xFF

static func code_of(id: int) -> int:
	return id & CODE_MASK

# Keys that exist in a left and a right version.
static func has_sides(keycode: int) -> bool:
	return keycode == KEY_SHIFT or keycode == KEY_ALT or keycode == KEY_CTRL or keycode == KEY_META

static func is_key_kind(kind: int) -> bool:
	return kind == KIND_KEY or kind == KIND_KEY_LEFT or kind == KIND_KEY_RIGHT

# A left/right key also counts as its generic version ("key_l:Shift" satisfies "key:Shift").
static func generic_of(id: int) -> int:
	var kind: int = kind_of(id)
	if kind == KIND_KEY_LEFT or kind == KIND_KEY_RIGHT:
		return make(KIND_KEY, code_of(id))
	return id

# --- Saved form (strings) ---
static func to_str(id: int) -> String:
	if id < 0:
		return ""
	var kind: int = kind_of(id)
	var code: int = code_of(id)
	var prefix: String = _PREFIXES.get(kind, "")
	if prefix == "":
		return ""
	var source_name: String = ""
	if is_key_kind(kind):
		source_name = OS.get_keycode_string(code as Key)
	elif kind == KIND_JOY_BUTTON:
		source_name = _JOY_BUTTON_NAMES.get(code, "")
	elif kind == KIND_JOY_AXIS_POS or kind == KIND_JOY_AXIS_NEG:
		source_name = _JOY_AXIS_NAMES.get(code, "")
	if source_name == "":
		return ""
	return prefix + source_name

# Returns INVALID for anything unrecognized. Never guesses.
static func from_str(text: String) -> int:
	for kind in _PREFIXES:
		var prefix: String = _PREFIXES[kind]
		if text.begins_with(prefix):
			var code: int = _code_from_name(kind, text.substr(prefix.length()))
			if code < 0:
				return INVALID
			return make(kind, code)
	return INVALID

static func _code_from_name(kind: int, source_name: String) -> int:
	if is_key_kind(kind):
		var keycode: int = OS.find_keycode_from_string(source_name)
		if keycode == KEY_NONE:
			return -1
		# Reject "Shift+K" style strings; a source is a single key.
		if (keycode & KEY_MODIFIER_MASK) != 0:
			return -1
		if kind != KIND_KEY and not has_sides(keycode):
			return -1
		return keycode
	if kind == KIND_JOY_BUTTON:
		for code in _JOY_BUTTON_NAMES:
			if _JOY_BUTTON_NAMES[code] == source_name:
				return code
		return -1
	for code in _JOY_AXIS_NAMES:
		if _JOY_AXIS_NAMES[code] == source_name:
			return code
	return -1

# --- Display (for a future rebinding screen) ---
static func label(id: int) -> String:
	var kind: int = kind_of(id)
	var code: int = code_of(id)
	if kind == KIND_KEY:
		return OS.get_keycode_string(code as Key)
	if kind == KIND_KEY_LEFT:
		return "Left " + OS.get_keycode_string(code as Key)
	if kind == KIND_KEY_RIGHT:
		return "Right " + OS.get_keycode_string(code as Key)
	if kind == KIND_JOY_BUTTON:
		var button_name: String = _JOY_BUTTON_NAMES.get(code, "?")
		return "Joypad " + button_name
	if kind == KIND_JOY_AXIS_POS:
		var axis_name: String = _JOY_AXIS_NAMES.get(code, "?")
		return "Joypad " + axis_name + " +"
	if kind == KIND_JOY_AXIS_NEG:
		var axis_name_neg: String = _JOY_AXIS_NAMES.get(code, "?")
		return "Joypad " + axis_name_neg + " -"
	return "?"

# --- From a live keyboard event ---
# Uses the physical key position. Shift/Alt/Ctrl/Meta report left or right when
# the platform provides it; otherwise they fall back to the generic key.
static func id_from_key_event(event: InputEventKey) -> int:
	var code: int = event.physical_keycode
	if code == KEY_NONE:
		code = event.keycode
	if code == KEY_NONE:
		return INVALID
	var kind: int = KIND_KEY
	if has_sides(code):
		if event.location == KEY_LOCATION_LEFT:
			kind = KIND_KEY_LEFT
		elif event.location == KEY_LOCATION_RIGHT:
			kind = KIND_KEY_RIGHT
	return make(kind, code)
