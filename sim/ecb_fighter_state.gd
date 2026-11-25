class_name EcbFighterState
extends FighterState
## v2 fighter state. Extends v1 so FighterState (and its golden hash) stays untouched.
## Effective ECB values live here: the future state machine overwrites them, the solver only reads.
## All values are sub-units relative to the origin (x, y). Vertices (world):
##   bottom (cx, y + off_y + bottom_y)    top (cx, y + off_y + top_y)
##   left   (cx - half_w, y + off_y + mid_y)    right (cx + half_w, ...)    where cx = x + off_x

const CONTACT_CEIL: int = 1
const CONTACT_WALL_L: int = 2 # an obstacle is on the fighter's left
const CONTACT_WALL_R: int = 4 # an obstacle is on the fighter's right

var half_w: int = 0
var bottom_y: int = 0
var mid_y: int = 0
var top_y: int = 0
var off_x: int = 0
var off_y: int = 0
var contact: int = 0 # reset at the start of every step; OR of CONTACT_* bits

func apply_ecb(d: EcbData) -> void:
	half_w = d.half_w
	bottom_y = d.bottom_y
	mid_y = d.mid_y
	top_y = d.top_y
	off_x = d.off_x
	off_y = d.off_y

func to_array() -> PackedInt64Array:
	var a: PackedInt64Array = super.to_array()
	a.append_array(PackedInt64Array([half_w, bottom_y, mid_y, top_y, off_x, off_y, contact]))
	return a

func from_array(a: PackedInt64Array) -> void:
	super.from_array(a)
	half_w = a[9]
	bottom_y = a[10]
	mid_y = a[11]
	top_y = a[12]
	off_x = a[13]
	off_y = a[14]
	contact = a[15]
