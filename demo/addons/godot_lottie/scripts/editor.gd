extends Node

# Professional Runtime Lottie Scene Editor
# Full-featured editor for creating and managing LottieAnimation nodes
# Features: Drag & drop, property editing, scene management, visual feedback

@onready var root: Node = get_parent()
@onready var assets: Node = root.get_node("Assets")

# UI Components
var _ui: CanvasLayer
var _toolbar: HBoxContainer
var _prop_panel: VBoxContainer
var _prop_panel_container: PanelContainer  # Store reference to toggle visibility
var _scene_combo: OptionButton
var _file_dialog: FileDialog
var _save_dialog: FileDialog
var _save_confirm_popup: AcceptDialog
var _import_path_label: Label
var _save_path_display: Label
var _status_bar: HBoxContainer
var _camera: Camera2D
var _overlay: Control

# Selection & Interaction
var _selected: Node2D = null
var _dragging := false
var _resizing := false
var _resize_handle := -1  # 0=TL, 1=TR, 2=BR, 3=BL
var _resize_start_mouse := Vector2.ZERO
var _resize_start_size := Vector2i.ZERO
var _drag_offset := Vector2.ZERO
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO
var _show_properties := false
var _last_mouse_screen := Vector2.ZERO
var _hover_node: Node2D = null
var _clipboard: Node2D = null
var _panning := false  # Space key camera pan
var _pan_start_mouse := Vector2.ZERO
var _pan_start_camera := Vector2.ZERO
var _ignore_scene_change := false  # Flag to prevent load when setting selection programmatically

# Smooth zoom/pan targets
var _zoom_target := Vector2.ONE
var _pos_target := Vector2.ZERO
var _zoom_from := Vector2.ONE
var _zoom_to := Vector2.ONE
var _zoom_anim := 0.0
var _zoom_focus_screen := Vector2.ZERO
var _zoom_focus_world := Vector2.ZERO  # restored for focus lock
const ZOOM_MIN := 0.1
const ZOOM_MAX := 5.0
# Discrete zoom percentages used when snapping (Godot-like): 33.3%, 50%, 100%, 200%
const ZOOM_LEVELS := [33.333333, 50.0, 100.0, 200.0]
const ZOOM_STEP_IN := 0.9   # wheel up (zoom in): scale zoom vector by 0.9
const ZOOM_STEP_OUT := 1.1  # wheel down (zoom out): scale zoom vector by 1.1
const ZOOM_ANIM_TIME := 0.12
const ZOOM_LERP_SPEED := 14.0
const PAN_LERP_SPEED := 18.0

# User-selected paths
var _import_base_path := ""
var _save_base_path := ""

# Editor Settings
const SELECTION_COLOR := Color(0.3, 0.7, 1.0, 0.8)
const HOVER_COLOR := Color(1.0, 1.0, 0.3, 0.6)

# Paths
const SCENES_DIR := "res://addons/scenes"
const USER_SCENES_DIR := "user://scenes"
const CONFIG_FILE := "user://lottie_editor_config.json"

# Theme colors - Modern minimalist
const THEME_DARK_BG := Color(0.12, 0.12, 0.14)
const THEME_PANEL_BG := Color(0.16, 0.16, 0.18)
const THEME_ACCENT := Color(0.4, 0.65, 1.0)
const THEME_TEXT := Color(0.92, 0.92, 0.94)

func _ready() -> void:
	_ensure_dirs()
	_load_config()
	_make_camera()
	_build_ui()
	_refresh_scene_list()
	# Auto-carregar a primeira cena disponível ao abrir o editor
	if _scene_combo and _scene_combo.item_count > 0:
		_scene_combo.selected = 0
		_load_selected_scene()
	else:
		# Sem cenas: manter estado atual (rendering demo/blank) até o usuário criar/importar
		_update_status("No scenes found. Use New/Import to start.")
	set_process(true)

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(USER_SCENES_DIR)

# Resolve a directory hint (res://, user:// or absolute) to a valid project path.
func _resolve_dir(p: String) -> String:
	if p == null or p == "":
		return ""
	var path := p
	# Convert absolute OS path to project-relative if inside project
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = ProjectSettings.localize_path(path)
	# Verify directory exists or can be opened
	return path if DirAccess.open(path) else ""

func _get_scene_root_dir() -> String:
	var root := _resolve_dir(_save_base_path)
	if root == "":
		# Prefer user:// if writable
		var user_root := _resolve_dir(USER_SCENES_DIR)
		if user_root != "":
			return user_root
		var res_root := _resolve_dir(SCENES_DIR)
		if res_root != "":
			return res_root
	return SCENES_DIR

func _load_config() -> void:
	if FileAccess.file_exists(CONFIG_FILE):
		var file = FileAccess.open(CONFIG_FILE, FileAccess.READ)
		if file:
			var json = JSON.new()
			var parse_result = json.parse(file.get_as_text())
			file.close()
			if parse_result == OK:
				var config = json.data
				if config.has("import_base_path"):
					_import_base_path = config["import_base_path"]
				if config.has("save_base_path"):
					_save_base_path = config["save_base_path"]
				if config.has("custom_scenes_dir"):
					var cdir = _resolve_dir(config["custom_scenes_dir"])
					if cdir != "":
						_save_base_path = cdir  # treat as save base override

func _save_config() -> void:
	var config = {
		"import_base_path": _import_base_path,
		"save_base_path": _save_base_path
	}
	var file = FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(config, "\t"))
		file.close()
		# Config saved silently


func _make_camera() -> void:
	_camera = Camera2D.new()
	# Start centered anchor for intuitive zoom pivot (position is world center of viewport)
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2.ZERO
	add_child(_camera)
	_camera.enabled = true
	_camera.call_deferred("make_current")
	_zoom_target = _camera.zoom
	_pos_target = _camera.position
	
	# Create overlay in CanvasLayer for screen-space drawing (independent of camera)
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "OverlayLayer"
	overlay_layer.layer = 99  # Below UI (100) but above game
	add_child(overlay_layer)
	
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_layer.add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)

func _screen_to_world(p: Vector2) -> Vector2:
	# With center anchor: world = camera.position + (screen - viewport_center)*zoom
	var vs = get_viewport().get_visible_rect().size
	return _camera.position + ((p - vs * 0.5) * _camera.zoom)

func _world_to_screen(p: Vector2) -> Vector2:
	var vs = get_viewport().get_visible_rect().size
	return ((p - _camera.position) / _camera.zoom) + vs * 0.5

func _apply_focus(lock_mouse: Vector2, old_zoom: float, new_zoom: float) -> void:
	# Compute world focus BEFORE changing zoom then reposition to keep it stable.
	var world_focus := _camera.position + (lock_mouse * old_zoom)
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_camera.position = world_focus - (lock_mouse * new_zoom)

func _snap_camera_to_pixel_grid() -> void:
	# Align camera position to pixel grid for crisp rendering at integer zoom levels.
	var s := _camera.zoom.x
	if s <= 0.0:
		return
	_camera.position.x = round(_camera.position.x / s) * s
	_camera.position.y = round(_camera.position.y / s) * s

func _apply_texture_filter_for_assets(use_nearest: bool) -> void:
	# Filtering control disabled per request; keep stub for potential future toggle.
	var percent_dbg := int(round(100.0 / _camera.zoom.x))
	return

func _is_mouse_over_ui(mouse_pos: Vector2) -> bool:
	# Check if mouse is over toolbar (top 48px)
	if mouse_pos.y < 48:
		return true
	# Check if mouse is over status bar (bottom 32px)
	var viewport_height = get_viewport().get_visible_rect().size.y
	if mouse_pos.y > viewport_height - 32:
		return true
	# Check if mouse is over right panel (rightmost 320px)
	var viewport_width = get_viewport().get_visible_rect().size.x
	if mouse_pos.x > viewport_width - 320:
		return true
	return false

func _get_next_zoom_level(current_percent: float, zoom_in: bool) -> float:
	# Use ZOOM_LEVELS; pick the next defined level strictly (not closest).
	var levels: Array = ZOOM_LEVELS
	var idx := 0
	# Find insertion index (first level >= current)
	for i in range(levels.size()):
		if levels[i] >= current_percent:
			idx = i
			break
		idx = i  # if all levels < current, idx ends at last
	# If current is nearly equal to a level, treat as exact
	if abs(levels[idx] - current_percent) < 0.05:
		if zoom_in:
			return levels[max(idx - 1, 0)]
		else:
			return levels[min(idx + 1, levels.size() - 1)]
	else:
		# current lies between levels[idx-1] and levels[idx]
		if zoom_in:
			return levels[max(idx - 1, 0)]
		else:
			return levels[min(idx, levels.size() - 1)]

