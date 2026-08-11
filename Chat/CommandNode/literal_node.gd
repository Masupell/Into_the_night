class_name LiteralNode
extends CommandNode

func _init(_name: String) -> void:
	super(_name)

func parse(token: String) -> bool:
	return token.to_lower() == name.to_lower()

func get_completions(prefix: String) -> Array[String]:
	if name.to_lower().begins_with(prefix):
		return [name]
	return []
