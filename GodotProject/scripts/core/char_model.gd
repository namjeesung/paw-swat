class_name CharModel
extends Node3D
## 程序化 Q 版角色模型。负责走路摇摆、受击闪白/挤压、枪后坐等“手感”动画。
## 层级：CharModel(朝向) → pose(倒地/翻滚) → body(上半身摇摆) / feet

var pose: Node3D
var body: Node3D
var head: Node3D
var gun: Node3D
var muzzle: Marker3D
var foot_l: Node3D
var foot_r: Node3D
var tail: Node3D
var handcuffs: Node3D
var mats: Array[StandardMaterial3D] = []
var outline_color := Pal.OUTLINE_PROP

var crouch := 0.0
var tail_wag := 1.0
var gun_kick := 0.0

var _walk := 0.0
var _time := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _flash_dirty := false
var _squash := 0.0
var _gun_rest := Vector3.ZERO
var _foot_base := Vector3(0.14, 0.1, 0.02)


func _init() -> void:
	pose = Node3D.new()
	pose.name = "Pose"
	add_child(pose)
	body = Node3D.new()
	body.name = "Body"
	pose.add_child(body)


## 创建并登记一个角色材质（登记后可统一闪白/改描边）
func m(color: Color, outline := true) -> StandardMaterial3D:
	var mt := Toon.mat(color, outline, outline_color, 0.024)
	mats.append(mt)
	return mt


func part(parent: Node3D, mesh: Mesh, mt: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mt
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


func node(parent: Node3D, pos: Vector3, n := "") -> Node3D:
	var nd := Node3D.new()
	if n != "":
		nd.name = n
	nd.position = pos
	parent.add_child(nd)
	return nd


func add_feet(mt: Material, r := 0.12, spread := 0.14) -> void:
	_foot_base = Vector3(spread, r * 0.85, 0.02)
	foot_l = node(pose, Vector3(-spread, _foot_base.y, _foot_base.z), "FootL")
	foot_r = node(pose, Vector3(spread, _foot_base.y, _foot_base.z), "FootR")
	part(foot_l, Models.sphere(r), mt, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.8, 1.35))
	part(foot_r, Models.sphere(r), mt, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.8, 1.35))


func set_gun(g: Node3D) -> void:
	gun = g
	_gun_rest = g.position


func add_handcuffs(at: Vector3) -> void:
	handcuffs = node(body, at, "Cuffs")
	var steel := Toon.mat(Color("D9E2EC"), true, Pal.OUTLINE_PROP, 0.012, 0.6)
	steel.metallic = 0.6
	part(handcuffs, Models.torus(0.035, 0.07), steel, Vector3(-0.07, 0, 0), Vector3(90, 0, 0))
	part(handcuffs, Models.torus(0.035, 0.07), steel, Vector3(0.07, 0, 0), Vector3(90, 0, 0))
	part(handcuffs, Models.box(Vector3(0.08, 0.015, 0.015)), steel, Vector3.ZERO)
	handcuffs.visible = false


## ---------------------------------------------------------------- 烘焙合批（性能关键）
## 角色由几十个小几何体拼成。原来每个零件 = 1 次绘制 + 1 次描边绘制，一个角色 50~60 次，
## 场上 40 个角色就是 2000+ 次绘制，手机和网页直接卡死。
## 烘焙：把同一个「会动的节点」（Pose / Body / Head / Gun / 脚 / 尾巴 / 手铐）下面的所有零件
## 合成一个网格，颜色写进顶点色，整个角色只用两个材质（有描边 / 无描边）。
## 动画、闪白、改描边、残影都照常工作；同一种角色的网格全局缓存，生成僵尸时没有额外开销。
static var _bake_cache := {}
var _baked := false


func _ready() -> void:
	bake()


