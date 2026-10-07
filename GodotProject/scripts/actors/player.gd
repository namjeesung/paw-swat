class_name Player
extends Actor
## 柴犬 · 豆包。双摇杆操作：WASD 移动 / 鼠标瞄准 / 左键射击 / 右键精瞄
## 空格翻滚（无敌帧）/ R 换弹（完美换弹）/ Q 破门冲撞 / E 互动

const SPEED := 6.2
const ACCEL := 80.0
const ROLL_SPEED := 13.5
const ROLL_TIME := 0.32
const ROLL_CD := 0.45
const FIRE_INTERVAL := 0.1
const MAG := 30
const RELOAD_TIME := 1.45
const PERFECT_A := 0.44
const PERFECT_B := 0.62
const JAM_PENALTY := 0.6
const DASH_TIME := 0.3
const DASH_SPEED := 21.0
const DASH_CD := 7.0
## 拾取护盾：5 秒未暂停的实际时间；重复拾取不刷新、不累加。
const SHIELD_DURATION := 5.0
const HIT_GRACE := 0.4

var ammo := MAG
var reloading := false
var reload_t := 0.0
var reload_dur := RELOAD_TIME
var reload_tried := false
var buff_t := 0.0
var roll_t := 0.0
var roll_cd := 0.0
var roll_dir := Vector3.FORWARD
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector3.FORWARD
var fire_cd := 0.0
var bloom := 0.0
var aim_point := Vector3.ZERO
var aim_dir := Vector3(0, 0, -1)
var aiming := false
var in_cover := false
var since_damage := 99.0
var shield_t := 0.0
var _shield_visual: MeshInstance3D
var _shield_warned := false
var dead := false
var action_lock := 0.0
var move01 := 0.0

## 自动测试用：bot_enabled 时从 bot 字典读取输入
var bot_enabled := false
var bot := {}

var _dash_hits: Array = []
var _ghost_t := 0.0
var _step_t := 0.0
var _dodge_cd := 0.0
var _face_aim_t := 0.0

## 当前武器（rifle 无限弹药；神装打空自动换回步枪）
var weapon := "rifle"
var special_ammo := 0
## 已拥有的神装 → 剩余弹药（当前手上那把的弹药在 special_ammo 里）。神装之间可以随时切换
var arsenal := {}
const MAX_GRENADES := 3
var grenades := 0
var _grenade_cd := 0.0
## 触屏锁定的目标：子弹会轻微追踪它
var lock_target: Node3D
var _beam: MeshInstance3D
var _beam_t := 0.0
var _laser_snd := 0.0
var _shot_n := 0


func _ready() -> void:
	team = 0
	max_hp = Game.dv("player_hp")
	hp = max_hp
	collision_layer = Bullet.LAYER_PLAYER
	collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	_add_capsule(0.32, 1.15)
	model = Models.shiba()
	add_child(model)
	add_blob_shadow(0.5)
	model.rotation.y = atan2(facing.x, facing.z)
	_build_shield_visual()


# ------------------------------------------------------------------ 输入抽象

func _vec() -> Vector2:
	if bot_enabled:
		return bot.get("move", Vector2.ZERO)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _held(a: String) -> bool:
	if bot_enabled:
		return bool(bot.get(a, false))
	return Input.is_action_pressed(a)


func _just(a: String) -> bool:
	if bot_enabled:
		var k := "just_" + a
		if bot.get(k, false):
			bot[k] = false
			return true
		return false
	return Input.is_action_just_pressed(a)


# ------------------------------------------------------------------ 主循环

