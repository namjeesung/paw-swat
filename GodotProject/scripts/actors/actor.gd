class_name Actor
extends CharacterBody3D
## 角色基类：血量、朝向、击退、碰撞体、脚下圆形阴影。

var level: Level
var model: CharModel
var max_hp := 10.0
var hp := 10.0
var team := 0
var facing := Vector3(0, 0, 1)
var knock := Vector3.ZERO

static var _blob_mat: StandardMaterial3D


func _add_capsule(r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	cs.shape = cap
	cs.position.y = h * 0.5 + 0.06
	add_child(cs)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	# 俯视角只在平面上滑墙，3 次足够（默认 6 次，人多时是物理开销大头）
	max_slides = 3


## 柔和的圆形投影，让角色在等距视角下“站得住”
func add_blob_shadow(radius: float) -> void:
	if _blob_mat == null:
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.albedo_texture = Fx.tex("soft")
		_blob_mat.albedo_color = Color(0.02, 0.03, 0.08, 0.55)
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var p := PlaneMesh.new()
	p.size = Vector2(radius * 2.4, radius * 2.4)
	var mi := MeshInstance3D.new()
	mi.mesh = p
	mi.material_override = _blob_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.025
	add_child(mi)


func face_toward(dir: Vector3, delta: float, speed := 18.0) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	facing = dir.normalized()
	var yaw := atan2(facing.x, facing.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, 1.0 - exp(-speed * delta))


func model_forward() -> Vector3:
	return Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))


func center() -> Vector3:
	return global_position + Vector3(0, 0.7, 0)


## 被子弹/攻击命中。返回 false 表示子弹应当穿过（如翻滚无敌）
func take_hit(_dmg: float, _dir: Vector3, _from: Vector3, _source: Node) -> bool:
	return false


## 轻量移动：只平移不做碰撞检测（下一次正常 _move 会把轻微嵌入墙的部分推出来）。
## 只在速度很小（一步 < 0.1 米）时由调用方使用，不会穿墙。
func _move_cheap(delta: float) -> bool:
	var v := velocity + knock
	if v.length() * delta > 0.1:
		return false
	global_position += v * delta
	global_position.y = 0.0
	return true


func _move(delta_mult := 1.0) -> void:
	var keep := velocity
	velocity = (keep + knock) * delta_mult
	move_and_slide()
	velocity = keep
	global_position.y = 0.0


## 物理插值（流畅画质）：角色在物理帧里移动，画面在两个物理帧之间插值。
## 关卡根节点关掉插值（特效、相机、UI 在 _process 里每帧更新，不需要插值），角色重新打开。
func _enter_tree() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
