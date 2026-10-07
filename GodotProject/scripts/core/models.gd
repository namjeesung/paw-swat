class_name Models
## 角色建模工厂：全部由基础几何体拼成，后续可整体替换为美术模型。
## 约定：模型面朝 +Z。

static var _mesh_cache := {}


## 面数随大小变化：角色在屏幕上只有几十像素高，眼睛、鼻头这种小球 6 段就够圆了
static func sphere(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if not _mesh_cache.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12 if r >= 0.15 else (8 if r >= 0.06 else 6)
		s.rings = s.radial_segments / 2
		_mesh_cache[key] = s
	return _mesh_cache[key]


static func capsule(r: float, h: float) -> CapsuleMesh:
	var key := "c%.3f_%.3f" % [r, h]
	if not _mesh_cache.has(key):
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = maxf(h, r * 2.0)
		c.radial_segments = 12
		c.rings = 2
		_mesh_cache[key] = c
	return _mesh_cache[key]


static func box(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _mesh_cache.has(key):
		var b := BoxMesh.new()
		b.size = size
		_mesh_cache[key] = b
	return _mesh_cache[key]


static func cyl(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var key := "y%.3f_%.3f_%.3f_%d" % [top, bottom, h, seg]
	if not _mesh_cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_mesh_cache[key] = c
	return _mesh_cache[key]


static func prism(size: Vector3) -> PrismMesh:
	var key := "p%s" % size
	if not _mesh_cache.has(key):
		var p := PrismMesh.new()
		p.size = size
		_mesh_cache[key] = p
	return _mesh_cache[key]


static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "t%.3f_%.3f" % [inner, outer]
	if not _mesh_cache.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 16
		t.ring_segments = 6
		_mesh_cache[key] = t
	return _mesh_cache[key]


## 扁平五角星（晕倒星星、枪口火光）
static func star(r_out := 0.12, r_in := 0.05, thickness := 0.03) -> ArrayMesh:
	var key := "star%.3f_%.3f_%.3f" % [r_out, r_in, thickness]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var r := r_out if i % 2 == 0 else r_in
		var a := -PI / 2 + PI * i / 5.0
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0))
	var h := thickness * 0.5
	for side in [1.0, -1.0]:
		var n := Vector3(0, 0, side)
		for i in 10:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % 10]
			st.set_normal(n)
			st.add_vertex(Vector3(0, 0, h * side))
			if side > 0:
				st.add_vertex(b + Vector3(0, 0, h * side))
				st.add_vertex(a + Vector3(0, 0, h * side))
			else:
				st.add_vertex(a + Vector3(0, 0, h * side))
				st.add_vertex(b + Vector3(0, 0, h * side))
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


static func _eye(c: CharModel, parent: Node3D, pos: Vector3, r: float, black: Material, white: Material) -> void:
	c.part(parent, sphere(r), black, pos)
	c.part(parent, sphere(r * 0.34), white, pos + Vector3(r * 0.35, r * 0.4, r * 0.75))


