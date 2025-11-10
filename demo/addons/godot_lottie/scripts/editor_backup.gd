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
var _scene_combo: OptionButton
var _file_dialog: FileDialog
var _status_bar: HBoxContainer
var _camera: Camera2D
var _overlay: Node2D

# Selection & Interaction
var _selected: Node2D = null
var _dragging := false
var _drag_offset := Vector2.ZERO
var _show_properties := false
var _last_mouse_screen := Vector2.ZERO
var _hover_node: Node2D = null
var _clipboard: Node2D = null

# Editor Settings
const SELECTION_COLOR := Color(0.3, 0.7, 1.0, 0.8)
const HOVER_COLOR := Color(1.0, 1.0, 0.3, 0.6)
const MIN_PICK_SCREEN_PX := 12  # tamanho mínimo clicável em pixels na tela

# Paths
const SCENES_DIR := "res://addons/scenes"
const USER_SCENES_DIR := "user://scenes"

# Theme colors - Modern minimalist
const THEME_DARK_BG := Color(0.12, 0.12, 0.14)
const THEME_PANEL_BG := Color(0.16, 0.16, 0.18)
const THEME_ACCENT := Color(0.4, 0.65, 1.0)
const THEME_TEXT := Color(0.92, 0.92, 0.94)

func _ready() -> void:
	_ensure_dirs()
	_make_camera()
	_build_ui()
	_refresh_scene_list()
	set_process(true)

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(USER_SCENES_DIR)

func _make_camera() -> void:
	_camera = Camera2D.new()
	_camera.zoom = Vector2(1, 1)
	_camera.position = Vector2.ZERO
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(_camera)
	_camera.enabled = true
	_camera.call_deferred("make_current")
	
	# Create overlay for drawing
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	add_child(_overlay)
	_overlay.z_index = 1000
	_overlay.draw.connect(_on_overlay_draw)

func _screen_to_world(p: Vector2) -> Vector2:
	return _camera.position + (p * _camera.zoom)

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

func _get_next_zoom_level(current: int, zoom_in: bool) -> int:
	# Zoom levels: 100%, 125%, 150%, 175%, 200%, 250%, 300%, 400%, 500%, 600%, 800%, 1000%
	var zoom_levels = [100, 125, 150, 175, 200, 250, 300, 400, 500, 600, 800, 1000]
	
	# Find current index or closest match
	var current_idx = 0
	var closest_diff = 999999
	for i in range(zoom_levels.size()):
		var diff = abs(zoom_levels[i] - current)
		if diff < closest_diff:
			closest_diff = diff
			current_idx = i
	
	if zoom_in:
		# Zoom in = menor porcentagem = mais próximo = índice menor
		if current_idx > 0:
			return zoom_levels[current_idx - 1]
		return zoom_levels[0]  # Min 100%
	else:
		# Zoom out = maior porcentagem = mais longe = índice maior
		if current_idx < zoom_levels.size() - 1:
			return zoom_levels[current_idx + 1]
		return zoom_levels[-1]  # Max 1000%

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
	
	# Right properties panel
	var right = PanelContainer.new()
	_ui.add_child(right)
	_apply_panel_theme(right)
	right.anchor_right = 1.0
	right.anchor_left = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = -320
	right.offset_top = 48
	right.offset_bottom = -32
	
	var scroll = ScrollContainer.new()
	right.add_child(scroll)
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
	
	# File dialog
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.json,*.lottie ; Lottie files"])
	_ui.add_child(_file_dialog)
	
	# Signals
	btn_new.pressed.connect(_new_scene)
	btn_save.pressed.connect(_save_scene)
	btn_import.pressed.connect(func(): _file_dialog.popup_centered(Vector2(900, 600)))
	_scene_combo.item_selected.connect(func(_i): _load_selected_scene())
	_file_dialog.file_selected.connect(_import_lottie)

