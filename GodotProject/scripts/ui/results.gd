class_name Results
extends Control
## 结算 = 《毛绒日报》头版：报纸旋转飞入 → 战报逐行统计 → 评级印章“啪”地盖上。

const HEADLINES := {
	"S": ["特警队完美出击！神器横扫僵尸鼠潮", "柴犬警员豆包首次出勤即解救人质、击退变异鼠群。局长老灰：“这孩子，有前途。”"],
	"A": ["便利店劫案告破！特警队表现亮眼", "黑眼圈帮成员悉数落网，店员仓鼠小米平安获救。"],
	"B": ["特警队险中求胜 便利店恢复营业", "行动虽有波折，但人质安全。局长：“还有进步空间。”"],
	"C": ["特警队险胜，局长：下次少吃点零食", "人质获救，但现场一片狼藉。店长表示货架需要重新上架。"],
	"F": ["特警队首战受挫！匪徒逍遥法外", "局长老灰：“回去好好练练翻滚。明天再来！”"],
}
const RATING_COLOR := {"S": Color("FFB000"), "A": Color("FF7A1A"), "B": Color("3DD6C6"), "C": Color("8E9AAF"), "F": Color("E63946")}

var data := {}
var board: Control
var paper: Control
var _rows: Array[Control] = []
var _stamp: Control
var _score_label: Label
var _final := {}


