class_name GameCamera
extends Node3D
## 45° 等距正交相机：平滑跟随 + 瞄准前瞻 + 创伤式震屏 + 后坐踢动。

const YAW := 45.0
const PITCH := -45.0
const SIZE := 15.5

var cam: Camera3D
var target: Node3D
var look_at_point := Vector3.ZERO
var aiming := false
var trauma := 0.0
var _kick := Vector3.ZERO
var _arm: Node3D
var _t := 0.0
var _zoom := 1.0
var _focus_pt := Vector3.ZERO
var _focus_t := 0.0
var _focus_w := 0.0


func _ready() -> void:
	_arm = Node3D.new()
	_arm.rotation_degrees = Vector3(PITCH, YAW, 0)
	add_child(_arm)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = SIZE
	cam.near = 0.5
	cam.far = 200.0
	cam.position = Vector3(0, 0, 60)
	_arm.add_child(cam)
	cam.make_current()
	Game.shake_requested.connect(add_trauma)


func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)


func kick(v: Vector3) -> void:
	_kick += v


## 镜头指引：推到某个位置停留 hold 秒后回到玩家身上
func focus(p: Vector3, hold := 1.4) -> void:
	_focus_pt = p
	_focus_t = hold


func snap() -> void:
	if target:
		global_position = target.global_position


## 屏幕上的“上/右”在地面上的方向（WASD 相对镜头移动）
func ground_forward() -> Vector3:
	var f := -cam.global_basis.z
	f.y = 0
	return f.normalized()


func ground_right() -> Vector3:
	var r := cam.global_basis.x
	r.y = 0
	return r.normalized()


## 屏幕方向（x 右、y 下）→ 地面方向。修正 45° 俯视的透视压缩：
## 地面“前方”投到屏幕上会被压扁成 sin(俯角) 倍，这里反算回来，保证“指哪打哪”。
func screen_to_ground(v: Vector2) -> Vector3:
	var l := v.length()
	if l < 0.0001:
		return Vector3.ZERO
	var s := sin(deg_to_rad(-PITCH))
	var w := ground_right() * v.x - ground_forward() * (v.y / s)
	return w.normalized() * minf(l, 1.0)


## 地面方向 → 屏幕方向（screen_to_ground 的逆运算）
func ground_to_screen(d: Vector3) -> Vector2:
	var s := sin(deg_to_rad(-PITCH))
	var v := Vector2(d.dot(ground_right()), -d.dot(ground_forward()) * s)
	return v.normalized() * minf(Vector2(d.x, d.z).length(), 1.0) if v.length() > 0.0001 else Vector2.ZERO


## 鼠标在高度 h 平面上的世界坐标
func mouse_on_plane(h: float) -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var n := cam.project_ray_normal(mp)
	if absf(n.y) < 0.0001:
		return o
	var t := (h - o.y) / n.y
	return o + n * t


func _process(delta: float) -> void:
	# 相机用真实时间，顿帧 / 子弹时间里也保持顺滑
	var rd := delta / maxf(Engine.time_scale, 0.01)
	rd = minf(rd, 0.05)
	_t += rd
	if target and is_instance_valid(target):
		# 物理插值开着时跟随「画面上」的位置，否则相机按 30Hz 一顿一顿地走
		var tp := (target as Node3D).get_global_transform_interpolated().origin if get_tree().physics_interpolation else target.global_position
		var ahead := look_at_point - tp
		ahead.y = 0
		var reach := 0.32 if aiming else 0.2
		ahead = ahead.limit_length(9.0) * reach
		var desired := tp + ahead
		if _focus_t > 0.0:
			_focus_t -= rd
			_focus_w = minf(1.0, _focus_w + rd * 3.0)
		else:
			_focus_w = maxf(0.0, _focus_w - rd * 2.5)
		desired = desired.lerp(_focus_pt, ease(_focus_w, -1.8))
		global_position = global_position.lerp(desired, 1.0 - exp(-7.0 * rd))
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-18.0 * rd))
	var shake := trauma * trauma
	trauma = maxf(0.0, trauma - rd * 1.8)
	cam.h_offset = (sin(_t * 47.0) * 0.6 + sin(_t * 91.0) * 0.4) * shake * 0.7 + _kick.dot(ground_right())
	cam.v_offset = (sin(_t * 53.0 + 1.3) * 0.6 + sin(_t * 83.0) * 0.4) * shake * 0.7 + _kick.dot(ground_forward()) * 0.7
	var want := (0.9 if aiming else 1.0) * (0.86 if Game.in_bullet_time() else 1.0) * (1.0 - 0.12 * _focus_w)
	_zoom = lerpf(_zoom, want, 1.0 - exp(-6.0 * rd))
	cam.size = SIZE * _zoom
