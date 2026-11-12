class_name HarborLevel
extends Level
## 第二章 · 雾港码头「罐头狂暴」（Windows 版）
##
## 一局 3–5 分钟，跟着【主线任务】走（顶部目标 + 地上箭头 + 目标头顶的标记）：
##   1 砸开货箱 → 2 撬开 3 个可疑集装箱找证物 → 3 炸掉油罐区的实验罐头（夜影加入）
##   → 4 打爆黑眼圈帮老大「老K」的罐头蟹机甲 → 5 坚守 50 秒等撤离艇 → 6 跑上撤离艇 = 任务完成
## 人物：局长老灰（指挥）、夜影（卧底黑猫，第 3 步爬上龙门吊支援）、老K（黑眼圈帮老大，船长帽浣熊，开罐头蟹）
## 一路上：砸东西 / 打僵尸鼠 → 罐头自己飞过来 → 罐头条满了【自动升级】
##   → 每吸满 100 罐触发【罐头狂暴】：豆包变身巨型罐头机甲 10 秒，无敌、踩到哪炸到哪
## 综合分：任务进度 + 通关用时 + 击退 + 罐头 + 狂暴 + 罐头蟹
##
## 复用序章的玩家、僵尸鼠、子弹、特效、HUD、暂停菜单；地图 / 可打碎物 / 罐头吸收来自 HarborBuilder、Breakable、Loot。

const START_POS := Vector3(0, 0, 8.5)
const MAX_LOOSE_LOOT := 450
const RAMPAGE_NEED := 100
const RAMPAGE_TIME := 10.0
## 主线：标题 / 目标头顶的标记文字
const STEPS := [
	{"title": "打碎货箱", "mark": "打碎"},
	{"title": "轰开红色集装箱", "mark": "证物"},
	{"title": "引爆红油桶", "mark": "引爆"},
	{"title": "打爆老K的罐头蟹", "mark": "老K"},
	{"title": "坚守到撤离艇来", "mark": ""},
	{"title": "跑上撤离艇！", "mark": "撤离"},
]
const EVIDENCE := [Vector3(-17.0, 0, 1.8), Vector3(1.5, 0, -9.5), Vector3(6.5, 0, 14.0)]
const OIL_YARD := Rect2(-21.5, -12.5, 11.5, 10.5)
## 撤离艇停靠点：西码头 / 大船旁边，哪个离豆包近就停哪个
const BOAT_SPOTS := [Vector3(-17.0, 0, -14.4), Vector3(4.0, 0, -14.4)]
const BOSS_POS := Vector3(4.0, 0, -14.2)
const HOLD_TIME := 50.0
## 第二章的难度表（简报页的难度说明也读这里）
const HDIFF := {
	"easy": {"desc": ["你有 200 血，受伤 ×0.4", "僵尸鼠少、慢、脆，回血快", "没有精英鼠王；罐头蟹技能间隔长", "回血、手雷掉得勤"],
		"bosses": 1, "boss_cd": 4.6, "boss_hp": 0.8, "grenade_every": 22.0, "heal_every": 18.0,
		"zombie": 0.75, "bite": 1.0, "regen": 1.0, "variant": 0.6, "speed": 1.0, "elite_every": 0.0, "lunge": 0.0},
	"normal": {"desc": ["你有 100 血，标准伤害", "冲刺鼠会扑咬，胖胖鼠 / 酸液鼠登场", "每 70 秒一只精英鼠王；罐头蟹会放弹幕", "回血、手雷适量"],
		"bosses": 1, "boss_cd": 3.4, "boss_hp": 1.0, "grenade_every": 30.0, "heal_every": 28.0,
		"zombie": 1.0, "bite": 1.6, "regen": 0.6, "variant": 1.0, "speed": 1.0, "elite_every": 70.0, "lunge": 0.0},
	"hard": {"desc": ["你有 130 血，受伤 ×1.25，回血很慢", "鼠潮 ×1.7、更快，所有僵尸鼠都会扑咬", "每 40 秒一只精英鼠王；罐头蟹血 ×1.6、连招", "补给更少"],
		"bosses": 1, "boss_cd": 2.5, "boss_hp": 1.6, "grenade_every": 40.0, "heal_every": 40.0,
		"zombie": 1.7, "bite": 2.6, "regen": 0.3, "variant": 1.7, "speed": 1.15, "elite_every": 40.0, "lunge": 1.0},
	"insane": {"desc": ["你有 90 血，受伤 ×1.8，几乎不回血", "鼠潮 ×2.1、飞快，扑咬不停", "每 28 秒一只精英鼠王；罐头蟹血 ×2、技能连发", "补给稀少"],
		"bosses": 1, "boss_cd": 1.9, "boss_hp": 2.0, "grenade_every": 50.0, "heal_every": 55.0,
		"zombie": 2.1, "bite": 2.8, "regen": 0.12, "variant": 2.2, "speed": 1.25, "elite_every": 28.0, "lunge": 1.6},
}


static func hdiff() -> Dictionary:
	return HDIFF.get(Game.difficulty, HDIFF["normal"])


## 高难度的倍率不是开局就拉满：前 75 秒从「接近中级」逐渐爬到满强度（那时你也升了几级）
func ramp(key: String) -> float:
	var x := float(hdiff()[key])
	if x <= 1.2:
		return x
	return lerpf(1.2, x, clampf(t / 75.0, 0.0, 1.0))


## 神装掉落池（散弹枪最好用，多放几份；激光 / 磁轨已删）
const WEAPON_POOL := ["shotgun", "shotgun", "shotgun", "rocket", "smg", "smg"]


## 每一步的「热度」：决定刷怪速度和上限（第一步几乎没怪，让人先学会砸箱子）
const HEAT := [0.0, 0.3, 0.45, 0.55, 0.85, 0.5]

const UPGRADES := {
	"rapid": {"name": "连发", "desc": "射速 +25%", "icon": "fire", "max": 3},
	"mag": {"name": "扩容弹匣", "desc": "弹匣 +12 发，并立刻装满", "icon": "reload", "max": 3},
	"spread": {"name": "散射", "desc": "每次多打 1 发子弹", "icon": "weapon", "max": 4},
	"boom": {"name": "爆炸弹", "desc": "子弹打中会小范围爆炸", "icon": "grenade", "max": 3},
	"pierce": {"name": "穿透", "desc": "子弹多穿过 1 个敌人", "icon": "warn", "max": 3},
	"power": {"name": "重拳", "desc": "子弹伤害 +35%", "icon": "dash", "max": 5},
	"magnet": {"name": "吸铁石", "desc": "吸罐头的范围 +60%", "icon": "magnet", "max": 3},
	"speed": {"name": "疾跑", "desc": "移动速度 +12%", "icon": "move", "max": 3},
	"vital": {"name": "罐头大餐", "desc": "生命上限 +25，并且回满血", "icon": "heart", "max": 4},
	"orbit": {"name": "罐头卫星", "desc": "身边多一颗旋转的罐头，撞到敌人造成伤害", "icon": "switch", "max": 5},
	"nade": {"name": "自动手雷", "desc": "每隔几秒自动往敌人最多的地方扔手雷", "icon": "grenade", "max": 4},
	"cat": {"name": "夜影支援", "desc": "夜影爬上龙门吊，自动狙击最近的敌人", "icon": "cat", "max": 4},
}

var hb: HarborBuilder
var hhud: HarborHud
var stage := "play"               # play → over
var step := 0                     # 主线第几步（0 起）
var step_n := 0                   # 这一步完成了多少
var step_need := 1
var won := false
var marks: Array[Node3D] = []     # 头顶要画标记的目标（HarborHud 画）
var evidence_found := 0
var _evidence: Array[Breakable] = []
var _bosses: Array[Zombie] = []
var _hold_t := 0.0
var _evac: Node3D
var _boat: Node3D
var _step_t := 0.0
var kings: Array[RatKing] = []
var _k_deck: Node3D               # 船上的老K（第 4 步跳进机甲，打爆后又弹回船上）
var support: HarborSupport
var spitters: Array[Zombie] = []
var elites_down := 0
var _elite_t := 0.0
var _lunge_scan := 0.0
var _mk_n := 0                    # 连爆：短时间内连续击杀的数量
var _mk_t := 0.0
var _corpses := 0
var _grenade_t := 0.0
var _heal_t := 0.0
var _upgrade_q := 0
var breakables: Array[Breakable] = []
var loose_loot := 0

# 本局数据
var cans := 0
var kills := 0
var smashed := 0
var bosses_down := 0
var rampages := 0
var level_n := 1
var xp := 0
var fever := 0
var ups := {}                     # 升级 id → 等级
var rampage_t := 0.0

var _drop_acc := 0.0
var _final_tide := false
var _surge_t := 0.0
var _surge_n := 0
var _stomp_t := 0.0
var _nade_t := 0.0
var _cat_t := 0.0
var _orbiters: Array[Node3D] = []
var _orbit_hit := {}
var _orbit_a := 0.0
var _stack: MultiMeshInstance3D
var _stack_label: Label3D
var _stack_slots: Array[Transform3D] = []
var _marker: MeshInstance3D
var _cat_node: Node3D
var _rng := RandomNumberGenerator.new()
var _occupied: Array[Rect2] = []


