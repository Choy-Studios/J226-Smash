class_name EcbSolver
extends RefCounted
## Deterministic integer ECB (rhombus) solver. Axis-aligned geometry only. v1 SimSolver is untouched.
##
## Tick: input -> velocity -> re-anchor -> N substeps -> blast zones.
## Substep: move X (side vertices sweep walls) -> ground update (step-up / support / transfer)
##          -> move Y (bottom vertex sweeps floors, top vertex sweeps ceilings) -> pushout.
## Pushout (max MAX_PUSHOUT_ITER passes): static vertex penetration, then surface endpoints inside the rhombus.
## Velocity is never zeroed by walls or ceilings; only landing zeroes vel_y.

const MAX_SUBSTEPS: int = 8
const MAX_PUSHOUT_ITER: int = 4

## Diagnostics only. Never read by the sim and never part of rollback state.
## Counts steps whose pushout was still changing the state after the final iteration.
static var debug_cap_hits: int = 0
## Diagnostics only: number of rhombus-vs-endpoint pushouts applied.
static var debug_endpoint_pushes: int = 0

# ---------- vertex helpers ----------

static func _cx(s: EcbFighterState) -> int:
	return s.x + s.off_x

static func _bottom_y(s: EcbFighterState) -> int:
	return s.y + s.off_y + s.bottom_y

static func _mid_y(s: EcbFighterState) -> int:
	return s.y + s.off_y + s.mid_y

static func _top_y(s: EcbFighterState) -> int:
	return s.y + s.off_y + s.top_y

static func _floor_has_x(geo: StageGeometry, i: int, px: int) -> bool:
	return px >= geo.floor_x1[i] and px <= geo.floor_x2[i]

static func _ceil_has_x(geo: StageGeometry, i: int, px: int) -> bool:
	return px >= geo.ceil_x1[i] and px <= geo.ceil_x2[i]

static func _is_drop(geo: StageGeometry, i: int) -> bool:
	return (geo.floor_flags[i] & StageGeometry.FLAG_DROP_THROUGH) != 0

static func _ceil_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return (a + b - 1) / b

## Exact split of `total` over n substeps: the n pieces always sum to `total`.
static func split(total: int, n: int, i: int) -> int:
	@warning_ignore("integer_division")
	return (total * (i + 1)) / n - (total * i) / n

static func _substep_count(s: EcbFighterState) -> int:
	var speed: int = maxi(absi(s.vel_x), absi(s.vel_y))
	var extent: int = mini(s.half_w, mini(s.mid_y - s.bottom_y, s.top_y - s.mid_y))
	@warning_ignore("integer_division")
	var limit: int = maxi(1, extent / 2)
	return clampi(_ceil_div(speed, limit), 1, MAX_SUBSTEPS)

# ---------- tick ----------

static func step(s: EcbFighterState, geo: StageGeometry, packed_input: int) -> void:
	s.tick += 1
	s.contact = 0
	if s.dead != 0:
		return

	var stick_fx: int = FixedMath.div(InputFrame.left_x(packed_input), InputFrame.STICK_MAX)
	var stick_y: int = InputFrame.left_y(packed_input)
	var jump_pressed: bool = InputFrame.just_pressed(packed_input, s.prev_input, InputFrame.JUMP)
	s.prev_input = packed_input

	if s.drop_timer > 0:
		s.drop_timer -= 1

	if s.ground_id != -1:
		var target: int = FixedMath.mul(SimConsts.WALK_SPEED, stick_fx)
		s.vel_x = _approach(s.vel_x, target, SimConsts.GROUND_ACCEL)
		s.vel_y = 0
		if jump_pressed:
			s.vel_y = SimConsts.JUMP_VEL
			s.ground_id = -1
		elif stick_y <= SimConsts.DROP_STICK and _is_drop(geo, s.ground_id):
			s.drop_timer = SimConsts.DROP_FRAMES
			s.ground_id = -1
	else:
		# Launch-speed velocities (above the normal caps) are left untouched.
		if absi(s.vel_x) <= SimConsts.AIR_SPEED:
			var air_target: int = FixedMath.mul(SimConsts.AIR_SPEED, stick_fx)
			s.vel_x = _approach(s.vel_x, air_target, SimConsts.AIR_ACCEL)
		if s.vel_y > -SimConsts.MAX_FALL:
			s.vel_y = maxi(s.vel_y - SimConsts.GRAVITY, -SimConsts.MAX_FALL)

	# ECB values may have changed since last tick: keep a grounded fighter's bottom vertex on its floor.
	if s.ground_id != -1:
		s.y = geo.floor_y[s.ground_id] - s.off_y - s.bottom_y

	var n: int = _substep_count(s)
	var total_dx: int = s.vel_x
	var total_dy: int = s.vel_y
	for i in n:
		_move_x(s, geo, split(total_dx, n, i))
		_ground_update(s, geo)
		_move_y(s, geo, split(total_dy, n, i))
		_resolve(s, geo)

	_check_blast(s, geo)

