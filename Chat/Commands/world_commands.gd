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
	var time_command = "time { set <time:any|dawn,morning,noon,afternoon,dusk,night> | speed <multiplier:float> }"
	command_processor.register_command_multiple(time_command, self, "Sets local time or adjusts time speed.",
	{
		"time": {
			"dawn": 5.0,
			"morning": 7.0,
			"noon": 12.0,
			"afternoon": 13.0,
			"dusk": 17.75,
			"night": 24.0,
		}
	})
	
	var camera_command = "camera <mode:any|plane,free,debug>"
	command_processor.register_command(camera_command, cmd_camera, "Switches between plane, freecam and debug cam",
	{
		"mode":
			{
				"plane": 1,
				"free": 2,
				"debug": 3
			}
	})
	
	#"/chunk border <show or hide> or /chunk lod <show or hide>",
	var chunk_command = "chunk { border <visible:any|show,hide> | lod <visible:any:show,hide> }" # 1 for visible, 0 for hidden
	command_processor.register_command_multiple(chunk_command, self, "Different things with the chunks, only for debug right now",
	{
		"visible":
			{
				"show": 1,
				"hide": 2
			}
	})
	
	var atmosphere_command = "atmosphere <visible:any|show,hide>"
	command_processor.register_command(atmosphere_command, cmd_atmosphere, "Currently just show or hide",
	{
		"visible":
			{
				"show": 1,
				"hide": 2
			}
	})
	
	var wireframe_toggle_command = "wireframe <visible:any|show,hide>"
	command_processor.register_command(wireframe_toggle_command, cmd_wireframe, "Currently just show or hide",
	{
		"visible":
			{
				"show": 1,
				"hide": 2
			}
	})


# In match statements, the _: branch will never trigger, because it gets evaluated before that

func cmd_time_set(ctx: CommandContext) -> String:
	var value = ctx.get_argument("time")
	var hours: float

	if value is float:
		hours = value
	else:
		var text: String = value
		if ":" in text:
			var parts := text.split(":")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				hours = parts[0].to_int() + parts[1].to_int() / 60.0
			else:
				return "Invalid time format. Use HH:MM or a number."
		else:
			hours = text.to_float()

	planet.set_time_hours(hours)
	var h_int := int(hours)
	var m_int := int((hours - h_int) * 60.0)
	command_processor.console.add_message("[color=green]Time set to %02d:%02d[/color]" % [h_int, m_int])
	return ""

func cmd_time_speed(ctx: CommandContext) -> String:
	var speed := ctx.get_float("multiplier")
	planet.set_time_speed(speed)
	command_processor.console.add_message("[color=green]Time speed multiplier set to %.1fx[/color]" % speed)
	return ""

func cmd_camera(context: CommandContext) -> String:
	var value := context.get_int("mode")
	
	match value:
		1:
			if planet.camera_mode != 1:
				planet.switch_to_plane()
				command_processor.console.add_message("[color=green]Switched to Plane View[/color]")
		2:
			if planet.camera_mode != 2:
				planet.switch_to_free()
				command_processor.console.add_message("[color=green]Switched to free fly mode[/color]")
		3:
			if planet.camera_mode != 3:
				planet.switch_to_free(true)
				command_processor.console.add_message("[color=green]Switched to debug[/color]")
		_:
			return "Invalid Argument. Expected 1/plane, 2/free, or 3/debug."
	return ""

func cmd_chunk_border(context: CommandContext) -> String:
	var value := context.get_int("visible")
	
	match value:
		1:
			if !show_borders:
						show_borders = true
						RenderingServer.global_shader_parameter_set("show_borders", true)
						command_processor.console.add_message("[color=green]Borders Shown[/color]")
		2:
			if show_borders:
						show_borders = false
						RenderingServer.global_shader_parameter_set("show_borders", false)
						command_processor.console.add_message("[color=green]Borders Hidden[/color]")
		_: 
			return "Invalid Argument '%s', Only 1/show or 2/hide is permitted" % context.get_string("visible")
	return ""

func cmd_chunk_lod(context: CommandContext) -> String:
	var value := context.get_int("visible")
	
	match value:
		1:
			if !show_borders:
						show_borders = true
						RenderingServer.global_shader_parameter_set("show_lod", true)
						command_processor.console.add_message("[color=green]Showing Lod[/color]")
		2:
			if show_borders:
						show_borders = false
						RenderingServer.global_shader_parameter_set("show_lod", false)
						command_processor.console.add_message("[color=green]Lod colors Hidden[/color]")
		_: 
			return "Invalid Argument '%s', Only 1/show or 2/hide is permitted" % context.get_string("visible")
	return ""

func cmd_atmosphere(ctx: CommandContext) -> String:
	var value := ctx.get_int("visible")
	
	match value:
		1:
			planet.atmosphere.show()
			command_processor.console.add_message("[color=green]Atmosphere Shown[/color]")
		2:
			planet.atmosphere.hide()
			command_processor.console.add_message("[color=green]Atmosphere Hidden[/color]")
		_:
			return "Invalid Argument"
	return ""

func cmd_wireframe(ctx: CommandContext) -> String:
	var value := ctx.get_int("visible")
	
	match value:
		1:
			if planet.get_viewport().debug_draw != Viewport.DEBUG_DRAW_WIREFRAME:
				planet.get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
				command_processor.console.add_message("[color=green]Wireframe mode enabled[/color]")
		2:
			if planet.get_viewport().debug_draw != Viewport.DEBUG_DRAW_DISABLED:
				planet.get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
				command_processor.console.add_message("[color=green]Wireframe mode disabled[/color]")
		_:
			return "Invalid Argument"
	return ""
