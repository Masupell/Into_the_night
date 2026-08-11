class_name CommandContext
extends RefCounted

var arguments: Dictionary = {}

func add_argument(arg_name: String, value: Variant):
	arguments[arg_name] = value

func has_argument(arg_name: String) -> bool:
	return arguments.has(arg_name)

func get_argument(arg_name: String, default: Variant = null) -> Variant:
	return arguments.get(arg_name, default)

func get_string(arg_name: String) -> String:
	return String(arguments.get(arg_name, ""))

func get_int(arg_name: String) -> int:
	var val = arguments.get(arg_name, 0)
	if val is int or val is float:
		return int(val)
	return String(val).to_int()


func get_float(arg_name: String) -> float:
	var val = arguments.get(arg_name, 0.0)
	if val is float or val is int:
		return float(val)
	return String(val).to_float()
