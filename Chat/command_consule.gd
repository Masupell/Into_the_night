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

var processor: CommandProcessor

var suggestion_panel: PanelContainer
var suggestion_label: RichTextLabel
var current_suggestions: Array[String] = []
var suggestion_index: int = -1
var base_prefix: String = ""
var is_completing: bool = false

var command_history: Array[String] = []
var history_index: int = -1
var draft_text: String = ""

var suggestion_applied := false

func _ready() -> void:
	input_field.hide()
	input_field.text_submitted.connect(text_submitted)
	input_field.text_changed.connect(text_changed)
	
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	setup_suggestion_overlay()

func setup_suggestion_overlay():
	var wrapper := Control.new()
	wrapper.custom_minimum_size.y = 0
	input_field.get_parent().add_child(wrapper)
	input_field.get_parent().move_child(wrapper, input_field.get_index())
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	
	suggestion_panel = PanelContainer.new()
	suggestion_panel.add_theme_stylebox_override("panel", style)
	suggestion_panel.anchor_left = 0.0
	suggestion_panel.anchor_right = 1.0
	suggestion_panel.anchor_top = 1.0
	suggestion_panel.anchor_bottom = 1.0
	suggestion_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	suggestion_panel.hide()
	wrapper.add_child(suggestion_panel)
	
	suggestion_label = RichTextLabel.new()
	suggestion_label.bbcode_enabled = true
	suggestion_label.fit_content = true
	suggestion_label.scroll_active = false
	suggestion_panel.add_child(suggestion_label)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP and is_open:
			if !current_suggestions.is_empty():
				navigate_suggestions(-1)
			else:
				navigate_history(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN and is_open:
			if !current_suggestions.is_empty():
				navigate_suggestions(1)
			else:
				navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif not event.is_echo():
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
			elif event.keycode == KEY_TAB and is_open:
				handle_tab_completion()
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
	history_index = -1
	draft_text = ""
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
	text_changed(initial_text)

func close_console():
	is_open = false
	input_field.clear()
	input_field.hide()
	input_field.release_focus()
	
	history_index = -1
	draft_text = ""
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	console_toggled.emit(false)
	
	var current_time_sec = Time.get_ticks_msec() / 1000.0
	for child in message_container.get_children():
		if child is Control:
			schedule_message_fade(child, current_time_sec)

func navigate_history(direction: int):
	if command_history.is_empty():
		return
	if history_index == -1 and direction == 1:
		draft_text = input_field.text
	
	var new_index = history_index + direction
	new_index = clamp(new_index, -1, command_history.size() - 1)
	
	if new_index == history_index:
		return
	history_index = new_index
	
	if history_index == -1:
		input_field.text = draft_text
	else:
		input_field.text = command_history[command_history.size() - 1 - history_index]
	input_field.caret_column = input_field.text.length()

func navigate_suggestions(direction: int):
	suggestion_index += direction
	
	if suggestion_index < 0:
		suggestion_index = current_suggestions.size() - 1
	elif suggestion_index >= current_suggestions.size():
		suggestion_index = 0
	
	suggestion_applied = false
	update_suggestion_ui()

func text_changed(new_text: String):
	if is_completing:
		return
	if !processor or !is_open:
		clear_suggestions()
		return
	base_prefix = new_text
	current_suggestions = processor.get_suggestions(new_text)
	suggestion_index = -1
	suggestion_applied = false
	update_suggestion_ui()

func handle_tab_completion():
	if current_suggestions.is_empty():
		return
	
	if suggestion_index == -1:
		suggestion_index = 0
	elif suggestion_applied:
		suggestion_index = (suggestion_index + 1) % current_suggestions.size()
	
	is_completing = true
	
	var selected_cmd = current_suggestions[suggestion_index]
	input_field.text = selected_cmd
	input_field.caret_column = selected_cmd.length()
	
	is_completing = false
	suggestion_applied = true
	
	update_suggestion_ui()

func update_suggestion_ui():
	if current_suggestions.is_empty():
		clear_suggestions()
		return
	var suggestion_text: Array[String] = []
	for i in range(current_suggestions.size()):
		var cmd = current_suggestions[i]
		if i == suggestion_index:
			suggestion_text.append("[color=yellow]%s[/color]\n" % cmd)
		else:
			suggestion_text.append("[color=gray]%s[/color]\n" % cmd)
	
	suggestion_label.text = "".join(suggestion_text)
	suggestion_panel.show()

func clear_suggestions():
	current_suggestions.clear()
	suggestion_index = -1
	if suggestion_label:
		suggestion_label.text = ""
		suggestion_panel.hide()

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
		if command_history.is_empty() or command_history.back() != trimmed:
			command_history.append(trimmed)
		add_message(trimmed)
		command_submitted.emit(trimmed)
	close_console()

func scroll_to_bottom():
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)
