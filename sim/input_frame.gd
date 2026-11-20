class_name InputFrame
# One player's input for one frame, packed into a single int.
# Put this file in res://sim/. The sim defines the format; the input layer fills it.
#
# Layout (bit positions, lowest first):
#   0-7    left stick X   (signed byte, -127..127)
#   8-15   left stick Y   (stick up = +Y)
#   16-23  right stick X
#   24-31  right stick Y
#   32-47  button bits (12 used, 4 spare)
#   48-63  reserved, always 0
#
# Sticks are stored as two's-complement bytes, so a frame of 0 decodes to
# "everything neutral, nothing pressed". Default-initialized frames are safe.

const STICK_MAX: int = 127
const FIELD_MASK: int = 0xFF       # 8 bits
const LX_SHIFT: int = 0
const LY_SHIFT: int = 8
const RX_SHIFT: int = 16
const RY_SHIFT: int = 24
const BUTTON_SHIFT: int = 32
const BUTTON_MASK: int = 0xFFFF    # 16 bits

# --- Button bits (1 << n means "a 1 in bit position n") ---
const NORMAL: int = 1 << 0
const SPECIAL: int = 1 << 1
const JUMP: int = 1 << 2
const SHORT_HOP: int = 1 << 3
const SUPER: int = 1 << 4
const GRAB: int = 1 << 5
const SHIELD: int = 1 << 6
const TAUNT_UP: int = 1 << 7
const TAUNT_DOWN: int = 1 << 8
const TAUNT_LEFT: int = 1 << 9
const TAUNT_RIGHT: int = 1 << 10
const SMASH: int = 1 << 11
const ALL_BUTTONS: int = (1 << 12) - 1   # twelve 1s

# --- Packing ---
# clampi keeps sticks in range. "& FIELD_MASK" cuts a negative number down to
# its low 8 bits (two's complement). "<< shift" moves it into its slot.
# "|=" merges each field into the frame.
static func pack(lx: int, ly: int, rx: int, ry: int, button_bits: int) -> int:
	var frame: int = 0
	frame |= (clampi(lx, -STICK_MAX, STICK_MAX) & FIELD_MASK) << LX_SHIFT
	frame |= (clampi(ly, -STICK_MAX, STICK_MAX) & FIELD_MASK) << LY_SHIFT
	frame |= (clampi(rx, -STICK_MAX, STICK_MAX) & FIELD_MASK) << RX_SHIFT
	frame |= (clampi(ry, -STICK_MAX, STICK_MAX) & FIELD_MASK) << RY_SHIFT
	frame |= (button_bits & BUTTON_MASK) << BUTTON_SHIFT
	return frame

# --- Unpacking ---
# ">> shift" moves the field down to bit 0. "& FIELD_MASK" isolates 8 bits.
# Values above 127 were negative, so subtract 256 to restore the sign.
static func _stick(frame: int, shift: int) -> int:
	var raw: int = (frame >> shift) & FIELD_MASK
	return raw - 256 if raw > STICK_MAX else raw

static func left_x(frame: int) -> int:
	return _stick(frame, LX_SHIFT)

static func left_y(frame: int) -> int:
	return _stick(frame, LY_SHIFT)

static func right_x(frame: int) -> int:
	return _stick(frame, RX_SHIFT)

static func right_y(frame: int) -> int:
	return _stick(frame, RY_SHIFT)

static func buttons(frame: int) -> int:
	return (frame >> BUTTON_SHIFT) & BUTTON_MASK

# --- Button queries ---
# Always wrap bitwise expressions in parentheses when comparing.
static func is_down(frame: int, button: int) -> bool:
	return (buttons(frame) & button) != 0

# "Just pressed" is derived by comparing against the previous frame.
# The previous frame lives in fighter state, not in the input frame.
static func just_pressed(frame: int, prev_frame: int, button: int) -> bool:
	return is_down(frame, button) and not is_down(prev_frame, button)
