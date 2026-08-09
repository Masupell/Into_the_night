class_name CommandProcessor
extends Node

@export var console: CommandConsule
var tree: CommandTree = CommandTree.new()

func _ready() -> void:
	console.processor = self
	console.command_submitted.connect(process_command)
	register_command("help", cmd_help, "Displays all available commands.")
	register_command("help <command_name>", cmd_help, "Displays info about a specific command.")

# command syntax:
# main_command { sub_command1 <name:type|option1, option2,...> | sub_command2 [<name:int>] }
# Example: time { set <time:any|dawn,morning,noon,afternoon,dusk,night> | speed <multiplier:float> }
# Symbols:
# name: required fixed word (like set), written without '<>'
# <name>: any string argument
# <name:type>: argument with specific type (flot, int)
# <name:string|option1,option2>: argument is a string with either one of the two options
# <name:any|option1,option1>: argument is either string with the specified option or a number (float or int)
# { command1 | command2 }: branching commands, split by '|', usage is either of the two
# [<name>]: [] makes it optional
func register_command(pattern: String, callback: Callable, description: String = ""):
	pass

#func register_command(pattern: String, callback: Callable, description: String = "", suggestions: Array[String] = []):
	#var tokens := pattern.split(" ", false)
	#if tokens.is_empty():
		#return
	#
	#var current: CommandNode = tree.root
	#var root_cmd_name := tokens[0].to_lower()
	#
	#for token in tokens:
		#var is_arg := token.begins_with("<") and token.ends_with(">")
		#if is_arg:
			## An Argument (<name> or <value:1> for example (<int:1>, <float:1.0>, (value>))
			#var raw_arg := token.substr(1, token.length()-2)
			#var arg_parts := raw_arg.split(":")
			#var arg_name := arg_parts[0]
			#var arg_type := ArgumentNode.Type.STRING
			#
			#if arg_parts.size() > 1:
				#match arg_parts[1].to_lower():
					#"int":
						#arg_type = ArgumentNode.Type.INT
					#"float":
						#arg_type = ArgumentNode.Type.FLOAT
					#_:
						#arg_type = ArgumentNode.Type.STRING
			#
			#var node_key := arg_name.to_lower()
			#if not current.children.has(node_key):
				#var arg_node := ArgumentNode.new(arg_name, arg_type, suggestions)
				#current.add_child_node(arg_node)
			#current = current.children[node_key]
		#else:
			#var node_key := token.to_lower()
			#if not current.children.has(node_key):
				#var lit_node := LiteralNode.new(token)
				#current.add_child_node(lit_node)
			#current = current.children[node_key]
	#
	#current.executes(callback)
	#
	#if tree.root.children.has(root_cmd_name):
		#var root_node: CommandNode = tree.root.children[root_cmd_name]
		#root_node.description = description
		#root_node.usage = pattern

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
				console.add_message("[color=yellow]/%s[/color] - %s:" % [cmd.name, cmd.usage])
		else:
			return "Command '%s' not found" % target_name
	else:
		for key in tree.root.children:
			var cmd: CommandNode = tree.root.children[key]
			if cmd.name == "help":
				continue
			console.add_message("[color=cyan]/%-10s[/color] - %s" % [cmd.name, cmd.description])
	
	return ""