func _make_styled_button(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(90, 32)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = color * Color(0.6, 0.6, 0.6, 0.8)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = color * Color(0.9, 0.9, 0.9, 1.0)
	style_hover.corner_radius_top_left = 6
	style_hover.corner_radius_top_right = 6
	style_hover.corner_radius_bottom_left = 6
	style_hover.corner_radius_bottom_right = 6
	style_hover.content_margin_left = 16
	style_hover.content_margin_right = 16
	style_hover.content_margin_top = 6
	style_hover.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = color * Color(0.4, 0.4, 0.4, 0.9)
	style_pressed.corner_radius_top_left = 6
	style_pressed.corner_radius_top_right = 6
	style_pressed.corner_radius_bottom_left = 6
	style_pressed.corner_radius_bottom_right = 6
	style_pressed.content_margin_left = 16
	style_pressed.content_margin_right = 16
	style_pressed.content_margin_top = 6
	style_pressed.content_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_color_override("font_color", THEME_TEXT)
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
		# Header
		var header = _make_section_header("PROPERTIES")
		_prop_panel.add_child(header)
		
		# Node name
		var name_section = _make_property_section("Node Name")
		_prop_panel.add_child(name_section)
		var name_label = Label.new()
		name_label.text = _selected.name
		name_label.add_theme_color_override("font_color", THEME_ACCENT)
		name_section.add_child(name_label)
		var btn_rename = _make_small_button("Rename")
		btn_rename.pressed.connect(_rename_selected)
		name_section.add_child(btn_rename)
		
		# Animation path
		if la.has_method("get_animation_path"):
			var path_section = _make_property_section("Animation File")
			_prop_panel.add_child(path_section)
			var path_label = Label.new()
			var full_path = la.get_animation_path()
			path_label.text = full_path.get_file() if full_path else "(none)"
			path_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			path_section.add_child(path_label)
		
		# Transform section
		var transform_header = _make_section_header("TRANSFORM")
		_prop_panel.add_child(transform_header)
		
		var pos_section = _make_property_section("Position")
		_prop_panel.add_child(pos_section)
		pos_section.add_child(_make_prop_vec2_inline(_selected.global_position, func(v):
			_selected.global_position = v
		))
		
		var scale_section = _make_property_section("Scale")
		_prop_panel.add_child(scale_section)
		scale_section.add_child(_make_prop_vec2_inline(la.scale, func(v):
			la.scale = v
			_update_enabler_rect_for(la)
		))
		
		var rotation_section = _make_property_section("Rotation")
		_prop_panel.add_child(rotation_section)
		rotation_section.add_child(_make_prop_angle_inline(rad_to_deg(la.rotation), func(deg):
			la.rotation = deg_to_rad(deg)
		))
		
		# Animation section
		var anim_header = _make_section_header("ANIMATION")
		_prop_panel.add_child(anim_header)
		
		_prop_panel.add_child(_make_prop_check("Playing", la.playing, func(v):
			la.playing = v
			if v:
				la.play()
			else:
				la.pause()
		))
		_prop_panel.add_child(_make_prop_check("Looping", la.looping, func(v): la.looping = v))
		
		var speed_section = _make_property_section("Speed")
		_prop_panel.add_child(speed_section)
		speed_section.add_child(_make_prop_slider_inline(0.05, 4.0, 0.01, la.speed, func(v): la.speed = v))
		
		# Visual section
		var visual_header = _make_section_header("VISUAL")
		_prop_panel.add_child(visual_header)
		
		var color_section = _make_property_section("Modulate")
		_prop_panel.add_child(color_section)
		color_section.add_child(_make_prop_color_inline(la.modulate, func(c): la.modulate = c))
		
		# Actions
		_prop_panel.add_child(_make_separator_horizontal())
		var btn_delete = _make_small_button("Delete Node")
		btn_delete.modulate = Color(1.0, 0.5, 0.5)
		btn_delete.pressed.connect(func():
			if _selected:
				_selected.queue_free()
				_selected = null
				_show_properties = false
				_build_property_panel()
		)
		_prop_panel.add_child(btn_delete)
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
		controls.text = "CONTROLS:\n• Left Click + Drag: Move node\n• Right Click: Select & edit\n• Mouse Wheel: Zoom\n• WASD/Arrows: Pan camera\n• Ctrl+C: Copy node\n• Ctrl+V: Paste node\n• Ctrl+D: Duplicate\n• Delete: Remove node"
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
		
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			# Zoom in (aproximar) mantendo o ponto sob o mouse fixo
			var mouse := mb.position
			var old_zoom: Vector2 = _camera.zoom
			var world_before := _camera.position + (mouse * old_zoom)
			var current_zoom_percent = roundi(100.0 / old_zoom.x)
			var new_zoom_percent = _get_next_zoom_level(current_zoom_percent, true)
			var new_zoom_scalar = 100.0 / float(new_zoom_percent)
			var new_zoom := Vector2(new_zoom_scalar, new_zoom_scalar)
			_camera.zoom = new_zoom
			_camera.position = world_before - (mouse * _camera.zoom)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			# Zoom out (afastar) mantendo o ponto sob o mouse fixo
			var mouse := mb.position
			var old_zoom: Vector2 = _camera.zoom
			var world_before := _camera.position + (mouse * old_zoom)
			var current_zoom_percent = roundi(100.0 / old_zoom.x)
			var new_zoom_percent = _get_next_zoom_level(current_zoom_percent, false)
			var new_zoom_scalar = 100.0 / float(new_zoom_percent)
			var new_zoom := Vector2(new_zoom_scalar, new_zoom_scalar)
			_camera.zoom = new_zoom
			_camera.position = world_before - (mouse * _camera.zoom)
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
		if _dragging:
			_drag_to(mm.position)
	elif event is InputEventKey:
		var ik := event as InputEventKey
		if ik.pressed and not ik.echo:
			if ik.keycode == KEY_DELETE and _selected:
				_selected.queue_free()
				_selected = null
				_show_properties = false
				_build_property_panel()
			elif ik.ctrl_pressed and ik.keycode == KEY_D and _selected:
				_duplicate_selected()
			elif ik.ctrl_pressed and ik.keycode == KEY_C and _selected:
				_copy_selected()
			elif ik.ctrl_pressed and ik.keycode == KEY_V:
				_paste_selected()

func _update_hover(mouse_pos: Vector2) -> void:
	if _dragging:
		_hover_node = null
		return
	_hover_node = _pick_at_screen(mouse_pos)

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
	var world = _screen_to_world(mouse_pos)
	var picked = _pick_at_screen(mouse_pos)
	if picked:
		_selected = picked
		_show_properties = true
		_dragging = true
		_drag_offset = _selected.global_position - world
		_build_property_panel()
	else:
		# Deselect if clicking on empty space
		_selected = null
		_show_properties = false
		_dragging = false
		_build_property_panel()

func _drag_to(mouse_pos: Vector2) -> void:
	if not _selected:
		return
	var world = _screen_to_world(mouse_pos)
	var new_pos = world + _drag_offset
	_selected.global_position = new_pos

func _end_drag() -> void:
	_dragging = false

func _pick_at(world_pos: Vector2) -> Node2D:
	# Use node bounds for accurate picking
	var candidates := []
	for n in assets.get_children():
		if n is Node2D:
			var bounds = _node_bounds(n)
			# Primeiro tenta o bounds real
			var hit := bounds.has_point(world_pos)
			if not hit:
				# Com zoom distante o objeto pode ficar menor que alguns pixels;
				# garanta uma área mínima clicável equivalente a MIN_PICK_SCREEN_PX.
				var min_world := Vector2(MIN_PICK_SCREEN_PX, MIN_PICK_SCREEN_PX) * _camera.zoom
				var ensured_size := Vector2(max(bounds.size.x, min_world.x), max(bounds.size.y, min_world.y))
				var expanded := Rect2(bounds.get_center() - ensured_size * 0.5, ensured_size)
				hit = expanded.has_point(world_pos)
			if hit:
				candidates.append(n)
	
	# Return closest if multiple candidates
	if candidates.size() == 0:
		return null
	elif candidates.size() == 1:
		return candidates[0]
	else:
		var closest = candidates[0]
		var closest_dist = (closest as Node2D).global_position.distance_to(world_pos)
		for c in candidates:
			var dist = (c as Node2D).global_position.distance_to(world_pos)
			if dist < closest_dist:
				closest = c
				closest_dist = dist
		return closest

func _select_at(screen_pos: Vector2) -> void:
	_selected = _pick_at_screen(screen_pos)

func _pick_at_screen(screen_pos: Vector2) -> Node2D:
	# Convert node world AABBs to screen-space rectangles and test there; improves hit at far zoom.
	var candidates: Array = []
	for n in assets.get_children():
		if n is Node2D:
			var rects := _node_candidate_rects(n)
			var hit := false
			var sr: Rect2
			for wb in rects:
				sr = Rect2((wb.position - _camera.position) / _camera.zoom, wb.size / _camera.zoom)
				if sr.has_point(screen_pos):
					hit = true; break
			if not hit:
				var min_size := Vector2(MIN_PICK_SCREEN_PX, MIN_PICK_SCREEN_PX)
				# use last computed sr (from loop) to expand
				var ensured := Vector2(max(sr.size.x, min_size.x), max(sr.size.y, min_size.y))
				var expanded := Rect2(sr.get_center() - ensured * 0.5, ensured)
				hit = expanded.has_point(screen_pos)
			if hit:
				candidates.append(n)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]
	var world_pos := _screen_to_world(screen_pos)
	var closest = candidates[0]
	var closest_dist = (closest as Node2D).global_position.distance_to(world_pos)
	for c in candidates:
		var dist = (c as Node2D).global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest = c; closest_dist = dist
	return closest

