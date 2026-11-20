class_name InputMapper
extends RefCounted
# Turns one RawInput into one packed InputFrame per sim tick.
# Owns its own history. That is fine: it lives outside sim/ and is never snapshotted.
# Call step() exactly once per real frame. Rollback replays stored frames, not this.
#
# Stage order (v1):
#   1. Bindings: physical sources -> buttons, stick directions, modifiers
#   2. Opposing digital directions cancel to neutral (left+right, up+down)
#   3. Analog sticks: deadzone, rescale, quantize to ints
#   4. Merge digital and analog (digital wins per axis)
#   5. Modifiers: taunt (consumes the stick), walk (clamps the stick)
#   6. [stubs] classic flick, tap jump, C-stick bit emission
#   7. Pack into an InputFrame

const TAUNT_STICK_THRESHOLD: int = 64   # stick value that counts as a taunt direction

# Small counters, not buffers. Fields exist now; the logic that uses them comes later.
class History:
	var prev_left: Vector2i = Vector2i.ZERO
	var prev_right: Vector2i = Vector2i.ZERO
	var frames_since_smash_cross: int = 0    # stub: classic flick detection
	var frames_since_normal_press: int = 0   # stub: classic flick detection

var profile: InputProfile
var compiled: CompiledBindings
var history: History = History.new()

func _init(p: InputProfile) -> void:
	profile = p
	compiled = p.compile()

# Call on match start, pause, or controller disconnect.
func reset() -> void:
	history = History.new()

func step(raw: RawInput) -> int:
	var buttons: int = 0
	var pos: Array[int] = [0, 0, 0, 0]   # strongest positive digital value per stick channel
	var neg: Array[int] = [0, 0, 0, 0]   # strongest negative digital value (stored positive)
	var walk: bool = false
	var taunt: bool = false

	# Stage 1: bindings
	for src in raw.held:
		var b: InputBinding = compiled.get_binding(src)
		if b == null:
			continue
		if b.target_type == InputBinding.TARGET_BUTTON:
			buttons |= b.target_id
		elif b.target_type == InputBinding.TARGET_STICK:
			if b.value > 0:
				pos[b.target_id] = maxi(pos[b.target_id], b.value)
			else:
				neg[b.target_id] = maxi(neg[b.target_id], -b.value)
		elif b.target_type == InputBinding.TARGET_MODIFIER:
			if b.target_id == InputBinding.MOD_WALK:
				walk = true
			elif b.target_id == InputBinding.MOD_TAUNT:
				taunt = true

	# Stage 2: opposing digital directions resolve mathematically to neutral
	var dig: Array[int] = [0, 0, 0, 0]
	for i in 4:
		if pos[i] > 0 and neg[i] > 0:
			dig[i] = 0
		else:
			dig[i] = pos[i] - neg[i]

	# Stage 3: analog sticks
	var left_analog: Vector2i = quantize_stick(raw.left_stick, profile.left_deadzone)
	var right_analog: Vector2i = Vector2i.ZERO
	if profile.c_stick_mode != InputProfile.C_STICK_OFF:
		right_analog = quantize_stick(raw.right_stick, profile.right_deadzone)

	# Stage 4: merge, digital wins per axis
	var lx: int = dig[InputBinding.STICK_LEFT_X] if dig[InputBinding.STICK_LEFT_X] != 0 else left_analog.x
	var ly: int = dig[InputBinding.STICK_LEFT_Y] if dig[InputBinding.STICK_LEFT_Y] != 0 else left_analog.y
	var rx: int = dig[InputBinding.STICK_RIGHT_X] if dig[InputBinding.STICK_RIGHT_X] != 0 else right_analog.x
	var ry: int = dig[InputBinding.STICK_RIGHT_Y] if dig[InputBinding.STICK_RIGHT_Y] != 0 else right_analog.y

	# Stage 5: modifiers
	if taunt:
		# While held, the left stick becomes taunt bits and sends no movement.
		if ly >= TAUNT_STICK_THRESHOLD:
			buttons |= InputFrame.TAUNT_UP
		elif ly <= -TAUNT_STICK_THRESHOLD:
			buttons |= InputFrame.TAUNT_DOWN
		if lx <= -TAUNT_STICK_THRESHOLD:
			buttons |= InputFrame.TAUNT_LEFT
		elif lx >= TAUNT_STICK_THRESHOLD:
			buttons |= InputFrame.TAUNT_RIGHT
		lx = 0
		ly = 0
	elif walk:
		lx = clampi(lx, -profile.walk_value, profile.walk_value)
		ly = clampi(ly, -profile.walk_value, profile.walk_value)

	# Stage 6: TODO classic flick (Normal + left-stick flick -> Smash bit),
	# tap jump (upward flick -> Jump bit), C-stick threshold -> Smash or Normal bit.
	# The right stick passes through as an attack-direction channel only.

	# Stage 7: remember and pack
	history.prev_left = Vector2i(lx, ly)
	history.prev_right = Vector2i(rx, ry)
	return InputFrame.pack(lx, ly, rx, ry, buttons)

# Radial deadzone, rescale so the edge of the deadzone maps to 0, then quantize.
# This is the one place a float becomes an int. Rounding is roundi (half away from zero).
static func quantize_stick(v: Vector2, deadzone: float) -> Vector2i:
	var m: float = v.length()
	if m <= deadzone:
		return Vector2i.ZERO
	var scaled: float = (minf(m, 1.0) - deadzone) / (1.0 - deadzone)
	var out: Vector2 = v / m * scaled
	var max_value: float = float(InputFrame.STICK_MAX)
	return Vector2i(
		clampi(roundi(out.x * max_value), -InputFrame.STICK_MAX, InputFrame.STICK_MAX),
		clampi(roundi(out.y * max_value), -InputFrame.STICK_MAX, InputFrame.STICK_MAX))
