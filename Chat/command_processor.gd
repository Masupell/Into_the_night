class_name CommandProcessor
extends Node

class Command:
	var name: String
	var callback: Callable
	var description: String
	var usage: String
	var schema: Variant # Dictionary, Array or Callable
	
	func _init(_name: String, _callback: Callable, _description: String, _usage: String, _schema: Variant = null) -> void:
		name = _name
		callback = _callback
		description = _description
		usage = _usage
		schema = _schema

@export var console: CommandConsule
var registered_commands: Dictionary = {}

func _ready() -> void:
	console.processor = self
	console.command_submitted.connect(process_command)
	register_command("help", cmd_help, "Displays all available commands or info about a specific command.", "/help [command_name]")

func register_command(cmd_name: String, callback: Callable, description: String = "", usage: String = "", schema: Variant = null):
	registered_commands[cmd_name] = Command.new(cmd_name, callback, description, usage, schema)

func unregister_command(cmd_name: String):
	registered_commands.erase(cmd_name)

func get_suggestions(input_text: String) -> Array[String]:
	if not input_text.begins_with("/"):
		return []
	
	var has_trailing_space := input_text.ends_with(" ")
	var raw_tokens: Array[String] = Array(Array(input_text.substr(1).split(" ", false)), TYPE_STRING, "", null)
	
	# just typing '/', to show you all commands
	if raw_tokens.is_empty():
		var all_cmds: Array[String] = []
		for cmd_name in registered_commands:
			all_cmds.append("/" + cmd_name)
		all_cmds.sort()
		return all_cmds
	
	# typing root command (like /time)
	if raw_tokens.size() == 1 and not has_trailing_space:
		var prefix := raw_tokens[0].to_lower()
		var sub_matches: Array[String] = []
		for cmd_name in registered_commands:
			if cmd_name.to_lower().begins_with(prefix):
				sub_matches.append("/" + cmd_name)
		sub_matches.sort()
		return sub_matches
	
	var root_name := raw_tokens[0]
	var cmd: Command = null
	if registered_commands.has(root_name):
		cmd = registered_commands[root_name]
	else:
		for k in registered_commands:
			if k.to_lower() == root_name.to_lower():
				cmd = registered_commands[k]
				root_name = k
				break
	
	if cmd == null or cmd.schema == null:
		return []
	
	var active_prefix := ""
	var completed_args: Array[String] = []
	
	if has_trailing_space:
		for i in range(1, raw_tokens.size()):
			completed_args.append(raw_tokens[i])
	else:
		active_prefix = raw_tokens.back()
		for i in range(1, raw_tokens.size() - 1):
			completed_args.append(raw_tokens[i])
	
	var baseline := "/" + root_name
	for arg in completed_args:
		baseline += " " + arg
	baseline += " "
	
	var current_node: Variant = cmd.schema
	for arg in completed_args:
		if current_node is Dictionary:
			var matched_key := ""
			for key in current_node.keys():
				if str(key).to_lower() == arg.to_lower():
					matched_key = key
					break
			if matched_key != "":
				current_node = current_node[matched_key]
			else:
				current_node = null
				break
		else:
			current_node = null
			break
	
	if current_node == null:
		return []
	
	var raw_options: Array[String] = []
	if current_node is Dictionary:
		for key in current_node.keys():
			raw_options.append(str(key))
	elif current_node is Array:
		for item in current_node:
			raw_options.append(str(item))
	elif current_node is Callable:
		var dynamic_res = current_node.call(completed_args)
		if dynamic_res is Array:
			for item in dynamic_res:
				raw_options.append(str(item))
	
	var matches: Array[String] = []
	for option in raw_options:
		if option.to_lower().begins_with(active_prefix.to_lower()):
			matches.append(baseline + option)
	matches.sort()
	return matches

func process_command(text: String):
	if not text.begins_with("/"):
		return
	
	var parts = text.substr(1).split(" ", false)
	if parts.is_empty():
		return
	var cmd_name = parts[0]
	
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	
	if not registered_commands.has(cmd_name):
		console.add_message("[color=red]Unknown command: '%s'[/color]"%cmd_name)
		return
	
	var cmd: Command = registered_commands[cmd_name]
	var result = cmd.callback.call(args)
	
	if result is String and result != "":
		console.add_message("[color=red]Error: %s[/color]"%result)
		if cmd.usage != "":
			console.add_message("[color=gray]Usage: %s[/color]" % cmd.usage)


func cmd_help(args: Array[String]):
	if args.size() > 0:
		var target_name = args[0]
		if registered_commands.has(target_name):
			var cmd: Command = registered_commands[args[0]]
			console.add_message("[color=yellow]/%s[/color] - %s" % [cmd.name, cmd.description])
			if cmd.usage != "":
				console.add_message("[color=gray]Usage: %s[/color]" % cmd.usage)
		else:
			return "Command '/%s' not found." % target_name
	else:
		for key in registered_commands:
			var cmd: Command = registered_commands[key]
			if cmd.name == "help":
				continue
			console.add_message("[color=cyan]/%-10s[/color] - %s" % [cmd.name, cmd.description])
	return ""
