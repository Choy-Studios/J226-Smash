extends Node
# Attach to the root Node of res://tests/test_input_mapper.tscn and run with F6.
# Results appear in the editor's Output panel.
# Feeds scripted raw input to the mapper; no real keyboard or controller needed.

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== Input layer tests starting ===")
	_test_source_ids()
	_test_profile_json()
	_test_profile_validation()
	_test_mapper_keyboard()
	_test_mapper_analog()
	_test_mapper_controller()
	_test_mapper_history()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(test_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s | expected %s, got %s" % [test_name, str(expected), str(actual)])

# Runs one frame through a fresh mapper using the default keyboard profile.
func _kb(held: Array, left: Vector2 = Vector2.ZERO, right: Vector2 = Vector2.ZERO) -> int:
	var mapper: InputMapper = InputMapper.new(InputProfile.default_keyboard())
	return mapper.step(RawInput.make(left, right, held))

func _test_source_ids() -> void:
	var ids: Array[int] = [
		SourceId.make(SourceId.KIND_KEY, KEY_K),
		SourceId.make(SourceId.KIND_KEY, KEY_SPACE),
		SourceId.make(SourceId.KIND_KEY, KEY_BRACKETLEFT),
		SourceId.make(SourceId.KIND_KEY, KEY_LEFT),
		SourceId.make(SourceId.KIND_KEY_LEFT, KEY_SHIFT),
		SourceId.make(SourceId.KIND_KEY_RIGHT, KEY_ALT),
		SourceId.make(SourceId.KIND_JOY_BUTTON, JOY_BUTTON_A),
		SourceId.make(SourceId.KIND_JOY_BUTTON, JOY_BUTTON_DPAD_UP),
		SourceId.make(SourceId.KIND_JOY_AXIS_POS, JOY_AXIS_TRIGGER_LEFT),
	]
	for id in ids:
		var text: String = SourceId.to_str(id)
		_check("to_str is not empty for %d" % id, text != "", true)
		_check("round trip %s" % text, SourceId.from_str(text), id)
	_check("kind_of", SourceId.kind_of(ids[4]), SourceId.KIND_KEY_LEFT)
	_check("code_of keeps special key codes", SourceId.code_of(ids[3]), KEY_LEFT)
	_check("generic_of left shift", SourceId.generic_of(ids[4]), SourceId.make(SourceId.KIND_KEY, KEY_SHIFT))
	_check("from_str key:K", SourceId.from_str("key:K"), ids[0])
	_check("unknown key rejected", SourceId.from_str("key:NotAKey"), SourceId.INVALID)
	_check("unknown prefix rejected", SourceId.from_str("bogus:K"), SourceId.INVALID)
	_check("left/right on a non-sided key rejected", SourceId.from_str("key_l:K"), SourceId.INVALID)
	_check("unknown joypad button rejected", SourceId.from_str("joy_btn:Nope"), SourceId.INVALID)
	_check("empty string rejected", SourceId.from_str(""), SourceId.INVALID)
	_check("modifier string rejected", SourceId.from_str("key:Shift+K"), SourceId.INVALID)

func _test_profile_json() -> void:
	var original: InputProfile = InputProfile.default_keyboard()
	var text: String = original.to_json()
	var errors: Array = []
	var again: InputProfile = InputProfile.from_json(text, errors)
	_check("keyboard profile loads with no errors", errors.size(), 0)
	_check("keyboard profile loads", again != null, true)
	if again == null:
		return
	_check("binding count survives", again.bindings.size(), original.bindings.size())
	_check("json is stable", again.to_json(), text)
	_check("compiled size matches", again.compile().size(), original.bindings.size())

	var ctrl_errors: Array = []
	var ctrl: InputProfile = InputProfile.from_json(InputProfile.default_controller().to_json(), ctrl_errors)
	_check("controller profile loads", ctrl != null and ctrl_errors.size() == 0, true)

func _test_profile_validation() -> void:
	# Duplicate source
	var dup: InputProfile = InputProfile.default_keyboard()
	dup.bindings.append(InputBinding.make_button(
		SourceId.make(SourceId.KIND_KEY, KEY_K), InputFrame.NORMAL))
	var dup_errors: Array = []
	dup.validate(dup_errors)
	_check("duplicate source rejected", dup_errors.size() > 0, true)

	# Broken JSON
	var json_errors: Array = []
	_check("broken json returns null", InputProfile.from_json("{ not json", json_errors) == null, true)
	_check("broken json reports an error", json_errors.size() > 0, true)

	# Newer version than supported
	var d: Dictionary = InputProfile.default_keyboard().to_dict()
	d["version"] = 999
	var ver_errors: Array = []
	_check("newer version rejected", InputProfile.from_json(JSON.stringify(d), ver_errors) == null, true)

	# Unknown source string
	var d2: Dictionary = InputProfile.default_keyboard().to_dict()
	d2["bindings"][0]["source"] = "key:NotAKey"
	var src_errors: Array = []
	_check("unknown source rejected", InputProfile.from_json(JSON.stringify(d2), src_errors) == null, true)
	_check("unknown source reports an error", src_errors.size() > 0, true)

	# Stick binding with value 0
	var d3: Dictionary = InputProfile.default_keyboard().to_dict()
	d3["bindings"][0]["value"] = 0
	var val_errors: Array = []
	_check("zero stick value rejected", InputProfile.from_json(JSON.stringify(d3), val_errors) == null, true)

func _test_mapper_keyboard() -> void:
	# Nothing held
	_check("idle frame is 0", _kb([]), 0)

	# Directions (stick up = +Y)
	var up: int = _kb(["key:W"])
	_check("W is up", InputFrame.left_y(up), 127)
	_check("W leaves x neutral", InputFrame.left_x(up), 0)
	_check("S is down", InputFrame.left_y(_kb(["key:S"])), -127)
	_check("A is left", InputFrame.left_x(_kb(["key:A"])), -127)
	_check("D is right", InputFrame.left_x(_kb(["key:D"])), 127)

	# Opposing directions resolve to neutral
	_check("A+D is neutral", InputFrame.left_x(_kb(["key:A", "key:D"])), 0)
	_check("W+S is neutral", InputFrame.left_y(_kb(["key:W", "key:S"])), 0)
	var diag: int = _kb(["key:A", "key:W"])
	_check("A+W diagonal x", InputFrame.left_x(diag), -127)
	_check("A+W diagonal y", InputFrame.left_y(diag), 127)
	var partial: int = _kb(["key:A", "key:D", "key:W"])
	_check("A+D+W keeps W", InputFrame.left_y(partial), 127)
	_check("A+D+W cancels x", InputFrame.left_x(partial), 0)

	# Walk modifier (45 is the profile default)
	_check("Shift+D clamps to walk value", InputFrame.left_x(_kb(["key_l:Shift", "key:D"])), 45)
	_check("Shift+A clamps negative", InputFrame.left_x(_kb(["key_l:Shift", "key:A"])), -45)
	_check("Shift alone is neutral", _kb(["key_l:Shift"]), 0)

	# Buttons
	_check("L is Normal", _kb(["key:L"]), InputFrame.pack(0, 0, 0, 0, InputFrame.NORMAL))
	_check("P is Special", _kb(["key:P"]), InputFrame.pack(0, 0, 0, 0, InputFrame.SPECIAL))
	_check("K is Smash", _kb(["key:K"]), InputFrame.pack(0, 0, 0, 0, InputFrame.SMASH))
	_check("Space is Jump", _kb(["key:Space"]), InputFrame.pack(0, 0, 0, 0, InputFrame.JUMP))
	_check("Right Alt is Super", _kb(["key_r:Alt"]), InputFrame.pack(0, 0, 0, 0, InputFrame.SUPER))
	_check("[ is Grab", _kb(["key:BracketLeft"]), InputFrame.pack(0, 0, 0, 0, InputFrame.GRAB))
	_check("] is Shield", _kb(["key:BracketRight"]), InputFrame.pack(0, 0, 0, 0, InputFrame.SHIELD))
	_check("Left Alt does not trigger Super", _kb(["key_l:Alt"]), 0)
	_check("unbound key does nothing", _kb(["key:Z"]), 0)

	# Buttons and direction together
	var combo: int = _kb(["key:K", "key:D"])
	_check("K+D smash bit", InputFrame.is_down(combo, InputFrame.SMASH), true)
	_check("K+D direction", InputFrame.left_x(combo), 127)

	# Taunt modifier: stick becomes taunt bits, no movement
	var taunt_up: int = _kb(["key:O", "key:W"])
	_check("O+W taunt up bit", InputFrame.is_down(taunt_up, InputFrame.TAUNT_UP), true)
	_check("O+W sends no movement y", InputFrame.left_y(taunt_up), 0)
	var taunt_left: int = _kb(["key:O", "key:A"])
	_check("O+A taunt left bit", InputFrame.is_down(taunt_left, InputFrame.TAUNT_LEFT), true)
	_check("O+A sends no movement x", InputFrame.left_x(taunt_left), 0)
	_check("O alone sets no taunt", _kb(["key:O"]), 0)

func _test_mapper_analog() -> void:
	# Default deadzone is 0.15. 0.5 rescales to (0.5-0.15)/0.85*127 = 52.29 -> 52.
	_check("analog full right", InputFrame.left_x(_kb([], Vector2(1.0, 0.0))), 127)
	_check("analog full left", InputFrame.left_x(_kb([], Vector2(-1.0, 0.0))), -127)
	_check("analog half rescaled", InputFrame.left_x(_kb([], Vector2(0.5, 0.0))), 52)
	_check("analog inside deadzone", _kb([], Vector2(0.1, 0.1)), 0)
	_check("analog up is +Y", InputFrame.left_y(_kb([], Vector2(0.0, 1.0))), 127)
	_check("analog over-range clamps", InputFrame.left_x(_kb([], Vector2(1.5, 0.0))), 127)

	# Digital wins over analog on the same axis
	_check("digital beats analog", InputFrame.left_x(_kb(["key:D"], Vector2(-1.0, 0.0))), 127)

	# Right stick passes through as attack direction
	_check("right stick up", InputFrame.right_y(_kb([], Vector2.ZERO, Vector2(0.0, 1.0))), 127)

	# C-stick off removes the analog right stick
	var off_profile: InputProfile = InputProfile.default_keyboard()
	off_profile.c_stick_mode = InputProfile.C_STICK_OFF
	var off_mapper: InputMapper = InputMapper.new(off_profile)
	var off_frame: int = off_mapper.step(RawInput.make(Vector2.ZERO, Vector2(0.0, 1.0), []))
	_check("C-stick off zeroes right stick", InputFrame.right_y(off_frame), 0)

	# quantize_stick directly
	_check("quantize zero", InputMapper.quantize_stick(Vector2.ZERO, 0.15), Vector2i.ZERO)
	_check("quantize diagonal stays symmetric",
		InputMapper.quantize_stick(Vector2(0.6, 0.6), 0.15).x,
		InputMapper.quantize_stick(Vector2(0.6, 0.6), 0.15).y)

func _test_mapper_controller() -> void:
	var mapper: InputMapper = InputMapper.new(InputProfile.default_controller())
	_check("B is Normal", mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:B"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.NORMAL))
	_check("A is Special", mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:A"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.SPECIAL))
	_check("X is Jump", mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:X"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.JUMP))
	_check("Y is Jump", mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:Y"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.JUMP))
	_check("left trigger is Shield",
		mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_axis+:TriggerLeft"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.SHIELD))
	_check("right trigger is Shield",
		mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_axis+:TriggerRight"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.SHIELD))
	_check("left shoulder is Super",
		mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:LeftShoulder"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.SUPER))
	_check("right shoulder is Grab",
		mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:RightShoulder"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.GRAB))
	_check("dpad up is a taunt",
		mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:DpadUp"])),
		InputFrame.pack(0, 0, 0, 0, InputFrame.TAUNT_UP))
	_check("Start is not bound", mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["joy_btn:Start"])), 0)

func _test_mapper_history() -> void:
	var mapper: InputMapper = InputMapper.new(InputProfile.default_keyboard())
	mapper.step(RawInput.make(Vector2.ZERO, Vector2.ZERO, ["key:W"]))
	_check("history remembers previous left", mapper.history.prev_left, Vector2i(0, 127))
	mapper.reset()
	_check("reset clears history", mapper.history.prev_left, Vector2i.ZERO)
