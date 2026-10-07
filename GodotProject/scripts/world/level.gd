class_name Level
extends Node3D
## 序章 · 午夜便利店。负责：搭场景、刷角色、任务流程、无线电剧情、胜负判定。
##
## 流程：进入便利店 → 清除匪徒(8) → 破门 → 制服劫持者 → 解救人质 → 结算

const CASE_TITLE := "序章 · 午夜便利店"
const PLAYER_START := Vector3(0, 0, 14.5)

## [类型, 位置, 区域, 朝向]
const SPAWNS := [
	["raccoon", Vector3(-1.5, 0, -4.2), "shop", Vector3(0, 0, 1)],
	["raccoon", Vector3(3.0, 0, 1.6), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(-7.8, 0, -4.2), "shop", Vector3(1, 0, 0)],
	["rat", Vector3(-5.0, 0, 0.5), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(-10.8, 0, 5.5), "shop", Vector3(1, 0, 0)],
	["raccoon", Vector3(10.0, 0, 2.3), "storage", Vector3(-1, 0, 0.4)],
	["rat", Vector3(8.2, 0, 6.6), "storage", Vector3(-1, 0, 0)],
	["rat", Vector3(11.0, 0, 7.0), "storage", Vector3(-1, 0, 0)],
	["taker", Vector3(10.0, 0, -6.9), "staff", Vector3(-0.2, 0, 1)],
	["raccoon", Vector3(6.3, 0, -2.0), "staff", Vector3(1, 0, 0.5)],
	["rat", Vector3(10.9, 0, -1.9), "staff", Vector3(-1, 0, 0)],
]
## 某难度下匪徒总数（简报页显示用）
static func bandit_count(diff: String) -> int:
	var tier := int(Game.diff_info(diff).bandits)
	var n := SPAWNS.size()
	if tier == 0:
		n -= EASY_SKIP.size()
	if tier >= 2:
		n += EXTRA_HARD.size()
	if tier >= 3:
		n += EXTRA_INSANE.size()
	return n


## 初级去掉的两只老鼠（SPAWNS 下标）
const EASY_SKIP := [4, 7]
## 高级起追加
const EXTRA_HARD := [
	["raccoon", Vector3(-8.0, 0, 1.5), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(-2.0, 0, -1.0), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(-10.6, 0, -4.6), "shop", Vector3(1, 0, 0)],
	["raccoon", Vector3(7.2, 0, 2.2), "storage", Vector3(-1, 0, 0.3)],
	["raccoon", Vector3(6.6, 0, -7.6), "staff", Vector3(1, 0, 0.3)],
]
## 鬼畜再追加
const EXTRA_INSANE := [
	["raccoon", Vector3(-4.0, 0, 5.6), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(-11.0, 0, 1.8), "shop", Vector3(1, 0, 0)],
	["raccoon", Vector3(1.2, 0, -4.6), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(-5.0, 0, -4.6), "shop", Vector3(0, 0, 1)],
	["rat", Vector3(9.2, 0, 4.6), "storage", Vector3(-1, 0, 0)],
	["raccoon", Vector3(11.2, 0, 4.4), "storage", Vector3(-1, 0, 0)],
	["rat", Vector3(7.8, 0, -3.6), "staff", Vector3(1, 0, 0)],
]
const HOSTAGE_POS := Vector3(11.1, 0, -6.2)
const DOOR_POS := Vector3(8.8, 0, 0)

var player: Player
var enemies: Array[Enemy] = []
var _bandits_total := 0
var _bandits_defeated := 0
var _front_total := 0
var _front_defeated := 0
var _taker_defeated := false
var _all_bandits_bonus := false
var hostage: Hostage
var taker: Enemy
var door: Door
var cam: GameCamera
var hud: Hud
var pause_menu: PauseMenu
var nav: NavigationRegion3D
var _boss_nav: NavigationRegion3D
var _boss_nav_map := RID()
const RENDER_PIXEL_BUDGET := 1280 * 720
var _render_profile := {}
var builder: MapBuilder

var phase := 0
var finished := false
var breached := false
var t := 0.0
var _tips := {}
var _alerted_once := false
var _entered := false
var _light_t := 0.0
var _door_marker: Node3D

# 僵尸潮
const WAVE_TIME := 60.0
## 60秒潮中约两次机会；同时地面最多一件护盾，无法无限刷新。
const SHIELD_DROP_INTERVAL := 22.0
const ZOMBIE_SPAWNS := [
	Vector3(0, 0, 16.0), Vector3(-8.0, 0, 15.5), Vector3(8.0, 0, 15.5),
	Vector3(-11.0, 0, -4.4), Vector3(11.0, 0, 7.0), Vector3(-10.5, 0, 6.5),
]
var zombies: Array[Zombie] = []
var pickups: Array[Pickup] = []
var wave_on := false
var wave_fired := false
var wave_t := 0.0
var _spawn_acc := 0.0
var _heal_acc := 0.0
## 所有回血来源共享本局预算；按生成计数，不因拾取而返还。
var heal_drop_limit := 0
var heal_drops_spawned := 0
var _shield_acc := 0.0
var _grenade_acc := 0.0
const GRENADE_DROP_LIMIT := 2
const GRENADE_GROUND_CAP := 1
const OPTIONAL_WEAPON_DROP_LIMIT := 3
const OPTIONAL_GROUND_CAP := 4
const GRENADE_SUPPLY_INTERVAL := 24.0
var _grenade_drops := 0
var _weapon_drops := 0
## 人质获救后跑去门口的警车，上车撤离
const EVAC_POS := Vector3(-5.4, 0, 11.5)
var _boss_spawned := 0
var _boss_defeated := 0
var boss_required := 0
var _boss_dead_ids := {}
var _artifact: Pickup
var _env: Environment
var guide: GroundGuide
## 排行榜计时（真实时间；暂停菜单 / 变身动画期间不计）
var run_ms := 0.0
var _run_last := 0


