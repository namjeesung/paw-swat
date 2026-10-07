extends Node
## Headless text/font layout measurement of production TipCards; no screenshot or rendering claim.
var checks: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	call_deferred("_run")

func check(name: String, passed: bool, detail: Dictionary = {}) -> void:
	checks.append({"name": name, "passed": passed, "details": detail})
	print("[heal-tip-metrics] ", "PASS " if passed else "FAIL ", name, " ", JSON.stringify(detail))

func _run() -> void:
	var card := TipCards.new()
	add_child(card)
	card.set_process(false)
	Game.current = null
	var limits := {"easy": 1, "normal": 2, "hard": 3, "insane": 4}
	for diff: String in limits:
		Game.set_difficulty(diff, false)
		var raw := String(Tips.get_tip("heal")[2])
		card._body.text = Tips.rich(raw)
		await get_tree().process_frame
		await get_tree().process_frame
		var height := card._body.get_content_height()
		check("%s_heal_tip_fits_production_body" % diff, height > 0 and height <= card._body.size.y, {"content_height": height, "body_height": card._body.size.y, "body_width": card._body.size.x, "font_size": card._body.get_theme_font_size("normal_font_size"), "bold_size": card._body.get_theme_font_size("bold_font_size"), "lines": card._body.get_line_count(), "plain_text": card._body.get_parsed_text()})
		check("%s_fallback_tip_has_selected_budget" % diff, raw.contains("{%d件}" % limits[diff]))
	var captured := Level.new()
	captured.heal_drop_limit = 2
	Game.current = captured
	Game.set_difficulty("insane", false)
	var captured_text := String(Tips.get_tip("heal")[2])
	check("tip_reads_captured_run_budget", captured_text.contains("{2件}") and not captured_text.contains("{4件}"), {"tip": captured_text, "selected_difficulty": Game.difficulty, "captured_limit": captured.heal_drop_limit})
	Game.current = null
	captured.free()
	var failed := checks.filter(func(c: Dictionary): return not c.passed)
	var path := ProjectSettings.globalize_path("user://heal-tip-metrics-report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "checks": checks, "passed": failed.is_empty(), "failed": failed.size(), "mode": "Headless production RichTextLabel/TextServer font metrics; no rendered screenshot"}, "\t"))
	file.close()
	print("[heal-tip-metrics] RESULT ", JSON.stringify({"checks": checks.size(), "failed": failed.size(), "passed": failed.is_empty(), "report": path}))
	card.queue_free()
	Sfx.music("")
	await get_tree().process_frame
	get_tree().quit(0 if failed.is_empty() else 1)
