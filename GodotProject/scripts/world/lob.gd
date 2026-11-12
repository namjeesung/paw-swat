class_name Lob
## 第二章通用的「抛物线投射 + 地面预警圈」：
##   酸液鼠吐酸（打你）、空袭炸弹 / 炮艇炮弹（打僵尸鼠）都用它。
##   落点先亮一个圈（敌方攻击 = 红 / 绿，我方支援 = 黄），然后东西飞过去，落地结算。

static var _mats := {}


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = c
		_mats[key] = m
	return _mats[key]


## 地上一个圆（从小长到大，scale 1 时是完整半径）
static func disk(level: Node3D, c: Vector3, r: float, col: Color) -> Node3D:
	var root := Node3D.new()
	level.add_child(root)
	root.global_position = Vector3(c.x, 0.04, c.z)
	var fill := MeshInstance3D.new()
	fill.mesh = Models.cyl(r, r, 0.02)
	fill.material_override = _mat(Color(col, 0.28))
	root.add_child(fill)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.12
	tm.outer_radius = r
	tm.rings = 32
	tm.ring_segments = 3
	edge.mesh = tm
	edge.material_override = _mat(Color(col, 0.85))
	edge.scale = Vector3(1, 0.05, 1)
	root.add_child(edge)
	root.scale = Vector3(0.1, 1, 0.1)
	return root


## from → at 抛过去；hurt_player：落地圈里的玩家吃 dmg；enemy_dmg > 0：落地对敌人范围伤害
static func shot(level: HarborLevel, from: Vector3, at: Vector3, delay: float, r: float, dmg: float, col: Color,
		fly := 1.1, hurt_player := true, enemy_dmg := 0.0, arc := 4.0, proj_scale := 1.6) -> void:
	at.y = 0.0
	var d := disk(level, at, r, col)
	var p := MeshInstance3D.new()
	p.mesh = Models.sphere(0.12)
	p.material_override = Toon.glow(col, 2.0)
	p.scale = Vector3.ONE * proj_scale
	p.visible = delay <= 0.0
	level.add_child(p)
	p.global_position = from
	var tw := d.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(d, "scale", Vector3.ONE, fly)
	var pt := p.create_tween()
	pt.tween_interval(delay)
	pt.tween_callback(func(): p.visible = true)
	pt.tween_method(func(k: float):
		if is_instance_valid(p):
			p.global_position = from.lerp(at, k) + Vector3(0, sin(k * PI) * arc, 0)
	, 0.0, 1.0, fly)
	pt.tween_callback(func():
		p.queue_free()
		d.queue_free()
		if level.stage != "play":
			return
		Fx.ring(level, at, col, r * 1.1, 0.3)
		Fx.spark(level, at + Vector3(0, 0.3, 0), Vector3.UP, col, 10, 7.0)
		if enemy_dmg > 0.0:
			Fx.dust(level, at, 8, Color(1.0, 0.85, 0.6, 0.8), r, 0.35)
			Sfx.play("explosion", -9.0, randf_range(0.8, 1.1), 0.1)
			level.explode(at, r, enemy_dmg, level.player, true)
		else:
			Sfx.play("splat", -8.0, 0.8, 0.1)
		var pl := level.player
		if hurt_player and not pl.dead and Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length() < r:
			var dir := pl.global_position - at
			dir.y = 0
			pl.take_hit(dmg, dir.normalized() * 2.0, at, null)
	)
