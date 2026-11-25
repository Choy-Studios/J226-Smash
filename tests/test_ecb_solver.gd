extends Node
## ECB solver v2 test scene. Run it; results print to Output. Exit code is 1 on any failure.
## v1 box-solver tests (tests/test_solver.tscn) are untouched and still serve as regression.

const IDLE: int = 0
const DATA_PATH: String = "res://tests/data/test_ecb.json"
## Golden fuzz hash for this file's fuzz stage + script (seed 12345, 8000 ticks). 0 = not recorded yet.
const GOLDEN_FUZZ_HASH: int = -6988171275757478515

var _pass: int = 0
var _fail: int = 0
var _data: EcbData
var _deaths: int = 0
var _tally: bool = false
var _cov: Dictionary = {"ceil": 0, "wall_l": 0, "wall_r": 0, "step_up": 0, "airborne": 0}

func _ready() -> void:
	_data = EcbData.load_json(DATA_PATH)
	if _data == null:
		print("FAIL: could not load ", DATA_PATH)
		get_tree().quit(1)
		return
	_test_data_bridge()
	_test_drop_onto_floor()
	_test_walk_off_ledge()
	_test_seam_transfer()
	_test_step_up()
	_test_tall_step_blocks()
	_test_corner_landing_slide()
	_test_corner_jump_slide()
	_test_ceiling_keeps_momentum()
	_test_wall_keeps_momentum()
	_test_tunnel_floor()
	_test_tunnel_wall()
	_test_tunnel_ceiling()
	_test_split_exact()
	_test_ecb_change()
	_test_crush_is_bounded_and_deterministic()
	_test_fuzz_determinism_and_snapshot()
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

func _base_stage() -> StageGeometry:
	var g: StageGeometry = StageGeometry.new()
	g.add_segment(_px(-600), 0, _px(600), 0) # floor 0
	g.blast_left = _px(-1000)
	g.blast_right = _px(1000)
	g.blast_top = _px(800)
	g.blast_bottom = _px(-600)
	return g

## Solid box. Top floor, side walls, and (optionally) an underside ceiling.
func _add_block(g: StageGeometry, x1: int, y1: int, x2: int, y2: int, with_bottom: bool) -> void:
	g.add_segment(_px(x1), _px(y2), _px(x2), _px(y2)) # top (floor)
	g.add_segment(_px(x1), _px(y1), _px(x1), _px(y2)) # left face, bottom-to-top: faces -X
	g.add_segment(_px(x2), _px(y2), _px(x2), _px(y1)) # right face, top-to-bottom: faces +X
	if with_bottom:
		g.add_segment(_px(x2), _px(y1), _px(x1), _px(y1)) # underside (ceiling)

func _spawn(x_px: int, y_px: int) -> EcbFighterState:
	var s: EcbFighterState = EcbFighterState.new()
	s.apply_ecb(_data)
	s.x = _px(x_px)
	s.y = _px(y_px)
	return s

func _verify(s: EcbFighterState, g: StageGeometry, caps_before: int, label: String) -> bool:
	var err: String = EcbSolver.check_invariants(s, g)
	if err != "":
		_check(false, "%s invariant at tick %d: %s" % [label, s.tick, err])
		return false
	if EcbSolver.debug_cap_hits == caps_before and EcbSolver.count_endpoint_penetrations(s, g) > 0:
		_check(false, "%s endpoint left inside rhombus at tick %d" % [label, s.tick])
		return false
	return true

func _run(s: EcbFighterState, g: StageGeometry, inp: int, ticks: int) -> bool:
	for t in ticks:
		var caps_before: int = EcbSolver.debug_cap_hits
		EcbSolver.step(s, g, inp)
		if not _verify(s, g, caps_before, "run"):
			return false
	return true

# ---------- scenarios ----------

