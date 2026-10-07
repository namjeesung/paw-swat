extends SceneTree
func _initialize() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var harness_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-harness="):
			harness_path = arg.substr(18)
	var script = load(harness_path)
	if script == null or not script.can_instantiate():
		quit(2)
		return
	root.add_child(script.new())
