> 历史记录；当前版本以根目录README-中文.md和Docs/QA/v0.11为准。

# 可复现检查

以下命令从整包解压后的根目录运行。Godot使用官方4.6.3标准版，Node使用已安装的正常版本。测试在本机保存JSON；它们不会证明浏览器可听输出。没有设置排行榜URL，不会向服务器提交成绩。

- 源码导入：`godot --headless --path GodotProject --import`
- 护盾实际类回归：`godot --headless --path GodotProject res://scripts/test/qa/shield_regression.tscn`
- 完整中级流程（不启用永久测试无敌）：`godot --headless --path GodotProject -- --autotest --diff=normal`
- 原生可见护盾场景：`godot --rendering-method gl_compatibility --path GodotProject res://scripts/test/qa/visual_driver.tscn`
- Web音频桥接模拟：`node Docs/QA/test_audio_bridge.cjs GodotProject/web/head_include.html`
- 源码音频状态：`godot --headless --path GodotProject --script "$PWD/Docs/QA/verify_audio.gd"`
- 导出PCK护盾与伤害逻辑：`godot --headless --main-pack Web/index.pck --script "$PWD/Docs/QA/packed_shield_driver.gd"`
- 导出PCK音频资源与发行隔离：`godot --headless --main-pack Web/index.pck --script "$PWD/Docs/QA/verify_packed_audio.gd"`
- 旧桥接缺陷复现：`node Docs/QA/reproduce_original_bridge.cjs`（仅使用随包历史HTML，模拟拒绝；不连接服务）

Windows可用对应Godot命令行程序，并把`$PWD`改为解压目录绝对路径。原生图像需要实际图形桌面；headless不能证明画面。截图默认写入用户数据目录，可加 `-- --qa-shots=绝对目录`。QA场景用于定向检查，会直接设置状态/拾取，不是人工游玩；普通完整流程另测。

脚本保存在源码` scripts/test/`下，Web发行预设排除该整个目录。网页构建中没有QA代码或`--god`持续恢复生命逻辑。
