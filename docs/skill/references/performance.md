# 性能参考：手机 / 网页「极致流畅」的做法（v0.12）

> 背景：v0.11 实测网页 3–5 FPS、手机 10–20 FPS。v0.12 用下面的方法把**每帧绘制调用砍到约 1/4、三角形砍到约 1/7、动态灯从 16 盏到 1 盏、物理脚本开销减到约 1/3**。
> 云端只有软件渲染（llvmpipe），帧率本身没参考价值；所以只比较和手机 GPU / CPU 负担**直接相关、又不依赖显卡的指标**：绘制调用数、三角形数、灯光数、每个物理步的脚本耗时。

---

## 1. 先测量，再优化

### 1.1 绘制负担探针 `scripts/test/perf_probe.gd`

`--autotest --perfprobe` 时每 3 秒打印一次：

```
[perfprobe] t5 phase=5 zombies=20 REAL draws=663 prims=125460 objects=886 | lights=1 (shadow 0) label3d=39 ...
[perfprobe]    bandit     meshes= 253 passes=  391 tris= 119322
[perfprobe]    zombie     meshes=  70 passes=  125 tris=  ...
[perfprobe]    level/fx   meshes=  45 passes=   49 tris=   4884
```

- `REAL draws / prims / objects`：`RenderingServer.get_rendering_info()`，本帧真实提交的绘制调用、图元、物体（**必须真渲染**：`xvfb-run … --rendering-driver opengl3`，`--headless` 下全是 0）。
- 分类统计：遍历所有可见 `MeshInstance3D`，按所属角色类型归类；`passes` = 材质链长度（`next_pass` 描边会让一个网格画两次），`tris` = 三角形 × passes。
- 第一次报告还会打印每类第一个角色身上的**每个网格**（`[perfdetail]`），一眼看出哪个零件是面数大户。
- 同一场景（`--god --wave --diff=insane`：23 个晕倒匪徒 + 最多 34 只僵尸 + 鼠王）做前后对比。

### 1.2 物理帧脚本耗时 `scripts/test/physmark.gd`

两个节点：`process_physics_priority = -100000` 的在物理帧最开始记时间，`+100000` 的在最后记时间，差值 = 本物理步所有 `_physics_process` 脚本的总耗时：

```
[physmark] steps=90 scripts=3.84ms/step (11.6% of wall time in physics scripts)
```

### 1.3 定位到函数：在**副本**里插桩

不要在源码里留计时代码。复制一份工程到临时目录，用脚本把每个 `func _physics_process(d)` / `_process` / `_draw` 改名为 `_xxx_inner` 并包一层计时，汇总到一个静态字典，按耗时排序打印：

```
[prof] zombie_total=90us/call  sepmove=61us  move_and_slide(Zombie)=37us  animate=7us  nav=7us  move_and_slide(Player)=125us
[prof] hud_widgets.draw#2=1.03ms/f  touch_controls.draw#2=0.60ms/f  level.process#1=0.55ms/f
```

这一步找到了「僵尸互相推开是 O(n²)」「狗牌血条每帧重画 1ms」这类肉眼看不出的问题。

---

## 2. 渲染：绘制调用和三角形

### 2.1 角色烘焙合批（最大的一项）`CharModel.bake()`

**问题**：角色由几十个小几何体拼成，每个零件 1 次绘制 + 1 次描边 = 一个角色 50–60 次绘制、1.5–2 万个三角形；40 个角色就是 2000+ 次绘制。

**做法**：模型进入场景树时（`CharModel._ready()`），对每个「会动的节点」（Pose / Body / Head / Gun / 两只脚 / 尾巴 / 手铐），把它下面所有零件合成**一个** `ArrayMesh`：

```gdscript
for part in parts:                         # 同一节点、同一类材质（有描边 / 无描边）
	var xf := part.transform
	var nb := xf.basis.inverse().transposed()  # 法线用逆转置矩阵（零件有非均匀缩放）
	var col := part.material_override.albedo_color
	for v in arrays[ARRAY_VERTEX]:
		verts.append(xf * v); norms.append((nb * n).normalized()); cols.append(col)
	# 索引加偏移……
```

- 颜色写进顶点色，整个角色只用**两个材质**：`vertex_color_use_as_albedo = true`、`vertex_color_is_srgb = true`（否则颜色发灰），一个带描边 `next_pass`、一个不带。
- 每个角色有自己的两个材质 → 受击闪白（改 emission）、改描边颜色、残影都照常工作，不会一只闪全体闪。
- 合并后的网格按「零件 mesh RID + 变换 + 颜色」的哈希**全局缓存**：生成第 30 只僵尸时没有任何合并开销。
- 动画不受影响：动的是节点，合并只发生在节点内部。
- 结果：一个角色 50+ 次绘制 → 约 14–17 次。

