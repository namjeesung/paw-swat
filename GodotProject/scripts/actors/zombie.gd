class_name Zombie
extends Actor
## 僵尸鼠（实验罐头泄漏变异）。摇摇晃晃追玩家，近身蓄力拍一下。
## 被打败时“噗”地变成一团烟和小幽灵——可爱、不血腥。

const BOSS_RADIUS := 0.7
const BOSS_WAYPOINT_REACH := 0.12
const BOSS_STUCK_TIME := 2.5
const BOSS_STUCK_DISPLACEMENT := 0.45
const BOSS_TELEPORT_WARNING := 1.0
const BOSS_TELEPORT_COOLDOWN := 8.0
const BOSS_TELEPORT_RECOVERY := 0.6
const PROGRESS_SAMPLE_TIME := 0.25

var boss := false
var speed := 3.0
var dead := false
var _attack_cd := 0.6
var _wind := 0.0
var _stun := 0.0
var _rise := 0.5
var _t := 0.0
var _groan_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _nav_progress_pos := Vector3.ZERO
var _nav_progress_t := 0.0
var _nav_stall_repath_cd := 0.0
var _progress_positions: Array[Vector3] = []
var _progress_times: Array[float] = []
var _progress_clock := 0.0
var _progress_sample := 0.0
var _stuck_repathed := false
var _teleport_cd := 0.0
var _teleport_retry := 0.0
var _teleport_left := 0.0
var _teleport_destination := Vector3.INF
var _teleport_marker: Node3D
var _teleport_ring: MeshInstance3D
var _attack_recovery := 0.0
var _teleport_count := 0
var _forced_repaths := 0
var _landing_shape: CapsuleShape3D
## 性能：分帧（不同僵尸错开），隔帧才做完整碰撞移动，间隔 3 帧才重算一次互相推开
var _frame_slot := randi() % 6
var _sep_push := Vector3.ZERO