# ---------------------------------------------------------------- 柴犬 · 豆包
static func shiba() -> CharModel:
	var c := CharModel.new()
	c.name = "Shiba"
	c.outline_color = Pal.OUTLINE_HERO
	var fur := c.m(Pal.SHIBA)
	var cream := c.m(Pal.SHIBA_CREAM)
	var vest := c.m(Pal.NAVY)
	var dark := c.m(Color("2A2E38"))
	var orange := c.m(Pal.ORANGE)
	var yellow := c.m(Pal.YELLOW)
	var black := c.m(Color("17181D"), false)
	var white := c.m(Color.WHITE, false)

	c.add_feet(fur, 0.12, 0.14)
	var b := c.body
	c.part(b, capsule(0.27, 0.72), vest, Vector3(0, 0.5, 0))
	c.part(b, sphere(0.2), cream, Vector3(0, 0.8, 0.07), Vector3.ZERO, Vector3(1.2, 0.55, 1.0))
	c.part(b, box(Vector3(0.4, 0.07, 0.07)), orange, Vector3(0, 0.38, 0.24))
	c.part(b, box(Vector3(0.14, 0.12, 0.06)), dark, Vector3(0.1, 0.48, 0.25))
	c.part(b, cyl(0.055, 0.055, 0.03), yellow, Vector3(-0.12, 0.64, 0.245), Vector3(90, 0, 0))
	var back := Label3D.new()
	back.text = "PAW"
	back.font = Style.num_font()
	back.font_size = 40
	back.pixel_size = 0.004
	back.modulate = Pal.CREAM
	back.outline_size = 0
	back.position = Vector3(0, 0.56, -0.275)
	back.rotation_degrees = Vector3(0, 180, 0)
	b.add_child(back)
	# 手臂
	c.part(b, capsule(0.075, 0.34), fur, Vector3(0.25, 0.56, 0.12), Vector3(70, 0, -8))
	c.part(b, capsule(0.075, 0.34), fur, Vector3(-0.2, 0.56, 0.18), Vector3(75, 0, 30))
	# 步枪
	var g := c.node(b, Vector3(0.08, 0.66, 0.3), "Gun")
	c.part(g, box(Vector3(0.11, 0.14, 0.52)), dark, Vector3(0, 0, 0.08))
	c.part(g, box(Vector3(0.08, 0.17, 0.09)), dark, Vector3(0, -0.13, 0.08), Vector3(-12, 0, 0))
	c.part(g, box(Vector3(0.115, 0.04, 0.28)), orange, Vector3(0, 0.07, 0.04))
	c.part(g, cyl(0.032, 0.032, 0.2), dark, Vector3(0, 0.01, 0.42), Vector3(90, 0, 0))
	c.part(g, box(Vector3(0.09, 0.1, 0.18)), dark, Vector3(0, -0.02, -0.24))
	c.muzzle = Marker3D.new()
	c.muzzle.position = Vector3(0, 0.01, 0.54)
	g.add_child(c.muzzle)
	c.set_gun(g)
	# 头
	c.head = c.node(b, Vector3(0, 1.0, 0), "Head")
	var h := c.head
	c.part(h, sphere(0.36), fur, Vector3.ZERO, Vector3.ZERO, Vector3(1.08, 0.94, 1.0))
	c.part(h, sphere(0.26), cream, Vector3(0, -0.11, 0.16), Vector3.ZERO, Vector3(1.18, 0.72, 0.85))
	c.part(h, sphere(0.14), cream, Vector3(0, -0.07, 0.31), Vector3.ZERO, Vector3(1.15, 0.8, 0.9))
	c.part(h, sphere(0.052), black, Vector3(0, -0.02, 0.44))
	_eye(c, h, Vector3(-0.14, 0.05, 0.3), 0.056, black, white)
	_eye(c, h, Vector3(0.14, 0.05, 0.3), 0.056, black, white)
	c.part(h, sphere(0.045), cream, Vector3(-0.13, 0.17, 0.3), Vector3.ZERO, Vector3(1.1, 0.6, 0.6))
	c.part(h, sphere(0.045), cream, Vector3(0.13, 0.17, 0.3), Vector3.ZERO, Vector3(1.1, 0.6, 0.6))
	for sx in [-1.0, 1.0]:
		c.part(h, prism(Vector3(0.22, 0.26, 0.1)), fur, Vector3(0.2 * sx, 0.31, -0.03), Vector3(0, 0, -14 * sx))
		c.part(h, prism(Vector3(0.12, 0.15, 0.04)), cream, Vector3(0.2 * sx, 0.29, 0.03), Vector3(0, 0, -14 * sx))
	# 小警帽
	c.part(h, cyl(0.2, 0.26, 0.1), vest, Vector3(0, 0.29, -0.02), Vector3(-8, 0, 0))
	c.part(h, box(Vector3(0.3, 0.025, 0.14)), vest, Vector3(0, 0.25, 0.22), Vector3(-10, 0, 0))
	c.part(h, cyl(0.04, 0.04, 0.02), yellow, Vector3(0, 0.3, 0.2), Vector3(70, 0, 0))
	# 卷尾巴
	c.tail = c.node(b, Vector3(0, 0.62, -0.27), "Tail")
	c.part(c.tail, torus(0.045, 0.13), fur, Vector3(0, 0.05, -0.04), Vector3(0, 0, 90))
	c.part(c.tail, sphere(0.05), cream, Vector3(0, 0.05, -0.04))
	return c


