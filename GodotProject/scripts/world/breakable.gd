class_name Breakable
extends StaticBody3D
## 第二章：可以打碎的东西。打中会抖一下、闪一下；碎掉时木板/纸片飞散，罐头喷出来。
##   box       纸箱      1 下   2–3 罐            「噗」
##   wood      木箱      3 下   4–6 罐 + 小几率零件  每下飞一片木板
##   fish      鱼箱      2 下   2 罐 + 1 鱼罐头      小鱼蹦出来
##   barrel    油桶      1 下   不掉东西，爆炸，引爆周围（连锁）
##   container 货柜      14 下  14–20 罐 + 零件 + 可能有神装；门「哐」地弹开，子弹时间
##   gold      金色集装箱 30 下  40 罐 + 6 零件 + 神装；第 50 秒由龙门吊放下来

const KINDS := {
	"box": {"hp": 1.0, "size": Vector3(0.8, 0.7, 0.8)},
	"wood": {"hp": 3.0, "size": Vector3(0.95, 0.9, 0.95)},
	"fish": {"hp": 2.0, "size": Vector3(1.0, 0.5, 0.7)},
	"barrel": {"hp": 1.0, "size": Vector3(0.7, 0.95, 0.7)},
	"container": {"hp": 14.0, "size": Vector3(4.2, 2.4, 2.4)},
	"gold": {"hp": 30.0, "size": Vector3(4.2, 2.4, 2.4)},
}

var level: Level
var kind := "box"
var color := Color.WHITE
var hp := 1.0
var broken := false
var hit_ms := -100000              # 上次被打的时间（HUD 用来显示血条）
var _vis: Node3D
var _mats: Array[StandardMaterial3D] = []
var _shake := 0.0
var _flash := 0.0
var _base_pos := Vector3.ZERO


func setup(k: String, c := Color.WHITE) -> Breakable:
	kind = k
	color = c
	return self


func size() -> Vector3:
	return KINDS[kind].size


func _ready() -> void:
	collision_layer = Bullet.LAYER_WORLD
	collision_mask = 0
	hp = float(KINDS[kind].hp)
	var sz := size()
	# 子弹在胸口高度（Bullet.HEIGHT）水平飞：矮箱子的碰撞体至少 1.4 米高，不然子弹会从上面飞过去
	var ch := maxf(sz.y, 1.4)
	var cs := CollisionShape3D.new()
	if kind == "barrel":
		var cyl := CylinderShape3D.new()
		cyl.radius = sz.x * 0.5
		cyl.height = ch
		cs.shape = cyl
	else:
		var b := BoxShape3D.new()
		b.size = Vector3(sz.x, ch, sz.z)
		cs.shape = b
	cs.position.y = ch * 0.5
	add_child(cs)
	_vis = Node3D.new()
	add_child(_vis)
	_build_visual()
	_base_pos = _vis.position


func _m(c: Color, outline := true) -> StandardMaterial3D:
	var m := Toon.mat(c, outline, Pal.OUTLINE_PROP, 0.022, 0.15)
	_mats.append(m)
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	_vis.add_child(mi)
	return mi


