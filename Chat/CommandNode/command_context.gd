class_name CommandContext
extends RefCounted

var arguments: Dictionary = {}

func add_argument(arg_name: String, token: String):
	arguments[arg_name] = token

func get_string(arg_name: String) -> String:
	return arguments.get(arg_name, "")

func get_int(arg_name: String) -> int:
	var raw: String = arguments.get(arg_name, "0")
	return raw.to_int()

func get_float(arg_name: String) -> float:
	var raw: String = arguments.get(arg_name, "0.0")
	return raw.to_float()
