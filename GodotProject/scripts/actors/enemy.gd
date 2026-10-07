class_name Enemy
extends Actor
## 黑眼圈帮成员。
## rat    老鼠小毛贼：成群冲锋，近身蓄力扑咬
## raccoon 浣熊打手：保持距离，开枪前红色激光预警，三连发
## taker  劫持者：挟持人质原地不动，两连发
## 血量归零即永久制服；立即停止战斗，短暂消散后释放整个节点。

const DESPAWN_TIME := 0.25

var kind := "raccoon"
var zone := "shop"
var state := "idle"
var alerted := false
var speed := 3.3
var stationary := false
var hostage: Hostage
var down_t := 0.0
## 被击倒时掉落的神装（空字符串 = 不掉落）
var drop := ""
var _gave_grenade := false
var _clear_t := 0.0
var _clear_cache := false

var _path := PackedVector3Array()
var _path_i := 0
var _home_yaw := 0.0
var _repath := 0.0
var _attack_cd := 1.0
var _tele := 0.0
var _burst := 0
var _burst_cd := 0.0
var _stun := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _bite_wind := 0.0
var _bite_cd := 0.0
var _lunge := 0.0
var _lunge_dir := Vector3.ZERO
var _bite_done := false
var _look_t := 0.0
var _idle_yaw := 0.0
var _laser: MeshInstance3D
var _mark: Label3D


func setup(k: String, z: String, face: Vector3) -> void:
	kind = k
	zone = z
	facing = face.normalized()


func _ready() -> void:
	collision_layer = Bullet.LAYER_ENEMY
	collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	match kind:
		"rat":
			max_hp = 3.0
			speed = 4.7
			model = Models.rat()
			_add_capsule(0.28, 0.95)
		"taker":
			max_hp = 8.0
			speed = 0.0
			stationary = true
			model = Models.raccoon(true)
			_add_capsule(0.32, 1.15)
		_:
			max_hp = 6.0
			speed = 3.3
			model = Models.raccoon()
			_add_capsule(0.32, 1.15)
	max_hp *= Game.dv("enemy_hp")
	speed *= Game.dv("enemy_speed")
	hp = max_hp
	add_child(model)
	_home_yaw = atan2(facing.x, facing.z)
	model.rotation.y = _home_yaw
	model.tail_wag = 0.25
	add_blob_shadow(0.48 if kind != "rat" else 0.4)
	_build_laser()
	_build_mark()
	_attack_cd = randf_range(0.5, 1.2)


func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	_laser.mesh = Models.box(Vector3(0.04, 0.04, 1.0))
	_laser.material_override = Toon.glow(Color(1.0, 0.15, 0.2, 0.75), 2.2)
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)


func _build_mark() -> void:
	_mark = Label3D.new()
	_mark.text = "!"
	_mark.font = Style.num_font()
	_mark.font_size = 120
	_mark.pixel_size = 0.006
	_mark.modulate = Pal.ORANGE
	_mark.outline_size = 22
	_mark.outline_modulate = Pal.INK
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.no_depth_test = true
	_mark.render_priority = 20
	_mark.outline_render_priority = 19
	_mark.position = Vector3(0, 1.9 if kind != "rat" else 1.5, 0)
	_mark.visible = false
	add_child(_mark)


func is_active() -> bool:
	return state in ["idle", "combat", "stunned"]


func is_neutralized() -> bool:
	return not is_active()


# ------------------------------------------------------------------ 主循环

func _physics_process(delta: float) -> void:
	if level == null or not is_active():
		return
	if level.finished:
		_laser.visible = false
		model.animate(delta, 0.0)
		return
	_bite_cd -= delta
	match state:
		"stunned":
			_stun -= delta
			velocity = velocity.move_toward(Vector3.ZERO, 25.0 * delta)
			model.body.rotation.y = sin(_stun * 30.0) * 0.25
			if _stun <= 0.0:
				model.body.rotation.y = 0.0
				state = "combat"
		"idle":
			_tick_idle(delta)
		"combat":
			if level.player.dead:
				velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
				_laser.visible = false
			elif kind == "rat":
				_tick_rat(delta)
			else:
				_tick_gunner(delta)
	if is_active():
		_separate()
	_move()
	knock = knock.move_toward(Vector3.ZERO, 22.0 * delta)
	var sp := maxf(speed, 0.1)
	model.animate(delta, clampf(velocity.length() / sp, 0.0, 1.0) if is_active() else 0.0)