**坑**：

- 遍历时不能直接对 `find_children()` 的结果边遍历边释放零件——先把「挂零件的节点」收集出来（不含零件本身），否则后面访问到已释放的对象，脚本报错并**中断**，只合并了一半。
- 描边用的是「法线外扩」（`grow`）：合并前零件的非均匀缩放会让描边粗细不一，合并后反而更均匀，视觉上可以接受。

### 2.2 基础几何体降面

角色在屏幕上只有几十像素高：

| 几何体 | 原来 | 现在 |
|---|---|---|
| 球 | 20 段 × 10 环（约 400 三角形） | 半径 ≥ 0.15：12×6；≥ 0.06：8×4；更小（眼睛、鼻头）：6×3 |
| 胶囊 | 18 段 × 6 环 | 12 段 × 2 环 |
| 圆柱 | 18 段 | 12 段 |
| 圆环 | 24 × 10 | 16 × 6 |

### 2.3 静态场景合批 `MapBuilder.bake_static()`

墙、货架、柜台、纸箱……原来 150 多个网格。建完场景后按「材质外观」（光照模式、高光、粗糙度、边缘光、描边颜色/粗细）分组合成顶点色网格 → 45 个。

- 不动：有贴图的（地板格子）、透明的（玻璃门会开合）、自发光的（霓虹）、警车（结局会开走）。
- 碰撞体完全不受影响（导航网格从碰撞体烘焙）。
- **坑**：`root.find_children()` 已经包含了子节点 `geo` 的内容，再加一遍 `geo.find_children()` 会重复，释放第二次时报错中断。
- 货架上的商品小方块本来就用 `MultiMeshInstance3D`（一次绘制），保持。

### 2.4 流畅画质 `Game.lite`（手机和网页默认开）

| 项 | 精美 | 流畅 | 原因 |
|---|---|---|---|
| 月光实时阴影 | 开 | 关 | 阴影要把所有投影物体再画一遍；角色脚下本来就有圆形假阴影 |
| SSAO | 开 | 关 | 只在 Forward+ 有效，很贵 |
| 场景点光源（路灯、店内灯、警灯、闪烁灯） | 14–19 盏 | 0（节点隐藏） | **Compatibility 渲染器（网页、现在的安卓）里每盏点光会让被照到的物体多画一遍** |
| 拾取物光、枪口闪光、爆炸光 | 有 | 无 | 同上，用自发光模型和光环特效代替 |
| 环境光 | 0.55 | 0.82 | 补偿没有点光源后的亮度 |

- 安卓渲染器改成 `gl_compatibility`（和网页一致）：中低端机更快，也不再要求 Vulkan，能装的手机更多。
- 电脑上 `-- --lite` 预览流畅画质，`-- --hq` 强制精美画质。
- 隐藏的灯（`visible = false`）不参与渲染；关卡里改灯光亮度的代码（警灯闪烁等）不用改。

### 2.5 「押走」：上铐的匪徒 3 秒后消失

上铐 3 秒后弹「押走」、缩小消失，然后 `visible = false`、`process_mode = DISABLED`。场面更干净，后半程少画十几个角色、少算十几个物理体。节点保留在 `enemies` 里，「全员落网」之类的统计照常。

---

## 3. CPU：物理帧和每帧逻辑

### 3.1 30Hz 物理 + 物理插值（流畅画质）

在手机 / 网页 CPU 上，34 只僵尸时每个物理步的脚本要 15–25ms；60Hz 根本跑不完，引擎就在一帧里补算最多 12 步物理 → 更慢 →「死亡螺旋」（网页 3–5 FPS 的直接原因）。

```gdscript
if lite:
	Engine.physics_ticks_per_second = 30
	Engine.max_physics_steps_per_frame = 3      # 10 FPS 也能保持正常速度；更慢时只是略微变慢，不会螺旋
	get_tree().physics_interpolation = true     # 画面按屏幕刷新率在两个物理帧之间插值
```

