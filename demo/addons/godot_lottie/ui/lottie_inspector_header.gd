@tool
extends VBoxContainer

var target_node: Node = null
@onready var info_tree: Tree = $Info

func _ready():
	_refresh_info()

func set_target_node(node: Node):
	target_node = node
	_refresh_info()

func _refresh_info():
	if info_tree == null:
		return
	info_tree.clear()
	var root = info_tree.create_item()
	var animations_item := info_tree.create_item(root)
	animations_item.set_text(0, "Animations")
	var states_item := info_tree.create_item(root)
	states_item.set_text(0, "State Machines")

	if target_node == null:
		return
	if not target_node.has_method("get_animation_path"):
		return
	var path: String = target_node.get_animation_path()
	if path.is_empty():
		return
	if path.get_file().to_lower().ends_with(".lottie"):
		var zr := ZIPReader.new()
		if zr.open(path) == OK:
			var manifest_path := "manifest.json"
			var files: PackedStringArray = zr.get_files()
			for f in files:
				if f.to_lower().ends_with("manifest.json"):
					manifest_path = f
					break
			if files.find(manifest_path) != -1:
				var bytes: PackedByteArray = zr.read_file(manifest_path)
				var text := bytes.get_string_from_utf8()
				var manifest := JSON.parse_string(text)
				if typeof(manifest) == TYPE_DICTIONARY:
					if manifest.has("animations") and typeof(manifest["animations"]) == TYPE_ARRAY:
						for anim in manifest["animations"]:
							var it = info_tree.create_item(animations_item)
							var nm = anim.get("id", anim.get("name", "animation"))
							it.set_text(0, str(nm))
							if anim.has("duration"):
								it.set_text(1, str(anim["duration"]))
					if manifest.has("stateMachines") and typeof(manifest["stateMachines"]) == TYPE_ARRAY:
						for sm in manifest["stateMachines"]:
							var sit = info_tree.create_item(states_item)
							var sm_name = sm.get("name", "state_machine")
							sit.set_text(0, str(sm_name))
							var states = sm.get("states", [])
							sit.set_text(1, str(len(states)) + " states")
			zr.close()