# ---------------------------------------------------------------- 浣熊 · 打手
static func raccoon(boss := false) -> CharModel:
	var c := CharModel.new()
	c.name = "Raccoon"
	c.outline_color = Pal.OUTLINE_ENEMY
	var fur := c.m(Pal.RACCOON)
	var mask := c.m(Color("25222D"))
	var shirt := c.m(Pal.PURPLE if not boss else Color("3B2A5E"))
	var stripe := c.m(Pal.CREAM)
	var beanie := c.m(Pal.PURPLE_DARK if not boss else Pal.RED)
	var white := c.m(Color.WHITE, false)
	var black := c.m(Color("141418"), false)
	var dark := c.m(Color("30333C"))

	c.add_feet(mask, 0.12, 0.14)
	var b := c.body
	c.part(b, capsule(0.28, 0.72), shirt, Vector3(0, 0.5, 0))
	c.part(b, torus(0.262, 0.298), stripe, Vector3(0, 0.42, 0))
	c.part(b, torus(0.27, 0.303), stripe, Vector3(0, 0.58, 0))
	c.part(b, capsule(0.075, 0.32), fur, Vector3(0.26, 0.55, 0.1), Vector3(70, 0, -8))
	c.part(b, capsule(0.075, 0.32), fur, Vector3(-0.22, 0.55, 0.14), Vector3(70, 0, 25))
	var g := c.node(b, Vector3(0.1, 0.64, 0.3), "Gun")
	c.part(g, box(Vector3(0.09, 0.12, 0.34)), dark, Vector3(0, 0, 0.04))
	c.part(g, box(Vector3(0.07, 0.15, 0.08)), dark, Vector3(0, -0.11, -0.04), Vector3(-15, 0, 0))
	c.part(g, box(Vector3(0.095, 0.03, 0.2)), beanie, Vector3(0, 0.07, 0.0))
	c.muzzle = Marker3D.new()
	c.muzzle.position = Vector3(0, 0, 0.24)
	g.add_child(c.muzzle)
	c.set_gun(g)
	c.add_handcuffs(Vector3(0, 0.45, 0.28))

	c.head = c.node(b, Vector3(0, 1.0, 0), "Head")
	var h := c.head
	c.part(h, sphere(0.34), fur)
	c.part(h, sphere(0.347), mask, Vector3(0, 0.03, 0.0), Vector3.ZERO, Vector3(1.0, 0.33, 1.0))
	c.part(h, sphere(0.075), white, Vector3(-0.13, 0.04, 0.29))
	c.part(h, sphere(0.075), white, Vector3(0.13, 0.04, 0.29))
	c.part(h, sphere(0.04), black, Vector3(-0.12, 0.04, 0.355))
	c.part(h, sphere(0.04), black, Vector3(0.12, 0.04, 0.355))
	c.part(h, box(Vector3(0.13, 0.035, 0.04)), mask, Vector3(-0.13, 0.14, 0.3), Vector3(0, 0, -18))
	c.part(h, box(Vector3(0.13, 0.035, 0.04)), mask, Vector3(0.13, 0.14, 0.3), Vector3(0, 0, 18))
	c.part(h, sphere(0.15), white, Vector3(0, -0.13, 0.25), Vector3.ZERO, Vector3(1.1, 0.7, 0.9))
	c.part(h, sphere(0.045), black, Vector3(0, -0.09, 0.39))
	for sx in [-1.0, 1.0]:
		c.part(h, sphere(0.1), fur, Vector3(0.27 * sx, 0.2, 0.0), Vector3.ZERO, Vector3(1, 1, 0.45))
		c.part(h, sphere(0.06), mask, Vector3(0.27 * sx, 0.2, 0.035), Vector3.ZERO, Vector3(1, 1, 0.3))
	c.part(h, sphere(0.3), beanie, Vector3(0, 0.17, -0.03), Vector3.ZERO, Vector3(1.04, 0.62, 1.04))
	c.part(h, sphere(0.075), stripe, Vector3(0, 0.38, -0.05))
	if boss:
		c.part(h, box(Vector3(0.5, 0.04, 0.04)), stripe, Vector3(0, 0.1, 0.24), Vector3(-25, 0, 0))

	c.tail = c.node(b, Vector3(0, 0.42, -0.26), "Tail")
	var rs := [0.11, 0.1, 0.095, 0.085, 0.07]
	for i in rs.size():
		c.part(c.tail, sphere(rs[i]), fur if i % 2 == 0 else mask, Vector3(0, i * 0.06, -i * 0.11))
	return c


