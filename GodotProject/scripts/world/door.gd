class_name Door
extends Node3D
## 可破的门：锁定时阻挡；破门时门板被踹飞（刚体），触发子弹时间。

signal breached

var level: Level
var width := 1.6
var height := 1.35
var breachable := false
var done := false
var body: StaticBody3D
var slab: MeshInstance3D
var _mat: StandardMaterial3D
var _pulse := 0.0


func build(geo: Node3D) -> void:
	body = StaticBody3D.new()
	body.collision_layer = Bullet.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 2.2, 0.25)
	cs.shape = sh
	cs.position.y = 1.1
	body.add_child(cs)
	geo.add_child(body)
	body.global_position = global_position

	_mat = Toon.mat(Color("5B6F95"), true, Pal.OUTLINE_PROP, 0.02, 0.2)
	slab = MeshInstance3D.new()
	slab.mesh = Models.box(Vector3(width - 0.08, height, 0.12))
	slab.material_override = _mat
	slab.position.y = height * 0.5
	add_child(slab)
	# 黄黑警示条 + 牌子 + 把手
	var stripe := MeshInstance3D.new()
	stripe.mesh = Models.box(Vector3(width - 0.1, 0.14, 0.14))
	stripe.material_override = Toon.prop(Pal.YELLOW)
	stripe.position = Vector3(0, -height * 0.5 + 0.2, 0)
	slab.add_child(stripe)
	var handle := MeshInstance3D.new()
	handle.mesh = Models.box(Vector3(0.18, 0.05, 0.08))
	handle.material_override = Toon.prop(Color("D9E2EC"))
	handle.position = Vector3(width * 0.33, 0.0, 0.1)
	slab.add_child(handle)
	var sign := Label3D.new()
	sign.text = "员工专用\nSTAFF ONLY"
	sign.font = Style.title_font()
	sign.font_size = 44
	sign.pixel_size = 0.004
	sign.modulate = Pal.CREAM
	sign.outline_size = 8
	sign.outline_modulate = Pal.INK
	sign.position = Vector3(0, 0.22, 0.07)
	slab.add_child(sign)
	# 门框
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = Models.box(Vector3(0.14, 1.55, 0.36))
		post.material_override = Toon.prop(Pal.NAVY)
		post.position = Vector3(sx * width * 0.5, 0.775, 0)
		add_child(post)


func _process(delta: float) -> void:
	if done:
		return
	if breachable:
		_pulse += delta * 5.0
		_mat.emission = Pal.ORANGE * (0.25 + 0.22 * sin(_pulse))
	else:
		_mat.emission = Color.BLACK


func breach(from: Vector3) -> void:
	if done or not breachable:
		return
	done = true
	if is_instance_valid(body):
		body.get_parent().remove_child(body)
		body.queue_free()
	# 门板变成刚体飞出去
	var rb := RigidBody3D.new()
	rb.collision_layer = 16
	rb.collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
	rb.mass = 25.0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width - 0.08, height, 0.12)
	cs.shape = sh
	rb.add_child(cs)
	level.add_child(rb)
	rb.global_transform = slab.global_transform
	slab.get_parent().remove_child(slab)
	rb.add_child(slab)
	slab.position = Vector3.ZERO
	var away := global_position - from
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, -1)
	rb.apply_central_impulse(away * 260.0 + Vector3.UP * 80.0)
	rb.apply_torque_impulse(Vector3(randf_range(-30, 30), randf_range(-40, 40), randf_range(-30, 30)))
	var freeze := get_tree().create_timer(4.0, false, true)
	freeze.timeout.connect(func():
		if is_instance_valid(rb):
			rb.freeze = true
	)
	_mat.emission = Color.BLACK

	var c := global_position + Vector3(0, 0.8, 0)
	Fx.spark(level, c, away, Color("C48A4E"), 18, 9.0)
	Fx.dust(level, global_position, 14, Color(0.95, 0.9, 0.82, 0.8), 4.0, 0.3)
	Fx.ring(level, global_position, Pal.ORANGE, 4.0, 0.45)
	Sfx.play("breach", 0.0)
	Sfx.play("slowmo", -4.0)
	Game.shake(0.8)
	Game.hitstop(0.08)
	Game.bullet_time(1.9)
	breached.emit()


# 互动接口
func can_interact(_p: Player) -> bool:
	return not done


func interact_enabled() -> bool:
	return breachable


func interact_text() -> String:
	return "破门！" if breachable else "门锁住了 · 先清理店面"


func interact_pos() -> Vector3:
	return global_position + Vector3(0, 0.6, 0)


func interact(p: Player) -> void:
	if breachable:
		p.kick_door(self)
	else:
		Sfx.play("ui_deny", -6.0)
		level.hud.toast("门锁住了 —— 先清理店面！")
