class_name CommandProcessor
extends Node

@export var console: CommandConsule
var tree: CommandTree = CommandTree.new()

func _ready() -> void:
	console.processor = self
	console.command_submitted.connect(process_command)
	register_command("help [<command_name>]", cmd_help, "Displays info about a specific command or lists all")

func register_command(pattern: String, callback: Callable, description: String = "", arg_value_maps: Dictionary = {}) -> void:
	_register(pattern, description, arg_value_maps, func(_line): return callback)
 
func register_command_multiple(pattern: String, target: Object, description: String = "", arg_value_maps: Dictionary = {}) -> void:
	_register(pattern, description, arg_value_maps, func(line): return _resolve_method_callback(line, target))


func _register(pattern: String, description: String, arg_value_maps: Dictionary, callback_resolver: Callable) -> void:
	var tokens := CommandParser.tokenize(pattern)
	if tokens.is_empty():
		return
 
	var root_name := tokens[0]
	for line in CommandParser.expand_branches(tokens):
		if line.is_empty():
			continue
		var callback: Callable = callback_resolver.call(line)
		if callback.is_valid():
			_build_line(line, callback, arg_value_maps)
 
	_set_root_metadata(root_name, description, pattern)
 
func _resolve_method_callback(line: Array, target: Object) -> Callable:
	var literals: Array[String] = []
	for token in line:
		var clean: String = String(token).trim_prefix("[").trim_suffix("]")
		if not (clean.begins_with("<") and clean.ends_with(">")):
			literals.append(clean.to_lower())
 
	var method_name := "cmd_" + "_".join(literals)
	if target.has_method(method_name):
		return Callable(target, method_name)
 
	push_error("CommandProcessor: Missing method '%s' on %s for command path: '%s'" % [method_name, target, " ".join(PackedStringArray(literals))])
	return Callable()
 
func _build_line(line: Array, callback: Callable, arg_value_maps: Dictionary) -> void:
	var current: CommandNode = tree.root
	for token in line:
		var text: String = String(token)
		var is_optional := text.begins_with("[") and text.ends_with("]")
		var clean := text.trim_prefix("[").trim_suffix("]")
 
		if is_optional:
			current.executes(callback)
 
		if clean.begins_with("<") and clean.ends_with(">"):
			current = _get_or_create_argument(current, clean, arg_value_maps)
		else:
			current = _get_or_create_literal(current, clean)
 
	current.executes(callback)
 
func _get_or_create_literal(parent: CommandNode, token_name: String) -> CommandNode:
	if not parent.children.has(token_name):
		parent.add_child_node(LiteralNode.new(token_name))
	return parent.children[token_name]
 
func _get_or_create_argument(parent: CommandNode, raw_token: String, arg_value_maps: Dictionary) -> CommandNode:
	var body := raw_token.substr(1, raw_token.length() - 2)
	var parts := body.split(":")
	var arg_name := parts[0].strip_edges()
 
	var arg_type := ArgumentNode.Type.STRING
	var suggestions: Array[String] = []
 
	if parts.size() == 2:
		var type_and_options := parts[1].split("|")
		arg_type = _parse_arg_type(type_and_options[0].strip_edges())
		if type_and_options.size() > 1:
			for option in type_and_options[1].split(","):
				var clean_option := option.strip_edges()
				if not clean_option.is_empty():
					suggestions.append(clean_option)
 
	if not parent.children.has(arg_name):
		var value_map: Dictionary = arg_value_maps.get(arg_name, {})
		parent.add_child_node(ArgumentNode.new(arg_name, arg_type, suggestions, value_map))
	return parent.children[arg_name]
 
func _parse_arg_type(type_str: String) -> ArgumentNode.Type:
	match type_str:
		"int":
			return ArgumentNode.Type.INT
		"float":
			return ArgumentNode.Type.FLOAT
		"any":
			return ArgumentNode.Type.ANY
		_:
			return ArgumentNode.Type.STRING
 
func _set_root_metadata(root_name: String, description: String, pattern: String) -> void:
	if tree.root.children.has(root_name):
		var root_node: CommandNode = tree.root.children[root_name]
		root_node.description = description
		root_node.usage = pattern

func execute(input_text: String) -> String:
	return tree.execute(input_text)

func get_suggestions(input_text: String) -> Array[String]:
	return tree.get_suggestions(input_text)

func process_command(text: String):
	var result := tree.execute(text)
	if not result.is_empty():
		console.add_message("[color=red]%s[/color]" % result)