func _test_data_bridge() -> void:
	var good: Dictionary = {"half_w": 20000, "bottom_y": 0, "mid_y": 30000, "top_y": 60000, "off_x": 0, "off_y": 0}
	_check(EcbData.from_dict(good) != null, "bridge: valid ints accepted")
	var whole: Dictionary = good.duplicate()
	whole["half_w"] = 20000.0
	var d2: EcbData = EcbData.from_dict(whole)
	_check(d2 != null and d2.half_w == 20000 and typeof(d2.half_w) == TYPE_INT, "bridge: whole float becomes int")
	var frac: Dictionary = good.duplicate()
	frac["mid_y"] = 30000.5
	_check(EcbData.from_dict(frac) == null, "bridge: fractional float rejected")
	var missing: Dictionary = good.duplicate()
	missing.erase("off_y")
	_check(EcbData.from_dict(missing) == null, "bridge: missing key rejected")
	var extra: Dictionary = good.duplicate()
	extra["half_height"] = 5
	_check(EcbData.from_dict(extra) == null, "bridge: unknown key rejected")
	var bad_shape: Dictionary = good.duplicate()
	bad_shape["mid_y"] = 0
	_check(EcbData.from_dict(bad_shape) == null, "bridge: invalid shape rejected")
	_check(_data.half_w == 20000 and _data.mid_y == 30000 and _data.top_y == 60000, "bridge: json file loaded")

func _test_drop_onto_floor() -> void:
	var g: StageGeometry = _base_stage()
	var s: EcbFighterState = _spawn(200, 300)
	_run(s, g, IDLE, 120)
	_check(s.ground_id == 0, "drop: grounded on floor 0")
	_check(s.y == 0, "drop: y == floor y")
	_check(s.x == _px(200), "drop: x unchanged")
	_check(s.vel_x == 0 and s.vel_y == 0, "drop: at rest")

func _test_walk_off_ledge() -> void:
	var g: StageGeometry = _base_stage()
	var s: EcbFighterState = _spawn(-590, 0)
	var left_tick: int = -1
	var regrounded: bool = false
	var vel_before: int = 0
	var vel_before_leave: int = 0
	var vel_at_leave: int = 0
	var walk_left: int = InputFrame.pack(-127, 0, 0, 0, 0)
	for t in 200:
		vel_before = s.vel_x
		EcbSolver.step(s, g, walk_left)
		if s.ground_id == -1 and left_tick == -1:
			left_tick = s.tick
			vel_at_leave = s.vel_x
			vel_before_leave = vel_before
		elif s.ground_id != -1 and left_tick != -1:
			regrounded = true
	_check(left_tick != -1, "ledge: left the ground")
	_check(not regrounded, "ledge: never regrounded after leaving")
	_check(vel_at_leave < 0 and absi(vel_at_leave) >= absi(vel_before_leave), "ledge: keeps walking speed into the air")
	_check(s.dead == 1, "ledge: fell out through bottom blast zone")

func _test_seam_transfer() -> void:
	var g: StageGeometry = StageGeometry.new()
	g.add_segment(_px(-400), 0, _px(0), 0) # floor 0
	g.add_segment(_px(0), 0, _px(400), 0) # floor 1, shares the seam at x = 0
	g.blast_left = _px(-1000)
	g.blast_right = _px(1000)
	g.blast_top = _px(800)
	g.blast_bottom = _px(-600)
	var s: EcbFighterState = _spawn(-100, 0)
	_run(s, g, IDLE, 5)
	_check(s.ground_id == 0, "seam: settled on floor 0")
	var walk_right: int = InputFrame.pack(127, 0, 0, 0, 0)
	var airborne_ticks: int = 0
	for t in 60:
		EcbSolver.step(s, g, walk_right)
		if s.ground_id == -1:
			airborne_ticks += 1
	_check(airborne_ticks == 0, "seam: never airborne while crossing a seam")
	_check(s.ground_id == 1 and s.x > _px(0), "seam: ended on floor 1")

