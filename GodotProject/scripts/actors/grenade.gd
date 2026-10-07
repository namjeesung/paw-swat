class_name Grenade
extends Node3D
## 罐头手雷：抛物线飞向目标点（0.55 秒），落地弹一下，引信闪 0.35 秒后爆炸。
## 飞行时目标点地面上有红色范围圈，让玩家看清会炸到哪里。爆炸不伤人质、不伤自己。

const RADIUS := 3.8
const DAMAGE := 7.0
const FLIGHT := 0.55
const FUSE := 0.35
const ARC_H := 2.4

var level: Level
var from := Vector3.ZERO
var to := Vector3.ZERO
var _t := 0.0
var _can: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _done := false


func _ready() -> void:
	top_level = true
	global_position = from
	_can = Node3D.new()
	add_child(_can)
	var body := MeshInstance3D.new()
	body.mesh = Models.cyl(0.16, 0.16, 0.3)
	body.material_override = Toon.mat(Color("5DBB63"), true, Pal.OUTLINE_PROP, 0.025)
	_can.add_child(body)
	var band := MeshInstance3D.new()
	band.mesh = Models.cyl(0.17, 0.17, 0.09)
	band.material_override = Toon.mat(Pal.CREAM, false)
	_can.add_child(band)
	var pin := MeshInstance3D.new()
	pin.mesh = Models.torus(0.04, 0.08)
	pin.material_override = Toon.mat(Pal.YELLOW, false)
	pin.position = Vector3(0, 0.2, 0)
	_can.add_child(pin)
	# 落点范围圈（不随手雷移动）
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS - 0.18
	tm.outer_radius = RADIUS
	tm.rings = 48
	_ring.mesh = tm
	# glow 材质是共享缓存，这里要改颜色所以复制一份
	_ring_mat = Toon.glow(Color(1.0, 0.3, 0.25, 0.55), 1.6).duplicate()
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.top_level = true
	add_child(_ring)
	_ring.global_position = Vector3(to.x, 0.06, to.z)
	_ring.scale = Vector3(0.2, 1, 0.2)
	var tw := _ring.create_tween()
	tw.tween_property(_ring, "scale", Vector3(1, 1, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < FLIGHT:
		var k := _t / FLIGHT
		var p := from.lerp(Vector3(to.x, 0.18, to.z), k)
		p.y += sin(k * PI) * ARC_H
		global_position = p
		_can.rotation.x += delta * 14.0
		_can.rotation.z += delta * 9.0
		return
	var f := _t - FLIGHT
	if f < 0.12:
		# 落地弹一下
		global_position = Vector3(to.x, 0.18 + sin(f / 0.12 * PI) * 0.25, to.z)
	else:
		global_position = Vector3(to.x, 0.18, to.z)
	# 引信：越来越快地闪
	var blink := fmod(f * (10.0 + f * 40.0), 1.0) < 0.5
	_ring_mat.albedo_color = Color(1.6, 0.48, 0.4, 0.85 if blink else 0.35)
	_can.scale = Vector3.ONE * (1.0 + (0.25 if blink else 0.0))
	if f >= FUSE:
		_explode()


func _explode() -> void:
	_done = true
	var pos := Vector3(to.x, 0.0, to.z)
	level.explode(pos, RADIUS, DAMAGE, level.player)
	Fx.ring(level, pos, Pal.YELLOW, RADIUS * 1.35, 0.5)
	Fx.dust(level, pos, 10, Color(0.6, 0.9, 0.55, 0.8), 5.0, 0.4)
	Game.hitstop(0.06)
	Game.shake(0.7)
	Game.vibrate(60)
	queue_free()