func _ready() -> void:
	collision_layer = Bullet.LAYER_ENEMY
	collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	max_hp = 45.0 * Game.dv("boss_hp") if boss else 2.6 * Game.dv("zombie_hp")
	hp = max_hp
	speed = (2.1 if boss else randf_range(2.7, 3.8)) * Game.dv("zombie_speed")
	model = Models.zombie(boss)
	add_child(model)
	if boss:
		model.scale = Vector3.ONE * 2.3
		_add_capsule(BOSS_RADIUS, 2.2)
		add_blob_shadow(1.1)
	else:
		_add_capsule(0.32, 1.0)
		add_blob_shadow(0.42)
	model.tail_wag = 0.6
	# Spread ordinary path requests across frames instead of querying every
	# member of a freshly spawned wave in the same physics tick.
	_repath = randf_range(0.02, 0.25)
	_nav_progress_pos = global_position
	if boss:
		_landing_shape = CapsuleShape3D.new()
		_landing_shape.radius = BOSS_RADIUS
		_landing_shape.height = 2.2
	_t = randf() * 10.0
	_groan_t = randf_range(1.0, 5.0)
	# 从地里钻出来
	model.position.y = -1.3 * model.scale.y
	var tw := create_tween()
	tw.tween_property(model, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.dust(level, global_position, 6 if not boss else 16, Color(0.6, 0.95, 0.7, 0.8), 2.0, 0.25 if not boss else 0.5)


func is_active() -> bool:
	return not dead


func stun(t: float) -> void:
	_stun = t
	_wind = 0.0
	_cancel_teleport()
	_reset_progress()


func _exit_tree() -> void:
	_cancel_teleport()


func _reach() -> float:
	return 2.1 if boss else 1.15


func _physics_process(delta: float) -> void:
	if dead or level == null:
		return
	if get_tree().paused:
		return
	_t += delta
	if level.finished:
		_cancel_teleport()
		_reset_progress()
		model.animate(delta, 0.0)
		return
	if _rise > 0.0:
		_cancel_teleport()
		_reset_progress()
		_rise -= delta
		model.animate(delta, 0.0)
		return
	var p := level.player
	if not is_instance_valid(p):
		_cancel_teleport()
		_reset_progress()
		return
	var to := p.global_position - global_position
	to.y = 0
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	_attack_cd -= delta
	_attack_recovery = maxf(0.0, _attack_recovery - delta)
	_teleport_cd = maxf(0.0, _teleport_cd - delta)
	_teleport_retry = maxf(0.0, _teleport_retry - delta)
	if p.dead:
		_cancel_teleport()
		_reset_progress()
	if boss and _teleport_left > 0.0:
		if _stun > 0.0 or _wind > 0.0 or p.dead:
			_cancel_teleport()
			_reset_progress()
		else:
			velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
			_update_teleport(delta)
			_move()
			knock = knock.move_toward(Vector3.ZERO, 20.0 * delta)
			face_toward(dir, delta, 8.0)
			model.animate(delta, 0.0)
			return
	var chasing := false
	if _stun > 0.0:
		_reset_progress()
		_stun -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
	elif _wind > 0.0:
		_reset_progress()
		_wind -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		model.crouch = 1.0
		if _wind <= 0.0:
			model.crouch = 0.0
			model.squash(0.3)
			if boss:
				Fx.ring(level, global_position, Color(0.6, 1.0, 0.6), 3.0)
				Game.shake(0.45)
				Sfx.play("bonk", -2.0, 0.5)
			if dist < _reach() + 0.35 and not p.dead and (not boss or level.line_of_sight(center(), p.center())):
				p.take_hit(22.0 if boss else 5.0, dir, global_position, self)
	elif dist < _reach() and _attack_cd <= 0.0 and _attack_recovery <= 0.0 and not p.dead and (not boss or level.line_of_sight(center(), p.center())):
		_reset_progress()
		_wind = 0.7 if boss else 0.45
		_attack_cd = 1.6 if boss else 1.0
		model.flash(Color(0.6, 1.0, 0.6), 0.7)
	elif not p.dead:
		chasing = true
		velocity = velocity.move_toward(_nav_dir(p.global_position, delta) * speed, 14.0 * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
	face_toward(dir, delta, 8.0)
	var f := Engine.get_physics_frames() + _frame_slot
	if f % 3 == 0:
		_sep_push = _separation_push()
	velocity += _sep_push
	if boss or f % 2 == 0 or not _move_cheap(delta):
		_move()
	if boss:
		var waiting_in_reach := dist <= _reach() + 0.35 and level.line_of_sight(center(), p.center())
		if chasing and not waiting_in_reach and _attack_recovery <= 0.0:
			_track_boss_progress(delta)
		else:
			_reset_progress()
	knock = knock.move_toward(Vector3.ZERO, 20.0 * delta)
	model.animate(delta, clampf(velocity.length() / speed, 0.0, 1.0))
	# 摇摇晃晃
	model.body.rotation.z += sin(_t * 7.0) * 0.14
	_groan_t -= delta
	if _groan_t <= 0.0:
		_groan_t = randf_range(3.0, 7.0)
		if global_position.distance_to(p.global_position) < 12.0:
			Sfx.play("groan", -14.0 if not boss else -4.0, 0.6 if boss else randf_range(1.1, 1.4), 0.1)


func _nav_dir(target: Vector3, delta: float) -> Vector3:
	var direct := target - global_position
	direct.y = 0
	direct = direct.normalized()
	_nav_stall_repath_cd = maxf(0.0, _nav_stall_repath_cd - delta)
	_nav_progress_t += delta
	if _nav_progress_t >= 0.7:
		# Horizontal displacement catches a body pushing a corner as well
		# as a follower oscillating around the same waypoint.
		var moved := global_position - _nav_progress_pos
		moved.y = 0.0
		if moved.length() < 0.18 and _nav_stall_repath_cd <= 0.0:
			_force_repath()
			_nav_stall_repath_cd = 0.8
		_nav_progress_t = 0.0
		_nav_progress_pos = global_position
	_repath -= delta
	if _repath <= 0.0:
		_repath = randf_range(0.3, 0.5)
		var map := level.zombie_navigation_map(boss)
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_path = NavigationServer3D.map_get_path(map, global_position, target, true)
			_path_i = 0
	while _path_i < _path.size():
		var wp := _path[_path_i]
		var dv := Vector3(wp.x - global_position.x, 0, wp.z - global_position.z)
		if dv.length() < (BOSS_WAYPOINT_REACH if boss else 0.4):
			_path_i += 1
			continue
		return dv.normalized()
	# A partial/empty route is not permission to run directly through a
	# blocking wall. Keep asking for a route; a stuck boss can use recovery.
	return direct if level.line_of_sight(center(), level.player.center()) else Vector3.ZERO


func _force_repath() -> void:
	_path.clear()
	_path_i = 0
	_repath = 0.0
	_forced_repaths += 1


func _reset_progress() -> void:
	_progress_positions.clear()
	_progress_times.clear()
	_progress_clock = 0.0
	_progress_sample = 0.0
	_stuck_repathed = false
	_nav_progress_pos = global_position
	_nav_progress_t = 0.0


## A rolling horizon uses net travel, not accumulated velocity/distance.
## Walking back and forth in a doorway therefore does not count as escape.
func _track_boss_progress(delta: float) -> void:
	_progress_clock += delta
	_progress_sample -= delta
	if _progress_sample > 0.0:
		return
	_progress_sample = PROGRESS_SAMPLE_TIME
	_progress_positions.append(global_position)
	_progress_times.append(_progress_clock)
	while _progress_times.size() > 1 and _progress_clock - _progress_times[1] >= BOSS_STUCK_TIME:
		_progress_times.pop_front()
		_progress_positions.pop_front()
	if _progress_times.is_empty():
		return
	var elapsed := _progress_clock - _progress_times[0]
	var net := global_position - _progress_positions[0]
	net.y = 0.0
	if elapsed >= 0.7 and net.length() < 0.18 and not _stuck_repathed:
		_force_repath()
		_stuck_repathed = true
	if elapsed >= BOSS_STUCK_TIME and net.length() < BOSS_STUCK_DISPLACEMENT:
		if _teleport_cd <= 0.0 and _teleport_retry <= 0.0:
			var spot := _find_teleport_destination()
			if spot != Vector3.INF:
				_begin_teleport(spot)
			else:
				_teleport_retry = 0.7
				_force_repath()
	elif elapsed >= BOSS_STUCK_TIME:
		_stuck_repathed = false


func _find_teleport_destination() -> Vector3:
	var map := level.zombie_navigation_map(true)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var ppos := level.player.global_position
	var start_angle := atan2(global_position.z - ppos.z, global_position.x - ppos.x)
	for radius in [2.6, 2.95, 2.2]:
		for i in 16:
			var angle := start_angle + TAU * float(i) / 16.0
			var wanted: Vector3 = ppos + Vector3(cos(angle), 0, sin(angle)) * float(radius)
			var spot := NavigationServer3D.map_get_closest_point(map, wanted)
			spot.y = 0.0
			if Vector2(spot.x - wanted.x, spot.z - wanted.z).length() > 0.45:
				continue
			if _teleport_spot_valid(spot):
				return spot
	return Vector3.INF


func _teleport_spot_valid(spot: Vector3) -> bool:
	if not spot.is_finite() or not boss or dead or level == null or level.finished or not is_instance_valid(level.player) or level.player.dead:
		return false
	var map := level.zombie_navigation_map(true)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var p := level.player
	var distance := Vector2(spot.x - p.global_position.x, spot.z - p.global_position.z).length()
	if distance < 2.0 or distance > 3.0:
		return false
	var projected := NavigationServer3D.map_get_closest_point(map, spot)
	if Vector2(projected.x - spot.x, projected.z - spot.z).length() > 0.08:
		return false
	if not level.line_of_sight(spot + Vector3(0, 1.38, 0), p.center()):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _landing_shape
	query.transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, 1.16, 0))
	query.collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER | Bullet.LAYER_PLAYER | Bullet.LAYER_ENEMY | Bullet.LAYER_HOSTAGE
	query.exclude = [get_rid()]
	query.margin = 0.02
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	# Reject another isolated nav island, even if Euclidean distance is close.
	var route := NavigationServer3D.map_get_path(map, spot, p.global_position, true)
	if route.is_empty():
		return false
	var endpoint := route[route.size() - 1]
	return Vector2(endpoint.x - p.global_position.x, endpoint.z - p.global_position.z).length() <= 0.9


