class_name MapBuilder
extends RefCounted
## 序章关卡「喵喵便利店」场景搭建。全部用几何体拼装：
##   街道(南) → 店面(西) → 仓库(东南) → 员工休息室(东北, 锁门)
## 坐标：x 向东，z 向南（朝镜头）。镜头在东南方 45° 俯视。

const WALL_TALL := 2.4
const WALL_MID := 1.4
const WALL_LOW := 0.55
const WALL_COLLIDE := 2.4

var root: Node3D
var geo: Node3D
var low_covers: Array[AABB] = []
var car_lights: Array[OmniLight3D] = []
var car: Node3D
var car_body: StaticBody3D
var car_bulbs: Array[MeshInstance3D] = []
var entry_doors: Array[MeshInstance3D] = []
var flicker_light: OmniLight3D

var _products: Array[Transform3D] = []
var _product_colors: Array[Color] = []

const C_WALL := Color("E8D9BC")
const C_WALL_IN := Color("D9C8A8")
const C_CAP := Color("1B2A4A")
const C_SHELF := Color("C3CCDB")
const C_WOOD := Color("B07A47")
const C_WOOD_DARK := Color("8B5E3C")


func _init(r: Node3D, g: Node3D) -> void:
	root = r
	geo = g


# ------------------------------------------------------------------ 基础件

