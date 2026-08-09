class_name CommandTree
extends RefCounted

var root: CommandNode

func _init() -> void:
	root = CommandNode.new("root")

func register_command(cmd_node: CommandNode):
	root.add_child_node(cmd_node)

func execute(input_text: String) -> String:
	if not input_text.begins_with("/"):
		return ""
	
	var raw_tokens := input_text.substr(1).split(" ", false)
	if raw_tokens.is_empty():
		return ""
	
	var current := root
	var context := CommandContext.new()
	
	for token in raw_tokens:
		var matched_child: CommandNode = null
		
		for child_name in current.children:
			var child: CommandNode = current.children[child_name]
			
			if child is LiteralNode:
				if child.parse(token):
					matched_child = child
					break
			elif child is ArgumentNode:
				if child.parse(token):
					matched_child = child
					context.add_argument(child.name, token)
					break
		
		if matched_child != null:
			current = matched_child
		else:
			return "Invalid syntax near '%s'" % token
	
	if current.can_execute():
		var result = current.callback.call(context)
		if result is String:
			return result
		return ""
	return "Incomplete Command"

func get_suggestions(input_text: String) -> Array[String]:
	if not input_text.begins_with("/"):
		return []

	var has_trailing_space := input_text.ends_with(" ")
	var raw_tokens := Array(Array(input_text.substr(1).split(" ", false)), TYPE_STRING, "", null)
	
	# just typing '/', to show you all commands
	if raw_tokens.is_empty():
		var root_matches: Array[String] = []
		for child_name in root.children:
			root_matches.append("/" + child_name)
		root_matches.sort()
		return root_matches
	
	var active_prefix := ""
	var completed_tokens: Array[String] = []
	
	if has_trailing_space:
		active_prefix = ""
		completed_tokens = raw_tokens
	else:
		active_prefix = raw_tokens.back().to_lower()
		for i in range(raw_tokens.size() - 1):
			completed_tokens.append(raw_tokens[i])
	
	var current := root
	for token in completed_tokens:
		var matched_child: CommandNode = null
		for child_name in current.children:
			var child: CommandNode = current.children[child_name]
			if child is LiteralNode:
				if child.parse(token):
					matched_child = child
					break
				elif child is ArgumentNode:
					if child.parse(token):
						matched_child = child
						break
		
		if matched_child != null:
			current = matched_child
		else:
			return []
	
	var base_string := "/"
	for token in completed_tokens:
		base_string += token + " "
	
	var matches: Array[String] = []
	for child_name in current.children:
		var child: CommandNode = current.children[child_name]
		if child is LiteralNode:
			if child.name.to_lower().begins_with(active_prefix):
				matches.append(base_string + child.name)
			elif child is ArgumentNode:
				if not child.custom_suggestions.is_empty():
					for suggestion in child.custom_suggestions:
						if suggestion.to_lower().begins_with(active_prefix):
							matches.append(base_string + suggestion)
	
	matches.sort()
	return matches
