extends Node
## Tests live and expired effect teardown repeatedly, with object-count plateaus.
var out_path := ""
var report := {"kind":"headless repeated parent exit/restart and pooled state lifecycle", "cycles":[],"checks":[]}
var failures: Array[String] = []
func _ready() -> void:
	Online.server_url = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-out="):
			out_path = arg.substr(14)
	call_deferred("_run")
func counters() -> Dictionary:
	return {"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"shell_count":Fx.shell_count}
func check(ok: bool, text: String) -> void:
	report.checks.append({"check":text,"pass":ok})
	if not ok: failures.append(text)
	print("[pool-teardown] ","PASS " if ok else "FAIL ",text)
func flush() -> void:
	for i in 5:
		await get_tree().process_frame
func completed_tweens_cleared(pool: Fx.EffectPool) -> bool:
	# A function-local loop must not retain its Array iterator during teardown.
	for slot in pool.buckets["hit_popup"]:
		if slot.tween != null:
			return false
	return true
func _run() -> void:
	for cycle in 10:
		var parent := Node3D.new()
		parent.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(parent)
		var model := Models.shiba()
		parent.add_child(model)
		for i in 120:
			Fx.spark(parent,Vector3.ZERO,Vector3.UP)
			Fx.dust(parent,Vector3.ZERO)
			Fx.muzzle(parent,Vector3.ZERO)
			Fx.ring(parent,Vector3.ZERO,Pal.ORANGE)
			Fx.ghost(parent,model)
			Fx.popup(parent,Vector3.ZERO,"10",Pal.CREAM)
			Fx.popup(parent,Vector3.ZERO,"击倒!",Pal.YELLOW,64,true)
			Fx.shell(parent,Vector3.ZERO,Vector3.RIGHT)
		var pool = parent.get_meta(&"paw_fx_pool")
		var bounded := true
		var caps := {"spark":64,"dust":48,"muzzle":16,"light":8,"ring":24,"ghost":16,"hit_popup":48,"notice_popup":32,"shell":36}
		for key in pool.buckets:
			bounded = bounded and pool.buckets[key].size() <= caps[key]
		check(bounded,"cycle "+str(cycle)+" every family remains within its cap")
		var weak_parent: WeakRef = weakref(parent)
		var weak_pool: WeakRef = weakref(pool)
		var weak_slot: WeakRef = weakref(pool.buckets["hit_popup"][0])
		# Odd cycles finish popups first; even cycles leave active bound Tweens.
		if cycle%2 == 1:
			await get_tree().create_timer(1.5).timeout
			var freed_tweens := completed_tweens_cleared(pool)
			check(freed_tweens,"cycle "+str(cycle)+" completed popup drops Tween reference")
		parent.queue_free()
		parent = null; model = null; pool = null
		await flush()
		if weak_slot.get_ref()!=null:
			print("[pool-teardown] diagnostic retained slot references=",weak_slot.get_ref().get_reference_count())
		check(weak_parent.get_ref()==null and weak_pool.get_ref()==null and weak_slot.get_ref()==null,"cycle "+str(cycle)+" parent, pool and RefCounted slots are freed")
		check(Fx.shell_count==0,"cycle "+str(cycle)+" shell counter returns to zero")
		report.cycles.append(counters())
	var steady: Dictionary = report.cycles[1]
	var plateau := true
	for i in range(2,report.cycles.size()):
		plateau = plateau and report.cycles[i] == steady
	check(plateau,"post-warm object/node/resource/orphan counters plateau across restarts")
	report["result"] = "PASS" if failures.is_empty() else "FAIL"
	report["failures"] = failures
	var file := FileAccess.open(out_path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("[pool-teardown] RESULT ",report.result," final counters=",JSON.stringify(counters()))
	get_tree().quit(0 if failures.is_empty() else 1)