func _step_stage(step_h: int) -> StageGeometry:
	var g: StageGeometry = StageGeometry.new()
	g.add_segment(_px(-400), 0, _px(400), 0) # floor 0
	g.add_segment(_px(100), 0, _px(100), _px(step_h)) # step face, faces -X
	g.add_segment(_px(100), _px(step_h), _px(400), _px(step_h)) # floor 1: step top
	g.blast_left = _px(-1000)
	g.blast_right = _px(1000)
	g.blast_top = _px(800)
	g.blast_bottom = _px(-600)
	return g

func _test_step_up() -> void:
	var g: StageGeometry = _step_stage(10) # lower than the side vertices (30 px)
	var s: EcbFighterState = _spawn(0, 0)
	_run(s, g, IDLE, 3)
	var airborne_ticks: int = 0
	var walk_right: int = InputFrame.pack(127, 0, 0, 0, 0)
	for t in 40:
		EcbSolver.step(s, g, walk_right)
		if s.ground_id == -1:
			airborne_ticks += 1
	_check(airborne_ticks == 0, "step-up: stays grounded while stepping up")
	_check(s.ground_id == 1 and s.y == _px(10), "step-up: lifted onto the step floor")
	_check(s.x > _px(100), "step-up: not blocked by the step")
	_check(EcbSolver.check_invariants(s, g) == "", "step-up: invariants hold")

func _test_tall_step_blocks() -> void:
	var g: StageGeometry = _step_stage(40) # taller than the side vertices
	var s: EcbFighterState = _spawn(0, 0)
	_run(s, g, IDLE, 3)
	_run(s, g, InputFrame.pack(127, 0, 0, 0, 0), 60)
	_check(s.x == _px(100) - _data.half_w, "tall step: side vertex stops flush against the face")
	_check(s.ground_id == 0, "tall step: still on floor 0")
	_check(s.vel_x == SimConsts.WALK_SPEED, "tall step: velocity is kept, not zeroed")
	_check((s.contact & EcbFighterState.CONTACT_WALL_R) != 0, "tall step: wall-right contact reported")

func _test_corner_landing_slide() -> void:
	var g: StageGeometry = _base_stage()
	_add_block(g, 0, 0, 200, 100, false)
	var s: EcbFighterState = _spawn(210, 300) # bottom vertex 10 px past the block's right edge
	var prev_x: int = s.x
	var monotonic: bool = true
	var vel_x_always_zero: bool = true
	for t in 250:
		var caps_before: int = EcbSolver.debug_cap_hits
		EcbSolver.step(s, g, IDLE)
		if not _verify(s, g, caps_before, "corner-land"):
			break
		if s.x < prev_x:
			monotonic = false
		prev_x = s.x
		if s.vel_x != 0:
			vel_x_always_zero = false
	var cx: int = s.x + s.off_x
	_check(monotonic, "corner landing: only slides away from the block")
	_check(vel_x_always_zero, "corner landing: velocity untouched (no friction, no bounce)")
	_check(cx >= _px(220) and cx < _px(225), "corner landing: slid out to one half-width off the edge (rhombus)")
	_check(s.ground_id == 0 and s.y == 0, "corner landing: ends on the main floor")

func _test_corner_jump_slide() -> void:
	var g: StageGeometry = _base_stage()
	_add_block(g, 0, 150, 200, 300, true)
	var s: EcbFighterState = _spawn(210, 0)
	s.vel_y = SimConsts.JUMP_VEL
	s.ground_id = -1
	var prev_x: int = s.x
	var monotonic: bool = true
	for t in 120:
		var caps_before: int = EcbSolver.debug_cap_hits
		EcbSolver.step(s, g, IDLE)
		if not _verify(s, g, caps_before, "corner-jump"):
			break
		if s.x < prev_x:
			monotonic = false
		prev_x = s.x
	var cx: int = s.x + s.off_x
	_check(monotonic, "corner jump: only slides away from the block")
	_check(cx >= _px(220) and cx < _px(225), "corner jump: slid sideways off the underside corner (rhombus)")
	_check(s.ground_id == 0, "corner jump: lands back on the main floor")

