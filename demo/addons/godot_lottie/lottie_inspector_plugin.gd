@tool
extends EditorInspectorPlugin

func _can_handle(object):
	return object.get_class() == "LottieAnimation" or object is LottieAnimationWrapper

func _parse_begin(object):
	# Add custom header
	var header = preload("res://addons/godot_lottie/ui/lottie_inspector_header.tscn").instantiate()
	add_custom_control(header)
	if header.has_method("set_target_node"):
		header.set_target_node(object)

func _parse_category(object, category):
	pass

func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	# Custom property editors can be added here
	return false
