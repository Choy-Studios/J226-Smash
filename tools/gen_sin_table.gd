@tool
extends EditorScript

# This generates a sin table based on the scale factor.
func _run() -> void:
	var out: PackedStringArray = []
	for d in 360:
		out.append(str(roundi(sin(deg_to_rad(d)) * FixedMath.SCALE)))
	print("[", ", ".join(out), "]")