func _is_discrete_level(percent: float) -> bool:
	for L in ZOOM_LEVELS:
		if abs(percent - L) < 0.05:
			return true
	return false

func _format_percent(percent: float) -> String:
	# Show integer when very close, else one decimal (e.g., 33.3)
	if abs(percent - round(percent)) < 0.05:
		return "%d%%" % int(round(percent))
	else:
		return "%.1f%%" % (round(percent * 10.0) / 10.0)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 100
	add_child(_ui)
	
	# Professional toolbar
	var top = PanelContainer.new()
	_ui.add_child(top)
	_apply_panel_theme(top)
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.anchor_right = 1.0
	top.offset_right = 0
	top.offset_bottom = 48
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_toolbar = HBoxContainer.new()
	top.add_child(_toolbar)
	_toolbar.add_theme_constant_override("separation", 12)
	_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Scene selector with label and delete button
	var scene_label = Label.new()
	scene_label.text = "Scene:"
	scene_label.add_theme_color_override("font_color", THEME_TEXT)
	_toolbar.add_child(scene_label)
	
	_scene_combo = OptionButton.new()
	_scene_combo.custom_minimum_size = Vector2(200, 0)
	_apply_button_theme(_scene_combo)
	_toolbar.add_child(_scene_combo)
	
	var btn_delete_scene = Button.new()
	btn_delete_scene.text = "×"
	btn_delete_scene.custom_minimum_size = Vector2(32, 32)
	btn_delete_scene.tooltip_text = "Delete selected scene"
	var delete_style = StyleBoxFlat.new()
	delete_style.bg_color = Color(0.8, 0.2, 0.2, 0.7)
	delete_style.corner_radius_top_left = 4
	delete_style.corner_radius_top_right = 4
	delete_style.corner_radius_bottom_left = 4
	delete_style.corner_radius_bottom_right = 4
	btn_delete_scene.add_theme_stylebox_override("normal", delete_style)
	btn_delete_scene.add_theme_color_override("font_color", THEME_TEXT)
	btn_delete_scene.add_theme_font_size_override("font_size", 24)
	btn_delete_scene.pressed.connect(_delete_selected_scene)
	_toolbar.add_child(btn_delete_scene)
	
	# Separator
	_toolbar.add_child(_make_separator())
	
	# Action buttons with improved styling
	var btn_new = _make_styled_button("New", Color(0.4, 0.65, 1.0))
	_toolbar.add_child(btn_new)
	
	var btn_save = _make_styled_button("Save", Color(0.35, 0.75, 0.5))
	_toolbar.add_child(btn_save)
	
	_toolbar.add_child(_make_separator())
	
	var btn_import = _make_styled_button("Import Lottie", Color(0.6, 0.5, 0.9))
	_toolbar.add_child(btn_import)
	
	_toolbar.add_child(_make_separator())
	
	# Toggle panel button
	var btn_toggle_panel = _make_styled_button("☰", Color(0.5, 0.5, 0.5))
	btn_toggle_panel.tooltip_text = "Toggle Properties Panel (Tab)"
	btn_toggle_panel.pressed.connect(_toggle_properties_panel)
	_toolbar.add_child(btn_toggle_panel)
	
	# Right properties panel
	_prop_panel_container = PanelContainer.new()
	_ui.add_child(_prop_panel_container)
	_apply_panel_theme(_prop_panel_container)
	_prop_panel_container.anchor_right = 1.0
	_prop_panel_container.anchor_left = 1.0
	_prop_panel_container.anchor_top = 0.0
	_prop_panel_container.anchor_bottom = 1.0
	_prop_panel_container.offset_left = -320
	_prop_panel_container.offset_top = 48
	_prop_panel_container.offset_bottom = -32
	_prop_panel_container.visible = false  # Start hidden
	
	var scroll = ScrollContainer.new()
	_prop_panel_container.add_child(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_prop_panel = VBoxContainer.new()
	scroll.add_child(_prop_panel)
	_prop_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prop_panel.add_theme_constant_override("separation", 8)
	_prop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_property_panel()
	
	# Status bar
	var status = PanelContainer.new()
	_ui.add_child(status)
	_apply_panel_theme(status)
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.anchor_right = 1.0
	status.offset_top = -32
	status.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_status_bar = HBoxContainer.new()
	status.add_child(_status_bar)
	_status_bar.add_theme_constant_override("separation", 16)
	_status_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var status_label = Label.new()
	status_label.text = "Ready"
	status_label.add_theme_color_override("font_color", THEME_TEXT)
	_status_bar.add_child(status_label)
	
	# File dialogs
	# Import Lottie - select folder with JSON files
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.title = "Select Folder with Lottie Files"
	_ui.add_child(_file_dialog)
	
	# Save dialog - select folder to save TSCN files
	_save_dialog = FileDialog.new()
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_save_dialog.title = "Select Folder to Save Scene"
	_ui.add_child(_save_dialog)
	
	# Signals
	btn_new.pressed.connect(_new_scene)
	btn_save.pressed.connect(_show_save_confirmation)
	btn_import.pressed.connect(_show_import_lottie_popup)
	_scene_combo.item_selected.connect(func(_i): _load_selected_scene())
	_file_dialog.dir_selected.connect(_on_import_folder_selected)
	_file_dialog.file_selected.connect(_import_lottie)
	_save_dialog.dir_selected.connect(_on_save_folder_selected)

func _make_styled_button(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(90, 32)

	# Base palette derivations
	var base := color
	# Slightly less transparent (more opaque) per feedback
	var bg_normal := Color(base.r, base.g, base.b, 0.20)
	var bg_hover := Color(base.r, base.g, base.b, 0.32)
	var bg_pressed := Color(base.r * 0.85, base.g * 0.85, base.b * 0.85, 0.46)
	var bg_focus := Color(base.r, base.g, base.b, 0.36)
	var border_normal := Color(base.r, base.g, base.b, 0.55)
	var border_hover := Color(base.r + 0.1, base.g + 0.1, base.b + 0.1, 0.75).clamp(Color(0,0,0), Color(1,1,1))
	var border_pressed := Color(base.r * 0.7, base.g * 0.7, base.b * 0.7, 0.9)
	var border_focus := Color(0.95, 0.95, 1.0, 0.85)

	var _mk_style := func(bg: Color, border: Color, shadow_alpha: float) -> StyleBoxFlat:
		var s = StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 1
		s.corner_radius_top_left = 6
		s.corner_radius_top_right = 6
		s.corner_radius_bottom_left = 6
		s.corner_radius_bottom_right = 6
		# Softer, smaller shadow
		s.shadow_size = 4
		s.shadow_color = Color(0,0,0, shadow_alpha)
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		return s

	# Slightly reduce shadow opacity for all states
	btn.add_theme_stylebox_override("normal", _mk_style.call(bg_normal, border_normal, 0.25))
	btn.add_theme_stylebox_override("hover", _mk_style.call(bg_hover, border_hover, 0.33))
	btn.add_theme_stylebox_override("pressed", _mk_style.call(bg_pressed, border_pressed, 0.15))
	btn.add_theme_stylebox_override("focus", _mk_style.call(bg_focus, border_focus, 0.38))
	# Disabled style: desaturate & reduce alpha
	var disabled := _mk_style.call(bg_normal * Color(0.8,0.8,0.8,0.5), border_normal * Color(0.7,0.7,0.7,0.4), 0.0)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", THEME_TEXT)
	btn.add_theme_color_override("font_disabled_color", Color(0.55,0.55,0.6))
	btn.add_theme_font_size_override("font_size", 12)
	btn.tooltip_text = text

	return btn

func _make_separator() -> VSeparator:
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 0)
	return sep

func _apply_panel_theme(panel: PanelContainer) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_PANEL_BG
	style.border_color = THEME_DARK_BG
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

func _apply_button_theme(button: Control) -> void:
	button.add_theme_color_override("font_color", THEME_TEXT)

func _build_property_panel() -> void:
	for child in _prop_panel.get_children():
		_prop_panel.remove_child(child)
		child.queue_free()
	
	var la: LottieAnimation = null
	if _selected is VisibleOnScreenEnabler2D and _selected.get_child_count() > 0 and _selected.get_child(0) is LottieAnimation:
		la = _selected.get_child(0)
	elif _selected is LottieAnimation:
		la = _selected
	
	if _show_properties and la:
		# Professional header with subtle background
		var header_panel = PanelContainer.new()
		var header_style = StyleBoxFlat.new()
		header_style.bg_color = Color(0.22, 0.35, 0.55, 0.3)
		header_style.border_width_bottom = 2
		header_style.border_color = THEME_ACCENT
		header_style.content_margin_left = 12
		header_style.content_margin_right = 12
		header_style.content_margin_top = 10
		header_style.content_margin_bottom = 10
		header_panel.add_theme_stylebox_override("panel", header_style)
		_prop_panel.add_child(header_panel)
		
		var header = Label.new()
		header.text = "PROPERTIES"
		header.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
		header.add_theme_font_size_override("font_size", 12)
		header_panel.add_child(header)
		
		_prop_panel.add_child(_make_separator_horizontal())
		
		# Node name - clean and professional
		var name_container = VBoxContainer.new()
		name_container.add_theme_constant_override("separation", 6)
		_prop_panel.add_child(name_container)
		
		var name_title = Label.new()
		name_title.text = "Node Name"
		name_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		name_title.add_theme_font_size_override("font_size", 11)
		name_container.add_child(name_title)
		
		var name_value = Label.new()
		name_value.text = _selected.name
		name_value.add_theme_color_override("font_color", THEME_ACCENT)
		name_value.add_theme_font_size_override("font_size", 13)
		name_container.add_child(name_value)
		
		_prop_panel.add_child(_make_separator_horizontal())
		
		# Animation file
		if la.has_method("get_animation_path"):
			var anim_container = VBoxContainer.new()
			anim_container.add_theme_constant_override("separation", 6)
			_prop_panel.add_child(anim_container)
			
			var anim_title = Label.new()
			anim_title.text = "Animation"
			anim_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
			anim_title.add_theme_font_size_override("font_size", 11)
			anim_container.add_child(anim_title)
			
			var anim_value = Label.new()
			var full_path = la.get_animation_path()
			anim_value.text = full_path.get_file() if full_path else "(none)"
			anim_value.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
			anim_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			anim_container.add_child(anim_value)
			
			_prop_panel.add_child(_make_separator_horizontal())
		
		# Size section - clean style
		var size_container = VBoxContainer.new()
		size_container.add_theme_constant_override("separation", 8)
		_prop_panel.add_child(size_container)
		
		var size_title = Label.new()
		size_title.text = "SIZE"
		size_title.add_theme_color_override("font_color", THEME_ACCENT)
		size_title.add_theme_font_size_override("font_size", 11)
		size_container.add_child(size_title)
		
		var current_size = la.get_fit_box_size() if la.has_method("get_fit_box_size") else Vector2i(256, 256)
		size_container.add_child(_make_prop_int_inline(current_size.x, func(v):
			if la.has_method("set_fit_box_size"):
				la.set_fit_box_size(Vector2i(v, v))
				_update_enabler_rect_for(la)
		))
		
		_prop_panel.add_child(_make_separator_horizontal())
		
		# Animation controls section
		var controls_title = Label.new()
		controls_title.text = "ANIMATION"
		controls_title.add_theme_color_override("font_color", THEME_ACCENT)
		controls_title.add_theme_font_size_override("font_size", 11)
		_prop_panel.add_child(controls_title)
		
		_prop_panel.add_child(_make_prop_check("Playing", la.playing, func(v):
			la.playing = v
			if v:
				la.play()
			else:
				la.pause()
		))
		_prop_panel.add_child(_make_prop_check("Looping", la.looping, func(v): la.looping = v))
		
		var speed_container = VBoxContainer.new()
		speed_container.add_theme_constant_override("separation", 4)
		_prop_panel.add_child(speed_container)
		
		var speed_label = Label.new()
		speed_label.text = "Speed"
		speed_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		speed_label.add_theme_font_size_override("font_size", 11)
		speed_container.add_child(speed_label)
		
		speed_container.add_child(_make_prop_slider_inline(0.05, 4.0, 0.01, la.speed, func(v): la.speed = v))
		
		_prop_panel.add_child(_make_separator_horizontal())
		
		# Visual section
		var visual_title = Label.new()
		visual_title.text = "VISUAL"
		visual_title.add_theme_color_override("font_color", THEME_ACCENT)
		visual_title.add_theme_font_size_override("font_size", 11)
		_prop_panel.add_child(visual_title)
		
		var modulate_container = VBoxContainer.new()
		modulate_container.add_theme_constant_override("separation", 4)
		_prop_panel.add_child(modulate_container)
		
		var modulate_label = Label.new()
		modulate_label.text = "Modulate"
		modulate_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		modulate_label.add_theme_font_size_override("font_size", 11)
		modulate_container.add_child(modulate_label)
		
		modulate_container.add_child(_make_prop_color_inline(la.modulate, func(c): la.modulate = c))
		
		# Actions - Professional delete button
		_prop_panel.add_child(_make_separator_horizontal())
		
		var delete_container = MarginContainer.new()
		delete_container.add_theme_constant_override("margin_top", 8)
		delete_container.add_theme_constant_override("margin_bottom", 8)
		_prop_panel.add_child(delete_container)
		
		var btn_delete = Button.new()
		btn_delete.text = "Delete Node"
		btn_delete.custom_minimum_size = Vector2(0, 36)
		
		# Professional red button style
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.65, 0.15, 0.15, 0.3)
		style_normal.border_width_left = 1
		style_normal.border_width_right = 1
		style_normal.border_width_top = 1
		style_normal.border_width_bottom = 1
		style_normal.border_color = Color(0.85, 0.25, 0.25, 0.6)
		style_normal.corner_radius_top_left = 6
		style_normal.corner_radius_top_right = 6
		style_normal.corner_radius_bottom_left = 6
		style_normal.corner_radius_bottom_right = 6
		btn_delete.add_theme_stylebox_override("normal", style_normal)
		
		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(0.75, 0.2, 0.2, 0.5)
		style_hover.border_width_left = 1
		style_hover.border_width_right = 1
		style_hover.border_width_top = 1
		style_hover.border_width_bottom = 1
		style_hover.border_color = Color(0.95, 0.3, 0.3, 0.8)
		style_hover.corner_radius_top_left = 6
		style_hover.corner_radius_top_right = 6
		style_hover.corner_radius_bottom_left = 6
		style_hover.corner_radius_bottom_right = 6
		btn_delete.add_theme_stylebox_override("hover", style_hover)
		
		var style_pressed = StyleBoxFlat.new()
		style_pressed.bg_color = Color(0.85, 0.25, 0.25, 0.7)
		style_pressed.border_width_left = 1
		style_pressed.border_width_right = 1
		style_pressed.border_width_top = 1
		style_pressed.border_width_bottom = 1
		style_pressed.border_color = Color(1.0, 0.35, 0.35, 1.0)
		style_pressed.corner_radius_top_left = 6
		style_pressed.corner_radius_top_right = 6
		style_pressed.corner_radius_bottom_left = 6
		style_pressed.corner_radius_bottom_right = 6
		btn_delete.add_theme_stylebox_override("pressed", style_pressed)
		
		btn_delete.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
		btn_delete.add_theme_font_size_override("font_size", 12)
		
		btn_delete.pressed.connect(func():
			if _selected:
				_selected.queue_free()
				_selected = null
				_show_properties = false
				if _prop_panel_container:
					_prop_panel_container.visible = false
				_build_property_panel()
		)
		delete_container.add_child(btn_delete)
	else:
		var header = _make_section_header("EDITOR SETTINGS")
		_prop_panel.add_child(header)
		
		var hint = Label.new()
		hint.text = "Right-click a Lottie node to edit its properties"
		hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_prop_panel.add_child(hint)
		
		_prop_panel.add_child(_make_separator_horizontal())
		
		var controls = Label.new()
		controls.text = "CONTROLS:\n• Left Click + Drag: Move node\n• Right Click: Select & edit\n• Mouse Wheel: Zoom\n• WASD/Arrows: Pan camera\n• Space + Mouse: Pan camera\n• F: Center on origin\n• Tab: Toggle this panel\n• Ctrl+C: Copy node\n• Ctrl+V: Paste node\n• Ctrl+D: Duplicate\n• Delete: Remove node"
		controls.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_prop_panel.add_child(controls)

