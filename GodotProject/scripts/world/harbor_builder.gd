class_name HarborBuilder
extends MapBuilder
## 第二章 · 雾港码头「罐头狂暴」：静态场景（地面、仓库、集装箱迷宫、渔市、油桶区、龙门吊、海、货轮）。
## 可以打碎的箱子 / 集装箱 / 油桶不在这里（Breakable，由 HarborLevel 摆放），
## 这样它们不会被 bake_static() 合进静态网格。
##
## 坐标：仓库在原点；海在北边（-Z），城市大门在南边（+Z）；集装箱迷宫在东（+X），渔市和油桶区在西（-X）。

const HALF_X := 23.0
const DOCK_EDGE_Z := -16.0
const GATE_Z := 18.0
const WAREHOUSE := Rect2(-6, -5, 12, 10)       # x, z, 宽, 深
const STACK_POS := Vector3(0, 0, -0.5)          # 仓库里的罐头货堆

const C_DOCK := Color("4A5062")
const C_DOCK_LINE := Color("E8C35A")
const C_WARE := Color("8C9BB8")
const C_WARE_ROOF_EDGE := Color("5A6886")
const CONTAINER_COLORS: Array[Color] = [Color("D9534F"), Color("3E7CB1"), Color("F0A202"), Color("2A9D8F"), Color("8E6CC9"), Color("E07A3F")]

var crane_top := Vector3(-3.0, 9.0, -13.5)


func build() -> void:
	_ground()
	_warehouse()
	_container_maze()
	_fish_market()
	_oil_yard()
	_crane_and_ship()
	_bounds()
	_harbor_lights()
	flush_products()
	bake_static()


# ------------------------------------------------------------------ 地面 / 海

func _ground() -> void:
	solid(Vector3(0, -1.0, 1.0), Vector3(HALF_X * 2 + 4, 1.0, (GATE_Z - DOCK_EDGE_Z) + 4), Color.BLACK, Bullet.LAYER_WORLD, false, false)
	floor_plane(-HALF_X - 2, DOCK_EDGE_Z, HALF_X + 2, GATE_Z + 6, Toon.prop(C_DOCK), -0.01)
	# 码头边缘的黄黑警示条
	for i in 24:
		var x := -HALF_X + i * 2.0 + 1.0
		deco(Models.box(Vector3(1.0, 0.04, 0.4)), Toon.prop(C_DOCK_LINE if i % 2 == 0 else Color("1B1F2A")), Vector3(x, 0.02, DOCK_EDGE_Z + 0.3))
	# 地面上的车道线
	for i in 6:
		deco(Models.box(Vector3(0.25, 0.02, 2.0)), Toon.prop(Color("C9CFDD")), Vector3(-7.5, 0.01, -12.0 + i * 5.5))
	# 海（码头以北，低于地面）
	var sea := PlaneMesh.new()
	sea.size = Vector2(160, 70)
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color("163556")
	sea_mat.metallic_specular = 0.9
	sea_mat.roughness = 0.15
	sea_mat.emission_enabled = true
	sea_mat.emission = Color("0A1E33")
	deco(sea, sea_mat, Vector3(0, -0.9, DOCK_EDGE_Z - 35))
	# 码头立面（地面到海面的“墙”）
	deco(Models.box(Vector3(HALF_X * 2 + 4, 0.9, 0.4)), Toon.prop(Color("2A3142")), Vector3(0, -0.45, DOCK_EDGE_Z - 0.2))
	# 系船柱
	for x in [-18.0, -10.0, 6.0, 14.0, 20.0]:
		deco(Models.cyl(0.22, 0.28, 0.6), Toon.prop_outlined(Color("2A2E38")), Vector3(x, 0.3, DOCK_EDGE_Z + 0.8))
		deco(Models.cyl(0.32, 0.32, 0.12), Toon.prop_outlined(Color("2A2E38")), Vector3(x, 0.62, DOCK_EDGE_Z + 0.8))