func _test_ceiling_keeps_momentum() -> void:
	var g: StageGeometry = _base_stage()
	_add_block(g, -100, 150, 200, 300, true)
	var s: EcbFighterState = _spawn(50, 0)
	s.vel_y = SimConsts.JUMP_VEL
	s.ground_id = -1
	var drift: int = InputFrame.pack(127, 0, 0, 0, 0)
	var pinned_ticks: int = 0
	var first_pin_x: int = 0
	var last_pin_x: int = 0
	var kept_velocity: bool = true
	var flush: bool = true
	for t in 120:
		var caps_before: int = EcbSolver.debug_cap_hits
		EcbSolver.step(s, g, drift)
		if not _verify(s, g, caps_before, "ceiling"):
			break
		if (s.contact & EcbFighterState.CONTACT_CEIL) != 0:
			if pinned_ticks == 0:
				first_pin_x = s.x
			last_pin_x = s.x
			pinned_ticks += 1
			if s.vel_y <= 0:
				kept_velocity = false
			if s.y + s.top_y != _px(150):
				flush = false
	_check(pinned_ticks > 5, "ceiling: pinned against the underside for several ticks")
	_check(kept_velocity, "ceiling: upward velocity is kept while pinned")
	_check(flush, "ceiling: top vertex held flush, never through")
	_check(last_pin_x > first_pin_x, "ceiling: horizontal drift continues while pinned")
	_check(s.ground_id == 0, "ceiling: falls back to the floor once momentum is spent")

func _test_wall_keeps_momentum() -> void:
	var g: StageGeometry = _base_stage()
	g.add_segment(_px(300), 0, _px(300), _px(300)) # faces -X
	var s: EcbFighterState = _spawn(100, 0)
	_run(s, g, IDLE, 3)
	_run(s, g, InputFrame.pack(127, 0, 0, 0, 0), 120)
	_check(s.x == _px(300) - _data.half_w, "wall: flush against the wall")
	_check(s.vel_x == SimConsts.WALK_SPEED, "wall: velocity kept")
	_check((s.contact & EcbFighterState.CONTACT_WALL_R) != 0, "wall: contact bit set")
	_check(s.ground_id == 0, "wall: stays grounded")

func _test_tunnel_floor() -> void:
	var g: StageGeometry = _base_stage()
	var s: EcbFighterState = _spawn(200, 1000)
	s.vel_y = -_px(250)
	_run(s, g, IDLE, 10)
	_check(s.ground_id == 0 and s.y == 0, "tunnel floor: caught by floor")
	_check(s.dead == 0, "tunnel floor: not dead")

func _test_tunnel_wall() -> void:
	var g: StageGeometry = _base_stage()
	g.add_segment(_px(300), 0, _px(300), _px(300))
	var s: EcbFighterState = _spawn(100, 0)
	_run(s, g, IDLE, 1)
	s.vel_x = _px(250)
	_run(s, g, IDLE, 3)
	_check(s.x == _px(300) - _data.half_w, "tunnel wall: stopped flush against wall")
	_check((s.contact & EcbFighterState.CONTACT_WALL_R) != 0, "tunnel wall: contact reported")

func _test_tunnel_ceiling() -> void:
	var g: StageGeometry = _base_stage()
	_add_block(g, -100, 150, 200, 300, true)
	var s: EcbFighterState = _spawn(50, 0)
	s.vel_y = _px(250)
	s.ground_id = -1
	EcbSolver.step(s, g, IDLE)
	_check(s.y + s.top_y == _px(150), "tunnel ceiling: stopped under the underside")
	_check(s.vel_y > 0, "tunnel ceiling: velocity kept")
	_check((s.contact & EcbFighterState.CONTACT_CEIL) != 0, "tunnel ceiling: contact reported")

