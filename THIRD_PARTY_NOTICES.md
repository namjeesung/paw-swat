# 第三方组件与素材许可

根目录的 `LICENSE` 仅适用于 namjeesung 拥有版权并有权授权的原创内容。第三方代码、字体、素材及依赖保留各自的原许可；本项目的非商业限制不修改它们的许可。

## 随源码分发的字体

| 字体文件 | 随包版权声明 | 许可 |
| --- | --- | --- |
| `ZCOOLKuaiLe-Regular.ttf` | Copyright 2018 The ZCOOL KuaiLe Project Authors | [SIL Open Font License 1.1](GodotProject/assets/fonts/OFL-zcoolkuaile.txt) |
| `NotoSansSC-Medium.ttf`、`NotoSansSC-Black.ttf` | 随附许可列出 Copyright 2014–2021 Adobe，Reserved Font Name “Source” | [SIL Open Font License 1.1](GodotProject/assets/fonts/OFL-notosanssc.txt) |
| `Bungee-Regular.ttf` | Copyright 2023 The Bungee Project Authors | [SIL Open Font License 1.1](GodotProject/assets/fonts/OFL-bungee.txt) |

字体版权声明按随包文件记录，不代表已独立核验每个字体二进制的来源。再分发或修改字体时，须遵守对应 OFL 全文，包括保留版权、许可及适用的保留字体名称要求。

## 引擎、平台接口与服务依赖

- **Godot**：运行和导出需使用 Godot 引擎。引擎及导出模板的许可独立于本项目。发布包含引擎的游戏构建时，请遵循 [Godot 官方许可与署名要求](https://godotengine.org/license/)；本仓库未打包引擎二进制。
- **B 站 Toy SDK**：Web 集成通过 `GodotProject/web/head_include.html` 引用平台 SDK。平台 SDK、账号与排行榜服务须遵循其自身条款；本项目许可不授予这些第三方服务的权利。
- **Cloudflare Wrangler 及依赖**：`server/leaderboard/package.json` 与 `package-lock.json` 声明独立排行榜服务的开发依赖。仓库未提交 `node_modules`；安装与再分发相关依赖时须保留并遵守依赖各自的许可。

如果后续加入第三方代码、模型、图片、音乐或其他素材，应在此补充来源与许可，并保留原许可文件。