# ------------------------------------------------------------------ 7 号仓库（基地 / 卸货点）

func _warehouse() -> void:
	var r := WAREHOUSE
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.position.x + r.size.x
	var z1 := r.position.y + r.size.y
	# 北、西墙高；朝镜头的南、东墙矮（碰撞仍是完整高度）
	wall(x0, z0, x1, z0, WALL_TALL, C_WARE)
	wall(x0, z0, x0, z1, WALL_TALL, C_WARE)
	wall(x1, z0, x1, z1, WALL_LOW, C_WARE, WALL_COLLIDE)
	# 南墙中间是大门（宽 4.4）
	wall(x0, z1, -2.2, z1, WALL_LOW, C_WARE, WALL_COLLIDE)
	wall(2.2, z1, x1, z1, WALL_LOW, C_WARE, WALL_COLLIDE)
	floor_plane(x0, z0, x1, z1, checker_mat(Color("A7B2C6"), Color("98A3B8"), Vector2(12, 10)), 0.004)
	# 大门门框 + 招牌
	deco(Models.box(Vector3(5.0, 0.35, 0.4)), Toon.prop_outlined(Pal.ORANGE), Vector3(0, WALL_TALL - 0.3, z1))
	label("7 号仓库", Vector3(0, WALL_TALL - 0.3, z1 + 0.22), 96, Pal.INK, Vector3.ZERO, Style.title_font(), 0.008)
	for sx in [-1.0, 1.0]:
		deco(Models.box(Vector3(0.35, WALL_TALL, 0.4)), Toon.prop_outlined(Pal.ORANGE), Vector3(2.2 * sx, WALL_TALL * 0.5, z1))
	# 仓库里靠墙的货架（装饰）
	for i in 4:
		solid(Vector3(x0 + 1.6 + i * 2.6, 0, z0 + 0.8), Vector3(2.2, 1.6, 0.8), Color("6E7A96"), Bullet.LAYER_WORLD, true)


# ------------------------------------------------------------------ 东区：集装箱迷宫

## 一排排固定的集装箱（不能打碎）。能打碎的「货柜」由 HarborLevel 摆在缝隙里。
const MAZE := [
	# [中心 x, 中心 z, 是否旋转 90°]
	[11.0, -12.0, false], [18.0, -12.0, false],
	[11.0, -7.5, false], [19.5, -7.5, false],
	[14.5, -3.0, true],
	[10.5, 1.5, false], [18.5, 1.5, false],
	[12.0, 6.0, true], [20.0, 6.5, true],
	[11.0, 11.0, false], [18.0, 12.0, false],
]


func _container_maze() -> void:
	for i in MAZE.size():
		var m: Array = MAZE[i]
		var c: Color = CONTAINER_COLORS[i % CONTAINER_COLORS.size()]
		container_static(Vector3(m[0], 0, m[1]), m[2], c)
	label("东区 · 集装箱", Vector3(15.0, 0.03, 15.5), 96, Color(1, 1, 1, 0.35), Vector3(-90, 0, 0), Style.title_font(), 0.01)


func container_static(center: Vector3, rotated: bool, color: Color) -> void:
	var size := Vector3(6.0, 2.4, 2.4) if not rotated else Vector3(2.4, 2.4, 6.0)
	solid(center, size, color, Bullet.LAYER_WORLD, true)
	# 竖向波纹
	var n := 9
	for k in n:
		var t := -0.5 + (k + 0.5) / n
		if not rotated:
			deco(Models.box(Vector3(0.12, 2.3, 2.46)), Toon.prop(color.darkened(0.18)), center + Vector3(t * 5.8, 1.2, 0))
		else:
			deco(Models.box(Vector3(2.46, 2.3, 0.12)), Toon.prop(color.darkened(0.18)), center + Vector3(0, 1.2, t * 5.8))
	# 顶边
	deco(Models.box(Vector3(size.x + 0.06, 0.1, size.z + 0.06)), Toon.prop(color.darkened(0.3)), center + Vector3(0, 2.42, 0))


