class_name FligthHUD
extends CanvasLayer

@onready var motor_power_label: Label = $Control/MarginContainer/VBoxContainer/MotorPowerLabel
@onready var speed_label: Label = $Control/MarginContainer/VBoxContainer/SpeedLabel
#AMSL = Above Mean Sea Level
@onready var altitude_label: Label = $Control/MarginContainer/VBoxContainer/AltitudeLabel
#AGL = Above Ground Level
@onready var agl_label: Label = $Control/MarginContainer/VBoxContainer/AGLLabel
@onready var pitch_roll_label: Label = $Control/MarginContainer/VBoxContainer/PitchRollLabel

func update_metrics(power: float, speed_ms: float, altitude_amsl: float, altitude_agl: float, pitch_deg: float, roll_deg: float):
	var speed_kmh = speed_ms * 3.6
	
	motor_power_label.text = "Engine: %3d%%" % [power*100.0]
	speed_label.text = "Speed: %3dkm/h (%dm/s)" % [speed_kmh, speed_ms]
	altitude_label.text = "Altitude (AMSL): %3dm" % [max(0.0, altitude_amsl)] # Not exactly sealevel, because the water is a little higher still, but fine for now
	
	if altitude_agl >= 0.0:
		agl_label.text = "Altitude (AGL): %3dm" % [max(0.0, altitude_agl)]
	else:
		agl_label.text = "Altitude (AGL): ---" # Raycast not touching anything
	
	var pitch_sign = "+" if pitch_deg > 0 else ""
	var roll_sign = "+" if roll_deg > 0 else ""
	
	pitch_roll_label.text = "Pitch: %s%.1f° -- Roll: %s%.1f°" % [pitch_sign, pitch_deg, roll_sign, roll_deg]
