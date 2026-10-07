class_name Hostage
extends Actor
## 店员仓鼠 · 小米。被劫持时瑟瑟发抖；被玩家子弹误伤三次即任务失败。

var state := "held"
var hits := 0
var _t := 0.0
var _grace := 0.0
var _bubble: Label3D
var _evac_to := Vector3.ZERO
var _path := PackedVector3Array()
var _path_i := 0
var _evac_t := 0.0
const EVAC_SPEED := 5.2


func _ready() -> void:
	team = 2
	collision_layer = Bullet.LAYER_HOSTAGE
	collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	_add_capsule(0.3, 0.95)
	model = Models.hamster()
	add_child(model)
	model.rotation.y = atan2(facing.x, facing.z)
	add_blob_shadow(0.42)
	_bubble = Label3D.new()
	_bubble.text = "救命!"
	_bubble.font = Style.title_font()
	_bubble.font_size = 72
	_bubble.pixel_size = 0.006
	_bubble.modulate = Pal.TEAL
	_bubble.outline_size = 16
	_bubble.outline_modulate = Pal.INK
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 1.55, 0)
	_bubble.no_depth_test = true
	_bubble.render_priority = 15
	_bubble.outline_render_priority = 14
	add_child(_bubble)


func _physics_process(delta: float) -> void:
	_t += delta
	_grace -= delta
	model.animate(delta, 1.0 if state == "evac" else 0.0)
	velocity = _evac_velocity(delta) if state == "evac" else Vector3.ZERO
	_move()
	knock = knock.move_toward(Vector3.ZERO, 12.0 * delta)
	match state:
		"held":
			model.body.rotation.z = sin(_t * 42.0) * 0.035
			model.crouch = 0.6
			_bubble.position.y = 1.55 + sin(_t * 4.0) * 0.06
		"free":
			model.crouch = 0.0
			model.body.rotation.z = sin(_t * 30.0) * 0.02
			if level and level.player:
				face_toward(level.player.global_position - global_position, delta, 6.0)
			_bubble.position.y = 1.55 + absf(sin(_t * 6.0)) * 0.12
		"evac":
			_bubble.position.y = 1.55 + absf(sin(_t * 10.0)) * 0.1
		"rescued":
			model.body.position.y = absf(sin(_t * 9.0)) * 0.15
			if level and level.player:
				face_toward(level.player.global_position - global_position, delta, 6.0)


func take_hit(_dmg: float, dir: Vector3, _from: Vector3, _source: Node) -> bool:
	if state in ["rescued", "evac", "gone"] or _grace > 0.0:
		return false
	_grace = 1.0
	hits += 1
	if Game.autotest:
		print("[hostage] hit by %s weapon=%s" % [_source.get_class() if _source else "null", level.player.weapon])
	Game.run.hostage_hits = int(Game.run.hostage_hits) + 1
	model.flash(Color(1, 0.3, 0.3))
	model.squash(0.3)
	knock = dir * 1.5
	Sfx.play("hit_player", -2.0, 1.6)
	Fx.popup(level, global_position + Vector3(0, 1.6, 0), "好痛!", Pal.RED, 64, true)
	level.on_hostage_hit(hits)
	return true


func release() -> void:
	if state != "held":
		return
	state = "free"
	_bubble.text = "特警!"
	Fx.ring(level, global_position, Pal.TEAL, 1.6)


func rescue() -> void:
	if state != "free":
		return
	state = "rescued"
	_bubble.text = "谢谢!"
	model.flash(Pal.TEAL, 0.8)
	Fx.ring(level, global_position, Pal.TEAL, 2.6)
	Fx.popup(level, global_position + Vector3(0, 1.9, 0), "人质获救!", Pal.TEAL, 84, true, 1.3, 1.2)
	Sfx.play("perfect", -2.0, 0.8, 0.0)
	level.on_hostage_rescued()


# 互动接口
func can_interact(_p: Player) -> bool:
	return state == "free"


func interact_enabled() -> bool:
	return true


func interact_text() -> String:
	return "解救人质"


func interact_pos() -> Vector3:
	return global_position


func interact(p: Player) -> void:
	p.do_rescue(self)


# 撤离：沿导航路线跑到门口的警车旁，到了通知关卡（上车、警车开走）
func evacuate(to: Vector3) -> void:
	state = "evac"
	_evac_to = to
	_evac_t = 0.0
	_bubble.text = "去警车!"
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		_path = NavigationServer3D.map_get_path(map, global_position, to, true)
	_path_i = 0


func _evac_velocity(delta: float) -> Vector3:
	_evac_t += delta
	var flat := Vector3(_evac_to.x - global_position.x, 0, _evac_to.z - global_position.z)
	# 到了（或者跑了太久卡住了，直接算到达）
	if flat.length() < 0.6 or _evac_t > 14.0:
		state = "gone"
		level.on_hostage_evacuated()
		return Vector3.ZERO
	var dir := flat.normalized()
	while _path_i < _path.size():
		var wp := _path[_path_i]
		var dv := Vector3(wp.x - global_position.x, 0, wp.z - global_position.z)
		if dv.length() < 0.35:
			_path_i += 1
			continue
		dir = dv.normalized()
		break
	face_toward(dir, delta, 12.0)
	return dir * EVAC_SPEED
