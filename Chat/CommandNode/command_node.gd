class_name CommandNode
extends RefCounted

var name: String = ""
var children: Dictionary = {} # String -> CommandNode
var callback: Callable = Callable()

var description: String = ""
var usage: String = ""

func _init(_name: String) -> void:
	name = _name

func add_child_node(node: CommandNode) -> CommandNode:
	children[node.name.to_lower()] = node
	return node

func executes(target_callback: Callable) -> CommandNode:
	callback = target_callback
	return self

func can_execute() -> bool:
	return callback.is_valid()
