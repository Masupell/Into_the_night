class_name WorldCommands
extends RefCounted

var planet: Planet
var command_processor: CommandProcessor

var show_borders: bool = false
var show_lod: bool = false

func _init(processor: CommandProcessor, _planet: Planet) -> void:
	command_processor = processor
	planet = _planet
	register_all()

func register_all():
	command_processor.register_command("time", cmd_time, 
	"Sets local time or adjusts time speed.",
	"/time set <HH:MM or number or \n['Dawn', 'Morning', 'Noon', 'AfterNoon', 'Dusk', Night']> \nOr /time speed <multiplier>",
	{
		"set": ["Dawn", "Morning", "Noon", "AfterNoon", "Dusk", "Night"],
		"speed": []
	})
	
	command_processor.register_command("wireframe", cmd_wireframe,
	"Enables or disables wireframe view",
	"/wireframe <1 or 2> (1 for default no wireframe, 2 for wireframe)",
	["1", "2"])
	
	command_processor.register_command("camera", cmd_camera,
	"Switches between plane, freecam and debug cam",
	"/camera <plane or freecam/free or debug or <1 or 2 or 3>",
	["plane", "free", "freecam", "debug", "1", "2", "3"])
	
	command_processor.register_command("atmosphere", cmd_atmosphere,
	"Currently just show or hide", 
	"/atmosphere <show or hide>",
	["show", "hide"])
	
	command_processor.register_command("chunk", cmd_chunk,
	"Different things with the chunks, only for debug right now",
	"/chunk border <show or hide> or /chunk lod <show or hide>",
	{
		"border": ["show", "hide"],
		"lod": ["show", "hide"]
	})

func cmd_time(args: Array[String]) -> String:
	if args.size() < 2:
		return "Missing Arguments"
	var sub_command = args[0]
	var value_str = args[1]
	
	match sub_command:
		"set":
			var hours: float = 0.0
			if ":" in value_str:
				var time_parts = value_str.split(":")
				if time_parts.size() == 2 and time_parts[0].is_valid_int() and time_parts[1].is_valid_int():
					var h = time_parts[0].to_int()
					var m = time_parts[1].to_int()
					hours = h + (m/60.0)
				else:
					return "Invalid time format. Use HH:MM or a number."
			elif value_str.is_valid_float():
				hours = value_str.to_float()
			else:
				match value_str.to_lower():
					"dawn":
						hours = 5.0
					"morning":
						hours = 7.0
					"noon":
						hours = 12.0
					"afternoon":
						hours = 13.0
					"dusk":
						hours = 17.75
					"night":
						hours = 24.0
					_:
						return "Invalid Time. Use ['Dawn', 'Morning', 'Noon', 'AfterNoon', 'Dusk', Night']"
			planet.set_time_hours(hours)
			var h_int = int(hours)
			var m_int = int((hours - h_int) * 60.0)
			command_processor.console.add_message("[color=green]Time set to %02d:%02d[/color]" % [h_int, m_int])
			return ""
		"speed":
			if not value_str.is_valid_float():
				return "Speed multiplier must be a number"
			var speed_val = value_str.to_float()
			planet.set_time_speed(speed_val)
			command_processor.console.add_message("[color=green]Time speed multiplier set to %.1fx[/color]" % speed_val)
			return ""
		_:
			return "Unknown subcommand '%s'. Use 'set' or 'speed'." % sub_command

func cmd_wireframe(args: Array[String]) -> String:
	if args.is_empty():
		return "Missing Arguments"
	if args[0].is_valid_int():
		var value = args[0].to_int()
		if value == 1:
			if planet.get_viewport().debug_draw != Viewport.DEBUG_DRAW_DISABLED:
				planet.get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
				command_processor.console.add_message("[color=green]Wireframe mode disabled[/color]")
			return ""
		elif value == 2:
			if planet.get_viewport().debug_draw != Viewport.DEBUG_DRAW_WIREFRAME:
				planet.get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
				command_processor.console.add_message("[color=green]Wireframe mode enabled[/color]")
			return ""
		else:
			return "Only '1' or '2'"
	return "Invalid Number"

func cmd_camera(args: Array[String]) -> String:
	if args.is_empty():
		return "Missing Arguments"
	var value_str = args[0]
	if value_str.is_valid_int():
		match value_str.to_int():
			1:
				if planet.camera_mode != 1:
					planet.switch_to_plane()
					command_processor.console.add_message("[color=green]Switched to Plane View[/color]")
				return ""
			2:
				if planet.camera_mode != 2:
					planet.switch_to_free()
					command_processor.console.add_message("[color=green]Switched to free fly mode[/color]")
				return ""
			3:
				if planet.camera_mode != 3:
					planet.switch_to_free(true)
					command_processor.console.add_message("[color=green]Switched to debug[/color]")
				return ""
			_:
				return "Invalid Argument"
	else:
		match value_str.to_lower():
			"plane":
				if planet.camera_mode != 1:
					planet.switch_to_plane()
					command_processor.console.add_message("[color=green]Switched to Plane View[/color]")
				return ""
			"free", "freecam":
				if planet.camera_mode != 2:
					planet.switch_to_free()
					command_processor.console.add_message("[color=green]Switched to free fly mode[/color]")
				return ""
			"debug":
				if planet.camera_mode != 3:
					planet.switch_to_free(true)
					command_processor.console.add_message("[color=green]Switched to debug[/color]")
				return ""
			_:
				return "Invalid Argument"

func cmd_atmosphere(args: Array[String]) -> String:
	if args.is_empty():
		return "Missing Arguments"
	match args[0].to_lower():
		"show":
			planet.atmosphere.show()
			command_processor.console.add_message("[color=green]Atmosphere Shown[/color]")
			return ""
		"hide":
			planet.atmosphere.hide()
			command_processor.console.add_message("[color=green]Atmosphere Hidden[/color]")
			return ""
		_:
			return "Invalid Argument"

func cmd_chunk(args: Array[String]) -> String:
	if args.size() < 2:
		return "Missing Arguments"
	var sub_command = args[0]
	var value_str = args[1]
	
	match sub_command.to_lower():
		"border":
			match value_str.to_lower():
				"show":
					if !show_borders:
						show_borders = true
						RenderingServer.global_shader_parameter_set("show_borders", true)
						command_processor.console.add_message("[color=green]Borders Shown[/color]")
				"hide":
					if show_borders:
						show_borders = false
						RenderingServer.global_shader_parameter_set("show_borders", false)
						command_processor.console.add_message("[color=green]Borders Hidden[/color]")
				_:
					return "Invalid Argument: '%s'" % value_str
			return ""
		"lod":
			match value_str.to_lower():
				"show":
					if !show_lod:
						show_lod = true
						RenderingServer.global_shader_parameter_set("show_lod", true)
						command_processor.console.add_message("[color=green]Showing Lod[/color]")
				"hide":
					if show_lod:
						show_lod = false
						RenderingServer.global_shader_parameter_set("show_lod", false)
						command_processor.console.add_message("[color=green]Lod colors Hidden[/color]")
				_:
					return "Invalid Argument: '%s'" % value_str
			return ""
		_:
			return "Invalid Argument: '%s'" % sub_command
