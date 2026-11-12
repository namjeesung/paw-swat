class_name LeaderboardScreen
extends Control
## 最速通关排行榜：全球榜（云端）/ 本机记录，以及“我的特警证”（昵称、恢复码、找回身份）。

var board: Control
var _list: VBoxContainer
var _status: Label
var _tab := "global"
var _tab_btns := {}
var _diff := "normal"
var _diff_btns := {}
var _nick_label: Label
var _code_label: Label


func _ready() -> void:
	Style.full_rect(self)
	Sfx.music("menu")
	var bg := Style.shader_rect("res://shaders/cork.gdshader", {"base": Color("3A4A6A")})
	add_child(bg)
	board = Control.new()
	board.anchor_left = 0.5
	board.anchor_right = 0.5
	board.anchor_top = 0.5
	board.anchor_bottom = 0.5
	board.offset_left = -960
	board.offset_right = 960
	board.offset_top = -540
	board.offset_bottom = 540
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)

	var title := Style.label("最速通关榜", 84, Pal.YELLOW, Style.title_font(), 16)
	title.position = Vector2(80, 30)
	board.add_child(title)
	var sub := Style.label("序章 · 午夜便利店 —— 用时越短排名越高（暂停时间不计）", 24, Pal.CREAM, Style.body_font(), 6)
	sub.position = Vector2(86, 140)
	board.add_child(sub)

	# 榜单
	var panel := Style.panel(Color(Pal.NAVY_DARK, 0.92), 20, 4, Pal.INK, 12)
	panel.position = Vector2(80, 190)
	panel.size = Vector2(1060, 840)
	board.add_child(panel)
	var x := 110.0
	_tab = "global" if Online.online() else "local"
	for t in [["global", "全球榜"], ["local", "本机记录"]]:
		var b := StickerButton.new(t[1], "primary" if t[0] == _tab else "secondary", 28)
		b.position = Vector2(x, 210)
		b.custom_minimum_size = Vector2(200, 60)
		b.pressed.connect(_switch.bind(t[0]))
		board.add_child(b)
		_tab_btns[t[0]] = b
		x += 220
	# 难度：每个难度单独排名
	_diff = Game.difficulty
	var dx := 572.0
	for d in Game.DIFF_ORDER:
		var db := Button.new()
		db.position = Vector2(dx, 212)
		db.custom_minimum_size = Vector2(128, 56)
		db.focus_mode = Control.FOCUS_NONE
		db.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		db.add_theme_font_override("font", Style.title_font())
		db.add_theme_font_size_override("font_size", 26)
		db.pressed.connect(func():
			Sfx.play("ui_click", -6.0)
			_diff = d
			_switch(_tab)
		)
		board.add_child(db)
		_diff_btns[d] = db
		dx += 136.0
	_status = Style.label("", 22, Color(Pal.CREAM, 0.7), Style.body_font())
	_status.position = Vector2(112, 282)
	_status.size = Vector2(1000, 32)
	board.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(100, 322)
	scroll.size = Vector2(1020, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_build_profile()
	var back := StickerButton.new("返回任务板", "secondary", 30)
	back.position = Vector2(1500, 960)
	back.custom_minimum_size = Vector2(300, 70)
	back.pressed.connect(func(): Game.goto("menu"))
	board.add_child(back)
	var play := StickerButton.new("开始挑战 ▶", "primary", 36)
	play.position = Vector2(1200, 960)
	play.custom_minimum_size = Vector2(280, 70)
	play.pressed.connect(func(): Game.goto("briefing"))
	board.add_child(play)
	Online.profile_changed.connect(_refresh_profile)
	_switch(_tab)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Game.goto("menu")


# ------------------------------------------------------------------ 我的特警证

func _build_profile() -> void:
	var card := Control.new()
	card.position = Vector2(1200, 190)
	card.size = Vector2(620, 720)
	card.rotation = deg_to_rad(1.5)
	board.add_child(card)
	var sh := Style.panel(Color(0, 0, 0, 0.3), 22)
	sh.position = Vector2(8, 12)
	sh.size = Vector2(620, 720)
	card.add_child(sh)
	var p := Style.panel(Pal.CREAM, 22, 5, Pal.INK)
	p.size = Vector2(620, 720)
	card.add_child(p)
	var head := Style.panel(Pal.NAVY, 18)
	head.position = Vector2(5, 5)
	head.size = Vector2(610, 80)
	card.add_child(head)
	var ht := Style.label("我的特警证", 36, Pal.YELLOW, Style.title_font())
	ht.position = Vector2(30, 20)
	card.add_child(ht)
	var pr := Portrait.new()
	pr.species = "shiba"
	pr.position = Vector2(30, 110)
	pr.size = Vector2(130, 130)
	card.add_child(pr)
	_nick_label = Style.label("", 44, Pal.INK, Style.title_font())
	_nick_label.position = Vector2(180, 120)
	card.add_child(_nick_label)
	var best := Style.label("", 20, Color(Pal.INK, 0.7), Style.body_font())
	best.position = Vector2(184, 178)
	best.name = "Best"
	card.add_child(best)
	var rename := StickerButton.new("改昵称", "secondary", 24)
	rename.position = Vector2(30, 270)
	rename.pressed.connect(_rename_dialog)
	card.add_child(rename)

	var ct := Style.label("恢复码", 30, Pal.ORANGE_DARK, Style.title_font())
	ct.position = Vector2(30, 360)
	card.add_child(ct)
	_code_label = Style.label("", 32, Pal.INK, Style.num_font())
	_code_label.position = Vector2(30, 404)
	card.add_child(_code_label)
	var note := Style.label("换手机 / 换浏览器时，用恢复码找回你的成绩。\n请截图保存，不要告诉别人。", 21, Color(Pal.INK, 0.65), Style.body_font())
	note.position = Vector2(32, 456)
	card.add_child(note)
	var copy := StickerButton.new("复制恢复码", "secondary", 24)
	copy.position = Vector2(30, 540)
	copy.pressed.connect(func():
		if Online.secret != "":
			DisplayServer.clipboard_set(Online.secret)
			_status.text = "恢复码已复制"
	)
	card.add_child(copy)
	var restore := StickerButton.new("用恢复码找回", "ghost", 24)
	restore.position = Vector2(270, 540)
	restore.pressed.connect(_restore_dialog)
	card.add_child(restore)
	card.set_meta("best", best)
	_refresh_profile()


func _refresh_profile() -> void:
	if not is_instance_valid(_nick_label):
		return
	_nick_label.text = Online.nickname
	var best: Label = _nick_label.get_parent().get_meta("best")
	var lines: PackedStringArray = []
	for d in Game.DIFF_ORDER:
		lines.append("%s最佳  %s" % [Game.DIFFS[d].name, Online.fmt_time(Online.local_best(d))])
	best.text = "\n".join(lines)
	if Online.secret != "":
		_code_label.text = Online.secret
	elif Online.online():
		_code_label.text = "（第一次挑战后生成）"
	else:
		_code_label.text = "（云端未开启）"


# ------------------------------------------------------------------ 榜单

func _switch(tab: String) -> void:
	_tab = tab
	# 选中的标签用橙色贴纸样式，另一个用深色
	for k in _tab_btns:
		var old: StickerButton = _tab_btns[k]
		var nb := StickerButton.new(old.text, "primary" if k == tab else "secondary", 28)
		nb.position = old.position
		nb.custom_minimum_size = old.custom_minimum_size
		nb.pressed.connect(_switch.bind(k))
		old.get_parent().add_child(nb)
		old.queue_free()
		_tab_btns[k] = nb
	for d in _diff_btns:
		var db: Button = _diff_btns[d]
		var info: Dictionary = Game.DIFFS[d]
		var on: bool = d == _diff
		db.text = info.name
		for st in ["normal", "hover", "pressed"]:
			var sb := Style.box(info.color if on else Color("1A2748"), 12, 3, Pal.INK if on else Color(info.color, 0.6))
			if st == "hover" and not on:
				sb.bg_color = Color("24355E")
			db.add_theme_stylebox_override(st, sb)
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			db.add_theme_color_override(st, Pal.INK if on else info.color)
	var dname: String = Game.DIFFS[_diff].name
	for c in _list.get_children():
		c.queue_free()
	if tab == "local":
		var mine := Online.local_list(_diff)
		_status.text = "%s · 本机最好的 %d 次通关" % [dname, mine.size()]
		var rows: Array = []
		for r in mine:
			rows.append({"nickname": String(r.get("nick", Online.nickname)), "time_ms": int(r.time_ms), "rating": r.rating, "sub": String(r.get("date", ""))})
		_fill(rows, true)
		return
	if not Online.online():
		_status.text = ""
		_message("云端排行榜还没开启。\n\n部署服务器后（见 server/leaderboard/README.md），\n把网址填进 leaderboard.cfg 重新导出即可。\n\n现在可以先看「本机记录」。")
		return
	_status.text = "加载中…"
	var want := _diff
	var res: Dictionary = await Online.fetch_board(want, 50)
	if not is_instance_valid(self) or _tab != "global" or _diff != want:
		return
	if res.has("error"):
		_status.text = ""
		_message("网络连接失败，请稍后再试。")
		return
	var rows2: Array = []
	var my := Online.player_id.substr(0, 8)
	for e in res.get("entries", []):
		rows2.append({"nickname": e.nickname, "time_ms": int(e.time_ms), "rating": e.get("rating", ""), "me": my != "" and e.get("pid", "") == my})
	_status.text = "%s榜 · 共 %d 名特警上榜" % [dname, rows2.size()]
	_fill(rows2, false)


func _message(text: String) -> void:
	var l := Style.label(text, 28, Pal.CREAM, Style.body_font())
	l.custom_minimum_size = Vector2(1000, 400)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_list.add_child(l)


func _fill(rows: Array, local: bool) -> void:
	if rows.is_empty():
		_message("还没有成绩 —— 去挑战一把吧！")
		return
	for i in rows.size():
		var r: Dictionary = rows[i]
		var row := PanelContainer.new()
		var me: bool = r.get("me", false)
		var sb := Style.box(Color(Pal.ORANGE, 0.3) if me else Color(Pal.NAVY, 0.9), 12, 2, Pal.ORANGE if me else Pal.NAVY_LIGHT)
		sb.content_margin_left = 16
		sb.content_margin_right = 20
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 18)
		row.add_child(hb)
		var medal_col: Color = [Pal.YELLOW, Color("D9E2EC"), Color("E0A060")][i] if i < 3 else Color(Pal.CREAM, 0.6)
		var rank := Style.label("%d" % (i + 1), 40 if i < 3 else 32, medal_col, Style.num_font(), 6)
		rank.custom_minimum_size = Vector2(80, 0)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(rank)
		var nm := Style.label(String(r.nickname) + ("（我）" if me else ""), 32, Pal.CREAM, Style.title_font())
		nm.custom_minimum_size = Vector2(440, 0)
		nm.clip_text = true
		hb.add_child(nm)
		var rt := Style.label(String(r.get("rating", "")), 32, Pal.ORANGE, Style.num_font())
		rt.custom_minimum_size = Vector2(60, 0)
		hb.add_child(rt)
		var tm := Style.label(Online.fmt_time(int(r.time_ms)), 34, Pal.YELLOW if i == 0 else Pal.CREAM, Style.num_font())
		tm.custom_minimum_size = Vector2(220, 0)
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(tm)
		if local and r.get("sub", "") != "":
			var d := Style.label(String(r.sub), 18, Color(Pal.CREAM, 0.5), Style.body_font())
			hb.add_child(d)
		_list.add_child(row)