# Scene load/save ------------------------------------------------------------
func _new_scene() -> void:
	var dlg = AcceptDialog.new()
	dlg.title = "New Scene"
	var vbox = VBoxContainer.new()
	dlg.add_child(vbox)
	var label = Label.new()
	label.text = "Scene name:"
	vbox.add_child(label)
	var le = LineEdit.new()
	le.text = "new_scene"
	le.custom_minimum_size = Vector2(250, 0)
	vbox.add_child(le)
	dlg.confirmed.connect(func():
		for c in assets.get_children():
			assets.remove_child(c)
			c.queue_free()
		_selected = null
		_show_properties = false
		_build_property_panel()
		_update_status("New scene created: " + le.text)
		# Save immediately with the given name
		_save_scene_with_name(le.text)
	)
	_ui.add_child(dlg)
	dlg.popup_centered(Vector2(320, 140))

func _save_scene() -> void:
	if assets.get_child_count() == 0:
		_update_status("Nothing to save")
		return
	_save_scene_with_name("scene_%d" % Time.get_unix_time_from_system())

func _save_scene_with_name(scene_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENES_DIR))
	
	var root_scene := Node2D.new()
	root_scene.name = "Scene"
	
	var container := Node.new()
	container.name = "Assets"
	root_scene.add_child(container)
	container.owner = root_scene
	
	for n in assets.get_children():
		if n is VisibleOnScreenEnabler2D:
			var dup = n.duplicate()
			container.add_child(dup)
			dup.owner = root_scene
			for child in dup.get_children():
				child.owner = root_scene
		elif n is LottieAnimation:
			var wrap = VisibleOnScreenEnabler2D.new()
			wrap.name = n.name + "Wrapper"
			wrap.global_position = n.global_position
			var la_dup = n.duplicate()
			wrap.add_child(la_dup)
			container.add_child(wrap)
			wrap.owner = root_scene
			la_dup.owner = root_scene
			_sync_enabler_rect(wrap, la_dup)
	
	var scene := PackedScene.new()
	scene.pack(root_scene)
	if not scene_name.ends_with(".tscn"):
		scene_name += ".tscn"
	var path = SCENES_DIR + "/" + scene_name
	var err = ResourceSaver.save(scene, path)
	if err != OK:
		_update_status("Save failed: " + str(err))
		print("[Editor] Save failed:", err)
	else:
		_update_status("Saved: " + scene_name)
		print("[Editor] Saved:", path)
	_refresh_scene_list()

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
	if not meta_str.begins_with("res://"):
		_update_status("Cannot delete user:// scenes")
		return
	
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
	# Only res:// scenes from SCENES_DIR
	var ra = DirAccess.open(SCENES_DIR)
	if ra:
		ra.list_dir_begin()
		var g = ra.get_next()
		while g != "":
			if g.ends_with(".tscn") and not g.begins_with("."):
				_scene_combo.add_item(g)
				_scene_combo.set_item_metadata(idx, SCENES_DIR + "/" + g)
				idx += 1
			g = ra.get_next()
		ra.list_dir_end()

