// 爪爪特警 · 最速通关排行榜（Cloudflare Worker + D1）
//
// 身份：游客 ID + 昵称；“恢复码”既是登录凭证也是跨设备找回方式（服务器只存哈希）。
// 防刷榜：每局开始向服务器领令牌，服务器记录开局时间；提交时校验
//   1) 令牌存在、属于本人、只能用一次；
//   2) 上报用时 ≤ 服务器实际经过的时间（+少量网络容差）——改网页数字无法“变快”；
//   3) 上报用时 ≥ 关卡物理下限（僵尸潮固定 60 秒等）；
//   4) 关键统计合理（人质获救、清掉了店里的匪徒、打过僵尸潮）。
// 这不能防住“改客户端真实地打得更快”，但能挡住直接改分数/伪造请求。

const MIN_TIME_MS = 75_000;        // 坚守 60 秒 + 前面流程的理论最低值
const MAX_RUN_MS = 60 * 60_000;    // 一局最多 1 小时
const CLOCK_SLACK_MS = 3_000;      // 网络/时钟容差
const MAX_NICK = 12;
const RUNS_PER_HOUR = 60;          // 每人每小时最多开局数（防滥用）
const DIFFICULTIES = ["easy", "normal", "hard", "insane"];   // 初级 / 中级 / 高级 / 鬼畜，各自单独排名
// 每个难度至少要击倒的匪徒数（店面全部 + 劫持者）
const MIN_DOWNS = { easy: 7, normal: 9, hard: 13, insane: 19 };

function cleanDiff(d) {
  d = String(d ?? "normal");
  if (!DIFFICULTIES.includes(d)) throw new ApiError("bad_difficulty");
  return d;
}

export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
    try {
      const url = new URL(req.url);
      const p = url.pathname;
      if (req.method === "GET" && p === "/api/leaderboard") return json(await leaderboard(env, url));
      if (req.method === "POST") {
        const body = await req.json().catch(() => ({}));
        switch (p) {
          case "/api/register": return json(await register(env, body));
          case "/api/restore": return json(await restore(env, body));
          case "/api/rename": return json(await rename(env, body));
          case "/api/run/start": return json(await runStart(env, body));
          case "/api/run/finish": return json(await runFinish(env, body));
        }
      }
      return json({ error: "not_found" }, 404);
    } catch (e) {
      if (e instanceof ApiError) return json({ error: e.code }, e.status);
      return json({ error: "server_error" }, 500);
    }
  },
};

class ApiError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}

function cors(res) {
  res.headers.set("Access-Control-Allow-Origin", "*");
  res.headers.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.headers.set("Access-Control-Allow-Headers", "Content-Type");
  return res;
}

function json(obj, status = 200) {
  return cors(new Response(JSON.stringify(obj), {
    status, headers: { "Content-Type": "application/json; charset=utf-8" },
  }));
}

async function sha256(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// 恢复码：PAW-XXXX-XXXX-XXXX（去掉易混淆字符）
function newRecoveryCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  let s = "";
  for (let i = 0; i < 12; i++) {
    s += alphabet[bytes[i] % alphabet.length];
    if (i === 3 || i === 7) s += "-";
  }
  return "PAW-" + s;
}

function cleanNick(n) {
  n = String(n ?? "").replace(/[\u0000-\u001f\u007f<>]/g, "").trim();
  if (!n) throw new ApiError("bad_nickname");
  return [...n].slice(0, MAX_NICK).join("");
}

async function auth(env, body) {
  const id = String(body.player_id ?? "");
  const secret = String(body.secret ?? "").toUpperCase().trim();
  if (!id || !secret) throw new ApiError("unauthorized", 401);
  const row = await env.DB.prepare("SELECT id, nickname FROM players WHERE id = ? AND secret_hash = ?")
    .bind(id, await sha256(secret)).first();
  if (!row) throw new ApiError("unauthorized", 401);
  return row;
}

async function register(env, body) {
  const nickname = cleanNick(body.nickname);
  const id = crypto.randomUUID();
  const code = newRecoveryCode();
  await env.DB.prepare("INSERT INTO players (id, nickname, secret_hash, created_at) VALUES (?, ?, ?, ?)")
    .bind(id, nickname, await sha256(code), Date.now()).run();
  return { player_id: id, nickname, recovery_code: code };
}