func _physics_process(delta: float) -> void:
	if level == null:
		return
	if dead or level.finished:
		velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
		_move()
		model.animate(delta, 0.0)
		return
	_tick_shield(delta / maxf(Engine.time_scale, 0.001))
	var d := delta * Game.player_time_mult()
	_tick_timers(d)

	aim_point = bot.get("aim_point", global_position + aim_dir) if bot_enabled else level.mouse_world()
	var to_aim := aim_point - global_position
	to_aim.y = 0
	if to_aim.length() > 0.15:
		aim_dir = to_aim.normalized()
	aiming = _held("aim")

	var mv := _vec()
	var wish := level.cam.screen_to_ground(mv)

	if roll_t > 0.0:
		roll_t -= d
		var k := clampf(roll_t / ROLL_TIME, 0.0, 1.0)
		velocity = roll_dir * ROLL_SPEED * (0.5 + 0.5 * k)
		model.pose.rotation.x = (1.0 - k) * TAU
		model.pose.position.y = sin((1.0 - k) * PI) * 0.25
		_trail(d)
		if roll_t <= 0.0:
			model.pose.rotation.x = 0.0
			model.pose.position.y = 0.0
			Fx.dust(level, global_position, 4, Color(1, 0.96, 0.88, 0.7), 1.5, 0.18)
	elif dash_t > 0.0:
		dash_t -= d
		velocity = dash_dir * DASH_SPEED
		_trail(d)
		_dash_collide()
		if dash_t <= 0.0:
			velocity = dash_dir * 3.0
	elif action_lock > 0.0:
		action_lock -= d
		velocity = velocity.move_toward(Vector3.ZERO, ACCEL * d)
	else:
		var spd := SPEED * (0.55 if aiming else 1.0)
		velocity = velocity.move_toward(wish * spd, ACCEL * d)
		if _just("roll") and roll_cd <= 0.0:
			_start_roll(wish if wish.length() > 0.2 else aim_dir)
		elif _just("skill"):
			if dash_cd <= 0.0:
				_start_dash(aim_dir)
			else:
				Sfx.play("ui_deny", -10.0)
				level.hud.toast("冲撞冷却中 · %d 秒" % ceili(dash_cd))
		_handle_fire()
		if _just("interact"):
			level.player_interact()

	_grenade_cd -= d
	if _just("switch"):
		cycle_weapon()
	if _just("grenade"):
		throw_grenade()

	if _just("reload") and weapon == "rifle":
		if reloading:
			_try_perfect()
		elif ammo < MAG:
			_start_reload()

	# 朝向：开火/精瞄时（及之后一小会儿）朝准星，否则朝移动方向
	if _held("shoot") or aiming:
		_face_aim_t = 0.35
	else:
		_face_aim_t -= d
	var face := facing
	if roll_t > 0.0:
		face = roll_dir
	elif dash_t > 0.0:
		face = dash_dir
	elif _face_aim_t > 0.0:
		face = aim_dir
	elif wish.length() > 0.15:
		face = wish
	# 开火时瞬间转身，枪口和子弹方向始终一致
	face_toward(face, d, 70.0 if _held("shoot") else 20.0)
	_beam_t -= d
	if _beam:
		_beam.visible = _beam_t > 0.0

	_move(Game.player_time_mult())
	knock = knock.move_toward(Vector3.ZERO, 30.0 * d)

	move01 = clampf(velocity.length() / SPEED, 0.0, 1.0)
	in_cover = roll_t <= 0.0 and velocity.length() < 2.5 and level.near_low_cover(global_position, 0.7)
	var want_crouch := 1.0 if in_cover and not _held("shoot") else 0.0
	model.crouch = lerpf(model.crouch, want_crouch, 1.0 - exp(-14.0 * d))
	model.tail_wag = 1.0 if since_damage > 2.0 else 0.2
	model.animate(d, move01)
	_footsteps(d)


func _tick_timers(d: float) -> void:
	fire_cd -= d
	roll_cd -= d
	dash_cd = maxf(0.0, dash_cd - d)
	buff_t = maxf(0.0, buff_t - d)
	_dodge_cd -= d
	since_damage += d
	if not _held("shoot") or reloading:
		bloom = move_toward(bloom, 0.0, 10.0 * d)
	if since_damage > Game.dv("regen_delay") and hp < max_hp:
		hp = minf(max_hp, hp + Game.dv("regen_rate") * d)
	if reloading:
		reload_t += d
		if reload_t >= reload_dur:
			_finish_reload(false)


# ------------------------------------------------------------------ 射击 / 换弹

func _handle_fire() -> void:
	if not _held("shoot") or fire_cd > 0.0:
		return
	if weapon != "rifle":
		_fire_special()
		return
	if reloading:
		return
	if ammo <= 0:
		Sfx.play("empty", -6.0)
		fire_cd = 0.25
		_start_reload()
		return
	_fire()


func current_spread() -> float:
	if Game.touch:
		# 手机上不靠随机散布制造难度
		return deg_to_rad(0.5 + bloom * 0.25 + move01 * 0.6)
	return deg_to_rad(1.4 + bloom + move01 * 3.0) * (0.35 if aiming else 1.0)