func _make_section_header(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", THEME_ACCENT)
	label.add_theme_font_size_override("font_size", 14)
	return label

func _make_property_section(title: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var label = Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(label)
	return vbox

func _make_small_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 24)
	return btn

func _make_separator_horizontal() -> HSeparator:
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 8)
	return sep

func _make_prop_slider_inline(min_v: float, max_v: float, step: float, value: float, on_change: Callable) -> Control:
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var s = HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value = value
	hb.add_child(s)
	var val_label = Label.new()
	val_label.text = "%.2f" % value
	val_label.custom_minimum_size = Vector2(50, 0)
	val_label.add_theme_color_override("font_color", THEME_TEXT)
	hb.add_child(val_label)
	s.value_changed.connect(func(v):
		val_label.text = "%.2f" % v
		on_change.call(v)
	)
	return hb

func _make_prop_check(label: String, value: bool, on_change: Callable) -> Control:
	var cb = CheckBox.new()
	cb.text = label
	cb.button_pressed = value
	cb.toggled.connect(on_change)
	return cb

func _make_prop_color_inline(value: Color, on_change: Callable) -> Control:
	var hb = HBoxContainer.new()
	var pc = ColorPickerButton.new()
	pc.color = value
	pc.custom_minimum_size = Vector2(200, 32)
	hb.add_child(pc)
	pc.color_changed.connect(on_change)
	return hb

