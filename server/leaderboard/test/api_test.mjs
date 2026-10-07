// 本地接口测试：node test/api_test.mjs [baseUrl]
const BASE = process.argv[2] ?? "http://127.0.0.1:8787";
const post = async (p, b) => { const r = await fetch(BASE + p, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(b) }); return [r.status, await r.json()]; };
const check = (name, cond, info) => { console.log((cond ? "PASS " : "FAIL ") + name, cond ? "" : JSON.stringify(info)); if (!cond) process.exitCode = 1; };
const stats = { rescued: true, downs: 25, zombies: 80, rating: "S" };

const [s1, me] = await post("/api/register", { nickname: "测试柴犬<script>" });
check("register", s1 === 200 && me.recovery_code.startsWith("PAW-") && me.nickname === "测试柴犬script", me);
const cred = { player_id: me.player_id, secret: me.recovery_code };

const [s2] = await post("/api/run/start", { player_id: me.player_id, secret: "PAW-WRONG" });
check("wrong secret rejected", s2 === 401);

const [, run1] = await post("/api/run/start", cred);
const [s3, r3] = await post("/api/run/finish", { ...cred, run_token: run1.run_token, time_ms: 30000, stats });
check("too fast rejected", s3 === 400 && r3.error === "too_fast", r3);
const [s4, r4] = await post("/api/run/finish", { ...cred, run_token: run1.run_token, time_ms: 90000, stats });
check("token reuse rejected", s4 === 409, r4);

const [, run2] = await post("/api/run/start", cred);
const [s5, r5] = await post("/api/run/finish", { ...cred, run_token: run2.run_token, time_ms: 95000, stats });
check("claimed time > server elapsed rejected", s5 === 400 && r5.error === "time_mismatch", r5);

const [, run3] = await post("/api/run/start", cred);
const [s6, r6] = await post("/api/run/finish", { ...cred, run_token: run3.run_token, time_ms: 80000, stats: { ...stats, rescued: false } });
check("incomplete run rejected", s6 === 400, r6);

const [s10, r10] = await post("/api/run/start", { ...cred, difficulty: "godmode" });
check("bad difficulty rejected", s10 === 400 && r10.error === "bad_difficulty", r10);
const [s11, r11] = await post("/api/run/start", { ...cred, difficulty: "insane" });
check("difficulty bound to run", s11 === 200 && r11.difficulty === "insane", r11);
const lbBad = await fetch(BASE + "/api/leaderboard?difficulty=xx");
check("leaderboard bad difficulty rejected", lbBad.status === 400);

const [s7, r7] = await post("/api/restore", { recovery_code: me.recovery_code.toLowerCase() });
check("restore by recovery code", s7 === 200 && r7.player_id === me.player_id, r7);
const [s8, r8] = await post("/api/rename", { ...cred, nickname: "新名字" });
check("rename", s8 === 200 && r8.nickname === "新名字", r8);

if (process.argv.includes("--wait")) {
  // 真实等待 76 秒后提交一个合法成绩（高级·鬼畜难度：只出现在鬼畜榜）
  const [, run4] = await post("/api/run/start", { ...cred, difficulty: "insane" });
  await new Promise((r) => setTimeout(r, 76_000));
  const [s9, r9] = await post("/api/run/finish", { ...cred, run_token: run4.run_token, time_ms: 75500, stats, difficulty: "easy" });
  check("valid run accepted", s9 === 200 && r9.ok && r9.rank === 1 && r9.difficulty === "insane", r9);
  const lb = await (await fetch(BASE + "/api/leaderboard?difficulty=insane")).json();
  check("insane board shows it", lb.entries[0]?.nickname === "新名字" && lb.entries[0]?.time_ms === 75500, lb);
  const lbE = await (await fetch(BASE + "/api/leaderboard?difficulty=easy")).json();
  check("easy board does not (difficulty can't be changed at submit)", !lbE.entries.some((e) => e.time_ms === 75500), lbE);
}