func _fire() -> void:
	fire_cd = FIRE_INTERVAL
	ammo -= 1
	Game.run.shots = int(Game.run.shots) + 1
	var spread := current_spread()
	var dir := aim_dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var hot := buff_t > 0.0
	level.spawn_bullet(global_position + Vector3(0, Bullet.HEIGHT, 0), dir, true, 1.5 if hot else 1.0, self, {"homing": lock_target})
	bloom = minf(bloom + 0.9, 6.5)
	model.gun_kick = 0.13
	var mp := model.muzzle.global_position
	_shot_n += 1
	Fx.muzzle(level, mp, Color(1.0, 0.55, 0.2) if hot else Color(1.0, 0.82, 0.4), 0.9, _shot_n % 2 == 0)
	Fx.shell(level, mp - aim_dir * 0.35, aim_dir.cross(Vector3.UP).normalized() * -1.0)
	Sfx.play("shot_buff" if hot else "shot", -8.0, 1.0, 0.08)
	Game.shake(0.05)
	level.cam.kick(-dir * 0.14)
	level.noise(global_position, 10.0)
	level.hud.on_shot()
	if ammo == 0:
		_start_reload()
	elif ammo == 8:
		level.tip("reload")


# ------------------------------------------------------------------ 神装武器

## 捡到神装：放进武器库（同种叠加弹药）并立刻换上；之前的神装保留，可以切回去
func give_weapon(id: String) -> void:
	_stash()
	arsenal[id] = int(arsenal.get(id, 0)) + int(Weapons.info(id).ammo)
	_equip(id)
	model.flash(Weapons.info(id).color, 1.0)
	Fx.ring(level, global_position, Weapons.info(id).color, 2.6)
	level.hud.weapon_banner(id)
	if arsenal.size() >= 2 or weapon != "rifle":
		level.tip("switch")


## 当前可切换的武器（步枪 + 已拥有的神装，按固定顺序）
func owned_weapons() -> Array:
	var list := ["rifle"]
	for id in Weapons.DATA:
		if id != "rifle" and arsenal.has(id):
			list.append(id)
	return list


func _stash() -> void:
	if weapon != "rifle":
		arsenal[weapon] = special_ammo


func _equip(id: String) -> void:
	weapon = id
	special_ammo = int(arsenal.get(id, 0)) if id != "rifle" else 0
	reloading = false
	fire_cd = 0.15
	_beam_t = 0.0


## 切到下一把（Tab / X / 滚轮；触屏点武器按钮）
func cycle_weapon(step := 1) -> void:
	var list := owned_weapons()
	if list.size() < 2:
		Sfx.play("ui_deny", -10.0)
		level.hud.toast("还没有其他武器 · 击倒带神装的匪徒会掉落")
		return
	_stash()
	var i := list.find(weapon)
	var next: String = list[(i + step + list.size()) % list.size()]
	_equip(next)
	var w := Weapons.info(next)
	Sfx.play("reload_done", -4.0, 1.2)
	model.flash(w.color, 0.6)
	model.squash(0.12)
	Fx.popup(level, global_position + Vector3(0, 2.1, 0), String(w.short), w.color, 60, true, 0.8, 0.6)
	level.hud.on_weapon_switch(next)


## 扔手雷：有锁定目标就扔向目标，否则扔向准星方向（最远 7 米）
func throw_grenade() -> void:
	if grenades <= 0:
		Sfx.play("ui_deny", -10.0)
		level.hud.toast("没有手雷了 · 击倒匪徒有机会掉落")
		return
	if _grenade_cd > 0.0 or dead:
		return
	_grenade_cd = 0.5
	grenades -= 1
	var target := global_position + aim_dir * 6.5
	if not bot_enabled:
		# 键鼠：扔到鼠标位置
		target = aim_point
	else:
		# 触屏：锁定目标 > 最近的敌人（8 米内）> 正前方
		var best: Node3D = lock_target if lock_target and is_instance_valid(lock_target) else null
		if best == null:
			var bd := 8.0
			for t in level.targets():
				var dd: float = (t as Node3D).global_position.distance_to(global_position)
				if dd < bd:
					bd = dd
					best = t
		if best and best.global_position.distance_to(global_position) < 9.0:
			target = best.global_position
	var off := target - global_position
	off.y = 0.0
	if off.length() > 7.0:
		target = global_position + off.normalized() * 7.0
	target = level.safe_drop_point(target, global_position)
	var g := Grenade.new()
	g.level = level
	g.from = model.muzzle.global_position
	g.to = target
	level.add_child(g)
	model.gun_kick = 0.2
	model.squash(0.15)
	Sfx.play("swing", -4.0, 1.1)
	level.tip("grenade")


