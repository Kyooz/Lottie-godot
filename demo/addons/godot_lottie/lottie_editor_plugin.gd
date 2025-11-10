@tool
extends EditorPlugin

var lottie_dock: Control
var inspector_plugin: EditorInspectorPlugin

func _enter_tree():
	# Add custom node type
	var icon: Texture2D = null
	# Prefer the project icon provided at src/lottieico.svg
	var svg_path := "res://src/lottieico.svg"
	# Try to load SVG icon at runtime if a loader is available
	if ResourceLoader.exists(svg_path, "Texture2D"):
		icon = load(svg_path)
	# Fallback to a built-in Node2D icon if SVG isn't supported
	if icon == null:
		icon = get_editor_interface().get_base_control().get_theme_icon("Node2D", "EditorIcons")

	add_custom_type(
		"LottieAnimation",
		"Node2D",
		preload("res://addons/godot_lottie/lottie_animation_script.gd"),
		icon
	)
	
	# Keep the inspector native and clean: disable custom dock and header for now.
	# lottie_dock = preload("res://addons/godot_lottie/ui/lottie_dock.tscn").instantiate()
	# add_control_to_dock(DOCK_SLOT_RIGHT_UL, lottie_dock)
	# inspector_plugin = preload("res://addons/godot_lottie/lottie_inspector_plugin.gd").new()
	# add_inspector_plugin(inspector_plugin)
	
	print("Godot Lottie plugin enabled")

func _exit_tree():
	# Remove custom node type
	remove_custom_type("LottieAnimation")
	
	# Remove dock / inspector plugin if ever enabled above
	if lottie_dock:
		remove_control_from_docks(lottie_dock)
		lottie_dock.queue_free()

	if inspector_plugin:
		remove_inspector_plugin(inspector_plugin)
	
	print("Godot Lottie plugin disabled")

func _handles(object):
	return object is LottieAnimation

func _make_visible(visible):
	if lottie_dock:
		lottie_dock.visible = visible
