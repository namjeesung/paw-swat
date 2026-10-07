extends Node
## Deterministic object/resource/lifecycle QA, not a frame-rate benchmark.
var report := {"kind": "headless structural and lifecycle QA", "assertions": [], "families": {}, "models": {}, "bullets": {}}
var failures: Array[String] = []
var out_path := ""
var candidate := false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120
	Online.server_url = ""
	Game.new_run()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-out="):
			out_path = arg.substr(14)
		if arg == "--candidate":
			candidate = true
	call_deferred("_run")
func check(ok: bool, text: String) -> void:
	report.assertions.append({"check":text,"pass":ok})
	if not ok:
		failures.append(text)
	print("[effects-qa] ", "PASS " if ok else "FAIL ", text)
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
func inventory(root: Node) -> Dictionary:
	var data := {"nodes":0,"meshes":0,"labels":0,"lights":0,"particle_emitters":0,"particle_amount":0,"shadow_casting_geometry":0,"shadow_casting_particle_amount":0,"visible_nodes":0,"estimated_geometry_passes":0,"triangles_in_geometry":0}
	var resources := {"meshes":{},"materials":{}}
	_visit(root,data,resources)
	data["unique_mesh_resources"] = resources.meshes.size()
	data["unique_material_resources"] = resources.materials.size()
	return data
func _visit(node: Node, data: Dictionary, resources: Dictionary) -> void:
	data.nodes += 1
	if node is Node3D and node.visible:
		data.visible_nodes += 1
	if node is OmniLight3D:
		data.lights += 1
	if node is Label3D:
		data.labels += 1
	var mesh: Mesh
	var material: Material
	var multiplier := 1
	if node is MeshInstance3D:
		data.meshes += 1
		mesh = node.mesh
		material = node.material_override
	elif node is CPUParticles3D:
		data.particle_emitters += 1
		data.particle_amount += node.amount
		mesh = node.mesh
		material = node.material_override
		multiplier = node.amount
	if node is GeometryInstance3D and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		data.shadow_casting_geometry += 1
		if node is CPUParticles3D:
			data.shadow_casting_particle_amount += node.amount
	if mesh:
		resources.meshes[mesh.get_instance_id()] = true
		data.triangles_in_geometry += (mesh.get_faces().size() / 3) * multiplier
		data.estimated_geometry_passes += 1
	while material:
		resources.materials[material.get_instance_id()] = true
		material = material.next_pass
		if material:
			data.estimated_geometry_passes += 1
	for child in node.get_children():
		_visit(child, data, resources)
func run_family(kind: String, model: CharModel) -> void:
	var root := Node3D.new()
	root.name = kind
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(root)
	seed(11011)
	for i in 100:
		var pos := Vector3((i % 10) * 0.3, 0.5, (i / 10) * 0.3)
		match kind:
			"spark": Fx.spark(root,pos,Vector3.UP,Color(1,0.95,0.85),7,5.0)
			"dust": Fx.dust(root,pos,6)
			"muzzle": Fx.muzzle(root,pos,Color(1.0,0.82,0.4),0.9,true)
			"ring": Fx.ring(root,pos,Pal.ORANGE,2.5,0.35)
			"ghost": Fx.ghost(root,model)
			"popup": Fx.popup(root,pos,"10",Pal.CREAM)
			"notice": Fx.popup(root,pos,"击倒!",Pal.YELLOW,64,true)
			"shell": Fx.shell(root,pos,Vector3.RIGHT)
	var before := inventory(root)
	report.families[kind] = {"burst":before}
	print("[effects-qa] ", kind, " ", JSON.stringify(before))
	if candidate:
		var pool = root.get_meta(&"paw_fx_pool",null)
		check(pool != null,kind+" owns a parent-local pool")
		if pool:
			report.families[kind]["created"] = pool.created.duplicate()
			report.families[kind]["recycled"] = pool.recycled.duplicate()
	if kind != "shell":
		get_tree().paused = true
		var before_pause := inventory(root)
		await wait(0.1)
		check(inventory(root) == before_pause,kind+" pauses without recycling/freeing")
		get_tree().paused = false
	await wait(3.3 if kind == "shell" else 1.5)
	var expired := inventory(root)
	report.families[kind]["expired"] = expired
	if candidate:
		var pool = root.get_meta(&"paw_fx_pool",null)
		var active := 0
		for bucket: Array in pool.buckets.values():
			for slot in bucket:
				if slot.active:
					active += 1
		check(active == 0,kind+" expires and returns every slot")
		var first_created: Dictionary = pool.created.duplicate()
		for i in 20:
			match kind:
				"spark": Fx.spark(root,Vector3.ZERO,Vector3.UP,Color(1,0.95,0.85),7,5.0)
				"dust": Fx.dust(root,Vector3.ZERO,6)
				"muzzle": Fx.muzzle(root,Vector3.ZERO,Color(1.0,0.82,0.4),0.9,true)
				"ring": Fx.ring(root,Vector3.ZERO,Pal.ORANGE,2.5,0.35)
				"ghost": Fx.ghost(root,model)
				"popup": Fx.popup(root,Vector3.ZERO,"10",Pal.CREAM)
				"notice": Fx.popup(root,Vector3.ZERO,"击倒!",Pal.YELLOW,64,true)
				"shell": Fx.shell(root,Vector3.ZERO,Vector3.RIGHT)
		check(pool.created == first_created,kind+" repeats without new effect nodes")
		if kind == "spark" or kind == "dust" or kind == "ghost":
			check(before.shadow_casting_geometry == 0,kind+" cosmetic geometry casts no shadows")
	root.queue_free()
	await get_tree().process_frame
func _run() -> void:
	var model := Models.shiba()
	add_child(model)
	for key in ["shiba", "raccoon", "rat", "hamster", "zombie", "boss_zombie"]:
		var m: Node3D
		match key:
			"shiba": m = Models.shiba()
			"raccoon": m = Models.raccoon()
			"rat": m = Models.rat()
			"hamster": m = Models.hamster()
			"zombie": m = Models.zombie()
			"boss_zombie": m = Models.zombie(true)
		report.models[key] = inventory(m)
		m.free()
	for key in ["spark","dust","muzzle","ring","ghost","popup","notice","shell"]:
		await run_family(key,model)
	check(Fx.shell_count == 0,"all shells returned and level count restored")
	var lv := Level.new()
	for kind in ["bullet", "rocket", "enemy"]:
		var root := Node3D.new()
		add_child(root)
		for i in 100:
			var b := Bullet.new()
			b.setup(lv,Vector3(i*0.1,0.72,0),Vector3.FORWARD,kind!="enemy",1.0,null,{"kind":"rocket" if kind=="rocket" else "bullet"})
			root.add_child(b)
			b.set_physics_process(false)
		var info := inventory(root)
		report.bullets[kind] = info
		print("[effects-qa] bullets ",kind," ",JSON.stringify(info))
		if candidate and kind == "rocket":
			check(info.unique_material_resources == 3,"100 rockets share exactly base/outline/tip materials")
		root.queue_free()
		await get_tree().process_frame
	lv.free()
	model.queue_free()
	await get_tree().process_frame
	check(get_node_or_null("/root") != null,"pool teardown completed")
	report["failures"] = failures
	report["result"] = "PASS" if failures.is_empty() else "FAIL"
	var file := FileAccess.open(out_path,FileAccess.WRITE)
	if file == null:
		print("[effects-qa] FAIL cannot write report ",out_path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("[effects-qa] RESULT ",report.result," output=",out_path)
	Fx._res.clear()
	Fx._tex.clear()
	get_tree().quit(0 if failures.is_empty() else 1)
