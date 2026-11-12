class_name CrabMech
extends Node3D
## 第二章 Boss 的外形：黑眼圈帮老大「老K」开的罐头蟹机甲。
## 只是外观：挂在 boss 僵尸鼠节点下面（原来的鼠王模型藏起来），
## 移动 / 血量 / 碰撞仍由 Zombie 负责，技能由 RatKing（Boss 大脑）控制。
##   六条腿走路时一起一伏；两只大钳子会开合（蓄力时张开）；背后一门罐头炮；
##   玻璃驾驶舱里坐着戴船长帽的浣熊老K。

var shell_mats: Array[StandardMaterial3D] = []
var pilot: CharModel
var claw_open := 0.0             # 0 合 → 1 张开
var _walk := 0.0
var _flash := 0.0
var _legs: Array[Node3D] = []
var _claws: Array[Node3D] = []
var _pincers: Array[Node3D] = []
var _body: Node3D
var _cannon: Node3D


func _m(c: Color, outline := true) -> StandardMaterial3D:
	var m := Toon.mat(c, outline, Pal.OUTLINE_ENEMY, 0.03)
	shell_mats.append(m)
	return m


func _p(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _ready() -> void:
	var red := _m(Color("D9483B"))
	var dark := _m(Color("3A2F3F"))
	var steel := _m(Color("9AA3B5"))
	var stripe := _m(Pal.YELLOW, false)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.85, 1.0, 0.28)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body = Node3D.new()
	_body.position.y = 1.15
	add_child(_body)
	# 壳：一个压扁的集装箱 + 黄黑警示条
	_p(_body, Models.box(Vector3(2.6, 0.9, 2.0)), red, Vector3.ZERO)
	_p(_body, Models.box(Vector3(2.64, 0.16, 2.04)), stripe, Vector3(0, -0.2, 0))
	for k in 5:
		_p(_body, Models.box(Vector3(0.08, 0.8, 2.04)), dark, Vector3(-1.0 + k * 0.5, 0, 0))
	var lab := Label3D.new()
	lab.text = "K"
	lab.font = Style.num_font()
	lab.font_size = 120
	lab.pixel_size = 0.006
	lab.modulate = Pal.YELLOW
	lab.outline_size = 16
	lab.outline_modulate = Pal.INK
	lab.position = Vector3(0, 0.1, 1.03)
	_body.add_child(lab)
	# 眼睛（两根小天线上的灯）
	for sx in [-0.45, 0.45]:
		_p(_body, Models.cyl(0.04, 0.04, 0.5), steel, Vector3(sx, 0.65, 0.85))
		_p(_body, Models.sphere(0.13), Toon.glow(Color(1.0, 0.85, 0.2), 2.4), Vector3(sx, 0.95, 0.85))
	# 驾驶舱（玻璃罩 + 老K）
	pilot = HarborLevel.make_boss_k()
	pilot.scale = Vector3.ONE * 0.75
	pilot.position = Vector3(0, 0.45, 0.1)
	_body.add_child(pilot)
	_p(_body, Models.sphere(0.75), glass, Vector3(0, 0.75, 0.1), Vector3.ZERO, Vector3(1, 0.85, 1))
	# 罐头炮（背上）
	_cannon = Node3D.new()
	_cannon.position = Vector3(0.75, 0.6, -0.6)
	_body.add_child(_cannon)
	_p(_cannon, Models.cyl(0.24, 0.3, 1.1), dark, Vector3(0, 0.3, 0), Vector3(-35, 0, 0))
	_p(_cannon, Models.cyl(0.26, 0.26, 0.12), stripe, Vector3(0, 0.75, 0.32), Vector3(-35, 0, 0))
	# 烟囱
	_p(_body, Models.cyl(0.14, 0.18, 0.7), steel, Vector3(-0.8, 0.75, -0.7))
	# 六条腿
	for side in [-1.0, 1.0]:
		for k in 3:
			var hip := Node3D.new()
			hip.position = Vector3(1.2 * side, -0.15, -0.7 + k * 0.7)
			_body.add_child(hip)
			_p(hip, Models.box(Vector3(0.9, 0.18, 0.18)), dark, Vector3(0.4 * side, 0.15, 0), Vector3(0, 0, 25 * side))
			_p(hip, Models.box(Vector3(0.18, 1.2, 0.18)), steel, Vector3(0.85 * side, -0.35, 0), Vector3(0, 0, -12 * side))
			hip.set_meta("side", side)
			hip.set_meta("phase", k * 2.1 + (0.0 if side > 0 else PI))
			_legs.append(hip)
	# 两只大钳子
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.9 * side, 0.0, 1.0)
		_body.add_child(arm)
		_p(arm, Models.box(Vector3(0.3, 0.3, 0.9)), dark, Vector3(0, 0, 0.4), Vector3(0, -20 * side, 0))
		var claw := Node3D.new()
		claw.position = Vector3(0.25 * side, 0.0, 0.95)
		arm.add_child(claw)
		_p(claw, Models.box(Vector3(0.6, 0.55, 0.7)), red, Vector3(0, 0, 0.1))
		var top := Node3D.new()
		top.position = Vector3(0, 0.18, 0.4)
		claw.add_child(top)
		_p(top, Models.box(Vector3(0.5, 0.18, 0.7)), red, Vector3(0, 0, 0.3))
		_p(top, Models.box(Vector3(0.52, 0.06, 0.2)), stripe, Vector3(0, 0.1, 0.55))
		var bot := Node3D.new()
		bot.position = Vector3(0, -0.18, 0.4)
		claw.add_child(bot)
		_p(bot, Models.box(Vector3(0.45, 0.16, 0.6)), red, Vector3(0, 0, 0.25))
		_claws.append(arm)
		_pincers.append(top)
		_pincers.append(bot)


## 每帧由 Boss 大脑调用：k = 0（站着）~ 1（全速）
func animate(delta: float, k: float) -> void:
	_walk += delta * (2.0 + 8.0 * k)
	_body.position.y = 1.15 + sin(_walk * 2.0) * 0.05 * (0.3 + k)
	_body.rotation.z = sin(_walk) * 0.04 * k
	for leg in _legs:
		var ph: float = leg.get_meta("phase")
		var side: float = leg.get_meta("side")
		leg.rotation.z = sin(_walk + ph) * 0.25 * k * side
		leg.rotation.y = cos(_walk + ph) * 0.2 * k
	for i in _pincers.size():
		var up := i % 2 == 0
		var a := deg_to_rad(-8.0 - 32.0 * claw_open) if up else deg_to_rad(8.0 + 22.0 * claw_open)
		_pincers[i].rotation.x = lerp_angle(_pincers[i].rotation.x, a, 1.0 - exp(-14.0 * delta))
	for i in _claws.size():
		_claws[i].rotation.x = sin(_walk * 0.7 + i) * 0.08 - claw_open * 0.25
	if pilot:
		pilot.head.rotation.y = sin(_walk * 0.3) * 0.4
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for m in shell_mats:
			m.emission = Color(1, 1, 1) * _flash * 0.7


func flash() -> void:
	_flash = 1.0


func cannon_tip() -> Vector3:
	return _cannon.global_position + _cannon.global_basis.y * 0.9 + _cannon.global_basis.z * 0.5


## 暴怒：壳变成暗红、冒火星
func enrage() -> void:
	for m in shell_mats:
		m.albedo_color = m.albedo_color.lerp(Color("8E1E1E"), 0.45)