func _make_prop_vec2_inline(value: Vector2, on_change: Callable) -> Control:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var lx = Label.new()
	lx.text = "X:"
	lx.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	h.add_child(lx)
	var sx = SpinBox.new()
	sx.min_value = -10000
	sx.max_value = 10000
	sx.step = 1
	sx.value = value.x
	sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sx)
	var ly = Label.new()
	ly.text = "Y:"
	ly.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	h.add_child(ly)
	var sy = SpinBox.new()
	sy.min_value = -10000
	sy.max_value = 10000
	sy.step = 1
	sy.value = value.y
	sy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sy)
	sx.value_changed.connect(func(v): on_change.call(Vector2(v, sy.value)))
	sy.value_changed.connect(func(v): on_change.call(Vector2(sx.value, v)))
	return h

func _make_prop_vec2i_inline(value: Vector2i, on_change: Callable) -> Control:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var lx = Label.new()
	lx.text = "W:"
	lx.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	h.add_child(lx)
	var sx = SpinBox.new()
	sx.min_value = 16
	sx.max_value = 2048
	sx.step = 1
	sx.value = value.x
	sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sx)
	var ly = Label.new()
	ly.text = "H:"
	ly.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	h.add_child(ly)
	var sy = SpinBox.new()
	sy.min_value = 16
	sy.max_value = 2048
	sy.step = 1
	sy.value = value.y
	sy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sy)
	sx.value_changed.connect(func(v): on_change.call(Vector2i(int(v), int(sy.value))))
	sy.value_changed.connect(func(v): on_change.call(Vector2i(int(sx.value), int(v))))
	return h

func _make_prop_int_inline(value: int, on_change: Callable) -> Control:
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var s = SpinBox.new()
	s.min_value = 16
	s.max_value = 2048
	s.step = 1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(s)
	var px_label = Label.new()
	px_label.text = "px"
	px_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hb.add_child(px_label)
	s.value_changed.connect(func(v): on_change.call(int(v)))
	return hb

func _make_prop_angle_inline(value: float, on_change: Callable) -> Control:
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var s = SpinBox.new()
	s.min_value = -360
	s.max_value = 360
	s.step = 1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(s)
	var deg_label = Label.new()
	deg_label.text = "°"
	deg_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hb.add_child(deg_label)
	s.value_changed.connect(on_change)
	return hb

# Input handling & interaction ----------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# Check if mouse is over UI
		if _is_mouse_over_ui(mb.position):
			return
		
		if (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mb.pressed:
			# Discrete integer zoom levels with smooth animation.
			# Wheel up => zoom in to next level; wheel down => zoom out to next level.
			var is_wheel_up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			var zoom_in: bool = is_wheel_up
			var mouse := mb.position
			var old_scalar := _camera.zoom.x
			# Convert current scalar to percent and pick next level
			var current_percent: float = 100.0 / max(old_scalar, 0.0001)
			var target_percent: float = _get_next_zoom_level(current_percent, zoom_in)
			var new_scalar := clampf(100.0 / float(target_percent), ZOOM_MIN, ZOOM_MAX)
			# Prepare animated zoom around the mouse focus
			_zoom_from = Vector2(old_scalar, old_scalar)
			_zoom_to = Vector2(new_scalar, new_scalar)
			_zoom_focus_screen = mouse
			# Convert focus using center anchor
			var vs = get_viewport().get_visible_rect().size
			_zoom_focus_world = _camera.position + ((mouse - vs * 0.5) * old_scalar)
			_zoom_anim = ZOOM_ANIM_TIME
			# Set targets for post-animation settling and UI status
			_zoom_target = _zoom_to
			_pos_target = _zoom_focus_world - ((mouse - vs * 0.5) * new_scalar)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(mb.position)
			else:
				_end_drag()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_select_at(mb.position)
			_show_properties = _selected != null
			_build_property_panel()
		_last_mouse_screen = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_last_mouse_screen = mm.position
		_update_hover(mm.position)
		
		# Update cursor based on hover over handles
		if not _dragging and not _resizing and not _panning:
			var handle_idx = _get_handle_at(mm.position)
			if handle_idx >= 0:
				Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE if handle_idx in [0, 2] else Input.CURSOR_BDIAGSIZE)
			else:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		
		if _dragging or _resizing:
			_drag_to(mm.position)
		elif _panning:
			# Pan camera with mouse while holding Space
			var mouse_delta = mm.position - _pan_start_mouse
			_pos_target = _pan_start_camera - (mouse_delta * _camera.zoom)
	elif event is InputEventKey:
		var ik := event as InputEventKey
		if ik.pressed and not ik.echo:
			if ik.keycode == KEY_DELETE and _selected:
				_selected.queue_free()
				_selected = null
				_show_properties = false
				_build_property_panel()
			elif ik.keycode == KEY_TAB:
				_toggle_properties_panel()
			elif ik.keycode == KEY_F:
				_center_camera_on_origin()
			elif ik.keycode == KEY_SPACE:
				_start_panning(get_viewport().get_mouse_position())
			elif ik.ctrl_pressed and ik.keycode == KEY_D and _selected:
				_duplicate_selected()
			elif ik.ctrl_pressed and ik.keycode == KEY_C and _selected:
				_copy_selected()
			elif ik.ctrl_pressed and ik.keycode == KEY_V:
				_paste_selected()
		elif not ik.pressed and ik.keycode == KEY_SPACE:
			_end_panning()

func _update_hover(mouse_pos: Vector2) -> void:
	if _dragging:
		_hover_node = null
		return
	var world = _screen_to_world(mouse_pos)
	_hover_node = _pick_at(world)

func _duplicate_selected() -> void:
	if not _selected:
		return
	var copy = _selected.duplicate()
	assets.add_child(copy)
	copy.global_position = (_selected as Node2D).global_position + Vector2(32, 32)
	_selected = copy
	_build_property_panel()

func _copy_selected() -> void:
	if not _selected:
		return
	_clipboard = _selected
	_update_status("Copied: " + _selected.name)

func _paste_selected() -> void:
	if not _clipboard:
		_update_status("Nothing to paste")
		return
	var copy = _clipboard.duplicate()
	assets.add_child(copy)
	# Paste at center of viewport
	var viewport_size = get_viewport().get_visible_rect().size
	var center_screen = viewport_size * 0.5
	copy.global_position = _screen_to_world(center_screen)
	_selected = copy
	_show_properties = true
	_build_property_panel()
	_update_status("Pasted: " + copy.name)

func _begin_drag(mouse_pos: Vector2) -> void:
	# Check if clicking on a resize handle first (if something is selected)
	if _selected:
		var handle_idx = _get_handle_at(mouse_pos)
		if handle_idx >= 0:
			# Start resizing
			_resizing = true
			_resize_handle = handle_idx
			_resize_start_mouse = mouse_pos
			var la = _extract_lottie(_selected)
			if la and la.has_method("get_fit_box_size"):
				_resize_start_size = la.get_fit_box_size()
			return
	
	# Otherwise, try to pick a node
	var world = _screen_to_world(mouse_pos)
	var picked = _pick_at(world)
	if picked:
		_selected = picked
		_show_properties = true
		# Show panel when selecting a node
		if _prop_panel_container:
			_prop_panel_container.visible = true
		_dragging = true
		# Store initial mouse position and object position for direct dragging
		_drag_start_mouse = mouse_pos
		_drag_start_pos = _selected.global_position
		_build_property_panel()
	else:
		# Deselect if clicking on empty space
		_selected = null
		_show_properties = false
		# Hide panel when deselecting
		if _prop_panel_container:
			_prop_panel_container.visible = false
		_dragging = false
		_build_property_panel()

func _get_handle_at(mouse_pos: Vector2) -> int:
	if not _selected:
		return -1
	
	var la = _extract_lottie(_selected)
	if not la:
		return -1

	# Compute on-screen oriented corners using canvas transform (includes camera zoom)
	var corners = _lottie_screen_corners(la)
	
	var handle_radius = 8.0
	for i in range(corners.size()):
		if mouse_pos.distance_to(corners[i]) < handle_radius:
			return i
	
	return -1