func cmd_help(ctx: CommandContext) -> String:
	var target_name := ctx.get_string("command_name").to_lower()
	
	if not target_name.is_empty():
		if tree.root.children.has(target_name):
			var cmd: CommandNode = tree.root.children[target_name]
			if not cmd.usage.is_empty():
				console.add_message("[color=yellow]/%s[/color] - %s" % [cmd.name, cmd.usage])
		else:
			return "Command '%s' not found" % target_name
	else:
		for key in tree.root.children:
			var cmd: CommandNode = tree.root.children[key]
			if cmd.name == "help":
				continue
			console.add_message("[color=cyan]/%-10s[/color] - %s" % [cmd.name, cmd.description])
	
	return ""


## command syntax
## main_command { sub_command1 <name:type|option1, option2,...> | sub_command2 [<name:int>] }
## Example: time { set <time:any|dawn,morning,noon,afternoon,dusk,night> | speed <multiplier:float> }
## Symbols:
## name: required fixed word (like set), written without '<>'
## <name>: any string argument
## <name:type>: argument with specific type (flot, int)
## <name:string|option1,option2>: argument is a string with either one of the two options
## <name:any|option1,option1>: argument is either string with the specified option or a number (float or int)
## { command1 | command2 }: branching commands, split by '|', usage is either of the two
## [<name>]: [] makes it optional
## Right now, very space sensitive and lower-uppercase sensitive
## this one, if I want multiple functions
#func register_command_multiple(pattern: String, target: Object, description: String = ""):
	#var raw_tokens: Array = Array(Array(pattern.split(" ", false)), TYPE_STRING, "", null)
	#if raw_tokens.is_empty():
		#return
	#
	#var expanded_branches: Array = expand_branch(raw_tokens)
	#var root_cmd_name: String = raw_tokens[0]
	#
	#
	#for line in expanded_branches:
		#if line.is_empty(): # should not be happening, but still
			#continue
		#
		## To create the function name
		##
		#var literals: Array[String] = []
		#for token: String in line:
			#var clean = token.trim_prefix("[").trim_suffix("]")
			#if not (clean.begins_with("<") and clean.ends_with(">")):
				#literals.append(clean.to_lower())
		#var method_name := "cmd" + "_" + "_".join(literals)
		#
		#if target.has_method(method_name):
			#var callback := Callable(target, method_name)
			#register_branch_line(line, callback)
		#else:
			#push_error("CommandProcessor: Missing method '%s' on %s for command path: '%s'" % [method_name, target, " ".join(line)])
		#
	#if tree.root.children.has(root_cmd_name):
		#var root_node: CommandNode = tree.root.children[root_cmd_name]
		#root_node.description = description
		#root_node.usage = pattern
#
#func register_branch_line(line: Array, callback: Callable):
	#var current: CommandNode = tree.root
	#
	#for token: String in line:
		#var is_optional = token.begins_with("[") and token.ends_with("]")
		#var clean_token = token.trim_prefix("[").trim_suffix("]")
		#
		#if is_optional:
			#current.executes(callback)
		#
		#var is_arg = clean_token.begins_with("<") and clean_token.ends_with(">")
		#
		#if is_arg:
			#var raw_arg := clean_token.substr(1, clean_token.length()-2)
			#var arg_parts := raw_arg.split(":")
			#var arg_name := arg_parts[0].strip_edges()
			#var arg_type := ArgumentNode.Type.STRING
			#var suggestions: Array[String] = []
			#
			#if arg_parts.size() == 2: # [name] ":" [type|option1,option2]
				## [type] "|" [option1,option2]
				#var type_parts = arg_parts[1].split("|")
				#match type_parts[0].strip_edges():
					#"int":
						#arg_type = ArgumentNode.Type.INT
					#"float":
						#arg_type = ArgumentNode.Type.FLOAT
					#"any":
						#arg_type = ArgumentNode.Type.ANY
					#_:
						#arg_type = ArgumentNode.Type.STRING
				#
				#if type_parts.size() > 1:
					#var options_str = type_parts[1]
					#for option in options_str.split(","):
						#var clean_option = option.strip_edges()
						#if not clean_option.is_empty():
							#suggestions.append(option)
				#
			#if not current.children.has(arg_name):
				#var arg_node := ArgumentNode.new(arg_name, arg_type, suggestions)
				#current.add_child_node(arg_node)
			#current = current.children[arg_name]
		#else:
			#if not current.children.has(clean_token):
				#var lit_node := LiteralNode.new(clean_token)
				#current.add_child_node(lit_node)
			#current = current.children[clean_token]
	#
	#current.executes(callback)