func _fire_special() -> void:
	var w := Weapons.info(weapon)
	fire_cd = float(w.interval)
	var origin := global_position + Vector3(0, Bullet.HEIGHT, 0)
	var mp := model.muzzle.global_position
	var col: Color = w.color
	Game.run.shots = int(Game.run.shots) + 1
	match weapon:
		"shotgun":
			for i in 8:
				var a := deg_to_rad(-17.0 + 34.0 * i / 7.0 + randf_range(-2, 2))
				level.spawn_bullet(origin, aim_dir.rotated(Vector3.UP, a), true, 1.4, self, {"max_dist": 11.0, "knock": 2.6, "color": col, "safe": true})
			Sfx.play("shotgun", -3.0)
			Fx.muzzle(level, mp, col, 1.6)
			Game.shake(0.28)
			level.cam.kick(-aim_dir * 0.4)
			knock = -aim_dir * 3.0
			model.gun_kick = 0.25
			Game.run.shots = int(Game.run.shots) + 7
		"laser":
			var end := level.laser(origin, aim_dir, 20.0, 0.6, self)
			_show_beam(mp, end + Vector3(0, mp.y - end.y, 0), col)
			_laser_snd -= float(w.interval)
			if _laser_snd <= 0.0:
				_laser_snd = 0.16
				Sfx.play("laser", -8.0, 1.0, 0.08)
			Game.shake(0.04)
			model.gun_kick = 0.05
		"rocket":
			level.spawn_bullet(origin, aim_dir, true, 5.0, self, {"kind": "rocket", "speed": 24.0, "explode": 3.4, "max_dist": 26.0, "safe": true})
			Sfx.play("rocket", -2.0)
			Fx.muzzle(level, mp, col, 1.8)
			Game.shake(0.3)
			level.cam.kick(-aim_dir * 0.45)
			knock = -aim_dir * 4.0
			model.gun_kick = 0.3
		"gatling":
			var spread := deg_to_rad(4.0)
			var dir := aim_dir.rotated(Vector3.UP, randf_range(-spread, spread))
			level.spawn_bullet(origin, dir, true, 1.3, self, {"pierce": 2, "color": col, "homing": lock_target, "safe": true})
			_shot_n += 1
			Fx.muzzle(level, mp, col, 1.1, _shot_n % 4 == 0)
			if _shot_n % 3 == 0:
				Fx.shell(level, mp - aim_dir * 0.35, aim_dir.cross(Vector3.UP).normalized() * -1.0)
			Sfx.play("shot", -10.0, 1.25, 0.1)
			Game.shake(0.07)
			model.gun_kick = 0.1
	level.noise(global_position, 10.0)
	level.hud.on_shot()
	special_ammo -= 1
	if special_ammo <= 0:
		_beam_t = 0.0
		Fx.popup(level, global_position + Vector3(0, 2.0, 0), "神装耗尽", Color(0.75, 0.8, 0.9), 56, true)
		arsenal.erase(weapon)
		# 还有别的神装就自动换上，没有才回到步枪
		var list := owned_weapons()
		_equip(list[list.size() - 1])
		Sfx.play("reload_done", -4.0)


func _show_beam(from: Vector3, to: Vector3, col: Color) -> void:
	if _beam == null:
		_beam = MeshInstance3D.new()
		_beam.mesh = Models.box(Vector3(1, 1, 1))
		_beam.material_override = Toon.glow(Color(col.r, col.g, col.b, 0.85), 2.6)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.top_level = true
		add_child(_beam)
	var v := to - from
	var l := maxf(v.length(), 0.1)
	_beam.global_position = from + v * 0.5
	_beam.look_at(to, Vector3.UP)
	var w := 0.16 + randf() * 0.08
	_beam.scale = Vector3(w, w, l)
	_beam_t = 0.09


func _start_reload() -> void:
	if reloading or ammo >= MAG:
		return
	reloading = true
	reload_t = 0.0
	reload_dur = RELOAD_TIME
	reload_tried = false
	Sfx.play("reload_start", -4.0)


