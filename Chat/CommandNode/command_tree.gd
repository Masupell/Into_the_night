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
	
	var raw_tokens := CommandParser.tokenize(input_text.substr(1))
	if raw_tokens.is_empty():
		return ""
	
	var current := root
	var context := CommandContext.new()
	
	for token in raw_tokens:
		var matched := find_matching_child(current, token)
		if matched == null:
			return "Invalid syntax near '%s'" % token
		matched.contribute_to_context(context, token)
		current = matched

	
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
	var raw_tokens := CommandParser.tokenize(input_text.substr(1))
	
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
		completed_tokens = raw_tokens
	else:
		active_prefix = raw_tokens[raw_tokens.size() - 1].to_lower()
		completed_tokens = raw_tokens.slice(0, raw_tokens.size() - 1)

	
	var current := root
	for token in completed_tokens:
		var matched := find_matching_child(current, token)
		if matched == null:
			return []
		current = matched
	
	var base_string := "/"
	for token in completed_tokens:
		base_string += " ".join(completed_tokens) + " "
	
	var matches: Array[String] = []
	for child_name in current.children:
		var child: CommandNode = current.children[child_name]
		for completion in child.get_completions(active_prefix):
			matches.append(base_string + completion)
	
	matches.sort()
	return matches

func find_matching_child(node: CommandNode, token: String) -> CommandNode:
	for child_name in node.children:
		var child: CommandNode = node.children[child_name]
		if child.parse(token):
			return child
	return null
