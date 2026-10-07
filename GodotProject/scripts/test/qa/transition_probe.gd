extends Node

func _ready() -> void:
	Online.server_url = ""
	call_deferred("_run")

func _run() -> void:
	var ts := TextServerManager.get_primary_interface()
	for method in ts.get_method_list():
		if method.name in ["font_render_glyph", "font_get_glyph_index", "font_has_char"]:
			print(method)
	for spec in [[Style.title_font(), "僵尸鼠来袭！", 110, 22], [Style.num_font(), "FIRE!", 220, 40]]:
		for pass_index in 2:
			var start := Time.get_ticks_usec()
			var max_us := 0
			var font: Font = spec[0]
			for character in String(spec[1]):
				for rid in font.get_rids():
					if not ts.font_has_char(rid, character.unicode_at(0)):
						continue
					var glyph := ts.font_get_glyph_index(rid, int(spec[2]), character.unicode_at(0), 0)
					for outline in [0, int(spec[3])]:
						var one := Time.get_ticks_usec()
						ts.font_render_glyph(rid, Vector2i(spec[2], outline), glyph)
						max_us = maxi(max_us, Time.get_ticks_usec() - one)
					break
			print("[transition-probe] text=%s pass=%d total_us=%d max_glyph_us=%d" % [spec[1], pass_index, Time.get_ticks_usec() - start, max_us])
	get_tree().quit()