#
#func register_command(pattern: String, callback: Callable, description: String = ""):
	#var raw_tokens: Array = Array(Array(pattern.split(" ", false)), TYPE_STRING, "", null)
	#if raw_tokens.is_empty():
		#return
	#
	#var expanded_branches: Array = expand_branch(raw_tokens)
	#var root_cmd_name: String = raw_tokens[0]
	#
	#for line in expanded_branches:
		#if line.is_empty(): # should not be happening, but still
			#continue
		#
		#var current: CommandNode = tree.root
		#
		#for token: String in line:
			#var is_optional = token.begins_with("[") and token.ends_with("]")
			#var clean_token = token.trim_prefix("[").trim_suffix("]")
			#
			#if is_optional:
				#current.executes(callback)
			#
			#var is_arg = clean_token.begins_with("<") and clean_token.ends_with(">")
			#
			#if is_arg:
				#var raw_arg := clean_token.substr(1, clean_token.length()-2)
				#var arg_parts := raw_arg.split(":")
				#var arg_name := arg_parts[0].strip_edges().trim_prefix("<").trim_suffix(">")
				#var arg_type := ArgumentNode.Type.STRING
				#var suggestions: Array[String] = []
				#
				#if arg_parts.size() == 2: # [name] ":" [type|option1,option2]
					## [type] "|" [option1,option2]
					#var type_parts = arg_parts[1].split("|")
					#match type_parts[0].strip_edges():
						#"int":
							#arg_type = ArgumentNode.Type.INT
						#"float":
							#arg_type = ArgumentNode.Type.FLOAT
						#"any":
							#arg_type = ArgumentNode.Type.ANY
						#_:
							#arg_type = ArgumentNode.Type.STRING
					#
					#if type_parts.size() > 1:
						#var options_str = type_parts[1]
						#for option in options_str.split(","):
							#var clean_option = option.strip_edges()
							#if not clean_option.is_empty():
								#suggestions.append(option)
					#
				#if not current.children.has(arg_name):
					#var arg_node := ArgumentNode.new(arg_name, arg_type, suggestions)
					#current.add_child_node(arg_node)
				#current = current.children[arg_name]
			#else:
				#if not current.children.has(clean_token):
					#var lit_node := LiteralNode.new(clean_token)
					#current.add_child_node(lit_node)
				#current = current.children[clean_token]
		#
		#current.executes(callback)
		#
	#if tree.root.children.has(root_cmd_name):
		#var root_node: CommandNode = tree.root.children[root_cmd_name]
		#root_node.description = description
		#root_node.usage = pattern
#
##Currently works with branches inside of other branches but not a branch after another one
#func expand_branch(tokens: Array) -> Array: # tokens: Array[String] -> Array[Array[String]]
	#if not tokens.has("{"):
		#return [tokens]
	#
	#var branches: Array = [] # Array[Array[String]]
	#var branch: Array = []
	#var has_branching: Array[bool] = [false]
	#var current_branch: int = 0
	#var first_bracket_idx: int = 0
	#var last_bracket_idx: int = 0
	#
	#var depth: int = 0
	#
	#for i in tokens.size():
		#var token = tokens[i]
		#if token == "{":
			#depth += 1
			#if depth == 1:
				#first_bracket_idx = i
				#continue
			#elif depth == 2:
				#has_branching[current_branch] = true
		#elif token == "|" and depth == 1:
			#branches.append(branch.duplicate())
			#branch.clear()
			#has_branching.append(false)
			#current_branch += 1
			#continue
		#elif token == "}":
			#depth -= 1
			#if depth == 0:
				#last_bracket_idx = i
				#branches.append(branch.duplicate())
				#branch.clear()
				#continue
		#
		#if depth == 0:
			#continue
		#
		#branch.append(token)
	#
	#var prefix := tokens.slice(0, first_bracket_idx)
	#var suffix := tokens.slice(last_bracket_idx + 1)
	#
	#var flattened_branches: Array = []
	#for i in branches.size():
		#if has_branching[i]:
			#var sub_expanded := expand_branch(branches[i])
			#flattened_branches.append_array(sub_expanded)
		#else:
			#flattened_branches.append(branches[i])
	#
	#var final_branches: Array = []
	#for b in flattened_branches:
		#var combined_branch: Array = []
		#combined_branch.append_array(prefix)
		#combined_branch.append_array(b)
		#combined_branch.append_array(suffix)
		#final_branches.append(combined_branch)
	#
	#return final_branches
