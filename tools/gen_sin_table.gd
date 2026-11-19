@tool
extends EditorScript

func _run() -> void:
	var out: PackedStringArray = []
	for d in 360:
		out.append(str(roundi(sin(deg_to_rad(d)) * FixedMath.SCALE)))
	print("[", ", ".join(out), "]")
