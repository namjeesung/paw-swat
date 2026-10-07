# 爪爪特警 · 云端排行榜服务器

Cloudflare Workers + D1（SQLite）实现的「最速通关榜」。免费额度足够个人项目使用。

## 功能

- **游客身份**：首次联网自动注册「游客 ID + 昵称」，并生成一个**恢复码**（`PAW-XXXX-XXXX-XXXX`）。
  同一浏览器 / 同一台手机自动保留身份；换设备时在游戏「排行榜 → 用恢复码找回」输入即可。
  服务器只保存恢复码的哈希。
- **防刷榜校验**（`src/index.js` 顶部有详细说明）：
  1. 每局开始向服务器领取一次性令牌，服务器记录开局时间；
  2. 上报用时不能比服务器实际经过的时间更短（改网页里的数字无法“变快”）；
  3. 不能低于关卡物理下限（僵尸潮固定 60 秒，`MIN_TIME_MS = 75000`）；
  4. 必须真的完成了关卡（人质获救、击倒匪徒、打过僵尸潮）；
  5. 每个令牌只能提交一次，每人每小时最多开 60 局；
  6. 难度（初级 / 中级 / 高级 / 鬼畜）在开局领令牌时绑定，提交时不能改，每个难度单独排名。

  它挡得住“直接改分数 / 伪造请求”，但挡不住“改了客户端后真的打得更快”。
  如果以后要做有奖比赛，建议再加录像回放校验或人工审核。

## 部署（约 5 分钟）

需要：Node.js 18+、一个 Cloudflare 账号（免费）。

```bash
cd server/leaderboard
npm install
npx wrangler login                       # 浏览器里登录 Cloudflare
npx wrangler d1 create paw-swat          # 记下输出里的 database_id
# 把 database_id 填进 wrangler.toml
npm run db:init                          # 建表
npm run deploy                           # 部署，输出网址如 https://paw-swat-leaderboard.xxx.workers.dev
```

然后把网址填进游戏工程的 `game/leaderboard.cfg`：

```ini
[server]
url="https://paw-swat-leaderboard.xxx.workers.dev"
```

重新导出 APK / 网页版即可。留空则只记录本机成绩。

**从 v0.4 升级**（已经部署过旧版数据库）：执行一次 `npm run db:migrate`（给成绩加“难度”列，旧成绩算作中级），再 `npm run deploy`。

## 本地开发与测试

```bash
npm install
npm run db:init:local
npm run dev                               # http://127.0.0.1:8787
node test/api_test.mjs                    # 接口 + 防作弊测试
node test/api_test.mjs http://127.0.0.1:8787 --wait   # 额外跑一局真实等待 76 秒的合法提交
```

游戏连本地服务器：`godot --path game -- --lb=http://127.0.0.1:8787`

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/register` | `{nickname}` → `{player_id, nickname, recovery_code}` |
| POST | `/api/restore` | `{recovery_code}` → 找回身份 |
| POST | `/api/rename` | `{player_id, secret, nickname}` |
| POST | `/api/run/start` | `{player_id, secret, difficulty}` → `{run_token}`（difficulty：easy / normal / hard / insane） |
| POST | `/api/run/finish` | `{player_id, secret, run_token, time_ms, stats}` → `{rank, best_ms, new_best}` |
| GET | `/api/leaderboard?difficulty=normal&limit=50` | 该难度每人最好成绩，按用时升序 |