func _ready() -> void:
	Style.full_rect(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var success: bool = data.get("success", false)
	_final = Game.final_score()
	var rating: String = _final.rating if success else "F"
	Sfx.music("menu")

	var bg := Style.shader_rect("res://shaders/cork.gdshader", {"base": Color("5A3A24")})
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

	paper = Control.new()
	paper.position = Vector2(400, 40)
	paper.size = Vector2(1060, 1000)
	paper.pivot_offset = paper.size * 0.5
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(paper)
	var sh := Style.panel(Color(0, 0, 0, 0.45), 4)
	sh.position = Vector2(14, 18)
	sh.size = paper.size
	paper.add_child(sh)
	var pp := Style.shader_rect("res://shaders/paper.gdshader")
	pp.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pp.size = paper.size
	paper.add_child(pp)

	_masthead()
	var hl: Array = HEADLINES[rating]
	var head := Style.label(hl[0], 62, Pal.INK, Style.title_font())
	head.position = Vector2(40, 196)
	head.size = Vector2(980, 90)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper.add_child(head)
	var subtxt: String = hl[1]
	if not success:
		subtxt = "失败原因：%s。%s" % [data.get("reason", "未知"), subtxt]
	var sub := Style.label(subtxt, 26, Color(Pal.INK, 0.8), Style.body_font())
	sub.position = Vector2(60, 290)
	sub.size = Vector2(940, 70)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper.add_child(sub)
	_rule(372, 3)

	var photo := NewsPhoto.new()
	photo.success = success
	photo.position = Vector2(40, 396)
	photo.size = Vector2(450, 340)
	paper.add_child(photo)
	var cap := Style.label("▲ 本报记者摄：特警豆包与获救店员小米合影。" if success else "▲ 本报记者摄：嚣张的黑眼圈帮成员。", 19, Color(Pal.INK, 0.65), Style.body_font())
	cap.position = Vector2(40, 744)
	paper.add_child(cap)
	_ad()
	_stats(success)
	_stamp = RatingStamp.new()
	_stamp.rating = rating
	_stamp.color = RATING_COLOR[rating]
	_stamp.position = Vector2(945, 900)
	_stamp.modulate.a = 0.0
	paper.add_child(_stamp)

	var again := StickerButton.new("再来一次", "primary", 38)
	again.position = Vector2(1520, 760)
	again.custom_minimum_size = Vector2(340, 90)
	again.pressed.connect(func(): Game.goto("level"))
	board.add_child(again)
	var menu := StickerButton.new("返回任务板", "secondary", 30)
	menu.position = Vector2(1545, 880)
	menu.custom_minimum_size = Vector2(290, 70)
	menu.pressed.connect(func(): Game.goto("menu"))
	board.add_child(menu)
	again.grab_focus.call_deferred()
	var lb_btn := StickerButton.new("排行榜", "ghost", 28)
	lb_btn.position = Vector2(1580, 975)
	lb_btn.custom_minimum_size = Vector2(220, 64)
	lb_btn.pressed.connect(func(): Game.goto("leaderboard"))
	board.add_child(lb_btn)
	_animate(success)
	if success:
		_build_lb_panel()
		_submit()


func _masthead() -> void:
	var t := Style.label("毛绒日报", 112, Pal.INK, Style.title_font())
	t.position = Vector2(0, 14)
	t.size = Vector2(1060, 130)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paper.add_child(t)
	var l := Style.label("THE FLUFFTON\nDAILY", 18, Color(Pal.INK, 0.7), Style.num_font())
	l.position = Vector2(48, 58)
	paper.add_child(l)
	var r := Style.label("第 0427 期\n今日 4 版", 20, Color(Pal.INK, 0.7), Style.body_font())
	r.position = Vector2(890, 52)
	paper.add_child(r)
	_rule(146, 6)
	_rule(156, 2)
	var d := Style.label("2026 年 10 月 5 日  ·  星期一  ·  晴转多云  ·  售价：两条小鱼干", 20, Color(Pal.INK, 0.7), Style.body_font())
	d.position = Vector2(0, 162)
	d.size = Vector2(1060, 30)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paper.add_child(d)


func _rule(y: float, h: float) -> void:
	var c := ColorRect.new()
	c.color = Pal.INK
	c.position = Vector2(40, y)
	c.size = Vector2(980, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(c)


func _ad() -> void:
	var box := Style.panel(Color(0, 0, 0, 0), 0, 3, Pal.INK)
	box.position = Vector2(40, 786)
	box.size = Vector2(450, 180)
	paper.add_child(box)
	var a := Style.label("广 告", 22, Pal.CREAM, Style.title_font())
	var tag := Style.panel(Pal.INK, 0)
	tag.position = Vector2(40, 786)
	tag.size = Vector2(90, 34)
	paper.add_child(tag)
	a.position = Vector2(56, 786)
	paper.add_child(a)
	var t := Style.label("喵喵便利店 · 重新开业", 34, Pal.INK, Style.title_font())
	t.position = Vector2(64, 830)
	paper.add_child(t)
	var t2 := Style.label("今日猫罐头全场 8 折！\n特警队员凭证件再送冻干一包。", 22, Color(Pal.INK, 0.75), Style.body_font())
	t2.position = Vector2(64, 882)
	paper.add_child(t2)


func _stats(success: bool) -> void:
	var r := Game.run
	var x := 530.0
	var head := Style.label("行动战报", 40, Pal.INK, Style.title_font())
	head.position = Vector2(x, 392)
	paper.add_child(head)
	var tt := float(r.get("time", 0.0))
	var hostage := "仍被挟持"
	if bool(r.get("rescued", false)):
		hostage = "平安获救" if int(r.hostage_hits) == 0 else "获救（误伤 %d 次）" % int(r.hostage_hits)
	var rows := [
		["行动用时", "%02d:%02d" % [int(tt / 60.0), int(fmod(tt, 60.0))]],
		["命中率", "%d%%" % int(round(float(_final.accuracy) * 100.0))],
		["击倒匪徒", "%d 次" % int(r.downs)],
		["永久制服", "%d 名" % int(r.cuffs)],
		["完美换弹", "%d 次" % int(r.perfect)],
		["翻滚闪避", "%d 次" % int(r.dodges)],
		["承受伤害", "%d" % int(r.damage)],
		["击退僵尸鼠", "%d 只%s" % [int(r.get("zombies", 0)), " + 鼠王" if bool(r.get("boss", false)) else ""]],
		["人质状态", hostage],
	]
	for i in rows.size():
		var row := Control.new()
		row.position = Vector2(x, 448 + i * 38)
		row.size = Vector2(490, 40)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := Style.label(rows[i][0], 26, Pal.INK, Style.body_font())
		row.add_child(k)
		var dots := Style.label("··················", 22, Color(Pal.INK, 0.25), Style.body_font())
		dots.position = Vector2(118, 2)
		dots.size = Vector2(250, 30)
		dots.clip_text = true
		row.add_child(dots)
		var v := Style.label(rows[i][1], 26, Pal.INK, Style.bold_font())
		v.size = Vector2(490, 36)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		row.modulate.a = 0.0
		paper.add_child(row)
		_rows.append(row)
	var line := ColorRect.new()
	line.color = Pal.INK
	line.position = Vector2(x, 794)
	line.size = Vector2(490, 3)
	paper.add_child(line)
	var sl := Style.label("总分", 34, Pal.INK, Style.title_font())
	sl.position = Vector2(x, 806)
	paper.add_child(sl)
	_score_label = Style.label("0", 50, Pal.ORANGE_DARK, Style.num_font())
	_score_label.position = Vector2(x + 84, 800)
	paper.add_child(_score_label)
	if not success:
		_score_label.text = "—"


func _animate(success: bool) -> void:
	paper.scale = Vector2.ONE * 0.05
	paper.rotation = -TAU * 3.0
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(func(): Sfx.play("paper", 0.0, 0.9))
	tw.tween_property(paper, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(paper, "rotation", deg_to_rad(-1.5), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for row in _rows:
		tw.tween_callback(func(): Sfx.play("type", -8.0, 0.8))
		tw.tween_property(row, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(row, "position:x", row.position.x, 0.16).from(row.position.x + 40)
		tw.tween_interval(0.05)
	if success:
		var target: int = int(_final.score)
		tw.tween_method(_set_score, 0.0, float(target), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(0.25)
	tw.tween_callback(func():
		Sfx.play("stamp", 0.0, 1.0, 0.0)
		_stamp.scale = Vector2.ONE * 3.0
	)
	tw.tween_property(_stamp, "modulate:a", 1.0, 0.06)
	tw.parallel().tween_property(_stamp, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_IN)
	tw.tween_callback(_thump)
	if success:
		tw.tween_callback(func(): Sfx.play("victory", -6.0, 1.0, 0.0))


func _set_score(v: float) -> void:
	_score_label.text = "%d" % int(v)


func _thump() -> void:
	var base := board.position
	var tw := create_tween()
	for i in 6:
		tw.tween_property(board, "position", base + Vector2(randf_range(-12, 12), randf_range(-8, 8)) * (1.0 - i / 6.0), 0.03)
	tw.tween_property(board, "position", base, 0.04)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		Game.goto("level")
	elif event.is_action_pressed("pause"):
		Game.goto("menu")


# ------------------------------------------------------------------ 组件

class RatingStamp extends Control:
	var rating := "S"
	var color := Color.RED

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, deg_to_rad(-14), Vector2.ONE * 0.82)
		var c := Color(color, 0.92)
		draw_arc(Vector2.ZERO, 118, 0, TAU, 64, c, 9.0)
		draw_arc(Vector2.ZERO, 100, 0, TAU, 64, c, 3.0)
		var big := rating if rating != "F" else "败"
		var f := Style.num_font() if rating != "F" else Style.title_font()
		HudWidgets.text(self, f, Vector2(-100, 52), big, 150, c, HORIZONTAL_ALIGNMENT_CENTER, 200)
		HudWidgets.text(self, Style.title_font(), Vector2(-100, -66), "P.A.W. 评级", 24, c, HORIZONTAL_ALIGNMENT_CENTER, 200)
		HudWidgets.text(self, Style.title_font(), Vector2(-100, 92), "毛绒市警局", 22, c, HORIZONTAL_ALIGNMENT_CENTER, 200)


class NewsPhoto extends Control:
	var success := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("3E3428"))
		var inner := r.grow(-10)
		draw_polygon(PackedVector2Array([inner.position, inner.position + Vector2(inner.size.x, 0), inner.end, inner.position + Vector2(0, inner.size.y)]),
			PackedColorArray([Color("8C7A60"), Color("8C7A60"), Color("5E4E3A"), Color("5E4E3A")]))
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.72), Vector2(inner.size.x, inner.size.y * 0.28)), Color("4A3D2E"))
		if success:
			Portrait.draw_face(self, Vector2(size.x * 0.36, size.y * 0.5), 92, "shiba")
			Portrait.draw_face(self, Vector2(size.x * 0.72, size.y * 0.6), 66, "hamster")
		else:
			Portrait.draw_face(self, Vector2(size.x * 0.32, size.y * 0.52), 78, "raccoon")
			Portrait.draw_face(self, Vector2(size.x * 0.7, size.y * 0.56), 64, "rat")
		# 做旧：泛黄 + 网点
		draw_rect(inner, Color(0.85, 0.7, 0.45, 0.28))
		for y in range(int(inner.position.y), int(inner.end.y), 6):
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0, 0, 0, 0.06), 2)


