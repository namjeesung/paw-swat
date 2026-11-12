class_name HarborHud
extends CanvasLayer
## 第二章「罐头狂暴」HUD（叠在通用 HUD 上面）：
##   顶部（目标横幅下）：等级 + 罐头经验条
##   底部中间：罐头狂暴能量条（满 100 变身巨型罐头机甲；变身中显示剩余时间）
##   右上（计时器下）：击退数 + 实时分数
##   连吸计数、「罐 头 狂 暴 ！」大字、倒下后的结算卡

const BEST_FILE := "user://harbor_mission_best.cfg"   # 主线版分数和旧的无尽版不通用

var level: HarborLevel
var root: Control
var _panel: Control
var _summary: Control
var _chain_show := 0
var _chain_a := 0.0
var _pulse := 0.0
var _smash_pulse := 0.0


func _ready() -> void:
	layer = 6
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.full_rect(root)
	add_child(root)
	_panel = Panel_.new()
	_panel.hud = self
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.full_rect(_panel)
	root.add_child(_panel)


func on_collect(chain: int) -> void:
	_pulse = 1.0
	_chain_show = chain
	_chain_a = 1.0


func on_smash() -> void:
	_smash_pulse = 1.0


func _process(delta: float) -> void:
	var rd := HudWidgets.real_delta(delta)
	_pulse = maxf(0.0, _pulse - rd * 6.0)
	_smash_pulse = maxf(0.0, _smash_pulse - rd * 5.0)
	_chain_a = maxf(0.0, _chain_a - rd * 1.2)
	_panel.queue_redraw()


## 大字横幅（罐头狂暴 / Boss 登场等）
var _banner_free_ms := 0


## 大字横幅：同时来好几条时排队，一条一条地出（不叠在一起）
func big_banner(text: String, col: Color, size := 140) -> void:
	var now := Time.get_ticks_msec()
	var wait := maxf(0.0, (_banner_free_ms - now) / 1000.0)
	_banner_free_ms = now + int((wait + 1.75) * 1000.0)
	var l := Style.label(text, size, col, Style.title_font(), 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.38
	l.anchor_bottom = 0.38
	l.offset_left = -800
	l.offset_right = 800
	l.offset_top = -100
	l.offset_bottom = 100
	l.pivot_offset = Vector2(800, 100)
	l.scale = Vector2(2.4, 2.4)
	l.modulate.a = 0.0
	root.add_child(l)
	var tw := l.create_tween().set_ignore_time_scale(true)
	if wait > 0.0:
		tw.tween_interval(wait)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): Game.shake(0.2))
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


func rampage_banner() -> void:
	big_banner("罐 头 狂 暴 ！", Pal.ORANGE)


## 自动升级的提示条：经验条下面滑出来 2 秒（不暂停、不挡视线）
var _up_box: Control
var _up_tw: Tween


func upgrade_banner(id: String, lv: int) -> void:
	var info: Dictionary = HarborLevel.UPGRADES[id]
	if _up_box:
		_up_box.queue_free()
	if _up_tw:
		_up_tw.kill()
	var box := Style.panel(Color(Pal.NAVY_DARK, 0.94), 18, 3, Pal.YELLOW)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = 156
	box.offset_bottom = 232
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_up_box = box
	var head := Style.label("升级！ %s %s" % [info.name, "Lv%d" % lv], 32, Pal.YELLOW, Style.title_font(), 8)
	head.position = Vector2(24, 4)
	box.add_child(head)
	var d := Style.label(String(info.desc), 22, Pal.CREAM, Style.body_font())
	d.position = Vector2(24, 42)
	box.add_child(d)
	box.modulate.a = 0.0
	box.pivot_offset = Vector2(300, 38)
	box.scale = Vector2(1.15, 1.15)
	_up_tw = box.create_tween().set_ignore_time_scale(true)
	_up_tw.tween_property(box, "modulate:a", 1.0, 0.12)
	_up_tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_up_tw.tween_interval(2.0)
	_up_tw.tween_property(box, "modulate:a", 0.0, 0.3)
	_up_tw.tween_callback(box.queue_free)


## 主线一步完成：大字「✔ 完成」
func step_done(i: int) -> void:
	big_banner("完成！%s" % HarborLevel.STEPS[i].title, Pal.GREEN, 72)