func _enter_tree() -> void:
	# 物理插值只给在物理帧里移动的角色 / 子弹用（它们自己打开），其他节点每帧直接更新
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	Game.new_run()
	_apply_render_budget()
	get_viewport().size_changed.connect(_apply_render_budget)
	heal_drop_limit = int(Game.diff_info(String(Game.run.difficulty)).heal_drops)
	heal_drops_spawned = 0
	boss_required = clampi(int(Game.diff_info(String(Game.run.difficulty)).bosses), 0, 3)
	Fx.shell_count = 0
	_build_env()
	nav = NavigationRegion3D.new()
	add_child(nav)
	builder = MapBuilder.new(self, nav)
	builder.build()
	# 先烘焙导航（此时门还没建，门洞是通的），破门后就不用重烘焙了
	_bake_nav()
	door = Door.new()
	door.position = DOOR_POS
	door.level = self
	add_child(door)
	door.build(nav)
	door.breached.connect(_on_breached)
	_spawn()
	_build_door_marker()
	guide = GroundGuide.new()
	guide.level = self
	add_child(guide)

	cam = GameCamera.new()
	add_child(cam)
	cam.target = player
	cam.snap()
	hud = Hud.new()
	hud.level = self
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.level = self
	add_child(pause_menu)

	if not Game.touch:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_prewarm()
	hud.prewarm_transition_text()
	Game.bullet_time_changed.connect(_on_bullet_time)
	Sfx.music("combat")
	_set_phase(0)
	_intro()
	Online.start_run()


## 预热：把所有会用到的特效、模型、材质在镜头里各生成一次，
## 让着色器在转场遮挡期间编译完，避免游戏中第一次出现时卡顿。
func _prewarm() -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = player.global_position + Vector3(0, 0, 2.0)
	var p := root.global_position
	Fx.muzzle(root, p, Color(1, 0.8, 0.4))
	Fx.spark(root, p, Vector3.UP, Color(1, 0.85, 0.4))
	Fx.dust(root, p)
	Fx.dust(root, p, 2, Color(0.75, 1.0, 0.8, 0.85), 2.6, 0.22)
	Fx.ring(root, p, Pal.ORANGE)
	Fx.popup(root, p, "10", Pal.CREAM)
	Fx.popup(root, p, "击倒!", Pal.YELLOW, 64, true)
	Fx.shell(root, p, Vector3.RIGHT)
	Fx.ghost(root, player.model)
	var z := Models.zombie(false)
	root.add_child(z)
	z.position = Vector3(1.5, 0, 0)
	var zb := Models.zombie(true)
	root.add_child(zb)
	zb.position = Vector3(-1.5, 0, 0)
	root.add_child(Models.ghost())
	for w in ["shotgun", "laser", "rocket", "gatling", "heal"]:
		var m := Weapons.model(w)
		root.add_child(m)
	var star := MeshInstance3D.new()
	star.mesh = Models.star()
	star.material_override = Toon.glow(Pal.YELLOW, 1.6)
	root.add_child(star)
	for c in [Color(1.0, 0.86, 0.45), Color(1.0, 0.45, 0.15), Pal.ORANGE, Pal.TEAL, Pal.YELLOW]:
		var b := MeshInstance3D.new()
		b.mesh = Models.box(Vector3(0.1, 0.1, 0.5))
		b.material_override = Toon.glow(c, 3.0)
		root.add_child(b)
	var eb := MeshInstance3D.new()
	eb.mesh = Models.sphere(0.13)
	eb.material_override = Toon.glow(Color(0.85, 0.4, 1.0), 2.6)
	root.add_child(eb)
	var t := get_tree().create_timer(0.35, true, false, true)
	t.timeout.connect(root.queue_free)


## Cap only the 3D backbuffer; HUD/text/input stay at native viewport size.
## This avoids high-DPI canvas dimensions multiplying 3D pixel cost.
func _apply_render_budget() -> void:
	var viewport := get_viewport()
	var pixels := get_window().size
	# ViewportTexture metadata may apply the canvas stretch scale again.
	# Window.size is the actual display/canvas pixel extent on native/Web.
	var count := maxf(1.0, float(pixels.x) * float(pixels.y))
	var scale := minf(1.0, sqrt(float(RENDER_PIXEL_BUDGET) / count))
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	var fxaa := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_scale = scale
	_render_profile = {"viewport": [int(pixels.x), int(pixels.y)], "scale_3d": scale, "pixels_3d": int(count * scale * scale), "msaa": 0, "fxaa": fxaa, "hud_native_resolution": true}


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _boss_nav_map.is_valid():
		NavigationServer3D.free_rid(_boss_nav_map)
		_boss_nav_map = RID()


# ------------------------------------------------------------------ 场景

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0B1120")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6A7CB0")
	# 流畅画质没有点光源，环境光提亮补偿
	env.ambient_light_energy = 0.82 if Game.lite else 0.55
	# Keep the same fog shader variant from the first rendered frame.
	# Enabling fog at the horde used to invalidate the no-fog prewarm.
	# Zero density is visually clear; the existing horde tween adds the fog.
	env.fog_enabled = true
	env.fog_density = 0.0
	env.fog_height_density = 0.0
	env.fog_light_color = Color("3E7A55")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = not Game.lite
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	we.environment = env
	_env = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58, -35, 0)
	moon.light_color = Color("A9BCFF")
	moon.light_energy = 0.55
	# 角色脚下已有圆形假阴影；流畅画质关掉实时阴影（省掉整个场景再画一遍）
	moon.shadow_enabled = not Game.lite
	if Game.lite:
		moon.light_energy = 0.7
	moon.directional_shadow_max_distance = 45.0
	moon.shadow_blur = 1.5
	add_child(moon)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.25
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	nm.filter_baking_aabb = AABB(Vector3(-15, -1.5, -11), Vector3(30, 5, 30))
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)
	_bake_boss_nav(nm)