func _build_visual() -> void:
	var sz := size()
	match kind:
		"box":
			var c := Color("C9A26B")
			_part(Models.box(sz), _m(c), Vector3(0, sz.y * 0.5, 0))
			_part(Models.box(Vector3(sz.x + 0.01, 0.06, 0.18)), _m(Color("E8D9B5"), false), Vector3(0, sz.y + 0.005, 0))
			_part(Models.box(Vector3(0.3, 0.2, 0.01)), _m(Color("3E7CB1"), false), Vector3(0.12, sz.y * 0.55, sz.z * 0.5 + 0.006))
		"wood":
			var c := Color("B07A45")
			_part(Models.box(sz), _m(c), Vector3(0, sz.y * 0.5, 0))
			for k in 3:
				_part(Models.box(Vector3(sz.x + 0.02, 0.07, sz.z + 0.02)), _m(c.darkened(0.3), false), Vector3(0, 0.1 + k * (sz.y - 0.2) * 0.5, 0))
			_part(Models.box(Vector3(0.08, sz.y * 1.1, sz.z + 0.02)), _m(c.darkened(0.3), false), Vector3(0, sz.y * 0.5, 0), Vector3(0, 0, 40))
		"fish":
			var c := Color("4FA3C7")
			_part(Models.box(sz), _m(c), Vector3(0, sz.y * 0.5, 0))
			_part(Models.box(Vector3(sz.x * 0.9, 0.04, sz.z * 0.9)), _m(Color("D9F2FF"), false), Vector3(0, sz.y + 0.01, 0))
			for k in 3:
				_part(Models.sphere(0.1), _m(Color("9FB8C9"), false), Vector3(-0.28 + k * 0.28, sz.y + 0.06, 0.05 * (k - 1)), Vector3.ZERO, Vector3(1.6, 0.6, 0.8))
		"barrel":
			var c := Color("D64545")
			_part(Models.cyl(sz.x * 0.5, sz.x * 0.5, sz.y), _m(c), Vector3(0, sz.y * 0.5, 0))
			_part(Models.cyl(sz.x * 0.52, sz.x * 0.52, 0.14), _m(Pal.YELLOW, false), Vector3(0, sz.y * 0.55, 0))
			_part(Models.cyl(sz.x * 0.52, sz.x * 0.52, 0.06), _m(Color("1B1F2A"), false), Vector3(0, sz.y * 0.55, 0))
		"container", "gold":
			var c := color if kind == "container" else Color("FFC93C")
			var body := _m(c)
			if kind == "gold":
				body.emission = Color(0.35, 0.25, 0.0)
			_part(Models.box(sz), body, Vector3(0, sz.y * 0.5, 0))
			for k in 7:
				var t := -0.5 + (k + 0.5) / 7.0
				_part(Models.box(Vector3(0.1, sz.y - 0.1, sz.z + 0.06)), _m(c.darkened(0.2), false), Vector3(t * (sz.x - 0.2), sz.y * 0.5, 0))
			# 朝镜头那面的两扇门 + 门闩（金色集装箱上画个罐头标志）
			_part(Models.box(Vector3(sz.x * 0.46, sz.y * 0.9, 0.06)), _m(c.lightened(0.12), false), Vector3(-sz.x * 0.24, sz.y * 0.5, sz.z * 0.5 + 0.03))
			_part(Models.box(Vector3(sz.x * 0.46, sz.y * 0.9, 0.06)), _m(c.lightened(0.12), false), Vector3(sz.x * 0.24, sz.y * 0.5, sz.z * 0.5 + 0.03))
			for sx in [-0.05, 0.05]:
				_part(Models.box(Vector3(0.05, sz.y * 0.8, 0.08)), _m(Color("2A2E38"), false), Vector3(sx * sz.x, sz.y * 0.5, sz.z * 0.5 + 0.07))
			if kind == "gold":
				_part(Models.cyl(0.35, 0.35, 0.1), _m(Pal.ORANGE, false), Vector3(-sz.x * 0.24, sz.y * 0.55, sz.z * 0.5 + 0.1), Vector3(90, 0, 0))
				_part(Models.cyl(0.36, 0.36, 0.11), _m(Pal.CREAM, false), Vector3(-sz.x * 0.24, sz.y * 0.55, sz.z * 0.5 + 0.1), Vector3(90, 0, 0), Vector3(1, 0.35, 1))


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 6.0)
		_vis.position = _base_pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * _shake * 0.08
		_vis.scale = Vector3(1.0 + _shake * 0.06, 1.0 - _shake * 0.05, 1.0 + _shake * 0.06)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 8.0)
		for m in _mats:
			m.emission = Color(1, 1, 1) * _flash * 0.8 + (Color(0.35, 0.25, 0.0) if kind == "gold" else Color.BLACK)
	if _shake <= 0.0 and _flash <= 0.0:
		set_process(false)


## 子弹 / 爆炸打中。返回 true = 子弹被吃掉。
func take_hit(dmg: float, dir: Vector3, _from: Vector3, src: Node) -> bool:
	if broken:
		return false
	hp -= dmg
	hit_ms = Time.get_ticks_msec()
	_shake = 1.0
	_flash = 1.0
	if src == level.player and level.hud:
		level.hud.hitmarker(hp <= 0.0)
	set_process(true)
	match kind:
		"wood":
			Sfx.play("clank", -10.0, randf_range(1.2, 1.4), 0.1)
			_chip(dir, Color("B07A45"))
		"container", "gold":
			Sfx.play("clank", -12.0, randf_range(0.7, 0.85), 0.1)
		"fish":
			Sfx.play("splat", -12.0, 1.4, 0.1)
		_:
			Sfx.play("paper", -10.0, 1.3, 0.1)
	if hp <= 0.0:
		_break(dir, src)
	return true


## 打中木箱时飞出一小片木板
func _chip(dir: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.box(Vector3(0.28, 0.05, 0.1))
	mi.material_override = Toon.prop(c.lightened(0.1))
	level.add_child(mi)
	var from := global_position + Vector3(0, size().y * 0.7, 0)
	mi.global_position = from
	var to := from - dir.normalized() * 0.9 + Vector3(randf_range(-0.4, 0.4), -size().y * 0.7, randf_range(-0.4, 0.4))
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.35)
	tw.tween_interval(0.6)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(mi.queue_free)