# ------------------------------------------------------------------ 最速通关榜

var _lb_time: Label
var _lb_line1: Label
var _lb_line2: Label
var _lb_badge: Label
var _lb_retry: Button


func _build_lb_panel() -> void:
	var box := Control.new()
	box.position = Vector2(1490, 70)
	box.size = Vector2(400, 330)
	box.rotation = deg_to_rad(2.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(box)
	var sh := Style.panel(Color(0, 0, 0, 0.35), 16)
	sh.position = Vector2(8, 10)
	sh.size = box.size
	box.add_child(sh)
	var p := Style.panel(Pal.NAVY, 16, 4, Pal.INK)
	p.size = box.size
	box.add_child(p)
	var t := Style.label("最速通关", 34, Pal.YELLOW, Style.title_font())
	t.position = Vector2(24, 16)
	box.add_child(t)
	_lb_time = Style.label(Online.fmt_time(int(Game.run.get("run_ms", 0))), 64, Pal.CREAM, Style.num_font(), 10)
	_lb_time.position = Vector2(24, 64)
	box.add_child(_lb_time)
	var di := Game.diff_info(String(Game.run.get("difficulty", Game.difficulty)))
	var chip := Style.panel(di.color, 10, 3, Pal.INK)
	chip.position = Vector2(292, 86)
	chip.size = Vector2(86, 44)
	box.add_child(chip)
	var cl := Style.label(di.name, 26, Pal.INK, Style.title_font())
	cl.position = Vector2(292, 88)
	cl.size = Vector2(86, 40)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cl)
	_lb_line1 = Style.label("个人最佳 …", 24, Pal.CREAM, Style.body_font())
	_lb_line1.position = Vector2(26, 168)
	box.add_child(_lb_line1)
	_lb_line2 = Style.label("正在提交成绩…", 22, Color(Pal.CREAM, 0.7), Style.body_font())
	_lb_line2.position = Vector2(26, 206)
	_lb_line2.size = Vector2(350, 110)
	_lb_line2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lb_line2)
	_lb_badge = Style.label("", 30, Pal.INK, Style.title_font())
	var bb := Style.panel(Pal.ORANGE, 10, 3, Pal.INK)
	bb.position = Vector2(220, 18)
	bb.size = Vector2(158, 44)
	bb.visible = false
	box.add_child(bb)
	_lb_badge.position = Vector2(232, 20)
	box.add_child(_lb_badge)
	_lb_badge.set_meta("bg", bb)
	if Online.toy_mode():
		_lb_retry = StickerButton.new("查询 / 重试提交", "secondary", 24)
		_lb_retry.position = Vector2(1490, 430)
		_lb_retry.custom_minimum_size = Vector2(390, 60)
		_lb_retry.visible = false
		_lb_retry.pressed.connect(func():
			_lb_retry.disabled = true
			_lb_line2.text = "正在查询 / 提交…"
			var response := await Online.retry_toy_submission()
			if not is_instance_valid(self):
				return
			_show_cloud_result(response, Game.diff_info(String(Game.run.get("difficulty", Game.difficulty))).name)
			_lb_retry.disabled = false
		)
		board.add_child(_lb_retry)


