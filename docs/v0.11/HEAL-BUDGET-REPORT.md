> 历史记录；当前版本以根目录README-中文.md和Docs/QA/v0.11为准。

# PAW S.W.A.T. 医疗补给限额：独立回归记录

## 结果

- 本次实际引擎为 Godot 4.6.3 stable official；工程保留 4.5 特性声明
- 最新生产源码隔离副本导入退出码 0，无解析错误
- 医疗补给 110/110 检查通过，退出码 0，无脚本错误、资源错误或退出警告
- 保留原 43 项护盾测试，针对医疗限额修改后的源码再次运行仍为 43/43 通过；此旧场景依旧有已记录的一个 SceneTreeTimer 退出警告
- 最新缩短的补给提示实际字体/版面度量 9/9 通过：四档均 3 行、内容高 104px，小于正文 108px；正文宽 422px、普通字 21/粗体 22。文案显示已捕获的本局限额。此为 headless RichTextLabel/TextServer 度量，不是渲染截图
- 本记录验证最新医疗改动，未额外修改音频、GUI或导出，也没有联网计分或发布

## 规则与覆盖

四个实际难度每局最多成功生成医疗补给 1 / 2 / 3 / 4 次：初级 easy、中级 normal、高级 hard、鬼畜 insane。限额按本局启动时的难度捕获，记录的是“生成”，而非“拾取”。

实际类断言验证：

1. 每档初始计数为 0，每成功生成一件才扣预算；Level 和 Game.run.heal_drops 记录一致
2. 原有僵尸潮定时空投、真实鼠王死亡和集中 spawn_pickup 调用共同消耗同一预算，互相不能绕过；地上已有医疗补给时不会重叠生成
3. 满血进入真实自动拾取距离时，道具留在地上、计数不退；“生命已满”提示只出现一次，不每帧重启动画
4. 受伤后同一件道具能正常拾取，最多恢复 35 HP；重复调用拾取方法不再回血、弹字或消耗预算
5. 缺血 60 时实际恢复 35 并显示 +35；只缺 10 时封顶至最大血量并显示 +10，没有错误显示 +35
6. 未拾取道具即已计入本局生成预算；人为移除未拾取道具也不能退还名额
7. 超出总额、死亡、关卡结束或没有玩家时生成返回 null，计数保持不变；死亡/结束状态不能拾取旧道具
8. 暂停/继续保留预算与地上补给；中途改变所选难度不改写已捕获限额；实际 Game.goto 重开清零并捕获当前选择，新局同样清零
9. 医疗预算耗尽不会挡住武器或护盾生成、护盾授予，也不会改变原 5 秒护盾机制

测试包含 109 条行为断言与 1 条完整性断言，避免部分测试因异常提前返回却误报完成。详细结果见 heal-budget-regression-report.json；测试副本与当前源码对应文件的哈希见 heal-budget-source-manifest.json。另见 heal-tip-metrics-report.json 与 shield-regression-after-heal-budget-report.json。

## 复现与边界

开发测试文件在 heal-budget-tests/，复制到 GodotProject/scripts/test/qa/ 后运行：

    godot --headless --path GodotProject --import
    godot --headless --path GodotProject res://scripts/test/qa/heal_budget_regression.tscn

报告默认存入 user://heal-budget-regression-report.json。推荐使用独立 XDG 测试目录，以免改动已有游戏设置。发行时仍排除 scripts/test/*。

本记录仅证明当前源码的实际逻辑。没有新 Web 浏览器、原生听音、手机或截图验收，也没有在新医疗规则下声称完整普通难度通关。用户反馈的 Web 静音问题仍待定位，本轮医疗回归不表示音频已修好。
