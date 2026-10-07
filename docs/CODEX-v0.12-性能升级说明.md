# 给 Codex：v0.12「极致流畅」改了什么 + 剩下要做什么

> 基线：用户的 v0.11（网页 3–5 FPS、手机 10–20 FPS）。本轮只做性能，不改玩法数值。
> 详细做法、代码片段、坑：`docs/skill/references/performance.md`（请并入 SKILL）。

## 一、已完成（都已提交，回归测试通过）

| 方向 | 改动 | 文件 |
|---|---|---|
| 测量 | `--autotest --perfprobe`：每 3 秒打印真实绘制调用 / 三角形 / 灯光 / 按角色分类的网格与面数；`physmark` 测每个物理步的脚本耗时 | `scripts/test/perf_probe.gd` `physmark.gd`（不进发行包） |
| 角色合批 | `CharModel.bake()`：同一动画节点下的零件合成一个顶点色网格，每角色 2 个材质（描边/无描边），全局缓存 | `core/char_model.gd`，`models.gd` 去掉旧 `batch_rigid_parts` 调用 |
| 降面 | 球按半径 12/8/6 段；胶囊 12×2；圆柱 12；圆环 16×6 | `core/models.gd` |
| 静态合批 | `MapBuilder.bake_static()`：墙/货架/箱子按材质外观合成顶点色网格（153→45 个网格） | `world/map_builder.gd` |
| 流畅画质 | `Game.lite`（网页/手机默认，`--lite`/`--hq` 切换）：关实时阴影、SSAO、所有点光源（拾取光、枪口光、爆炸光），环境光 0.55→0.82 | `autoload/game.gd` `world/level.gd` `map_builder.gd` `pickup.gd` `core/fx.gd` |
| 渲染器 | 安卓改 `gl_compatibility`（和网页一致，不再要求 Vulkan），关 FXAA | `project.godot` |
| 物理 | lite：30Hz 物理 + 物理插值，追帧上限 3；关卡根节点插值 OFF，Actor/子弹/弹壳 ON；相机跟随插值位置；鼠王瞬移后 `reset_physics_interpolation()` | `game.gd` `actor.gd` `bullet.gd` `level.gd` `game_camera.gd` `zombie.gd` `fx.gd` |
| AI 开销 | 僵尸互相推开每 3 帧算一次（错开）；僵尸隔帧才完整 `move_and_slide`（另一帧低速直接平移）；`max_slides=3`；晕倒不动的匪徒跳过碰撞移动；匪徒视线射线 0.12 秒一次；头顶倒计时只在整秒改字 | `zombie.gd` `actor.gd` `enemy.gd` |
| HUD | 狗牌血条、弹药面板、目标横幅、对讲框、提示卡只在内容变化/有动画时重画（狗牌原来每帧 ~1ms） | `ui/hud_widgets.gd` `radio.gd` `tip_cards.gd` |
| 场面 | 上铐 3 秒后「押走」：缩小消失、停止处理 | `actors/enemy.gd` |

### 实测（鬼畜、23 匪徒 + 34 僵尸 + 鼠王，云端软件渲染，只比可横向比较的指标）

| 指标 | v0.11 | v0.12 lite |
|---|---|---|
| 每帧绘制调用 | 2,782–4,210 | 580–1,000 |
| 每帧三角形 | 87 万–164 万 | 12–19 万 |
| 动态灯 / 阴影 | 14–19 / 开 | 1 / 关 |
| 物理脚本 CPU | 4.1ms/步 × 60 = 约 246ms/秒 | 4.7ms/步 × 30 = 约 141ms/秒（−43%） |

### 回归
- 用户 QA：shield_regression 43/43、heal_budget_regression 110/110、heal_tip_metrics 9/9（60Hz 和 `--lite` 30Hz 都通过）
- 自动通关：普通（lite，无无敌）、初级（无无敌）、高级/鬼畜（无敌）全部通关；截图检查 lite 与 hq 画面基本一致

## 二、没做完 / 建议 Codex 接着做（按收益排序）

1. **真机测帧率**（最重要）：网页（Safari / 微信 / B站内置浏览器）和安卓 APK 各跑一局鬼畜僵尸潮，记录 FPS。云端只有软件渲染，帧率无法在这里验证。
2. **剩余 CPU 热点**：僵尸每步 ~90µs（`move_and_slide` ~35µs 占大头），被唤醒参战的匪徒每步 ~110µs，玩家被围时 `move_and_slide` ~125µs。可做：远离玩家（>12m）的僵尸 AI 降频（每 2–3 步一次决策）；匪徒 `_separate` 也错帧；考虑用 Jolt（本轮测试差别不大，未启用）。
3. **网页音频**：v0.11 把网页播放模式设为 Stream（`audio/general/default_playback_type.web=0`），无线程网页版的 Stream 模式在主线程混音，掉帧时会占 CPU、出爆音。可评估改回 Sample 模式（注意 v0.11 的音频修复经验，需真机听）。
4. **触屏层 `_draw`** 每帧 ~0.6ms：静态按钮外观可缓存（拆成静态控件 + 只重画动态部分）。
5. **动态分辨率**：若真机仍 <30FPS，在 lite 下根据实测帧时间自动降低 `scaling_3d_scale`（目前固定按 1280×720 像素预算）。
6. **Label3D**：场上 30–60 个（倒计时、跳字），可只显示离玩家最近的几个倒计时。
7. 画质选项进暂停菜单（流畅 / 精美），目前只能命令行切换。

## 三、注意

- APK 用本仓库 debug 签名，包名沿用 `com.niko.pawswat.test`；如果手机上装着 v0.11 测试签名的版本，需要先卸载再装。
- 本轮用 Godot 4.5 导出（工程声明仍是 4.5）；v0.11 用 4.6.3 导出，两者都能打开工程。
- 新加角色/道具/灯光时遵守 `performance.md` 第 5 节的 8 条规则，每次改完跑 `--perfprobe` 对比。
