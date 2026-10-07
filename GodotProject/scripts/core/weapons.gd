class_name Weapons
## 神装武器数据。步枪无限子弹；神装有弹药上限，打空自动换回步枪。

const DATA := {
	"rifle": {"name": "P-30 突击步枪", "short": "步枪", "desc": "", "ammo": 0, "interval": 0.1, "color": Color("FFF4E0")},
	"shotgun": {"name": "喵喵散弹", "short": "散弹", "desc": "扇形 8 连发 · 一枪击退一片 · 不伤人质", "ammo": 18, "interval": 0.5, "color": Color("FF7A1A")},
	"laser": {"name": "罐头激光", "short": "激光", "desc": "贯穿一整排敌人", "ammo": 110, "interval": 0.06, "color": Color("3DD6C6")},
	"rocket": {"name": "肉垫火箭", "short": "火箭", "desc": "爆炸范围伤害", "ammo": 10, "interval": 0.7, "color": Color("E63946")},
	"gatling": {"name": "神器 · 罐头加特林", "short": "神器", "desc": "超高射速 · 子弹贯穿", "ammo": 1400, "interval": 0.045, "color": Color("FFC93C")},
}


static func info(id: String) -> Dictionary:
	return DATA.get(id, DATA["rifle"])


## 武器箱上方漂浮的小模型
static func model(id: String) -> Node3D:
	var root := Node3D.new()
	var dark := Toon.mat(Color("2A2E38"), true, Pal.OUTLINE_PROP, 0.02)
	var c: Color = info(id).color
	var accent := Toon.mat(c, true, Pal.OUTLINE_PROP, 0.02)
	accent.emission = c * 0.5
	match id:
		"shotgun":
			_p(root, Models.box(Vector3(0.16, 0.16, 0.7)), dark, Vector3.ZERO)
			_p(root, Models.cyl(0.06, 0.06, 0.4), accent, Vector3(0.05, 0.04, 0.3), Vector3(90, 0, 0))
			_p(root, Models.cyl(0.06, 0.06, 0.4), accent, Vector3(-0.05, 0.04, 0.3), Vector3(90, 0, 0))
			_p(root, Models.box(Vector3(0.12, 0.22, 0.25)), accent, Vector3(0, -0.12, -0.3))
		"laser":
			_p(root, Models.cyl(0.13, 0.13, 0.32), accent, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
			_p(root, Models.box(Vector3(0.12, 0.12, 0.55)), dark, Vector3(0, 0, 0.25))
			_p(root, Models.sphere(0.07), Toon.glow(c, 2.5), Vector3(0, 0, 0.55))
		"rocket":
			_p(root, Models.cyl(0.14, 0.14, 0.8), dark, Vector3.ZERO, Vector3(90, 0, 0))
			_p(root, Models.sphere(0.13), accent, Vector3(0, 0, 0.42))
			_p(root, Models.box(Vector3(0.08, 0.2, 0.15)), accent, Vector3(0, -0.18, -0.1))
		"gatling":
			for i in 6:
				var a := TAU * i / 6.0
				_p(root, Models.cyl(0.035, 0.035, 0.8), dark, Vector3(cos(a) * 0.09, sin(a) * 0.09, 0.25), Vector3(90, 0, 0))
			_p(root, Models.cyl(0.2, 0.2, 0.28), accent, Vector3(0, 0, -0.2), Vector3(90, 0, 0))
			_p(root, Models.cyl(0.16, 0.16, 0.22), Toon.mat(Pal.ORANGE), Vector3(0, -0.25, -0.2))
		"grenade":
			_p(root, Models.cyl(0.16, 0.16, 0.3), Toon.mat(Color("5DBB63"), true, Pal.OUTLINE_PROP, 0.025), Vector3.ZERO)
			_p(root, Models.cyl(0.17, 0.17, 0.09), Toon.mat(Pal.CREAM, false), Vector3.ZERO)
			_p(root, Models.torus(0.04, 0.08), Toon.mat(Pal.YELLOW, false), Vector3(0, 0.2, 0))
		"shield":
			var shield_mat := Toon.mat(Color("60DFFF"), true, Pal.OUTLINE_PROP, 0.02)
			_p(root, Models.box(Vector3(0.4, 0.38, 0.08)), shield_mat, Vector3(0, 0.08, 0))
			_p(root, Models.sphere(0.19), shield_mat, Vector3(0, -0.12, 0))
			_p(root, Models.box(Vector3(0.08, 0.24, 0.1)), Toon.mat(Pal.CREAM), Vector3(0, 0.04, 0.05))
		"heal":
			var can := Toon.mat(Pal.ORANGE, true, Pal.OUTLINE_PROP, 0.02)
			_p(root, Models.cyl(0.2, 0.2, 0.3), can, Vector3.ZERO)
			_p(root, Models.cyl(0.21, 0.21, 0.12), Toon.mat(Pal.CREAM), Vector3.ZERO)
			_p(root, Models.box(Vector3(0.18, 0.05, 0.05)), Toon.mat(Pal.RED), Vector3(0, 0, 0.22))
			_p(root, Models.box(Vector3(0.05, 0.18, 0.05)), Toon.mat(Pal.RED), Vector3(0, 0, 0.22))
		_:
			_p(root, Models.box(Vector3(0.12, 0.14, 0.55)), dark, Vector3.ZERO)
	return root


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
