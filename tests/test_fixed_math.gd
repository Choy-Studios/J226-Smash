extends Node
# Attach to the root Node of res://tests/test_fixed_math.tscn and run with F6.
# Output appears in the editor's Output panel.

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== FixedMath tests starting ===")
	_test_mul()
	_test_div()
	_test_dist_sq()
	_test_trig()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	# Exit code 0 = all passed, 1 = something failed (useful for headless runs).
	get_tree().quit(1 if _failed > 0 else 0)

# Records a result instead of stopping at the first failure.
func _check(test_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s | expected %s, got %s" % [test_name, str(expected), str(actual)])

func _test_mul() -> void:
	_check("mul 1.5 * 2.0", FixedMath.mul(1500, 2000), 3000)
	_check("mul negative", FixedMath.mul(-1500, 2000), -3000)
	_check("mul both negative", FixedMath.mul(-1500, -2000), 3000)
	_check("mul by zero", FixedMath.mul(1500, 0), 0)
	_check("mul by one", FixedMath.mul(1500, 1000), 1500)
	_check("mul 2.25", FixedMath.mul(1500, 1500), 2250)
	_check("mul truncates small positive", FixedMath.mul(1, 1), 0)
	_check("mul truncates small negative toward zero", FixedMath.mul(-1, 1), 0)
	_check("mul truncates 999", FixedMath.mul(999, 1), 0)
	_check("mul large values", FixedMath.mul(5000000, 5000000), 25000000000)

func _test_div() -> void:
	_check("div 3.0 / 2.0", FixedMath.div(3000, 2000), 1500)
	_check("div negative", FixedMath.div(-3000, 2000), -1500)
	_check("div by one", FixedMath.div(1500, 1000), 1500)
	_check("div truncates", FixedMath.div(1000, 3000), 333)
	_check("div truncates negative toward zero", FixedMath.div(-1000, 3000), -333)
	_check("div zero numerator", FixedMath.div(0, 3000), 0)

func _test_dist_sq() -> void:
	_check("dist_sq 3-4-5", FixedMath.dist_sq(Vector2i(0, 0), Vector2i(3, 4)), 25)
	_check("dist_sq same point", FixedMath.dist_sq(Vector2i(7, 7), Vector2i(7, 7)), 0)
	_check("dist_sq negative coords", FixedMath.dist_sq(Vector2i(-3, -4), Vector2i(0, 0)), 25)
	var a: Vector2i = Vector2i(120, -45)
	var b: Vector2i = Vector2i(-30, 800)
	_check("dist_sq symmetric", FixedMath.dist_sq(a, b), FixedMath.dist_sq(b, a))
	# Blast-zone scale: 10,000,000 units apart. 1e14 must not overflow.
	_check("dist_sq large", FixedMath.dist_sq(Vector2i(-5000000, 0), Vector2i(5000000, 0)), 100000000000000)

func _test_trig() -> void:
	_check("sin table size", FixedMath.SIN_TABLE.size(), 360)
	# Stop here if the table is still the placeholder; the rest would crash.
	if FixedMath.SIN_TABLE.size() != 360:
		return
	_check("sin 0", FixedMath.sin_deg(0), 0)
	_check("sin 30", FixedMath.sin_deg(30), 500)
	_check("sin 90", FixedMath.sin_deg(90), 1000)
	_check("sin 180", FixedMath.sin_deg(180), 0)
	_check("sin 270", FixedMath.sin_deg(270), -1000)
	_check("cos 0", FixedMath.cos_deg(0), 1000)
	_check("cos 90", FixedMath.cos_deg(90), 0)
	_check("cos 180", FixedMath.cos_deg(180), -1000)
	_check("sin wraps at 360", FixedMath.sin_deg(360), FixedMath.sin_deg(0))
	_check("sin wraps at 450", FixedMath.sin_deg(450), FixedMath.sin_deg(90))
	_check("sin negative angle", FixedMath.sin_deg(-90), -1000)
	_check("sin negative wraps", FixedMath.sin_deg(-270), FixedMath.sin_deg(90))
	var in_range: bool = true
	for d in 360:
		if absi(FixedMath.sin_deg(d)) > FixedMath.SCALE:
			in_range = false
	_check("all sin values within +-SCALE", in_range, true)