func reload_progress() -> float:
	return clampf(reload_t / reload_dur, 0.0, 1.0)


## 换弹进度条里“完美区”的位置（随卡壳延长而缩放）
func perfect_window() -> Vector2:
	return Vector2(PERFECT_A, PERFECT_B) * (RELOAD_TIME / reload_dur)


func _try_perfect() -> void:
	if reload_tried:
		return
	reload_tried = true
	var p := reload_t / RELOAD_TIME
	if p >= PERFECT_A and p <= PERFECT_B:
		_finish_reload(true)
	else:
		reload_dur = RELOAD_TIME + JAM_PENALTY
		Sfx.play("jam", -4.0)
		Fx.popup(level, global_position + Vector3(0, 1.9, 0), "卡壳!", Color(0.7, 0.75, 0.85), 60, true)
		level.hud.reload_jam()


func _finish_reload(perfect: bool) -> void:
	reloading = false
	ammo = MAG
	if perfect:
		buff_t = 4.0
		Sfx.play("perfect", -2.0, 1.0, 0.0)
		Fx.popup(level, global_position + Vector3(0, 2.0, 0), "完美换弹!", Pal.ORANGE, 76, true, 1.2, 0.9)
		Fx.ring(level, global_position, Pal.ORANGE, 2.2)
		model.flash(Pal.ORANGE, 0.9)
		Game.run.perfect = int(Game.run.perfect) + 1
		Game.add_score(50)
		level.hud.score_popup("完美换弹 · 火力强化", 50)
	else:
		Sfx.play("reload_done", -4.0)


# ------------------------------------------------------------------ 翻滚 / 冲撞

func _start_roll(dir: Vector3) -> void:
	roll_t = ROLL_TIME
	roll_cd = ROLL_TIME + ROLL_CD
	roll_dir = Vector3(dir.x, 0, dir.z).normalized()
	Sfx.play("roll", -3.0)
	Fx.dust(level, global_position, 5, Color(1, 0.96, 0.88, 0.7), 2.0, 0.2)
	level.hud.on_roll()


func invulnerable() -> bool:
	return shield_t > 0.0 or roll_t > 0.03 or dash_t > 0.0


func _start_dash(dir: Vector3) -> void:
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	dash_dir = Vector3(dir.x, 0, dir.z).normalized()
	_dash_hits.clear()
	Sfx.play("dash", -1.0)
	Game.shake(0.2)
	Fx.ring(level, global_position, Pal.ORANGE, 2.4)
	model.flash(Pal.ORANGE, 0.6)


func _dash_collide() -> void:
	for e in level.targets():
		if not e.is_active() or _dash_hits.has(e):
			continue
		if e.global_position.distance_to(global_position) < 1.2:
			_dash_hits.append(e)
			e.take_hit(3.0, dash_dir, global_position, self)
			if e.is_active():
				e.stun(1.3)
			e.knock = dash_dir * 10.0
			Game.hitstop(0.06)
			Game.shake(0.35)
			Fx.spark(level, e.center(), -dash_dir, Pal.ORANGE, 12, 7.0)
	var dr := level.door
	if dr and not dr.done:
		var flat := Vector2(dr.global_position.x - global_position.x, dr.global_position.z - global_position.z)
		if flat.length() < 1.7:
			if dr.breachable:
				dr.breach(global_position)
				dash_t = 0.04
			else:
				dash_t = 0.0
				knock = -dash_dir * 7.0
				velocity = Vector3.ZERO
				Sfx.play("bonk", -4.0, 0.7)
				Game.shake(0.3)
				level.hud.toast("门锁死了 —— 先清理店面！")


func _trail(d: float) -> void:
	_ghost_t -= d
	if _ghost_t <= 0.0:
		_ghost_t = 0.045
		Fx.ghost(level, model, Color(1.0, 0.55, 0.15, 0.5) if dash_t > 0.0 else Color(1.0, 0.8, 0.5, 0.35))


func _footsteps(d: float) -> void:
	if move01 < 0.6 or roll_t > 0.0:
		return
	_step_t -= d
	if _step_t <= 0.0:
		_step_t = 0.3
		Fx.dust(level, global_position + Vector3(0, 0.05, 0), 2, Color(1, 0.96, 0.88, 0.35), 0.8, 0.12)


