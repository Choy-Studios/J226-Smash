extends Node
# Attach to the root Node of res://tests/test_input_frame.tscn and run with F6.
# Results appear in the editor's Output panel.

var _passed: int = 0
var _failed: int = 0

const ALL_BUTTON_LIST: Array[int] = [
	InputFrame.NORMAL, InputFrame.SPECIAL, InputFrame.JUMP, InputFrame.SHORT_HOP,
	InputFrame.SUPER, InputFrame.GRAB, InputFrame.SHIELD,
	InputFrame.TAUNT_UP, InputFrame.TAUNT_DOWN, InputFrame.TAUNT_LEFT,
	InputFrame.TAUNT_RIGHT, InputFrame.SMASH,
]

func _ready() -> void:
	print("=== InputFrame tests starting ===")
	_test_neutral()
	_test_stick_round_trip()
	_test_stick_isolation()
	_test_clamping()
	_test_buttons()
	_test_reserved_bits()
	_test_just_pressed()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(test_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s | expected %s, got %s" % [test_name, str(expected), str(actual)])

func _test_neutral() -> void:
	_check("neutral packs to 0", InputFrame.pack(0, 0, 0, 0, 0), 0)
	_check("zero frame left_x", InputFrame.left_x(0), 0)
	_check("zero frame left_y", InputFrame.left_y(0), 0)
	_check("zero frame right_x", InputFrame.right_x(0), 0)
	_check("zero frame right_y", InputFrame.right_y(0), 0)
	_check("zero frame buttons", InputFrame.buttons(0), 0)

func _test_stick_round_trip() -> void:
	for v in range(-127, 128):
		var f: int = InputFrame.pack(v, -v, v, -v, 0)
		_check("lx %d" % v, InputFrame.left_x(f), v)
		_check("ly %d" % v, InputFrame.left_y(f), -v)
		_check("rx %d" % v, InputFrame.right_x(f), v)
		_check("ry %d" % v, InputFrame.right_y(f), -v)

func _test_stick_isolation() -> void:
	# Extremes in every field, with all buttons held: nothing may bleed.
	var f: int = InputFrame.pack(-127, 127, -127, 127, InputFrame.ALL_BUTTONS)
	_check("isolation lx", InputFrame.left_x(f), -127)
	_check("isolation ly", InputFrame.left_y(f), 127)
	_check("isolation rx", InputFrame.right_x(f), -127)
	_check("isolation ry", InputFrame.right_y(f), 127)
	_check("isolation buttons", InputFrame.buttons(f), InputFrame.ALL_BUTTONS)
	var g: int = InputFrame.pack(127, -127, 127, -127, 0)
	_check("isolation 2 lx", InputFrame.left_x(g), 127)
	_check("isolation 2 ly", InputFrame.left_y(g), -127)
	_check("isolation 2 buttons empty", InputFrame.buttons(g), 0)

func _test_clamping() -> void:
	var f: int = InputFrame.pack(200, -200, 999, -999, 0)
	_check("clamp lx", InputFrame.left_x(f), 127)
	_check("clamp ly", InputFrame.left_y(f), -127)
	_check("clamp rx", InputFrame.right_x(f), 127)
	_check("clamp ry", InputFrame.right_y(f), -127)

func _test_buttons() -> void:
	for b in ALL_BUTTON_LIST:
		var f: int = InputFrame.pack(0, 0, 0, 0, b)
		_check("button %d is down" % b, InputFrame.is_down(f, b), true)
		_check("button %d is the only bit" % b, InputFrame.buttons(f), b)
		for other in ALL_BUTTON_LIST:
			if other != b:
				_check("button %d does not set %d" % [b, other], InputFrame.is_down(f, other), false)
	var all: int = InputFrame.pack(0, 0, 0, 0, InputFrame.ALL_BUTTONS)
	for b in ALL_BUTTON_LIST:
		_check("all buttons includes %d" % b, InputFrame.is_down(all, b), true)

func _test_reserved_bits() -> void:
	# Even with every possible input value, bits 48-63 must stay 0.
	var f: int = InputFrame.pack(-127, -127, -127, -127, 0xFFFF)
	_check("reserved bits zero", f >> 48, 0)
	# Button bits beyond the 16-bit mask must be discarded, not leak.
	var g: int = InputFrame.pack(0, 0, 0, 0, 1 << 20)
	_check("out-of-range button discarded", InputFrame.buttons(g), 0)
	_check("out-of-range button leaves frame 0", g, 0)

func _test_just_pressed() -> void:
	var up: int = InputFrame.pack(0, 0, 0, 0, 0)
	var down: int = InputFrame.pack(0, 0, 0, 0, InputFrame.JUMP)
	_check("just pressed on new press", InputFrame.just_pressed(down, up, InputFrame.JUMP), true)
	_check("not just pressed when held", InputFrame.just_pressed(down, down, InputFrame.JUMP), false)
	_check("not just pressed on release", InputFrame.just_pressed(up, down, InputFrame.JUMP), false)
	_check("not just pressed when idle", InputFrame.just_pressed(up, up, InputFrame.JUMP), false)
	_check("other button unaffected", InputFrame.just_pressed(down, up, InputFrame.SPECIAL), false)