# ---------- movement ----------

## Side vertices sweep walls. Position is clamped, velocity is kept.
static func _move_x(s: EcbFighterState, geo: StageGeometry, dx: int) -> void:
	if dx == 0:
		return
	var c: int = _cx(s)
	var ym: int = _mid_y(s)
	var w: int = s.half_w
	var best: int = c + dx
	var hit: bool = false
	if dx > 0:
		var edge_old: int = c + w
		var edge_new: int = c + dx + w
		for i in geo.wall_x.size():
			if geo.wall_dir[i] != -1:
				continue
			var wx: int = geo.wall_x[i]
			if edge_old <= wx and edge_new > wx and ym > geo.wall_y1[i] and ym < geo.wall_y2[i]:
				var cand: int = wx - w
				if cand < best:
					best = cand
					hit = true
		if hit:
			s.contact |= EcbFighterState.CONTACT_WALL_R
	else:
		var edge_old2: int = c - w
		var edge_new2: int = c + dx - w
		for i in geo.wall_x.size():
			if geo.wall_dir[i] != 1:
				continue
			var wx2: int = geo.wall_x[i]
			if edge_old2 >= wx2 and edge_new2 < wx2 and ym > geo.wall_y1[i] and ym < geo.wall_y2[i]:
				var cand2: int = wx2 + w
				if cand2 > best:
					best = cand2
					hit = true
		if hit:
			s.contact |= EcbFighterState.CONTACT_WALL_L
	s.x += best - c

## Grounded fighters: step-up onto low solid floors, keep support, same-height floor transfer, or leave the ground.
static func _ground_update(s: EcbFighterState, geo: StageGeometry) -> void:
	if s.ground_id == -1:
		return
	var g: int = s.ground_id
	var bx: int = _cx(s)
	var feet: int = geo.floor_y[g]
	var ym: int = _mid_y(s)

	# Step-up: a solid floor under the bottom vertex that is above the feet but below the side vertices.
	var best: int = -1
	var best_y: int = 0
	for i in geo.floor_count():
		if _is_drop(geo, i):
			continue
		var fy: int = geo.floor_y[i]
		if fy > feet and fy < ym and _floor_has_x(geo, i, bx) and (best == -1 or fy > best_y):
			best = i
			best_y = fy
	if best != -1:
		s.y = best_y - s.off_y - s.bottom_y
		s.ground_id = best
		return

	if _floor_has_x(geo, g, bx):
		return

	# Same-height transfer (seams). Lowest index wins ties. No snap-down: anything else is airborne.
	for i in geo.floor_count():
		if i != g and geo.floor_y[i] == feet and _floor_has_x(geo, i, bx):
			s.ground_id = i
			return
	s.ground_id = -1