func _submit() -> void:
	var r := Game.run
	var stats := {"rescued": bool(r.get("rescued", false)), "downs": int(r.get("downs", 0)),
		"zombies": int(r.get("zombies", 0)), "rating": String(_final.rating),
		"difficulty": String(r.get("difficulty", Game.difficulty))}
	var res: Dictionary = await Online.finish_run(int(r.get("run_ms", 0)), stats)
	if not is_instance_valid(self):
		return
	var dname: String = Game.diff_info(String(stats.difficulty)).name
	_lb_line1.text = "%s最佳 %s · 本机第 %d 名" % [dname, Online.fmt_time(Online.local_best(String(stats.difficulty))), int(res.local_rank)]
	var cloud: Dictionary = res.cloud
	_show_cloud_result(cloud, dname)
	var newbest: bool = res.new_local_best or bool(cloud.get("new_best", false))
	if newbest:
		_lb_badge.text = "新纪录！"
		(_lb_badge.get_meta("bg") as Control).visible = true
		Sfx.play("perfect", -2.0, 1.1, 0.0)
	if not Online.toy_mode() and not Online.nick_confirmed and not Game.autotest:
		_nick_dialog()


func _show_cloud_result(cloud: Dictionary, dname: String) -> void:
	if cloud.get("ok", false):
		var rank := int(cloud.get("rank", 0))
		_lb_line2.text = "%s · %s\n成绩已提交%s" % [Online.board_name(), dname, " · 第 %d 名" % rank if rank > 0 else "，可打开榜单查看"]
		_lb_line2.add_theme_color_override("font_color", Pal.TEAL)
	else:
		_lb_line2.text = Online.error_text(String(cloud.get("error", "offline")))
	if is_instance_valid(_lb_retry):
		_lb_retry.visible = Online.has_pending_toy()