func _test_split_exact() -> void:
	var ok: bool = true
	for total in [250000, -250000, 7777, -7777, 1, -1, 0, 123456789, -123456789]:
		for n in range(1, EcbSolver.MAX_SUBSTEPS + 1):
			var sum: int = 0
			for i in n:
				sum += EcbSolver.split(total, n, i)
			if sum != total:
				ok = false
	_check(ok, "substeps: pieces always sum exactly to the total")

func _test_ecb_change() -> void:
	var g: StageGeometry = _base_stage()
	g.add_segment(_px(300), 0, _px(300), _px(300))
	var s: EcbFighterState = _spawn(0, 0)
	_run(s, g, IDLE, 3)
	s.bottom_y = -5000
	_run(s, g, IDLE, 1)
	_check(s.y + s.off_y + s.bottom_y == 0 and s.ground_id == 0, "ecb change: grounded bottom vertex re-anchored to floor")
	var w: EcbFighterState = _spawn(280, 0)
	_run(w, g, IDLE, 3)
	w.half_w += _px(10)
	_run(w, g, IDLE, 1)
	_check(w.x + w.half_w <= _px(300), "ecb change: widening into a wall is pushed out")
	_check((w.contact & EcbFighterState.CONTACT_WALL_R) != 0, "ecb change: wall contact reported")

func _crush_stage() -> StageGeometry:
	var g: StageGeometry = StageGeometry.new()
	g.add_segment(_px(-400), 0, _px(400), 0)
	g.add_segment(_px(-15), _px(300), _px(-15), 0) # faces +X
	g.add_segment(_px(15), 0, _px(15), _px(300)) # faces -X: 30 px gap, ECB is 40 px wide
	g.blast_left = _px(-1000)
	g.blast_right = _px(1000)
	g.blast_top = _px(800)
	g.blast_bottom = _px(-600)
	return g

func _crush_trace(g: StageGeometry) -> PackedInt64Array:
	var s: EcbFighterState = _spawn(0, 200)
	var trace: PackedInt64Array = PackedInt64Array()
	for t in 60:
		EcbSolver.step(s, g, IDLE)
		trace.append(s.state_hash())
	return trace

func _test_crush_is_bounded_and_deterministic() -> void:
	var g: StageGeometry = _crush_stage()
	var caps_before: int = EcbSolver.debug_cap_hits
	var a: PackedInt64Array = _crush_trace(g)
	var b: PackedInt64Array = _crush_trace(g)
	_check(a.size() == 60 and a == b, "crush: unsolvable gap terminates and is deterministic")
	_check(EcbSolver.debug_cap_hits > caps_before, "crush: iteration cap was actually exercised")

# ---------- determinism / rollback ----------

func _fuzz_stage() -> StageGeometry:
	var g: StageGeometry = _base_stage()
	g.floor_x1[0] = _px(-400)
	g.floor_x2[0] = _px(400)
	g.add_segment(_px(-100), _px(120), _px(100), _px(120), StageGeometry.FLAG_DROP_THROUGH) # floor 1: platform
	g.add_segment(_px(300), 0, _px(300), _px(300)) # wall facing -X
	_add_block(g, -300, 0, -200, 80, false) # solid block on the floor
	g.add_segment(_px(200), 0, _px(200), _px(10)) # low step
	g.add_segment(_px(200), _px(10), _px(300), _px(10))
	_add_block(g, 150, 160, 250, 220, true) # floating block
	return g

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
		btns = InputFrame.JUMP if (r >> 20) % 45 == 0 else 0
		inputs.append(InputFrame.pack(sx, sy, 0, 0, btns))
	return inputs

## Harness respawn: a pure function of state, so it is identical across runs and after restore.
func _respawn(s: EcbFighterState) -> void:
	s.x = _px(0)
	s.y = _px(300)
	s.vel_x = 0
	s.vel_y = 0
	s.ground_id = -1
	s.drop_timer = 0
	s.dead = 0
	s.contact = 0
	_deaths += 1