func bake() -> void:
	if _baked:
		return
	_baked = true
	var vm_o := Toon.mat(Color.WHITE, true, outline_color, 0.024)
	var vm_n := Toon.mat(Color.WHITE, false)
	for vm in [vm_o, vm_n]:
		vm.vertex_color_use_as_albedo = true
		vm.vertex_color_is_srgb = true
	var used := false
	# 先收集「挂零件的节点」（不含零件本身），合并时会释放零件
	var nodes: Array[Node] = [self]
	for n in find_children("*", "Node3D", true, false):
		if not (n is MeshInstance3D):
			nodes.append(n)
	for n in nodes:
		var groups := {true: [], false: []}
		for ch in n.get_children():
			var mi := ch as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible or mi.get_child_count() > 0:
				continue
			var mt := mi.material_override as StandardMaterial3D
			if mt == null or not mats.has(mt):
				continue
			groups[mt.next_pass != null].append(mi)
		for outlined in groups:
			var parts: Array = groups[outlined]
			if parts.is_empty():
				continue
			var merged := MeshInstance3D.new()
			merged.name = "Baked" + ("O" if outlined else "N")
			merged.mesh = _baked_mesh(parts)
			merged.material_override = vm_o if outlined else vm_n
			n.add_child(merged)
			for part: MeshInstance3D in parts:
				n.remove_child(part)
				part.free()
			used = true
	if used:
		# 之后闪白 / 改描边只需要改这两个材质
		mats = [vm_o, vm_n]


static func _baked_mesh(parts: Array) -> ArrayMesh:
	var key_parts := PackedStringArray()
	for part: MeshInstance3D in parts:
		var mt := part.material_override as StandardMaterial3D
		key_parts.append("%d|%s|%s" % [part.mesh.get_rid().get_id(), part.transform, mt.albedo_color.to_html()])
	var key := "|".join(key_parts).hash()
	if _bake_cache.has(key):
		return _bake_cache[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for part: MeshInstance3D in parts:
		var xf := part.transform
		var nb := xf.basis.inverse().transposed()
		var col := (part.material_override as StandardMaterial3D).albedo_color
		for si in part.mesh.get_surface_count():
			var arr := part.mesh.surface_get_arrays(si)
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
	_bake_cache[key] = mesh
	return mesh


## 每帧由角色驱动：move01 = 当前速度占最大速度比例
func animate(delta: float, move01: float) -> void:
	_time += delta
	_walk += delta * (4.0 + 11.0 * move01)
	var s := sin(_walk)
	var breathe := 1.0 + sin(_time * 3.2) * 0.018 * (1.0 - move01)
	body.position.y = absf(s) * 0.07 * move01 - crouch * 0.17
	body.rotation.z = s * 0.075 * move01
	body.rotation.x = 0.1 * move01 + crouch * 0.25
	if foot_l:
		foot_l.position.z = _foot_base.z + s * 0.17 * move01
		foot_l.position.y = _foot_base.y + maxf(0.0, s) * 0.07 * move01
		foot_r.position.z = _foot_base.z - s * 0.17 * move01
		foot_r.position.y = _foot_base.y + maxf(0.0, -s) * 0.07 * move01
	if tail:
		tail.rotation.y = sin(_time * lerpf(3.0, 13.0, tail_wag)) * 0.35 * maxf(tail_wag, 0.3)
	_squash = move_toward(_squash, 0.0, delta * 1.6)
	var sq := sin(_squash * 9.0) * _squash
	body.scale = Vector3(1.0 + sq, (1.0 - sq) * breathe, 1.0 + sq)
	if gun:
		gun_kick = move_toward(gun_kick, 0.0, delta * 1.4)
		gun.position = _gun_rest + Vector3(0, gun_kick * 0.3, -gun_kick)
	if _flash > 0.0 or _flash_dirty:
		_flash = maxf(0.0, _flash - delta * 7.0)
		var c := _flash_color * (_flash * 1.6)
		for mt in mats:
			mt.emission = c
		_flash_dirty = _flash > 0.0


func flash(color := Color.WHITE, amount := 1.0) -> void:
	_flash = amount
	_flash_color = color
	_flash_dirty = true


func squash(v := 0.22) -> void:
	_squash = v


## 改描边颜色；xray=true 时描边无视深度（子弹时间里隔墙可见）
func set_outline(color: Color, xray := false) -> void:
	for mt in mats:
		var o := mt.next_pass as StandardMaterial3D
		if o:
			o.albedo_color = color
			o.no_depth_test = xray
			o.render_priority = 10 if xray else 0


## 生成残影（翻滚/冲刺拖尾）
func make_ghost(mat: Material) -> Node3D:
	var g := pose.duplicate(0) as Node3D
	_apply_override(g, mat)
	return g


func _apply_override(n: Node, mat: Material) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).material_override = mat
			(ch as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif ch is Label3D:
			ch.queue_free()
			continue
		_apply_override(ch, mat)
