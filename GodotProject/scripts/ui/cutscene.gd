class_name Cutscene
extends CanvasLayer
## 神器变身特写：320x180 像素画布、30 帧/秒逐帧动画，放大后保留硬像素边缘。
##   0-30   黑边推入 + 速度线 + 豆包特写滑入，眼睛闪光
##   30-60  神器零件从四面八方飞来组装
##   60-80  神器发光 + “神器装备！”
##   80-108 “FIRE!” 砸屏 + 喊叫
## 播放期间整个游戏暂停。

signal done

const W := 320
const H := 180
const FPS := 30.0
const FRAMES := 108

var _vp: SubViewport
var _canvas: PixelCanvas
var _top: ColorRect
var _bottom: ColorRect
var _flash: ColorRect
var _f := 0
var _acc := 0.0
var _last := 0
var _ended := false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_canvas = PixelCanvas.new()
	_canvas.size = Vector2(W, H)
	_vp.add_child(_canvas)

	var root := Control.new()
	Style.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	Style.full_rect(bg)
	root.add_child(bg)
	var tex := TextureRect.new()
	tex.texture = _vp.get_texture()
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Style.full_rect(tex)
	root.add_child(tex)
	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.anchor_right = 1.0
	root.add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.anchor_right = 1.0
	root.add_child(_bottom)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 1)
	Style.full_rect(_flash)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_last = Time.get_ticks_usec()
	Sfx.play("transform", -2.0, 1.0, 0.0)
	_on_frame(0)


func _process(_d: float) -> void:
	if _ended:
		return
	var now := Time.get_ticks_usec()
	_acc += minf((now - _last) / 1000000.0, 0.1)
	_last = now
	while _acc >= 1.0 / FPS and not _ended:
		_acc -= 1.0 / FPS
		_f += 1
		_on_frame(_f)
	# 黑边与闪白在全分辨率层上平滑过渡
	var bar := 0.07 * clampf(_f / 6.0, 0.0, 1.0)
	var vs := _top.get_parent_area_size()
	_top.size = Vector2(vs.x, vs.y * bar)
	_bottom.position = Vector2(0, vs.y * (1.0 - bar))
	_bottom.size = Vector2(vs.x, vs.y * bar)
	_flash.color.a = maxf(0.0, _flash.color.a - _d * 4.0)


func _on_frame(f: int) -> void:
	_canvas.frame = f
	_canvas.queue_redraw()
	match f:
		32, 38, 44, 50, 56:
			Sfx.play("clank", -4.0, 0.9 + f * 0.004, 0.05)
		62:
			Sfx.play("powerup", -2.0, 1.0, 0.0)
			_flash.color.a = 0.7
		80:
			Sfx.play("shout_fire", 0.0, 1.0, 0.0)
			Sfx.play("explosion", -4.0, 1.3, 0.0)
			_flash.color.a = 0.9
	if f >= FRAMES:
		_finish()


func _finish() -> void:
	_ended = true
	_flash.color.a = 1.0
	get_tree().paused = false
	done.emit()
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_flash, "color:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


