@tool
extends Node2D
class_name LottieAnimationWrapper

# This is a wrapper script that will be replaced by the actual C++ implementation
# when the GDExtension is loaded. This allows the plugin to register the node type
# even if the native library is not yet compiled.

@export_file("*.json", "*.lottie") var animation_path: String = ""
@export var playing: bool = false
@export var autoplay: bool = false
@export var looping: bool = true
@export_range(0.0, 10.0, 0.01) var speed: float = 1.0
## Internal render size is managed by the native extension; keep the wrapper minimal.

var current_frame: float = 0.0
var total_frames: float = 0.0
var duration: float = 0.0

signal animation_finished
signal frame_changed(frame: float)
signal animation_loaded(success: bool)

func _ready():
	if autoplay and not animation_path.is_empty():
		play()

func play():
	playing = true

func stop():
	playing = false
	current_frame = 0.0

func pause():
	playing = false

func seek(frame: float):
	set_frame(frame)

func set_frame(frame: float):
	if total_frames > 0:
		current_frame = clamp(frame, 0.0, total_frames - 1)

func get_frame() -> float:
	return current_frame

func get_duration() -> float:
	return duration

func get_total_frames() -> float:
	return total_frames
