class_name CommandProcessor
extends Node

class Command:
	var name: String
	var callback: Callable
	var description: String
	var usage: String
	
	func _init(_name: String, _callback: Callable, _description: String, _usage: String) -> void:
		name = _name
		callback = _callback
		description = _description
		usage = _usage

@onready var console = $".."

var registered_commands: Dictionary = {}
func _ready() -> void:
	console.command_submitted.connect(process_command)
	register_command("help", cmd_help, "Displays all available commands or info about a specific command.", "/help [command_name]")

func register_command(cmd_name: String, callback: Callable, description: String = "", usage: String = ""):
	registered_commands[cmd_name] = Command.new(cmd_name, callback, description, usage)

func unregister_command(cmd_name: String):
	registered_commands.erase(cmd_name)

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
