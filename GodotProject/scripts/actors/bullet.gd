class_name Bullet
extends Node3D
## 子弹：逐帧射线检测。低矮掩体规则——射手离掩体 1.8m 内可越过掩体射击，否则被挡住。

const HEIGHT := 0.72
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_HOSTAGE := 8
const LAYER_LOWCOVER := 32
const OVER_COVER := 1.8

var level: Level
var dir := Vector3.FORWARD
var speed := 60.0
var dmg := 1.0
var from_player := true
var shooter: Node
var origin := Vector3.ZERO
var travelled := 0.0
var max_dist := 40.0
var _exclude: Array[RID] = []
var _mesh: MeshInstance3D
## Reuse one query resource per projectile instead of allocating one at 120 Hz.
var _ray_query := PhysicsRayQueryParameters3D.new()
static var _rocket_mat: StandardMaterial3D
var kind := "bullet"
var explode := 0.0
var pierce := 0
var knock_mult := 1.0
var homing: Node3D
var color := Color(1.0, 0.86, 0.45)
var _smoke_t := 0.0
## 神装子弹带“友军识别”，不会打到人质
var safe := false


## opts: speed / max_dist / kind("rocket") / explode(半径) / pierce(贯穿数) / knock / homing / color
func setup(lv: Level, o: Vector3, d: Vector3, player: bool, damage: float, src: Node, opts := {}) -> void:
	level = lv
	origin = o
	dir = Vector3(d.x, 0, d.z).normalized()
	from_player = player
	dmg = damage
	shooter = src
	speed = 64.0 if player else 15.5
	speed = float(opts.get("speed", speed))
	max_dist = float(opts.get("max_dist", max_dist))
	kind = String(opts.get("kind", "bullet"))
	explode = float(opts.get("explode", 0.0))
	pierce = int(opts.get("pierce", 0))
	knock_mult = float(opts.get("knock", 1.0))
	safe = bool(opts.get("safe", false))
	var h = opts.get("homing", null)
	homing = h if h is Node3D and is_instance_valid(h) else null
	if dmg > 1.0 and kind == "bullet":
		color = Color(1.0, 0.45, 0.15)
	color = opts.get("color", color)
	position = o
	if src is CollisionObject3D:
		_exclude.append((src as CollisionObject3D).get_rid())


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == "rocket":
		_mesh.mesh = Models.capsule(0.13, 0.6)
		_mesh.rotation_degrees = Vector3(90, 0, 0)
		if _rocket_mat == null:
			_rocket_mat = Toon.mat(Pal.RED, true, Pal.INK, 0.02)
		_mesh.material_override = _rocket_mat
		var tip := MeshInstance3D.new()
		tip.mesh = Models.sphere(0.12)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tip.material_override = Toon.glow(Pal.YELLOW, 2.5)
		tip.position = Vector3(0, -0.32, 0)
		_mesh.add_child(tip)
	elif from_player:
		var big := dmg > 1.0
		_mesh.mesh = Models.box(Vector3(0.09, 0.09, 1.0) if big else Vector3(0.065, 0.065, 0.85))
		_mesh.material_override = Toon.glow(color, 3.0)
		_mesh.visible = false
	else:
		_mesh.mesh = Models.sphere(0.13)
		_mesh.material_override = Toon.glow(Color(0.85, 0.4, 1.0), 2.6)
		var trail := MeshInstance3D.new()
		trail.mesh = Models.box(Vector3(0.12, 0.12, 0.7))
		trail.material_override = Toon.glow(Color(0.65, 0.25, 1.0, 0.45), 1.6)
		trail.position = Vector3(0, 0, 0.38)
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.add_child(trail)
	add_child(_mesh)
	look_at(global_position + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	# Bandits now despawn while their earlier projectiles may still be flying.
	if not is_instance_valid(shooter):
		shooter = null
	var d := delta * (Game.player_time_mult() if from_player else 1.0)
	# 子弹吸附：朝锁定目标轻微转向（只在偏差很小时生效，不会“拐弯”）
	if homing and is_instance_valid(homing) and homing.has_method("is_active") and homing.is_active():
		var want := homing.global_position - global_position
		want.y = 0
		if want.length() > 0.5:
			want = want.normalized()
			var ang := dir.signed_angle_to(want, Vector3.UP)
			if absf(ang) < deg_to_rad(14.0):
				dir = dir.rotated(Vector3.UP, clampf(ang, -deg_to_rad(90.0) * d, deg_to_rad(90.0) * d))
				look_at(global_position + dir, Vector3.UP)
	if kind == "rocket":
		_smoke_t -= d
		if _smoke_t <= 0.0:
			_smoke_t = 0.03
			Fx.dust(level, global_position - dir * 0.4, 1, Color(0.9, 0.9, 0.95, 0.6), 0.4, 0.16)
	var step := speed * d
	var from := global_position
	var to := from + dir * step
	var space := get_world_3d().direct_space_state
	var mask := (LAYER_WORLD | LAYER_ENEMY | LAYER_HOSTAGE | LAYER_LOWCOVER) if from_player \
		else (LAYER_WORLD | LAYER_PLAYER | LAYER_LOWCOVER)
	if safe:
		mask &= ~LAYER_HOSTAGE
	for i in 8:
		_ray_query.from = from
		_ray_query.to = to
		_ray_query.collision_mask = mask
		_ray_query.exclude = _exclude
		var hit := space.intersect_ray(_ray_query)
		if hit.is_empty():
			break
		var col: Object = hit.collider
		var pos: Vector3 = hit.position
		if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & LAYER_LOWCOVER) != 0:
			if Vector2(origin.x, origin.z).distance_to(Vector2(pos.x, pos.z)) < OVER_COVER:
				_exclude.append((col as CollisionObject3D).get_rid())
				from = pos
				continue
			_impact(pos, hit.normal, true)
			return
		if col.has_method("take_hit"):
			if explode > 0.0:
				_impact(pos, -dir, false)
				return
			if col.take_hit(dmg, dir * knock_mult, origin, shooter):
				_hit_fx(pos, col)
				if pierce > 0:
					pierce -= 1
					_exclude.append((col as CollisionObject3D).get_rid())
					from = pos
					continue
				queue_free()
				return
			_exclude.append((col as CollisionObject3D).get_rid())
			from = pos
			continue
		_impact(pos, hit.normal, false)
		return
	global_position = to
	travelled += step
	if from_player and not _mesh.visible and travelled > 0.5:
		_mesh.visible = true
	if travelled > max_dist:
		if explode > 0.0:
			_impact(global_position, Vector3.UP, false)
		else:
			queue_free()


func _impact(pos: Vector3, normal: Vector3, cover: bool) -> void:
	if explode > 0.0:
		level.explode(pos, explode, dmg, shooter)
		queue_free()
		return
	var col := color if from_player else Color(0.85, 0.5, 1.0)
	Fx.spark(level, pos, normal, col, 6, 4.5)
	if cover and not from_player and level.player and not level.player.dead:
		if pos.distance_to(level.player.global_position) < 2.2:
			level.on_cover_block(pos)
	queue_free()


func _hit_fx(pos: Vector3, actor: Object) -> void:
	if from_player:
		Game.run.hits = int(Game.run.hits) + 1
		var killed: bool = actor.has_method("is_active") and not actor.is_active()
		level.hud.hitmarker(killed)
	Fx.spark(level, pos, -dir, Color(1, 0.95, 0.85), 7, 5.0)


func _enter_tree() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
