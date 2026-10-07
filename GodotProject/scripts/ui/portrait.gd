class_name Portrait
extends Control
## 2D 头像：所有角色的扁平插画头像都由这里绘制（无需图片素材）。

@export var species := "shiba"
@export var bg := Pal.NAVY
@export var ring := Pal.INK
@export var dim := false

const SPECIES := {
	"shiba": {"fur": Color("E8963C"), "face": Color("FFE9C7"), "ear": "pointy", "inner": Color("FFE9C7"), "nose": Color("17181D")},
	"chief": {"fur": Color("8E9AAF"), "face": Color("DCE1EA"), "ear": "pointy", "inner": Color("C3CAD8"), "nose": Color("17181D")},
	"hamster": {"fur": Color("E9B872"), "face": Color("FFF1DC"), "ear": "round", "inner": Color("FFAABB"), "nose": Color("FF8FA6")},
	"raccoon": {"fur": Color("9EA3AD"), "face": Color("F4F4F6"), "ear": "round", "inner": Color("25222D"), "nose": Color("17181D")},
	"rat": {"fur": Color("9A8A7A"), "face": Color("D9CBB8"), "ear": "big", "inner": Color("FF9DB0"), "nose": Color("FF8FA6")},
	"cat_black": {"fur": Color("2E2E38"), "face": Color("3A3A46"), "ear": "pointy", "inner": Color("FF9DB0"), "nose": Color("FF8FA6")},
	"golden": {"fur": Color("E7B65C"), "face": Color("F7DDA8"), "ear": "floppy", "inner": Color("D49A3C"), "nose": Color("17181D")},
	"calico": {"fur": Color("FFF8EE"), "face": Color("FFF8EE"), "ear": "pointy", "inner": Color("FF9DB0"), "nose": Color("FF8FA6")},
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, ring)
	draw_circle(c, r - 4, bg)
	draw_face(self, c + Vector2(0, r * 0.1), r * 0.82, species)
	if dim:
		draw_circle(c, r - 4, Color(0.05, 0.07, 0.12, 0.72))
		draw_string(Style.num_font(), c + Vector2(-r, r * 0.3), "?", HORIZONTAL_ALIGNMENT_CENTER, r * 2, int(r * 0.9), Pal.CREAM)


static func _ell(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, outline := 0.0, rot := 0.0) -> void:
	var pts := Style.ellipse_points(c, rx, ry, 32, rot)
	if outline > 0.0:
		ci.draw_colored_polygon(Style.ellipse_points(c, rx + outline, ry + outline, 32, rot), Pal.INK)
	ci.draw_colored_polygon(pts, col)


static func _tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color, outline := 0.0) -> void:
	var pts := PackedVector2Array([a, b, c])
	ci.draw_colored_polygon(pts, col)
	if outline > 0.0:
		ci.draw_polyline(PackedVector2Array([a, b, c, a]), Pal.INK, outline, true)