async function restore(env, body) {
  const code = String(body.recovery_code ?? "").toUpperCase().trim();
  const row = await env.DB.prepare("SELECT id, nickname FROM players WHERE secret_hash = ?")
    .bind(await sha256(code)).first();
  if (!row) throw new ApiError("bad_code", 404);
  return { player_id: row.id, nickname: row.nickname, recovery_code: code };
}

async function rename(env, body) {
  const me = await auth(env, body);
  const nickname = cleanNick(body.nickname);
  await env.DB.prepare("UPDATE players SET nickname = ? WHERE id = ?").bind(nickname, me.id).run();
  return { nickname };
}

async function runStart(env, body) {
  const me = await auth(env, body);
  const now = Date.now();
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM runs WHERE player_id = ? AND started_at > ?")
    .bind(me.id, now - 3_600_000).first();
  if ((recent?.n ?? 0) >= RUNS_PER_HOUR) throw new ApiError("too_many_runs", 429);
  const difficulty = cleanDiff(body.difficulty);
  const token = crypto.randomUUID();
  await env.DB.prepare("INSERT INTO runs (token, player_id, started_at, difficulty) VALUES (?, ?, ?, ?)")
    .bind(token, me.id, now, difficulty).run();
  return { run_token: token, server_time: now, difficulty };
}

async function runFinish(env, body) {
  const me = await auth(env, body);
  const now = Date.now();
  const run = await env.DB.prepare("SELECT token, player_id, started_at, difficulty, used FROM runs WHERE token = ?")
    .bind(String(body.run_token ?? "")).first();
  if (!run || run.player_id !== me.id) throw new ApiError("bad_token", 403);
  if (run.used) throw new ApiError("token_used", 409);
  // 先作废令牌（无论成绩是否通过校验，一个令牌只能提交一次）
  await env.DB.prepare("UPDATE runs SET used = 1 WHERE token = ?").bind(run.token).run();

  const timeMs = Math.round(Number(body.time_ms));
  const serverMs = now - run.started_at;
  const s = body.stats ?? {};
  if (!Number.isFinite(timeMs)) throw new ApiError("bad_time");
  if (timeMs < MIN_TIME_MS) throw new ApiError("too_fast");
  if (timeMs > serverMs + CLOCK_SLACK_MS) throw new ApiError("time_mismatch");
  if (serverMs > MAX_RUN_MS) throw new ApiError("run_expired");
  if (s.rescued !== true || Number(s.downs) < MIN_DOWNS[run.difficulty || "normal"] || Number(s.zombies) < 8) throw new ApiError("incomplete_run");

  const rating = ["S", "A", "B", "C"].includes(s.rating) ? s.rating : "C";
  // 难度以开局时绑定在令牌上的为准（提交时不能改）
  const diff = run.difficulty || "normal";
  await env.DB.prepare("INSERT INTO scores (player_id, time_ms, rating, difficulty, server_ms, created_at) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(me.id, timeMs, rating, diff, serverMs, now).run();
  const best = await env.DB.prepare("SELECT MIN(time_ms) AS t FROM scores WHERE player_id = ? AND difficulty = ?")
    .bind(me.id, diff).first();
  const rank = await env.DB.prepare(
    "SELECT COUNT(*) + 1 AS r FROM (SELECT player_id, MIN(time_ms) AS t FROM scores WHERE difficulty = ? GROUP BY player_id) WHERE t < ?"
  ).bind(diff, best.t).first();
  return { ok: true, time_ms: timeMs, best_ms: best.t, rank: rank.r, new_best: best.t === timeMs, difficulty: diff };
}

async function leaderboard(env, url) {
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get("limit") ?? 50)));
  const diff = cleanDiff(url.searchParams.get("difficulty") ?? "normal");
  const { results } = await env.DB.prepare(
    `SELECT p.nickname AS nickname, b.player_id AS player_id, b.t AS time_ms,
            (SELECT rating FROM scores s WHERE s.player_id = b.player_id AND s.difficulty = ? AND s.time_ms = b.t LIMIT 1) AS rating
     FROM (SELECT player_id, MIN(time_ms) AS t FROM scores WHERE difficulty = ? GROUP BY player_id) b
     JOIN players p ON p.id = b.player_id
     ORDER BY b.t ASC LIMIT ?`
  ).bind(diff, diff, limit).all();
  // 不公开完整玩家 ID：只返回前 8 位用于客户端高亮“我”
  return { difficulty: diff, entries: results.map((r, i) => ({ rank: i + 1, nickname: r.nickname, time_ms: r.time_ms, rating: r.rating, pid: r.player_id.slice(0, 8) })) };
}
