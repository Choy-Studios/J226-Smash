class_name InputBinding
extends RefCounted
# One binding: a physical source -> one logical target.
# Targets: a button bit, a stick direction (with a signed value), or a modifier.

const TARGET_BUTTON: int = 0
const TARGET_STICK: int = 1
const TARGET_MODIFIER: int = 2

const STICK_LEFT_X: int = 0
const STICK_LEFT_Y: int = 1    # stick up = +Y
const STICK_RIGHT_X: int = 2
const STICK_RIGHT_Y: int = 3

const MOD_WALK: int = 0
const MOD_TAUNT: int = 1

# Names used in saved JSON. Never rename these once profiles exist in the wild.
const TARGET_NAMES: Dictionary = {
	"button": TARGET_BUTTON,
	"stick": TARGET_STICK,
	"modifier": TARGET_MODIFIER,
}
const STICK_NAMES: Dictionary = {
	"left_x": STICK_LEFT_X,
	"left_y": STICK_LEFT_Y,
	"right_x": STICK_RIGHT_X,
	"right_y": STICK_RIGHT_Y,
}
const MOD_NAMES: Dictionary = {
	"walk": MOD_WALK,
	"taunt": MOD_TAUNT,
}
const BUTTON_NAMES: Dictionary = {
	"normal": InputFrame.NORMAL,
	"special": InputFrame.SPECIAL,
	"jump": InputFrame.JUMP,
	"short_hop": InputFrame.SHORT_HOP,
	"super": InputFrame.SUPER,
	"grab": InputFrame.GRAB,
	"shield": InputFrame.SHIELD,
	"taunt_up": InputFrame.TAUNT_UP,
	"taunt_down": InputFrame.TAUNT_DOWN,
	"taunt_left": InputFrame.TAUNT_LEFT,
	"taunt_right": InputFrame.TAUNT_RIGHT,
	"smash": InputFrame.SMASH,
}

var source: int = SourceId.INVALID
var target_type: int = TARGET_BUTTON
var target_id: int = 0   # button bit, stick channel, or modifier id (depends on target_type)
var value: int = 0       # sticks only: signed, nonzero, -127..127

# --- Builders ---
static func make_button(source_id: int, button_bit: int) -> InputBinding:
	var b: InputBinding = InputBinding.new()
	b.source = source_id
	b.target_type = TARGET_BUTTON
	b.target_id = button_bit
	return b

static func make_stick(source_id: int, stick_channel: int, stick_value: int) -> InputBinding:
	var b: InputBinding = InputBinding.new()
	b.source = source_id
	b.target_type = TARGET_STICK
	b.target_id = stick_channel
	b.value = stick_value
	return b

static func make_modifier(source_id: int, modifier_id: int) -> InputBinding:
	var b: InputBinding = InputBinding.new()
	b.source = source_id
	b.target_type = TARGET_MODIFIER
	b.target_id = modifier_id
	return b

# --- JSON ---
func to_dict() -> Dictionary:
	var d: Dictionary = {
		"source": SourceId.to_str(source),
		"target": _name_for(TARGET_NAMES, target_type),
	}
	if target_type == TARGET_BUTTON:
		d["name"] = _name_for(BUTTON_NAMES, target_id)
	elif target_type == TARGET_STICK:
		d["name"] = _name_for(STICK_NAMES, target_id)
		d["value"] = value
	else:
		d["name"] = _name_for(MOD_NAMES, target_id)
	return d

# Returns null (and appends to errors) if anything is wrong. Never guesses.
static func from_dict(data: Variant, errors: Array, index: int) -> InputBinding:
	var where: String = "binding %d" % index
	if not (data is Dictionary):
		errors.append(where + ": not an object")
		return null
	var d: Dictionary = data

	var source_text: Variant = d.get("source")
	if not (source_text is String):
		errors.append(where + ": missing source")
		return null
	var source_id: int = SourceId.from_str(source_text)
	if source_id == SourceId.INVALID:
		errors.append(where + ": unknown source '%s'" % source_text)
		return null

	var target_text: Variant = d.get("target")
	if not (target_text is String) or not TARGET_NAMES.has(target_text):
		errors.append(where + ": unknown target type")
		return null
	var type_id: int = TARGET_NAMES[target_text]

	var name_text: Variant = d.get("name")
	if not (name_text is String):
		errors.append(where + ": missing target name")
		return null

	if type_id == TARGET_BUTTON:
		if not BUTTON_NAMES.has(name_text):
			errors.append(where + ": unknown button '%s'" % name_text)
			return null
		return make_button(source_id, BUTTON_NAMES[name_text])

	if type_id == TARGET_MODIFIER:
		if not MOD_NAMES.has(name_text):
			errors.append(where + ": unknown modifier '%s'" % name_text)
			return null
		return make_modifier(source_id, MOD_NAMES[name_text])

	# Stick
	if not STICK_NAMES.has(name_text):
		errors.append(where + ": unknown stick '%s'" % name_text)
		return null
	var raw_value: Variant = d.get("value")
	if not (raw_value is float or raw_value is int):
		errors.append(where + ": stick binding needs a numeric value")
		return null
	var stick_value: int = int(raw_value)
	if stick_value == 0 or absi(stick_value) > InputFrame.STICK_MAX:
		errors.append(where + ": stick value must be nonzero and within +-%d" % InputFrame.STICK_MAX)
		return null
	return make_stick(source_id, STICK_NAMES[name_text], stick_value)

static func _name_for(table: Dictionary, wanted: int) -> String:
	for key in table:
		if table[key] == wanted:
			return key
	return ""