# ---------------------------------------------------------------- 老鼠 · 小毛贼
static func rat() -> CharModel:
	var c := CharModel.new()
	c.name = "Rat"
	c.outline_color = Pal.OUTLINE_ENEMY
	var fur := c.m(Pal.RAT)
	var belly := c.m(Color("D9CBB8"))
	var pink := c.m(Color("FF9DB0"))
	var band := c.m(Pal.PURPLE)
	var wood := c.m(Color("A0703C"))
	var black := c.m(Color("141418"), false)
	var white := c.m(Color.WHITE, false)

	c.pose.scale = Vector3.ONE * 0.85
	c.add_feet(pink, 0.1, 0.12)
	var b := c.body
	c.part(b, capsule(0.24, 0.6), fur, Vector3(0, 0.42, 0))
	c.part(b, sphere(0.17), belly, Vector3(0, 0.38, 0.12), Vector3.ZERO, Vector3(1, 1.2, 0.6))
	c.part(b, torus(0.17, 0.24), band, Vector3(0, 0.66, 0))
	c.part(b, prism(Vector3(0.16, 0.18, 0.05)), band, Vector3(0, 0.6, -0.22), Vector3(180, 0, 0))
	c.part(b, capsule(0.065, 0.28), fur, Vector3(-0.22, 0.48, 0.08), Vector3(60, 0, 20))
	var g := c.node(b, Vector3(0.2, 0.5, 0.12), "Bat")
	c.part(g, capsule(0.05, 0.6), wood, Vector3(0, 0.18, 0.08), Vector3(35, 0, 0))
	c.part(g, capsule(0.065, 0.065), fur, Vector3.ZERO)
	c.muzzle = Marker3D.new()
	c.muzzle.position = Vector3(0, 0.35, 0.3)
	g.add_child(c.muzzle)
	c.set_gun(g)
	c.add_handcuffs(Vector3(0, 0.38, 0.24))

	c.head = c.node(b, Vector3(0, 0.86, 0), "Head")
	var h := c.head
	c.part(h, sphere(0.28), fur)
	c.part(h, cyl(0.03, 0.14, 0.26), fur, Vector3(0, -0.05, 0.28), Vector3(90, 0, 0))
	c.part(h, sphere(0.05), pink, Vector3(0, -0.05, 0.42))
	_eye(c, h, Vector3(-0.1, 0.06, 0.22), 0.046, black, white)
	_eye(c, h, Vector3(0.1, 0.06, 0.22), 0.046, black, white)
	for sx in [-1.0, 1.0]:
		c.part(h, cyl(0.15, 0.15, 0.03), fur, Vector3(0.21 * sx, 0.22, -0.02), Vector3(90, 0, 0))
		c.part(h, cyl(0.1, 0.1, 0.02), pink, Vector3(0.21 * sx, 0.22, 0.0), Vector3(90, 0, 0))
	c.tail = c.node(b, Vector3(0, 0.25, -0.22), "Tail")
	for i in 6:
		var a := i * 0.45
		c.part(c.tail, sphere(0.04), pink, Vector3(sin(a) * 0.08, i * 0.05, -i * 0.08))
	return c


# ---------------------------------------------------------------- 仓鼠 · 小米（人质）
static func hamster() -> CharModel:
	var c := CharModel.new()
	c.name = "Hamster"
	c.outline_color = Pal.OUTLINE_CIVIL
	var fur := c.m(Pal.HAMSTER)
	var cream := c.m(Color("FFF1DC"))
	var apron := c.m(Color("3BB273"))
	var pink := c.m(Color("FFAABB"))
	var black := c.m(Color("141418"), false)
	var white := c.m(Color.WHITE, false)

	c.add_feet(pink, 0.08, 0.13)
	var b := c.body
	c.part(b, sphere(0.36), fur, Vector3(0, 0.36, 0), Vector3.ZERO, Vector3(1, 0.95, 1))
	c.part(b, sphere(0.27), cream, Vector3(0, 0.32, 0.14), Vector3.ZERO, Vector3(1, 1, 0.6))
	c.part(b, box(Vector3(0.36, 0.28, 0.04)), apron, Vector3(0, 0.3, 0.31), Vector3(-8, 0, 0))
	c.part(b, box(Vector3(0.12, 0.05, 0.01)), white, Vector3(0.08, 0.38, 0.335), Vector3(-8, 0, 0))
	c.part(b, sphere(0.08), fur, Vector3(-0.3, 0.42, 0.12))
	c.part(b, sphere(0.08), fur, Vector3(0.3, 0.42, 0.12))
	c.head = c.node(b, Vector3(0, 0.8, 0), "Head")
	var h := c.head
	c.part(h, sphere(0.3), fur)
	c.part(h, sphere(0.14), cream, Vector3(-0.16, -0.07, 0.17))
	c.part(h, sphere(0.14), cream, Vector3(0.16, -0.07, 0.17))
	_eye(c, h, Vector3(-0.11, 0.04, 0.26), 0.05, black, white)
	_eye(c, h, Vector3(0.11, 0.04, 0.26), 0.05, black, white)
	c.part(h, sphere(0.035), pink, Vector3(0, -0.03, 0.3))
	for sx in [-1.0, 1.0]:
		c.part(h, sphere(0.085), fur, Vector3(0.19 * sx, 0.23, 0), Vector3.ZERO, Vector3(1, 1, 0.5))
		c.part(h, sphere(0.05), pink, Vector3(0.19 * sx, 0.23, 0.03), Vector3.ZERO, Vector3(1, 1, 0.3))
	return c


