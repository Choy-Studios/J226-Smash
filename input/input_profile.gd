class_name InputProfile
extends RefCounted
# A named, saveable set of player input settings (like a name tag in Smash).
# Saved as JSON under user://profiles/. JSON is used instead of .tres because
# .tres files can reference scripts, which is unsafe for files shared between friends.
#
# A profile travels with the player. It is never sent over the network:
# the network only ever sees the already-resolved InputFrame.

const CURRENT_VERSION: int = 1
const PROFILE_DIR: String = "user://profiles"

const C_STICK_OFF: int = 0
const C_STICK_SMASH: int = 1
const C_STICK_NORMAL: int = 2
const C_STICK_NAMES: Dictionary = {
	"off": C_STICK_OFF,
	"smash": C_STICK_SMASH,
	"normal": C_STICK_NORMAL,
}

var profile_name: String = "Player"
var version: int = CURRENT_VERSION
var tap_jump: bool = false                 # behavior flag (logic not implemented yet)
var c_stick_mode: int = C_STICK_SMASH      # behavior flag (emission logic not implemented yet)
var left_deadzone: float = 0.15
var right_deadzone: float = 0.15
var walk_value: int = 45                   # stick magnitude while the walk modifier is held
var bindings: Array[InputBinding] = []

# --- Compile (profile -> runtime lookup table) ---
# Call validate() first. This assumes no duplicate sources.
func compile() -> CompiledBindings:
	var compiled: CompiledBindings = CompiledBindings.new()
	for b in bindings:
		compiled.add(b)
	return compiled

# --- Validation ---
# Appends human-readable problems to errors. Empty means valid.
func validate(errors: Array) -> void:
	if profile_name.strip_edges() == "":
		errors.append("profile: name is empty")
	if version < 1 or version > CURRENT_VERSION:
		errors.append("profile: unsupported version %d" % version)
	if not C_STICK_NAMES.values().has(c_stick_mode):
		errors.append("profile: invalid C-stick mode")
	if left_deadzone < 0.0 or left_deadzone > 0.9:
		errors.append("profile: left deadzone must be between 0 and 0.9")
	if right_deadzone < 0.0 or right_deadzone > 0.9:
		errors.append("profile: right deadzone must be between 0 and 0.9")
	if walk_value < 1 or walk_value >= InputFrame.STICK_MAX:
		errors.append("profile: walk value must be between 1 and %d" % (InputFrame.STICK_MAX - 1))
	var seen: Dictionary = {}
	for i in bindings.size():
		var b: InputBinding = bindings[i]
		if b.source == SourceId.INVALID:
			errors.append("binding %d: invalid source" % i)
			continue
		if seen.has(b.source):
			errors.append("binding %d: source '%s' is bound more than once" % [i, SourceId.to_str(b.source)])
		seen[b.source] = true

# --- JSON ---
func to_dict() -> Dictionary:
	var list: Array = []
	for b in bindings:
		list.append(b.to_dict())
	var c_stick_name: String = ""
	for key in C_STICK_NAMES:
		if C_STICK_NAMES[key] == c_stick_mode:
			c_stick_name = key
	return {
		"version": version,
		"name": profile_name,
		"tap_jump": tap_jump,
		"c_stick": c_stick_name,
		"left_deadzone": left_deadzone,
		"right_deadzone": right_deadzone,
		"walk_value": walk_value,
		"bindings": list,
	}

func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")

static func from_json(text: String, errors: Array) -> InputProfile:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		errors.append("profile: not a valid JSON object")
		return null
	return from_dict(parsed, errors)

# Returns null (and fills errors) if the data is invalid.
# When CURRENT_VERSION is raised later, upgrade older versions here before validating.
static func from_dict(d: Dictionary, errors: Array) -> InputProfile:
	var start_count: int = errors.size()
	var p: InputProfile = InputProfile.new()

	var ver: Variant = d.get("version")
	if ver is float or ver is int:
		p.version = int(ver)
	else:
		errors.append("profile: missing version")

	var name_value: Variant = d.get("name")
	if name_value is String:
		p.profile_name = name_value
	else:
		errors.append("profile: missing name")

	var tap_value: Variant = d.get("tap_jump", false)
	if tap_value is bool:
		p.tap_jump = tap_value
	else:
		errors.append("profile: tap_jump must be true or false")

	var c_value: Variant = d.get("c_stick", "smash")
	if c_value is String and C_STICK_NAMES.has(c_value):
		p.c_stick_mode = C_STICK_NAMES[c_value]
	else:
		errors.append("profile: c_stick must be off, smash, or normal")

	var ldz: Variant = d.get("left_deadzone", p.left_deadzone)
	var rdz: Variant = d.get("right_deadzone", p.right_deadzone)
	if (ldz is float or ldz is int) and (rdz is float or rdz is int):
		p.left_deadzone = float(ldz)
		p.right_deadzone = float(rdz)
	else:
		errors.append("profile: deadzones must be numbers")

	var walk: Variant = d.get("walk_value", p.walk_value)
	if walk is float or walk is int:
		p.walk_value = int(walk)
	else:
		errors.append("profile: walk_value must be a number")

	var list: Variant = d.get("bindings")
	if list is Array:
		for i in list.size():
			var b: InputBinding = InputBinding.from_dict(list[i], errors, i)
			if b != null:
				p.bindings.append(b)
	else:
		errors.append("profile: bindings must be a list")

	if errors.size() > start_count:
		return null
	p.validate(errors)
	if errors.size() > start_count:
		return null
	return p

