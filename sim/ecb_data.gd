class_name EcbData
extends RefCounted
## Per-fighter ECB (rhombus) defaults. Integer sub-units, relative to the fighter origin.
## JSON numbers parse as floats, so every value goes through a strict bridge: it must be a
## whole number (and exactly representable) before it becomes an int. No float reaches the sim.

const KEYS: Array[String] = ["half_w", "bottom_y", "mid_y", "top_y", "off_x", "off_y"]
const MAX_SAFE: float = 9007199254740992.0 # 2^53: float -> int is exact below this

var half_w: int = 0
var bottom_y: int = 0
var mid_y: int = 0
var top_y: int = 0
var off_x: int = 0
var off_y: int = 0

## Returns null (and pushes an error) on any problem: unknown key, missing key,
## non-whole number, or an invalid shape.
static func from_dict(d: Dictionary) -> EcbData:
	for k in d.keys():
		if not KEYS.has(k):
			push_error("EcbData: unknown key '%s'" % str(k))
			return null
	var out: EcbData = EcbData.new()
	for k in KEYS:
		if not d.has(k):
			push_error("EcbData: missing key '%s'" % k)
			return null
		var v: Variant = d[k]
		var iv: int = 0
		if typeof(v) == TYPE_INT:
			iv = v
		elif typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) < MAX_SAFE:
			iv = int(v)
		else:
			push_error("EcbData: '%s' must be a whole number, got %s" % [k, str(v)])
			return null
		out.set(k, iv)
	if out.half_w <= 0 or not (out.bottom_y < out.mid_y and out.mid_y < out.top_y):
		push_error("EcbData: invalid shape (need half_w > 0 and bottom_y < mid_y < top_y)")
		return null
	return out

static func load_json(path: String) -> EcbData:
	if not FileAccess.file_exists(path):
		push_error("EcbData: file not found: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("EcbData: %s is not a JSON object" % path)
		return null
	return from_dict(parsed)