func _drag_to(mouse_pos: Vector2) -> void:
	if not _selected:
		return
	
	if _resizing:
		# Resize by handle (always maintains square aspect ratio)
		var mouse_delta = mouse_pos - _resize_start_mouse
		var la = _extract_lottie(_selected)
		if not la or not la.has_method("set_fit_box_size"):
			return
		
		# Calculate new size based on which handle is being dragged
		var delta_pixels = mouse_delta / _camera.zoom  # Convert to world space
		
		# Use the larger delta (X or Y) to maintain square
		var delta_x = 0
		var delta_y = 0
		
		# Handle resize based on corner
		match _resize_handle:
			0:  # Top-left: inverse both
				delta_x = -int(delta_pixels.x)
				delta_y = -int(delta_pixels.y)
			1:  # Top-right: normal X, inverse Y
				delta_x = int(delta_pixels.x)
				delta_y = -int(delta_pixels.y)
			2:  # Bottom-right: normal both
				delta_x = int(delta_pixels.x)
				delta_y = int(delta_pixels.y)
			3:  # Bottom-left: inverse X, normal Y
				delta_x = -int(delta_pixels.x)
				delta_y = int(delta_pixels.y)
		
		# Use average of both deltas to maintain square
		var avg_delta = (delta_x + delta_y) / 2
		var new_size_value = _resize_start_size.x + avg_delta
		
		# Clamp to reasonable values
		new_size_value = clampi(new_size_value, 16, 2048)
		
		la.set_fit_box_size(Vector2i(new_size_value, new_size_value))
		_update_enabler_rect_for(la)
		# Update panel during resize to show current size
		_build_property_panel()
		
	elif _dragging:
		# Move node
		var mouse_delta = mouse_pos - _drag_start_mouse
		var world_delta = mouse_delta / _camera.zoom
		_selected.global_position = _drag_start_pos + world_delta

func _end_drag() -> void:
	var was_resizing = _resizing
	_dragging = false
	_resizing = false
	_resize_handle = -1
	# Update panel after resize is complete
	if was_resizing:
		_build_property_panel()

func _start_panning(mouse_pos: Vector2) -> void:
	_panning = true
	_pan_start_mouse = mouse_pos
	_pan_start_camera = _camera.position
	# Change cursor to hand/move cursor
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)

func _end_panning() -> void:
	_panning = false
	# Reset cursor to default
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _toggle_properties_panel() -> void:
	if _prop_panel_container:
		_prop_panel_container.visible = not _prop_panel_container.visible

func _center_camera_on_origin() -> void:
	# Center camera on world origin (0, 0) with smooth transition
	# Position camera so (0,0) is at top-left of viewport
	_pos_target = Vector2.ZERO

func _pick_at(world_pos: Vector2) -> Node2D:
	# Oriented hit-test using node's transform (robust under zoom/rotation)
	var candidates := []
	for n in assets.get_children():
		if n is Node2D and _hit_node_oriented(n, world_pos):
			candidates.append(n)

	# Return closest if multiple candidates
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]
	var closest = candidates[0]
	var closest_dist = (closest as Node2D).global_position.distance_to(world_pos)
	for c in candidates:
		var dist = (c as Node2D).global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest = c
			closest_dist = dist
	return closest

func _select_at(screen_pos: Vector2) -> void:
	var world = _screen_to_world(screen_pos)
	_selected = _pick_at(world)

# Scene load/save ------------------------------------------------------------
func _new_scene() -> void:
	# Background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	_ui.add_child(overlay)
	
	# Center container for the popup
	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	overlay.add_child(center)
	
	# Main popup panel
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(340, 160)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.17, 0.98)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.35, 0.5, 0.85, 0.5)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.shadow_size = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", panel_style)
	
	center.add_child(popup)
	
	# Content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "New Scene"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Input label
	var input_label = Label.new()
	input_label.text = "Scene name:"
	input_label.add_theme_font_size_override("font_size", 11)
	input_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(input_label)
	
	# Line edit for scene name
	var le = LineEdit.new()
	le.text = "new_scene"
	le.custom_minimum_size = Vector2(0, 32)
	le.add_theme_font_size_override("font_size", 12)
	le.select_all()
	vbox.add_child(le)
	
	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Buttons
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 8)
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)
	
	# Cancel button
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 32)
	btn_cancel.add_theme_font_size_override("font_size", 11)
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
	)
	btn_container.add_child(btn_cancel)
	
	# Create button
	var btn_create = Button.new()
	btn_create.text = "Create"
	btn_create.custom_minimum_size = Vector2(100, 32)
	btn_create.add_theme_font_size_override("font_size", 11)
	
	var create_style = StyleBoxFlat.new()
	create_style.bg_color = Color(0.35, 0.6, 0.95, 0.8)
	create_style.corner_radius_top_left = 4
	create_style.corner_radius_top_right = 4
	create_style.corner_radius_bottom_left = 4
	create_style.corner_radius_bottom_right = 4
	btn_create.add_theme_stylebox_override("normal", create_style)
	
	var create_hover = StyleBoxFlat.new()
	create_hover.bg_color = Color(0.4, 0.65, 1.0, 0.9)
	create_hover.corner_radius_top_left = 4
	create_hover.corner_radius_top_right = 4
	create_hover.corner_radius_bottom_left = 4
	create_hover.corner_radius_bottom_right = 4
	btn_create.add_theme_stylebox_override("hover", create_hover)
	
	btn_create.pressed.connect(func():
		overlay.queue_free()
		# Clear current assets
		for c in assets.get_children():
			assets.remove_child(c)
			c.queue_free()
		_selected = null
		_show_properties = false
		if _prop_panel_container:
			_prop_panel_container.visible = false
		_build_property_panel()
		# Save empty scene with the given name
		_save_scene_with_name(le.text)
		_update_status("New scene created: " + le.text)
	)
	btn_container.add_child(btn_create)
	
	# Close on overlay click
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	
	# Focus the line edit
	le.call_deferred("grab_focus")

func _save_scene() -> void:
	if assets.get_child_count() == 0:
		_update_status("Nothing to save")
		return
	
	# Check if a scene is currently selected
	var selected_idx = _scene_combo.selected
	if selected_idx >= 0:
		var meta = _scene_combo.get_item_metadata(selected_idx)
		if meta != null:
			# Update the existing scene
			var scene_name = String(meta).get_file().get_basename()
			_save_scene_with_name(scene_name)
			return
	
	# No scene selected, create new one
	_save_scene_with_name("scene_%d" % Time.get_unix_time_from_system())

