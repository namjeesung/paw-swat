class_name Fx
## 特效工厂：枪口火光、火花、弹壳、烟尘、伤害数字、残影、冲击波……
## 所有特效自己管理生命周期。

static var _tex := {}
## 网格 / 材质缓存：特效频繁生成，避免每次都新建资源
static var _res := {}
static var shell_count := 0
const MAX_SHELLS := 36
## Per-level transient budgets. Ordinary fire retains its full original feedback;
## overload recycles the oldest cosmetic instance, never a projectile or actor.
const MAX_SPARKS := 64
const MAX_DUST := 48
const MAX_MUZZLES := 16
const MAX_LIGHTS := 8
const MAX_RINGS := 24
const MAX_GHOSTS := 16
const MAX_HIT_POPUPS := 48
const MAX_NOTICE_POPUPS := 32
const POOL_META := &"paw_fx_pool"

class EffectSlot extends RefCounted:
	var node: Node3D
	var active := false
	var serial := 0
	var tween: Tween
	var mode := ""
	var elapsed := 0.0
	var duration := 0.0
	var size := 1.0
	var alpha := 1.0

## One lightweight updater owns a level's effects. Pools die with their parent;
## no static node references can retain an old/restarted level.
class EffectPool extends Node3D:
	var buckets := {}
	var serial := 0
	var animated: Array[EffectSlot] = []
	var created := {}
	var recycled := {}

	func _ready() -> void:
		set_process(false)

	func acquire(kind: String, capacity: int) -> EffectSlot:
		if not buckets.has(kind):
			buckets[kind] = []
		var slots: Array = buckets[kind]
		var slot: EffectSlot
		for item: EffectSlot in slots:
			if not item.active:
				slot = item
				break
		if slot == null and slots.size() < capacity:
			slot = EffectSlot.new()
			match kind:
				"spark", "dust":
					slot.node = CPUParticles3D.new()
				"light":
					slot.node = OmniLight3D.new()
				"shell":
					slot.node = Shell.new()
				"ghost":
					slot.node = Node3D.new()
				"hit_popup", "notice_popup":
					slot.node = Label3D.new()
				_:
					slot.node = MeshInstance3D.new()
			add_child(slot.node)
			slots.append(slot)
			created[kind] = int(created.get(kind, 0)) + 1
			if slot.node is CPUParticles3D:
				(slot.node as CPUParticles3D).emitting = false
				(slot.node as CPUParticles3D).finished.connect(release.bind(slot))
		if slot == null:
			slot = slots[0]
			for item: EffectSlot in slots:
				if item.serial < slot.serial:
					slot = item
			recycled[kind] = int(recycled.get(kind, 0)) + 1
		if slot.tween and slot.tween.is_valid():
			slot.tween.kill()
		slot.tween = null
		serial += 1
		slot.serial = serial
		slot.active = true
		slot.elapsed = 0.0
		slot.node.visible = true
		return slot

	func animate(slot: EffectSlot, mode: String, duration: float) -> void:
		slot.mode = mode
		slot.duration = duration
		if not animated.has(slot):
			animated.append(slot)
		set_process(true)

	func release(slot: EffectSlot) -> void:
		# Callback tween binds this RefCounted slot: drop the return reference
		# so finished popups cannot retain a slot/Tween cycle after level exit.
		slot.tween = null
		slot.active = false
		slot.mode = ""
		slot.node.visible = false
		if slot.node is CPUParticles3D:
			(slot.node as CPUParticles3D).emitting = false

	func _exit_tree() -> void:
		for slots: Array in buckets.values():
			for slot: EffectSlot in slots:
				if slot.tween and slot.tween.is_valid():
					slot.tween.kill()
				slot.tween = null
				slot.node = null
		animated.clear()
		buckets.clear()

	func _process(delta: float) -> void:
		for i in range(animated.size() - 1, -1, -1):
			var slot := animated[i]
			if not slot.active or slot.mode == "":
				animated.remove_at(i)
				continue
			slot.elapsed += delta
			var t := clampf(slot.elapsed / slot.duration, 0.0, 1.0)
			match slot.mode:
				"muzzle":
					slot.node.scale = Vector3.ONE * slot.size * lerpf(1.0, 0.2, t)
				"light":
					(slot.node as OmniLight3D).light_energy = lerpf(3.0, 0.0, t)
				"ring":
					# Original EASE_OUT / TRANS_CUBIC.
					var eased := 1.0 - pow(1.0 - t, 3.0)
					slot.node.scale = Vector3.ONE * lerpf(0.2, slot.size, eased)
					((slot.node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 1.0 - t
				"ghost":
					var body := slot.node.get_child(0) as MeshInstance3D
					(body.material_override as StandardMaterial3D).albedo_color.a = slot.alpha * (1.0 - t)
			if t >= 1.0:
				release(slot)
				animated.remove_at(i)
		if animated.is_empty():
			set_process(false)

static func _pool(parent: Node) -> EffectPool:
	var pool: EffectPool
	if parent.has_meta(POOL_META):
		pool = parent.get_meta(POOL_META) as EffectPool
	if pool == null or not is_instance_valid(pool):
		pool = EffectPool.new()
		pool.name = "TransientFxPool"
		parent.add_child(pool)
		parent.set_meta(POOL_META, pool)
	return pool


## 程序化生成的贴图（星形 / 柔光圆）
static func tex(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var a := 0.0
			match kind:
				"soft":
					a = clampf(1.0 - p.length() / (n * 0.5), 0.0, 1.0)
					a = a * a
				"flash":
					var ang := atan2(p.y, p.x)
					var r := p.length() / (n * 0.5)
					var spike := 0.35 + 0.65 * pow(absf(cos(ang * 4.0)), 6.0)
					a = clampf((spike - r) * 3.0, 0.0, 1.0)
					a = maxf(a, clampf(1.0 - r * 2.2, 0.0, 1.0))
				"ring":
					var r2 := p.length() / (n * 0.5)
					a = clampf(1.0 - absf(r2 - 0.8) * 9.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func _sprite_mat(kind: String, color: Color, additive := true) -> StandardMaterial3D:
	var key := "sm_%s_%s_%s" % [kind, color.to_html(), additive]
	if _res.has(key):
		return _res[key]
	var m := StandardMaterial3D.new()
	_res[key] = m
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex(kind)
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _quad(parent: Node, pos: Vector3, size: float, mat: Material) -> MeshInstance3D:
	if not _res.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_res["quad"] = q
	var mi := MeshInstance3D.new()
	mi.mesh = _res["quad"]
	mi.scale = Vector3.ONE * size
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	return mi


## 枪口火光 + 瞬时点光
static func muzzle(parent: Node, pos: Vector3, color := Color(1.0, 0.8, 0.35), size := 0.9, with_light := true) -> void:
	var pool := _pool(parent)
	var slot := pool.acquire("muzzle", MAX_MUZZLES)
	var mi := slot.node as MeshInstance3D
	if not _res.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_res["quad"] = q
	mi.mesh = _res["quad"]
	mi.material_override = _sprite_mat("flash", Color(color.r * 3, color.g * 3, color.b * 3))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = pos
	slot.size = size * randf_range(0.8, 1.2)
	mi.scale = Vector3.ONE * slot.size
	pool.animate(slot, "muzzle", 0.06)
	if not with_light or Game.lite:
		return
	var light_slot := pool.acquire("light", MAX_LIGHTS)
	var light := light_slot.node as OmniLight3D
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 4.5
	light.global_position = pos + Vector3(0, 0.3, 0)
	pool.animate(light_slot, "light", 0.07)


## 命中火花
static func spark(parent: Node, pos: Vector3, normal: Vector3, color := Color(1.0, 0.85, 0.4), amount := 9, speed := 6.0) -> void:
	var pool := _pool(parent)
	var slot := pool.acquire("spark", MAX_SPARKS)
	var p := slot.node as CPUParticles3D
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.35
	p.explosiveness = 1.0
	if not _res.has("spark_mesh"):
		var m := BoxMesh.new()
		m.size = Vector3(0.05, 0.05, 0.16)
		_res["spark_mesh"] = m
		var c0 := Curve.new()
		c0.add_point(Vector2(0, 1))
		c0.add_point(Vector2(1, 0))
		_res["fade_curve"] = c0
	p.mesh = _res["spark_mesh"]
	p.material_override = Toon.glow(color, 2.5)
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _res["fade_curve"]
	p.global_position = pos
	p.restart()


## 落地烟尘 / 冲撞烟雾
static func dust(parent: Node, pos: Vector3, amount := 6, color := Color(1, 0.96, 0.88, 0.8), spread_speed := 2.0, size := 0.25) -> void:
	var pool := _pool(parent)
	var slot := pool.acquire("dust", MAX_DUST)
	var p := slot.node as CPUParticles3D
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.55
	p.explosiveness = 0.9
	var mk := "dust_mesh_%.2f" % size
	if not _res.has(mk):
		var s := SphereMesh.new()
		s.radius = size
		s.height = size * 2
		s.radial_segments = 8
		s.rings = 4
		_res[mk] = s
		var c1 := Curve.new()
		c1.add_point(Vector2(0, 0.6))
		c1.add_point(Vector2(0.3, 1.0))
		c1.add_point(Vector2(1, 0))
		_res["dust_curve"] = c1
	p.mesh = _res[mk]
	var ck := "dust_mat_" + color.to_html()
	if not _res.has(ck):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_res[ck] = mat
	p.material_override = _res[ck]
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = spread_speed * 0.4
	p.initial_velocity_max = spread_speed
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_curve = _res["dust_curve"]
	p.global_position = pos
	p.restart()


## 地面冲击波圈
static func ring(parent: Node, pos: Vector3, color: Color, radius := 2.5, time := 0.35) -> void:
	var pool := _pool(parent)
	var slot := pool.acquire("ring", MAX_RINGS)
	var mi := slot.node as MeshInstance3D
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex("ring")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
	m.albedo_color = Color(color.r * 2, color.g * 2, color.b * 2, 1)
	if not _res.has("ring_plane"):
		var q := PlaneMesh.new()
		q.size = Vector2(2, 2)
		_res["ring_plane"] = q
	mi.mesh = _res["ring_plane"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * 0.2
	slot.size = radius
	pool.animate(slot, "ring", time)


## 跳字：伤害数字 / 提示文字
static func popup(parent: Node, pos: Vector3, text: String, color: Color, size := 64, use_title_font := false, rise := 1.0, life := 0.7) -> void:
	var pool := _pool(parent)
	# Keep notices in their own budget so damage bursts do not evict key messages.
	var slot := pool.acquire("notice_popup" if use_title_font else "hit_popup", MAX_NOTICE_POPUPS if use_title_font else MAX_HIT_POPUPS)
	var l := slot.node as Label3D
	l.text = text
	l.font = Style.title_font() if use_title_font else Style.num_font()
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_modulate = Pal.INK
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 20
	l.outline_render_priority = 19
	l.double_sided = true
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
	l.scale = Vector3.ONE * 0.3
	var tw := l.create_tween()
	slot.tween = tw
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.06)
	tw.parallel().tween_property(l, "global_position:y", l.global_position.y + rise, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.2)
	tw.tween_callback(pool.release.bind(slot))


## 残影：两块半透明的剪影（不再复制整个角色模型，开销小得多）
static func ghost(parent: Node, model: CharModel, color := Color(1.0, 0.55, 0.15, 0.45)) -> void:
	var pool := _pool(parent)
	var slot := pool.acquire("ghost", MAX_GHOSTS)
	var g := slot.node
	var m: StandardMaterial3D
	if g.get_child_count() == 0:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var b := MeshInstance3D.new()
		b.mesh = Models.capsule(0.3, 0.8)
		b.material_override = m
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position.y = 0.5
		g.add_child(b)
		var h := MeshInstance3D.new()
		h.mesh = Models.sphere(0.36)
		h.material_override = m
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.position.y = 1.0
		g.add_child(h)
	else:
		m = (g.get_child(0) as MeshInstance3D).material_override
	m.albedo_color = color
	g.global_transform = model.pose.global_transform
	slot.alpha = color.a
	pool.animate(slot, "ghost", 0.22)


## 弹壳：自带简易物理，落地后停留
class Shell extends MeshInstance3D:
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var life := 6.0
	var resting := false
	var counted := false
	var pool: EffectPool
	var slot: EffectSlot

	func _enter_tree() -> void:
		# 弹壳在物理帧里运动：流畅画质（30Hz 物理）下需要插值
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

	func _exit_tree() -> void:
		if counted:
			Fx.shell_count = maxi(0, Fx.shell_count - 1)

	func _physics_process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			counted = false
			Fx.shell_count = maxi(0, Fx.shell_count - 1)
			set_physics_process(false)
			pool.release(slot)
			return
		if life < 0.5:
			scale = Vector3.ONE * (life / 0.5)
		if resting:
			return
		vel.y -= 18.0 * delta
		position += vel * delta
		rotation += spin * delta
		if position.y < 0.03:
			position.y = 0.03
			if absf(vel.y) < 1.2:
				resting = true
				rotation.x = PI / 2
			else:
				vel.y = -vel.y * 0.35
				vel.x *= 0.5
				vel.z *= 0.5
				spin *= 0.5


static var _shell_mesh: Mesh
static var _shell_mat: Material


static func shell(parent: Node, pos: Vector3, side: Vector3) -> void:
	if shell_count >= MAX_SHELLS:
		return
	shell_count += 1
	if _shell_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.022
		c.bottom_radius = 0.022
		c.height = 0.08
		c.radial_segments = 6
		c.rings = 1
		_shell_mesh = c
		var m := Toon.mat(Color("F2C14E"), false)
		m.metallic = 0.8
		m.emission = Color("4A3200")
		_shell_mat = m
	var pool := _pool(parent)
	var slot := pool.acquire("shell", MAX_SHELLS)
	var s := slot.node as Shell
	s.pool = pool
	s.slot = slot
	s.counted = true
	s.resting = false
	s.scale = Vector3.ONE
	s.rotation = Vector3.ZERO
	s.set_physics_process(true)
	s.life = 3.0
	s.mesh = _shell_mesh
	s.material_override = _shell_mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.global_position = pos
	s.vel = side * randf_range(2.5, 4.0) + Vector3(0, randf_range(3.0, 4.5), 0) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	s.spin = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
