extends SceneTree
## Portable external bootstrap. Production classes/resources are loaded from --main-pack.
## Usage: godot --headless --main-pack Web/index.pck --script /path/packed_qa_driver.gd -- --qa-harness=/path/NodeHarness.gd
func _initialize() -> void:
	_boot.call_deferred()

func _boot() -> void:
	var harness_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-harness="):
			harness_path = arg.substr(13)
	if harness_path == "":
		print("[packed-qa] ERROR: pass --qa-harness=/absolute/path/to/NodeHarness.gd")
		quit(2)
		return
	var script = load(harness_path)
	if script == null or not script.can_instantiate():
		print("[packed-qa] ERROR: external Node harness could not be loaded")
		quit(2)
		return
	var harness: Node = script.new()
	print("[packed-qa] Using external Node harness; production res:// resources come from the loaded PCK")
	root.add_child(harness)