- 关卡根节点 `physics_interpolation_mode = OFF`（相机、特效、UI 都在 `_process` 里每帧更新，不需要插值）；`Actor._enter_tree()`、`Bullet`、弹壳打开 `ON`（它们在物理帧里移动）。
- 相机跟随**插值后**的位置：`target.get_global_transform_interpolated().origin`，否则相机按 30Hz 一顿一顿。
- 瞬移（鼠王传送、测试里传送玩家）后调用 `reset_physics_interpolation()`，否则会画出一道拖影。
- 所有移动都乘了 `delta`，30Hz 下手感一致；子弹用「上一位置 → 下一位置」射线检测，不会因为步长变大而穿过目标。

### 3.2 每个物理步更便宜

| 改动 | 效果 |
|---|---|
| 僵尸互相推开：每 3 个物理步算一次（不同僵尸错开），中间复用结果；先比较 \|dx\|、\|dz\| 再开方 | O(n²) 的部分降到 1/3 |
| 僵尸隔一步才做完整 `move_and_slide`，另一步直接 `position += v·dt`（只在一步 < 0.1 米时；下一次完整移动会把轻微嵌入推出去，不会穿墙）；鼠王始终完整移动 | 碰撞移动开销减半 |
| `max_slides = 3`（默认 6）：俯视角只在平面上滑墙 | 人多时的碰撞开销 |
| 晕倒且不动的匪徒不做 `move_and_slide` | 场上常躺十几个 |
| 匪徒的视线射线每 0.12 秒检测一次（原来每步） | 射线查询 |
| 头顶倒计时文字只在整秒变化时改（`Label3D` 改字会重建网格） | 小 |

物理脚本：约 5.5ms/步 → 约 3.7ms/步（桌面原生，最重的测试场景），再加上 30Hz，每秒的物理脚本开销约为原来的 1/3。

### 3.3 HUD：只在内容变化时重画

原来每个 HUD 控件每帧 `queue_redraw()`。最贵的是狗牌血条（头像 + 10 段血条 + 文字，每帧约 1ms，网页上 3–4ms）。

```gdscript
var sig := "%d|%d|%d|%s|%s" % [ceili(hp), int(ghost), int(max_hp), in_cover, buff]
if sig != _sig or _shake > 0.0 or hp / max_hp <= 0.3:   # 变化 / 抖动 / 残血闪烁时才重画
	_sig = sig
	queue_redraw()
```

- 狗牌的轻微摇摆改用控件自身的 `rotation`（改变换不需要重画），抖动才用 `draw_set_transform`。
- 目标横幅：文字不变就不重画。弹药面板：数字、武器、换弹、强化、神装发光变化时才重画。对讲框、提示卡：看不见时不重画。
- 触屏按键层每帧都在变（摇杆、准星、冷却），保持每帧重画。

---

## 4. 结果（同一测试场景：鬼畜难度、23 个匪徒、最多 34 只僵尸 + 鼠王）

| 指标 | v0.11 | v0.12 流畅画质 |
|---|---|---|
| 每帧绘制调用 | 2,782–4,210 | 约 580–1,000 |
| 每帧三角形 | 87 万–164 万 | 约 12–19 万 |
| 动态灯 / 实时阴影 | 14–19 / 开 | 1 / 关 |
| 物理频率 | 60Hz（追帧上限 12） | 30Hz + 插值（追帧上限 3） |
| 物理脚本（桌面原生） | 约 5.5ms/步 × 60 | 约 3.7ms/步 × 30 |
| 狗牌血条重画 | 每帧 ~1ms | 只在变化时 |

**没有验证的**：真实手机 / 浏览器的帧率（云端只有软件渲染）。上面这些指标和手机负担直接相关，但最终帧率要在真机上看。

---

## 5. 以后加东西时的性能规则

1. 新角色 / 新道具用 `CharModel` 拼就自动烘焙；不要在模型上存某个零件的引用（烘焙后零件会被释放），要单独控制的部分放在单独的节点下。
2. 不要加新的 `OmniLight3D` / `SpotLight3D`；需要「亮」用自发光材质 + 环境光，或者只在 `not Game.lite` 时加。
3. 场景里的静态装饰用 `MapBuilder.deco()` / `solid()`，会被自动合批；会动的东西放在单独的父节点下（像警车）。
4. 同类小物件很多时用 `MultiMeshInstance3D`。
5. 物理帧里每只怪都做的事要问：能不能每 N 帧做一次、错开做？能不能先用便宜的比较排除？
6. HUD 自绘控件只在变化时 `queue_redraw()`；纯摇摆/缩放用控件自身的 `rotation` / `scale`。
7. 在物理帧里移动的新节点要打开物理插值；瞬移后 `reset_physics_interpolation()`。
8. 每次改完跑一遍 `--perfprobe`，绘制调用和三角形不能比上一版涨。