## Bottom vertex sweeps floors (landing), top vertex sweeps ceilings. Ceilings keep vel_y.
static func _move_y(s: EcbFighterState, geo: StageGeometry, dy: int) -> void:
	if s.ground_id != -1:
		s.vel_y = 0
		return
	if dy == 0:
		return
	var bx: int = _cx(s)
	if dy < 0:
		var yb: int = _bottom_y(s)
		var new_yb: int = yb + dy
		var best_i: int = -1
		var best_y: int = 0
		for i in geo.floor_count():
			if s.drop_timer > 0 and _is_drop(geo, i):
				continue
			var fy: int = geo.floor_y[i]
			if yb >= fy and new_yb <= fy and (best_i == -1 or fy > best_y) and _floor_has_x(geo, i, bx):
				best_i = i
				best_y = fy
		if best_i != -1:
			s.y += best_y - yb
			s.vel_y = 0
			s.ground_id = best_i
			return
	else:
		var yt: int = _top_y(s)
		var new_yt: int = yt + dy
		var best_c: int = -1
		var best_cy: int = 0
		for i in geo.ceil_y.size():
			var cy: int = geo.ceil_y[i]
			if yt <= cy and new_yt >= cy and (best_c == -1 or cy < best_cy) and _ceil_has_x(geo, i, bx):
				best_c = i
				best_cy = cy
		if best_c != -1:
			s.y += best_cy - yt
			s.contact |= EcbFighterState.CONTACT_CEIL
			return
	s.y += dy

# ---------- pushout ----------

static func _resolve(s: EcbFighterState, geo: StageGeometry) -> void:
	var changed: bool = false
	for _pass in MAX_PUSHOUT_ITER:
		changed = _pushout_pass(s, geo)
		if not changed:
			break
	if changed:
		debug_cap_hits += 1
	_ground_update(s, geo)

static func _apply_push(s: EcbFighterState, ux: int, uy: int) -> void:
	s.x += ux
	s.y += uy
	if ux < 0:
		s.contact |= EcbFighterState.CONTACT_WALL_R
	elif ux > 0:
		s.contact |= EcbFighterState.CONTACT_WALL_L
	if uy < 0:
		s.contact |= EcbFighterState.CONTACT_CEIL

static func _pushout_pass(s: EcbFighterState, geo: StageGeometry) -> bool:
	var changed: bool = false
	var grounded: bool = s.ground_id != -1

	# Static vertex penetration (ECB growth, or a previous pushout shoving us into another surface).
	if not grounded:
		for i in geo.ceil_y.size():
			var cy: int = geo.ceil_y[i]
			var yt: int = _top_y(s)
			if yt > cy and yt < cy + (s.top_y - s.mid_y) and _ceil_has_x(geo, i, _cx(s)):
				_apply_push(s, 0, cy - yt)
				changed = true
	for i in geo.wall_x.size():
		var wx: int = geo.wall_x[i]
		var ym: int = _mid_y(s)
		if ym <= geo.wall_y1[i] or ym >= geo.wall_y2[i]:
			continue
		var c: int = _cx(s)
		if geo.wall_dir[i] == -1:
			var rx: int = c + s.half_w
			if c < wx and rx > wx:
				_apply_push(s, wx - rx, 0)
				changed = true
		else:
			var lx: int = c - s.half_w
			if c > wx and lx < wx:
				_apply_push(s, wx - lx, 0)
				changed = true
	if not grounded:
		for i in geo.floor_count():
			if _is_drop(geo, i):
				continue
			var fy: int = geo.floor_y[i]
			var yb: int = _bottom_y(s)
			if yb < fy and yb > fy - (s.mid_y - s.bottom_y) and _floor_has_x(geo, i, _cx(s)):
				s.y += fy - yb
				if s.vel_y <= 0:
					s.vel_y = 0
					s.ground_id = i
				changed = true

	if _endpoint_pass(s, geo, false) > 0:
		changed = true
	return changed

## Grounded fighters skip endpoints that are low steps: those are handled by the step-up lift.
static func _is_step_point(s: EcbFighterState, grounded: bool, py: int) -> bool:
	return grounded and py > _bottom_y(s) and py < _mid_y(s)