## 第一次本机记录：起个昵称（默认给一个随机名字）
func _nick_dialog() -> void:
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
	p.offset_left = -380
	p.offset_right = 380
	p.offset_top = -170
	p.offset_bottom = 170
	dim.add_child(p)
	var t := Style.label("给自己起个特警代号", 44, Pal.YELLOW, Style.title_font())
	t.position = Vector2(40, 28)
	p.add_child(t)
	var hint := Style.label("会显示在排行榜上（最多 12 个字）", 22, Color(Pal.CREAM, 0.7), Style.body_font())
	hint.position = Vector2(42, 92)
	p.add_child(hint)
	var edit := LineEdit.new()
	edit.text = Online.nickname
	edit.max_length = 12
	edit.position = Vector2(40, 140)
	edit.size = Vector2(560, 72)
	edit.add_theme_font_override("font", Style.title_font())
	edit.add_theme_font_size_override("font_size", 36)
	edit.add_theme_stylebox_override("normal", Style.box(Pal.CREAM, 12, 3, Pal.INK))
	edit.add_theme_stylebox_override("focus", Style.box(Pal.CREAM, 12, 4, Pal.ORANGE))
	edit.add_theme_color_override("font_color", Pal.INK)
	p.add_child(edit)
	var dice := StickerButton.new("随机", "secondary", 26)
	dice.position = Vector2(614, 144)
	dice.pressed.connect(func(): edit.text = Online.random_nick())
	p.add_child(dice)
	var ok := StickerButton.new("就叫这个！", "primary", 34)
	ok.position = Vector2(250, 240)
	p.add_child(ok)
	ok.pressed.connect(func():
		var msg: String = await Online.set_nickname(edit.text)
		if is_instance_valid(_lb_line2) and msg != "":
			_lb_line2.text = msg
		elif is_instance_valid(_lb_line2) and _lb_line2.text.contains("昵称："):
			_lb_line2.text = _lb_line2.text.get_slice("昵称：", 0) + "昵称：" + Online.nickname
		dim.queue_free()
	)