# ---------------------------------------------------------------- 僵尸鼠（可爱款）
static func zombie(boss := false) -> CharModel:
	var c := CharModel.new()
	c.name = "Zombie"
	c.outline_color = Color("1E4D32")
	var skin := c.m(Color("9EE6B8") if not boss else Color("8FD9A8"))
	var belly := c.m(Color("D4F7DF"))
	var pink := c.m(Color("FF9DB0"))
	var band := c.m(Pal.PURPLE)
	var white := c.m(Color.WHITE, false)
	var black := c.m(Color("141418"), false)
	var bandage := c.m(Color("FFF1D6"))

	c.add_feet(skin, 0.1, 0.13)
	var b := c.body
	c.part(b, sphere(0.36), skin, Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1, 0.95, 0.95))
	c.part(b, sphere(0.25), belly, Vector3(0, 0.36, 0.17), Vector3.ZERO, Vector3(1, 1.05, 0.55))
	c.part(b, torus(0.2, 0.26), band, Vector3(0, 0.66, 0))
	# 伸直的小短手
	c.part(b, capsule(0.075, 0.38), skin, Vector3(-0.2, 0.55, 0.28), Vector3(85, 0, 0))
	c.part(b, capsule(0.075, 0.38), skin, Vector3(0.2, 0.58, 0.28), Vector3(80, 0, 0))
	c.add_handcuffs(Vector3(0, 0.4, 0.3))

	c.head = c.node(b, Vector3(0, 0.88, 0.02), "Head")
	var h := c.head
	c.part(h, sphere(0.31), skin)
	# 一大一小的呆萌眼睛
	c.part(h, sphere(0.1), white, Vector3(-0.12, 0.05, 0.25))
	c.part(h, sphere(0.04), black, Vector3(-0.1, 0.03, 0.34))
	c.part(h, sphere(0.075), white, Vector3(0.13, 0.08, 0.26))
	c.part(h, sphere(0.032), black, Vector3(0.15, 0.1, 0.32))
	# 缝线小嘴 + 吐舌头
	c.part(h, box(Vector3(0.16, 0.02, 0.02)), black, Vector3(0, -0.1, 0.29))
	for i in 3:
		c.part(h, box(Vector3(0.015, 0.06, 0.02)), black, Vector3(-0.05 + i * 0.05, -0.1, 0.295))
	c.part(h, sphere(0.045), pink, Vector3(0.05, -0.14, 0.27), Vector3.ZERO, Vector3(1, 0.7, 0.6))
	c.part(h, sphere(0.04), pink, Vector3(0, -0.02, 0.32))
	for sx in [-1.0, 1.0]:
		c.part(h, cyl(0.13, 0.13, 0.03), skin, Vector3(0.22 * sx, 0.22, -0.02), Vector3(90, 0, 0))
		c.part(h, cyl(0.085, 0.085, 0.02), pink, Vector3(0.22 * sx, 0.22, 0.0), Vector3(90, 0, 0))
	# 头顶创可贴
	c.part(h, box(Vector3(0.24, 0.06, 0.03)), bandage, Vector3(0.08, 0.25, 0.14), Vector3(-30, 0, 30))
	c.part(h, box(Vector3(0.24, 0.06, 0.03)), bandage, Vector3(0.08, 0.25, 0.14), Vector3(-30, 0, -30))
	if boss:
		var gold := c.m(Pal.YELLOW)
		c.part(h, cyl(0.17, 0.19, 0.12), gold, Vector3(0, 0.33, -0.02))
		for i in 5:
			var a := TAU * i / 5.0
			c.part(h, prism(Vector3(0.08, 0.12, 0.04)), gold, Vector3(cos(a) * 0.15, 0.44, sin(a) * 0.15 - 0.02), Vector3(0, -rad_to_deg(a) + 90, 0))
	c.tail = c.node(b, Vector3(0, 0.3, -0.3), "Tail")
	c.part(c.tail, torus(0.03, 0.08), skin, Vector3(0, 0.05, -0.04), Vector3(0, 0, 90))
	return c


## 僵尸被打败后飘走的小幽灵
static func ghost() -> Node3D:
	var g := Node3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var body := MeshInstance3D.new()
	body.mesh = sphere(0.22)
	body.material_override = m
	body.scale = Vector3(1, 1.2, 1)
	g.add_child(body)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Pal.INK
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = sphere(0.035)
		e.material_override = em
		e.position = Vector3(0.07 * sx, 0.04, 0.2)
		g.add_child(e)
	return g
