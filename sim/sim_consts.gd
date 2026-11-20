class_name SimConsts
extends RefCounted
## ALL placeholder tuning lives here. Units: sub-units (FixedMath.SCALE per px), per tick.

# Box fighter. Position is bottom-center (feet). Y-up.
const BOX_HALF_W: int = 20 * FixedMath.SCALE
const BOX_H: int = 60 * FixedMath.SCALE

# Ground
const WALK_SPEED: int = 5 * FixedMath.SCALE
const GROUND_ACCEL: int = 400

# Air
const AIR_SPEED: int = 4 * FixedMath.SCALE
const AIR_ACCEL: int = 200
const GRAVITY: int = 500
const MAX_FALL: int = 15 * FixedMath.SCALE
const JUMP_VEL: int = 14 * FixedMath.SCALE

# Platform drop-through (left stick Y, InputFrame range -127..127, down is negative)
const DROP_STICK: int = -76
const DROP_FRAMES: int = 12
