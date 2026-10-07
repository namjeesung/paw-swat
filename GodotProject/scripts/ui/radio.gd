class_name Radio
extends Control
## 无线电对话框：头像 + 名牌 + 打字机文字（支持 BBCode 按键高亮）。排队播放。

const SPEAKERS := {
	"chief": ["局长 · 老灰", Pal.ORANGE],
	"shiba": ["豆包", Color("FFB46B")],
	"hamster": ["店员 · 小米", Pal.TEAL],
	"raccoon": ["劫持者", Color("B07CFF")],
}
const W := 680.0
const H := 136.0
const CPS := 34.0

var _queue: Array = []
var _cur := {}
var _chars := 0.0
var _hold := 0.0
var _slide := 0.0
var _t := 0.0
var _typed := 0

var _portrait: Portrait
var _name: Label
var _name_box: PanelContainer
var _text: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	_portrait = Portrait.new()
	_portrait.position = Vector2(16, 16)
	_portrait.size = Vector2(104, 104)
	add_child(_portrait)
	_name_box = PanelContainer.new()
	var sb := Style.box(Pal.ORANGE, 12, 3, Pal.INK)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	_name_box.add_theme_stylebox_override("panel", sb)
	_name_box.position = Vector2(136, -16)
	_name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_box)
	_name = Style.label("", 26, Pal.INK, Style.title_font())
	_name_box.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.fit_content = false
	_text.position = Vector2(138, 30)
	_text.size = Vector2(W - 160, H - 38)
	_text.add_theme_font_override("normal_font", Style.body_font())
	_text.add_theme_font_override("bold_font", Style.bold_font())
	_text.add_theme_font_size_override("normal_font_size", 25)
	_text.add_theme_font_size_override("bold_font_size", 25)
	_text.add_theme_color_override("default_color", Pal.CREAM)
	_text.add_theme_constant_override("line_separation", 4)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	modulate.a = 0.0


func say(who: String, bbcode: String, hold := 0.0, urgent := false) -> void:
	var item := {"who": who, "text": bbcode, "hold": hold, "at": Time.get_ticks_msec()}
	if urgent:
		_queue.push_front(item)
		if not _cur.is_empty():
			_hold = minf(_hold, 0.15)
			_chars = 9999.0
	else:
		_queue.append(item)


func clear() -> void:
	_queue.clear()
	_cur = {}


func busy() -> bool:
	return not _cur.is_empty() or not _queue.is_empty()


func _start(item: Dictionary) -> void:
	_cur = item
	_text.text = item.text
	_text.visible_characters = 0
	_chars = 0.0
	_typed = 0
	var sp: Array = SPEAKERS.get(item.who, ["???", Pal.CREAM])
	_name.text = sp[0]
	var sb := _name_box.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = sp[1]
	_portrait.species = item.who
	_portrait.bg = Pal.NAVY_LIGHT if item.who != "raccoon" else Pal.PURPLE_DARK
	_portrait.queue_redraw()
	var total := _text.get_total_character_count()
	_hold = float(item.hold) if float(item.hold) > 0.0 else 1.1 + total * 0.035
	Sfx.play("radio", -10.0)


func _process(delta: float) -> void:
	var rd := HudWidgets.real_delta(delta)
	_t += rd
	if _cur.is_empty():
		# 过时的台词（排队超过 9 秒）直接丢弃，保证对白跟得上战况
		while not _queue.is_empty() and Time.get_ticks_msec() - int(_queue[0].at) > 9000:
			_queue.pop_front()
		if not _queue.is_empty():
			_start(_queue.pop_front())
		else:
			_slide = maxf(0.0, _slide - rd * 4.0)
	else:
		_slide = minf(1.0, _slide + rd * 5.0)
		var total := _text.get_total_character_count()
		if _chars < total:
			_chars += rd * CPS
			_text.visible_characters = int(_chars)
			if int(_chars) / 2 > _typed:
				_typed = int(_chars) / 2
				Sfx.play("type", -16.0, 1.0, 0.15)
		else:
			_text.visible_characters = -1
			_hold -= rd
			if _hold <= 0.0:
				_cur = {}
	var e := ease(_slide, -2.2)
	modulate.a = e
	position.x = lerpf(-W - 30.0, 28.0, e)
	if e > 0.001:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	draw_style_box(Style.box(Color(0, 0, 0, 0.35), 22), Rect2(Vector2(6, 8), r.size))
	draw_style_box(Style.box(Color("0E1626", 0.94), 22, 4, Pal.INK), r)
	# 信号波形
	var typing := not _cur.is_empty() and _chars < _text.get_total_character_count()
	for i in 5:
		var hgt := 6.0 + (absf(sin(_t * 14.0 + i * 1.7)) * 16.0 if typing else 4.0)
		draw_rect(Rect2(Vector2(W - 70 + i * 10, 26 - hgt * 0.5), Vector2(6, hgt)), Color(Pal.TEAL, 0.85))