func case_name() -> String:
	return "案件 #002 · 雾港码头"


func restart_screen() -> String:
	return "harbor"


func _ready() -> void:
	Game.new_run()
	Game.run["chapter"] = 2
	_rng.seed = 20261110
	_apply_render_budget()
	get_viewport().size_changed.connect(_apply_render_budget)
	Fx.shell_count = 0
	_build_env()
	nav = NavigationRegion3D.new()
	add_child(nav)
	hb = HarborBuilder.new(self, nav)
	builder = hb
	hb.build()
	_place_breakables()
	_build_stack()
	_bake_nav()
	_spawn_player()
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
	hhud = HarborHud.new()
	hhud.level = self
	add_child(hhud)
	support = HarborSupport.new()
	support.level = self
	add_child(support)
	pause_menu = PauseMenu.new()
	pause_menu.level = self
	add_child(pause_menu)

	if not Game.touch:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_prewarm()
	Game.bullet_time_changed.connect(_on_bullet_time)
	Sfx.music("combat")
	phase = 1
	_place_k_on_ship()
	hud.radio.say("chief", "豆包！黑眼圈帮的实验罐头就藏在这个码头，还有[color=#7CFFB2]僵尸鼠[/color]从船上爬下来！")
	hud.radio.say("boss_k", "条子来了？小的们，把罐头给我看好！天亮前[color=#FF5A5A]开船[/color]！")
	_start_step(0)
	tip("smash")


# ------------------------------------------------------------------ 场景（沿用 HarborBuilder）

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0A1626")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7486AD")
	env.ambient_light_energy = 0.85 if Game.lite else 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = not Game.lite
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color("3A5570")
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.06
	we.environment = env
	_env = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -30, 0)
	moon.light_color = Color("A9C4FF")
	moon.light_energy = 0.6 if not Game.lite else 0.75
	moon.shadow_enabled = not Game.lite
	moon.directional_shadow_max_distance = 50.0
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
	nm.filter_baking_aabb = AABB(Vector3(-24, -1.5, -16), Vector3(48, 5, 35))
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


# ------------------------------------------------------------------ 可打碎的东西

const REGIONS := [
	[Rect2(-9, 8, 18, 7), 10, ["box", "box", "wood"]],
	[Rect2(-21, -1, 13, 5), 8, ["box", "wood", "wood"]],
	[Rect2(-20, 6, 10, 10), 10, ["fish", "fish", "box"]],
	[Rect2(-20.5, -11, 9.5, 8), 12, ["barrel", "barrel", "barrel", "wood"]],
	[Rect2(7.5, -14.5, 15, 30), 16, ["box", "wood", "box", "barrel"]],
	[Rect2(-8, -14.5, 15, 8), 9, ["box", "wood", "barrel"]],
	[Rect2(-5, -4, 10, 3.0), 4, ["box", "wood"]],
]
const LOOT_CONTAINERS := [
	Vector3(16.0, 0, 6.5), Vector3(-17.0, 0, 1.8),
	Vector3(1.5, 0, -9.5), Vector3(6.5, 0, 14.0), Vector3(-8.0, 0, 11.0),
]
## 空投补货的区域（地图上的空地）
const DROP_ZONES := [
	Rect2(-9, 8, 18, 8), Rect2(-21, -1, 13, 5), Rect2(-8, -14.5, 15, 8),
	Rect2(7.5, -14.5, 15, 30), Rect2(-20.5, -12, 9.5, 9),
]


func _place_breakables() -> void:
	for m in HarborBuilder.MAZE:
		var sz := Vector2(6.4, 2.8) if not m[2] else Vector2(2.8, 6.4)
		# 外扩 0.9 米：集装箱之间的通道不放箱子，免得空投把路堵死
		_occupied.append(Rect2(Vector2(m[0], m[1]) - sz * 0.5, sz).grow(0.9))
	_occupied.append(Rect2(-6.4, -5.4, 12.8, 10.8))
	_occupied.append(Rect2(-2.6, 4.6, 5.2, 2.0))
	_occupied.append(Rect2(-1.5, 7.5, 3.0, 2.5))
	for k in 3:
		_occupied.append(Rect2(-18.9, 6.9 + k * 3.4, 7.8, 1.3))
	_occupied.append(Rect2(-6.8, -14.9, 7.6, 3.2))
	_occupied.append(Rect2(-9.4, -11.8, 1.8, 2.6))
	for bp in BOAT_SPOTS:
		_occupied.append(Rect2(bp.x - 2.5, bp.z - 1.5, 5.0, 3.5))
	for p in LOOT_CONTAINERS:
		var ev: bool = EVIDENCE.has(p)
		var c: Color = Pal.RED if ev else HarborBuilder.CONTAINER_COLORS[_rng.randi() % HarborBuilder.CONTAINER_COLORS.size()]
		var b := _add_breakable("container", p, c, not ev)   # 证物集装箱一定要放上
		if ev and b:
			b.set_meta("evidence", true)
			b.hp = 40.0   # 证物集装箱特别结实：头顶有血条，打起来像个小 boss
			_evidence.append(b)
	for reg in REGIONS:
		var r: Rect2 = reg[0]
		var n: int = reg[1]
		var kinds: Array = reg[2]
		var placed := 0
		var tries := 0
		while placed < n and tries < n * 40:
			tries += 1
			var k: String = kinds[_rng.randi() % kinds.size()]
			var p := Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y, r.end.y))
			if _add_breakable(k, p, Color.WHITE):
				placed += 1
				if k == "box" and _rng.randf() < 0.5:
					var p2 := p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 0.95
					_add_breakable("box", p2, Color.WHITE)


func _add_breakable(k: String, p: Vector3, c: Color, check := true) -> Breakable:
	var sz: Vector3 = Breakable.KINDS[k].size
	var rect := Rect2(p.x - sz.x * 0.5 - 0.35, p.z - sz.z * 0.5 - 0.35, sz.x + 0.7, sz.z + 0.7)
	if check:
		for o in _occupied:
			if o.intersects(rect):
				return null
	var b := Breakable.new().setup(k, c)
	b.level = self
	b.position = p
	if k != "container" and k != "gold":
		b.rotation.y = _rng.randf_range(-0.5, 0.5)
	b.set_meta("rect", rect)
	add_child(b)
	breakables.append(b)
	_occupied.append(rect)
	return b


# ------------------------------------------------------------------ 仓库里的罐头山（本局吸了多少罐，就堆多高）

func _build_stack() -> void:
	var step := 0.25
	var layer := 0
	var w := 12
	var d := 8
	while w > 0 and _stack_slots.size() < 900:
		for i in w:
			for j in d:
				_stack_slots.append(Transform3D(Basis.IDENTITY, HarborBuilder.STACK_POS + Vector3((i - (w - 1) * 0.5) * step, 0.1 + layer * 0.205, (j - (d - 1) * 0.5) * step)))
		layer += 1
		w -= 1
		d = maxi(1, d - 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Loot._res("can")[0]["can"]
	mm.instance_count = _stack_slots.size()
	for i in _stack_slots.size():
		mm.set_instance_transform(i, _stack_slots[i])
	mm.visible_instance_count = 0
	_stack = MultiMeshInstance3D.new()
	_stack.multimesh = mm
	_stack.material_override = Loot._res("can")[1]["can"]
	add_child(_stack)
	_stack_label = Label3D.new()
	_stack_label.font = Style.title_font()
	_stack_label.font_size = 80
	_stack_label.pixel_size = 0.007
	_stack_label.outline_size = 18
	_stack_label.outline_modulate = Pal.INK
	_stack_label.modulate = Pal.YELLOW
	_stack_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stack_label.no_depth_test = true
	_stack_label.render_priority = 12
	_stack_label.outline_render_priority = 11
	_stack_label.position = HarborBuilder.STACK_POS + Vector3(0, 3.4, 0)
	add_child(_stack_label)
	_update_stack()


func _update_stack() -> void:
	_stack.multimesh.visible_instance_count = mini(cans / 2, _stack_slots.size())
	_stack_label.text = "罐头山 %d" % cans


# ------------------------------------------------------------------ 玩家

func _spawn_player() -> void:
	player = Player.new()
	player.level = self
	player.facing = Vector3(0, 0, -1)
	player.position = START_POS
	player.infinite_ammo = false   # 步枪 30 发弹匣，打完要换弹（R 手动换弹，卡准时机 = 完美换弹）
	add_child(player)
	player.grenades = 1
	player.regen_mult = float(hdiff().regen)
	heal_drop_limit = 999   # 第二章的回血由补给计时器控制（见 _tick_supply）
	# 头顶穿透显示的小三角：被集装箱挡住时也知道自己在哪
	_marker = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.36, 0.3, 0.06)
	_marker.mesh = pm
	var mm := Toon.glow(Pal.ORANGE, 1.6).duplicate() as StandardMaterial3D
	mm.no_depth_test = true
	mm.render_priority = 20
	_marker.material_override = mm
	_marker.rotation_degrees = Vector3(180, 0, 0)
	add_child(_marker)


