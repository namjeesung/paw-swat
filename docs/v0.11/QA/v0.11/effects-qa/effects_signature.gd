extends Node
## Captures original effect appearance/settings below overload caps.
var out_path := ""
var report := {}
func _ready() -> void:
	Online.server_url = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-out="):
			out_path = arg.substr(14)
	call_deferred("_run")
func color(c: Color) -> Array:
	return [c.r,c.g,c.b,c.a]
func vec(v: Vector3) -> Array:
	return [v.x,v.y,v.z]
func mat(m: StandardMaterial3D) -> Dictionary:
	var data := {"shading":m.shading_mode,"albedo":color(m.albedo_color),"transparent":m.transparency,"blend":m.blend_mode,"billboard":m.billboard_mode,"cull":m.cull_mode}
	if m.albedo_texture:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(m.albedo_texture.get_image().get_data())
		data["texture_sha256"] = context.finish().hex_encode()
	return data
func mesh(m: Mesh) -> Dictionary:
	var d := {"class":m.get_class(),"triangles":m.get_faces().size()/3}
	if m is SphereMesh:
		d.merge({"radius":m.radius,"height":m.height,"segments":m.radial_segments,"rings":m.rings})
	elif m is CapsuleMesh:
		d.merge({"radius":m.radius,"height":m.height,"segments":m.radial_segments,"rings":m.rings})
	elif m is BoxMesh:
		d["size"] = vec(m.size)
	elif m is PlaneMesh or m is QuadMesh:
		d["size"] = [m.size.x,m.size.y]
	return d
func nodes(n: Node) -> Array:
	var data: Array = []
	for child in n.get_children():
		if child is CPUParticles3D:
			data.append({"class":child.get_class(),"mesh":mesh(child.mesh),"material":mat(child.material_override),"amount":child.amount,"lifetime":child.lifetime,"explosiveness":child.explosiveness,"one_shot":child.one_shot,"direction":vec(child.direction),"spread":child.spread,"velocity_min":child.initial_velocity_min,"velocity_max":child.initial_velocity_max,"gravity":vec(child.gravity),"scale_min":child.scale_amount_min,"scale_max":child.scale_amount_max,"damping_min":child.damping_min,"damping_max":child.damping_max,"align_y":child.particle_flag_align_y})
		elif child is MeshInstance3D:
			data.append({"class":"MeshInstance3D","mesh":mesh(child.mesh),"material":mat(child.material_override),"scale":vec(child.scale)})
		elif child is OmniLight3D:
			data.append({"class":"OmniLight3D","color":color(child.light_color),"energy":child.light_energy,"range":child.omni_range})
		elif child is Label3D:
			data.append({"class":"Label3D","text":child.text,"font_path":child.font.resource_path,"font_size":child.font_size,"pixel_size":child.pixel_size,"modulate":color(child.modulate),"outline_color":color(child.outline_modulate),"outline_size":child.outline_size,"billboard":child.billboard,"no_depth_test":child.no_depth_test,"render_priority":child.render_priority,"outline_priority":child.outline_render_priority,"double_sided":child.double_sided})
		data.append_array(nodes(child))
	return data
func _run() -> void:
	var model := Models.shiba()
	add_child(model)
	for key in ["spark","dust","muzzle","ring","ghost","popup"]:
		var root := Node3D.new()
		add_child(root)
		seed(11011)
		match key:
			"spark": Fx.spark(root,Vector3.ZERO,Vector3.UP,Color(1,0.95,0.85),7,5.0)
			"dust": Fx.dust(root,Vector3.ZERO,6)
			"muzzle": Fx.muzzle(root,Vector3.ZERO,Color(1.0,0.82,0.4),0.9,true)
			"ring": Fx.ring(root,Vector3.ZERO,Pal.ORANGE,2.5,0.35)
			"ghost": Fx.ghost(root,model)
			"popup": Fx.popup(root,Vector3.ZERO,"10",Pal.CREAM)
		report[key] = nodes(root)
		root.queue_free()
		await get_tree().process_frame
	model.queue_free()
	await get_tree().process_frame
	var f := FileAccess.open(out_path,FileAccess.WRITE)
	if f == null:
		get_tree().quit(2); return
	f.store_string(JSON.stringify(report,"\t")); f.close()
	print("[effect-signature] recorded below-cap appearance ",out_path)
	get_tree().quit()