func solid(center_bottom: Vector3, size: Vector3, color: Color, layer := Bullet.LAYER_WORLD,
		outlined := false, visual := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = center_bottom + Vector3(0, size.y * 0.5, 0)
	if visual:
		var mi := MeshInstance3D.new()
		mi.mesh = Models.box(size)
		mi.material_override = Toon.prop_outlined(color) if outlined else Toon.prop(color)
		sb.add_child(mi)
	geo.add_child(sb)
	if layer & Bullet.LAYER_LOWCOVER:
		low_covers.append(AABB(center_bottom - Vector3(size.x * 0.5, 0, size.z * 0.5), size))
	return sb


func deco(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE,
		parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	(parent if parent else root).add_child(mi)
	return mi


func label(text: String, pos: Vector3, size: int, color: Color, rot_deg := Vector3.ZERO,
		font: Font = null, pixel := 0.006, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font if font else Style.title_font()
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = outline
	l.outline_modulate = Pal.INK
	l.position = pos
	l.rotation_degrees = rot_deg
	l.shaded = false
	root.add_child(l)
	return l


## 轴对齐墙体：可视高度 h，碰撞高度 collide_h（矮墙用不可见的高碰撞）
func wall(x0: float, z0: float, x1: float, z1: float, h: float, color: Color, collide_h := -1.0, thick := 0.3) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var sx := absf(x1 - x0) + thick
	var sz := absf(z1 - z0) + thick
	var ch := maxf(h, collide_h)
	solid(Vector3(cx, 0, cz), Vector3(sx, ch, sz), color, Bullet.LAYER_WORLD, false, false)
	deco(Models.box(Vector3(sx, h, sz)), Toon.prop(color), Vector3(cx, h * 0.5, cz))
	deco(Models.box(Vector3(sx + 0.04, 0.07, sz + 0.04)), Toon.prop(C_CAP), Vector3(cx, h + 0.035, cz))
	# 踢脚线
	deco(Models.box(Vector3(sx + 0.02, 0.14, sz + 0.02)), Toon.prop(color.darkened(0.25)), Vector3(cx, 0.07, cz))


func barrier(x0: float, z0: float, x1: float, z1: float) -> void:
	var size := Vector3(absf(x1 - x0) + 0.3, 3.0, absf(z1 - z0) + 0.3)
	solid(Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5), size, Color.BLACK, Bullet.LAYER_WORLD, false, false)


func light(pos: Vector3, color: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	l.position = pos
	# 流畅画质：灯具本身的发光模型还在，只是不做实时光照（隐藏的灯不参与渲染）
	l.visible = not Game.lite
	root.add_child(l)
	return l


func checker_mat(a: Color, b: Color, tiles: Vector2) -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(tiles.x * 0.5, tiles.y * 0.5, 1)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 0.6
	m.metallic_specular = 0.6
	return m


func floor_plane(x0: float, z0: float, x1: float, z1: float, mat: Material, y := 0.0) -> void:
	var p := PlaneMesh.new()
	p.size = Vector2(x1 - x0, z1 - z0)
	deco(p, mat, Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5))


func product(pos: Vector3, size: Vector3, color: Color) -> void:
	_products.append(Transform3D(Basis.from_scale(size), pos))
	_product_colors.append(color)


func flush_products() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Models.box(Vector3.ONE)
	mm.instance_count = _products.size()
	for i in _products.size():
		mm.set_instance_transform(i, _products[i])
		mm.set_instance_color(i, _product_colors[i])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.roughness = 0.6
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	root.add_child(mmi)


# ------------------------------------------------------------------ 整体布局

func build() -> void:
	_floors()
	_walls()
	_shop()
	_storage()
	_staff()
	_street()
	_lights()
	flush_products()
	bake_static()


## 静态场景合批：墙、货架、柜台、纸箱……几百个小方块原来每个 1~2 次绘制。
## 按「材质外观」（光照参数 + 描边）分组，合成少数几个顶点色网格。
## 不动：有贴图的（地板格子）、透明 / 发光的（玻璃、霓虹）、警车（会开走）。碰撞体不受影响。
func bake_static() -> void:
	var groups := {}
	var inv := root.global_transform.affine_inverse()
	var all: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if geo != root and not root.is_ancestor_of(geo):
		all.append_array(geo.find_children("*", "MeshInstance3D", true, false))
	for n in all:
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible or mi.get_child_count() > 0 or mi.mesh.get_surface_count() != 1:
			continue
		if car and car.is_ancestor_of(mi):
			continue
		var mt := mi.material_override as StandardMaterial3D
		if mt == null or mt.albedo_texture or mt.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or mt.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or mt.vertex_color_use_as_albedo:
			continue
		var o := mt.next_pass as StandardMaterial3D
		var key := "%d|%d|%.2f|%.2f|%.2f|%s" % [mt.diffuse_mode, mt.specular_mode, mt.roughness, mt.metallic_specular, mt.rim if mt.rim_enabled else -1.0,
			("%s/%.3f" % [o.albedo_color.to_html(), o.grow_amount]) if o else "-"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	for key in groups:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for mi: MeshInstance3D in parts:
			var xf := inv * mi.global_transform
			var nb := xf.basis.inverse().transposed()
			var col := (mi.material_override as StandardMaterial3D).albedo_color
			var arr := mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn = arr[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * (nn[i] as Vector3)).normalized() if nn != null else Vector3.UP)
				cols.append(col)
			var ii = arr[Mesh.ARRAY_INDEX]
			if ii != null and (ii as PackedInt32Array).size() > 0:
				for k in (ii as PackedInt32Array):
					idx.append(base + k)
			else:
				for k in v.size():
					idx.append(base + k)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		a[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var first := (parts[0] as MeshInstance3D).material_override as StandardMaterial3D
		var vm := first.duplicate(true) as StandardMaterial3D
		vm.albedo_color = Color.WHITE
		vm.vertex_color_use_as_albedo = true
		vm.vertex_color_is_srgb = true
		var merged := MeshInstance3D.new()
		merged.name = "StaticBatch"
		merged.mesh = mesh
		merged.material_override = vm
		root.add_child(merged)
		for mi: MeshInstance3D in parts:
			mi.get_parent().remove_child(mi)
			mi.free()


func _floors() -> void:
	# 地面碰撞（导航网格烘焙需要）
	solid(Vector3(0, -1.0, 3.5), Vector3(40, 1.0, 36), Color.BLACK, Bullet.LAYER_WORLD, false, false)
	floor_plane(-40, -40, 40, 40, Toon.prop(Color("232838")), -0.01)
	floor_plane(-12, -6, 5, 8, checker_mat(Color("E4DED2"), Color("B4BFD3"), Vector2(17, 14)))
	floor_plane(5, 0, 12, 8, checker_mat(Color("A3ADBF"), Color("98A2B5"), Vector2(7, 8)))
	floor_plane(5, -10, 12, 0, checker_mat(Color("B9875A"), Color("A97A50"), Vector2(14, 20)))
	# 人行道 + 马路
	floor_plane(-15, 8, 15, 10.6, checker_mat(Color("6B7390"), Color("626A86"), Vector2(30, 2.6)), 0.005)
	deco(Models.box(Vector3(30, 0.16, 0.25)), Toon.prop(Color("8C93AD")), Vector3(0, 0.08, 10.6))
	floor_plane(-15, 10.7, 15, 19, Toon.prop(Color("2E3345")), 0.004)
	for i in 8:
		deco(Models.box(Vector3(2.0, 0.02, 0.22)), Toon.glow(Color("E8C35A"), 0.9), Vector3(-13 + i * 4, 0.01, 14.8))
	# 门口地垫
	deco(Models.box(Vector3(3.0, 0.02, 1.4)), Toon.prop(Pal.NAVY), Vector3(0, 0.01, 7.1))
	label("欢迎光临", Vector3(0, 0.03, 7.1), 64, Pal.ORANGE, Vector3(-90, 0, 0), null, 0.008)


func _walls() -> void:
	# 背面高墙（北、西）
	wall(-12, -6, 5, -6, WALL_TALL, C_WALL)
	wall(-12, -6, -12, 8, WALL_TALL, C_WALL)
	wall(5, -10, 12, -10, WALL_TALL, C_WALL)
	wall(5, -10, 5, -6, WALL_TALL, C_WALL)
	# 朝镜头的矮墙（南、东）：只露出一截，碰撞仍然完整
	wall(-12, 8, -1.6, 8, WALL_LOW, C_WALL, WALL_COLLIDE)
	wall(1.6, 8, 12, 8, WALL_LOW, C_WALL, WALL_COLLIDE)
	wall(12, -10, 12, 8, WALL_LOW, C_WALL, WALL_COLLIDE)
	# 内部隔墙
	wall(5, -6, 5, 0, WALL_MID, C_WALL_IN)
	wall(5, 0, 5, 4.3, WALL_MID, C_WALL_IN)
	wall(5, 6.9, 5, 8, WALL_MID, C_WALL_IN)
	# 门洞净宽 1.6m（墙厚 0.3，两端各让出 0.15）
	wall(5, 0, 7.85, 0, WALL_MID, C_WALL_IN)
	wall(9.75, 0, 12, 0, WALL_MID, C_WALL_IN)
	# 落地玻璃窗
	for seg in [[-11.8, -1.8], [1.8, 4.8], [5.2, 11.8]]:
		var w: float = seg[1] - seg[0]
		deco(Models.box(Vector3(w, 1.5, 0.06)), Toon.glass(), Vector3((seg[0] + seg[1]) * 0.5, WALL_LOW + 0.75, 8.0))
		deco(Models.box(Vector3(w, 0.06, 0.12)), Toon.prop(C_CAP), Vector3((seg[0] + seg[1]) * 0.5, WALL_LOW + 1.5, 8.0))
	# 自动门
	for sx in [-1.0, 1.0]:
		deco(Models.box(Vector3(0.18, 2.1, 0.3)), Toon.prop(C_CAP), Vector3(1.7 * sx, 1.05, 8.0))
		var d := deco(Models.box(Vector3(1.5, 1.95, 0.05)), Toon.glass(Color(0.7, 0.9, 1.0, 0.3)), Vector3(0.76 * sx, 0.98, 8.0))
		entry_doors.append(d)
	deco(Models.box(Vector3(3.6, 0.2, 0.3)), Toon.prop(C_CAP), Vector3(0, 2.15, 8.0))


func _shop() -> void:
	# 三排货架
	for sx in [-9.5, -6.5, -3.5]:
		_shelf(sx, 0.25, 6.4)
	# 冰柜（北墙）
	for i in 5:
		var x := -11.0 + i * 2.0 + 1.0
		solid(Vector3(x, 0, -5.5), Vector3(1.9, 2.1, 0.9), Color("C9D3E3"), Bullet.LAYER_WORLD, true)
		deco(Models.box(Vector3(1.7, 1.7, 0.05)), Toon.glow(Color(0.55, 0.85, 1.0, 0.55), 1.1), Vector3(x, 1.05, -5.03))
		deco(Models.box(Vector3(1.8, 0.1, 0.06)), Toon.glow(Color(0.7, 0.95, 1.0), 2.0), Vector3(x, 1.98, -5.03))
		for row in 3:
			for k in 6:
				var c: Color = Pal.PRODUCTS[(i * 3 + row * 2 + k) % Pal.PRODUCTS.size()]
				product(Vector3(x - 0.7 + k * 0.28, 0.45 + row * 0.5, -5.2), Vector3(0.14, 0.32, 0.14), c)
	# 收银台（L 形低矮掩体）
	solid(Vector3(2.5, 0, 3.0), Vector3(3.8, 0.95, 0.9), Color("FFB46B"), Bullet.LAYER_LOWCOVER, true)
	solid(Vector3(1.05, 0, 1.55), Vector3(0.9, 0.95, 2.0), Color("FFB46B"), Bullet.LAYER_LOWCOVER, true)
	deco(Models.box(Vector3(3.9, 0.08, 1.0)), Toon.prop(Pal.NAVY), Vector3(2.5, 0.99, 3.0))
	deco(Models.box(Vector3(0.55, 0.35, 0.45)), Toon.prop_outlined(Color("3A4258")), Vector3(3.5, 1.2, 3.0))
	deco(Models.box(Vector3(0.4, 0.22, 0.04)), Toon.glow(Pal.TEAL, 1.6), Vector3(3.5, 1.42, 3.24), Vector3(-20, 0, 0))
	for k in 7:
		product(Vector3(1.0 + k * 0.32, 1.12, 3.25), Vector3(0.2, 0.18, 0.14), Pal.PRODUCTS[k % Pal.PRODUCTS.size()])
	label("收银台", Vector3(2.5, 0.55, 3.46), 56, Pal.NAVY, Vector3.ZERO, null, 0.005)
	# 促销立牌
	deco(Models.box(Vector3(0.9, 1.2, 0.06)), Toon.prop_outlined(Pal.YELLOW), Vector3(-1.2, 0.6, 5.6), Vector3(0, 20, 0))
	label("罐头\n8折!", Vector3(-1.17, 0.7, 5.64), 64, Pal.RED, Vector3(0, 20, 0), null, 0.005)
	# 地面上散落的零食（被抢劫的痕迹）
	for k in 9:
		var p := Vector3(randf_range(-11, 3), 0.06, randf_range(-4.5, 7))
		product(p, Vector3(0.22, 0.1, 0.16), Pal.PRODUCTS[k % Pal.PRODUCTS.size()])


func _shelf(cx: float, cz: float, length: float) -> void:
	solid(Vector3(cx, 0, cz), Vector3(0.9, 1.3, length), C_SHELF, Bullet.LAYER_WORLD, true)
	deco(Models.box(Vector3(0.96, 0.06, length + 0.06)), Toon.prop(Pal.NAVY), Vector3(cx, 1.33, cz))
	var n := int(length / 0.3)
	for side in [-1.0, 1.0]:
		for row in 3:
			var y := 0.18 + row * 0.42
			for k in n:
				if randf() < 0.18:
					continue
				var z := cz - length * 0.5 + 0.18 + k * 0.3
				var h := randf_range(0.18, 0.3)
				var c: Color = Pal.PRODUCTS[randi() % Pal.PRODUCTS.size()]
				product(Vector3(cx + side * 0.46, y + h * 0.5, z), Vector3(0.12, h, 0.22), c)
	for k in n:
		if randf() < 0.3:
			continue
		var h2 := randf_range(0.14, 0.3)
		product(Vector3(cx + randf_range(-0.2, 0.2), 1.36 + h2 * 0.5, cz - length * 0.5 + 0.2 + k * 0.3),
			Vector3(0.24, h2, 0.2), Pal.PRODUCTS[randi() % Pal.PRODUCTS.size()])


func _storage() -> void:
	_crate(Vector3(7.0, 0, 2.2), Vector3(1.2, 0.9, 1.2))
	_crate(Vector3(9.8, 0, 3.7), Vector3(1.4, 0.9, 1.0))
	_crate(Vector3(7.4, 0, 5.7), Vector3(1.0, 0.9, 1.0))
	solid(Vector3(11.2, 0, 1.0), Vector3(1.2, 1.8, 1.4), C_WOOD_DARK, Bullet.LAYER_WORLD, true)
	deco(Models.box(Vector3(1.0, 0.7, 1.1)), Toon.prop_outlined(C_WOOD), Vector3(11.2, 2.15, 1.0), Vector3(0, 12, 0))
	# 罐头托盘
	solid(Vector3(6.0, 0, 7.3), Vector3(1.0, 0.25, 1.0), C_WOOD, Bullet.LAYER_LOWCOVER)
	for i in 3:
		for j in 3:
			deco(Models.cyl(0.13, 0.13, 0.26), Toon.prop_outlined(Pal.ORANGE), Vector3(5.7 + i * 0.3, 0.38, 7.0 + j * 0.3))
	label("仓库", Vector3(8.5, 0.03, 7.4), 72, Color(1, 1, 1, 0.35), Vector3(-90, 0, 0), null, 0.008)


func _crate(pos: Vector3, size: Vector3) -> void:
	solid(pos, size, C_WOOD, Bullet.LAYER_LOWCOVER, true)
	deco(Models.box(Vector3(size.x + 0.02, 0.1, size.z + 0.02)), Toon.prop(C_WOOD_DARK), pos + Vector3(0, size.y * 0.35, 0))
	deco(Models.box(Vector3(size.x + 0.02, 0.1, size.z + 0.02)), Toon.prop(C_WOOD_DARK), pos + Vector3(0, size.y * 0.8, 0))
	label("喵", pos + Vector3(0, size.y + 0.01, 0), 96, Color(0.3, 0.18, 0.08, 0.6), Vector3(-90, 0, 0), null, 0.006)


func _staff() -> void:
	# 桌子（低矮掩体）+ 零食
	solid(Vector3(8.0, 0, -6.5), Vector3(1.8, 0.8, 1.0), C_WOOD_DARK, Bullet.LAYER_LOWCOVER, true)
	for k in 5:
		product(Vector3(7.4 + k * 0.3, 0.88, -6.4 + (k % 2) * 0.2), Vector3(0.22, 0.12, 0.18), Pal.PRODUCTS[k])
	# 沙发
	solid(Vector3(8.4, 0, -9.3), Vector3(3.0, 0.75, 0.9), Color("2A9D8F"), Bullet.LAYER_LOWCOVER, true)
	deco(Models.box(Vector3(3.0, 0.5, 0.25)), Toon.prop_outlined(Color("23867A")), Vector3(8.4, 1.0, -9.68))
	# 储物柜
	solid(Vector3(11.5, 0, -4.2), Vector3(0.7, 2.0, 3.0), Color("6C7A99"), Bullet.LAYER_WORLD, true)
	for k in 4:
		deco(Models.box(Vector3(0.04, 1.7, 0.02)), Toon.prop(Color("3D4766")), Vector3(11.14, 1.0, -5.6 + k * 0.75 + 0.37))
	# 电视
	solid(Vector3(5.7, 0, -8.3), Vector3(0.7, 0.55, 1.5), C_WOOD, Bullet.LAYER_LOWCOVER, true)
	deco(Models.box(Vector3(0.1, 0.7, 1.2)), Toon.prop(Color("1A1D27")), Vector3(5.6, 0.95, -8.3))
	deco(Models.box(Vector3(0.02, 0.6, 1.1)), Toon.glow(Color("6FB7FF"), 1.4), Vector3(5.66, 0.95, -8.3))
	# 员工守则
	deco(Models.box(Vector3(1.4, 0.9, 0.04)), Toon.prop(Pal.CREAM), Vector3(10.0, 1.6, -9.82))
	label("员工守则\n1. 微笑服务\n2. 不许偷吃罐头", Vector3(10.0, 1.6, -9.79), 32, Pal.INK, Vector3.ZERO, null, 0.004)
	label("员工休息室", Vector3(8.5, 0.03, -3.0), 64, Color(1, 1, 1, 0.3), Vector3(-90, 0, 0), null, 0.008)


func _street() -> void:
	# 警车
	car = Node3D.new()
	car.position = Vector3(-6.5, 0, 13.4)
	root.add_child(car)
	car_body = solid(Vector3(-6.5, 0, 13.4), Vector3(4.3, 1.4, 2.0), Color.BLACK, Bullet.LAYER_WORLD, false, false)
	deco(Models.box(Vector3(4.3, 0.55, 2.0)), Toon.prop_outlined(Pal.NAVY), Vector3(0, 0.55, 0), Vector3.ZERO, Vector3.ONE, car)
	deco(Models.box(Vector3(4.32, 0.18, 2.02)), Toon.prop(Pal.CREAM), Vector3(0, 0.62, 0), Vector3.ZERO, Vector3.ONE, car)
	deco(Models.box(Vector3(2.3, 0.6, 1.8)), Toon.prop_outlined(Pal.CREAM), Vector3(-0.2, 1.1, 0), Vector3.ZERO, Vector3.ONE, car)
	deco(Models.box(Vector3(2.0, 0.42, 1.84)), Toon.prop(Color("223355")), Vector3(-0.2, 1.12, 0), Vector3.ZERO, Vector3.ONE, car)
	for wx in [-1.4, 1.4]:
		for wz in [-1.0, 1.0]:
			deco(Models.cyl(0.36, 0.36, 0.3), Toon.prop(Color("15171C")), Vector3(wx, 0.36, wz), Vector3(90, 0, 0), Vector3.ONE, car)
	var red := deco(Models.box(Vector3(0.5, 0.16, 0.5)), Toon.glow(Color(1, 0.2, 0.25), 2.5), Vector3(-0.5, 1.5, 0), Vector3.ZERO, Vector3.ONE, car)
	var blue := deco(Models.box(Vector3(0.5, 0.16, 0.5)), Toon.glow(Color(0.2, 0.45, 1.0), 2.5), Vector3(0.1, 1.5, 0), Vector3.ZERO, Vector3.ONE, car)
	car_bulbs = [red, blue]
	var lr := light(Vector3(-7.0, 2.0, 13.4), Color(1, 0.2, 0.25), 3.0, 7.0)
	var lb := light(Vector3(-6.4, 2.0, 13.4), Color(0.2, 0.45, 1.0), 3.0, 7.0)
	car_lights = [lr, lb]
	var side := label("P.A.W. 特警", Vector3(-6.5, 0.6, 14.42), 72, Pal.CREAM, Vector3.ZERO, Style.title_font(), 0.006)
	side.outline_size = 0
	# 车身字跟着车走（小米上车后警车会开走）
	side.get_parent().remove_child(side)
	car.add_child(side)
	side.position = Vector3(0, 0.6, 1.02)
	# 路灯
	for lx in [-11.5, 11.5]:
		deco(Models.cyl(0.07, 0.09, 3.6), Toon.prop(Color("2B3245")), Vector3(lx, 1.8, 9.6))
		deco(Models.box(Vector3(0.9, 0.12, 0.3)), Toon.prop(Color("2B3245")), Vector3(lx - 0.4 * signf(lx), 3.6, 9.6))
		deco(Models.box(Vector3(0.5, 0.08, 0.25)), Toon.glow(Color(1.0, 0.8, 0.5), 2.5), Vector3(lx - 0.7 * signf(lx), 3.53, 9.6))
		light(Vector3(lx - 0.7 * signf(lx), 3.2, 9.8), Color(1.0, 0.72, 0.42), 2.4, 8.5)
	# 消防栓 / 垃圾桶 / 隔离桩
	deco(Models.cyl(0.16, 0.2, 0.6), Toon.prop_outlined(Pal.RED), Vector3(6.0, 0.3, 9.4))
	deco(Models.sphere(0.16), Toon.prop_outlined(Pal.RED), Vector3(6.0, 0.62, 9.4))
	solid(Vector3(-3.6, 0, 9.3), Vector3(0.7, 0.9, 0.7), Color("3F8F5A"), Bullet.LAYER_LOWCOVER, true)
	deco(Models.box(Vector3(0.78, 0.1, 0.78)), Toon.prop(Color("2F6E45")), Vector3(-3.6, 0.95, 9.3))
	for bx in [-9.0, -8.0, 3.5, 8.5, 9.5]:
		deco(Models.cyl(0.1, 0.12, 0.7), Toon.prop_outlined(Pal.YELLOW), Vector3(bx, 0.35, 10.3))
	# 招牌
	for sx in [-2.4, 2.4]:
		deco(Models.cyl(0.06, 0.06, 2.9), Toon.prop(C_CAP), Vector3(sx, 1.45, 8.35))
	deco(Models.box(Vector3(5.4, 0.95, 0.18)), Toon.prop_outlined(Color("241A3A")), Vector3(0, 3.0, 8.35))
	var sign := label("喵喵便利店", Vector3(-0.55, 3.02, 8.46), 96, Color(1.0, 0.45, 0.75) * 2.2, Vector3.ZERO, Style.title_font(), 0.007)
	sign.outline_size = 0
	var h24 := label("24H", Vector3(1.95, 3.0, 8.46), 80, Pal.TEAL * 2.0, Vector3.ZERO, Style.num_font(), 0.007)
	h24.outline_size = 0
	light(Vector3(0, 2.6, 9.4), Color(1.0, 0.5, 0.8), 1.8, 6.0)
	# 不可见边界
	barrier(-14.5, 8, -14.5, 18.5)
	barrier(14.5, 8, 14.5, 18.5)
	barrier(-14.5, 18.5, 14.5, 18.5)
	barrier(-14.5, 8, -12, 8)
	barrier(12, 8, 14.5, 8)


func _lights() -> void:
	for p in [Vector3(-9, 3.2, -2.5), Vector3(-4, 3.2, -2.5), Vector3(0.5, 3.2, -2), Vector3(-9, 3.2, 4), Vector3(-4, 3.2, 4), Vector3(2, 3.2, 5)]:
		light(p, Color(0.88, 0.93, 1.0), 0.85, 7.0)
	light(Vector3(7.5, 3.0, 3.5), Color(1.0, 0.85, 0.62), 1.3, 6.5)
	light(Vector3(10.5, 3.0, 5.5), Color(1.0, 0.85, 0.62), 1.0, 5.5)
	flicker_light = light(Vector3(8.5, 3.0, -5.0), Color(1.0, 0.75, 0.45), 1.6, 8.0)
