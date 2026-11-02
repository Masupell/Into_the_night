class_name WorldCommands
extends RefCounted

var planet: Planet
var command_processor: CommandProcessor

var show_borders: bool = false
var show_lod: bool = false

const VISIBILITY_MAP := {
	"show": 1,
	"hide": 2
}

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

	var plane_command = "plane { here | position <latitude:coord|~> <longitude:coord|~> [<height:coord|~>] }"
	command_processor.register_command_multiple(plane_command, self, "Puts the plane in front of the current camera (level, standing still), or at a latitude, longitude and height above sea level. ~ is the plane's current value, ~5 relative to it")

	var tp_command = "tp <latitude:coord|~> <longitude:coord|~> [<height:coord|~>]"
	command_processor.register_command(tp_command, cmd_tp, "Teleports to latitude, longitude (degrees) and height above sea level (meters). ~ is the current value, ~5 relative to it, without height it stays the same")

	var chunk_command = "chunk { border <visible:any|show,hide> | lod <visible:any|show,hide> }" # 1 for visible, 0 for hidden
	command_processor.register_command_multiple(chunk_command, self, "Different things with the chunks, only for debug right now",
	{
		"visible": VISIBILITY_MAP
	})

	var atmosphere_command = "atmosphere <visible:any|show,hide>"
	command_processor.register_command(atmosphere_command, cmd_atmosphere, "Currently just show or hide",
	{
		"visible": VISIBILITY_MAP
	})

	var wireframe_toggle_command = "wireframe <visible:any|show,hide>"
	command_processor.register_command(wireframe_toggle_command, cmd_wireframe, "Currently just show or hide",
	{
		"visible": VISIBILITY_MAP
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

# Returns the target position in planet space, or an error text
func coordinates_from(context: CommandContext, current: Vector3) -> Variant:
	var latitude := context.get_coordinate("latitude", current.x)
	var longitude := wrapf(context.get_coordinate("longitude", current.y), -180.0, 180.0)
	var height := context.get_coordinate("height", current.z)
	if latitude < -90.0 or latitude > 90.0:
		return "Latitude has to be between -90 and 90, got %.4f" % latitude
	return planet.from_lat_lon_height(latitude, longitude, height)

func cmd_tp(context: CommandContext) -> String:
	var target = coordinates_from(context, planet.to_lat_lon_height(planet.controlled_position()))
	if target is String:
		return target
	planet.teleport_controlled(target)
	var c := planet.to_lat_lon_height(target)
	command_processor.console.add_message("[color=green]Teleported to %.4f, %.4f, %.0f m[/color]" % [c.x, c.y, c.z])
	return ""

func cmd_plane_position(context: CommandContext) -> String:
	var target = coordinates_from(context, planet.to_lat_lon_height(planet.plane_position()))
	if target is String:
		return target
	planet.teleport_plane(target)
	var c := planet.to_lat_lon_height(target)
	command_processor.console.add_message("[color=green]Plane moved to %.4f, %.4f, %.0f m[/color]" % [c.x, c.y, c.z])
	return ""

func cmd_plane_here(_context: CommandContext) -> String:
	if planet.camera_mode == 1:
		return "Already looking at the plane"
	planet.move_plane_to_view()
	command_processor.console.add_message("[color=green]Plane moved here[/color]")
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
