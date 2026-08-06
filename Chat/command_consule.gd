class_name CommandConsule
extends CanvasLayer

signal console_toggled(is_open: bool)
signal command_submitted(raw_text: String)

const MAX_MESSAGES: int = 50

@export var message_stay_time: float = 5.0
@export var message_fade_time: float = 0.8

@onready var scroll_container: ScrollContainer = $Control/MarginContainer/VBoxContainer/ScrollContainer
@onready var message_container: VBoxContainer = $Control/MarginContainer/VBoxContainer/ScrollContainer/MessageLog
@onready var input_field: LineEdit = $Control/MarginContainer/VBoxContainer/InputField

var is_open: bool = false

func _ready() -> void:
	input_field.hide()
	input_field.text_submitted.connect(text_submitted)
	
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ENTER:
			if not is_open:
				open_console()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SLASH:
			if not is_open:
				open_console("/")
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open:
			close_console()
			get_viewport().set_input_as_handled()
	
	if is_open and event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var scroll_step = 30
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				scroll_container.scroll_vertical -= scroll_step
			else:
				scroll_container.scroll_vertical += scroll_step
			get_viewport().set_input_as_handled()

func open_console(initial_text: String = ""):
	is_open = true
	input_field.show()
	input_field.text = initial_text
	input_field.caret_column = input_field.text.length()
	input_field.grab_focus()
	
	for child in message_container.get_children():
		if child is Control:
			if child.has_meta("tween"):
				var active_tween: Tween = child.get_meta("tween")
				if active_tween and active_tween.is_valid():
					active_tween.kill()
			child.modulate.a = 1.0
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	console_toggled.emit(true)
	
	scroll_to_bottom()

func close_console():
	is_open = false
	input_field.clear()
	input_field.hide()
	input_field.release_focus()
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	console_toggled.emit(false)
	
	var current_time_sec = Time.get_ticks_msec() / 1000.0
	for child in message_container.get_children():
		if child is Control:
			schedule_message_fade(child, current_time_sec)

func add_message(text: String):
	while message_container.get_child_count() >= MAX_MESSAGES:
		var oldest = message_container.get_child(0)
		message_container.remove_child(oldest)
		oldest.queue_free()
	
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	
	var birth_time_sec = Time.get_ticks_msec() / 1000.0
	label.set_meta("birth_time", birth_time_sec)
	
	message_container.add_child(label)
	scroll_to_bottom()
	
	if not is_open:
		schedule_message_fade(label, birth_time_sec)

func schedule_message_fade(label: Control, current_time_sec: float):
	if label.has_meta("tween"):
		var old_tween: Tween = label.get_meta("tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()
	
	var birth_time: float = label.get_meta("birth_time", current_time_sec)
	var age: float = current_time_sec - birth_time
	var remaining_stay: float = max(0.0, message_stay_time-age)
	
	
	if remaining_stay > 0.0:
		var tween = create_tween()
		label.set_meta("tween", tween)
		tween.tween_interval(remaining_stay)
		tween.tween_property(label, "modulate:a", 0.0, message_fade_time)
	else:
		var remaining_fade: float = max(0.0, message_fade_time - (age-message_stay_time))
		if remaining_fade > 0.0:
			var tween = create_tween()
			label.set_meta("tween", tween)
			tween.tween_property(label, "modulate:a", 0.0, remaining_fade)
		else:
			label.modulate.a = 0.0

func text_submitted(new_text: String):
	var trimmed = new_text.strip_edges()
	if trimmed != "":
		add_message(trimmed)
		command_submitted.emit(trimmed)
	close_console()

func scroll_to_bottom():
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)
