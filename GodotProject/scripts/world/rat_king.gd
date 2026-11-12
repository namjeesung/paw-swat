class_name RatKing
extends Node3D
## 第二章 Boss「老K 的罐头蟹机甲」的大脑：挂在关卡上，盯着一只 boss 僵尸鼠（外形换成 CrabMech），轮流放技能。
## 每个技能都有地面红色预警（看到红色就翻滚 / 跑开），打完会有一小段硬直让你输出。
##   钳子冲撞：地上亮一条红色长条，钳子张开 → 0.9 秒后沿直线猛冲，撞飞箱子；冲完卡壳 1 秒
##   跺地：脚下红圈越扩越大 → 1 秒后六条腿一起跺地，圈内的人和箱子都吃伤害
##   放鼠：舱门打开，放出一圈僵尸鼠
##   罐头炮：背上的炮往你脚下打 3 颗（暴怒 5 颗）罐头，落点先亮红圈，1.1 秒后炸
##   罐头弹幕：原地往四周打 2–3 圈慢速子弹，从缝里钻 / 翻滚穿过
##   半血暴怒：外壳变暗红、变快、技能间隔变短（鬼畜难度 70% 血就暴怒）

var level: HarborLevel
var z: Zombie
var enraged := false
var skill_name := ""             # HUD 显示「正在蓄力：冲撞」

var _cd := 2.5
var _busy := 0.0
var _n := 0
var _base_speed := 0.0
var _charge_dir := Vector3.ZERO
var _charging := 0.0
var _charge_hit := false
var mech: CrabMech
var _last_hp := 0.0

static var _warn_mat: StandardMaterial3D
static var _warn_edge: StandardMaterial3D