## 在任意 CanvasItem 上画一个角色头像。c=头部中心，r=头部半径
static func draw_face(ci: CanvasItem, c: Vector2, r: float, species: String, mood := "normal") -> void:
	var sp: Dictionary = SPECIES.get(species, SPECIES["shiba"])
	var fur: Color = sp.fur
	var face: Color = sp.face
	var inner: Color = sp.inner
	var ol := maxf(2.0, r * 0.06)
	# 耳朵
	match String(sp.ear):
		"pointy":
			for s in [-1.0, 1.0]:
				var base := c + Vector2(0.62 * r * s, -0.42 * r)
				_tri(ci, base + Vector2(-0.3 * r, 0.12 * r), base + Vector2(0.3 * r, 0.12 * r) + Vector2(-0.12 * r * s, -0.1 * r), base + Vector2(0.12 * r * s, -0.62 * r), fur, ol)
				_tri(ci, base + Vector2(-0.14 * r, 0.04 * r), base + Vector2(0.14 * r, 0.04 * r) + Vector2(-0.06 * r * s, -0.05 * r), base + Vector2(0.08 * r * s, -0.38 * r), inner)
		"round":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(0.66 * r * s, -0.62 * r), 0.3 * r, 0.3 * r, fur, ol)
				_ell(ci, c + Vector2(0.66 * r * s, -0.62 * r), 0.16 * r, 0.16 * r, inner)
		"big":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(0.72 * r * s, -0.6 * r), 0.42 * r, 0.42 * r, fur, ol)
				_ell(ci, c + Vector2(0.72 * r * s, -0.6 * r), 0.27 * r, 0.27 * r, inner)
	# 头
	_ell(ci, c, r, r * 0.94, fur, ol)
	if species == "calico":
		_ell(ci, c + Vector2(-0.45 * r, -0.4 * r), 0.42 * r, 0.36 * r, Color("F2A24A"), 0.0, 0.4)
		_ell(ci, c + Vector2(0.5 * r, -0.45 * r), 0.32 * r, 0.3 * r, Color("2E2E38"), 0.0, -0.3)
	if String(sp.ear) == "floppy":
		for s in [-1.0, 1.0]:
			_ell(ci, c + Vector2(0.86 * r * s, 0.05 * r), 0.26 * r, 0.5 * r, inner, ol, -0.25 * s)
	# 脸下半部 / 口鼻
	_ell(ci, c + Vector2(0, 0.36 * r), 0.56 * r, 0.42 * r, face)
	if species == "raccoon":
		_ell(ci, c + Vector2(0, -0.04 * r), 0.86 * r, 0.24 * r, Color("25222D"))
	if species == "hamster":
		for s in [-1.0, 1.0]:
			_ell(ci, c + Vector2(0.5 * r * s, 0.28 * r), 0.3 * r, 0.26 * r, face)
			_ell(ci, c + Vector2(0.52 * r * s, 0.3 * r), 0.14 * r, 0.08 * r, Color(1.0, 0.55, 0.65, 0.6))
	# 眼睛
	for s in [-1.0, 1.0]:
		var e := c + Vector2(0.34 * r * s, -0.04 * r)
		if species == "raccoon":
			_ell(ci, e, 0.14 * r, 0.14 * r, Color.WHITE)
			_ell(ci, e + Vector2(0.02 * r, 0.02 * r), 0.07 * r, 0.07 * r, Pal.INK)
			ci.draw_line(e + Vector2(-0.16 * r * s, -0.16 * r), e + Vector2(0.14 * r * s, -0.27 * r), Pal.INK, maxf(2.0, r * 0.07))
		elif species == "cat_black":
			_ell(ci, e, 0.14 * r, 0.12 * r, Pal.YELLOW)
			_ell(ci, e, 0.035 * r, 0.1 * r, Pal.INK)
		else:
			_ell(ci, e, 0.11 * r, 0.12 * r, Pal.INK)
			_ell(ci, e + Vector2(0.04 * r, -0.05 * r), 0.04 * r, 0.04 * r, Color.WHITE)
		if species == "shiba":
			_ell(ci, e + Vector2(0, -0.26 * r), 0.09 * r, 0.05 * r, face)
		if species == "chief":
			var bw := maxf(3.0, r * 0.09)
			ci.draw_line(e + Vector2(-0.2 * r, -0.24 * r + 0.05 * r * s), e + Vector2(0.2 * r, -0.24 * r - 0.05 * r * s), Color.WHITE, bw)
	# 鼻子 + 嘴
	var nose: Color = sp.nose
	_ell(ci, c + Vector2(0, 0.2 * r), 0.11 * r, 0.075 * r, nose)
	var mw := maxf(2.0, r * 0.05)
	if mood == "sad":
		ci.draw_arc(c + Vector2(0, 0.46 * r), 0.12 * r, PI * 1.1, PI * 1.9, 10, Pal.INK, mw)
	else:
		ci.draw_arc(c + Vector2(-0.09 * r, 0.3 * r), 0.09 * r, 0.1, PI - 0.1, 8, Pal.INK, mw)
		ci.draw_arc(c + Vector2(0.09 * r, 0.3 * r), 0.09 * r, 0.1, PI - 0.1, 8, Pal.INK, mw)
	if species == "chief":
		_ell(ci, c + Vector2(-0.16 * r, 0.33 * r), 0.2 * r, 0.09 * r, Color.WHITE, 0.0, 0.3)
		_ell(ci, c + Vector2(0.16 * r, 0.33 * r), 0.2 * r, 0.09 * r, Color.WHITE, 0.0, -0.3)
	# 帽子
	if species == "shiba" or species == "chief":
		var cap_c := c + Vector2(0, -0.78 * r)
		var w := 0.72 if species == "shiba" else 0.82
		_ell(ci, cap_c, w * r, 0.3 * r, Pal.NAVY, ol)
		ci.draw_rect(Rect2(cap_c + Vector2(-w * r, 0), Vector2(w * 2 * r, 0.16 * r)), Pal.NAVY)
		ci.draw_line(cap_c + Vector2(-w * r * 1.08, 0.17 * r), cap_c + Vector2(w * r * 1.08, 0.17 * r), Pal.INK, ol * 1.4)
		ci.draw_colored_polygon(Style.star_points(cap_c + Vector2(0, -0.02 * r), 0.15 * r, 0.065 * r), Pal.YELLOW)
	if species == "raccoon":
		var bc := c + Vector2(0, -0.7 * r)
		_ell(ci, bc, 0.8 * r, 0.38 * r, Pal.PURPLE_DARK, ol)
		ci.draw_rect(Rect2(bc + Vector2(-0.8 * r, 0.0), Vector2(1.6 * r, 0.16 * r)), Pal.PURPLE_DARK)
		_ell(ci, bc + Vector2(0, -0.38 * r), 0.14 * r, 0.14 * r, Pal.CREAM, ol * 0.6)