# ------------------------------------------------------------------ 结算卡

func show_summary() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var lv := level
	var score := lv.total_score()
	# 本机最佳（按难度）
	var cf := ConfigFile.new()
	cf.load(BEST_FILE)
	var diff := Game.difficulty
	var best := int(cf.get_value("best", diff, 0))
	var new_best := score > best
	if new_best:
		cf.set_value("best", diff, score)
		cf.save(BEST_FILE)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	Style.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.6, 0.3)
	_summary = Control.new()
	_summary.anchor_left = 0.5
	_summary.anchor_right = 0.5
	_summary.anchor_top = 0.5
	_summary.anchor_bottom = 0.5
	_summary.offset_left = -560
	_summary.offset_right = 560
	_summary.offset_top = -430
	_summary.offset_bottom = 430
	_summary.pivot_offset = Vector2(560, 430)
	root.add_child(_summary)
	var bg := Style.panel(Pal.PAPER, 26, 6, Pal.INK, 0)
	bg.size = Vector2(1120, 860)
	_summary.add_child(bg)
	var head := Style.panel(Pal.NAVY, 22)
	head.position = Vector2(6, 6)
	head.size = Vector2(1108, 120)
	_summary.add_child(head)
	var t := Style.label("任务完成！" if lv.won else "任务失败", 64, Pal.YELLOW if lv.won else Pal.CREAM, Style.title_font(), 12)
	t.position = Vector2(48, 22)
	_summary.add_child(t)
	var sub := Style.label("第二章 · 雾港码头 —— 罐头狂暴", 26, Pal.CREAM, Style.body_font())
	sub.position = Vector2(640, 52)
	_summary.add_child(sub)
	var secs := lv.survive_seconds()
	var rows := lv.score_rows()
	var y := 150.0 if rows.size() <= 6 else 140.0
	var fades: Array[Control] = []
	for r in rows:
		var a := Style.label(r[0], 34, Pal.INK, Style.title_font())
		a.position = Vector2(70, y)
		_summary.add_child(a)
		var v := Style.label(r[1], 38, Pal.ORANGE_DARK, Style.num_font())
		v.position = Vector2(400, y - 2)
		_summary.add_child(v)
		var m := Style.label(r[2], 26, Color(Pal.INK, 0.5), Style.num_font())
		m.position = Vector2(620, y + 6)
		_summary.add_child(m)
		var p := Style.label("+%d" % r[3], 38, Pal.INK, Style.num_font())
		p.position = Vector2(760, y - 2)
		p.size = Vector2(290, 50)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_summary.add_child(p)
		for c in [a, v, m, p]:
			c.modulate.a = 0.0
		fades.append(a)
		fades.append(v)
		fades.append(m)
		fades.append(p)
		y += 58.0
	var line := ColorRect.new()
	line.color = Pal.INK
	line.position = Vector2(70, y + 6)
	line.size = Vector2(980, 4)
	_summary.add_child(line)
	var sl := Style.label("综合分", 44, Pal.INK, Style.title_font())
	sl.position = Vector2(70, y + 30)
	_summary.add_child(sl)
	var sc := Style.label("0", 80, Pal.RED, Style.num_font(), 12)
	sc.position = Vector2(560, y + 10)
	sc.size = Vector2(490, 100)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary.add_child(sc)
	var bl := Style.label(("新纪录！" if new_best else "本机最佳 %d" % best) + "   ·   等级 Lv%d" % lv.level_n, 28, Pal.ORANGE_DARK if new_best else Color(Pal.INK, 0.6), Style.title_font())
	bl.position = Vector2(70, y + 108)
	bl.modulate.a = 0.0
	_summary.add_child(bl)
	# 本局拿到的升级
	var names := PackedStringArray()
	for id in lv.ups:
		names.append("%s Lv%d" % [HarborLevel.UPGRADES[id].name, int(lv.ups[id])])
	var ul := Style.label("本局升级：" + ("、".join(names) if not names.is_empty() else "无"), 22, Color(Pal.INK, 0.6), Style.body_font())
	ul.position = Vector2(70, y + 150)
	ul.size = Vector2(980, 60)
	ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(ul)
	var again := StickerButton.new("再来一局  ↵", "primary", 34)
	again.position = Vector2(200, 760)
	again.custom_minimum_size = Vector2(340, 80)
	again.pressed.connect(func(): Game.goto("harbor"))
	_summary.add_child(again)
	var menu := StickerButton.new("返回任务板", "secondary", 30)
	menu.position = Vector2(600, 766)
	menu.custom_minimum_size = Vector2(300, 70)
	menu.pressed.connect(func(): Game.goto("menu"))
	_summary.add_child(menu)
	again.grab_focus.call_deferred()
	_summary.scale = Vector2(0.6, 0.6)
	_summary.modulate.a = 0.0
	var tw := _summary.create_tween().set_ignore_time_scale(true)
	tw.tween_property(_summary, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_summary, "modulate:a", 1.0, 0.2)
	for i in rows.size():
		tw.tween_callback(func(): Sfx.play("type", -4.0, 1.1 + i * 0.08, 0.0))
		for k in 4:
			tw.parallel().tween_property(fades[i * 4 + k], "modulate:a", 1.0, 0.12)
		tw.tween_interval(0.14)
	tw.tween_method(func(v: float): sc.text = "%d" % roundi(v), 0.0, float(score), 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		Sfx.play("stamp", -2.0, 1.0, 0.0)
		if new_best:
			Sfx.play("perfect", -4.0, 1.0, 0.0)
		sc.pivot_offset = sc.size * 0.5
		var t2 := sc.create_tween()
		t2.tween_property(sc, "scale", Vector2(1.25, 1.25), 0.08)
		t2.tween_property(sc, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	)
	tw.tween_property(bl, "modulate:a", 1.0, 0.2)
	if Game.autotest:
		print("[harbor] SUMMARY won=%s step=%d time=%d kills=%d cans=%d rampages=%d bosses=%d level=%d smashed=%d score=%d ups=%s" % [
			str(lv.won), lv.step + 1, secs, lv.kills, lv.cans, lv.rampages, lv.bosses_down, lv.level_n, lv.smashed, score, str(lv.ups)])


func _unhandled_input(event: InputEvent) -> void:
	if _summary == null:
		return
	if event.is_action_pressed("confirm") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_R):
		get_viewport().set_input_as_handled()
		Game.goto("harbor")
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Game.goto("menu")