func _break(dir: Vector3, src: Node) -> void:
	broken = true
	collision_layer = 0
	var h := level as HarborLevel
	var center := global_position + Vector3(0, size().y * 0.5, 0)
	var debris_col := Color("C9A26B")
	match kind:
		"box":
			Sfx.play("paper", -2.0, 0.9, 0.1)
			h.burst_loot(center, randi_range(2, 3), 0, 0)
		"wood":
			Sfx.play("bonk", -4.0, 1.1, 0.1)
			debris_col = Color("B07A45")
			h.burst_loot(center, randi_range(4, 6), 1 if randf() < 0.2 else 0, 0)
		"fish":
			Sfx.play("splat", -2.0, 1.0, 0.1)
			debris_col = Color("4FA3C7")
			h.burst_loot(center, 2, 0, 1)
		"barrel":
			debris_col = Color("D64545")
			Fx.ring(level, global_position, Pal.RED, 1.2, 0.3)
			h.chain_explode(global_position, src)
		"container", "gold":
			debris_col = color if kind == "container" else Color("FFC93C")
			_burst_container(h, center, dir)
	Fx.dust(level, global_position, 8 if size().x < 2.0 else 20, Color(1, 0.95, 0.85, 0.8), 2.6, 0.3 if size().x < 2.0 else 0.5)
	_debris(debris_col, 6 if size().x < 2.0 else 12)
	h.on_smashed(self)
	var tw := create_tween()
	tw.tween_property(_vis, "scale", Vector3(1.25, 0.05, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


## 货柜 / 金色集装箱：门「哐」地弹开，子弹时间，罐头像瀑布一样涌出来
func _burst_container(h: HarborLevel, center: Vector3, _dir: Vector3) -> void:
	Sfx.play("breach", -1.0, 0.9 if kind == "container" else 0.7, 0.0)
	Game.shake(0.6 if kind == "container" else 0.9)
	Game.bullet_time(0.5 if kind == "container" else 0.9)
	var front := global_position + Vector3(0, 1.0, size().z * 0.5 + 0.4)
	if kind == "gold":
		Sfx.play("powerup", -2.0, 1.0, 0.0)
		Fx.popup(level, global_position + Vector3(0, 3.0, 0), "大丰收!", Pal.YELLOW, 110, true, 1.6, 1.4)
		h.burst_loot(front, 40, 6, 0, true)
		h.drop_weapon(front + Vector3(0, -1.0, 1.4))
	else:
		Fx.popup(level, global_position + Vector3(0, 2.8, 0), "开箱!", Pal.ORANGE, 84, true, 1.2, 1.0)
		h.burst_loot(front, randi_range(14, 20), randi_range(2, 3), 0, true)
		if randf() < 0.6:
			h.drop_weapon(front + Vector3(0, -1.0, 1.4))
	# 两扇门飞出去
	for sx in [-1.0, 1.0]:
		var door := MeshInstance3D.new()
		door.mesh = Models.box(Vector3(size().x * 0.46, size().y * 0.9, 0.06))
		door.material_override = Toon.prop_outlined(color.lightened(0.12) if kind == "container" else Color("FFD25A"))
		level.add_child(door)
		door.global_position = global_position + Vector3(size().x * 0.24 * sx, size().y * 0.5, size().z * 0.5 + 0.05)
		var tw := door.create_tween()
		var to := door.global_position + Vector3(sx * 1.8, -size().y * 0.42, 2.2)
		tw.tween_property(door, "global_position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(door, "rotation", Vector3(-PI / 2, sx * 0.6, 0), 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(2.5)
		tw.tween_property(door, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(door.queue_free)


## 碎片：几块小方块往外飞、落地、缩小消失
func _debris(c: Color, n: int) -> void:
	var sz := size()
	var mat := Toon.prop(c)
	for i in n:
		var mi := MeshInstance3D.new()
		var s := randf_range(0.12, 0.28) * (1.0 if sz.x < 2.0 else 2.0)
		mi.mesh = Models.box(Vector3(s, s * 0.4, s * 0.8))
		mi.material_override = mat
		level.add_child(mi)
		var from := global_position + Vector3(randf_range(-0.3, 0.3) * sz.x, sz.y * randf_range(0.3, 0.9), randf_range(-0.3, 0.3) * sz.z)
		mi.global_position = from
		var a := randf() * TAU
		var to := global_position + Vector3(cos(a), 0, sin(a)) * randf_range(0.6, 1.6) * (1.0 if sz.x < 2.0 else 2.2) + Vector3(0, 0.05, 0)
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", (from + to) * 0.5 + Vector3(0, 0.8, 0), 0.18).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.4)
		tw.tween_property(mi, "global_position", to, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_interval(randf_range(0.8, 1.4))
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(mi.queue_free)
