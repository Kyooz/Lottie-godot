@tool
extends VBoxContainer

var selected_node: Node = null
var updating: bool = false

# UI References
@onready var file_label = $AnimationInfo/FileLabel
@onready var duration_label = $AnimationInfo/DurationLabel
@onready var frames_label = $AnimationInfo/FramesLabel

@onready var play_button = $Controls/PlaybackButtons/PlayButton
@onready var pause_button = $Controls/PlaybackButtons/PauseButton
@onready var stop_button = $Controls/PlaybackButtons/StopButton

@onready var frame_label = $Controls/Timeline/FrameLabel
@onready var frame_slider = $Controls/Timeline/FrameSlider

@onready var speed_slider = $Controls/SpeedControl/SpeedSlider
@onready var speed_value = $Controls/SpeedControl/SpeedValue

@onready var current_state_label = $StateMachine/CurrentState
@onready var states_list = $StateMachine/StatesList
@onready var add_state_button = $StateMachine/StateButtons/AddStateButton
@onready var remove_state_button = $StateMachine/StateButtons/RemoveStateButton

@onready var parameters_list = $Parameters/ParametersList
@onready var add_param_button = $Parameters/ParameterButtons/AddParamButton
@onready var remove_param_button = $Parameters/ParameterButtons/RemoveParamButton

func _ready():
	# Connect signals
	play_button.pressed.connect(_on_play_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	
	frame_slider.value_changed.connect(_on_frame_slider_changed)
	speed_slider.value_changed.connect(_on_speed_slider_changed)
	
	add_state_button.pressed.connect(_on_add_state_pressed)
	remove_state_button.pressed.connect(_on_remove_state_pressed)
	
	add_param_button.pressed.connect(_on_add_param_pressed)
	remove_param_button.pressed.connect(_on_remove_param_pressed)
	
	# Update UI
	_update_ui()

func _process(_delta):
	if selected_node and is_instance_valid(selected_node):
		if not updating:
			_update_animation_info()

func set_selected_node(node: Node):
	# Disconnect previous node signals
	if selected_node and is_instance_valid(selected_node):
		if selected_node.has_signal("animation_loaded"):
			selected_node.animation_loaded.disconnect(_on_animation_loaded)
		if selected_node.has_signal("frame_changed"):
			selected_node.frame_changed.disconnect(_on_frame_changed)
	
	selected_node = node
	
	# Connect new node signals
	if selected_node and is_instance_valid(selected_node):
		if selected_node.has_signal("animation_loaded"):
			selected_node.animation_loaded.connect(_on_animation_loaded)
		if selected_node.has_signal("frame_changed"):
			selected_node.frame_changed.connect(_on_frame_changed)
	
	_update_ui()

func _update_ui():
	var has_node = selected_node != null and is_instance_valid(selected_node)
	
	# Enable/disable controls
	play_button.disabled = not has_node
	pause_button.disabled = not has_node
	stop_button.disabled = not has_node
	frame_slider.editable = has_node
	speed_slider.editable = has_node
	
	if has_node:
		_update_animation_info()
	else:
		file_label.text = "File: None"
		duration_label.text = "Duration: 0.0s"
		frames_label.text = "Frames: 0"
		frame_label.text = "Frame: 0 / 0"

func _update_animation_info():
	if not selected_node or not is_instance_valid(selected_node):
		return
	
	updating = true
	
	# Update file info
	if selected_node.has_method("get_animation_path"):
		var path = selected_node.get_animation_path()
		file_label.text = "File: " + (path.get_file() if not path.is_empty() else "None")
	
	# Update duration and frames
	if selected_node.has_method("get_duration"):
		var duration = selected_node.get_duration()
		duration_label.text = "Duration: %.2fs" % duration
	
	if selected_node.has_method("get_total_frames"):
		var total = selected_node.get_total_frames()
		frames_label.text = "Frames: %d" % total
		frame_slider.max_value = max(0, total - 1)
	
	# Update current frame
	if selected_node.has_method("get_frame"):
		var current = selected_node.get_frame()
		var total = selected_node.get_total_frames() if selected_node.has_method("get_total_frames") else 0
		frame_label.text = "Frame: %d / %d" % [int(current), int(total)]
		frame_slider.value = current
	
	# Update speed
	if selected_node.has_method("get_speed"):
		var speed = selected_node.get_speed()
		speed_slider.value = speed
		speed_value.text = "%.1fx" % speed
	
	updating = false

func _on_play_pressed():
	if selected_node and selected_node.has_method("play"):
		selected_node.play()

func _on_pause_pressed():
	if selected_node and selected_node.has_method("pause"):
		selected_node.pause()

func _on_stop_pressed():
	if selected_node and selected_node.has_method("stop"):
		selected_node.stop()

func _on_frame_slider_changed(value: float):
	if updating:
		return
	
	if selected_node and selected_node.has_method("set_frame"):
		selected_node.set_frame(value)

func _on_speed_slider_changed(value: float):
	if updating:
		return
	
	if selected_node and selected_node.has_method("set_speed"):
		selected_node.set_speed(value)
		speed_value.text = "%.1fx" % value

func _on_animation_loaded(_success: bool):
	_update_ui()

func _on_frame_changed(_frame: float):
	if not updating:
		_update_animation_info()

func _on_add_state_pressed():
	# TODO: Open dialog to create new state
	print("Add state functionality - to be implemented")

func _on_remove_state_pressed():
	# TODO: Remove selected state
	print("Remove state functionality - to be implemented")

func _on_add_param_pressed():
	# TODO: Open dialog to add parameter
	print("Add parameter functionality - to be implemented")

func _on_remove_param_pressed():
	# TODO: Remove selected parameter
	print("Remove parameter functionality - to be implemented")