# ------------------------------------------------------------------ 自绘部分

class Panel_ extends Control:
	var hud: HarborHud

	func _draw() -> void:
		var lv := hud.level
		if lv == null or lv.stage != "play":
			return
		var f := Style.title_font()
		var nf := Style.num_font()
		var cx := size.x * 0.5
		_draw_world_marks(lv, f)
		_draw_boss_bars(lv, f)
		_draw_support(lv, f)
		# ---- 等级 + 经验条（顶部，目标横幅下面）
		var w := 460.0   # 别伸到左上角的电台框下面
		var r := Rect2(Vector2(cx - w * 0.5, 100), Vector2(w, 40))
		draw_style_box(Style.box(Color(0, 0, 0, 0.35), 14), Rect2(r.position + Vector2(4, 6), r.size))
		draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.92), 14, 3, Pal.INK), r)
		var k := clampf(float(lv.xp) / float(lv.xp_need()), 0.0, 1.0)
		var fill := Rect2(r.position + Vector2(84, 8), Vector2((w - 96) * k, 24))
		draw_style_box(Style.box(Pal.YELLOW.lerp(Color.WHITE, hud._pulse * 0.4), 8), fill)
		var badge := Rect2(r.position + Vector2(-6, -8), Vector2(84, 56))
		draw_style_box(Style.box(Pal.ORANGE, 14, 3, Pal.INK), badge)
		HudWidgets.text(self, nf, badge.position + Vector2(0, 40), "Lv%d" % lv.level_n, 28, Pal.INK, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x)
		HudWidgets.text(self, f, r.position + Vector2(90, 29), "罐头 %d / %d" % [lv.xp, lv.xp_need()], 20, Pal.INK if k > 0.35 else Pal.CREAM)
		# ---- 罐头狂暴能量条（底部中间）
		var bw := 560.0
		var br := Rect2(Vector2(cx - bw * 0.5, size.y - 96), Vector2(bw, 46))
		var t := Time.get_ticks_msec() / 1000.0
		var giant := lv.rampage_t > 0.0
		var kk := (lv.rampage_t / HarborLevel.RAMPAGE_TIME) if giant else clampf(float(lv.fever) / HarborLevel.RAMPAGE_NEED, 0.0, 1.0)
		if giant or kk > 0.85:
			draw_style_box(Style.box(Color(Pal.ORANGE, 0.35 + 0.25 * sin(t * 12.0)), 24), br.grow(8))
		draw_style_box(Style.box(Color(0, 0, 0, 0.35), 18), Rect2(br.position + Vector2(5, 7), br.size))
		draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.92), 18, 4, Pal.INK), br)
		var fc := Pal.ORANGE.lerp(Pal.YELLOW, 0.5 + 0.5 * sin(t * 10.0)) if giant else Pal.ORANGE
		draw_style_box(Style.box(fc, 12), Rect2(br.position + Vector2(6, 6), Vector2((bw - 12) * kk, 34)))
		var label := ("狂暴中！ %.1f" % lv.rampage_t) if giant else ("罐头狂暴  %d / %d" % [lv.fever, HarborLevel.RAMPAGE_NEED])
		HudWidgets.text(self, f, br.position + Vector2(0, 34), label, 26, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, bw, 8)
		if hud._chain_a > 0.0 and hud._chain_show >= 3:
			HudWidgets.text(self, f, br.position + Vector2(0, -16), "连吸 ×%d" % hud._chain_show, int(28 + mini(hud._chain_show, 30)), Color(Pal.YELLOW, hud._chain_a), HORIZONTAL_ALIGNMENT_CENTER, bw, 8)
		# ---- 右上：击退 + 实时分数
		var rx := size.x - 330.0
		var rr := Rect2(Vector2(rx, 140), Vector2(300, 84))
		draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.85), 16, 3, Pal.ORANGE), rr)
		HudWidgets.text(self, f, rr.position + Vector2(18, 34), "击退 %d" % lv.kills, 26, Pal.CREAM)
		HudWidgets.text(self, f, rr.position + Vector2(150, 34), "主线 %d/6" % (lv.step + 1), 22, Pal.YELLOW)
		HudWidgets.text(self, nf, rr.position + Vector2(18, 72), "%d" % lv.total_score(), int(30 + hud._smash_pulse * 4), Pal.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		HudWidgets.text(self, f, rr.position + Vector2(200, 70), "分", 22, Color(Pal.CREAM, 0.6))

	## 主线目标头顶的小箭头 + 打过的箱子头顶的血条（让人一眼看出「这个能打、还差几枪」）
	func _draw_world_marks(lv: HarborLevel, f: Font) -> void:
		var cam := lv.cam.cam
		var now := Time.get_ticks_msec()
		var bob := sin(now / 1000.0 * 6.0) * 6.0
		var main: Node3D = lv.hud._markers.target
		var label: String = HarborLevel.STEPS[lv.step].mark
		for m in lv.marks:
			if not is_instance_valid(m) or m == main:
				continue
			var hgt := 2.0
			if m is Breakable:
				hgt = (m as Breakable).size().y + 0.9
			elif m is Zombie:
				hgt = 3.2
			var wp := m.global_position + Vector3(0, hgt, 0)
			if cam.is_position_behind(wp):
				continue
			var p := cam.unproject_position(wp) + Vector2(0, bob)
			var tri := PackedVector2Array([p + Vector2(-12, -18), p + Vector2(12, -18), p])
			draw_colored_polygon(tri, Pal.YELLOW)
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Pal.INK, 3.0)
			HudWidgets.text(self, f, p + Vector2(-60, -24), label, 22, Pal.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 120, 6)
		for b in lv.breakables:
			if b.broken or (now - b.hit_ms > 2500 and not (b.has_meta("evidence") and lv.step == 1)):
				continue
			var mx: float = 40.0 if b.has_meta("evidence") else float(Breakable.KINDS[b.kind].hp)
			if mx <= 1.0:
				continue
			var wp2 := b.global_position + Vector3(0, b.size().y + 0.35, 0)
			if cam.is_position_behind(wp2):
				continue
			var sp := cam.unproject_position(wp2)
			var bw := 70.0 if mx < 10.0 else 120.0
			var r := Rect2(sp - Vector2(bw * 0.5, 6), Vector2(bw, 12))
			draw_rect(r.grow(3), Pal.INK)
			draw_rect(Rect2(r.position, Vector2(bw * clampf(b.hp / mx, 0.0, 1.0), 12)), Pal.YELLOW if not b.has_meta("evidence") else Pal.RED)

	## 鼠王血条（底部中间，狂暴条上面）：名字 + 血量 + 正在蓄力的技能
	func _draw_boss_bars(lv: HarborLevel, f: Font) -> void:
		var i := 0
		for rk in lv.kings:
			if not is_instance_valid(rk) or not is_instance_valid(rk.z) or rk.z.dead:
				continue
			var w := 560.0
			var y := size.y - 200.0 - i * 64.0
			var r := Rect2(Vector2(size.x * 0.5 - w * 0.5, y), Vector2(w, 26))
			var k := clampf(rk.z.hp / rk.z.max_hp, 0.0, 1.0)
			draw_style_box(Style.box(Color(0, 0, 0, 0.4), 10), Rect2(r.position + Vector2(4, 5), r.size))
			draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.92), 10, 3, Pal.INK), r)
			var col := Pal.RED if rk.enraged else Color("9BE07A")
			draw_style_box(Style.box(col, 7), Rect2(r.position + Vector2(4, 4), Vector2((w - 8) * k, 18)))
			var name := "老K · 罐头蟹" + ("" if lv.kings.size() <= 1 else " %d" % (i + 1)) + ("  · 暴怒！" if rk.enraged else "")
			HudWidgets.text(self, f, r.position + Vector2(0, -6), name, 26, Pal.RED if rk.enraged else Pal.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
			if rk.skill_name != "":
				var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 60.0)
				HudWidgets.text(self, f, r.position + Vector2(0, -6), "蓄力：" + rk.skill_name + "！", 26, Color(Pal.RED, blink), HORIZONTAL_ALIGNMENT_RIGHT, w, 6)
			i += 1

	## 连杀支援（右下，弹药框上面）：三格，攒满亮起「按 n」
	func _draw_support(lv: HarborLevel, f: Font) -> void:
		if lv.support == null:
			return
		var sup := lv.support
		var cw := 128.0
		var x0 := size.x - 30.0 - cw * 3 - 16.0
		var y := size.y - 330.0
		var now := Time.get_ticks_msec() / 1000.0
		for i in 3:
			var info: Dictionary = HarborSupport.KINDS[i]
			var r := Rect2(Vector2(x0 + i * (cw + 8.0), y), Vector2(cw, 76))
			var rdy := sup.is_ready_slot(i)
			var col: Color = info.color
			if rdy:
				draw_style_box(Style.box(Color(col, 0.35 + 0.25 * sin(now * 8.0 + i)), 16), r.grow(5))
			draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.9), 14, 3, col if rdy else Color(col, 0.35)), r)
			var k := clampf(float(sup.points[i]) / float(info.need), 0.0, 1.0)
			draw_style_box(Style.box(Color(col, 0.85 if rdy else 0.45), 6), Rect2(r.position + Vector2(8, 60), Vector2((cw - 16) * k, 8)))
			draw_style_box(Style.box(Pal.INK if not rdy else col, 8), Rect2(r.position + Vector2(6, 6), Vector2(30, 30)))
			HudWidgets.text(self, Style.num_font(), r.position + Vector2(6, 30), str(i + 1), 22, Pal.CREAM if not rdy else Pal.INK, HORIZONTAL_ALIGNMENT_CENTER, 30)
			HudWidgets.text(self, f, r.position + Vector2(42, 30), String(info.name), 22, Pal.CREAM if rdy else Color(Pal.CREAM, 0.6))
			var sub := "就绪！" if rdy else "%d/%d 杀" % [sup.points[i], info.need]
			HudWidgets.text(self, f, r.position + Vector2(10, 54), sub, 18, col if rdy else Color(Pal.CREAM, 0.5))
		if sup.gunship_t > 0.0:
			HudWidgets.text(self, f, Vector2(x0, y - 12), "炮艇火力覆盖 %.1f 秒" % sup.gunship_t, 24, Color("FF7A5A"), HORIZONTAL_ALIGNMENT_LEFT, -1, 6)

