class_name FighterState
extends RefCounted
## Flat integer state. No floats, no Vector2, no node refs: snapshot/restore is a plain copy.

var x: int = 0 # feet, bottom-center
var y: int = 0
var vel_x: int = 0
var vel_y: int = 0
var ground_id: int = -1 # floor index, -1 = airborne
var drop_timer: int = 0
var prev_input: int = 0 # last tick's packed InputFrame (for just_pressed)
var dead: int = 0
var tick: int = 0

func to_array() -> PackedInt64Array:
	return PackedInt64Array([x, y, vel_x, vel_y, ground_id, drop_timer, prev_input, dead, tick])

func from_array(a: PackedInt64Array) -> void:
	x = a[0]
	y = a[1]
	vel_x = a[2]
	vel_y = a[3]
	ground_id = a[4]
	drop_timer = a[5]
	prev_input = a[6]
	dead = a[7]
	tick = a[8]

func copy_from(o: FighterState) -> void:
	from_array(o.to_array())

## FNV-1a style fold over every state int (64-bit wraparound).
func state_hash() -> int:
	var h: int = -3750763034362895579 # FNV offset basis as signed int64
	for v in to_array():
		h = (h ^ v) * 1099511628211
	return h