func _save_scene_with_name(scene_name: String) -> void:
	# Use selected path or fallback to a writable default
	var save_dir = _resolve_dir(_save_base_path)
	if save_dir == "":
		# Prefer user:// in exported games, default to USER_SCENES_DIR
		save_dir = USER_SCENES_DIR if DirAccess.open(USER_SCENES_DIR) or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_SCENES_DIR)) == OK else SCENES_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	
	# Create a complete scene structure like renderingDemo.tscn
	var root_scene := Node2D.new()
	root_scene.name = "Scene"
	
	# Add rendering_demo.gd script to root
	var rendering_script = load("res://addons/godot_lottie/scripts/rendering_demo.gd")
	if rendering_script:
		root_scene.set_script(rendering_script)
	
	# Create Editor node with editor.gd script
	var editor_node := Node.new()
	editor_node.name = "Editor"
	var editor_script = load("res://addons/godot_lottie/scripts/editor.gd")
	if editor_script:
		editor_node.set_script(editor_script)
	root_scene.add_child(editor_node)
	editor_node.owner = root_scene
	
	# Add viewport sprite as child of Editor (if exists in current scene)
	var viewport_sprite := Sprite2D.new()
	viewport_sprite.name = "viewport"
	viewport_sprite.self_modulate = Color(1, 1, 1, 0.4)
	viewport_sprite.position = Vector2(640, 360)
	var viewport_texture = load("res://addons/godot_lottie/demo/Rectangle 1.png")
	if viewport_texture:
		viewport_sprite.texture = viewport_texture
	viewport_sprite.set_meta("_edit_lock_", true)
	editor_node.add_child(viewport_sprite)
	viewport_sprite.owner = root_scene
	
	# Create Assets container
	var assets_node := Node.new()
	assets_node.name = "Assets"
	root_scene.add_child(assets_node)
	assets_node.owner = root_scene
	
	# Copy all VisibleOnScreenEnabler2D nodes from current assets
	for n in assets.get_children():
		if n is VisibleOnScreenEnabler2D:
			var enabler_dup := VisibleOnScreenEnabler2D.new()
			enabler_dup.name = n.name
			enabler_dup.global_position = n.global_position
			enabler_dup.rect = n.rect
			
			# Add to lottie_culling group
			enabler_dup.add_to_group("lottie_culling")
			
			# Ensure runtime enable toggles the Lottie child
			enabler_dup.set("enable_node_path", NodePath("LottieAnimation"))
			
			assets_node.add_child(enabler_dup)
			enabler_dup.owner = root_scene
			
			# Copy LottieAnimation child
			for child in n.get_children():
				if child is LottieAnimation:
					var la_dup := LottieAnimation.new()
					la_dup.name = child.name
					# LottieAnimation is always at (0,0) relative to parent
					la_dup.position = Vector2.ZERO
					la_dup.rotation = child.rotation
					la_dup.scale = child.scale
					la_dup.modulate = child.modulate
					
					# Copy Lottie properties
					if child.animation_path:
						la_dup.set_animation_path(child.animation_path)
					if child.is_fit_into_box():
						la_dup.set_fit_into_box(true)
						if child.has_method("get_fit_box_size"):
							la_dup.set_fit_box_size(child.get_fit_box_size())
					la_dup.looping = child.looping
					la_dup.playing = child.playing
					la_dup.speed = child.speed
					la_dup.process_mode = child.process_mode
					
					enabler_dup.add_child(la_dup)
					la_dup.owner = root_scene
					break
			
			# Connect signals (will be saved in the .tscn)
			# The rendering_demo.gd script will reconnect these on _ready
	
	# Pack and save the scene
	var scene := PackedScene.new()
	scene.pack(root_scene)
	if not scene_name.ends_with(".tscn"):
		scene_name += ".tscn"
	var path = save_dir + "/" + scene_name
	var err = ResourceSaver.save(scene, path)
	if err != OK:
		_update_status("Save failed: " + str(err))
	else:
		_update_status("Saved to: " + path)
	
	# Refresh list and keep this scene selected
	_refresh_scene_list()
	_select_scene_in_combo(scene_name)
	
	# Clean up temporary scene
	root_scene.queue_free()

func _update_status(message: String) -> void:
	if _status_bar and _status_bar.get_child_count() > 0:
		var label = _status_bar.get_child(0) as Label
		if label:
			label.text = message

func _delete_selected_scene() -> void:
	var selected_idx = _scene_combo.selected
	if selected_idx < 0:
		_update_status("No scene selected")
		return
	
	var meta = _scene_combo.get_item_metadata(selected_idx)
	if meta == null:
		return
	
	var meta_str := String(meta)
	# Normalize meta path: if it’s only a filename, prepend current root dir
	if not (meta_str.begins_with("res://") or meta_str.begins_with("user://")):
		meta_str = _get_scene_root_dir().rstrip("/") + "/" + meta_str
	
	# Confirmation dialog
	var dlg = ConfirmationDialog.new()
	dlg.title = "Delete Scene"
	dlg.dialog_text = "Delete scene: " + meta_str.get_file() + "?"
	
	var on_confirmed = func():
		var abs_path = ProjectSettings.globalize_path(meta_str)
		if FileAccess.file_exists(abs_path):
			var da = DirAccess.open(abs_path.get_base_dir())
			if da:
				var err = da.remove(abs_path.get_file())
				if err == OK:
					_update_status("Deleted: " + meta_str.get_file())
					await get_tree().process_frame
					_refresh_scene_list()
					# Load the first available scene after delete, or clear if none
					if _scene_combo.item_count > 0:
						_scene_combo.selected = 0
						_load_selected_scene()
					else:
						# No scenes left, clear assets
						for c in assets.get_children():
							assets.remove_child(c)
							c.queue_free()
						_selected = null
						_show_properties = false
						_build_property_panel()
				else:
					_update_status("Delete failed: " + str(err))
			else:
				_update_status("Failed to open directory")
		else:
			_update_status("File not found")
		dlg.queue_free()
	
	var on_canceled = func():
		dlg.queue_free()
	
	dlg.confirmed.connect(on_confirmed)
	dlg.canceled.connect(on_canceled)
	_ui.add_child(dlg)
	dlg.popup_centered(Vector2(350, 120))

func _refresh_scene_list() -> void:
	_scene_combo.clear()
	var idx := 0
	var root_dir := _get_scene_root_dir()
	var ra = DirAccess.open(root_dir)
	if ra:
		ra.list_dir_begin()
		var g = ra.get_next()
		while g != "":
			if g.ends_with(".tscn") and not g.begins_with("."):
				_scene_combo.add_item(g)
				_scene_combo.set_item_metadata(idx, root_dir + "/" + g)
				idx += 1
			g = ra.get_next()
		ra.list_dir_end()

func _select_scene_in_combo(scene_name: String) -> void:
	# Find and select scene in combo by name
	if not scene_name.ends_with(".tscn"):
		scene_name += ".tscn"
	
	_ignore_scene_change = true
	for i in range(_scene_combo.item_count):
		if _scene_combo.get_item_text(i) == scene_name:
			_scene_combo.selected = i
			break
	_ignore_scene_change = false

