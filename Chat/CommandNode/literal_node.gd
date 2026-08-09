class_name LiteralNode
extends CommandNode

func _init(_name: String) -> void:
	super(name)

func parse(token: String) -> bool:
	return token.to_lower() == name.to_lower()
