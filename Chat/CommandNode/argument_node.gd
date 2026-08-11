class_name ArgumentNode
extends CommandNode

enum Type { STRING, INT, FLOAT, ANY }

var arg_type: Type
var custom_suggestions: Array[String] = []
var value_map: Dictionary = {}

func _init(_name: String, _type: Type = Type.STRING, _suggestions: Array[String] = [], _value_map: Dictionary = {}) -> void:
	super(_name)
	arg_type = _type
	custom_suggestions = _suggestions
	value_map = _value_map
	if custom_suggestions.is_empty() and not value_map.is_empty():
		for key in value_map.keys():
			custom_suggestions.append(key)

func parse(token: String) -> bool:
	match arg_type:
		Type.INT:
			return token.is_valid_int()
		Type.FLOAT:
			return token.is_valid_float()
		Type.STRING:
			if not custom_suggestions.is_empty():
				matches_suggestions(token)
			return true
		Type.ANY: # any number or one of the suggestions (":" extra for HH:MM format)
			if token.is_valid_int() or token.is_valid_float() or ":" in token:
				return true
			return matches_suggestions(token)
	return false

func matches_suggestions(token: String) -> bool:
	var lower_token := token.to_lower()
	for s in custom_suggestions:
		if s.to_lower() == lower_token:
			return true
	return false

func get_resolved_value(token: String):
	var lower_token := token.to_lower()
	if value_map.has(lower_token):
		return value_map[lower_token]
	match arg_type:
		Type.INT:
			return token.to_int()
		Type.FLOAT:
			return token.to_float()
		_:
			return token

func contribute_to_context(context: CommandContext, token: String):
	context.add_argument(name, get_resolved_value(token))

func get_completions(prefix: String) -> Array[String]:
	var result: Array[String] = []
	for suggestion in custom_suggestions:
		if suggestion.to_lower().begins_with(prefix):
			result.append(suggestion)
	return result
