extends SceneTree
## External QA bootstrap: production classes/resources come from --main-pack, not source project.
func _initialize() -> void:
	_boot.call_deferred()

func _boot() -> void:
	var harness_path: String = get_script().resource_path.get_base_dir().path_join("../../GodotProject/scripts/test/qa/shield_regression.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--harness="):
			harness_path = arg.substr(10)
	var script = load(harness_path)
	if script == null:
		print("[packed-qa] FAILED to load external Node harness")
		quit(2)
		return
	var harness: Node = script.new()
	root.add_child(harness)