## Applies (or, when dry, only counts) rhombus-vs-endpoint pushouts. One-sided rule: an endpoint
## only counts if the rhombus center is on the open side of a solid segment that ends there.
static func _endpoint_pass(s: EcbFighterState, geo: StageGeometry, dry: bool) -> int:
	var n: int = 0
	var gr: bool = s.ground_id != -1
	for i in geo.floor_count():
		if _is_drop(geo, i):
			continue
		var fy: int = geo.floor_y[i]
		if _mid_y(s) <= fy or _is_step_point(s, gr, fy):
			continue
		if _push_from_point(s, geo.floor_x1[i], fy, gr, dry):
			n += 1
		if _push_from_point(s, geo.floor_x2[i], fy, gr, dry):
			n += 1
	for i in geo.ceil_y.size():
		var cy: int = geo.ceil_y[i]
		if _mid_y(s) >= cy:
			continue
		if _push_from_point(s, geo.ceil_x1[i], cy, gr, dry):
			n += 1
		if _push_from_point(s, geo.ceil_x2[i], cy, gr, dry):
			n += 1
	for i in geo.wall_x.size():
		var wx: int = geo.wall_x[i]
		var c: int = _cx(s)
		if geo.wall_dir[i] == -1:
			if c >= wx:
				continue
		elif c <= wx:
			continue
		var y1: int = geo.wall_y1[i]
		var y2: int = geo.wall_y2[i]
		if not _is_step_point(s, gr, y1) and _push_from_point(s, wx, y1, gr, dry):
			n += 1
		if not _is_step_point(s, gr, y2) and _push_from_point(s, wx, y2, gr, dry):
			n += 1
	return n

## If the point is strictly inside the rhombus, push the fighter out along the hit edge's normal
## (or horizontally only when grounded). Magnitudes round away so the point always ends outside.
## f is the penetration measure: > 0 inside, 0 on the edge. Returns true if the point was inside.
static func _push_from_point(s: EcbFighterState, px: int, py: int, horizontal_only: bool, dry: bool) -> bool:
	var yb: int = _bottom_y(s)
	var ym: int = _mid_y(s)
	var yt: int = _top_y(s)
	if py <= yb or py >= yt:
		return false
	var w: int = s.half_w
	var dx: int = px - _cx(s)
	var sgn: int = -1 if dx < 0 else 1
	var adx: int = absi(dx)
	var lower: bool = py <= ym
	var h: int = (ym - yb) if lower else (yt - ym)
	var f: int = (w * (py - yb) - adx * h) if lower else (w * (yt - py) - adx * h)
	if f <= 0:
		return false
	if dry:
		return true
	var ux: int = 0
	var uy: int = 0
	if horizontal_only:
		ux = -sgn * _ceil_div(f, h)
	else:
		var nn: int = h * h + w * w
		ux = -sgn * _ceil_div(h * f, nn)
		uy = _ceil_div(w * f, nn)
		if not lower:
			uy = -uy
	debug_endpoint_pushes += 1
	_apply_push(s, ux, uy)
	return true

## Diagnostics: number of applicable surface endpoints strictly inside the rhombus.
static func count_endpoint_penetrations(s: EcbFighterState, geo: StageGeometry) -> int:
	return _endpoint_pass(s, geo, true)

# ---------- blast zones / invariants / helpers ----------

static func _check_blast(s: EcbFighterState, geo: StageGeometry) -> void:
	if s.x < geo.blast_left or s.x > geo.blast_right or s.y < geo.blast_bottom or s.y > geo.blast_top:
		s.dead = 1

## Returns "" if state is consistent, otherwise a description of the violation.
static func check_invariants(s: EcbFighterState, geo: StageGeometry) -> String:
	if s.half_w <= 0 or not (s.bottom_y < s.mid_y and s.mid_y < s.top_y):
		return "ECB shape invalid"
	if s.ground_id != -1:
		if s.ground_id < 0 or s.ground_id >= geo.floor_count():
			return "ground_id out of range: %d" % s.ground_id
		if _bottom_y(s) != geo.floor_y[s.ground_id]:
			return "grounded but bottom vertex y != floor_y (bottom=%d floor=%d)" % [_bottom_y(s), geo.floor_y[s.ground_id]]
		if not _floor_has_x(geo, s.ground_id, _cx(s)):
			return "grounded but bottom vertex not over ground floor"
		if s.vel_y != 0:
			return "grounded with nonzero vel_y"
	return ""

static func _approach(v: int, target: int, amount: int) -> int:
	if v < target:
		return mini(v + amount, target)
	if v > target:
		return maxi(v - amount, target)
	return v
