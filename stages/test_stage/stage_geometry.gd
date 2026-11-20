class_name StageGeometry
extends RefCounted
## Baked stage geometry. Packed integer arrays, sub-units, Y-up.
## Segments are authored a -> b. The OPEN (collidable-from) side is the LEFT of a -> b:
##   left-to-right  = floor (open side up)
##   right-to-left  = ceiling (open side down)
##   top-to-bottom  = wall facing +X (open side right)
##   bottom-to-top  = wall facing -X (open side left)
## v1: axis-aligned only. Slopes are rejected.

const FLAG_DROP_THROUGH: int = 1

var floor_x1: PackedInt64Array = PackedInt64Array()
var floor_x2: PackedInt64Array = PackedInt64Array()
var floor_y: PackedInt64Array = PackedInt64Array()
var floor_flags: PackedInt64Array = PackedInt64Array()

var ceil_x1: PackedInt64Array = PackedInt64Array()
var ceil_x2: PackedInt64Array = PackedInt64Array()
var ceil_y: PackedInt64Array = PackedInt64Array()

# wall_dir: +1 = open side faces +X (blocks leftward movement), -1 = faces -X (blocks rightward)
var wall_x: PackedInt64Array = PackedInt64Array()
var wall_y1: PackedInt64Array = PackedInt64Array() # lower
var wall_y2: PackedInt64Array = PackedInt64Array() # upper
var wall_dir: PackedInt64Array = PackedInt64Array()

# Four independent blast zone values
var blast_left: int = 0
var blast_right: int = 0
var blast_top: int = 0
var blast_bottom: int = 0

func floor_count() -> int:
	return floor_x1.size()

## Returns the new segment's index within its category, or -1 on rejection.
func add_segment(x1: int, y1: int, x2: int, y2: int, flags: int = 0) -> int:
	var dx: int = x2 - x1
	var dy: int = y2 - y1
	if dy == 0 and dx != 0:
		if dx > 0:
			floor_x1.append(x1)
			floor_x2.append(x2)
			floor_y.append(y1)
			floor_flags.append(flags)
			return floor_x1.size() - 1
		ceil_x1.append(x2)
		ceil_x2.append(x1)
		ceil_y.append(y1)
		return ceil_x1.size() - 1
	if dx == 0 and dy != 0:
		wall_x.append(x1)
		if dy > 0:
			wall_dir.append(-1)
			wall_y1.append(y1)
			wall_y2.append(y2)
		else:
			wall_dir.append(1)
			wall_y1.append(y2)
			wall_y2.append(y1)
		return wall_x.size() - 1
	push_error("StageGeometry.add_segment: only axis-aligned, non-zero-length segments supported in v1")
	return -1
