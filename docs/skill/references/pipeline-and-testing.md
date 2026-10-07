# 流水线参考：测试机器人、截图验收、性能、导出打包、服务器、Git

> 这个项目的每一轮修改都走同一个闭环：**改代码 → 机器人跑完整流程 → 看截图 → 看卡顿统计 → 打包 → 交付 → 等反馈**。下面是每一步的具体做法和命令。

---

## 1. 环境

| 东西 | 位置 / 版本 | 备注 |
|---|---|---|
| Godot | 4.5 stable 官方 Linux 可执行文件 | 不用编辑器，全部命令行 |
| 导出模板 | `~/.local/share/godot/export_templates/4.5.stable/` | 网页版用 `web_nothreads_*` 模板（iPhone Safari 不支持 SharedArrayBuffer 多线程） |
| 安卓签名 | 系统 apt 装的 `apksigner`、`zipalign` + 一个假的 SDK 目录 + debug keystore | 不需要 gradle、不需要 Android Studio |
| 虚拟显示 | `xvfb-run` + `--rendering-driver opengl3` | 截图需要真渲染；纯逻辑测试用 `--headless` |
| 浏览器测试 | Playwright + 预装 Chromium（SwiftShader WebGL） | 验证网页版能启动、无报错、能点 |
| 服务器 | Node 18+、wrangler 4（Cloudflare Workers + D1） | 本地 `wrangler dev` 就能跑完整接口 |

第一次打开工程（或新增 `class_name` 脚本后）先跑一次导入，否则会报「找不到类」：

```bash
godot --headless --path game --import
```

---

## 2. 测试机器人（`scripts/test/autotest.gd`）

### 2.1 思路

- 机器人**真的在玩游戏**：从主菜单开始 → 简报 → 关卡 → 结算，走的是和玩家完全一样的界面和输入。
- 它通过 `player.bot` 虚拟输入字典驱动角色（和触屏层同一个接口），按**步骤状态机** `_step` 推进：`boot → to_brief → brief → to_level → level_wait → play → results_wait → done`（触屏测试走 `touch`，排行榜截图走 `lbshot → lbshot_local`）。
- 关卡里的寻路直接用导航网格：找最近的敌人/目标 → `map_get_path` → 沿路点走；看得见就开火；有倒地的就去上铐；门可以破就破门；人质自由了就去救。
- 整局超过 400 秒判超时（退出码 2）；通关退出码 0，失败退出码 1。

### 2.2 命令行参数

```bash
godot --headless --path game -- --autotest                    # 完整流程
godot --headless --path game -- --autotest --god              # 无敌（只测流程，不测难度）
godot --headless --path game -- --autotest --diff=insane      # 指定难度 easy / normal / hard / insane
godot --headless --path game -- --autotest --wave             # 直接跳到僵尸潮
godot --path game -- --autotest --shots=/tmp/shots            # 保存各界面截图（需要显示 → 用 xvfb）
godot --path game --resolution 2400x1080 -- --autotest --touch --touchtest   # 注入触屏事件测试
godot --headless --path game -- --autotest --god --lb=http://127.0.0.1:8787 --lbtest   # 连本地排行榜提交成绩
godot --path game -- --autotest --lbshot --lb=http://127.0.0.1:8787 --shots=/tmp/s     # 截排行榜界面
```

截图要真渲染：

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
  --path game --resolution 1920x1080 -- --autotest --god --shots=/tmp/shots
```

### 2.3 机器人会打印的关键日志

| 日志 | 用途 |
|---|---|
| `[autotest] step xxx at 12.3` | 每一步的时间点，流程卡在哪一目了然 |
| `[autotest] RESULT {...}` / `FINAL {...}` | 本局统计（伤害、击倒、上铐、僵尸数、用时、难度）和最终评分 |
| `[perf] frames=… hitches(>50ms)=… worst=…` | 卡顿统计（见第 3 节） |
| `[hitch] 96.8ms @ level_wait` | 每一次 >50ms 的卡顿发生在哪一步 |
| `[tip] show move at 6.2` / `[tip] hide after 2.0s` / `[tip] STUCK` | 新手提示卡出现和消失；同一张卡挂超过 15 秒判为 BUG |
| `[pickup] weapon rocket want=(9.9,-6.3) at=(10.0,-6.3)` | 掉落物原定位置和修正后位置（检查是否掉进墙里） |
| `[spawn] raccoon shop want=… at=…` | 高难度追加匪徒的站位修正 |
| `[touch] RESULT PASS` | 触屏测试通过 |
| `[leaderboard] time=… \| …` | 结算页排行榜面板显示的文字 |

### 2.4 用机器人调难度的方法

- 用**不开无敌**的机器人跑同一难度 2~3 次，看 `damage`、存活时间、是否通关。
- 临时在 `Player.take_hit` 里打印每次受伤的来源和时间（`[hit] 13.8 t=3.1 from=raccoon`），对比两档难度的**每秒受伤**，判断差距是不是合理（这个项目里：中级开局 10 秒受伤约 66，高级约 140）。
- 机器人不会翻滚、不会躲掩体，所以「机器人打不过」不等于「人打不过」：高难度要用无敌模式确认流程能走完，再请真人试玩。
- 多个测试并行时会互相抢 CPU，卡顿数字只看单独跑的那次。

---

## 3. 性能：怎么找卡顿

1. 测试机器人里每帧记录真实帧时间（`Time.get_ticks_usec()`），超过 50ms 记为一次 hitch，并记下当前步骤名。
2. 第一次跑：11 次卡顿，最坏 395ms，集中在「第一次开枪」「第一次爆炸」「破门」「第一次播放某个声音」。
3. 逐个对应原因并修掉：

| 卡顿 | 原因 | 修法 |
|---|---|---|
| 第一次播放某个音效 | GDScript 循环实时合成波形 | 离线烘焙成 WAV（`scripts/tools/bake_audio.gd`），启动时预载 |
| 第一次出现某种特效 | 着色器第一次编译 | 关卡加载、转场胶带还盖着屏幕时 `_prewarm()`：在玩家附近把每种特效（枪口火光、火花、烟尘、光环、跳字、弹壳……）各放一次，让着色器提前编译 |
| 每次开枪都 new 材质 | 资源没缓存 | `Fx` 里材质、网格、贴图全部按 key 缓存 |
| 弹壳越来越多 | 无上限 | `MAX_SHELLS = 36`，弹壳离开场景树时计数减一 |
| 破门瞬间 | 运行时重新烘焙导航 | 关卡一开始就烘焙（那时还没建门，门洞是通的） |
| 加特林扫射时「粘住」 | 每次命中都顿帧 | 顿帧最长 60ms，两次之间至少隔 350ms |

结果：卡顿 11 次 → 2 次，最坏 395ms → 79ms。

---

## 4. 导出与打包

### 4.1 安卓 APK

```bash
cd game
# 只打 arm64：体积从 ~52MB 降到 ~29MB（上传限制 30MB），覆盖几乎所有现代手机
cp export_presets.cfg /tmp/presets.bak
sed -i 's/architectures\/armeabi-v7a=true/architectures\/armeabi-v7a=false/' export_presets.cfg
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/debug.keystore \
GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android \
  godot --headless --path . --export-release "Android" /out/paw-swat-v0.6.apk