## Rat kings need a wider corridor than ordinary actors. A separate map
## keeps small-actor routes and all physical world collisions unchanged.
func _bake_boss_nav(base: NavigationMesh) -> void:
	var mesh := base.duplicate() as NavigationMesh
	mesh.clear()
	mesh.agent_radius = Zombie.BOSS_RADIUS + 0.05
	mesh.agent_height = 2.2
	mesh.cell_size = 0.05
	mesh.edge_max_error = 0.5
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, nav)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_boss_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_boss_nav_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(_boss_nav_map, mesh.cell_height)
	NavigationServer3D.map_set_active(_boss_nav_map, true)
	_boss_nav = NavigationRegion3D.new()
	add_child(_boss_nav)
	_boss_nav.set_navigation_map(_boss_nav_map)
	_boss_nav.navigation_mesh = mesh


func zombie_navigation_map(is_boss: bool) -> RID:
	return _boss_nav_map if is_boss and _boss_nav_map.is_valid() else get_world_3d().navigation_map


func _spawn() -> void:
	player = Player.new()
	player.level = self
	player.facing = Vector3(0, 0, -1)
	player.position = PLAYER_START
	add_child(player)
	var tier := int(Game.dv("bandits"))
	var list: Array = []
	for i in SPAWNS.size():
		if tier == 0 and EASY_SKIP.has(i):
			continue
		var sp: Array = SPAWNS[i].duplicate()
		# 神装掉落：收银台浣熊 → 散弹；仓库浣熊 → 激光；劫持者 → 火箭
		sp.append({1: "shotgun", 5: "laser", 8: "rocket"}.get(i, ""))
		sp.append(false)
		list.append(sp)
	if tier >= 2:
		for sp in EXTRA_HARD:
			list.append(sp + ["", true])
	if tier >= 3:
		for sp in EXTRA_INSANE:
			list.append(sp + ["", true])
	for s in list:
		var e := Enemy.new()
		e.setup(s[0], s[2], s[3])
		e.level = self
		# 追加的匪徒：站位离墙 / 货架保持距离，免得卡在墙里
		e.position = safe_drop_point(s[1]) if s[5] else s[1]
		if Game.autotest and s[5]:
			print("[spawn] %s %s want=(%.1f,%.1f) at=(%.2f,%.2f)" % [s[0], s[2], s[1].x, s[1].z, e.position.x, e.position.z])
		e.drop = s[4]
		add_child(e)
		enemies.append(e)
		_bandits_total += 1
		if e.zone != "staff":
			_front_total += 1
		if s[0] == "taker":
			taker = e
	hostage = Hostage.new()
	hostage.level = self
	hostage.facing = Vector3(-0.3, 0, 1)
	hostage.position = HOSTAGE_POS
	add_child(hostage)
	taker.hostage = hostage


func _build_door_marker() -> void:
	_door_marker = Node3D.new()
	add_child(_door_marker)
	_door_marker.position = DOOR_POS + Vector3(0, 2.3, 0.3)
	var m := MeshInstance3D.new()
	m.mesh = Models.prism(Vector3(0.6, 0.5, 0.15))
	m.material_override = Toon.glow(Pal.ORANGE, 2.2)
	m.rotation_degrees = Vector3(0, 45, 180)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_door_marker.add_child(m)
	_door_marker.visible = false


# ------------------------------------------------------------------ 每帧

func _process(delta: float) -> void:
	_light_t += delta
	# 警灯交替闪烁
	var phase_on := fmod(_light_t, 0.5) < 0.25
	if builder.car_lights.size() == 2:
		builder.car_lights[0].light_energy = 3.5 if phase_on else 0.2
		builder.car_lights[1].light_energy = 0.2 if phase_on else 3.5
		builder.car_bulbs[0].visible = phase_on
		builder.car_bulbs[1].visible = not phase_on
	# 员工休息室的灯在闪
	if builder.flicker_light and not breached:
		builder.flicker_light.light_energy = 1.6 if fmod(_light_t, 2.3) > 0.12 else 0.3
	# 自动门
	var near := player.global_position.distance_to(Vector3(0, 0, 8)) < 3.2
	for i in builder.entry_doors.size():
		var dd := builder.entry_doors[i]
		var sx := -1.0 if i == 0 else 1.0
		var target_x := sx * (2.3 if near else 0.76)
		dd.position.x = lerpf(dd.position.x, target_x, 1.0 - exp(-10.0 * delta))
	if Game.touch:
		# 手机上镜头只沿朝向轻微前瞻，开火时不晃
		cam.look_at_point = player.global_position + player.facing * 2.5
		cam.aiming = false
	else:
		cam.look_at_point = player.aim_point
		cam.aiming = player.aiming and not player.dead
	if _door_marker.visible:
		_door_marker.position.y = DOOR_POS.y + 2.3 + sin(_light_t * 4.0) * 0.18
		_door_marker.rotation.y += delta * 2.0

	var now_us := Time.get_ticks_usec()
	if _run_last > 0 and not finished:
		run_ms += minf((now_us - _run_last) / 1000.0, 100.0)
	_run_last = now_us
	if finished:
		return
	t += delta
	Game.run.time = t
	Game.run.run_ms = int(run_ms)
	if not _entered and player.global_position.z < 7.4 and absf(player.global_position.x) < 12.0:
		_entered = true
		Sfx.play("chime", -6.0)
		hud.radio.say("shiba", "汪！P.A.W. 特警！全部不许动！")
		if phase == 0:
			_set_phase(1)
	if player.in_cover:
		tip("cover")
	if wave_on:
		_tick_wave(delta)


