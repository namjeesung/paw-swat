class_name Tips
## 新手说明文案（触屏 / 键鼠两套措辞）。游戏中首次遇到时弹提示卡片，暂停菜单「操作说明」里可随时查看。

const ORDER := ["move", "fire", "laser", "cuff", "roll", "skill", "reload", "cover", "grenade", "door", "hostage", "weapon", "switch", "wave", "shield", "heal"]


const KEY_COLOR := "#FF5C5C"


## 返回 [图标, 标题, 正文]。正文里 {关键字} 会被标成红色（见 rich / plain）
static func get_tip(id: String) -> Array:
	var t := Game.touch
	var hh := int(Game.dv("hostage_hits"))
	match id:
		"move":
			return ["move", "移动",
				"{左手按住}屏幕任意位置拖动就能移动。地上的{橙色箭头}会一路带你去目标。" if t
				else "{WASD} 移动，鼠标瞄准。地上的{橙色箭头}会一路带你去目标。"]
		"fire":
			return ["fire", "开火 · 锁定",
				"{按住右下角开火}：自动锁定敌人连射，脚下{红框}= 正在打的目标。拖动开火键可手动瞄准，{点一下敌人}可切换目标。" if t
				else "{左键}射击，{按住右键}精准瞄准（散布更小）。"]
		"laser":
			return ["warn", "红色激光 = 马上开枪",
				"浣熊开枪前会亮起{红色激光}，看到就{翻滚}躲开！"]
		"cuff":
			return ["cuff", "击倒即制服", "匪徒被击倒后即{永久制服}并迅速消散，不会醒来，也不需要上铐。"]
		"roll":
			return ["roll", "翻滚",
				"点{【翻滚】}：翻滚的瞬间{无敌}，子弹会直接穿过你。被围住时翻滚突围！" if t
				else "按{空格}翻滚：翻滚的瞬间{无敌}，子弹会直接穿过你。被围住时翻滚突围！"]
		"skill":
			return ["dash", "技能 · 冲撞",
				"点{【冲撞】}朝面前猛冲：撞飞一路上的匪徒；撞到锁住的门{直接破门}。冷却 7 秒，按钮上会显示倒计时。" if t
				else "按 {Q} 朝准星方向猛冲：撞飞一路上的匪徒；撞到锁住的门{直接破门}。冷却 7 秒。"]
		"reload":
			return ["reload", "完美换弹",
				"子弹打空会自动换弹。开火键外圈走到{黄色区域}时再点一次{【换弹】}= 瞬间装满 + 4 秒火力强化。{点早了会卡壳}！" if t
				else "按 {R} 换弹。进度条走到{黄色区域}时再按一次 {R} = 瞬间装满 + 4 秒火力强化。{按早了会卡壳}！"]
		"cover":
			return ["cover", "掩体",
				"靠在{柜台、箱子}旁会自动蹲下（血条旁出现盾牌），远处飞来的{子弹会被挡住}。"]
		"door":
			return ["door", "破门",
				"走到门前点{【破门】}，或者用{【冲撞】}直接撞进去。破门瞬间进入{子弹时间}——世界变慢，你更快！" if t
				else "走到门前按 {E} 破门，或者按 {Q} 冲撞撞进去。破门瞬间进入{子弹时间}——世界变慢，你更快！"]
		"hostage":
			return ["hostage", "保护人质",
				"人质身边的匪徒{不会被自动锁定}，请拖动开火键手动瞄准。{误伤人质 %d 次任务失败}。神装武器不伤人质。" % hh if t
				else "小心瞄准！普通子弹会误伤人质，{误伤 %d 次任务失败}。神装武器不伤人质。" % hh]
		"weapon":
			return ["weapon", "神装武器",
				"{金色光柱}的武器箱，走过去{自动拾取}。神装威力巨大，弹药打完会自动换回步枪。"]
		"grenade":
			return ["grenade", "罐头手雷",
				"点{【手雷】}扔向锁定的敌人（没锁定就扔最近的）。落点有{红圈}，闪几下后{范围爆炸}，不伤人质。最多带 3 颗。" if t
				else "按 {G} 把手雷扔到鼠标位置。落点有{红圈}，闪几下后{范围爆炸}，不伤人质。最多带 3 颗。"]
		"switch":
			return ["switch", "切换神装",
				"捡到的神装都会留着，点右边的{【武器】}按钮在步枪和各把神装之间{来回切换}。弹药打完才会消失。" if t
				else "捡到的神装都会留着，按 {Tab} / {X} 或{滚轮}在步枪和各把神装之间{来回切换}。弹药打完才会消失。"]
		"heal":
			var limit := int(Game.current.heal_drop_limit) if Game.current is Level else int(Game.dv("heal_drops"))
			return ["cover", "回血补给", "走近罐头{最多回复 35 血}。{满血不消耗}，受伤后再捡。本局最多{%d件}，所有来源共用；地上最多一件。" % limit]
		"shield":
			return ["cover", "临时护盾", "{蓝色光柱}是护盾，走近自动拾取。{无敌 5 秒}，倒计时结束恢复受伤；{不能刷新或叠加}。暂停时倒计时停住，地面护盾 12 秒后消失。"]
		"wave":
			return ["zombie", "坚守 60 秒",
				"{按住开火}尽情扫射，神器子弹会{贯穿}敌人！地上的{补给罐头}可以回血，被围住就翻滚突围。"]
	return ["fire", id, ""]


