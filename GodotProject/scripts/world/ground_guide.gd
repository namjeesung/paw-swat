class_name GroundGuide
extends Node3D
## 地面指引：沿导航路径铺一串流动的橙色箭头，一直指到当前任务目标。

const SPACING := 1.1
const MAX_ARROWS := 22

var level: Level
var _arrows: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _path := PackedVector3Array()
var _repath := 0.0
var _t := 0.0


func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# 扁平的“〉”形箭头，指向 +Z
	var pts := [Vector3(0, 0, 0.28), Vector3(-0.3, 0, -0.08), Vector3(-0.18, 0, -0.2),
		Vector3(0, 0, 0.06), Vector3(0.18, 0, -0.2), Vector3(0.3, 0, -0.08)]
	for tri in [[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 5]]:
		for k in tri:
			st.add_vertex(pts[k])
	var mesh := st.commit()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = false
	_mat.albedo_color = Color(1.0 * 2.0, 0.55 * 2.0, 0.15 * 2.0, 0.85)
	for i in MAX_ARROWS:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat.duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_arrows.append(mi)


func _process(delta: float) -> void:
	_t += delta
	if level == null or level.player == null:
		return
	var target := level.guide_target()
	var p := level.player.global_position
	if level.finished or level.player.dead or target == Vector3.INF or p.distance_to(target) < 2.2:
		for a in _arrows:
			a.visible = false
		return
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.35
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_path = NavigationServer3D.map_get_path(map, p, target, true)
	# 沿路径按固定间距摆放箭头，整体向前流动
	var offset := fmod(_t * 2.2, SPACING) + 0.9
	var idx := 0
	var walked := 0.0
	var next_at := offset
	for i in range(_path.size() - 1):
		var a := _path[i]
		var b := _path[i + 1]
		a.y = 0
		b.y = 0
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var dir := (b - a) / seg
		while next_at <= walked + seg and idx < MAX_ARROWS:
			var pos := a + dir * (next_at - walked)
			if pos.distance_to(target) < 1.2:
				break
			var arrow := _arrows[idx]
			arrow.visible = true
			arrow.global_position = pos + Vector3(0, 0.05, 0)
			arrow.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
			var fade := clampf((next_at - 0.9) / 1.5, 0.0, 1.0) * clampf(1.0 - float(idx) / MAX_ARROWS, 0.25, 1.0)
			(arrow.material_override as StandardMaterial3D).albedo_color.a = 0.85 * fade
			idx += 1
			next_at += SPACING
		walked += seg
	for k in range(idx, MAX_ARROWS):
		_arrows[k].visible = false