func _load_selected_scene() -> void:
	# Ignore if this is a programmatic selection change
	if _ignore_scene_change:
		# Ignored programmatic selection change
		return
	
	var meta = _scene_combo.get_selected_metadata()
	if meta == null:
		# No scene metadata to load
		return
	
	# Loading scene
	
	# Force reload by using CACHE_MODE_REPLACE
	var ps: PackedScene = ResourceLoader.load(meta, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not ps:
		_update_status("Failed to load scene")
		return
	
	for c in assets.get_children():
		assets.remove_child(c)
		c.queue_free()
	
	var inst = ps.instantiate()
	if inst.has_node("Assets"):
		var a = inst.get_node("Assets")
		for c in a.get_children():
			a.remove_child(c)
			# Clear owner before adding to new tree
			c.owner = null
			assets.add_child(c)
			# Check if it has LottieAnimation child and reload animation
			if c.get_child_count() > 0 and c.get_child(0) is LottieAnimation:
				var la = c.get_child(0) as LottieAnimation
				# In editor: disable runtime culling/enabling and force visible/processing
				if c is VisibleOnScreenEnabler2D and c.has_method("set"):
					# Prevent the enabler from toggling child state during editing
					c.set("enable_node_path", NodePath(""))
				# Ensure visibility and processing are active in the editor
				la.show()
				la.process_mode = Node.PROCESS_MODE_ALWAYS
				# Ensure animation is loaded and playing
				if la.animation_path:
					if not la.playing:
						la.playing = true
					la.play()
					# Force canvas update
					la.queue_redraw()
	else:
		for c in inst.get_children():
			inst.remove_child(c)
			# Clear owner before adding to new tree
			c.owner = null
			assets.add_child(c)
	inst.queue_free()
	
	# Ensure wrappers are properly configured
	for w in assets.get_children():
		if w is VisibleOnScreenEnabler2D and w.get_child_count() > 0 and w.get_child(0) is LottieAnimation:
			var la := w.get_child(0) as LottieAnimation
			_sync_enabler_rect(w, la)
	
	_selected = null
	_show_properties = false
	_build_property_panel()
	_update_all_enabler_rects()
	_update_status("Scene loaded: " + String(meta).get_file())

# Lottie creation -----------------------------------------------------------
func _import_lottie(path: String) -> void:
	# Create VisibleOnScreenEnabler2D wrapper with unique name
	var wrapper := VisibleOnScreenEnabler2D.new()
	wrapper.name = _get_unique_name("Visible")
	wrapper.add_to_group("lottie_culling")
	
	var la := LottieAnimation.new()
	la.name = "LottieAnimation"
	la.position = Vector2.ZERO  # Child is at (0,0) relative to parent
	la.set_animation_path(path)
	la.set_fit_into_box(true)
	if la.has_method("set_fit_box_size"):
		la.set_fit_box_size(Vector2i(256, 256))
	
	# Set playing state
	la.playing = true
	la.looping = true
	la.speed = 1.0
	
	# Always spawn at center of viewport (position is on the wrapper/parent)
	var viewport_size = get_viewport().get_visible_rect().size
	var center_screen = viewport_size * 0.5
	wrapper.global_position = _screen_to_world(center_screen)
	
	assets.add_child(wrapper)
	wrapper.add_child(la)
	
	if wrapper.has_method("set"):
		# Disable enabler side-effects while editing; re-enable on save
		wrapper.set("enable_node_path", NodePath(""))
	# Ensure visible and always processing in editor
	la.show()
	la.process_mode = Node.PROCESS_MODE_ALWAYS
	
	_sync_enabler_rect(wrapper, la)
	_selected = wrapper
	_show_properties = true
	if _prop_panel_container:
		_prop_panel_container.visible = true
	_build_property_panel()
	_update_status("Imported: " + path.get_file())
	
	# Force the LottieAnimation to start after being added to tree
	la.call_deferred("set_playing", true)

func _add_empty_lottie() -> void:
	# Create VisibleOnScreenEnabler2D wrapper with unique name
	var wrapper := VisibleOnScreenEnabler2D.new()
	wrapper.name = _get_unique_name("Visible")
	wrapper.add_to_group("lottie_culling")
	
	var la := LottieAnimation.new()
	la.name = "LottieAnimation"
	la.position = Vector2.ZERO  # Child is at (0,0) relative to parent
	la.set_fit_into_box(true)
	if la.has_method("set_fit_box_size"):
		la.set_fit_box_size(Vector2i(256, 256))
	
	# Always spawn at center of viewport (position is on the wrapper/parent)
	var viewport_size = get_viewport().get_visible_rect().size
	var center_screen = viewport_size * 0.5
	wrapper.global_position = _screen_to_world(center_screen)
	
	assets.add_child(wrapper)
	wrapper.add_child(la)
	
	if wrapper.has_method("set"):
		# Disable enabler side-effects while editing; re-enable on save
		wrapper.set("enable_node_path", NodePath(""))
	# Ensure visible and always processing in editor
	la.show()
	la.process_mode = Node.PROCESS_MODE_ALWAYS
	
	_sync_enabler_rect(wrapper, la)
	_selected = wrapper
	_show_properties = true
	_build_property_panel()
	_update_status("Added new Lottie node")

func _get_unique_name(base_name: String) -> String:
	# Check if base name exists, if not return it
	if not assets.has_node(base_name):
		return base_name
	
	# Find next available number
	var counter = 2
	while assets.has_node(base_name + str(counter)):
		counter += 1
	
	return base_name + str(counter)

func _rename_selected() -> void:
	if not _selected:
		return
	var dlg = AcceptDialog.new()
	dlg.title = "Rename Node"
	var vbox = VBoxContainer.new()
	dlg.add_child(vbox)
	var label = Label.new()
	label.text = "New name:"
	vbox.add_child(label)
	var le = LineEdit.new()
	le.text = _selected.name
	le.custom_minimum_size = Vector2(250, 0)
	vbox.add_child(le)
	dlg.confirmed.connect(func():
		_selected.name = le.text
		_build_property_panel()
	)
	_ui.add_child(dlg)
	dlg.popup_centered(Vector2(320, 120))

func _process(delta: float) -> void:
	if _overlay:
		_overlay.queue_redraw()
	
	# Update status bar with camera info
	_update_camera_status()

	# Animated zoom around focus point if active
	if _zoom_anim > 0.0:
		var step = min(delta, _zoom_anim)
		_zoom_anim -= step
		var t = 1.0 - (_zoom_anim / ZOOM_ANIM_TIME)
		_camera.zoom = _zoom_from.lerp(_zoom_to, t)
		# Keep the world point under cursor fixed
		var vs = get_viewport().get_visible_rect().size
		_camera.position = _zoom_focus_world - ((_zoom_focus_screen - vs * 0.5) * _camera.zoom.x)
		# (Optional filtering tweak removed: RenderingServer helper not available here)
	else:
		# Smoothly animate camera zoom and position towards targets (post-animation settling / pan)
		var z_t = 1.0 - pow(0.001, delta * ZOOM_LERP_SPEED)
		var p_t = 1.0 - pow(0.001, delta * PAN_LERP_SPEED)
		if _camera.zoom != _zoom_target:
			_camera.zoom = _camera.zoom.lerp(_zoom_target, z_t)
		if _camera.position != _pos_target:
			_camera.position = _camera.position.lerp(_pos_target, p_t)

		# Snap to exact target when close and align to pixel grid for crisp 100%
		if abs(_camera.zoom.x - _zoom_target.x) < 0.0005:
			_camera.zoom = _zoom_target
			_snap_camera_to_pixel_grid()
			# Filtering toggles are disabled (using engine defaults)
	
	# Camera keyboard pan (WASD + arrows)
	var move := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move.y -= 1
	if move != Vector2.ZERO:
		# Divide by zoom so camera moves faster when zoomed out (just like drag)
		# At 200% zoom (zoom=0.5), movement is 2x faster
		# At 500% zoom (zoom=0.2), movement is 5x faster
		var speed = 600.0 * delta
		_pos_target += (move.normalized() * speed) / _camera.zoom.x

func _update_camera_status() -> void:
	if _status_bar and _status_bar.get_child_count() > 0:
		var label = _status_bar.get_child(0) as Label
		if label and not _dragging:
			var percent: float = 100.0 / _camera.zoom.x
			label.text = "Zoom: %s | Camera: (%.0f, %.0f)" % [_format_percent(percent), _camera.position.x, _camera.position.y]

func _on_overlay_draw() -> void:
	if not _overlay:
		return
	
	# Draw selection highlight
	if _selected:
		_draw_oriented_outline(_selected, SELECTION_COLOR, 2.0, true)
	
	# Draw hover highlight
	if _hover_node and _hover_node != _selected:
		_draw_oriented_outline(_hover_node, HOVER_COLOR, 1.5, false)

# Draw oriented rectangle using node's global transform
func _draw_oriented_outline(node: Node2D, color: Color, width: float, draw_handles: bool) -> void:
	var la := _extract_lottie(node)
	if not la:
		# Fallback for non-Lottie nodes
		var size := Vector2(128, 128)
		var pos_screen := _world_to_screen(node.global_position)
		var rect_screen := Rect2(pos_screen - size * 0.5, size)
		_overlay.draw_rect(rect_screen, color, false, width)
		if draw_handles:
			var corners := [
				rect_screen.position,
				rect_screen.position + Vector2(rect_screen.size.x, 0),
				rect_screen.position + rect_screen.size,
				rect_screen.position + Vector2(0, rect_screen.size.y)
			]
			for c in corners:
				_overlay.draw_circle(c, 6.0, color)
		return

	# Compute exact on-screen corners with full transform (camera zoom included)
	var corners_screen: Array = _lottie_screen_corners(la)
	for i in range(corners_screen.size()):
		var a: Vector2 = corners_screen[i]
		var b: Vector2 = corners_screen[(i + 1) % corners_screen.size()]
		_overlay.draw_line(a, b, color, width)
	if draw_handles:
		for cs in corners_screen:
			_overlay.draw_circle(cs, 6.0, color)

func _draw_handles(bounds: Rect2) -> void:
	if not _overlay:
		return
	var handle_size = 8.0
	var corners = [
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0),
		bounds.position + bounds.size,
		bounds.position + Vector2(0, bounds.size.y)
	]
	for corner in corners:
		_overlay.draw_circle(corner, handle_size, SELECTION_COLOR)

func _selected_bounds() -> Rect2:
	if not _selected:
		return Rect2()
	return _node_bounds(_selected)

func _node_bounds(node: Node2D) -> Rect2:
	var la: LottieAnimation = null
	if node is VisibleOnScreenEnabler2D and node.get_child_count() > 0 and node.get_child(0) is LottieAnimation:
		la = node.get_child(0)
	elif node is LottieAnimation:
		la = node
	
	if la:
		var size := _lottie_size_world(la)
		return Rect2(la.global_position - size * 0.5, size)
	
	return Rect2(node.global_position - Vector2(64, 64), Vector2(128, 128))

# Helpers: oriented hit test and size computation ---------------------------------
func _extract_lottie(node: Node2D) -> LottieAnimation:
	if node is LottieAnimation:
		return node
	if node is VisibleOnScreenEnabler2D and node.get_child_count() > 0 and node.get_child(0) is LottieAnimation:
		return node.get_child(0)
	return null

func _lottie_base_size(la: LottieAnimation) -> Vector2:
	var base := Vector2.ZERO
	if la.is_fit_into_box():
		base = Vector2(la.get_fit_box_size())
	elif la.texture:
		base = Vector2(la.texture.get_width(), la.texture.get_height())
	if base == Vector2.ZERO:
		base = Vector2(128,128)
	return base

func _lottie_local_rect_top_left(la: LottieAnimation) -> Rect2:
	var scaled := _lottie_base_size(la) * la.scale
	return Rect2(Vector2.ZERO, scaled)

func _lottie_local_rect_centered(la: LottieAnimation) -> Rect2:
	var scaled := _lottie_base_size(la) * la.scale
	return Rect2(-scaled * 0.5, scaled)

func _lottie_size_world(la: LottieAnimation) -> Vector2:
	# Default to top-left model for size
	return _lottie_local_rect_top_left(la).size