## {关键字} → 红色 BBCode
static func rich(text: String) -> String:
	return text.replace("[", "[lb]").replace("{", "[color=%s][b]" % KEY_COLOR).replace("}", "[/b][/color]")


static func plain(text: String) -> String:
	return text.replace("{", "").replace("}", "")


## 在 ci 上画提示图标（c = 中心，r = 半径）
static func draw_icon(ci: CanvasItem, c: Vector2, r: float, icon: String) -> void:
	var ink := Pal.INK
	match icon:
		"move":
			ci.draw_arc(c, r * 0.62, 0, TAU, 32, ink, r * 0.1)
			ci.draw_circle(c + Vector2(r * 0.22, -r * 0.18), r * 0.3, ink)
		"fire":
			ci.draw_arc(c, r * 0.5, 0, TAU, 32, ink, r * 0.1)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * r * 0.25, c + d * r * 0.72, ink, r * 0.1)
			ci.draw_circle(c, r * 0.1, Pal.RED)
		"warn":
			ci.draw_line(c + Vector2(-r * 0.7, r * 0.35), c + Vector2(r * 0.7, -r * 0.35), Pal.RED, r * 0.16)
			ci.draw_circle(c + Vector2(-r * 0.7, r * 0.35), r * 0.16, ink)
		"cuff":
			ci.draw_arc(c + Vector2(-r * 0.28, 0), r * 0.3, 0, TAU, 24, ink, r * 0.13)
			ci.draw_arc(c + Vector2(r * 0.28, 0), r * 0.3, 0, TAU, 24, ink, r * 0.13)
		"roll":
			ci.draw_arc(c, r * 0.45, -PI * 0.9, PI * 0.6, 20, ink, r * 0.14)
			var tip := c + Vector2(cos(PI * 0.6), sin(PI * 0.6)) * r * 0.45
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.3, 0), tip + Vector2(r * 0.12, -r * 0.25), tip + Vector2(r * 0.1, r * 0.25)]), ink)
		"dash":
			ci.draw_rect(Rect2(c + Vector2(r * 0.25, -r * 0.5), Vector2(r * 0.2, r)), ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.15), c + Vector2(-r * 0.1, -r * 0.15), c + Vector2(-r * 0.1, -r * 0.38), c + Vector2(r * 0.2, 0), c + Vector2(-r * 0.1, r * 0.38), c + Vector2(-r * 0.1, r * 0.15), c + Vector2(-r * 0.6, r * 0.15)]), ink)
		"reload":
			for i in 3:
				var p := c + Vector2(-r * 0.4 + i * r * 0.4, 0)
				ci.draw_rect(Rect2(p + Vector2(-r * 0.13, -r * 0.3), Vector2(r * 0.26, r * 0.6)), Pal.ORANGE)
				ci.draw_rect(Rect2(p + Vector2(-r * 0.13, -r * 0.3), Vector2(r * 0.26, r * 0.6)), ink, false, r * 0.06)
		"cover":
			var s := PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.5), c + Vector2(r * 0.45, -r * 0.5), c + Vector2(r * 0.45, 0), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.45, 0)])
			ci.draw_colored_polygon(s, Pal.TEAL)
			ci.draw_polyline(PackedVector2Array([s[0], s[1], s[2], s[3], s[4], s[0]]), ink, r * 0.08)
		"door":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.55), Vector2(r * 0.7, r * 1.1)), Color("5B6F95"))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.55), Vector2(r * 0.7, r * 1.1)), ink, false, r * 0.08)
			ci.draw_circle(c + Vector2(r * 0.18, 0), r * 0.07, Pal.YELLOW)
		"hostage":
			Portrait.draw_face(ci, c + Vector2(0, r * 0.08), r * 0.62, "hamster")
		"weapon":
			ci.draw_colored_polygon(Style.star_points(c, r * 0.65, r * 0.28), Pal.YELLOW)
			ci.draw_polyline(Style.star_points(c, r * 0.65, r * 0.28) + PackedVector2Array([Style.star_points(c, r * 0.65, r * 0.28)[0]]), ink, r * 0.07)
		"zombie":
			ci.draw_circle(c, r * 0.6, Color("9EE6B8"))
			ci.draw_circle(c + Vector2(-r * 0.22, -r * 0.05), r * 0.17, Color.WHITE)
			ci.draw_circle(c + Vector2(r * 0.24, -r * 0.08), r * 0.12, Color.WHITE)
			ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.05), r * 0.06, ink)
			ci.draw_circle(c + Vector2(r * 0.26, -r * 0.08), r * 0.05, ink)
			ci.draw_line(c + Vector2(-r * 0.2, r * 0.28), c + Vector2(r * 0.2, r * 0.28), ink, r * 0.05)
		"grenade":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.3), Vector2(r * 0.56, r * 0.7)), Color("5DBB63"))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.05), Vector2(r * 0.56, r * 0.16)), Pal.CREAM)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.3), Vector2(r * 0.56, r * 0.7)), ink, false, r * 0.07)
			ci.draw_arc(c + Vector2(r * 0.12, -r * 0.45), r * 0.14, 0, TAU, 16, Pal.ORANGE, r * 0.07)
		"switch":
			ci.draw_arc(c, r * 0.45, -PI * 0.95, -PI * 0.1, 16, ink, r * 0.12)
			ci.draw_arc(c, r * 0.45, PI * 0.05, PI * 0.9, 16, Pal.ORANGE, r * 0.12)
			var a1 := c + Vector2(cos(-PI * 0.1), sin(-PI * 0.1)) * r * 0.45
			ci.draw_colored_polygon(PackedVector2Array([a1 + Vector2(-r * 0.2, -r * 0.05), a1 + Vector2(r * 0.12, -r * 0.05), a1 + Vector2(-r * 0.04, r * 0.22)]), ink)
			var a2 := c + Vector2(cos(PI * 0.9), sin(PI * 0.9)) * r * 0.45
			ci.draw_colored_polygon(PackedVector2Array([a2 + Vector2(r * 0.2, r * 0.05), a2 + Vector2(-r * 0.12, r * 0.05), a2 + Vector2(r * 0.04, -r * 0.22)]), Pal.ORANGE)