# --- Files ---
func save_to_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	return OK

static func load_from_file(path: String, errors: Array) -> InputProfile:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return null
	return from_json(f.get_as_text(), errors)

# --- Defaults ---
static func _key(code: int) -> int:
	return SourceId.make(SourceId.KIND_KEY, code)

static func default_keyboard() -> InputProfile:
	var p: InputProfile = InputProfile.new()
	p.profile_name = "Keyboard"
	var m: int = InputFrame.STICK_MAX
	# WASD: left stick, full deflection only (stick up = +Y).
	p.bindings.append(InputBinding.make_stick(_key(KEY_W), InputBinding.STICK_LEFT_Y, m))
	p.bindings.append(InputBinding.make_stick(_key(KEY_S), InputBinding.STICK_LEFT_Y, -m))
	p.bindings.append(InputBinding.make_stick(_key(KEY_A), InputBinding.STICK_LEFT_X, -m))
	p.bindings.append(InputBinding.make_stick(_key(KEY_D), InputBinding.STICK_LEFT_X, m))
	# Modifiers.
	p.bindings.append(InputBinding.make_modifier(
		SourceId.make(SourceId.KIND_KEY_LEFT, KEY_SHIFT), InputBinding.MOD_WALK))
	p.bindings.append(InputBinding.make_modifier(_key(KEY_O), InputBinding.MOD_TAUNT))
	# Buttons.
	p.bindings.append(InputBinding.make_button(_key(KEY_SPACE), InputFrame.JUMP))
	p.bindings.append(InputBinding.make_button(
		SourceId.make(SourceId.KIND_KEY_RIGHT, KEY_ALT), InputFrame.SUPER))
	p.bindings.append(InputBinding.make_button(_key(KEY_L), InputFrame.NORMAL))
	p.bindings.append(InputBinding.make_button(_key(KEY_P), InputFrame.SPECIAL))
	p.bindings.append(InputBinding.make_button(_key(KEY_K), InputFrame.SMASH))
	p.bindings.append(InputBinding.make_button(_key(KEY_BRACKETLEFT), InputFrame.GRAB))
	p.bindings.append(InputBinding.make_button(_key(KEY_BRACKETRIGHT), InputFrame.SHIELD))
	return p

static func default_controller() -> InputProfile:
	var p: InputProfile = InputProfile.new()
	p.profile_name = "Controller"
	var btn: int = SourceId.KIND_JOY_BUTTON
	var axis_pos: int = SourceId.KIND_JOY_AXIS_POS
	# Face buttons (positional: A = bottom, B = right, X = left, Y = top).
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_A), InputFrame.SPECIAL))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_B), InputFrame.NORMAL))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_X), InputFrame.JUMP))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_Y), InputFrame.JUMP))
	# Shoulders and triggers.
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_LEFT_SHOULDER), InputFrame.SUPER))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_RIGHT_SHOULDER), InputFrame.GRAB))
	p.bindings.append(InputBinding.make_button(SourceId.make(axis_pos, JOY_AXIS_TRIGGER_LEFT), InputFrame.SHIELD))
	p.bindings.append(InputBinding.make_button(SourceId.make(axis_pos, JOY_AXIS_TRIGGER_RIGHT), InputFrame.SHIELD))
	# D-pad: taunts.
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_DPAD_UP), InputFrame.TAUNT_UP))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_DPAD_DOWN), InputFrame.TAUNT_DOWN))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_DPAD_LEFT), InputFrame.TAUNT_LEFT))
	p.bindings.append(InputBinding.make_button(SourceId.make(btn, JOY_BUTTON_DPAD_RIGHT), InputFrame.TAUNT_RIGHT))
	return p
