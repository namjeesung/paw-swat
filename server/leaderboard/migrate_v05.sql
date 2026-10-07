-- 旧版本（v0.4）已部署的数据库升级：给成绩加“难度”列。新部署直接用 schema.sql 即可。
ALTER TABLE runs ADD COLUMN difficulty TEXT NOT NULL DEFAULT 'normal';
ALTER TABLE scores ADD COLUMN difficulty TEXT NOT NULL DEFAULT 'normal';
DROP INDEX IF EXISTS scores_time;
DROP INDEX IF EXISTS scores_player;
CREATE INDEX IF NOT EXISTS scores_diff_time ON scores(difficulty, time_ms);
CREATE INDEX IF NOT EXISTS scores_player ON scores(player_id, difficulty, time_ms);
