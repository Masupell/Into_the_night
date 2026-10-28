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


# For coord arguments: "~" is current, "~5" current + 5, "5" is 5. Missing (optional argument) is current too
func get_coordinate(arg_name: String, current: float) -> float:
	if not arguments.has(arg_name):
		return current
	var token := String(arguments[arg_name])
	if token.begins_with("~"):
		return current + (token.substr(1).to_float() if token.length() > 1 else 0.0)
	return token.to_float()

func get_float(arg_name: String) -> float:
	var val = arguments.get(arg_name, 0.0)
	if val is float or val is int:
		return float(val)
	return String(val).to_float()