## 当前任务目标的位置（地面箭头指引用），没有时返回 Vector3.INF
func guide_target() -> Vector3:
	match phase:
		0:
			return Vector3(0, 0, 6.5)
		1:
			var best := Vector3.INF
			var bd := 1e9
			for e in _front_enemies():
				if e.is_active():
					var d := e.global_position.distance_to(player.global_position)
					if d < bd:
						bd = d
						best = e.global_position
			return best
		2:
			return DOOR_POS + Vector3(0, 0, 1.0)
		3:
			return taker.global_position if is_instance_valid(taker) and taker.is_active() else Vector3.INF
		4:
			return hostage.global_position
		5:
			if _artifact and is_instance_valid(_artifact) and not _artifact.taken:
				return _artifact.global_position
	return Vector3.INF


# ------------------------------------------------------------------ 查询（供角色/子弹使用）

func mouse_world() -> Vector3:
	return cam.mouse_on_plane(Bullet.HEIGHT)


func zone_active(zone: String) -> bool:
	return zone != "staff" or breached


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Bullet.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## 子弹能否打到：考虑低矮掩体规则（离射手近的掩体可越过）
func clear_shot(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var start := from
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(start, to, Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var col: CollisionObject3D = hit.collider
		if (col.collision_layer & Bullet.LAYER_LOWCOVER) != 0:
			var p: Vector3 = hit.position
			if Vector2(from.x, from.z).distance_to(Vector2(p.x, p.z)) < Bullet.OVER_COVER:
				exclude.append(col.get_rid())
				start = p
				continue
		return false
	return true


func near_low_cover(pos: Vector3, r: float) -> bool:
	var p := Vector3(pos.x, 0.3, pos.z)
	for a in builder.low_covers:
		if a.grow(r).has_point(p):
			return true
	return false


func spawn_bullet(origin: Vector3, dir: Vector3, from_player: bool, dmg: float, shooter: Node, opts := {}) -> void:
	var b := Bullet.new()
	b.setup(self, origin, dir, from_player, dmg, shooter, opts)
	add_child(b)


## 所有可以被攻击的敌对目标（已激活区域的匪徒 + 僵尸）
func targets() -> Array:
	var list: Array = []
	for e in enemies:
		if e.is_active() and zone_active(e.zone):
			list.append(e)
	for z in zombies:
		if not z.dead:
			list.append(z)
	return list


## 激光：贯穿路径上所有敌人，碰到墙停下。返回终点
func laser(origin: Vector3, dir: Vector3, max_d: float, dmg: float, src: Node) -> Vector3:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var from := origin
	var end := origin + dir * max_d
	var hit_any := false
	for i in 14:
		var q := PhysicsRayQueryParameters3D.create(from, end, Bullet.LAYER_WORLD | Bullet.LAYER_ENEMY, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col: Object = hit.collider
		if col.has_method("take_hit"):
			if col.take_hit(dmg, dir * 0.6, origin, src):
				hit_any = true
				if randf() < 0.4:
					Fx.spark(self, hit.position, -dir, Pal.TEAL, 4, 4.0)
			exclude.append((col as CollisionObject3D).get_rid())
			from = hit.position
			continue
		end = hit.position
		if randf() < 0.5:
			Fx.spark(self, end, hit.normal, Pal.TEAL, 3, 3.0)
		break
	if hit_any:
		Game.run.hits = int(Game.run.hits) + 1
		hud.hitmarker(false)
	return end


## 爆炸：范围伤害（不伤人质，也不伤自己）
func explode(pos: Vector3, radius: float, dmg: float, src: Node) -> void:
	for t in targets():
		var d: float = t.global_position.distance_to(pos)
		if d < radius:
			var dir: Vector3 = t.global_position - pos
			dir.y = 0
			t.take_hit(dmg * (1.0 - 0.5 * d / radius), dir.normalized() * 2.5, pos, src)
	Fx.ring(self, pos, Pal.ORANGE, radius * 1.15, 0.4)
	Fx.dust(self, pos, 14, Color(1.0, 0.85, 0.6, 0.85), 4.0, 0.35)
	Fx.spark(self, pos + Vector3(0, 0.4, 0), Vector3.UP, Pal.ORANGE, 20, 9.0)
	if not Game.lite:
		var l := OmniLight3D.new()
		l.light_color = Pal.ORANGE
		l.light_energy = 6.0
		l.omni_range = radius * 2.5
		add_child(l)
		l.global_position = pos + Vector3(0, 1.0, 0)
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.35)
		tw.tween_callback(l.queue_free)
	Sfx.play("explosion", -2.0)
	Game.shake(0.5)


func spawn_pickup(pos: Vector3, kind: String, weapon := "", drop_height := 0.0, from := Vector3.INF) -> Pickup:
	# Every source shares successful-spawn budgets and simultaneous limits.
	# The story-critical gatling drop is exempt, so loot throttling cannot
	# prevent the horde from starting or make the mission unwinnable.
	var essential := kind == "weapon" and weapon == "gatling"
	if finished or player == null or player.dead:
		return null
	if not essential and optional_pickups_on_ground() >= OPTIONAL_GROUND_CAP:
		return null
	if kind == "heal" and (heal_drops_spawned >= heal_drop_limit or has_ground_heal()):
		return null
	if kind == "grenade" and (_grenade_drops >= GRENADE_DROP_LIMIT or _grenades_on_ground() >= GRENADE_GROUND_CAP or player.grenades >= Player.MAX_GRENADES):
		return null
	if kind == "shield" and (player.shield_t > 0.0 or has_ground_shield()):
		return null
	if kind == "weapon" and not essential and (_weapon_drops >= OPTIONAL_WEAPON_DROP_LIMIT or optional_weapon_on_ground()):
		return null
	var p := Pickup.new()
	p.level = self
	p.kind = kind
	p.weapon = weapon
	p.drop_height = drop_height
	var want := pos
	pos = safe_drop_point(pos, from)
	p.position = Vector3(pos.x, 0, pos.z)
	if Game.autotest:
		print("[pickup] %s %s want=(%.2f,%.2f) at=(%.2f,%.2f)" % [kind, weapon, want.x, want.z, pos.x, pos.z])
	if kind == "heal":
		heal_drops_spawned += 1
		Game.run.heal_drops = heal_drops_spawned
	if kind == "grenade":
		_grenade_drops += 1
	elif kind == "weapon" and not essential:
		_weapon_drops += 1
	add_child(p)
	pickups.append(p)
	if kind == "heal":
		tip("heal")
	if kind == "weapon" and weapon != "gatling":
		tip("weapon")
	return p


## 掉落点修正：不穿墙（从掉落者位置连线检查）、离墙/柜子至少 1.1 米、落在导航网格上
func safe_drop_point(want: Vector3, from := Vector3.INF) -> Vector3:
	var space := get_world_3d().direct_space_state
	var mask := Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	var p := Vector3(want.x, 0.5, want.z)
	if from != Vector3.INF:
		var a := Vector3(from.x, 0.5, from.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, p, mask))
		if hit:
			p = a + (p - a).limit_length(maxf(0.0, a.distance_to(hit.position) - 0.3))
	const CLEAR := 1.1
	for _it in 4:
		var push := Vector3.ZERO
		for i in 8:
			var d := Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 8.0)
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + d * CLEAR, mask))
			if r:
				push -= d * (CLEAR - p.distance_to(r.position))
		if push.length() < 0.02:
			break
		var np := p + push
		var r2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, np, mask))
		if r2:
			np = p + (np - p).limit_length(maxf(0.0, p.distance_to(r2.position) - 0.3))
		p = np
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var q := NavigationServer3D.map_get_closest_point(map, p)
		# 只接受附近的吸附点，防止吸到墙外的导航面
		if Vector2(q.x - p.x, q.z - p.z).length() < 0.8:
			p = Vector3(q.x, p.y, q.z)
	return Vector3(p.x, 0, p.z)


