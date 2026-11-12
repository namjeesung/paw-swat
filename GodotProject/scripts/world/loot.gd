class_name Loot
extends Node3D
## 第二章的掉落物：罐头（主货币）/ 零件 / 鱼罐头（回血）。
## 生命周期：喷出（抛物线 + 落地弹一下）→ 原地转圈 → 玩家靠近就被「吸」过去 → 进背包。
## 吸收时「叮」一声，连续吸的音调越来越高（解压的关键反馈）。

const MAGNET_R := 4.5
const PICK_R := 0.55

var level: HarborLevel
var kind := "can"          # can / part / fish
var vel := Vector3.ZERO
var _t := 0.0
var _landed := false
var _bounced := false
var _magnet := false
var _speed := 0.0
var _spin := 0.0
var _mesh: Node3D

static var _meshes := {}
static var _mats := {}


static func _res(k: String) -> Array:
	if _meshes.is_empty():
		var can := CylinderMesh.new()
		can.top_radius = 0.11
		can.bottom_radius = 0.11
		can.height = 0.2
		can.radial_segments = 10
		can.rings = 1
		_meshes["can"] = can
		var band := CylinderMesh.new()
		band.top_radius = 0.114
		band.bottom_radius = 0.114
		band.height = 0.08
		band.radial_segments = 10
		band.rings = 1
		_meshes["band"] = band
		var gear := TorusMesh.new()
		gear.inner_radius = 0.05
		gear.outer_radius = 0.14
		gear.rings = 8
		gear.ring_segments = 4
		_meshes["part"] = gear
		_mats["can"] = Toon.mat(Pal.ORANGE, true, Pal.OUTLINE_PROP, 0.018)
		_mats["band"] = Toon.mat(Pal.CREAM, false)
		_mats["part"] = Toon.mat(Color("C9D1DC"), true, Pal.OUTLINE_PROP, 0.018)
		_mats["fish"] = Toon.mat(Color("4FA3C7"), true, Pal.OUTLINE_PROP, 0.018)
		(_mats["can"] as StandardMaterial3D).emission = Color(0.25, 0.1, 0.0)
	return [_meshes, _mats]


func _ready() -> void:
	var r := _res(kind)
	var meshes: Dictionary = r[0]
	var mats: Dictionary = r[1]
	_mesh = Node3D.new()
	add_child(_mesh)
	var body := MeshInstance3D.new()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.add_child(body)
	match kind:
		"part":
			body.mesh = meshes["part"]
			body.material_override = mats["part"]
			body.rotation_degrees = Vector3(90, 0, 0)
		_:
			body.mesh = meshes["can"]
			body.material_override = mats["fish"] if kind == "fish" else mats["can"]
			var band := MeshInstance3D.new()
			band.mesh = meshes["band"]
			band.material_override = mats["band"]
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mesh.add_child(band)
	_spin = randf_range(-6.0, 6.0)


func _process(delta: float) -> void:
	_t += delta
	if level == null or level.player == null:
		return
	var p := level.player
	var target := p.global_position + Vector3(0, 0.8 if not p.giant else 2.2, 0)
	if not _landed:
		vel.y -= 22.0 * delta
		global_position += vel * delta
		_mesh.rotation += Vector3(_spin, _spin * 0.7, 0) * delta
		if global_position.y <= 0.12 and vel.y < 0.0:
			global_position.y = 0.12
			if not _bounced and absf(vel.y) > 2.0:
				_bounced = true
				vel = Vector3(vel.x * 0.45, -vel.y * 0.35, vel.z * 0.45)
			else:
				_landed = true
				_mesh.rotation = Vector3.ZERO
		return
	if not _magnet:
		_mesh.rotation.y += delta * 3.0
		_mesh.position.y = 0.08 + sin(_t * 4.0 + _spin) * 0.05
		if p.dead or not level.can_take(kind):
			return
		var flat := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if flat < level.magnet_radius():
			_magnet = true
			_speed = 3.0
		return
	# 被吸过去：越来越快，最后贴上玩家
	if not level.can_take(kind):
		_magnet = false
		_landed = true
		return
	_speed = minf(_speed + 60.0 * delta, 22.0)
	var to := target - global_position
	var d := to.length()
	if d < PICK_R or d < _speed * delta:
		level.collect(kind, global_position)
		queue_free()
		return
	global_position += to / d * _speed * delta
	_mesh.scale = Vector3.ONE * clampf(d / 2.0, 0.6, 1.0)