func zone_active(_zone: String) -> bool:
	return true


func interactables() -> Array:
	return []


func _set_phase(p: int) -> void:
	phase = p


# ------------------------------------------------------------------ 每帧

func _process(delta: float) -> void:
	_light_t += delta
	cam.look_at_point = player.aim_point
	cam.aiming = player.aiming and not player.dead
	var pp := player.get_global_transform_interpolated().origin if get_tree().physics_interpolation else player.global_position
	_marker.global_position = pp + Vector3(0, (2.25 if not player.giant else 5.0) + sin(_light_t * 5.0) * 0.08, 0)
	_marker.visible = not player.dead
	var now_us := Time.get_ticks_usec()
	if _run_last > 0 and stage == "play":
		run_ms += minf((now_us - _run_last) / 1000.0, 100.0)
	_run_last = now_us
	if stage != "play":
		return
	t += delta
	Game.run.time = t
	Game.run.run_ms = int(run_ms)
	_tick_mission(delta)
	_tick_supply(delta)
	_tick_spitters(delta)
	_tick_lunges(delta)
	_tick_elites(delta)
	_tick_multikill(delta)
	_tick_spawns(delta)
	_tick_drops(delta)
	_tick_rampage(delta)
	_tick_upgrades(delta)


## 僵尸鼠：跟着主线越来越多；最后坚守阶段一波接一波
func _tick_spawns(delta: float) -> void:
	var k := maxf(HEAT[step], clampf(t / 360.0, 0.0, 1.0) * 0.9)
	var zf := ramp("zombie")
	var interval := lerpf(1.6, 0.16, k) / zf
	var cap := int(lerpf(4.0, 60.0, k) * zf) + (_surge_n * 8 if _final_tide else 0)
	_spawn_acc += delta
	while _spawn_acc >= interval:
		_spawn_acc -= interval
		if zombies.size() < cap:
			_spawn_zombie_ring(false)
	# 坚守阶段：每 15 秒涌上来一波
	if _final_tide:
		_surge_t -= delta
		if _surge_t <= 0.0:
			_surge_t = 15.0
			_surge_n += 1
			hhud.big_banner("涨 潮 ×%d" % _surge_n, Color("7CFFB2"), 96)
			Sfx.play("alarm", -6.0, 0.7, 0.0)
			for i in int((12 + _surge_n * 6) * ramp("zombie")):
				if zombies.size() < 110:
					_spawn_zombie_ring(false)


## 在玩家周围 13–17 米的一圈找一个能走到的点刷怪（看不见的地方刷，不会凭空出现在脸上）
func _spawn_zombie_ring(is_boss: bool, at := Vector3.INF) -> Zombie:
	var map := get_world_3d().navigation_map
	for _try in 8:
		var a := randf() * TAU
		var want := player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(13.0, 17.0)
		if at != Vector3.INF:
			want = at + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 1.5)
		want.x = clampf(want.x, -HarborBuilder.HALF_X + 1.0, HarborBuilder.HALF_X - 1.0)
		want.z = clampf(want.z, HarborBuilder.DOCK_EDGE_Z + 1.0, HarborBuilder.GATE_Z - 1.0)
		var p := NavigationServer3D.map_get_closest_point(map, want)
		p.y = 0.0
		if at == Vector3.INF and (p.distance_to(player.global_position) < 9.0 or Vector2(p.x - want.x, p.z - want.z).length() > 2.0):
			continue
		var z := Zombie.new()
		z.boss = is_boss
		z.level = self
		z.position = p
		add_child(z)
		# 主线越往后鼠越硬、越疼；磨蹭超过 5 分钟就开始指数变强（一局别拖太久）
		var dsp := Game.dv("zombie_speed")
		if dsp > 1.3:
			z.speed *= 1.3 / dsp   # 高难度的僵尸鼠别比猫还快
		var dhp := Game.dv("boss_hp" if is_boss else "zombie_hp")
		if dhp > 1.8:
			z.max_hp *= 1.8 / dhp
		var over := maxf(0.0, t - 300.0) / 30.0
		if not is_boss:
			z.max_hp *= (1.0 + step * 0.2) * pow(1.6, over)
		if not is_boss:
			z.max_hp *= 1.0 + level_n * 0.1   # 你升级，它们也跟着变硬
		z.speed *= (1.0 + minf(step * 0.04 + over * 0.05, 0.8)) * float(hdiff().speed)
		z.dmg_mult = (1.0 + step * 0.12) * ramp("bite") + over * over / clampf(Game.dv("dmg"), 0.4, 1.0)
		if not is_boss:
			_roll_variant(z)
		z.hp = z.max_hp
		zombies.append(z)
		return z
	return null


# ------------------------------------------------------------------ 僵尸鼠变种

static var _var_mats := {}


static func _vmat(k: String) -> Material:
	if _var_mats.is_empty():
		_var_mats["runner"] = Toon.glow(Color(1.0, 0.25, 0.25), 2.2)
		_var_mats["tank"] = Toon.mat(Pal.ORANGE, true, Pal.OUTLINE_ENEMY, 0.03)
		_var_mats["spit"] = Toon.glow(Color(0.55, 1.0, 0.3), 2.0)
	return _var_mats[k]


## 冲刺鼠（红头带，快、脆）/ 胖胖鼠（大一圈 + 罐头头盔，肉、咬得狠）/ 酸液鼠（背上绿色酸囊，远处吐酸）
func _roll_variant(z: Zombie) -> void:
	if step == 0:
		return
	var r := randf()
	var vf := ramp("variant")
	var p_run := (0.1 + step * 0.03) * vf
	var p_tank := (0.04 + step * 0.015) * vf
	var p_spit := (0.05 + step * 0.02) * vf if spitters.size() < int(4 + 3 * vf) else 0.0
	var head: Node3D = z.model.head if z.model.head else z.model
	if r < p_run:
		z.set_meta("variant", "runner")
		z.speed *= 1.6
		z.max_hp *= 0.6
		var band := MeshInstance3D.new()
		band.mesh = Models.box(Vector3(0.62, 0.1, 0.62))
		band.material_override = _vmat("runner")
		band.position = Vector3(0, 0.12, 0)
		head.add_child(band)
	elif r < p_run + p_tank:
		z.set_meta("variant", "tank")
		z.speed *= 0.65
		z.max_hp *= 6.0
		z.dmg_mult *= 2.2
		z.model.scale *= 1.5
		var helm := MeshInstance3D.new()
		helm.mesh = Models.cyl(0.36, 0.36, 0.3)
		helm.material_override = _vmat("tank")
		helm.position = Vector3(0, 0.3, 0)
		head.add_child(helm)
	elif r < p_run + p_tank + p_spit:
		z.set_meta("variant", "spit")
		z.set_meta("spit_cd", randf_range(1.5, 3.0))
		z.max_hp *= 1.2
		var sac := MeshInstance3D.new()
		sac.mesh = Models.sphere(0.3)
		sac.material_override = _vmat("spit")
		sac.position = Vector3(0, 0.7, -0.3)
		z.model.body.add_child(sac)
		spitters.append(z)


## 酸液鼠：离你 4–11 米时停下来吐一口酸（落点先亮绿圈），太近会往后退
func _tick_spitters(delta: float) -> void:
	var pp := player.global_position
	for zz in spitters.duplicate():
		if not is_instance_valid(zz) or (zz as Zombie).dead:
			spitters.erase(zz)
			continue
		var z: Zombie = zz
		var cd: float = float(z.get_meta("spit_cd", 0.0)) - delta
		z.set_meta("spit_cd", cd)
		var d := z.global_position.distance_to(pp)
		if cd <= 0.0 and d > 3.5 and d < 11.0 and z.skill_lock <= 0.0 and not player.dead:
			z.set_meta("spit_cd", randf_range(3.0, 4.2))
			z.skill_lock = 0.7
			z.skill_vel = Vector3.ZERO
			z.model.squash(0.3)
			var lead := player.velocity * 0.4
			lead.y = 0
			Lob.shot(self, z.global_position + Vector3(0, 1.2, 0), pp + lead, 0.15, 1.5, 7.0 * z.dmg_mult, Color(0.55, 1.0, 0.3), 0.9)
		elif d < 4.0 and cd > 1.0 and z.skill_lock <= 0.0:
			var away := z.global_position - pp
			away.y = 0
			z.skill_lock = 0.3
			z.skill_vel = away.normalized() * z.speed * 0.8


