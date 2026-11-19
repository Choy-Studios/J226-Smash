class_name FixedMath

# Static helper functions for fixed integer math
# floats are bad, we do not like them

const SCALE: int = 1000

# --- Conversion (ints only; float conversion lives render-side, not here) ---
static func from_px(px: int) -> int:
	return px * SCALE

# --- Multiply / divide ---
# In GDScript, int / int is integer division and truncates toward zero.
# That is deterministic. The annotation just silences the editor warning.
# Multiply BEFORE dividing, or you lose precision.

static func mul(a: int, b: int) -> int:
	@warning_ignore("integer_division")	
	return (a * b) / SCALE


static func div(a: int, b: int) -> int:
	@warning_ignore("integer_division")	
	return (a * SCALE) / b

# --- Squared distance (compare squared values instead of using sqrt) ---
# Vector2i components are 32-bit, but locals typed as int are 64-bit,
# so the multiplication below is safe.
static func dist_sq(a: Vector2i, b: Vector2i) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return dx * dx + dy * dy

# --- Trig lookup (whole degrees, values scaled by SCALE) ---
# Paste the 360 generated entries here. Never compute this at runtime.
const SIN_TABLE: Array[int] = [
	0, 17, 35, 52, 70, 87, 105, 122, 139, 156, 174, 191, 208, 225, 242, 259, 276, 292, 309, 326, 342, 358, 375, 391, 407, 423, 438, 454, 469, 485, 500, 515, 530, 545, 559, 574, 588, 602, 616, 629, 643, 656, 669, 682, 695, 707, 719, 731, 743, 755, 766, 777, 788, 799, 809, 819, 829, 839, 848, 857, 866, 875, 883, 891, 899, 906, 914, 921, 927, 934, 940, 946, 951, 956, 961, 966, 970, 974, 978, 982, 985, 988, 990, 993, 995, 996, 998, 999, 999, 1000, 1000, 1000, 999, 999, 998, 996, 995, 993, 990, 988, 985, 982, 978, 974, 970, 966, 961, 956, 951, 946, 940, 934, 927, 921, 914, 906, 899, 891, 883, 875, 866, 857, 848, 839, 829, 819, 809, 799, 788, 777, 766, 755, 743, 731, 719, 707, 695, 682, 669, 656, 643, 629, 616, 602, 588, 574, 559, 545, 530, 515, 500, 485, 469, 454, 438, 423, 407, 391, 375, 358, 342, 326, 309, 292, 276, 259, 242, 225, 208, 191, 174, 156, 139, 122, 105, 87, 70, 52, 35, 17, 0, -17, -35, -52, -70, -87, -105, -122, -139, -156, -174, -191, -208, -225, -242, -259, -276, -292, -309, -326, -342, -358, -375, -391, -407, -423, -438, -454, -469, -485, -500, -515, -530, -545, -559, -574, -588, -602, -616, -629, -643, -656, -669, -682, -695, -707, -719, -731, -743, -755, -766, -777, -788, -799, -809, -819, -829, -839, -848, -857, -866, -875, -883, -891, -899, -906, -914, -921, -927, -934, -940, -946, -951, -956, -961, -966, -970, -974, -978, -982, -985, -988, -990, -993, -995, -996, -998, -999, -999, -1000, -1000, -1000, -999, -999, -998, -996, -995, -993, -990, -988, -985, -982, -978, -974, -970, -966, -961, -956, -951, -946, -940, -934, -927, -921, -914, -906, -899, -891, -883, -875, -866, -857, -848, -839, -829, -819, -809, -799, -788, -777, -766, -755, -743, -731, -719, -707, -695, -682, -669, -656, -643, -629, -616, -602, -588, -574, -559, -545, -530, -515, -500, -485, -469, -454, -438, -423, -407, -391, -375, -358, -342, -326, -309, -292, -276, -259, -242, -225, -208, -191, -174, -156, -139, -122, -105, -87, -70, -52, -35, -17
	]

# posmod keeps the index in 0..359 even for negative angles.
static func sin_deg(deg: int) -> int:
	return SIN_TABLE[posmod(deg, 360)]

# cos is just sin shifted by 90 degrees.
static func cos_deg(deg: int) -> int:
	return SIN_TABLE[posmod(deg + 90, 360)]
