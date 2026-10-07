class_name Pickup
extends Node3D
## 掉落物：神装武器箱（金色光柱）/ 回血罐头。走过去自动拾取。

var level: Level
var kind := "weapon"
var weapon := "shotgun"
var drop_height := 0.0
var taken := false
var _t := 0.0
var _show: Node3D
var _landed := true
const SHIELD_GROUND_LIFETIME := 12.0
const GRENADE_GROUND_LIFETIME := 20.0
const WEAPON_GROUND_LIFETIME := 30.0
var _ground_t := 0.0
const HEAL_AMOUNT := 35.0
var _full_heal_notice := false


func _ready() -> void:
	var col: Color = Color("60DFFF") if kind == "shield" else (Pal.TEAL if kind == "heal" else (Color("7EE081") if kind == "grenade" else Weapons.info(weapon).color))
	var gold := Toon.mat(Color("FFD25A") if kind == "weapon" else Color("8FD9A8"), true, Pal.OUTLINE_PROP, 0.02)
	gold.emission = Color(0.35, 0.25, 0.05) if kind == "weapon" else Color(0.05, 0.2, 0.1)
	var crate := MeshInstance3D.new()
	crate.mesh = Models.box(Vector3(0.75, 0.42, 0.75))
	crate.material_override = gold
	crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crate.position.y = 0.21
	add_child(crate)
	var band := MeshInstance3D.new()
	band.mesh = Models.box(Vector3(0.78, 0.1, 0.78))
	band.material_override = Toon.prop(Pal.NAVY)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.position.y = 0.3
	add_child(band)
	# 光柱
	var beam := MeshInstance3D.new()
	beam.mesh = Models.cyl(0.32, 0.42, 7.0)
	beam.material_override = Toon.glow(Color(col.r, col.g, col.b, 0.22), 1.4)
	beam.position.y = 3.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_show = Weapons.model(kind if kind != "weapon" else weapon)
	_show.position.y = 1.05
	_show.scale = Vector3.ONE * 1.5
	add_child(_show)
	var l := Label3D.new()
	match kind:
		"shield":
			l.text = "临时护盾 · 5秒"
		"heal":
			l.text = "补给罐头 · +35"
		"grenade":
			l.text = "罐头手雷 ×2"
		_:
			l.text = ("神器" if weapon == "gatling" else "神装 · ") + ("" if weapon == "gatling" else Weapons.info(weapon).short)
	l.font = Style.title_font()
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Pal.INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 12
	l.outline_render_priority = 11
	l.position.y = 1.8
	add_child(l)
	if not Game.lite:
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.6
		light.omni_range = 3.5
		light.position.y = 1.0
		add_child(light)
	if drop_height > 0.0:
		_landed = false
		var target_y := position.y
		position.y += drop_height
		var tw := create_tween()
		tw.tween_property(self, "position:y", target_y, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(_land)


func _land() -> void:
	_landed = true
	Fx.dust(level, global_position, 10, Color(1, 0.95, 0.85, 0.8), 3.0, 0.3)
	Fx.ring(level, global_position, Pal.YELLOW, 2.2)
	Sfx.play("stamp", -4.0)
	Game.shake(0.25)


func _process(delta: float) -> void:
	var lifetime := SHIELD_GROUND_LIFETIME if kind == "shield" else (GRENADE_GROUND_LIFETIME if kind == "grenade" else (WEAPON_GROUND_LIFETIME if kind == "weapon" and weapon != "gatling" else 0.0))
	if lifetime > 0.0 and _landed and not taken:
		_ground_t += delta / maxf(Engine.time_scale, 0.001)
		if _ground_t >= lifetime:
			level.pickups.erase(self)
			queue_free()
			return
	_t += delta
	_show.rotation.y += delta * 2.0
	_show.position.y = 1.05 + sin(_t * 3.0) * 0.12
	if taken or not _landed or level == null or level.player == null or level.player.dead or level.finished:
		return
	var pp := level.player.global_position
	if Vector2(pp.x - global_position.x, pp.z - global_position.z).length() < 1.5:
		_collect()


func _collect() -> void:
	if taken or level == null or level.player == null or level.player.dead or level.finished:
		return
	taken = true
	var p := level.player
	if kind == "shield":
		if not p.grant_shield():
			taken = false
			return
	elif kind == "heal":
		if p.hp >= p.max_hp:
			taken = false
			if not _full_heal_notice:
				_full_heal_notice = true
				level.hud.toast("生命已满 · 补给留在地上")
			return
		var recovered := minf(HEAL_AMOUNT, p.max_hp - p.hp)
		p.hp = minf(p.max_hp, p.hp + recovered)
		Fx.popup(level, p.global_position + Vector3(0, 2.0, 0), "+%d" % roundi(recovered), Pal.GREEN, 72)
		Sfx.play("perfect", -4.0, 1.2, 0.0)
	elif kind == "grenade":
		if p.grenades >= Player.MAX_GRENADES:
			# 满了就不捡，留在地上
			taken = false
			return
		p.grenades = mini(Player.MAX_GRENADES, p.grenades + 2)
		Fx.popup(level, p.global_position + Vector3(0, 2.0, 0), "手雷 ×%d" % p.grenades, Color("7EE081"), 64, true)
		Sfx.play("pickup", -4.0, 1.3, 0.0)
		level.tip("grenade")
	else:
		Sfx.play("pickup", -2.0, 1.0, 0.0)
		if weapon == "gatling":
			level.equip_artifact()
		else:
			p.give_weapon(weapon)
	level.pickups.erase(self)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