func _hit_node_oriented(node: Node2D, world_pos: Vector2) -> bool:
	var la := _extract_lottie(node)
	if la:
		# Use canvas transform and polygon hit test in screen-space (robust to zoom/rotation)
		var corners = _lottie_screen_corners(la)
		var screen_pos := _world_to_screen(world_pos)
		var poly: PackedVector2Array = PackedVector2Array(corners)
		return Geometry2D.is_point_in_polygon(screen_pos, poly)
	# Fallback AABB for generic Node2D
	var screen_pos := _world_to_screen(world_pos)
	var node_screen := _world_to_screen(node.global_position)
	return Rect2(node_screen - Vector2(64,64), Vector2(128,128)).has_point(screen_pos)

# Compute the four on-screen corners of a LottieAnimation's displayed box using its canvas transform.
func _lottie_screen_corners(la: LottieAnimation) -> Array[Vector2]:
	var base_size := _lottie_base_size(la)
	var scaled_size := base_size * la.scale
	var half := scaled_size * 0.5
	var local_corners = [
		-half,                              # TL in local (Node2D) space
		Vector2(half.x, -half.y),          # TR
		half,                               # BR
		Vector2(-half.x, half.y)           # BL
	]
	var xf := la.get_global_transform_with_canvas()
	var out: Array[Vector2] = []
	for p in local_corners:
		# In Godot 4.x Transform2D multiplication operator applies the transform to a Vector2
		out.append(xf * p)
	return out

func _sync_enabler_rect(enabler: VisibleOnScreenEnabler2D, la: LottieAnimation) -> void:
	var size := Vector2.ZERO
	if la.is_fit_into_box():
		size = Vector2(la.get_fit_box_size()) * la.scale
	elif la.texture:
		size = Vector2(la.texture.get_width(), la.texture.get_height()) * la.scale
	if size == Vector2.ZERO:
		size = Vector2(256, 256)
	
	# LottieAnimation is always at (0,0) relative to parent
	# Create rect centered on (0,0)
	var rect_pos := -(size * 0.5)
	enabler.rect = Rect2(rect_pos, size)

func _update_all_enabler_rects() -> void:
	for w in assets.get_children():
		if w is VisibleOnScreenEnabler2D and w.get_child_count() > 0 and w.get_child(0) is LottieAnimation:
			_sync_enabler_rect(w, w.get_child(0))

func _update_enabler_rect_for(la: LottieAnimation) -> void:
	if la and la.get_parent() is VisibleOnScreenEnabler2D:
		_sync_enabler_rect(la.get_parent(), la)

# FileDialog callbacks for Import and Save
func _on_import_folder_selected(path: String) -> void:
	_import_base_path = path
	_save_config()
	# Import path updated silently
	_update_status("✅ Lottie folder set to: " + path.get_file())
	# Reopen the import popup to show the updated path
	call_deferred("_show_import_lottie_popup")

func _show_import_lottie_popup() -> void:
	# Background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	_ui.add_child(overlay)
	
	# Center container for the popup
	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	overlay.add_child(center)
	
	# Main popup panel
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(340, 160)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.17, 0.98)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.35, 0.5, 0.85, 0.5)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.shadow_size = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", panel_style)
	
	center.add_child(popup)
	
	# Content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Import Lottie"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Path info
	var path_label = Label.new()
	path_label.text = "Folder:"
	path_label.add_theme_font_size_override("font_size", 10)
	path_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(path_label)
	
	var path_display = Label.new()
	if _import_base_path != "":
		path_display.text = _import_base_path
		path_display.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	else:
		path_display.text = "Not set - will browse filesystem"
		path_display.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	path_display.add_theme_font_size_override("font_size", 10)
	path_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(path_display)
	
	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Buttons
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 8)
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)
	
	# Change folder button
	var btn_change = Button.new()
	btn_change.text = "Set Folder"
	btn_change.custom_minimum_size = Vector2(90, 32)
	btn_change.add_theme_font_size_override("font_size", 11)
	btn_change.pressed.connect(func():
		overlay.queue_free()
		_file_dialog.clear_filters()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_file_dialog.title = "Select Folder with Lottie Files"
		_file_dialog.popup_centered(Vector2(900, 600))
	)
	btn_container.add_child(btn_change)
	
	# Cancel button
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(90, 32)
	btn_cancel.add_theme_font_size_override("font_size", 11)
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
	)
	btn_container.add_child(btn_cancel)
	
	# Open button
	var btn_open = Button.new()
	btn_open.text = "Browse"
	btn_open.custom_minimum_size = Vector2(90, 32)
	btn_open.add_theme_font_size_override("font_size", 11)
	
	var open_style = StyleBoxFlat.new()
	open_style.bg_color = Color(0.5, 0.4, 0.9, 0.8)
	open_style.corner_radius_top_left = 4
	open_style.corner_radius_top_right = 4
	open_style.corner_radius_bottom_left = 4
	open_style.corner_radius_bottom_right = 4
	btn_open.add_theme_stylebox_override("normal", open_style)
	
	var open_hover = StyleBoxFlat.new()
	open_hover.bg_color = Color(0.6, 0.5, 1.0, 0.9)
	open_hover.corner_radius_top_left = 4
	open_hover.corner_radius_top_right = 4
	open_hover.corner_radius_bottom_left = 4
	open_hover.corner_radius_bottom_right = 4
	btn_open.add_theme_stylebox_override("hover", open_hover)
	
	btn_open.pressed.connect(func():
		overlay.queue_free()
		# Open file picker in the set folder or default
		_file_dialog.clear_filters()
		_file_dialog.add_filter("*.json", "Lottie Animation")
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.title = "Select Lottie Animation"
		if _import_base_path != "":
			_file_dialog.current_dir = _import_base_path
		_file_dialog.popup_centered(Vector2i(800, 600))
	)
	btn_container.add_child(btn_open)
	
	# Close on overlay click
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)

func _on_save_folder_selected(path: String) -> void:
	_save_base_path = path
	_save_config()
	# Save path updated silently
	# Now actually save
	_save_scene()

func _show_save_confirmation() -> void:
	# Background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	_ui.add_child(overlay)
	
	# Center container for the popup
	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	overlay.add_child(center)
	
	# Main popup panel
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(320, 160)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.17, 0.98)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.35, 0.5, 0.85, 0.5)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.shadow_size = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", panel_style)
	
	center.add_child(popup)
	
	# Content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Save Scene"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Path info
	var path_label = Label.new()
	path_label.text = "Location:"
	path_label.add_theme_font_size_override("font_size", 10)
	path_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(path_label)
	
	var path_display = Label.new()
	if _save_base_path != "":
		path_display.text = _save_base_path
		path_display.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	else:
		path_display.text = SCENES_DIR + " (default)"
		path_display.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
	path_display.add_theme_font_size_override("font_size", 10)
	path_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(path_display)
	
	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Buttons
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 8)
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)
	
	# Change folder button
	var btn_change = Button.new()
	btn_change.text = "Change"
	btn_change.custom_minimum_size = Vector2(80, 32)
	btn_change.add_theme_font_size_override("font_size", 11)
	btn_change.pressed.connect(func():
		overlay.queue_free()
		_save_dialog.popup_centered(Vector2(900, 600))
	)
	btn_container.add_child(btn_change)
	
	# Cancel button
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(80, 32)
	btn_cancel.add_theme_font_size_override("font_size", 11)
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
	)
	btn_container.add_child(btn_cancel)
	
	# Save button
	var btn_save = Button.new()
	btn_save.text = "Save"
	btn_save.custom_minimum_size = Vector2(80, 32)
	btn_save.add_theme_font_size_override("font_size", 11)
	
	var save_style = StyleBoxFlat.new()
	save_style.bg_color = Color(0.3, 0.7, 0.45, 0.8)
	save_style.corner_radius_top_left = 4
	save_style.corner_radius_top_right = 4
	save_style.corner_radius_bottom_left = 4
	save_style.corner_radius_bottom_right = 4
	btn_save.add_theme_stylebox_override("normal", save_style)
	
	var save_hover = StyleBoxFlat.new()
	save_hover.bg_color = Color(0.35, 0.8, 0.5, 0.9)
	save_hover.corner_radius_top_left = 4
	save_hover.corner_radius_top_right = 4
	save_hover.corner_radius_bottom_left = 4
	save_hover.corner_radius_bottom_right = 4
	btn_save.add_theme_stylebox_override("hover", save_hover)
	
	btn_save.pressed.connect(func():
		overlay.queue_free()
		_save_scene()
	)
	btn_container.add_child(btn_save)
	
	# Close on overlay click
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
 