func _begin_teleport(spot: Vector3) -> void:
	_teleport_destination = spot
	_teleport_left = BOSS_TELEPORT_WARNING
	velocity = Vector3.ZERO
	_teleport_marker = Node3D.new()
	level.add_child(_teleport_marker)
	_teleport_marker.global_position = spot
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = Fx.tex("ring")
	mat.albedo_color = Color(2.0, 1.0, 0.18, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (BOSS_RADIUS * 2.0 + 0.3)
	_teleport_ring = MeshInstance3D.new()
	_teleport_ring.mesh = plane
	_teleport_ring.material_override = mat
	_teleport_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_teleport_ring.position.y = 0.06
	_teleport_marker.add_child(_teleport_ring)
	var label := Label3D.new()
	label.text = "鼠王即将出现"
	label.font = Style.bold_font()
	label.font_size = 32
	label.pixel_size = 0.008
	label.modulate = Pal.ORANGE
	label.outline_modulate = Pal.INK
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.5
	_teleport_marker.add_child(label)
	Fx.dust(level, spot, 8, Color(1.0, 0.65, 0.22, 0.65), 1.0, 0.18)
	model.flash(Pal.ORANGE, BOSS_TELEPORT_WARNING)
	Sfx.play("groan", -6.0, 0.6)


func _update_teleport(delta: float) -> void:
	_teleport_left -= delta
	if is_instance_valid(_teleport_ring):
		_teleport_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 18.0))
	if _teleport_left > 0.0:
		return
	var spot := _teleport_destination
	_cancel_teleport()
	if not _teleport_spot_valid(spot):
		_teleport_retry = 0.7
		_force_repath()
		_reset_progress()
		return
	var origin := global_position
	global_position = spot
	# 瞬移不要被物理插值画成一道拖影
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	_teleport_cd = BOSS_TELEPORT_COOLDOWN
	_attack_recovery = BOSS_TELEPORT_RECOVERY
	_teleport_count += 1
	_force_repath()
	_reset_progress()
	Fx.dust(level, origin, 12, Color(0.6, 0.95, 0.7, 0.8), 2.0, 0.3)
	Fx.dust(level, spot, 16, Color(0.75, 1.0, 0.8, 0.85), 2.0, 0.28)
	Fx.ring(level, spot, Pal.ORANGE, 1.2, 0.4)
	Sfx.play("dash", -4.0, 0.75)


