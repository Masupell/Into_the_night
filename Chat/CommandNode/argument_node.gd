class_name ArgumentNode
extends CommandNode

enum Type { STRING, INT, FLOAT }

var arg_type: Type
var custom_suggestions: Array[String] = []

func _init(_name: String, _type: Type = Type.STRING, _suggestions: Array[String] = []) -> void:
	super(name)
	arg_type = _type
	custom_suggestions = _suggestions

func parse(token: String) -> bool:
	match arg_type:
		Type.INT:
			return token.is_valid_int()
		Type.FLOAT:
			return token.is_valid_float()
		Type.STRING:
			if not custom_suggestions.is_empty():
				for s in custom_suggestions:
					if s.to_lower() == token.to_lower():
						return true
			return true
	return false
