extends Node
## Offline actual-class checks only, no Toy scores or external calls.
var checks := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error("ranking QA failed: " + label)
		get_tree().quit(2)
	checks += 1
	print("[ranking-qa] PASS ", label)
func _ready() -> void:
	Game.autotest = true
	Online.server_url = ""
	Online.local_runs = []
	Game.new_run()
	Online.start_run()
	var stats := {"difficulty": "normal", "rating": "S"}
	var first := await Online.finish_run(81000, stats)
	var second := await Online.finish_run(81000, stats)
	check(Online.local_runs.size() == 1, "repeated results do not duplicate local run")
	check(first == second, "repeat result is cached")
	check(not Online.toy_mode(), "native runtime does not claim Toy support")
	check(not Online.online(), "native defaults offline")
	var screen := LeaderboardScreen.new()
	add_child(screen)
	await get_tree().process_frame
	check(screen._tab == "local", "native defaults to clearly labeled local tab")
	check(screen._list.get_child_count() > 0, "local score visible")
	screen._switch("global")
	await get_tree().process_frame
	check(screen._list.get_child_count() == 1, "native global tab explains platform requirement")
	screen.queue_free()
	await get_tree().process_frame
	Game.run.run_ms = 81000
	Game.run.rescued = true
	var result := Results.new()
	result.data = {"success": true}
	add_child(result)
	await get_tree().process_frame
	check(result._lb_line2.text.contains("本机"), "native result says only local record")
	check(not is_instance_valid(result._lb_retry), "native does not show Toy retry")
	check(Online.local_runs.size() == 1, "results reopening keeps local score once")
	result.queue_free()
	await get_tree().process_frame
	Online.set_script(load("res://scripts/test/qa/mock_toy_online.gd"))
	Online.local_runs = []
	Online.start_run()
	var toy_screen := LeaderboardScreen.new()
	add_child(toy_screen)
	for i in 4:
		await get_tree().process_frame
	check(toy_screen._tab == "global", "offline Toy mock selects public tab")
	check(toy_screen._list.get_child_count() == 2, "offline Toy mock displays two public rows")
	check(toy_screen._nick_label.text == "离线模拟账号", "offline Toy mock displays platform nickname")
	toy_screen.queue_free()
	await get_tree().process_frame
	var toy_result := Results.new()
	toy_result.data = {"success": true}
	add_child(toy_result)
	for i in 4:
		await get_tree().process_frame
	check(toy_result._lb_line2.text.contains("登录"), "offline Toy mock explains login error")
	check(toy_result._lb_retry.visible, "offline Toy mock offers explicit retry")
	check(Online.local_runs.size() == 1, "failed Toy mock submit keeps local record")
	toy_result.queue_free()
	await get_tree().process_frame
	print("[ranking-qa] PASS ", checks, " assertions; offline native and SDK mock, no live Toy calls")
	get_tree().quit(0)
