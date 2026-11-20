extends Node
## Solver test scene. Run it; results print to Output. Exit code is 1 on any failure.

const IDLE: int = 0 # neutral InputFrame

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	_test_drop_onto_floor()
	_test_walk_off_ledge()
	_test_jump_through_and_drop_through()
	_test_tunnel_floor()
	_test_tunnel_wall()
	_test_determinism_and_snapshot()
	print("---- %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ---------- helpers ----------

func _px(v: int) -> int:
	return FixedMath.from_px(v)

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)

func _make_stage() -> StageGeometry:
	var g: StageGeometry = StageGeometry.new()
	g.add_segment(_px(-400), 0, _px(400), 0) # floor 0: main floor
	g.add_segment(_px(-100), _px(120), _px(100), _px(120), StageGeometry.FLAG_DROP_THROUGH) # floor 1: platform
	g.add_segment(_px(300), 0, _px(300), _px(300)) # wall facing -X at x=300
	g.blast_left = _px(-1000)
	g.blast_right = _px(1000)
	g.blast_top = _px(800)
	g.blast_bottom = _px(-600)
	return g

func _spawn(x_px: int, y_px: int) -> FighterState:
	var s: FighterState = FighterState.new()
	s.x = _px(x_px)
	s.y = _px(y_px)
	return s

func _run(s: FighterState, g: StageGeometry, inp: int, ticks: int) -> void:
	for t in ticks:
		SimSolver.step(s, g, inp)
		var err: String = SimSolver.check_invariants(s, g)
		if err != "":
			_check(false, "invariant at tick %d: %s" % [s.tick, err])
			return

# ---------- scenarios ----------

func _test_drop_onto_floor() -> void:
	var g: StageGeometry = _make_stage()
	var s: FighterState = _spawn(200, 300)
	_run(s, g, IDLE, 120)
	_check(s.ground_id == 0, "drop: grounded on floor 0")
	_check(s.y == 0, "drop: y == floor y")
	_check(s.x == _px(200), "drop: x unchanged")
	_check(s.vel_x == 0 and s.vel_y == 0, "drop: at rest")

func _test_walk_off_ledge() -> void:
	var g: StageGeometry = _make_stage()
	var s: FighterState = _spawn(-380, 0)
	var left_ground_tick: int = -1
	var regrounded: bool = false
	var walk_left: int = InputFrame.pack(-127, 0, 0, 0, 0)
	for t in 200:
		SimSolver.step(s, g, walk_left)
		if s.ground_id == -1 and left_ground_tick == -1:
			left_ground_tick = s.tick
		elif s.ground_id != -1 and left_ground_tick != -1:
			regrounded = true
	_check(left_ground_tick != -1, "ledge: left the ground")
	_check(not regrounded, "ledge: never regrounded after leaving")
	_check(s.dead == 1, "ledge: fell out through bottom blast zone")

func _test_jump_through_and_drop_through() -> void:
	var g: StageGeometry = _make_stage()
	var s: FighterState = _spawn(0, 0)
	_run(s, g, IDLE, 5) # settle onto floor
	_check(s.ground_id == 0, "jump: settled on floor")
	_run(s, g, InputFrame.pack(0, 0, 0, 0, InputFrame.JUMP), 1) # press
	var max_y: int = s.y
	for t in 120:
		SimSolver.step(s, g, IDLE)
		max_y = maxi(max_y, s.y)
	_check(max_y > _px(120), "jump: rose above platform (passed up through it)")
	_check(s.ground_id == 1, "jump: landed on platform")
	_check(s.y == _px(120), "jump: y == platform y")
	# Hold down: should drop through the platform onto the main floor.
	_run(s, g, InputFrame.pack(0, -127, 0, 0, 0), 60)
	_check(s.ground_id == 0, "drop-through: ended on main floor")
	_check(s.y == 0, "drop-through: y == 0")

func _test_tunnel_floor() -> void:
	var g: StageGeometry = _make_stage()
	var s: FighterState = _spawn(200, 1000)
	s.vel_y = -_px(250) # 250 px per tick, far beyond MAX_FALL
	_run(s, g, IDLE, 10)
	_check(s.ground_id == 0 and s.y == 0, "tunnel floor: caught by floor")
	_check(s.dead == 0, "tunnel floor: not dead")

func _test_tunnel_wall() -> void:
	var g: StageGeometry = _make_stage()
	var s: FighterState = _spawn(100, 0)
	_run(s, g, IDLE, 1) # settle
	s.vel_x = _px(250)
	_run(s, g, IDLE, 3)
	_check(s.x == _px(300) - SimConsts.BOX_HALF_W, "tunnel wall: stopped flush against wall")
	_check(s.vel_x == 0, "tunnel wall: vel_x zeroed")

# ---------- determinism / rollback ----------

func _make_script(ticks: int, seed_value: int) -> PackedInt64Array:
	var inputs: PackedInt64Array = PackedInt64Array()
	var rng: int = seed_value
	var sx: int = 0
	var sy: int = 0
	var btns: int = 0
	for t in ticks:
		rng = rng * 6364136223846793005 + 1442695040888963407
		var r: int = (rng >> 33) & 0x7FFFFFFF
		if r % 8 == 0:
			sx = (r >> 4) % 255 - 127
			sy = (r >> 12) % 255 - 127
		btns = InputFrame.JUMP if (r >> 20) % 10 == 0 else 0
		inputs.append(InputFrame.pack(sx, sy, 0, 0, btns))
	return inputs

func _run_trace(g: StageGeometry, inputs: PackedInt64Array, s: FighterState, from_tick: int) -> PackedInt64Array:
	var trace: PackedInt64Array = PackedInt64Array()
	for t in range(from_tick, inputs.size()):
		SimSolver.step(s, g, inputs[t])
		trace.append(s.state_hash())
		var err: String = SimSolver.check_invariants(s, g)
		if err != "":
			_check(false, "fuzz invariant at tick %d: %s" % [s.tick, err])
			break
	return trace

func _test_determinism_and_snapshot() -> void:
	var g: StageGeometry = _make_stage()
	var inputs: PackedInt64Array = _make_script(2000, 12345)

	var a: FighterState = _spawn(0, 300)
	var trace_a: PackedInt64Array = _run_trace(g, inputs, a, 0)
	var b: FighterState = _spawn(0, 300)
	var trace_b: PackedInt64Array = _run_trace(g, inputs, b, 0)
	_check(trace_a == trace_b, "determinism: two runs produce identical hash traces")

	# Snapshot at tick 700, run on, restore, rerun: traces must match.
	var c: FighterState = _spawn(0, 300)
	var _pre: PackedInt64Array = _run_trace(g, inputs.slice(0, 700), c, 0)
	var snap: PackedInt64Array = c.to_array()
	var trace_c1: PackedInt64Array = _run_trace(g, inputs, c, 700)
	var d: FighterState = FighterState.new()
	d.from_array(snap)
	var trace_c2: PackedInt64Array = _run_trace(g, inputs, d, 700)
	_check(trace_c1 == trace_c2, "rollback: restore at tick 700 reproduces the same trace")
	_check(trace_a.slice(700) == trace_c1, "rollback: matches the uninterrupted run")
	print("fuzz: final tick %d, dead=%d, hash=%d" % [a.tick, a.dead, a.state_hash()])
