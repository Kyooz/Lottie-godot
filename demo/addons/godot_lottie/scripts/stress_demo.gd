extends Node2D

@onready var camera_2d: Camera2D = $Camera2D
@onready var lottie_template: LottieAnimation = $LottieAnimation
@onready var count_label: Label = $Count

var lotties: Array[LottieAnimation] = []

const ZOOM_STEP := 1.0
const ZOOM_MIN := 1.0
const ZOOM_MAX := 5.0

# Inspector-configurable options
@export var initial_spawn: int = 0
@export var spawn_batch_count: int = 4
@export var spawn_random_in_view: bool = true

func _ready() -> void:
	lotties.append(lottie_template)
	if is_instance_valid(count_label):
		# Make the label ignore mouse to avoid GUI picking cost
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Prefer polling via actions to avoid per-event script calls on mouse move.
	# Also enable accumulated input to collapse many motion/wheel events per frame.
	Input.set_use_accumulated_input(true)
	_init_actions()
	# Spawn a starting batch for quick stress tests
	_spawn_random_batch(initial_spawn)
	_update_label()

func _process(_delta: float) -> void:
	# Poll actions instead of reacting to every raw mouse event.
	if Input.is_action_just_pressed("spawn_lottie"):
		_spawn_lottie_at(get_global_mouse_position())
	if Input.is_action_just_pressed("spawn_batch"):
		_spawn_random_batch(spawn_batch_count)
	if Input.is_action_just_pressed("zoom_in"):
		_set_zoom(camera_2d.zoom.x * (1.0 + ZOOM_STEP))
	if Input.is_action_just_pressed("zoom_out"):
		_set_zoom(camera_2d.zoom.x * (1.0 - ZOOM_STEP))

func _set_zoom(value: float) -> void:
	var z := clamp(value, ZOOM_MIN, ZOOM_MAX)
	camera_2d.zoom = Vector2(z, z)

func _spawn_lottie_at(world_pos: Vector2) -> void:
	var node := LottieAnimation.new()
	node.animation_path = lottie_template.animation_path
	# Respect template autoplay/looping instead of forcing playback.
	node.autoplay = lottie_template.autoplay
	node.looping = lottie_template.looping
	node.playing = lottie_template.playing
	node.fit_box_size = lottie_template.fit_box_size
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(node)
	node.global_position = world_pos
	lotties.append(node)
	_update_label()

func _spawn_random_batch(n: int) -> void:
	if n <= 0:
		return
	var rect := _current_world_rect()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in n:
		var p := Vector2(
			rng.randf_range(rect.position.x, rect.position.x + rect.size.x),
			rng.randf_range(rect.position.y, rect.position.y + rect.size.y)
		) if spawn_random_in_view else get_global_mouse_position() + Vector2(rng.randi_range(-32, 32), rng.randi_range(-32, 32))
		_spawn_lottie_at(p)

func _update_label() -> void:
	if is_instance_valid(count_label):
		count_label.text = "Lotties: %d" % lotties.size()

func _init_actions() -> void:
	# Define actions at runtime if they don't exist (wheel + right click)
	if not InputMap.has_action("spawn_lottie"):
		InputMap.add_action("spawn_lottie")
		var ev_rmb := InputEventMouseButton.new()
		ev_rmb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("spawn_lottie", ev_rmb)
	if not InputMap.has_action("spawn_batch"):
		InputMap.add_action("spawn_batch")
		var ev_key := InputEventKey.new()
		ev_key.keycode = KEY_B
		InputMap.action_add_event("spawn_batch", ev_key)
	if not InputMap.has_action("zoom_in"):
		InputMap.add_action("zoom_in")
		var ev_wu := InputEventMouseButton.new()
		ev_wu.button_index = MOUSE_BUTTON_WHEEL_UP
		InputMap.action_add_event("zoom_in", ev_wu)
	if not InputMap.has_action("zoom_out"):
		InputMap.add_action("zoom_out")
		var ev_wd := InputEventMouseButton.new()
		ev_wd.button_index = MOUSE_BUTTON_WHEEL_DOWN
		InputMap.action_add_event("zoom_out", ev_wd)

func _current_world_rect() -> Rect2:
	# Approximate the visible world rect using camera zoom and viewport size.
	# world_half_extents ≈ (screen_size * 0.5) * zoom
	var vp_size := get_viewport_rect().size
	var half := vp_size * 0.5 * camera_2d.zoom
	var center := camera_2d.get_screen_center_position()
	return Rect2(center - half, half * 2.0)