func _cancel_teleport() -> void:
	_teleport_left = 0.0
	_teleport_destination = Vector3.INF
	if is_instance_valid(_teleport_marker):
		_teleport_marker.queue_free()
	_teleport_marker = null
	_teleport_ring = null


func _separate() -> void:
	velocity += _separation_push()


func _separation_push() -> Vector3:
	var push := Vector3.ZERO
	var r := 1.3 if boss else 0.75
	var me := global_position
	for z in level.zombies:
		if z == self or z.dead:
			continue
		var dx := me.x - z.global_position.x
		var dz := me.z - z.global_position.z
		var rr := r if not z.boss else 1.3
		if absf(dx) >= rr or absf(dz) >= rr:
			continue
		var l := sqrt(dx * dx + dz * dz)
		if l < rr and l > 0.001:
			push += Vector3(dx, 0, dz) / l * (rr - l) * 7.0
	return push


func take_hit(dmg: float, dir: Vector3, _from: Vector3, _source: Node) -> bool:
	if dead or _rise > 0.25:
		return false
	hp -= dmg
	model.flash()
	model.squash(0.25 if not boss else 0.08)
	knock += dir * (2.2 if not boss else 0.25)
	if boss:
		Fx.popup(level, global_position + Vector3(0, 3.2, 0), str(int(round(dmg * 10.0))), Pal.YELLOW, 60)
	Sfx.play("hit", -10.0, 1.2)
	if hp <= 0.0:
		_die()
	return true


func _die(silent := false) -> void:
	if dead:
		return
	dead = true
	_cancel_teleport()
	_reset_progress()
	collision_layer = 0
	var c := global_position + Vector3(0, 0.6 * model.scale.y, 0)
	Fx.dust(level, c, 5 if not boss else 24, Color(0.75, 1.0, 0.8, 0.85), 2.6, 0.22 if not boss else 0.5)
	if boss:
		Fx.spark(level, c, Vector3.UP, Color(0.55, 1.0, 0.65), 30, 5.0)
	var g := Models.ghost()
	level.add_child(g)
	g.global_position = c
	g.scale = Vector3.ONE * (1.0 if not boss else 2.5)
	var gt := g.create_tween()
	gt.tween_property(g, "global_position:y", c.y + 2.2, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	gt.parallel().tween_property(g, "scale", Vector3.ONE * 0.2, 1.0).set_ease(Tween.EASE_IN)
	gt.tween_callback(g.queue_free)
	if not silent:
		Sfx.play("splat", -6.0 if not boss else 0.0, randf_range(0.9, 1.3) if not boss else 0.6, 0.0)
	level.on_zombie_killed(self)
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3(model.scale.x * 1.4, model.scale.y * 0.2, model.scale.z * 1.4), 0.1)
	tw.tween_callback(queue_free)


## 终局空投炸弹：延迟后依次炸飞
func finale_pop(delay: float) -> void:
	var t := get_tree().create_timer(delay, true, false, true)
	t.timeout.connect(func():
		if is_instance_valid(self) and not dead:
			_die(randf() < 0.6)
	)


func center() -> Vector3:
	return global_position + Vector3(0, 0.6 * (2.3 if boss else 1.0), 0)