func _load_selected_scene() -> void:
	var meta = _scene_combo.get_selected_metadata()
	if meta == null:
		return
	
	var ps: PackedScene = ResourceLoader.load(meta)
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
			assets.add_child(c)
	else:
		for c in inst.get_children():
			inst.remove_child(c)
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
	var wrapper := VisibleOnScreenEnabler2D.new()
	wrapper.name = "Visible"
	
	var la := LottieAnimation.new()
	la.name = "LottieAnimation"
	la.set_animation_path(path)
	la.set_fit_into_box(true)
	if la.has_method("set_fit_box_size"):
		la.set_fit_box_size(Vector2i(256, 256))
	
	# Always spawn at center of viewport
	var viewport_size = get_viewport().get_visible_rect().size
	var center_screen = viewport_size * 0.5
	wrapper.global_position = _screen_to_world(center_screen)
	
	assets.add_child(wrapper)
	wrapper.add_child(la)
	
	if wrapper.has_method("set"):
		wrapper.set("enable_node_path", NodePath("LottieAnimation"))
	
	_sync_enabler_rect(wrapper, la)
	_selected = wrapper
	_show_properties = true
	_build_property_panel()
	_update_status("Imported: " + path.get_file())

func _add_empty_lottie() -> void:
	var wrapper := VisibleOnScreenEnabler2D.new()
	wrapper.name = "Visible"
	
	var la := LottieAnimation.new()
	la.name = "LottieAnimation"
	la.set_fit_into_box(true)
	if la.has_method("set_fit_box_size"):
		la.set_fit_box_size(Vector2i(256, 256))
	
	# Always spawn at center of viewport
	var viewport_size = get_viewport().get_visible_rect().size
	var center_screen = viewport_size * 0.5
	wrapper.global_position = _screen_to_world(center_screen)
	
	assets.add_child(wrapper)
	wrapper.add_child(la)
	
	if wrapper.has_method("set"):
		wrapper.set("enable_node_path", NodePath("LottieAnimation"))
	
	_sync_enabler_rect(wrapper, la)
	_selected = wrapper
	_show_properties = true
	_build_property_panel()
	_update_status("Added new Lottie node")

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
		_camera.position += (move.normalized() * 600.0 * delta) * _camera.zoom.x