func _tick_idle(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = randf_range(1.4, 3.0)
		_idle_yaw = randf_range(-0.9, 0.9)
	model.rotation.y = lerp_angle(model.rotation.y, _home_yaw + _idle_yaw, 1.0 - exp(-3.0 * delta))
	if hostage:
		model.crouch = 0.0
	if _can_see_player():
		alert()


func _can_see_player() -> bool:
	if not level.zone_active(zone):
		return false
	var p := level.player
	if p.dead:
		return false
	var to := p.global_position - global_position
	to.y = 0
	var dist := to.length()
	if dist > 11.0:
		return false
	if dist > 3.5 and model_forward().dot(to / dist) < 0.25:
		return false
	return level.line_of_sight(center(), p.center())


func alert() -> void:
	if alerted or not is_active():
		return
	if not level.zone_active(zone):
		return
	alerted = true
	state = "combat"
	_mark.visible = true
	_mark.scale = Vector3.ONE * 0.2
	var tw := _mark.create_tween()
	tw.tween_property(_mark, "scale", Vector3.ONE * 1.3, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mark, "scale", Vector3.ONE, 0.08)
	tw.tween_interval(0.7)
	tw.tween_property(_mark, "scale", Vector3.ZERO, 0.12)
	tw.tween_callback(func(): _mark.visible = false)
	Sfx.play("alert", -8.0)
	level.on_enemy_alerted(self)
	for e in level.enemies:
		if e != self and e.zone == zone and not e.alerted and e.global_position.distance_to(global_position) < 7.0:
			e.call_deferred("alert")


# ------------------------------------------------------------------ 浣熊：射击 AI

func _tick_gunner(delta: float) -> void:
	var p := level.player
	var to := p.global_position - global_position
	to.y = 0
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	face_toward(dir, delta, 10.0)
	var eye := global_position + Vector3(0, Bullet.HEIGHT, 0)
	var target := p.global_position + Vector3(0, Bullet.HEIGHT, 0)
	# 视线检测（射线）每 0.12 秒做一次就够了
	_clear_t -= delta
	if _clear_t <= 0.0:
		_clear_t = 0.12
		_clear_cache = level.clear_shot(eye, target)
	var clear := _clear_cache

	if _tele > 0.0:
		_tele -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		_update_laser(model.muzzle.global_position, target)
		if _tele <= 0.0:
			_burst = maxi(1, (2 if kind == "taker" else 3) + int(Game.dv("burst")))
			_burst_cd = 0.0
			_laser.visible = false
		return
	if _burst > 0:
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		_burst_cd -= delta
		if _burst_cd <= 0.0:
			_shoot(dir)
			_burst -= 1
			_burst_cd = 0.15 if Game.dv("burst") <= 0 else 0.12
		return

	_attack_cd -= delta
	var want := Vector3.ZERO
	if stationary:
		want = Vector3.ZERO
	elif not clear or dist > 9.5:
		want = _nav_dir(p.global_position, delta) * speed
	elif dist < 3.5:
		want = -dir * speed * 0.8
	else:
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe_t = randf_range(0.8, 1.8)
			_strafe = -1.0 if randf() < 0.5 else 1.0
		want = dir.cross(Vector3.UP) * _strafe * speed * 0.55
	velocity = velocity.move_toward(want, 20.0 * delta)

	if clear and dist < 13.0 and _attack_cd <= 0.0:
		_tele = (0.65 if kind == "taker" else 0.5) * Game.dv("tele")
		_attack_cd = randf_range(1.4, 2.2) * Game.dv("atk_cd")
		Sfx.play("telegraph", -12.0)
		level.tip("laser")
		model.flash(Pal.RED, 0.45)
		_laser.visible = true
		_update_laser(model.muzzle.global_position, target)


func _update_laser(from: Vector3, to: Vector3) -> void:
	var v := to - from
	var l := v.length()
	if l < 0.1:
		return
	_laser.global_position = from + v * 0.5
	_laser.look_at(to, Vector3.UP)
	_laser.scale = Vector3(1.0 + sin(Time.get_ticks_msec() * 0.05) * 0.4, 1.0, l)


func _shoot(dir: Vector3) -> void:
	var spread := deg_to_rad(5.5 * Game.dv("spread"))
	var d := dir.rotated(Vector3.UP, randf_range(-spread, spread))
	level.spawn_bullet(global_position + Vector3(0, Bullet.HEIGHT, 0), d, false, 11.0, self,
		{"speed": 15.5 * Game.dv("bullet_speed")})
	Fx.muzzle(level, model.muzzle.global_position, Color(0.85, 0.45, 1.0), 0.7)
	Sfx.play("enemy_shot", -10.0)
	model.gun_kick = 0.1


# ------------------------------------------------------------------ 老鼠：近战 AI

func _tick_rat(delta: float) -> void:
	var p := level.player
	var to := p.global_position - global_position
	to.y = 0
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	if _lunge > 0.0:
		_lunge -= delta
		velocity = _lunge_dir * 9.0
		if not _bite_done and dist < 1.25:
			_bite_done = true
			Sfx.play("bite", -4.0)
			p.take_hit(9.0, _lunge_dir, global_position, self)
		if _lunge <= 0.0:
			velocity = Vector3.ZERO
			model.gun.rotation.x = 0.0
		return
	face_toward(dir, delta, 14.0)
	if _bite_wind > 0.0:
		_bite_wind -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
		model.crouch = 1.0
		model.gun.rotation.x = -1.2 * (1.0 - _bite_wind / 0.33)
		if _bite_wind <= 0.0:
			_lunge = 0.16
			_lunge_dir = dir
			_bite_done = false
			model.crouch = 0.0
			model.gun.rotation.x = 1.0
			Sfx.play("swing", -6.0)
		return
	model.crouch = 0.0
	if dist < 1.4 and _bite_cd <= 0.0:
		_bite_wind = 0.33
		_bite_cd = 1.1
		model.flash(Pal.RED, 0.6)
		return
	var want := _nav_dir(p.global_position, delta) * speed if dist > 1.0 else Vector3.ZERO
	velocity = velocity.move_toward(want, 30.0 * delta)


# ------------------------------------------------------------------ 寻路 / 分离

func _nav_dir(target: Vector3, delta: float) -> Vector3:
	var direct := target - global_position
	direct.y = 0
	direct = direct.normalized()
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.3
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_path = NavigationServer3D.map_get_path(map, global_position, target, true)
			_path_i = 0
	# 只按水平距离推进路点（导航网格高度与角色脚底有体素误差）
	while _path_i < _path.size():
		var wp := _path[_path_i]
		var dv := Vector3(wp.x - global_position.x, 0, wp.z - global_position.z)
		if dv.length() < 0.35:
			_path_i += 1
			continue
		return dv.normalized()
	return direct


func _separate() -> void:
	for e in level.enemies:
		if e == self or not e.is_active():
			continue
		var dv := global_position - e.global_position
		dv.y = 0
		var l := dv.length()
		if l < 0.8 and l > 0.001:
			velocity += dv / l * (0.8 - l) * 8.0


# ------------------------------------------------------------------ 受击 / 晕倒 / 上铐

func take_hit(dmg: float, dir: Vector3, _from: Vector3, _source: Node) -> bool:
	if not is_active():
		return false
	hp -= dmg
	model.flash()
	model.squash(0.25)
	knock += dir * (3.0 if kind == "rat" else 1.6)
	Fx.popup(level, global_position + Vector3(0, 1.6, 0), str(int(round(dmg * 10.0))),
		Pal.CREAM if dmg <= 1.0 else Pal.ORANGE, 56 if dmg <= 1.0 else 70)
	Sfx.play("hit", -7.0)
	if not alerted:
		alert()
	if hp <= 0.0:
		_go_down(dir)
	return true


func stun(t: float) -> void:
	if not is_active():
		return
	state = "stunned"
	_stun = t
	_tele = 0.0
	_burst = 0
	_laser.visible = false


func _go_down(_dir: Vector3) -> void:
	if not is_active():
		return
	state = "defeated"
	hp = 0.0
	down_t = 0.0
	_tele = 0.0
	_burst = 0
	_burst_cd = 0.0
	_bite_wind = 0.0
	_lunge = 0.0
	_stun = 0.0
	_path.clear()
	_path_i = 0
	_laser.visible = false
	_mark.visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	set_physics_process(false)
	set_process(false)
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	model.crouch = 0.0
	model.tail_wag = 0.0
	Sfx.play("bonk", -3.0)
	Game.hitstop(0.07)
	Game.shake(0.3)
	Fx.dust(level, global_position, 4)
	Game.run.downs = int(Game.run.downs) + 1
	# Retain the previous defeat + permanent-subdue score, without an E step.
	Game.run.cuffs = int(Game.run.cuffs) + 1
	Game.add_score(250)
	level.hud.score_popup("制服匪徒", 250)
	level.hud.add_kill()
	if drop != "":
		# 往玩家那边掉，别掉进墙角
		var to_p := level.player.global_position - global_position
		to_p.y = 0.0
		var ddir := to_p.normalized() if to_p.length() > 0.1 else Vector3(0.7, 0, 0.7)
		level.spawn_pickup(global_position + ddir * 1.2, "weapon", drop, 0.0, global_position)
		drop = ""
	elif not _gave_grenade and level.roll_grenade_drop():
		# 罐头手雷：第一次击倒必掉，之后有一定几率（同一个匪徒只掉一次）
		_gave_grenade = true
		var to_p2 := level.player.global_position - global_position
		to_p2.y = 0.0
		level.spawn_pickup(global_position + to_p2.normalized() * 1.0, "grenade", "", 0.0, global_position)
	if hostage:
		hostage.release()
		hostage = null
	level.on_enemy_down(self)
	# One small transform tween; no corpse, countdown, ghost mesh or new shader.
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, DESPAWN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


## Legacy interaction hooks are inert; defeated bandits never wake or reward twice.
func cuff() -> void:
	pass

func can_interact(_p: Player) -> bool:
	return false

func interact_enabled() -> bool:
	return false

func interact_text() -> String:
	return ""

func interact_pos() -> Vector3:
	return global_position

func interact(_p: Player) -> void:
	pass
