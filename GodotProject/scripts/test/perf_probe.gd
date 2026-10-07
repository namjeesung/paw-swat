class_name PerfProbe
extends Node
## 性能探针（开发用，不进发行包）：autotest 加 --perfprobe 时启用。
## 每隔 N 秒打印一次：本帧真实绘制调用 / 三角形 / 可见物体（RenderingServer），
## 以及按「来源」分类的估算：每类有多少个可见网格、每帧要画几次（材质 pass 数）、多少三角形。
## 云端是软件渲染，帧时间没参考价值；但绘制调用和三角形数与手机 GPU 负担直接相关，可以横向比较。

var level: Level
var _m1: Node
var _m2: Node
var _wall0 := 0
var interval := 3.0
var _t := 0.0
var _n := 0


func _process(delta: float) -> void:
	if level == null or not is_instance_valid(level):
		return
	_t += delta
	if _t < interval:
		return
	_t = 0.0
	_n += 1
	report("t%d" % _n)


func _ready() -> void:
	var M = load("res://scripts/test/physmark.gd")
	_m1 = M.new()
	_m2 = M.new()
	_m2.set("last", true)
	add_child(_m1)
	add_child(_m2)
	_wall0 = Time.get_ticks_usec()


func report(tag: String) -> void:
	var M = load("res://scripts/test/physmark.gd")
	var wall := Time.get_ticks_usec() - _wall0
	_wall0 = Time.get_ticks_usec()
	print("[physmark] steps=%d scripts=%.2fms/step  (%.1f%% of wall time in physics scripts)" % [M.steps, M.acc / 1000.0 / maxf(M.steps, 1), 100.0 * M.acc / maxf(wall, 1)])
	M.acc = 0
	M.steps = 0
	var rs := RenderingServer
	var draws := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var cats := {}
	var lights := 0
	var shadow_lights := 0
	var labels := 0
	var particles := 0
	_walk(level, cats, "level")
	for n in level.find_children("*", "Light3D", true, false):
		if (n as Light3D).is_visible_in_tree():
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadow_lights += 1
	for n in level.find_children("*", "Label3D", true, false):
		if (n as Node3D).is_visible_in_tree():
			labels += 1
	for n in level.find_children("*", "", true, false):
		if (n is CPUParticles3D or n is GPUParticles3D) and (n as Node3D).is_visible_in_tree():
			particles += 1
	print("[perfprobe] %s phase=%d zombies=%d  REAL draws=%d prims=%d objects=%d | lights=%d (shadow %d) label3d=%d particles=%d fps=%d | cpu process=%.2fms physics=%.2fms nodes=%d" % [
		tag, level.phase, level.zombies.size(), draws, prims, objs, lights, shadow_lights, labels, particles, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	print("[perfprobe]    nav iteration=%d  physics bodies=%d pairs=%d islands=%d" % [
		NavigationServer3D.map_get_iteration_id(level.get_world_3d().navigation_map),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))])
	if _n == 1:
		_detail()
	var keys := cats.keys()
	keys.sort_custom(func(a, b): return cats[a].tris > cats[b].tris)
	for k in keys:
		var c: Dictionary = cats[k]
		print("[perfprobe]    %-10s meshes=%4d passes=%5d tris=%7d" % [k, c.meshes, c.passes, c.tris])


func _category(n: Node) -> String:
	var p := n
	while p and p != level:
		if p is Zombie:
			return "boss" if (p as Zombie).boss else "zombie"
		if p is Enemy:
			return "bandit"
		if p is Player:
			return "player"
		if p is Hostage:
			return "hostage"
		if p is Pickup:
			return "pickup"
		if p is Bullet:
			return "bullet"
		if p is Door:
			return "door"
		p = p.get_parent()
	return "level/fx"


func _walk(n: Node, cats: Dictionary, _cat: String) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var k := _category(m)
		if not cats.has(k):
			cats[k] = {"meshes": 0, "passes": 0, "tris": 0}
		var passes := 0
		var tris := 0
		for s in m.mesh.get_surface_count():
			var mat: Material = m.material_override if m.material_override else m.get_active_material(s)
			var np := 0
			while mat:
				np += 1
				mat = mat.next_pass
			np = maxi(np, 1)
			var t := _surface_tris(m.mesh, s)
			passes += np
			tris += t * np
		cats[k].meshes += 1
		cats[k].passes += passes
		cats[k].tris += tris


static var _tri_cache := {}


static func _surface_tris(mesh: Mesh, s: int) -> int:
	var key := "%d:%d" % [mesh.get_instance_id(), s]
	if _tri_cache.has(key):
		return _tri_cache[key]
	var arr := mesh.surface_get_arrays(s)
	var t := 0
	if arr[Mesh.ARRAY_INDEX] != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		t = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	elif arr[Mesh.ARRAY_VERTEX] != null:
		t = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_tri_cache[key] = t
	return t


## 第一次报告时：列出每类第一个角色身上的每个网格（定位面数大户）
func _detail() -> void:
	var seen := {}
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var k := _category(m)
		if k == "level/fx":
			continue
		var owner_actor := m.get_parent()
		while owner_actor and not (owner_actor is Actor):
			owner_actor = owner_actor.get_parent()
		if seen.has(k) and seen[k] != owner_actor:
			continue
		seen[k] = owner_actor
		var mat: Material = m.material_override
		var np := 0
		while mat:
			np += 1
			mat = mat.next_pass
		print("[perfdetail] %-8s %-40s vis=%s passes=%d tris=%d" % [k, str(m.get_path()).get_slice("/", -2) + "/" + m.name, m.is_visible_in_tree(), np, _surface_tris(m.mesh, 0)])