func _ready() -> void:
	if _warn_mat == null:
		_warn_mat = StandardMaterial3D.new()
		_warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_warn_mat.albedo_color = Color(1.0, 0.15, 0.15, 0.32)
		_warn_mat.no_depth_test = false
		_warn_edge = _warn_mat.duplicate()
		_warn_edge.albedo_color = Color(1.0, 0.25, 0.2, 0.85)
	_base_speed = z.speed
	_cd = HarborLevel.hdiff().boss_cd * 0.8
	# 换上机甲外形：原来的鼠王模型藏起来
	z.no_ghost = true
	z.model.visible = false
	mech = CrabMech.new()
	mech.scale = Vector3.ONE * 1.25
	z.add_child(mech)
	mech.position.y = -2.5
	mech.create_tween().tween_property(mech, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_last_hp = z.hp


func _cooldown() -> float:
	return float(HarborLevel.hdiff().boss_cd) * (0.65 if enraged else 1.0)


func _process(delta: float) -> void:
	if not is_instance_valid(z) or z.dead or level.stage != "play":
		queue_free()
		return
	# 机甲外形跟着 boss 转向、走路、受击闪白
	mech.rotation.y = z.model.rotation.y
	mech.animate(delta, clampf(z.velocity.length() / maxf(_base_speed, 0.1), 0.0, 1.0))
	if z.hp < _last_hp:
		mech.flash()
	_last_hp = z.hp
	mech.claw_open = move_toward(mech.claw_open, 1.0 if skill_name != "" else 0.0, delta * 4.0)
	var p := level.player
	if p.dead:
		return
	if not enraged and z.hp < z.max_hp * (0.7 if Game.difficulty == "insane" else 0.5):
		_enrage()
	if _charging > 0.0:
		_tick_charge(delta)
		return
	if _busy > 0.0:
		_busy -= delta
		return
	skill_name = ""
	_cd -= delta
	if _cd > 0.0:
		return
	var d := z.global_position.distance_to(p.global_position)
	_n += 1
	if _n % 4 == 0 and level.zombies.size() < 70:
		_summon()
	elif d > 7.5:
		var r := randf()
		if r < 0.45:
			_charge()
		elif r < 0.8:
			_throw()
		else:
			_barrage()
	elif d < 4.5:
		if randf() < 0.7:
			_slam()
		else:
			_barrage()
	else:
		[_charge, _slam, _throw, _barrage][randi() % 4].call()
	_cd = _cooldown()


# ------------------------------------------------------------------ 暴怒

func _enrage() -> void:
	if enraged:
		return
	enraged = true
	z.speed = _base_speed * 1.35
	mech.enrage()
	Fx.ring(level, z.global_position, Pal.RED, 6.0, 0.5)
	Fx.popup(level, z.global_position + Vector3(0, 3.6, 0), "暴怒！", Pal.RED, 96, true, 1.2, 1.0)
	Sfx.play("alarm", -4.0, 0.8, 0.0)
	if level.stage == "play" and level.t > 1.0:
		level.hud.radio.say("boss_k", "你敢弄坏我的宝贝？！[color=#FF5A5A]全速前进！[/color]", 0.0, true)


# ------------------------------------------------------------------ 冲撞

func _charge() -> void:
	var p := level.player
	var dir := p.global_position - z.global_position
	dir.y = 0
	if dir.length() < 0.1:
		return
	_charge_dir = dir.normalized()
	var length := clampf(dir.length() + 4.0, 8.0, 15.0)
	var wind := 0.9 if not enraged else 0.7
	skill_name = "钳子冲撞"
	z.skill_lock = wind
	z.skill_vel = Vector3.ZERO
	z.face_toward(_charge_dir, 1.0, 100.0)
	z.model.crouch = 1.0
	z.model.flash(Pal.RED, wind)
	Sfx.play("clank", -2.0, 0.5, 0.0)
	# 地上的红色长条
	var bar := MeshInstance3D.new()
	bar.mesh = Models.box(Vector3(1.8, 0.02, length))
	bar.material_override = _warn_mat
	level.add_child(bar)
	var mid := z.global_position + _charge_dir * (length * 0.5)
	bar.global_position = Vector3(mid.x, 0.04, mid.z)
	bar.look_at(Vector3(z.global_position.x, 0.04, z.global_position.z), Vector3.UP)
	bar.scale = Vector3(1, 1, 0.05)
	var tw := bar.create_tween()
	tw.tween_property(bar, "scale:z", 1.0, wind * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(wind * 0.4)
	tw.tween_callback(func():
		bar.queue_free()
		if not is_instance_valid(z) or z.dead:
			return
		z.model.crouch = 0.0
		_charging = length / 20.0
		_charge_hit = false
		z.skill_lock = _charging
		z.skill_vel = _charge_dir * 20.0
		Sfx.play("dash", -2.0, 0.6, 0.0)
	)
	_busy = wind + 0.1


func _tick_charge(delta: float) -> void:
	_charging -= delta
	var zp := z.global_position
	if int(Engine.get_process_frames()) % 3 == 0:
		Fx.dust(level, zp, 3, Color(1.0, 0.9, 0.75, 0.7), 2.0, 0.3)
	var p := level.player
	if not _charge_hit and not p.dead and Vector2(p.global_position.x - zp.x, p.global_position.z - zp.z).length() < 1.6:
		_charge_hit = true
		p.take_hit(24.0, _charge_dir * 2.5, zp, z)
	for b in level.breakables.duplicate():
		if is_instance_valid(b) and not b.broken and Vector2(b.global_position.x - zp.x, b.global_position.z - zp.z).length() < 1.6:
			b.take_hit(99.0, _charge_dir, zp, z)
	if _charging <= 0.0:
		z.skill_lock = 0.0
		z.skill_vel = Vector3.ZERO
		z.stun(1.0 if not enraged else 0.6)
		Fx.popup(level, zp + Vector3(0, 3.4, 0), "晕！", Pal.YELLOW, 64, true)
		Game.shake(0.2)
		Sfx.play("bonk", -4.0, 0.5, 0.0)
		_busy = 1.0


# ------------------------------------------------------------------ 震地

func _slam() -> void:
	var r := 5.5 if not enraged else 6.5
	var wind := 1.0 if not enraged else 0.8
	skill_name = "跺地"
	z.skill_lock = wind + 0.3
	z.skill_vel = Vector3.ZERO
	z.model.crouch = 1.0
	z.model.flash(Pal.RED, wind)
	Sfx.play("clank", -2.0, 0.4, 0.0)
	var c := z.global_position
	var disk := _disk(c, r)
	var tw := disk.create_tween()
	tw.tween_property(disk, "scale", Vector3(1, 1, 1), wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		disk.queue_free()
		if not is_instance_valid(z) or z.dead:
			return
		z.model.crouch = 0.0
		z.model.squash(0.4)
		var pos := z.global_position
		Fx.ring(level, pos, Pal.RED, r, 0.4)
		Fx.dust(level, pos, 16, Color(1.0, 0.9, 0.75, 0.85), r * 0.8, 0.45)
		Game.shake(0.3)
		Sfx.play("explosion", -6.0, 0.55, 0.0)
		var p := level.player
		if not p.dead and p.global_position.distance_to(pos) < r:
			var dir := p.global_position - pos
			dir.y = 0
			p.take_hit(18.0, dir.normalized() * 3.0, pos, z)
		for b in level.breakables.duplicate():
			if is_instance_valid(b) and not b.broken and b.global_position.distance_to(pos) < r:
				b.take_hit(99.0, (b.global_position - pos).normalized(), pos, z)
	)
	_busy = wind + 0.5


## 地上一个红色圆（从小长到大）+ 外圈描边
func _disk(c: Vector3, r: float) -> Node3D:
	var root := Node3D.new()
	level.add_child(root)
	root.global_position = Vector3(c.x, 0.04, c.z)
	var fill := MeshInstance3D.new()
	fill.mesh = Models.cyl(r, r, 0.02)
	fill.material_override = _warn_mat
	root.add_child(fill)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.12
	tm.outer_radius = r
	tm.rings = 40
	tm.ring_segments = 3
	edge.mesh = tm
	edge.material_override = _warn_edge
	edge.scale = Vector3(1, 0.05, 1)
	root.add_child(edge)
	root.scale = Vector3(0.1, 1, 0.1)
	return root


# ------------------------------------------------------------------ 召唤

func _summon() -> void:
	skill_name = "放鼠"
	z.skill_lock = 0.8
	z.skill_vel = Vector3.ZERO
	z.model.flash(Color(0.6, 1.0, 0.6), 0.8)
	Sfx.play("alarm", -8.0, 1.6, 0.0)
	Fx.ring(level, z.global_position, Color(0.6, 1.0, 0.6), 4.0, 0.6)
	Fx.popup(level, z.global_position + Vector3(0, 3.6, 0), "开舱放鼠！", Color(0.6, 1.0, 0.6), 72, true)
	var n := 4 + (2 if enraged else 0) + (1 if Game.difficulty in ["hard", "insane"] else 0)
	for i in n:
		level._spawn_zombie_ring(false, z.global_position + Vector3(cos(TAU * i / n), 0, sin(TAU * i / n)) * 2.5)
	_busy = 0.9


# ------------------------------------------------------------------ 罐头弹幕

## 原地转一圈，往四面八方打 2 圈（暴怒 3 圈）慢速罐头弹：从缝里穿过去，或者翻滚穿过去
func _barrage() -> void:
	skill_name = "罐头弹幕"
	var rings := 2 if not enraged else 3
	z.skill_lock = 0.6 + rings * 0.45
	z.skill_vel = Vector3.ZERO
	z.model.flash(Pal.ORANGE, 0.6)
	Sfx.play("clank", -2.0, 0.7, 0.0)
	var zid: int = z.get_instance_id()
	for k in rings:
		get_tree().create_timer(0.6 + k * 0.45, false).timeout.connect(func():
			var zz := instance_from_id(zid) as Zombie
			if zz == null or zz.dead or level.stage != "play":
				return
			var n := 14
			var origin := zz.global_position + Vector3(0, Bullet.HEIGHT, 0)
			for i in n:
				var a := TAU * (i + 0.5 * (k % 2)) / n
				var dir := Vector3(cos(a), 0, sin(a))
				level.spawn_bullet(origin + dir * 1.6, dir, false, 8.0, zz, {"speed": 8.5, "max_dist": 16.0, "color": Pal.ORANGE})
			Fx.ring(level, zz.global_position, Pal.ORANGE, 2.4, 0.25)
			Sfx.play("shotgun", -8.0, 0.8, 0.05)
		)
	_busy = 0.7 + rings * 0.45


# ------------------------------------------------------------------ 罐头炸弹

func _throw() -> void:
	skill_name = "罐头炮"
	z.skill_lock = 0.6
	z.skill_vel = Vector3.ZERO
	z.model.flash(Pal.ORANGE, 0.6)
	var p := level.player
	var n := 3 if not enraged else 5
	for i in n:
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.6, 3.2)
		# 往你跑的方向多扔一点：站着不动 / 直线跑都会被炸
		var lead := p.velocity * 0.5 if i == 1 else Vector3.ZERO
		lead.y = 0
		_bomb(p.global_position + off + lead, 0.1 * i)
	Sfx.play("explosion", -12.0, 1.8, 0.0)
	Fx.spark(level, mech.cannon_tip(), Vector3.UP, Pal.ORANGE, 8, 5.0)
	_busy = 0.8


func _bomb(at: Vector3, delay: float) -> void:
	at.y = 0.0
	var r := 1.8
	var from := mech.cannon_tip() if is_instance_valid(mech) else z.global_position + Vector3(0, 2.0, 0)
	var disk := _disk(at, r)
	var can := MeshInstance3D.new()
	can.mesh = Loot._res("can")[0]["can"]
	can.material_override = Toon.glow(Pal.RED, 1.6)
	can.scale = Vector3.ONE * 2.0
	level.add_child(can)
	can.global_position = from
	var fly := 1.1
	var tw := disk.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(disk, "scale", Vector3.ONE, fly).set_trans(Tween.TRANS_LINEAR)
	var ct := can.create_tween()
	ct.tween_interval(delay)
	ct.tween_method(func(k: float):
		if is_instance_valid(can):
			can.global_position = from.lerp(at, k) + Vector3(0, sin(k * PI) * 4.0, 0)
			can.rotation = Vector3(k * 9.0, k * 5.0, 0)
	, 0.0, 1.0, fly)
	ct.tween_callback(func():
		can.queue_free()
		disk.queue_free()
		if level.stage != "play":
			return
		Fx.ring(level, at, Pal.ORANGE, r * 1.1, 0.3)
		Fx.spark(level, at + Vector3(0, 0.3, 0), Vector3.UP, Pal.ORANGE, 10, 7.0)
		Sfx.play("explosion", -10.0, 1.2, 0.1)
		var p := level.player
		if not p.dead and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < r:
			var dir := p.global_position - at
			dir.y = 0
			p.take_hit(11.0, dir.normalized() * 2.0, at, null)
	)