cp /tmp/presets.bak export_presets.cfg        # 改回去，别把临时改动提交了
apksigner verify /out/paw-swat-v0.6.apk
```

- 每次发版改 `export_presets.cfg` 里的 `version/code`（整数，必须递增，否则不能覆盖安装）和 `version/name`。
- 权限只开 `VIBRATE` 和 `INTERNET`（排行榜）。
- `exclude_filter` 排除 `scripts/test/*`、`scripts/tools/*`、`web/*`，测试代码不进安装包。
- 正式上架要换成自己的 release keystore（不要用 debug key）。

### 4.2 网页版

```bash
godot --headless --path game --export-release "Web" /out/paw-swat-web/index.html
```

- 预设：`variant/thread_support=false`（用无线程模板，iPhone Safari、各种内置浏览器都能跑，不需要服务器发 COOP/COEP 头）。
- `html/head_include`：注入 iOS 音频解锁 + 防缩放脚本（源码 `game/web/head_include.html`，见 `mobile-controls.md` 第 7 节）。改了这个文件要同步到 `export_presets.cfg`（字符串里的 `"` 要转义成 `\"`）。
- 本地验证：`python3 -m http.server` 起服务，Playwright 打开，等 30 秒加载，截图，收集 `pageerror` 和 `console.error`；点一下屏幕后检查 `__pawAudioDebug()` 返回 `["running"]`。
- 网页版**必须通过 http(s) 打开**，双击 `index.html` 用 `file://` 打开会失败。

### 4.3 交付三件套

| 文件 | 内容 | 体积 |
|---|---|---|
| `paw-swat-vX.apk` | 安卓安装包（arm64） | ~29.7MB |
| `paw-swat-vX-web.zip` | `paw-swat-web/`（index.html + wasm + pck + 说明.txt） | ~13MB |
| `paw-swat-vX-source.zip` | `godot-project/`（整个 game 目录）+ `server/` + `docs/` + `README.md` + 说明.txt | ~5MB |

源码包用 `git archive` 生成（只包含已提交的文件，不会带上缓存和临时文件）：

```bash
git archive --format=tar HEAD game server README.md docs | tar -x -C src
mv src/game src/godot-project
python3 -c "import shutil; shutil.make_archive('paw-swat-v0.6-source', 'zip', 'src')"
```

每个包都带一份 `说明.txt`：怎么安装、怎么玩、已知限制。单个文件要小于 30MB（聊天上传上限），所以 APK 只打 arm64，三个文件分开发。

---

## 5. 排行榜服务器

```bash
cd server/leaderboard
npm install
npm run db:init:local            # 本地建表
npx wrangler dev --port 8787     # 本地服务
node test/api_test.mjs           # 接口 + 防作弊测试（十几项，全部 PASS 才算过）
node test/api_test.mjs http://127.0.0.1:8787 --wait   # 额外真实等 76 秒提交一局合法成绩
```

- 测试覆盖：注册、错误恢复码、太快、令牌重复使用、上报时间大于服务器测得时间、未完成关卡、非法难度、难度绑定在令牌上（提交时改难度无效）、找回、改名、各难度榜单互不影响。
- 部署：`wrangler login` → `wrangler d1 create` → 把 `database_id` 填进 `wrangler.toml` → `npm run db:init` → `npm run deploy` → 把网址填进 `game/leaderboard.cfg`。从旧版升级用 `npm run db:migrate`。
- 修改校验规则（比如加难度、改最低击倒数）时，**测试数据也要跟着改**：v0.6 把鬼畜的最低击倒数提高到 19 后，测试里的 `downs: 12` 就提交不上了。

---

## 6. Git 习惯

- 只在指定的功能分支上开发和推送；每一轮反馈一个提交（或几个），提交说明写清楚「改了什么 + 为什么」。
- 提交前确认没有把临时改动带进去（例如打包时临时关掉的 armv7、调试用的 `print`）。
- 大文件（APK、zip、截图）放在仓库外的临时目录，不提交。
- 每次推送后再打包，保证交付的源码包和远程分支一致。