# ------------------------------------------------------------------ 西南：渔市棚

func _fish_market() -> void:
	# 三张长桌（矮掩体）+ 棚顶（只画柱子和边，避免挡住视线）
	for k in 3:
		var z := 7.5 + k * 3.4
		solid(Vector3(-15.0, 0, z), Vector3(7.0, 0.85, 1.1), Color("D9E2EC"), Bullet.LAYER_LOWCOVER, true)
		deco(Models.box(Vector3(7.1, 0.06, 1.2)), Toon.prop(Color("4FA3C7")), Vector3(-15.0, 0.88, z))
		for i in 8:
			# 桌上的鱼（小扁球）
			var fx := -18.2 + i * 0.9
			deco(Models.sphere(0.12), Toon.prop(Color("9FB8C9")), Vector3(fx, 0.97, z + (0.2 if i % 2 == 0 else -0.2)), Vector3.ZERO, Vector3(1.6, 0.6, 0.8))
	for p in [Vector3(-19.2, 0, 5.8), Vector3(-10.8, 0, 5.8), Vector3(-19.2, 0, 15.2), Vector3(-10.8, 0, 15.2)]:
		deco(Models.cyl(0.08, 0.08, 3.2), Toon.prop_outlined(Color("2A2E38")), p + Vector3(0, 1.6, 0))
	# 条纹雨棚（只在北边一条，靠后不挡人）
	for i in 8:
		deco(Models.box(Vector3(1.05, 0.12, 1.4)), Toon.prop(Pal.RED if i % 2 == 0 else Pal.CREAM), Vector3(-18.7 + i * 1.05, 3.2, 5.8))
	label("渔市", Vector3(-15.0, 0.03, 17.0), 96, Color(1, 1, 1, 0.35), Vector3(-90, 0, 0), Style.title_font(), 0.01)


# ------------------------------------------------------------------ 西北：油桶区

func _oil_yard() -> void:
	# 地上的油渍 + 围栏
	deco(Models.cyl(2.6, 2.6, 0.02), Toon.prop(Color("232733")), Vector3(-15.5, 0.012, -8.5))
	for i in 6:
		deco(Models.box(Vector3(0.1, 1.0, 0.1)), Toon.prop_outlined(Color("C9CFDD")), Vector3(-21.5 + i * 2.0, 0.5, -2.2))
	deco(Models.box(Vector3(10.2, 0.08, 0.06)), Toon.prop(Pal.YELLOW), Vector3(-16.5, 0.9, -2.2))
	label("油桶区 · 小心爆炸", Vector3(-15.5, 0.03, -1.0), 72, Color(1.0, 0.8, 0.4, 0.5), Vector3(-90, 0, 0), Style.title_font(), 0.008)
	# 叉车（装饰掩体）
	solid(Vector3(-8.5, 0, -10.5), Vector3(1.4, 1.2, 2.2), Pal.YELLOW, Bullet.LAYER_LOWCOVER, true)
	deco(Models.box(Vector3(0.1, 2.2, 0.1)), Toon.prop_outlined(Color("2A2E38")), Vector3(-9.0, 1.1, -11.7))
	deco(Models.box(Vector3(0.1, 2.2, 0.1)), Toon.prop_outlined(Color("2A2E38")), Vector3(-8.0, 1.1, -11.7))


# ------------------------------------------------------------------ 北：龙门吊 + 货轮（远景，不挡视线）