# ------------------------------------------------------------------ 对话框

func _dialog(title: String, value: String, placeholder: String, ok_text: String, on_ok: Callable) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	Style.full_rect(dim)
	add_child(dim)
	var p := Style.panel(Pal.NAVY, 20, 5, Pal.YELLOW, 14)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.4
	p.anchor_bottom = 0.4
	p.offset_left = -400
	p.offset_right = 400
	p.offset_top = -160
	p.offset_bottom = 180
	dim.add_child(p)
	var t := Style.label(title, 40, Pal.YELLOW, Style.title_font())
	t.position = Vector2(40, 26)
	p.add_child(t)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.position = Vector2(40, 100)
	edit.size = Vector2(720, 72)
	edit.add_theme_font_override("font", Style.title_font())
	edit.add_theme_font_size_override("font_size", 34)
	edit.add_theme_stylebox_override("normal", Style.box(Pal.CREAM, 12, 3, Pal.INK))
	edit.add_theme_stylebox_override("focus", Style.box(Pal.CREAM, 12, 4, Pal.ORANGE))
	edit.add_theme_color_override("font_color", Pal.INK)
	p.add_child(edit)
	var err := Style.label("", 22, Pal.RED, Style.body_font())
	err.position = Vector2(42, 184)
	p.add_child(err)
	var ok := StickerButton.new(ok_text, "primary", 30)
	ok.position = Vector2(200, 228)
	p.add_child(ok)
	var cancel := StickerButton.new("取消", "secondary", 28)
	cancel.position = Vector2(470, 230)
	cancel.pressed.connect(dim.queue_free)
	p.add_child(cancel)
	ok.pressed.connect(func():
		var msg: String = await on_ok.call(edit.text)
		if msg == "":
			dim.queue_free()
			_switch(_tab)
		elif is_instance_valid(err):
			err.text = msg
	)


func _rename_dialog() -> void:
	_dialog("改昵称（最多 12 字）", Online.nickname, "", "保存", func(t): return await Online.set_nickname(t))


func _restore_dialog() -> void:
	_dialog("输入恢复码找回身份", "", "PAW-XXXX-XXXX-XXXX", "找回", func(t): return await Online.restore(t))
