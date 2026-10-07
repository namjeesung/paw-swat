-- 爪爪特警 · 最速通关排行榜（Cloudflare D1 / SQLite）

CREATE TABLE IF NOT EXISTS players (
  id            TEXT PRIMARY KEY,          -- 游客 ID（UUID）
  nickname      TEXT NOT NULL,
  secret_hash   TEXT NOT NULL UNIQUE,      -- 恢复码的 SHA-256（服务器不存明文）
  created_at    INTEGER NOT NULL
);

-- 每局开始时领取的令牌：服务器记录开局时间，用来校验成绩
CREATE TABLE IF NOT EXISTS runs (
  token         TEXT PRIMARY KEY,
  player_id     TEXT NOT NULL,
  started_at    INTEGER NOT NULL,
  difficulty    TEXT NOT NULL DEFAULT 'normal',   -- easy / normal / hard / insane（开局时绑定）
  used          INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS runs_player ON runs(player_id, started_at);

CREATE TABLE IF NOT EXISTS scores (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id     TEXT NOT NULL,
  time_ms       INTEGER NOT NULL,          -- 通关用时（越短越好）
  rating        TEXT NOT NULL,
  difficulty    TEXT NOT NULL DEFAULT 'normal',   -- 每个难度单独排名
  server_ms     INTEGER NOT NULL,          -- 服务器测得的开局→提交时长（审计用）
  created_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS scores_diff_time ON scores(difficulty, time_ms);
CREATE INDEX IF NOT EXISTS scores_player ON scores(player_id, difficulty, time_ms);
