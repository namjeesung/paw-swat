class_name TipCards
extends Control
## 新手提示卡片：每种机制第一次出现时弹出，带图标 + 标题 + 一两句说明，几秒后自动收起。
## 放在屏幕左侧（局长对讲下面），不挡战场中间；关键字标红。

const W := 560.0
const H := 168.0

const STALE_MS := 9000
var _queue: Array = []   # [id, 排队时刻 ms]
var _shown := {}
var _cur := ""
var _left := 0.0
var _age := 0.0
var _a := 0.0
var _title: Label
var _body: RichTextLabel
var _icon: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	_icon = Control.new()
	_icon.position = Vector2(14, 36)
	_icon.size = Vector2(96, 96)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	add_child(_icon)
	_title = Style.label("", 30, Pal.YELLOW, Style.title_font())
	_title.position = Vector2(122, 14)
	add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.position = Vector2(124, 54)
	_body.size = Vector2(W - 138, 108)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_override("normal_font", Style.body_font())
	_body.add_theme_font_override("bold_font", Style.body_font())
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_font_size_override("bold_font_size", 22)
	_body.add_theme_color_override("default_color", Pal.CREAM)
	_body.add_theme_constant_override("line_separation", 2)
	add_child(_body)
	modulate.a = 0.0


## 某个提示只会自动弹出一次
func show_tip(id: String) -> void:
	if _shown.has(id):
		return
	_shown[id] = true
	_queue.append([id, Time.get_ticks_msec()])
	# 新提示来了：当前这张最多再显示 1.2 秒（但至少让玩家看满 2.8 秒），避免重要提示被压在后面
	if _cur != "":
		_left = minf(_left, maxf(1.2, 2.8 - _age))


func _draw_icon() -> void:
	if _cur == "":
		return
	var tip := Tips.get_tip(_cur)
	var c := _icon.size * 0.5
	_icon.draw_circle(c, 46, Pal.INK)
	_icon.draw_circle(c, 41, Pal.CREAM)
	Tips.draw_icon(_icon, c, 40, tip[0])


func _process(delta: float) -> void:
	var rd := HudWidgets.real_delta(delta)
	# 排队太久的提示已经和眼前的情况对不上了：先丢掉，等这个机制下次出现时再提示
	while _cur == "" and not _queue.is_empty() and Time.get_ticks_msec() - int(_queue[0][1]) > STALE_MS:
		_shown.erase(_queue.pop_front()[0])
	if _cur == "" and not _queue.is_empty():
		_cur = _queue.pop_front()[0]
		var tip := Tips.get_tip(_cur)
		_title.text = tip[1]
		_body.text = Tips.rich(tip[2])
		_left = 3.0 + Tips.plain(tip[2]).length() * 0.06
		_age = 0.0
		_icon.queue_redraw()
		Sfx.play("score", -6.0, 0.8)
	if _cur != "":
		_left -= rd
		_age += rd
		if _left > 0.0:
			_a = minf(1.0, _a + rd * 5.0)
		else:
			# 时间到：只淡出（之前淡入和淡出同时进行，淡入更快，卡片永远不消失）
			_a = maxf(0.0, _a - rd * 4.0)
			if _a <= 0.0:
				_cur = ""
	modulate.a = _a
	# 从左边滑进来
	position.x = lerpf(position.x, _base_x() + (1.0 - _a) * -60.0, 1.0 - exp(-14.0 * rd))
	if _a > 0.001:
		queue_redraw()


var _bx := -99999.0


func _base_x() -> float:
	if _bx < -9999.0:
		_bx = position.x
	return _bx


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(Style.box(Color(0, 0, 0, 0.35), 20), Rect2(Vector2(6, 8), size))
	draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.95), 20, 4, Pal.YELLOW), r)
	var tag := Rect2(Vector2(W - 146, -16), Vector2(130, 34))
	draw_style_box(Style.box(Pal.YELLOW, 10, 3, Pal.INK), tag)
	HudWidgets.text(self, Style.title_font(), tag.position + Vector2(0, 26), "新手提示", 22, Pal.INK, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x)
	if _left > 0.0 and _cur != "":
		var k := clampf(_left / (3.0 + _body.get_parsed_text().length() * 0.06), 0.0, 1.0)
		draw_rect(Rect2(Vector2(14, H - 8), Vector2((W - 28) * k, 3)), Color(Pal.YELLOW, 0.6))