func _crane_and_ship() -> void:
	var cx := crane_top.x
	var cz := crane_top.z
	var steel := Toon.prop_outlined(Color("F0A202"))
	for sx in [-3.0, 3.0]:
		deco(Models.box(Vector3(0.5, 9.0, 0.5)), steel, Vector3(cx + sx, 4.5, cz - 1.0))
		deco(Models.box(Vector3(0.5, 9.0, 0.5)), steel, Vector3(cx + sx, 4.5, cz + 1.0))
		solid(Vector3(cx + sx, 0, cz), Vector3(0.7, 2.0, 2.4), Color("F0A202"), Bullet.LAYER_WORLD, false, false)
	deco(Models.box(Vector3(7.0, 0.7, 2.6)), steel, Vector3(cx, 9.2, cz))
	# 伸向海面的吊臂
	deco(Models.box(Vector3(1.0, 0.5, 14.0)), steel, Vector3(cx, 9.6, cz - 7.0))
	# 夜影趴的平台
	deco(Models.box(Vector3(2.0, 0.15, 1.6)), Toon.prop_outlined(Color("2A2E38")), Vector3(cx, 9.65, cz + 0.6))
	# 货轮（不开灯，黑乎乎）
	var hull := Color("1C2333")
	deco(Models.box(Vector3(30.0, 4.0, 7.0)), Toon.prop_outlined(hull, Color("0B0F18")), Vector3(4.0, 0.6, DOCK_EDGE_Z - 7.5))
	deco(Models.box(Vector3(8.0, 3.0, 5.0)), Toon.prop_outlined(Color("2A3348"), Color("0B0F18")), Vector3(14.0, 4.1, DOCK_EDGE_Z - 7.5))
	deco(Models.box(Vector3(30.2, 0.3, 7.2)), Toon.prop(Color("8B2E2E")), Vector3(4.0, -1.0, DOCK_EDGE_Z - 7.5))
	label("BLACK MASK", Vector3(4.0, 1.4, DOCK_EDGE_Z - 3.95), 120, Color(1, 1, 1, 0.25), Vector3.ZERO, Style.num_font(), 0.012)


# ------------------------------------------------------------------ 边界

func _bounds() -> void:
	# 码头边（北）：看不见的墙，人掉不下海
	barrier(-HALF_X, DOCK_EDGE_Z + 0.1, HALF_X, DOCK_EDGE_Z + 0.1)
	barrier(-HALF_X, DOCK_EDGE_Z, -HALF_X, GATE_Z)
	barrier(HALF_X, DOCK_EDGE_Z, HALF_X, GATE_Z)
	barrier(-HALF_X, GATE_Z, HALF_X, GATE_Z)
	# 南边的铁丝网（矮，只露一截）
	for i in 24:
		deco(Models.box(Vector3(0.08, 1.1, 0.08)), Toon.prop_outlined(Color("C9CFDD")), Vector3(-HALF_X + i * 2.0, 0.55, GATE_Z))
	deco(Models.box(Vector3(HALF_X * 2, 0.05, 0.05)), Toon.prop(Color("C9CFDD")), Vector3(0, 1.0, GATE_Z))
	deco(Models.box(Vector3(HALF_X * 2, 0.05, 0.05)), Toon.prop(Color("C9CFDD")), Vector3(0, 0.5, GATE_Z))


# ------------------------------------------------------------------ 灯：码头的黄色工作灯

func _harbor_lights() -> void:
	for p in [Vector3(-12, 0, -6), Vector3(-12, 0, 10), Vector3(8, 0, -14), Vector3(8, 0, 14), Vector3(22, 0, -2)]:
		deco(Models.cyl(0.07, 0.09, 5.0), Toon.prop_outlined(Color("2A2E38")), p + Vector3(0, 2.5, 0))
		deco(Models.box(Vector3(0.7, 0.18, 0.4)), Toon.glow(Color(1.0, 0.85, 0.5), 2.2), p + Vector3(0, 5.0, 0))
		light(p + Vector3(0, 4.6, 0), Color(1.0, 0.8, 0.5), 2.0, 11.0)
	# 仓库里一盏暖灯
	light(Vector3(0, 3.0, 0), Color(1.0, 0.75, 0.45), 1.6, 9.0)