## 龙门吊不停往场上空投新箱子（地上的箱子少于 45 个时）
func _tick_drops(delta: float) -> void:
	_drop_acc += delta
	if _drop_acc < 4.0:
		return
	_drop_acc = 0.0
	if breakables.size() >= 45:
		return
	var zone: Rect2 = DROP_ZONES[randi() % DROP_ZONES.size()]
	var big := randf() < 0.25
	for _try in 12:
		var p := Vector3(randf_range(zone.position.x, zone.end.x), 0, randf_range(zone.position.y, zone.end.y))
		if p.distance_to(player.global_position) < 3.0:
			continue
		var kind: String = "container" if big else (["box", "wood", "barrel", "barrel", "box", "fish"][randi() % 6])
		var c: Color = HarborBuilder.CONTAINER_COLORS[randi() % HarborBuilder.CONTAINER_COLORS.size()]
		var b := _add_breakable(kind, p, c)
		if b == null:
			continue
		# 从天上掉下来
		b.position.y = 12.0
		var tw := b.create_tween()
		tw.tween_property(b, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			Fx.dust(self, p, 10 if big else 5, Color(1.0, 0.95, 0.85, 0.8), 2.5, 0.35)
			Sfx.play("stamp", -6.0 if big else -12.0, 0.7 if big else 1.2, 0.0)
			if big:
				Game.shake(0.3)
		)
		if not big:
			# 小箱子一次掉一小堆
			for i in 2:
				var q := p + Vector3(randf_range(-1.4, 1.4), 0, randf_range(-1.4, 1.4))
				var b2 := _add_breakable("box", q, c)
				if b2:
					b2.position.y = 12.0 + i
					b2.create_tween().tween_property(b2, "position:y", 0.0, 0.8 + i * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return


# ------------------------------------------------------------------ 罐头：吸收 / 升级 / 狂暴

func magnet_radius() -> float:
	return Loot.MAGNET_R * (1.0 + 0.6 * int(ups.get("magnet", 0))) * (1.6 if player.giant else 1.0)


func can_take(_kind: String) -> bool:
	return stage == "play"


func burst_loot(pos: Vector3, n_cans: int, parts: int, fish: int, big := false) -> void:
	var list: Array[String] = []
	for i in n_cans + parts:
		list.append("can")
	for i in fish:
		list.append("fish")
	for i in list.size():
		if loose_loot >= MAX_LOOSE_LOOT:
			collect(list[i], pos)
			continue
		var l := Loot.new()
		l.level = self
		l.kind = list[i]
		var a := randf() * TAU
		if big:
			var spread := randf_range(-0.9, 0.9)
			l.vel = Vector3(sin(spread) * randf_range(2.0, 5.0), randf_range(5.0, 9.0), cos(spread) * randf_range(3.0, 7.0))
		else:
			l.vel = Vector3(cos(a) * randf_range(1.0, 3.2), randf_range(4.0, 7.0), sin(a) * randf_range(1.0, 3.2))
		add_child(l)
		l.global_position = pos + Vector3(0, 0.2, 0)
		loose_loot += 1
		l.tree_exited.connect(func(): loose_loot -= 1)


func xp_need() -> int:
	return 10 + level_n * 6


var _chain := 0
var _chain_t := 0.0


func collect(kind: String, _pos: Vector3) -> void:
	if stage != "play":
		return
	if kind == "fish":
		player.hp = minf(player.max_hp, player.hp + 15.0)
		Fx.popup(self, player.global_position + Vector3(0, 2.0, 0), "+15", Pal.GREEN, 56)
		Sfx.play("perfect", -8.0, 1.3, 0.0)
		return
	cans += 1
	_chain = _chain + 1 if _chain_t > 0.0 else 1
	_chain_t = 0.7
	Sfx.play("pickup", -12.0, 1.0 + minf(_chain, 30) * 0.035, 0.0)
	if cans % 2 == 0:
		_update_stack()
	if not player.giant:
		fever += 1
		if fever >= RAMPAGE_NEED:
			_start_rampage()
	xp += 1
	if xp >= xp_need():
		xp -= xp_need()
		level_n += 1
		_upgrade_q += 1
	hhud.on_collect(_chain)


## 升级不打断战斗：罐头条满了就自动抽一个强化，头顶 + 屏幕上报一下
func _tick_upgrades(delta: float) -> void:
	_chain_t -= delta
	if _upgrade_q > 0 and not player.dead:
		_upgrade_q -= 1
		var id := _roll_upgrade()
		if id != "":
			Sfx.play("powerup", -4.0, 1.0, 0.0)
			Fx.ring(self, player.global_position, Pal.YELLOW, 3.5, 0.5)
			apply_upgrade(id)
			hhud.upgrade_banner(id, int(ups[id]))
			if level_n == 2:
				tip("levelup")
	_tick_orbit(delta)
	_tick_auto_nade(delta)
	_tick_cat(delta)


## 随机抽一个还没满级的强化（夜影是剧情给的，给过之后才会抽到她的升级）
func _roll_upgrade() -> String:
	var pool: Array = []
	for id in UPGRADES:
		if id == "cat" and not ups.has("cat"):
			continue
		if int(ups.get(id, 0)) < int(UPGRADES[id].max):
			pool.append(id)
			# 先把手感最明显的几个（连发 / 散射 / 重拳）抽出来
			if id in ["rapid", "spread", "power"] and int(ups.get(id, 0)) == 0:
				pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


## 选好升级后生效
func apply_upgrade(id: String) -> void:
	ups[id] = int(ups.get(id, 0)) + 1
	var lv := int(ups[id])
	var m := player.mods
	match id:
		"mag":
			player.mag_size = Player.MAG + 12 * lv
			player.ammo = player.mag_size
			player.reloading = false
		"rapid":
			m.fire = pow(0.8, lv)
		"spread":
			m.multi = lv
		"boom":
			m.explode = 1.2 + 0.3 * lv
		"pierce":
			m.pierce = lv
		"power":
			m.dmg = 1.0 + 0.35 * lv
		"speed":
			m.speed = 1.0 + 0.12 * lv
		"vital":
			player.max_hp += 25.0
			player.hp = player.max_hp
		"orbit":
			_add_orbiter()
		"cat":
			_show_cat()
	Fx.popup(self, player.global_position + Vector3(0, 2.4, 0), "%s Lv%d" % [UPGRADES[id].name, lv], Pal.YELLOW, 56, true, 1.0, 0.9)
	player.model.flash(Pal.YELLOW, 0.8)


# ------------------------------------------------------------------ 罐头狂暴：巨型罐头机甲

func _start_rampage() -> void:
	fever = 0
	rampages += 1
	rampage_t = RAMPAGE_TIME
	player.giant = true
	player.infinite_ammo = true    # 机甲形态不用换弹
	player.reloading = false
	player.ammo = player.mag_size
	_stomp_t = 0.0
	var tw := player.model.create_tween()
	tw.tween_property(player.model, "scale", Vector3.ONE * 2.6, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	player.model.flash(Pal.ORANGE, 1.0)
	hud.fire_shout()
	hud.flash(0.4)
	Game.shake(0.35)
	Game.bullet_time(0.6)
	Sfx.play("transform", 0.0, 1.0, 0.0)
	Sfx.play("shout_fire", 0.0, 1.0, 0.0)
	Sfx.music("wave")
	Fx.ring(self, player.global_position, Pal.ORANGE, 8.0, 0.5)
	hhud.rampage_banner()
	if rampages == 1:
		tip("rampage")


func _tick_rampage(delta: float) -> void:
	if rampage_t <= 0.0:
		return
	rampage_t -= delta
	_stomp_t -= delta
	if _stomp_t <= 0.0:
		_stomp_t = 0.45
		# 每一步都是一次小地震：炸飞周围的僵尸鼠，踩碎箱子
		var p := player.global_position
		explode(p, 4.2, 6.0 * float(player.mods.dmg), player, true)   # 安静版：不震屏
		Fx.dust(self, p, 8, Color(1.0, 0.9, 0.7, 0.7), 3.5, 0.35)
		Sfx.play("bonk", -14.0, 0.6, 0.1)
	if rampage_t <= 0.0:
		_end_rampage()


func _end_rampage() -> void:
	rampage_t = 0.0
	player.giant = false
	player.infinite_ammo = false
	var tw := player.model.create_tween()
	tw.tween_property(player.model, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	# 收尾：一记大冲击波
	explode(player.global_position, 7.5, 12.0 * float(player.mods.dmg), player, true)
	Fx.ring(self, player.global_position, Pal.YELLOW, 12.0, 0.6)
	hud.flash(0.3)
	Game.shake(0.4)
	Sfx.play("breach", 0.0, 0.7, 0.0)
	Sfx.music("combat")


# ------------------------------------------------------------------ 升级的持续效果

func _add_orbiter() -> void:
	var o := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Loot._res("can")[0]["can"]
	mi.material_override = Toon.glow(Pal.YELLOW, 1.4)
	mi.scale = Vector3.ONE * 2.2
	o.add_child(mi)
	add_child(o)
	_orbiters.append(o)


func _tick_orbit(delta: float) -> void:
	if _orbiters.is_empty():
		return
	_orbit_a += delta * 3.2
	var pp := player.global_position
	var r := 2.0 * (2.0 if player.giant else 1.0)
	for i in _orbiters.size():
		var a := _orbit_a + TAU * i / _orbiters.size()
		var o := _orbiters[i]
		o.global_position = pp + Vector3(cos(a) * r, 0.8, sin(a) * r)
		o.rotation.y += delta * 8.0
	# 撞到的敌人掉血（同一个敌人 0.4 秒内只算一次）
	var now := Time.get_ticks_msec()
	for z in zombies:
		if z.dead:
			continue
		for o in _orbiters:
			var dz := Vector2(z.global_position.x - o.global_position.x, z.global_position.z - o.global_position.z).length()
			if dz < (0.7 if not z.boss else 1.6):
				var id := z.get_instance_id()
				if now - int(_orbit_hit.get(id, 0)) > 400:
					_orbit_hit[id] = now
					var dir := z.global_position - pp
					dir.y = 0
					z.take_hit(2.0 * float(player.mods.dmg), dir.normalized() * 2.0, o.global_position, player)
					Fx.spark(self, o.global_position, Vector3.UP, Pal.YELLOW, 5, 4.0)
				break
	for b in breakables.duplicate():
		if b.broken:
			continue
		for o in _orbiters:
			if Vector2(b.global_position.x - o.global_position.x, b.global_position.z - o.global_position.z).length() < 0.8:
				b.take_hit(2.0, (b.global_position - pp).normalized(), o.global_position, player)
				break


func _tick_auto_nade(delta: float) -> void:
	var lv := int(ups.get("nade", 0))
	if lv <= 0 or zombies.is_empty():
		return
	_nade_t -= delta
	if _nade_t > 0.0:
		return
	_nade_t = 5.5 - lv * 1.0
	# 找周围僵尸最多的位置
	var best: Vector3 = Vector3.INF
	var best_n := 0
	for z in zombies:
		if z.dead or z.global_position.distance_to(player.global_position) > 9.0:
			continue
		var n := 0
		for z2 in zombies:
			if not z2.dead and z2.global_position.distance_to(z.global_position) < 3.5:
				n += 1
		if n > best_n:
			best_n = n
			best = z.global_position
	if best == Vector3.INF:
		return
	var g := Grenade.new()
	g.level = self
	g.from = player.model.muzzle.global_position
	g.to = best
	add_child(g)


## 夜影：龙门吊顶上一个黑猫剪影 + 狙击光束
func _show_cat() -> void:
	if _cat_node:
		return
	_cat_node = Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = Models.sphere(0.45)
	body.material_override = Toon.mat(Color("2E2E38"), true, Color("C59BFF"), 0.03)
	_cat_node.add_child(body)
	for sx in [-0.22, 0.22]:
		var ear := MeshInstance3D.new()
		ear.mesh = Models.prism(Vector3(0.2, 0.26, 0.1))
		ear.material_override = body.material_override
		ear.position = Vector3(sx, 0.48, 0)
		_cat_node.add_child(ear)
	var eye := MeshInstance3D.new()
	eye.mesh = Models.box(Vector3(0.36, 0.08, 0.05))
	eye.material_override = Toon.glow(Color("FFE066"), 2.0)
	eye.position = Vector3(0, 0.08, 0.42)
	_cat_node.add_child(eye)
	add_child(_cat_node)
	_cat_node.global_position = hb.crane_top + Vector3(0, 1.2, 0.6)
	hud.radio.say("cat_black", "我在吊车上。你负责跑，我负责……[color=#C59BFF]一枪一个[/color]。", 0.0, true)


func _tick_cat(delta: float) -> void:
	var lv := int(ups.get("cat", 0))
	if lv <= 0:
		return
	_cat_t -= delta
	if _cat_t > 0.0:
		return
	_cat_t = 1.3 - lv * 0.22
	# 打离豆包最近的敌人（鼠王优先）
	var best: Zombie = null
	var bd := 1e9
	for z in zombies:
		if z.dead:
			continue
		var d := z.global_position.distance_to(player.global_position) - (6.0 if z.boss else 0.0)
		if d < bd and d < 16.0:
			bd = d
			best = z
	if best == null:
		return
	var from := _cat_node.global_position + Vector3(0, 0.2, 0.4)
	var to := best.global_position + Vector3(0, 0.6, 0)
	var dir := to - from
	dir.y = 0
	best.take_hit(4.0 + lv * 2.0, dir.normalized() * 3.0, from, player)
	# 光束
	var beam := MeshInstance3D.new()
	beam.mesh = Models.box(Vector3(1, 1, 1))
	beam.material_override = Toon.glow(Color(0.8, 0.6, 1.0, 0.9), 2.6)
	add_child(beam)
	beam.global_position = (from + to) * 0.5
	beam.look_at(to, Vector3.UP)
	beam.scale = Vector3(0.12, 0.12, from.distance_to(to))
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale:x", 0.01, 0.15)
	tw.parallel().tween_property(beam, "scale:y", 0.01, 0.15)
	tw.tween_callback(beam.queue_free)
	Fx.spark(self, to, Vector3.UP, Color(0.8, 0.6, 1.0), 8, 5.0)
	Sfx.play("laser", -10.0, 1.6, 0.05)


# ------------------------------------------------------------------ 主线任务

func _start_step(i: int) -> void:
	if Game.autotest:
		print("[harbor] STEP %d at %.1f lv=%d" % [i + 1, t, level_n])
	step = i
	step_n = 0
	_step_t = 0.0
	marks.clear()
	match i:
		0:
			step_need = 5
			_mark_nearest_crates(5)
			hud.radio.say("chief", "先热热身：[color=#FFC93C]箭头指着的货箱[/color]，开枪就能打碎，里面全是罐头！", 0.0, true)
		1:
			step_need = maxi(1, _evidence.size())
			step_n = evidence_found
			for b in _evidence:
				if is_instance_valid(b) and not b.broken:
					marks.append(b)
			hud.radio.say("cat_black", "我是[color=#C59BFF]夜影[/color]，在码头卧底三天了。老K 的账本藏在 3 个[color=#FF5A5A]红色集装箱[/color]里，我给你标出来了。", 0.0, true)
			hud.radio.say("shiba", "收到！集装箱结实，多打几枪！", 0.0)
		2:
			step_need = 5
			_drop_oil_barrels()
			hud.radio.say("chief", "第三本账本写着：实验罐头藏在[color=#FF5A5A]油罐区的红油桶[/color]里。一桶都别留——它们会连锁爆炸！", 0.0, true)
			hud.radio.say("boss_k", "谁在翻我的账本？！吊车，把油桶都给我吊下来！", 0.0)
			_grant_cat()
		3:
			var n: int = hdiff().bosses
			step_need = n
			_bosses.clear()
			for k in n:
				var bz := _spawn_zombie_ring(true, BOSS_POS + Vector3(k * 3.0, 0, 0))
				if bz:
					# 罐头蟹血量跟着你的等级涨：升得越多它越肉，保证是一场像样的 boss 战
					bz.max_hp *= (3.6 + level_n * 0.5) * float(hdiff().boss_hp) / sqrt(float(n))
					bz.set_meta("mech", true)
					bz.hp = bz.max_hp
					_bosses.append(bz)
					var rk := RatKing.new()
					rk.level = self
					rk.z = bz
					add_child(rk)
					kings.append(rk)
					marks.append(bz)
			if not _bosses.is_empty():
				cam.focus(_bosses[0].global_position, 1.4)
			hhud.big_banner("老K · 罐头蟹", Pal.RED, 120)
			Sfx.play("alarm", -4.0, 0.8, 0.0)
			if _k_deck:
				_k_deck.visible = false   # 老K 跳进了机甲
			hud.radio.say("boss_k", "敢炸我的货？小子，见识一下我的[color=#FF5A5A]罐头蟹[/color]！", 0.0, true)
			hud.radio.say("cat_black", "它会冲撞、跺地、开炮！[color=#FF5A5A]地上一红就翻滚[/color]！", 0.0)
		4:
			step_need = int(HOLD_TIME)
			_hold_t = HOLD_TIME
			_final_tide = true
			_surge_t = 0.5
			hhud.big_banner("坚 守 5 0 秒", Color("7CFFB2"), 110)
			hud.radio.say("chief", "老K 把船上的僵尸鼠全放出来了！撤离艇 [color=#7CFFB2]50 秒[/color]后到——顶住！", 0.0)
		5:
			step_need = 1
			_final_tide = false   # 涨潮停了：给一条跑向撤离艇的路
			_spawn_evac()
			marks.append(_evac)
			hud.radio.say("chief", "撤离艇到了！[color=#7CFFB2]跑过去上船！[/color]", 0.0, true)
	if not marks.is_empty():
		marks[0].set_meta("mark", STEPS[i].mark)
	_refresh_objective()


func _refresh_objective() -> void:
	var prog := "%d / %d" % [step_n, step_need]
	if step == 4:
		prog = "%d 秒" % ceili(_hold_t)
	elif step == 5:
		prog = ""
	hud.set_objective("%d/%d · %s" % [step + 1, STEPS.size(), STEPS[step].title], prog)
	# 屏幕边缘的橙色箭头：指向最近的一个目标
	var best: Node3D = null
	var bd := 1e9
	for m in marks:
		if not is_instance_valid(m) or (m is Breakable and m.broken) or (m is Zombie and m.dead):
			continue
		var d := m.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = m
	if best:
		best.set_meta("mark", STEPS[step].mark)
		var h := 2.2
		if best is Breakable:
			h = (best as Breakable).size().y + 1.5
		elif best is Zombie:
			h = 3.6
		best.set_meta("mark_h", h)
	hud.set_target(best)


func guide_target() -> Vector3:
	if stage != "play":
		return Vector3.INF
	var tgt: Node3D = hud._markers.target if hud else null
	if tgt == null or not is_instance_valid(tgt):
		return Vector3.INF
	# 箭头铺到目标跟前就够了（打碎类目标不用走到脸上）
	if step <= 3 and tgt.global_position.distance_to(player.global_position) < 8.0:
		return Vector3.INF
	return tgt.global_position


func _tick_mission(delta: float) -> void:
	_step_t += delta
	if Game.autotest and int(t) % 20 == 0 and int(t - delta) % 20 != 0:
		var tg: Node3D = hud._markers.target
		print("[harbor] t=%d pos=%s step=%d %d/%d marks=%d target=%s dist=%.1f zombies=%d" % [int(t), str(player.global_position.snapped(Vector3.ONE * 0.1)), step + 1, step_n, step_need, marks.size(), str(tg.global_position) if tg else "-", tg.global_position.distance_to(player.global_position) if tg else -1.0, zombies.size()])
	# 清掉已经不存在的标记
	marks = marks.filter(func(m): return is_instance_valid(m) and not (m is Breakable and m.broken) and not (m is Zombie and m.dead))
	match step:
		0:
			if marks.is_empty() and step_n < step_need:
				_mark_nearest_crates(step_need - step_n)
		4:
			_hold_t -= delta
			step_n = int(HOLD_TIME - _hold_t)
			if _hold_t <= 0.0:
				_complete_step()
				return
		5:
			if _evac and Vector2(player.global_position.x - _evac.global_position.x, player.global_position.z - _evac.global_position.z).length() < 2.4:
				_win()
				return
	if step_n >= step_need and step < 4:
		_complete_step()
		return
	_refresh_objective()


func _complete_step() -> void:
	Sfx.play("perfect", -2.0, 1.0, 0.0)
	hud.score_popup("主线 %d/%d 完成" % [step + 1, STEPS.size()], 300)
	hhud.step_done(step)
	if step + 1 < STEPS.size():
		_start_step(step + 1)


## 老K：船长帽浣熊（序章浣熊打手的老大）
static func make_boss_k() -> CharModel:
	var c := Models.raccoon(true)
	var h := c.head
	var black := c.m(Color("1B1D26"))
	var gold := c.m(Pal.YELLOW, false)
	c.part(h, Models.cyl(0.4, 0.4, 0.08), black, Vector3(0, 0.27, 0.04))
	c.part(h, Models.cyl(0.33, 0.3, 0.2), black, Vector3(0, 0.38, -0.01))
	c.part(h, Models.cyl(0.335, 0.335, 0.05), gold, Vector3(0, 0.31, -0.01))
	c.part(h, Models.sphere(0.07), gold, Vector3(0, 0.38, 0.3))
	c.part(c.body, Models.torus(0.2, 0.24), gold, Vector3(0, 0.78, 0.04), Vector3(70, 0, 0))
	return c


## 开局时老K 站在大船甲板上叉腰看着你
func _place_k_on_ship() -> void:
	_k_deck = Node3D.new()
	add_child(_k_deck)
	_k_deck.global_position = Vector3(1.0, 2.6, HarborBuilder.DOCK_EDGE_Z - 4.6)
	var k := make_boss_k()
	k.scale = Vector3.ONE * 1.4
	_k_deck.add_child(k)
	var lab := Label3D.new()
	lab.text = "老K"
	lab.font = Style.title_font()
	lab.font_size = 64
	lab.pixel_size = 0.008
	lab.modulate = Color("FF6A5A")
	lab.outline_size = 14
	lab.outline_modulate = Pal.INK
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = Vector3(0, 2.5, 0)
	_k_deck.add_child(lab)
	var tw := k.create_tween().set_loops()
	tw.tween_property(k, "position:y", 0.12, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(k, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_SINE)


## 罐头蟹被打爆：零件四散，老K 从驾驶舱弹射回船上，放狠话开船
func _mech_destroyed(z: Zombie) -> void:
	var pos := z.global_position
	explode(pos, 4.0, 10.0, player, true)
	Fx.ring(self, pos, Pal.RED, 9.0, 0.6)
	Fx.dust(self, pos, 26, Color(1.0, 0.85, 0.6, 0.9), 5.0, 0.6)
	Fx.spark(self, pos + Vector3(0, 1.2, 0), Vector3.UP, Pal.ORANGE, 40, 10.0)
	Sfx.play("explosion", 0.0, 0.7, 0.0)
	Sfx.play("breach", -2.0, 0.6, 0.0)
	Game.shake(0.5)
	hud.flash(0.3)
	for i in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = Models.box(Vector3(randf_range(0.3, 0.7), randf_range(0.15, 0.4), randf_range(0.3, 0.7)))
		mi.material_override = Toon.prop_outlined(Color("D9483B") if i % 2 == 0 else Color("3A2F3F"))
		add_child(mi)
		mi.global_position = pos + Vector3(0, 1.2, 0)
		var a := randf() * TAU
		var to := pos + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 5.0) + Vector3(0, 0.15, 0)
		var tw := mi.create_tween()
		tw.tween_method(func(k: float):
			if is_instance_valid(mi):
				mi.global_position = (pos + Vector3(0, 1.2, 0)).lerp(to, k) + Vector3(0, sin(k * PI) * 3.0, 0)
				mi.rotation = Vector3(k * 8.0, k * 5.0, 0)
		, 0.0, 1.0, 0.9)
		tw.tween_interval(2.0)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(mi.queue_free)
	# 老K 弹射
	if _k_deck:
		var dest := _k_deck.global_position
		var k := make_boss_k()
		add_child(k)
		k.global_position = pos + Vector3(0, 1.5, 0)
		k.scale = Vector3.ONE * 1.4
		var kt := k.create_tween()
		kt.tween_method(func(s: float):
			if is_instance_valid(k):
				k.global_position = (pos + Vector3(0, 1.5, 0)).lerp(dest, s) + Vector3(0, sin(s * PI) * 6.0, 0)
				k.rotation.x = s * TAU * 2.0
		, 0.0, 1.0, 1.3)
		kt.tween_callback(func():
			k.queue_free()
			if is_instance_valid(_k_deck):
				_k_deck.visible = true
		)
	hud.radio.say("boss_k", "我的罐头蟹！！……你给我等着！[color=#FF5A5A]开船！[/color]", 0.0, true)
	hud.radio.say("cat_black", "让他跑。我已经在他船上放了[color=#C59BFF]追踪器[/color]。", 0.0)


## 第 1 步：给离玩家最近的几个小货箱打上标记
func _mark_nearest_crates(n: int) -> void:
	var list: Array = []
	for b in breakables:
		if b.broken or b.kind in ["container", "gold", "barrel"]:
			continue
		list.append(b)
	var pp := player.global_position
	list.sort_custom(func(a, b): return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))
	for i in mini(n, list.size()):
		marks.append(list[i])


## 第 3 步：龙门吊往油罐区空投一排新油桶（保证够炸，也让人看见「从天而降的红桶」）
func _drop_oil_barrels() -> void:
	var placed := 0
	var tries := 0
	while placed < 8 and tries < 120:
		tries += 1
		var p := Vector3(randf_range(OIL_YARD.position.x + 1.0, OIL_YARD.end.x - 1.0), 0, randf_range(OIL_YARD.position.y + 1.0, OIL_YARD.end.y - 1.0))
		var b := _add_breakable("barrel", p, Color.WHITE)
		if b == null:
			continue
		b.position.y = 10.0 + placed * 0.6
		b.create_tween().tween_property(b, "position:y", 0.0, 0.7 + placed * 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		b.set_meta("oil", true)
		marks.append(b)
		placed += 1
	step_need = mini(step_need, placed)


## 夜影：剧情加入（之后升级才可能抽到她的强化）
func _grant_cat() -> void:
	if ups.has("cat"):
		return
	ups["cat"] = 1
	_show_cat()
	hhud.upgrade_banner("cat", 1)


## 撤离艇：从西边开进来，停在码头边；码头上亮一个绿圈
func _spawn_evac() -> void:
	_evac = Node3D.new()
	add_child(_evac)
	var bpos: Vector3 = BOAT_SPOTS[0]
	for bp in BOAT_SPOTS:
		if bp.distance_to(player.global_position) < bpos.distance_to(player.global_position):
			bpos = bp
	_evac.global_position = bpos
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.9
	tm.outer_radius = 2.2
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = Toon.glow(Color("7CFFB2"), 2.2)
	ring.position.y = 0.05
	ring.scale = Vector3(1, 0.1, 1)
	_evac.add_child(ring)
	var pillar := MeshInstance3D.new()
	pillar.mesh = Models.cyl(1.9, 1.9, 6.0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.albedo_color = Color(0.5, 1.0, 0.7, 0.16)
	pillar.material_override = pm
	pillar.position.y = 3.0
	_evac.add_child(pillar)
	# 小艇
	_boat = Node3D.new()
	add_child(_boat)
	var hull := MeshInstance3D.new()
	hull.mesh = Models.box(Vector3(5.0, 1.0, 2.2))
	hull.material_override = Toon.mat(Color("F2F2F2"), true, Pal.OUTLINE_PROP, 0.03)
	_boat.add_child(hull)
	var stripe := MeshInstance3D.new()
	stripe.mesh = Models.box(Vector3(5.05, 0.25, 2.25))
	stripe.material_override = Toon.prop(Color("2F6FD6"))
	stripe.position.y = 0.1
	_boat.add_child(stripe)
	var cabin := MeshInstance3D.new()
	cabin.mesh = Models.box(Vector3(1.8, 0.9, 1.6))
	cabin.material_override = Toon.mat(Color("2F6FD6"), true, Pal.OUTLINE_PROP, 0.03)
	cabin.position = Vector3(-0.6, 0.95, 0)
	_boat.add_child(cabin)
	var siren := MeshInstance3D.new()
	siren.mesh = Models.box(Vector3(0.5, 0.2, 0.3))
	siren.material_override = Toon.glow(Pal.RED, 3.0)
	siren.position = Vector3(-0.6, 1.5, 0)
	_boat.add_child(siren)
	_boat.global_position = Vector3(-45.0, -0.3, HarborBuilder.DOCK_EDGE_Z - 2.0)
	if bpos.x > -10.0:
		# 大船那边：小艇从大船后面绕出来（从东边开过来，停在船头前）
		_boat.global_position = Vector3(45.0, -0.3, HarborBuilder.DOCK_EDGE_Z - 2.0)
	var tw := _boat.create_tween()
	tw.tween_property(_boat, "global_position:x", bpos.x, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sfx.play("alarm", -8.0, 1.3, 0.0)


func _win() -> void:
	if stage != "play":
		return
	won = true
	stage = "over"
	finished = true
	rampage_t = 0.0
	player.giant = false
	hud.set_target(null)
	hud.set_objective("任务完成！", "")
	Sfx.music("")
	Sfx.play("perfect", 0.0, 0.9, 0.0)
	Game.bullet_time(0.8)
	hhud.big_banner("任 务 完 成", Pal.YELLOW, 130)
	hud.radio.clear()
	hud.radio.say("chief", "豆包，干得漂亮！账本、实验罐头都拿下了！", 0.0, true)
	hud.radio.say("cat_black", "老K 的船往东边跑了……我在他船上放了追踪器。[color=#C59BFF]下一站，见。[/color]", 0.0)
	for z in zombies.duplicate():
		if is_instance_valid(z) and not z.dead:
			z.take_hit(99999.0, Vector3.ZERO, z.global_position, null)
	# 豆包跳上船
	var tw := player.create_tween()
	tw.tween_property(player, "global_position", _boat.global_position + Vector3(0.8, 0.8, 0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	player.set_physics_process(false)
	Game.run["score"] = total_score()
	await get_tree().create_timer(2.6, true, false, true).timeout
	hud.visible = false
	hhud.show_summary()


# ------------------------------------------------------------------ 打碎 / 爆炸 / 击杀

## 补给：手雷 / 回血按难度定时「准备好」，准备好之后打碎的下一个箱子就会掉出来
##（不会满地都是，也不会一整局都见不到）
func _tick_supply(delta: float) -> void:
	_grenade_t += delta
	if player.hp < player.max_hp * 0.75:
		_heal_t += delta
	else:
		_heal_t += delta * 0.3


func _supply_drop(b: Breakable) -> void:
	if b.kind == "barrel" or player.dead:
		return
	var pos := b.global_position
	if _heal_t >= float(hdiff().heal_every) and player.hp < player.max_hp * 0.85:
		if spawn_pickup(pos, "heal", "", 1.0, pos):
			_heal_t = 0.0
			return
	if _grenade_t >= float(hdiff().grenade_every) and player.grenades < Player.MAX_GRENADES:
		_grenade_drops = 0   # 第二章不用序章的「整局最多 2 个」上限，靠计时器控制
		if spawn_pickup(pos, "grenade", "", 1.0, pos):
			_grenade_t = 0.0


func on_smashed(b: Breakable) -> void:
	smashed += 1
	_supply_drop(b)
	breakables.erase(b)
	if b.has_meta("evidence"):
		evidence_found += 1
		Fx.popup(self, b.global_position + Vector3(0, 3.6, 0), "证物 %d/3" % evidence_found, Pal.RED, 90, true, 1.4, 1.2)
		if step == 1:
			step_n = evidence_found
			if step_n < 3:
				hud.radio.say("cat_black", ["第一本账本：收货人——[color=#FF5A5A]老K[/color]。", "第二本：这批罐头要倒进……[color=#FF5A5A]毛绒市自来水厂[/color]？！还差一本！"][step_n - 1], 0.0, true)
	elif stage == "play":
		match step:
			0:
				if b.kind != "container" and b.kind != "gold":
					step_n += 1
			2:
				if b.has_meta("oil"):
					step_n += 1
	if b.has_meta("rect"):
		_occupied.erase(b.get_meta("rect"))
	hhud.on_smash()


func chain_explode(pos: Vector3, src: Node) -> void:
	explode(pos, 3.2, 5.0, src)


func explode(pos: Vector3, radius: float, dmg: float, src: Node, quiet := false) -> void:
	super.explode(pos, radius, dmg, src, quiet)
	for b in breakables.duplicate():
		if not is_instance_valid(b) or b.broken or b.position.y > 0.5:   # 还在天上掉的不算
			continue
		var d := Vector2(b.global_position.x - pos.x, b.global_position.z - pos.z).length()
		if d < radius + 0.4:
			var dir: Vector3 = b.global_position - pos
			dir.y = 0
			var delay := 0.04 + d * 0.03
			var bid: int = b.get_instance_id()
			var sid: int = src.get_instance_id() if src else 0
			get_tree().create_timer(delay, false).timeout.connect(func():
				var bb := instance_from_id(bid) as Breakable
				if bb and not bb.broken:
					bb.take_hit(maxf(dmg, 1.0) * 3.0, dir.normalized(), pos, instance_from_id(sid) if sid else null)
			)


func drop_weapon(pos: Vector3) -> void:
	_weapon_drops = 0   # 第二章不受序章「整局最多 3 把神装」的限制
	spawn_pickup(pos, "weapon", WEAPON_POOL[randi() % WEAPON_POOL.size()], 0.0, pos + Vector3(0, 0, -1.0))


func on_zombie_killed(z: Zombie) -> void:
	zombies.erase(z)
	if stage != "play":
		return
	kills += 1
	Game.run.zombies = kills
	hud.add_kill()
	spitters.erase(z)
	_mk_n += 1
	_mk_t = 0.55
	var c := z.global_position + Vector3(0, 0.5, 0)
	if z.has_meta("mech"):
		if support:
			support.add_kills(10)
		bosses_down += 1
		if step == 3:
			step_n += 1
		Game.hitstop(0.12)
		Game.bullet_time(0.9)
		Fx.ring(self, z.global_position, Pal.YELLOW, 6.0, 0.5)
		hud.score_popup("打爆罐头蟹", 500)
		_mech_destroyed(z)
		burst_loot(c, 40, 0, 3, true)
		drop_weapon(z.global_position + Vector3(0, 0, 1.5))
		spawn_pickup(z.global_position + Vector3(1.5, 0, 0), "heal", "", 1.5, z.global_position)
	elif z.boss:
		# 精英鼠王（序章那只）：掉一堆罐头 + 支援点
		elites_down += 1
		if support:
			support.add_kills(6)
		Game.hitstop(0.08)
		Fx.ring(self, z.global_position, Pal.YELLOW, 5.0, 0.4)
		hud.score_popup("击倒精英鼠王", 200)
		burst_loot(c, 18, 0, 1, true)
	else:
		if support:
			support.add_kills(1)
		_fling_corpse(z)
		if String(z.get_meta("variant", "")) == "tank":
			# 胖胖鼠：撑爆！炸飞周围的同伴，罐头喷一地
			explode(z.global_position, 3.0, 6.0, player, true)
			Fx.dust(self, z.global_position, 12, Color(0.75, 1.0, 0.8, 0.85), 3.0, 0.4)
			Sfx.play("splat", -2.0, 0.6, 0.0)
			burst_loot(c, 8, 0, 0, true)
		else:
			burst_loot(c, 1 if randf() < 0.7 else 2, 0, 0)


# ------------------------------------------------------------------ 解压反馈：打飞 / 连爆 / 换弹冲击波

static var _corpse_mesh: Mesh
static var _corpse_mat: Material


## 被打死的僵尸鼠顺着最后一枪的方向飞出去，落地再弹一下（同屏最多 28 个）
func _fling_corpse(z: Zombie) -> void:
	if _corpses >= 28:
		return
	if _corpse_mesh == null:
		_corpse_mesh = Models.capsule(0.26, 0.8)
		_corpse_mat = Toon.mat(Color("8FE3D2"), true, Pal.OUTLINE_ENEMY, 0.03)
	var dir := z.knock
	dir.y = 0
	var power := clampf(dir.length() / 2.2, 0.6, 2.4)
	if dir.length() < 0.2:
		dir = z.global_position - player.global_position
		dir.y = 0
	dir = dir.normalized().rotated(Vector3.UP, randf_range(-0.3, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = _corpse_mesh
	mi.material_override = _corpse_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * (1.5 if z.has_meta("variant") and String(z.get_meta("variant")) == "tank" else 1.0)
	add_child(mi)
	var from := z.global_position + Vector3(0, 0.6, 0)
	var dist := randf_range(2.5, 4.5) * power
	var to := from + dir * dist
	to.x = clampf(to.x, -HarborBuilder.HALF_X + 0.5, HarborBuilder.HALF_X - 0.5)
	to.z = clampf(to.z, HarborBuilder.DOCK_EDGE_Z - 3.0, HarborBuilder.GATE_Z - 0.5)   # 可以飞进海里
	to.y = 0.25 if to.z > HarborBuilder.DOCK_EDGE_Z else -1.0
	mi.global_position = from
	_corpses += 1
	var spin := Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
	var h := 1.2 + power
	var dur := 0.38 + 0.08 * power
	var tw := mi.create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(mi):
			mi.global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * h, 0)
			mi.rotation = spin * k
	, 0.0, 1.0, dur)
	tw.tween_callback(func():
		if to.y > 0.0:
			Fx.dust(self, to, 4, Color(0.8, 1.0, 0.85, 0.7), 1.6, 0.25)
		else:
			Fx.dust(self, Vector3(to.x, 0.0, to.z), 6, Color(0.7, 0.9, 1.0, 0.9), 2.4, 0.4)   # 扑通
	)
	tw.tween_property(mi, "scale", Vector3(mi.scale.x * 1.3, 0.05, mi.scale.z * 1.3), 0.12)
	tw.tween_callback(func():
		_corpses -= 1
		mi.queue_free()
	)


## 0.55 秒内连续击杀：结算成「连爆」，杀得越多奖励越多
func _tick_multikill(delta: float) -> void:
	if _mk_t <= 0.0:
		return
	_mk_t -= delta
	if _mk_t > 0.0:
		return
	var n := _mk_n
	_mk_n = 0
	if n < 4:
		return
	var title := "清 场 ！" if n >= 16 else ("大 爆 杀 ！" if n >= 9 else "连 爆 ！")
	var col := Pal.RED if n >= 16 else (Pal.ORANGE if n >= 9 else Pal.YELLOW)
	Fx.popup(self, player.global_position + Vector3(0, 2.8, 0), "%s ×%d" % [title, n], col, 70 + mini(n, 20) * 2, true, 1.2, 1.0)
	Sfx.play("perfect", -4.0, 1.0 + minf(n, 20) * 0.03, 0.0)
	hud.score_popup("%s ×%d" % [title.replace(" ", ""), n], n * 10)
	burst_loot(player.global_position + Vector3(0, 1.6, 0), n / 2, 0, 0)
	if n >= 9:
		Game.hitstop(0.06)
		fever = mini(RAMPAGE_NEED - 1, fever + n) if not player.giant else fever


## 换弹不再是「干等」：换完那一下震开身边的僵尸鼠；完美换弹震得更远、还带伤害
func on_reload_done(perfect: bool) -> void:
	if stage != "play":
		return
	var r := 5.5 if perfect else 3.6
	var pp := player.global_position
	Fx.ring(self, pp, Pal.ORANGE if perfect else Pal.CREAM, r, 0.35)
	for z in zombies.duplicate():
		if not is_instance_valid(z) or z.dead or z.has_meta("mech"):
			continue
		var d: Vector3 = z.global_position - pp
		d.y = 0
		if d.length() < r:
			z.take_hit(3.0 * float(player.mods.dmg) if perfect else 0.4, d.normalized() * (3.2 if perfect else 2.4), pp, player)
			z.stun(0.5 if perfect else 0.25)
	if perfect:
		Sfx.play("bonk", -6.0, 0.8, 0.0)


# ------------------------------------------------------------------ 加难：扑咬 / 精英鼠王

## 冲刺鼠（高级以上：所有僵尸鼠）靠近到 2–4.5 米会蹲一下然后扑过来；扑到身上才掉血，翻滚 / 横移能躲
func _tick_lunges(delta: float) -> void:
	_lunge_scan -= delta
	if _lunge_scan > 0.0 or player.dead:
		return
	_lunge_scan = 0.12
	var all: float = hdiff().lunge if t > 45.0 else 0.0   # 开局只有冲刺鼠会扑
	var pp := player.global_position
	var now := Time.get_ticks_msec()
	var started := 0
	for z in zombies:
		if z.dead or z.boss or z.skill_lock > 0.0 or started >= 3:
			continue
		var v: String = z.get_meta("variant", "")
		if v != "runner" and (all <= 0.0 or v != ""):
			continue
		if now < int(z.get_meta("lunge_at", 0)):
			continue
		var to := pp - z.global_position
		to.y = 0
		var d := to.length()
		if d < 2.0 or d > 4.5:
			continue
		var cd := 2200.0 if v == "runner" else 5200.0 / maxf(all, 0.5)
		z.set_meta("lunge_at", now + int(cd + randf_range(0, 900)))
		started += 1
		_lunge(z, to / d)


func _lunge(z: Zombie, dir: Vector3) -> void:
	z.skill_lock = 0.3
	z.skill_vel = Vector3.ZERO
	z.model.crouch = 1.0
	z.model.flash(Pal.RED, 0.8)
	var zid: int = z.get_instance_id()
	get_tree().create_timer(0.3, false).timeout.connect(func():
		var zz := instance_from_id(zid) as Zombie
		if zz == null or zz.dead or stage != "play":
			return
		zz.model.crouch = 0.0
		zz.skill_lock = 0.28
		zz.skill_vel = dir * 13.0
		get_tree().create_timer(0.26, false).timeout.connect(func():
			var z3 := instance_from_id(zid) as Zombie
			if z3 == null or z3.dead or player.dead:
				return
			z3.skill_vel = Vector3.ZERO
			var to := player.global_position - z3.global_position
			to.y = 0
			if to.length() < 1.15:
				player.take_hit(5.0 * z3.dmg_mult, dir, z3.global_position, z3)
		)
	)


## 精英鼠王（序章的那只大僵尸鼠）：按难度定时从远处走过来，拍地很疼，打倒掉一堆罐头
func _tick_elites(delta: float) -> void:
	var every: float = hdiff().elite_every
	if every <= 0.0 or step < 1 or step == 3 or step == 5:
		return
	_elite_t += delta
	if _elite_t < every:
		return
	_elite_t = 0.0
	var e := _spawn_zombie_ring(true)
	if e == null:
		return
	e.max_hp = (26.0 + level_n * 7.0) * float(hdiff().boss_hp)
	e.hp = e.max_hp
	e.speed *= 1.25
	e.dmg_mult = 1.0 + step * 0.1   # 拍地本来就 22 点，不再乘咬人倍率
	hud.toast("精英鼠王来了！")
	Sfx.play("groan", -2.0, 0.5, 0.0)


func on_enemy_alerted(_e: Enemy) -> void:
	pass


func on_enemy_down(_e: Enemy) -> void:
	pass


func on_enemy_woke(_e: Enemy) -> void:
	pass


func on_enemy_cuffed(_e: Enemy) -> void:
	pass


# ------------------------------------------------------------------ 结束

func on_player_dead() -> void:
	if stage != "play":
		return
	stage = "over"
	finished = true
	rampage_t = 0.0
	hud.set_target(null)
	hud.set_objective("任务失败", "")
	Sfx.music("")
	Sfx.play("fail", -2.0, 1.0, 0.0)
	hud.radio.clear()
	hud.radio.say("chief", "豆包倒下了！直升机，把他吊出来！", 0.0, true)
	Game.run["score"] = total_score()
	await get_tree().create_timer(2.4, true, false, true).timeout
	hud.visible = false
	hhud.show_summary()


func survive_seconds() -> int:
	return int(t)


## 结算的每一行：[名字, 数值文字, 倍率文字, 得分]
func score_rows() -> Array:
	var secs := survive_seconds()
	var steps_done := step + (1 if won else 0)
	var rows := [
		["主线进度", "%d / %d" % [steps_done, STEPS.size()], "× 400", steps_done * 400],
	]
	if won:
		rows.append(["通关用时", "%d:%02d" % [secs / 60, secs % 60], "快 = 多", maxi(0, 420 - secs) * 10])
	rows.append(["击退僵尸鼠", "%d" % kills, "× 3", kills * 3])
	rows.append(["吸到的罐头", "%d" % cans, "× 2", cans * 2])
	rows.append(["罐头狂暴", "%d 次" % rampages, "× 100", rampages * 100])
	rows.append(["打爆罐头蟹", "%d 台" % bosses_down, "× 500", bosses_down * 500])
	if elites_down > 0:
		rows.append(["精英鼠王", "%d 只" % elites_down, "× 200", elites_down * 200])
	return rows


func total_score() -> int:
	var sum := 0
	for r in score_rows():
		sum += int(r[3])
	return sum


func tip(id: String) -> void:
	if stage != "play":
		return
	super.tip(id)