func _update_camera_status() -> void:
	if _status_bar and _status_bar.get_child_count() > 0:
		var label = _status_bar.get_child(0) as Label
		if label and not _dragging:
			var zoom_percent = int(100.0 / _camera.zoom.x)
			label.text = "Zoom: %d%% | Camera: (%.0f, %.0f)" % [zoom_percent, _camera.position.x, _camera.position.y]

func _on_overlay_draw() -> void:
	if not _overlay:
		return
	
	# Draw viewport boundary
	_draw_viewport_boundary()
	
	# Draw selection highlight
	if _selected:
		var bounds = _selected_bounds()
		_overlay.draw_rect(bounds, SELECTION_COLOR, false, 2.0)
		# Draw corner handles
		_draw_handles(bounds)
	
	# Draw hover highlight
	if _hover_node and _hover_node != _selected:
		var bounds = _node_bounds(_hover_node)
		_overlay.draw_rect(bounds, HOVER_COLOR, false, 1.5)

func _draw_viewport_boundary() -> void:
	if not _overlay:
		return
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Convert viewport boundaries to world space
	var top_left_world = _camera.position
	var bottom_right_world = _camera.position + (viewport_size * _camera.zoom)
	var size_world = bottom_right_world - top_left_world
	
	# Convert back to screen space for drawing
	var top_left_screen = (top_left_world - _camera.position) / _camera.zoom
	var size_screen = size_world / _camera.zoom
	
	var viewport_rect = Rect2(top_left_screen, size_screen)
	var border_width = max(2.0, 2.0 / _camera.zoom.x)
	_overlay.draw_rect(viewport_rect, Color(0.3, 0.5, 0.8, 0.6), false, border_width)

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
	
	var size := Vector2.ZERO
	if la:
		if la.is_fit_into_box():
			size = Vector2(la.get_fit_box_size()) * la.scale
		elif la.texture:
			size = Vector2(la.texture.get_width(), la.texture.get_height()) * la.scale
	if size == Vector2.ZERO:
		size = Vector2(128, 128)
	return Rect2(node.global_position - size * 0.5, size)

# Returns possible world rects (centered and top-left anchored) for robust picking
func _node_candidate_rects(node: Node2D) -> Array:
	var la: LottieAnimation = null
	if node is VisibleOnScreenEnabler2D and node.get_child_count() > 0 and node.get_child(0) is LottieAnimation:
		la = node.get_child(0)
	elif node is LottieAnimation:
		la = node
	var rects: Array = []
	var size := Vector2.ZERO
	if la:
		if la.is_fit_into_box():
			size = Vector2(la.get_fit_box_size()) * la.scale
		elif la.texture:
			size = Vector2(la.texture.get_width(), la.texture.get_height()) * la.scale
	if size == Vector2.ZERO:
		size = Vector2(128, 128)
	# centered
	rects.append(Rect2(node.global_position - size * 0.5, size))
	# top-left
	rects.append(Rect2(node.global_position, size))
	return rects

func _sync_enabler_rect(enabler: VisibleOnScreenEnabler2D, la: LottieAnimation) -> void:
	var size := Vector2.ZERO
	if la.is_fit_into_box():
		size = Vector2(la.get_fit_box_size()) * la.scale
	elif la.texture:
		size = Vector2(la.texture.get_width(), la.texture.get_height()) * la.scale
	if size == Vector2.ZERO:
		size = Vector2(256,256)
	enabler.rect = Rect2(Vector2.ZERO, size)

func _update_all_enabler_rects() -> void:
	for w in assets.get_children():
		if w is VisibleOnScreenEnabler2D and w.get_child_count() > 0 and w.get_child(0) is LottieAnimation:
			_sync_enabler_rect(w, w.get_child(0))

func _update_enabler_rect_for(la: LottieAnimation) -> void:
	if la and la.get_parent() is VisibleOnScreenEnabler2D:
		_sync_enabler_rect(la.get_parent(), la)
