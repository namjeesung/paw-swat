extends Node
## Exact authored geometry/settings are sampled before and after batching.
var out_path := ""
var failures: Array[String] = []
func _ready() -> void:
	Online.server_url = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-out="):
			out_path = arg.substr(14)
	call_deferred("_run")
func vec(v: Vector3) -> Array:
	return [v.x,v.y,v.z]
func material(m: StandardMaterial3D) -> Dictionary:
	var c := m.albedo_color
	var o := m.next_pass as StandardMaterial3D
	return {"color":[c.r,c.g,c.b,c.a],"outline":o!=null,"width":o.grow_amount if o else 0.0,"shading":m.shading_mode,"diffuse":m.diffuse_mode,"rim":m.rim,"rim_enabled":m.rim_enabled}
func group(model: CharModel, n: Node) -> String:
	var p := n.get_parent()
	if p == model.head: return "head"
	if p == model.body: return "body"
	if p == model.foot_l: return "foot_l"
	if p == model.foot_r: return "foot_r"
	if p == model.tail: return "tail"
	if p == model.handcuffs: return "cuffs"
	return "other"
func sample(model: CharModel) -> Dictionary:
	var report := {"triangles":{},"materials":{},"mesh_instances":0,"visible_mesh_instances":0,"base_outline_passes":0,"visible_base_outline_passes":0,"triangles_total":0,"nodes":0,"parents":{},"aabb_min":Vector3(INF,INF,INF),"aabb_max":Vector3(-INF,-INF,-INF)}
	_visit(model,model,report)
	for key in ["body","head","foot_l","foot_r","tail"]:
		var p: Node3D = model.get(key)
		report.parents[key] = {"position":vec(p.position),"rotation":vec(p.rotation),"scale":vec(p.scale)}
	report.aabb_min = vec(report.aabb_min)
	report.aabb_max = vec(report.aabb_max)
	return report
func _visit(node: Node, model: CharModel, report: Dictionary) -> void:
	report.nodes += 1
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mt := mi.material_override as StandardMaterial3D
		var idx := model.mats.find(mt)
		var key := group(model,mi)+"/"+str(idx)
		if not report.triangles.has(key):
			report.triangles[key] = []
			report.materials[key] = material(mt)
		report.mesh_instances += 1
		report.base_outline_passes += 2 if mt.next_pass else 1
		if mi.is_visible_in_tree():
			report.visible_mesh_instances += 1
			report.visible_base_outline_passes += 2 if mt.next_pass else 1
		var xform := model.global_transform.affine_inverse() * mi.global_transform
		var normal_xform := xform.basis.inverse().transposed()
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				var triangle: Array = []
				for j in 3:
					var index := indices[i+j] if not indices.is_empty() else i+j
					var point := xform * vertices[index]
					var normal := (normal_xform * normals[index]).normalized()
					var outline := xform * (vertices[index]+normals[index]*float(report.materials[key].width))
					report.aabb_min = report.aabb_min.min(point)
					report.aabb_max = report.aabb_max.max(point)
					triangle.append_array(vec(point))
					triangle.append_array(vec(normal))
					triangle.append_array([uvs[index].x,uvs[index].y])
					triangle.append_array(vec(outline))
				report.triangles[key].append(triangle)
				report.triangles_total += 1
	for child in node.get_children():
		_visit(child,model,report)
func _run() -> void:
	var report := {"models":{},"checks":[]}
	for boss in [false,true]:
		var a := Models.zombie(boss)
		var b := Models.zombie(boss)
		add_child(a); add_child(b)
		var key := "boss" if boss else "normal"
		report.models[key] = {"rest":sample(a)}
		a.tail_wag = 0.7
		a.crouch = 0.25
		a.squash(0.22)
		a.animate(0.16,0.7)
		report.models[key]["animated"] = sample(a)
		a.flash(Color(0.7,0.3,1.0),0.6)
		a.animate(0.05,0.7)
		var independent := true
		for mt: StandardMaterial3D in b.mats:
			independent = independent and mt.emission.is_equal_approx(Color.BLACK)
		var flash_refs := true
		for mesh_node in a.find_children("*","MeshInstance3D",true,false):
			var mi := mesh_node as MeshInstance3D
			if a.mats.has(mi.material_override):
				flash_refs = flash_refs and not (mi.material_override as StandardMaterial3D).emission.is_equal_approx(Color.BLACK)
		report.checks.append({"check":key+" second instance has no flash leakage","pass":independent})
		report.checks.append({"check":key+" every registered mesh retains own flash material","pass":flash_refs})
		if not independent or not flash_refs: failures.append(key+" flash independence")
		a.set_outline(Pal.TEAL,true)
		var own_outlines := true
		for mt: StandardMaterial3D in a.mats:
			if mt.next_pass:
				var o := mt.next_pass as StandardMaterial3D
				own_outlines = own_outlines and o.albedo_color.is_equal_approx(Pal.TEAL) and o.no_depth_test
		for mt: StandardMaterial3D in b.mats:
			if mt.next_pass:
				own_outlines = own_outlines and not (mt.next_pass as StandardMaterial3D).no_depth_test
		report.checks.append({"check":key+" outline xray is instance-local","pass":own_outlines})
		if not own_outlines: failures.append(key+" outline independence")
		a.queue_free(); b.queue_free()
		await get_tree().process_frame
	report["failures"] = failures
	var file := FileAccess.open(out_path,FileAccess.WRITE)
	if file == null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report));file.close()
	print("[zombie-geometry] ", "PASS" if failures.is_empty() else "FAIL", " output=",out_path)
	get_tree().quit(0 if failures.is_empty() else 1)