func _tally_tick(s: EcbFighterState, prev_ground: int, prev_y: int) -> void:
	if (s.contact & EcbFighterState.CONTACT_CEIL) != 0:
		_cov["ceil"] += 1
	if (s.contact & EcbFighterState.CONTACT_WALL_L) != 0:
		_cov["wall_l"] += 1
	if (s.contact & EcbFighterState.CONTACT_WALL_R) != 0:
		_cov["wall_r"] += 1
	if prev_ground != -1 and s.ground_id != -1 and s.y > prev_y:
		_cov["step_up"] += 1
	if s.ground_id == -1:
		_cov["airborne"] += 1

func _run_trace(g: StageGeometry, inputs: PackedInt64Array, s: EcbFighterState, from_tick: int) -> PackedInt64Array:
	var trace: PackedInt64Array = PackedInt64Array()
	for t in range(from_tick, inputs.size()):
		if s.dead != 0:
			_respawn(s)
		var caps_before: int = EcbSolver.debug_cap_hits
		var prev_ground: int = s.ground_id
		var prev_y: int = s.y
		EcbSolver.step(s, g, inputs[t])
		trace.append(s.state_hash())
		if _tally:
			_tally_tick(s, prev_ground, prev_y)
		if not _verify(s, g, caps_before, "fuzz t=%d" % t):
			break
	return trace

func _test_fuzz_determinism_and_snapshot() -> void:
	var g: StageGeometry = _fuzz_stage()
	var inputs: PackedInt64Array = _make_script(8000, 12345)
	var caps_start: int = EcbSolver.debug_cap_hits
	var pushes_start: int = EcbSolver.debug_endpoint_pushes

	_deaths = 0
	var a: EcbFighterState = _spawn(0, 300)
	_tally = true
	var trace_a: PackedInt64Array = _run_trace(g, inputs, a, 0)
	_tally = false
	var deaths_a: int = _deaths
	var b: EcbFighterState = _spawn(0, 300)
	var trace_b: PackedInt64Array = _run_trace(g, inputs, b, 0)
	_check(trace_a.size() == inputs.size(), "fuzz: ran the full script without a violation")
	_check(trace_a == trace_b, "determinism: two runs produce identical hash traces")
	_check(EcbSolver.debug_cap_hits == caps_start, "fuzz: pushout never needed the iteration cap")

	var c: EcbFighterState = _spawn(0, 300)
	var _pre: PackedInt64Array = _run_trace(g, inputs.slice(0, 700), c, 0)
	var snap: PackedInt64Array = c.to_array()
	var trace_c1: PackedInt64Array = _run_trace(g, inputs, c, 700)
	var d: EcbFighterState = EcbFighterState.new()
	d.from_array(snap)
	var trace_c2: PackedInt64Array = _run_trace(g, inputs, d, 700)
	_check(trace_c1 == trace_c2, "rollback: restore at tick 700 reproduces the same trace")
	_check(trace_a.slice(700) == trace_c1, "rollback: matches the uninterrupted run")
	_cov["endpoint_pushes"] = EcbSolver.debug_endpoint_pushes - pushes_start
	print("fuzz coverage: ", _cov)
	_check(_cov["ceil"] > 0 and _cov["step_up"] > 0 and (_cov["wall_l"] + _cov["wall_r"]) > 0 and _cov["endpoint_pushes"] > 0, "fuzz: exercised ceiling, wall, step-up, and corner pushouts")
	print("fuzz: final tick %d, respawns=%d, hash=%d" % [a.tick, deaths_a, a.state_hash()])
	if GOLDEN_FUZZ_HASH != 0:
		_check(a.state_hash() == GOLDEN_FUZZ_HASH, "golden: fuzz hash matches recorded value")