# ------------------------------------------------------------------ 互动

func kick_door(door: Door) -> void:
	action_lock = 0.28
	var to := door.global_position - global_position
	to.y = 0
	face_toward(to, 1.0, 100.0)
	knock = to.normalized() * 5.0
	model.squash(0.25)
	Sfx.play("swing", -4.0)
	var t := get_tree().create_timer(0.12, false, true)
	t.timeout.connect(func(): door.breach(global_position))


func do_cuff(e: Enemy) -> void:
	if not is_instance_valid(e) or not e.can_interact(self):
		return
	action_lock = 0.3
	var to := e.global_position - global_position
	face_toward(to, 1.0, 100.0)
	model.squash(0.15)
	e.cuff()


func do_rescue(h: Hostage) -> void:
	action_lock = 0.4
	face_toward(h.global_position - global_position, 1.0, 100.0)
	h.rescue()


# ------------------------------------------------------------------ 受伤

func take_hit(dmg: float, dir: Vector3, from: Vector3, _source: Node) -> bool:
	if dead:
		return false
	if invulnerable():
		if _dodge_cd <= 0.0:
			_dodge_cd = 0.4
			Fx.popup(level, global_position + Vector3(0, 1.9, 0), "护盾!" if shield_t > 0.0 else "闪避!", Pal.TEAL, 56, true)
			Sfx.play("dodge", -4.0)
			if shield_t <= 0.0:
				Game.run.dodges = int(Game.run.dodges) + 1
		return false
	# 受击后 0.4 秒无敌，防止被一群围住时瞬间蒸发
	if since_damage < HIT_GRACE:
		return true
	dmg *= Game.dv("dmg")
	hp -= dmg
	since_damage = 0.0
	Game.run.damage = float(Game.run.damage) + dmg
	knock = dir * 3.5
	model.flash(Color(1.0, 0.25, 0.25), 1.0)
	model.squash(0.2)
	Game.shake(0.4)
	Game.vibrate(40)
	Sfx.play("hit_player", -2.0)
	level.hud.on_player_hit(from, dmg)
	level.tip("damage")
	if hp <= 0.0:
		_die()
	return true


func _die() -> void:
	dead = true
	clear_shield()
	hp = 0.0
	collision_layer = 0
	reloading = false
	var tw := create_tween()
	tw.tween_property(model.pose, "rotation:x", -PI / 2, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(model.pose, "position:y", 0.3, 0.35)
	level.on_player_dead()
	Game.bullet_time(1.5)


# 独立于翻滚/冲撞与受击宽限的临时护盾。没有僵尸潮永久无敌开关。
func _build_shield_visual() -> void:
	_shield_visual = MeshInstance3D.new()
	_shield_visual.mesh = Models.torus(0.68, 0.75)
	_shield_visual.material_override = Toon.glow(Color("60DFFF"), 1.4)
	_shield_visual.position.y = 0.12
	_shield_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_visual.visible = false
	add_child(_shield_visual)


func grant_shield() -> bool:
	if dead or shield_t > 0.0 or level == null or level.finished:
		return false
	shield_t = SHIELD_DURATION
	_shield_warned = false
	_shield_visual.visible = true
	Fx.ring(level, global_position, Color("60DFFF"), 2.0)
	Sfx.play("powerup", -6.0, 1.0, 0.0)
	level.hud.toast("临时无敌 · 5 秒 · 不可叠加")
	level.tip("shield")
	return true


func _tick_shield(unpaused_seconds: float) -> void:
	if shield_t <= 0.0:
		return
	shield_t = maxf(0.0, shield_t - unpaused_seconds)
	if shield_t <= 1.0 and not _shield_warned:
		_shield_warned = true
		Sfx.play("alert", -9.0, 1.0, 0.0)
	if _shield_visual:
		_shield_visual.visible = shield_t > 0.0 and (shield_t > 1.0 or fmod(shield_t, 0.2) > 0.07)
	if shield_t <= 0.0:
		clear_shield()
		Sfx.play("ui_deny", -7.0, 1.0, 0.0)
		if level and not level.finished and not dead:
			level.hud.toast("护盾结束 · 小心受伤！")


func clear_shield() -> void:
	shield_t = 0.0
	_shield_warned = false
	if _shield_visual:
		_shield_visual.visible = false
