class_name SimSolver
extends RefCounted
## Custom deterministic solver. Integer math only.
## Order per tick: input -> velocity -> move X (sweep) -> support check -> move Y (sweep) -> blast zones.

static func step(s: FighterState, geo: StageGeometry, packed_input: int) -> void:
	s.tick += 1
	if s.dead != 0:
		return

	# Left stick X as a fixed-point fraction of full tilt (-SCALE..SCALE).
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
		elif stick_y <= SimConsts.DROP_STICK and (geo.floor_flags[s.ground_id] & StageGeometry.FLAG_DROP_THROUGH) != 0:
			s.drop_timer = SimConsts.DROP_FRAMES
			s.ground_id = -1
	else:
		# Launch-speed velocities (above the normal caps) are left untouched.
		if absi(s.vel_x) <= SimConsts.AIR_SPEED:
			var air_target: int = FixedMath.mul(SimConsts.AIR_SPEED, stick_fx)
			s.vel_x = _approach(s.vel_x, air_target, SimConsts.AIR_ACCEL)
		if s.vel_y > -SimConsts.MAX_FALL:
			s.vel_y = maxi(s.vel_y - SimConsts.GRAVITY, -SimConsts.MAX_FALL)

	_move_x(s, geo)
	_check_support(s, geo)
	_move_y(s, geo)
	_check_blast(s, geo)

static func _move_x(s: FighterState, geo: StageGeometry) -> void:
	var dx: int = s.vel_x
	if dx == 0:
		return
	var hw: int = SimConsts.BOX_HALF_W
	var top: int = s.y + SimConsts.BOX_H
	var new_x: int = s.x + dx
	var best: int = new_x
	var hit: bool = false
	if dx > 0:
		var edge_old: int = s.x + hw
		var edge_new: int = new_x + hw
		for i in geo.wall_x.size():
			if geo.wall_dir[i] != -1:
				continue
			var wx: int = geo.wall_x[i]
			if edge_old <= wx and edge_new > wx and s.y < geo.wall_y2[i] and top > geo.wall_y1[i]:
				var cand: int = wx - hw
				if cand < best:
					best = cand
					hit = true
	else:
		var edge_old2: int = s.x - hw
		var edge_new2: int = new_x - hw
		for i in geo.wall_x.size():
			if geo.wall_dir[i] != 1:
				continue
			var wx2: int = geo.wall_x[i]
			if edge_old2 >= wx2 and edge_new2 < wx2 and s.y < geo.wall_y2[i] and top > geo.wall_y1[i]:
				var cand2: int = wx2 + hw
				if cand2 > best:
					best = cand2
					hit = true
	s.x = best
	if hit:
		s.vel_x = 0

static func _check_support(s: FighterState, geo: StageGeometry) -> void:
	if s.ground_id == -1:
		return
	var g: int = s.ground_id
	var hw: int = SimConsts.BOX_HALF_W
	if not (s.x + hw > geo.floor_x1[g] and s.x - hw < geo.floor_x2[g]):
		s.ground_id = -1

static func _move_y(s: FighterState, geo: StageGeometry) -> void:
	if s.ground_id != -1:
		s.vel_y = 0
		return
	var dy: int = s.vel_y
	if dy == 0:
		return
	var hw: int = SimConsts.BOX_HALF_W
	var new_y: int = s.y + dy
	if dy < 0:
		# Falling: land on the highest floor crossed this tick.
		var best_i: int = -1
		var best_y: int = 0
		for i in geo.floor_count():
			if s.drop_timer > 0 and (geo.floor_flags[i] & StageGeometry.FLAG_DROP_THROUGH) != 0:
				continue
			var fy: int = geo.floor_y[i]
			if s.y >= fy and new_y <= fy and (best_i == -1 or fy > best_y):
				if s.x + hw > geo.floor_x1[i] and s.x - hw < geo.floor_x2[i]:
					best_i = i
					best_y = fy
		if best_i != -1:
			s.y = best_y
			s.vel_y = 0
			s.ground_id = best_i
			return
	else:
		# Rising: stop under the lowest ceiling crossed this tick.
		var top_old: int = s.y + SimConsts.BOX_H
		var top_new: int = new_y + SimConsts.BOX_H
		var best_c: int = -1
		var best_cy: int = 0
		for i in geo.ceil_y.size():
			var cy: int = geo.ceil_y[i]
			if top_old <= cy and top_new >= cy and (best_c == -1 or cy < best_cy):
				if s.x + hw > geo.ceil_x1[i] and s.x - hw < geo.ceil_x2[i]:
					best_c = i
					best_cy = cy
		if best_c != -1:
			s.y = best_cy - SimConsts.BOX_H
			s.vel_y = 0
			return
	s.y = new_y

static func _check_blast(s: FighterState, geo: StageGeometry) -> void:
	if s.x < geo.blast_left or s.x > geo.blast_right or s.y < geo.blast_bottom or s.y > geo.blast_top:
		s.dead = 1

## Returns "" if state is consistent, otherwise a description of the violation.
static func check_invariants(s: FighterState, geo: StageGeometry) -> String:
	if s.ground_id != -1:
		if s.ground_id < 0 or s.ground_id >= geo.floor_count():
			return "ground_id out of range: %d" % s.ground_id
		if s.y != geo.floor_y[s.ground_id]:
			return "grounded but y != floor_y (y=%d floor=%d)" % [s.y, geo.floor_y[s.ground_id]]
		var hw: int = SimConsts.BOX_HALF_W
		if not (s.x + hw > geo.floor_x1[s.ground_id] and s.x - hw < geo.floor_x2[s.ground_id]):
			return "grounded but not over ground floor"
		if s.vel_y != 0:
			return "grounded with nonzero vel_y"
	return ""

static func _approach(v: int, target: int, amount: int) -> int:
	if v < target:
		return mini(v + amount, target)
	if v > target:
		return maxi(v - amount, target)
	return v