## 小米跑到警车旁：上车，警车鸣笛开走
func on_hostage_evacuated() -> void:
	var h := hostage
	if h == null:
		return
	hostage = null
	if Game.autotest:
		print("[evac] hostage reached the car after %.1fs at (%.1f, %.1f)" % [h._evac_t, h.global_position.x, h.global_position.z])
	var car_pos := Vector3(-6.5, 0.6, 13.4)
	Fx.ring(self, h.global_position, Pal.TEAL, 2.4)
	Fx.popup(self, h.global_position + Vector3(0, 1.9, 0), "小米安全撤离!", Pal.TEAL, 72, true, 1.3, 1.2)
	Sfx.play("perfect", -4.0, 1.1, 0.0)
	var tw := h.create_tween()
	tw.tween_property(h, "global_position", car_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(h, "scale", Vector3.ONE * 0.2, 0.35)
	tw.tween_callback(h.queue_free)
	hud.radio.say("chief", "小米已经上车撤离！[color=#FFC93C]你守住这里！[/color]", 0.0, true)
	Game.add_score(200)
	hud.score_popup("人质安全撤离", 200)
	# 警车开走（碰撞体一起拿掉）
	await get_tree().create_timer(0.5, false).timeout
	if builder.car == null:
		return
	if builder.car_body:
		builder.car_body.queue_free()
	Sfx.play("alarm", -8.0, 1.3, 0.0)
	var ct := builder.car.create_tween().set_parallel()
	ct.tween_property(builder.car, "position:x", builder.car.position.x - 34.0, 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for l in builder.car_lights:
		ct.tween_property(l, "position:x", l.position.x - 34.0, 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ct.chain().tween_callback(func():
		for l in builder.car_lights:
			l.queue_free()
		builder.car_lights.clear()
		builder.car.visible = false
	)


func _grenades_on_ground() -> int:
	var n := 0
	for pk in pickups:
		if is_instance_valid(pk) and pk.kind == "grenade" and not pk.taken:
			n += 1
	return n


## First successful grenade drop teaches it; subsequent chances are rare.
## The roll never spends the budget: only spawn_pickup may count a crate.
func roll_grenade_drop() -> bool:
	if _grenade_drops >= GRENADE_DROP_LIMIT or _grenades_on_ground() >= GRENADE_GROUND_CAP or player.grenades >= Player.MAX_GRENADES:
		return false
	return _grenade_drops == 0 or randf() < 0.12


func optional_pickups_on_ground() -> int:
	var n := 0
	for pk in pickups:
		if is_instance_valid(pk) and not pk.taken and not (pk.kind == "weapon" and pk.weapon == "gatling"):
			n += 1
	return n


func optional_weapon_on_ground() -> bool:
	for pk in pickups:
		if is_instance_valid(pk) and not pk.taken and pk.kind == "weapon" and pk.weapon != "gatling":
			return true
	return false


## 枪声：惊动附近（非员工休息室）的匪徒
func noise(pos: Vector3, radius: float) -> void:
	for e in enemies:
		if not e.alerted and e.is_active() and zone_active(e.zone):
			if e.global_position.distance_to(pos) < radius:
				e.alert()


func interactables() -> Array:
	var list: Array = []
	if door and not door.done:
		list.append(door)
	if hostage:
		list.append(hostage)
	return list


func best_interactable() -> Node:
	if player == null or player.dead or finished:
		return null
	var best: Node = null
	var best_d := 1e9
	for it in interactables():
		if not it.can_interact(player):
			continue
		var p: Vector3 = it.interact_pos()
		var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		var reach := 2.1 if it is Door else 1.7
		if d < reach and d < best_d:
			best = it
			best_d = d
	return best


func player_interact() -> void:
	var it := best_interactable()
	if it:
		it.interact(player)


# ------------------------------------------------------------------ 任务流程

func _set_phase(p: int) -> void:
	phase = p
	match p:
		0:
			hud.set_objective("进入喵喵便利店", "")
		1:
			_update_clear_objective()
		2:
			door.breachable = true
			_door_marker.visible = true
			hud.set_objective("破门进入员工休息室", "")
			hud.set_target(door)
			cam.focus(DOOR_POS, 1.6)
		3:
			_door_marker.visible = false
			if _taker_defeated:
				_set_phase(4)
				return
			hud.set_objective("制服劫持者", "")
			hud.set_target(taker)
		4:
			hud.set_objective("解救人质 · 小米", "")
			hud.set_target(hostage)
			# 镜头指引：推到人质身上，再回来
			cam.focus(hostage.global_position, 1.8)
			hud.cinema(1.8)
		5:
			hud.set_target(null)
			hud.set_objective("小米已获救", "")


func _front_enemies() -> Array[Enemy]:
	var list: Array[Enemy] = []
	for e in enemies:
		if e.zone != "staff":
			list.append(e)
	return list


func _update_clear_objective() -> void:
	hud.set_objective("清除店内匪徒", "%d/%d" % [_front_defeated, _front_total])
	if _front_total > 0 and _front_defeated >= _front_total and phase == 1:
		_set_phase(2)
		hud.radio.say("chief", "店面清理完毕！员工休息室里有动静……人质就在里面。")
		hud.radio.say("shiba", "交给我！")
		tip("door")


func on_enemy_alerted(e: Enemy) -> void:
	if phase == 0 and e.zone != "staff":
		_set_phase(1)
	if not _alerted_once:
		_alerted_once = true
		hud.radio.say("chief", "发现匪徒！[color=#FFB347]击倒即可永久制服[/color]，注意人质。")
		tip("fire")
		get_tree().create_timer(9.0, false).timeout.connect(func(): tip("skill"))


func on_enemy_down(e: Enemy) -> void:
	# Lifetime-independent counters; no freed bandit remains in actor queries.
	if not enemies.has(e):
		return
	var was_taker := e == taker
	enemies.erase(e)
	_bandits_defeated += 1
	if e.zone != "staff":
		_front_defeated += 1
	if player.lock_target == e:
		player.lock_target = null
	if was_taker:
		_taker_defeated = true
		taker = null
	if phase == 1:
		_update_clear_objective()
	if was_taker and phase == 3:
		_set_phase(4)
		hud.radio.say("chief", "劫持者已制服！快去解救人质！")
	if not _all_bandits_bonus and _bandits_defeated == _bandits_total:
		_all_bandits_bonus = true
		hud.score_popup("全员制服", 300)
		Game.add_score(300)


func _on_breached() -> void:
	breached = true
	if builder.flicker_light:
		builder.flicker_light.light_energy = 1.8
	hud.radio.say("shiba", "破门！！", 0.0, true)
	tip("hostage")
	for e in enemies:
		if e.zone == "staff":
			e.alert()
	_set_phase(3)


func on_hostage_hit(hits: int) -> void:
	var limit := int(Game.dv("hostage_hits"))
	if hits >= limit:
		_fail("人质被误伤")
	else:
		hud.radio.say("chief", "[color=#E63946]小心人质！！[/color]" + ("再打中一次就全完了！" if hits == limit - 1 else "瞄准了再开火！"), 0.0, true)
		hud.toast("小心人质！")


func on_hostage_rescued() -> void:
	Game.run.rescued = true
	_start_wave()


func on_player_dead() -> void:
	_fail("被僵尸鼠淹没了" if phase == 5 else "豆包被击倒了")


func on_cover_block(pos: Vector3) -> void:
	Fx.popup(self, pos + Vector3(0, 1.0, 0), "格挡", Pal.TEAL, 44, true, 0.6, 0.5)
	Sfx.play("block", -8.0)


func _on_bullet_time(active: bool) -> void:
	hud.set_bullet_time(active, active and not finished and phase == 2)
	for e in enemies:
		if e.is_active():
			e.model.set_outline(Pal.RED if active else Pal.OUTLINE_ENEMY)


# ------------------------------------------------------------------ 剧情与教学

static func K(key: String) -> String:
	return "[color=#FFB347][b]【%s】[/b][/color]" % key


## 按平台选择提示文字：键鼠 / 触屏
static func T(pc: String, touch: String) -> String:
	return touch if Game.touch else pc


func _intro() -> void:
	var front := _front_enemies().size()
	hud.radio.say("chief", "豆包，这是你第一次独立出勤。喵喵便利店报警，店里至少有 %d 名匪徒。" % front)
	hud.radio.say("chief", "先进店里看看 —— 注意安全。")
	tip("move")


## 一次性教学提示：弹出新手提示卡片（文案见 Tips）
## （卡片自己会去重；排队太久被丢掉的提示，下次再触发时还能弹出）
func tip(id: String) -> void:
	if finished:
		return
	match id:
		"damage":
			hud.tip("roll")
		_:
			hud.tip(id)


# ------------------------------------------------------------------ 结束

# ------------------------------------------------------------------ 高潮：僵尸来袭

func _start_wave() -> void:
	_set_phase(5)
	hostage.evacuate(EVAC_POS)
	if Game.autotest:
		get_tree().create_timer(2.0, false).timeout.connect(func():
			var at := Game.get_node_or_null("AutoTest")
			if at == null:
				for c in Game.get_children():
					if c.has_method("_shot"):
						at = c
			if at:
				at._shot("evac")
		)
	hud.radio.clear()
	hud.radio.say("hamster", "呜呜……谢谢特警叔叔！", 1.8)
	hud.radio.say("shiba", "不客气！……是哥哥。快去门口的警车！", 1.6)
	Sfx.play("victory", -6.0, 1.0, 0.0)
	await get_tree().create_timer(3.4, false).timeout
	if finished:
		return
	hud.radio.say("chief", "等等……仓库里那批[color=#7CFFB2]实验罐头[/color]在冒绿烟！", 2.0, true)
	hud.radio.say("chief", "外面来了一大群[color=#7CFFB2]僵尸鼠[/color]！守住便利店，坚持到增援赶到！", 2.6)
	Sfx.play("alarm", -2.0, 1.0, 0.0)
	Sfx.music("wave")
	hud.wave_banner()
	Game.shake(0.4)
	# 灯光变成诡异的绿色
	var et := create_tween().set_parallel()
	et.tween_property(_env, "ambient_light_color", Color("6E9E86"), 1.5)
	# Do not toggle fog_enabled here: only change uniforms, not shaders.
	et.tween_property(_env, "fog_density", 0.004, 2.0)
	wave_on = true
	await get_tree().create_timer(1.6, false).timeout
	if finished:
		return
	# 空投神器：落在豆包面前
	var drop := player.global_position + player.facing * 2.6
	_artifact = spawn_pickup(drop, "weapon", "gatling", 9.0, player.global_position)
	hud.set_target(_artifact)
	cam.focus(_artifact.global_position, 1.3)
	hud.set_objective("拿起空投神器！", "")
	hud.radio.say("chief", "空投神器到了 —— 快拿上它！", 0.0, true)


## 拾取神器 → 像素风变身特写 → FIRE!
func equip_artifact() -> void:
	if hud.touch:
		hud.touch.release_all()
	var cs := Cutscene.new()
	cs.name = "Cutscene"
	add_child(cs)
	await cs.done
	if finished:
		return
	player.give_weapon("gatling")
	wave_fired = true
	wave_t = 0.0
	hud.fire_shout()
	hud.set_target(null)
	Game.shake(0.7)
	Fx.ring(self, player.global_position, Pal.YELLOW, 5.0, 0.5)
	hud.radio.say("shiba", "[color=#FFC93C][b]FIRE！！！[/b][/color]", 1.4, true)
	get_tree().create_timer(1.5, false).timeout.connect(func(): tip("wave"))


func _tick_wave(delta: float) -> void:
	if finished or player.dead:
		return
	if wave_fired:
		wave_t = minf(WAVE_TIME, wave_t + delta)
	var deadline := wave_fired and wave_t >= WAVE_TIME
	if wave_fired:
		if deadline:
			hud.set_objective("消灭剩余鼠王", "剩余 %d 只 · 00秒" % remaining_bosses())
		else:
			var left := maxf(0.0, WAVE_TIME - wave_t)
			hud.set_objective("坚守阵地" if hostage == null else "坚守阵地 · 掩护小米撤离", "%d秒" % ceili(left))
	# The deadline ends new regular waves, not living rat kings.
	if not deadline:
		var rate := 2.2
		var cap := 6
		if wave_fired:
			rate = lerpf(1.0, 0.36, clampf(wave_t / 45.0, 0.0, 1.0)) * Game.dv("zombie_rate")
			cap = int(Game.dv("zombie_cap"))
		_spawn_acc += delta
		if _spawn_acc >= rate and zombies.size() < cap:
			_spawn_acc = 0.0
			_spawn_zombie(false)
	# Count successful spawns only. A failed spawn retries next tick; if a
	# tick skips several scheduled times, all due kings still appear.
	var boss_times := [26.0, 38.0, 48.0]
	while wave_fired and _boss_spawned < boss_required and wave_t >= boss_times[_boss_spawned]:
		var bz := _spawn_zombie(true)
		if bz == null:
			break
		_boss_spawned += 1
		if Game.autotest:
			print("[boss] #%d at wave_t=%.1f" % [_boss_spawned, wave_t])
		cam.focus(bz.global_position, 1.2)
		if _boss_spawned == 1:
			hud.toast("僵尸鼠王出现了！")
			hud.radio.say("chief", "小心！是[color=#FFC93C]僵尸鼠王[/color]！", 0.0, true)
		else:
			hud.toast("又来一只鼠王！！" if _boss_spawned == 2 else "第三只鼠王！！！")
			hud.radio.say("chief", "[color=#E63946]%s鼠王！[/color]顶住！" % ("第二只" if _boss_spawned == 2 else "第三只"), 0.0, true)
	if wave_fired and not deadline:
		_shield_acc += delta
		if _shield_acc >= SHIELD_DROP_INTERVAL:
			_shield_acc = 0.0
			if player.shield_t <= 0.0 and not has_ground_shield():
				var shield_pos := player.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
				spawn_pickup(shield_pos, "shield", "", 8.0, player.global_position)
				tip("shield")
		_heal_acc += delta
		# 手雷补给：24 秒间隔，与所有敌人来源共享每局两箱上限
		_grenade_acc += delta
		if _grenade_acc > GRENADE_SUPPLY_INTERVAL and player.grenades < Player.MAX_GRENADES and _grenades_on_ground() < GRENADE_GROUND_CAP and _grenade_drops < GRENADE_DROP_LIMIT:
			_grenade_acc = 0.0
			var gp := player.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			spawn_pickup(gp, "grenade", "", 8.0, player.global_position)
		if _heal_acc > Game.dv("heal_every"):
			_heal_acc = 0.0
			var hp_pos := player.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			spawn_pickup(hp_pos, "heal", "", 8.0, player.global_position)
	if deadline and can_finish_wave():
		_finale()


func remaining_bosses() -> int:
	var alive := 0
	for z in zombies:
		if is_instance_valid(z) and z.boss and not z.dead:
			alive += 1
	return maxi(alive, maxi(0, boss_required - _boss_defeated))


func can_finish_wave() -> bool:
	return not finished and not player.dead and wave_fired and wave_t >= WAVE_TIME \
		and bool(Game.run.get("rescued", false)) and _boss_spawned >= boss_required \
		and _boss_defeated >= boss_required and remaining_bosses() == 0


func _spawn_zombie(is_boss: bool) -> Zombie:
	var options: Array = []
	for sp in ZOMBIE_SPAWNS:
		if sp.distance_to(player.global_position) > 7.5:
			options.append(sp)
	if options.is_empty():
		return null
	var pos: Vector3 = options.pick_random()
	pos += Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
	if is_boss:
		pos = _clear_boss_spawn(options)
		if pos == Vector3.INF:
			return null
	var z := Zombie.new()
	z.boss = is_boss
	z.level = self
	z.position = pos
	add_child(z)
	zombies.append(z)
	return z


## Correct the initial spawn before the actor exists; this is not chase recovery.
## The nav point is flattened to the same floor plane used by Actor._move.
func _clear_boss_spawn(options: Array) -> Vector3:
	var map := zombie_navigation_map(true)
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var capsule := CapsuleShape3D.new()
	capsule.radius = Zombie.BOSS_RADIUS
	capsule.height = 2.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	query.margin = 0.01
	var candidates := options.duplicate()
	candidates.shuffle()
	for sp in candidates:
		for attempt in 2:
			var seed_pos: Vector3 = sp
			if attempt == 0:
				seed_pos += Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
			var pos := NavigationServer3D.map_get_closest_point(map, seed_pos)
			pos.y = 0.0
			if pos.distance_to(player.global_position) < 7.5:
				continue
			query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.16, 0))
			if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				return pos
	return Vector3.INF


func on_zombie_killed(z: Zombie) -> void:
	if z.boss and _boss_dead_ids.has(z.get_instance_id()):
		return
	if z.boss and z.dead:
		_boss_dead_ids[z.get_instance_id()] = true
		_boss_defeated += 1
	zombies.erase(z)
	if finished:
		Game.run.zombies = int(Game.run.get("zombies", 0)) + 1
		return
	Game.run.zombies = int(Game.run.get("zombies", 0)) + 1
	Game.add_score(500 if z.boss else 20)
	hud.add_kill()
	if z.boss:
		Game.run.boss = true
		Game.hitstop(0.12)
		Game.bullet_time(0.9)
		Fx.ring(self, z.global_position, Pal.YELLOW, 6.0, 0.5)
		hud.score_popup("击败僵尸鼠王", 500)
		hud.radio.say("shiba", "鼠王，搞定！", 0.0, true)
		if randf() < 1.0:
			spawn_pickup(z.global_position, "heal", "", 0.0, z.global_position)


## 终局：空投炸弹清场
func _finale() -> void:
	if not can_finish_wave():
		return
	finished = true
	player.clear_shield()
	wave_on = false
	hud.set_target(null)
	hud.set_objective("坚守成功！", "")
	Sfx.music("")
	hud.radio.clear()
	hud.radio.say("chief", "增援到了 —— 空投炸弹！豆包，趴下！！", 1.6)
	await get_tree().create_timer(1.0, true, false, true).timeout
	hud.flash(1.0)
	Sfx.play("explosion", 2.0, 0.7, 0.0)
	Sfx.play("breach", 0.0, 0.8, 0.0)
	Game.shake(1.0)
	Game.bullet_time(2.4)
	Fx.ring(self, player.global_position, Color(1.0, 0.95, 0.7), 16.0, 0.8)
	for z in zombies.duplicate():
		if not z.boss:
			z.finale_pop(randf_range(0.05, 0.9))
	await get_tree().create_timer(0.6, true, false, true).timeout
	Sfx.play("victory", -2.0, 1.0, 0.0)
	hud.mission_banner(true, "僵尸潮清除 · 小米安全")
	hud.radio.say("hamster", "哇 —— 豆包哥哥好帅！", 1.8)
	if _taker_defeated:
		hud.radio.say("raccoon", "哼……你们什么都不知道。老K 会来接我的。", 2.6)
	await get_tree().create_timer(6.0, true, false, true).timeout
	Game.goto("results", {"success": true})


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	hud.set_target(null)
	Sfx.music("")
	Sfx.play("fail", -2.0, 1.0, 0.0)
	hud.mission_banner(false, reason)
	hud.radio.clear()
	hud.radio.say("chief", "豆包！豆包！听到请回答……撤退，重新部署！", 2.4)
	await get_tree().create_timer(3.2, true, false, true).timeout
	Game.goto("results", {"success": false, "reason": reason})


func has_ground_shield() -> bool:
	for pk in pickups:
		if is_instance_valid(pk) and not pk.taken and pk.kind == "shield":
			return true
	return false


func has_ground_heal() -> bool:
	for pk in pickups:
		if is_instance_valid(pk) and not pk.taken and pk.kind == "heal":
			return true
	return false