# ======================================================================= 像素画布
class PixelCanvas extends Control:
	var frame := 0
	const C := Vector2(160, 90)
	const G := Vector2(226, 104)

	func _k(f0: float, f1: float) -> float:
		return clampf((frame - f0) / maxf(f1 - f0, 1.0), 0.0, 1.0)

	func _draw() -> void:
		var f := frame
		var shake := Vector2.ZERO
		if f >= 80 and f < 92:
			shake = Vector2(randi_range(-4, 4), randi_range(-3, 3))
		elif f in [32, 38, 44, 50, 56]:
			shake = Vector2(randi_range(-2, 2), randi_range(-2, 2))
		draw_set_transform(shake, 0, Vector2.ONE)
		_bg(f)
		_shiba(f)
		_weapon(f)
		_texts(f)

	func _bg(f: int) -> void:
		var base := Pal.NAVY
		var c1 := Pal.ORANGE
		var c2 := Pal.NAVY_LIGHT
		if f >= 62:
			base = Color("C9560A")
			c1 = Pal.YELLOW
			c2 = Pal.ORANGE
		if f >= 80:
			base = Color("7A1020")
			c1 = Pal.RED
			c2 = Color("FF8A3D")
		draw_rect(Rect2(-10, -10, 340, 200), base)
		var speed := 0.06 if f < 62 else 0.16
		for i in 28:
			var a := i * TAU / 28.0 + f * speed
			var col := c1 if i % 2 == 0 else c2
			var p0 := C + Vector2(cos(a), sin(a)) * (36 + (f * 7 + i * 13) % 30)
			var p1 := C + Vector2(cos(a), sin(a)) * 240
			draw_line(p0, p1, col, 3 + i % 3, false)

	func _shiba(f: int) -> void:
		var x := lerpf(-80.0, 96.0, ease(_k(3, 15), -2.4))
		if f >= 80:
			x = lerpf(96.0, 84.0, _k(80, 84))
		var c := Vector2(x, 102)
		draw_circle(c, 62, Pal.INK, true, -1.0, false)
		draw_circle(c, 58, Pal.NAVY_LIGHT, true, -1.0, false)
		Portrait.draw_face(self, c + Vector2(0, 8), 48, "shiba", "normal")
		# 坚定的眉毛
		if f >= 24:
			draw_line(c + Vector2(-26, -14), c + Vector2(-8, -8), Pal.INK, 4, false)
			draw_line(c + Vector2(26, -14), c + Vector2(8, -8), Pal.INK, 4, false)
		# 眼睛闪光
		if f >= 20 and f < 30:
			var s := sin(_k(20, 30) * PI) * 12.0
			draw_colored_polygon(Style.star_points(c + Vector2(18, 4), s, s * 0.3, 4), Color.WHITE)
		# 喊 FIRE 时张大嘴
		if f >= 80:
			draw_colored_polygon(Style.ellipse_points(c + Vector2(0, 30), 10, 9, 16), Color("5A1020"))
			draw_colored_polygon(Style.ellipse_points(c + Vector2(0, 35), 6, 3, 12), Color("FF8FA6"))

	func _part_pos(final: Vector2, from: Vector2, arrive: int) -> Vector2:
		var k := ease(_k(arrive - 7, arrive), -2.0)
		return from.lerp(final, k)

	func _weapon(f: int) -> void:
		if f < 25:
			return
		var glow := f >= 60
		if glow:
			for i in 3:
				var r := 46.0 + i * 12.0 + sin(f * 0.5 + i) * 4.0
				draw_arc(G + Vector2(10, 0), r, 0, TAU, 32, Color(Pal.YELLOW, 0.45 - i * 0.12), 4, false)
		var dark := Color("2A2E38")
		var steel := Color("9AA3B5")
		# 机身
		var body := _part_pos(G + Vector2(-30, -12), G + Vector2(-30, 120), 44)
		if f >= 37:
			draw_rect(Rect2(body, Vector2(46, 26)), dark)
			draw_rect(Rect2(body + Vector2(0, 6), Vector2(46, 5)), Pal.YELLOW)
			draw_rect(Rect2(body, Vector2(46, 26)), Pal.INK, false, 2)
		# 枪管
		var bp := _part_pos(G + Vector2(16, -10), G + Vector2(180, -10), 32)
		var spin := (f / 2) % 3
		for i in 3:
			var y := bp.y + i * 7 + (spin if f >= 60 else 0)
			draw_rect(Rect2(Vector2(bp.x, y), Vector2(46, 5)), steel)
			draw_rect(Rect2(Vector2(bp.x + 42, y), Vector2(4, 5)), dark)
		draw_rect(Rect2(bp + Vector2(44, -2), Vector2(6, 24)), dark)
		# 弹鼓（罐头）
		var dp := _part_pos(G + Vector2(-18, 22), G + Vector2(-18, -160), 38)
		draw_circle(dp, 15, Pal.INK, true, -1.0, false)
		draw_circle(dp, 13, Pal.ORANGE, true, -1.0, false)
		draw_circle(dp, 8, Pal.CREAM, true, -1.0, false)
		draw_rect(Rect2(dp + Vector2(-3, -3), Vector2(6, 6)), Pal.RED)
		# 握把
		if f >= 43:
			var hp := _part_pos(G + Vector2(-14, -22), G + Vector2(120, -140), 50)
			draw_rect(Rect2(hp, Vector2(18, 9)), dark)
		# 子弹链（罐头）
		if f >= 49:
			var lp := _part_pos(G + Vector2(-60, 26), G + Vector2(-260, 26), 56)
			for i in 5:
				draw_rect(Rect2(lp + Vector2(i * 9, 0), Vector2(7, 9)), Pal.ORANGE)
				draw_rect(Rect2(lp + Vector2(i * 9, 3), Vector2(7, 3)), Pal.CREAM)
		# 零件到位的闪光
		for a in [32, 38, 44, 50, 56]:
			if f >= a and f < a + 4:
				var s: float = (4 - (f - a)) * 4.0
				var sp := G + Vector2(randi_range(-30, 40), randi_range(-20, 20))
				draw_colored_polygon(Style.star_points(sp, s, s * 0.3, 4), Color.WHITE)

	func _texts(f: int) -> void:
		var tf := Style.title_font()
		if f >= 30 and f < 60:
			var dots := ".".repeat(1 + (f / 4) % 3)
			draw_string_outline(tf, Vector2(0, 42), "神器组装中" + dots, HORIZONTAL_ALIGNMENT_CENTER, W, 18, 6, Pal.INK)
			draw_string(tf, Vector2(0, 42), "神器组装中" + dots, HORIZONTAL_ALIGNMENT_CENTER, W, 18, Pal.CREAM)
		if f >= 60 and f < 80:
			var s := lerpf(1.6, 1.0, _k(60, 65))
			draw_set_transform(Vector2(160, 38) * (1.0 - s), 0, Vector2(s, s))
			draw_string_outline(tf, Vector2(0, 44), "神器装备！", HORIZONTAL_ALIGNMENT_CENTER, W, 24, 8, Pal.INK)
			draw_string(tf, Vector2(0, 44), "神器装备！", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Pal.YELLOW)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			draw_string_outline(tf, Vector2(0, 158), "罐头加特林", HORIZONTAL_ALIGNMENT_CENTER, W, 22, 8, Pal.INK)
			draw_string(tf, Vector2(0, 158), "罐头加特林", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Pal.CREAM)
		if f >= 78:
			var s2 := lerpf(3.2, 1.0, ease(_k(78, 83), 0.4))
			var nf := Style.num_font()
			draw_set_transform(Vector2(200, 92) * (1.0 - s2) + Vector2(randi_range(-2, 2), 0) * (1 if f < 90 else 0), -0.08, Vector2(s2, s2))
			draw_string_outline(nf, Vector2(120, 112), "FIRE!", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, 12, Pal.INK)
			draw_string(nf, Vector2(120, 112), "FIRE!", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Pal.YELLOW)
			draw_string(nf, Vector2(120, 109), "FIRE!", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1, 1, 1, 0.35))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
