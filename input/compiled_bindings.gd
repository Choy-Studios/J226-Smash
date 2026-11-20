class_name CompiledBindings
extends RefCounted
# The runtime lookup table the mapper uses: source id (int) -> InputBinding.
# Built from a validated InputProfile. The mapper never touches JSON or strings.

var _by_source: Dictionary = {}

func add(binding: InputBinding) -> void:
	_by_source[binding.source] = binding

# Returns null when the source has no binding.
func get_binding(source_id: int) -> InputBinding:
	return _by_source.get(source_id)

func sources() -> Array:
	return _by_source.keys()

func size() -> int:
	return _by_source.size()
