extends Node
## 排行榜：Toy 公共榜（网页版）/ 独立服务器（可选）/ 本机记录。
## 服务器地址读取 res://leaderboard.cfg（也可用命令行 -- --lb=网址 覆盖）。
## 同一浏览器 / 同一台手机自动保留身份；换设备用“恢复码”找回。

signal profile_changed

const PROFILE := "user://profile.cfg"
const MAX_LOCAL := 20

var server_url := ""
var player_id := ""
var secret := ""          # 恢复码（也是登录凭证）
var nickname := ""
var nick_confirmed := false
var local_runs: Array = []
var run_token := ""
var toy_profile: Dictionary = {}
var _toy_bridge: JavaScriptObject
var _run_sequence := 0
var _finished_sequence := -1
var _finish_busy := false
var _finish_result: Dictionary = {}
var _pending_toy: Dictionary = {}
const TOY_BOARDS := {"easy": 1, "normal": 2, "hard": 3, "insane": 4}



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cf := ConfigFile.new()
	if cf.load("res://leaderboard.cfg") == OK:
		server_url = String(cf.get_value("server", "url", "")).strip_edges().trim_suffix("/")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lb="):
			server_url = a.substr(5).strip_edges().trim_suffix("/")
	if OS.has_feature("web"):
		_toy_bridge = JavaScriptBridge.get_interface("pawToy")
	_load()
	if nickname == "":
		nickname = random_nick()


func online() -> bool:
	return toy_mode() or server_url != ""


func toy_mode() -> bool:
	# A configured independent server remains an explicit opt-in alternative.
	return OS.has_feature("web") and server_url == ""


func board_name() -> String:
	return "Toy 公共榜" if toy_mode() else ("独立服务器榜" if server_url != "" else "联网榜未启用")


func platform_name() -> String:
	return String(toy_profile.get("nickname", ""))


func _toy_call(op: String, payload: Dictionary = {}) -> Dictionary:
	if not toy_mode() or _toy_bridge == null:
		return {"error": "toy_unavailable"}
	if Game.autotest and not OS.get_cmdline_user_args().has("--lbtest"):
		return {"error": "test_offline"}
	var ticket := str(_toy_bridge.start(op, JSON.stringify(payload)))
	var begun := Time.get_ticks_msec()
	while Time.get_ticks_msec() - begun < 26000:
		var result := str(_toy_bridge.poll(ticket))
		if result != "":
			var parsed = JSON.parse_string(result)
			return parsed if parsed is Dictionary else {"error": "toy_bad_response"}
		await get_tree().process_frame
	return {"error": "toy_pending" if op == "submit" else "toy_timeout"}


func refresh_toy_profile(force := false) -> Dictionary:
	var response := await _toy_call("profile", {"force": force})
	if not response.has("error"):
		toy_profile = response
	else:
		toy_profile = {"error": response.error}
	profile_changed.emit()
	return response


func retry_toy_submission() -> Dictionary:
	if _pending_toy.is_empty():
		return {"error": "no_pending_score"}
	var pending_id := str(_pending_toy.get("run_id", ""))
	var response := await _toy_call("submit", _pending_toy)
	if response.get("ok", false) and str(_pending_toy.get("run_id", "")) == pending_id:
		_pending_toy = {}
	return response


func has_pending_toy() -> bool:
	return not _pending_toy.is_empty()



func registered() -> bool:
	return player_id != "" and secret != ""


func random_nick() -> String:
	var a := ["勇敢的", "迅捷的", "冷静的", "暴走的", "爱吃罐头的", "夜行的", "无敌的"]
	var b := ["柴犬", "黑猫", "金毛", "三花", "柯基", "布偶"]
	return "%s%s%d" % [a.pick_random(), b.pick_random(), randi_range(10, 99)]


static func fmt_time(ms: int) -> String:
	if ms <= 0:
		return "--:--.--"
	var s := ms / 1000.0
	return "%d:%05.2f" % [int(s / 60.0), fmod(s, 60.0)]


# ------------------------------------------------------------------ 存档

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PROFILE) != OK:
		return
	player_id = cf.get_value("profile", "player_id", "")
	secret = cf.get_value("profile", "secret", "")
	nickname = cf.get_value("profile", "nickname", "")
	nick_confirmed = cf.get_value("profile", "nick_confirmed", false)
	local_runs = cf.get_value("records", "runs", [])


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "player_id", player_id)
	cf.set_value("profile", "secret", secret)
	cf.set_value("profile", "nickname", nickname)
	cf.set_value("profile", "nick_confirmed", nick_confirmed)
	cf.set_value("records", "runs", local_runs)
	cf.save(PROFILE)
	profile_changed.emit()


## 本机记录（按难度分开；v0.4 的旧记录没有难度字段，算作中级）
func local_list(diff: String) -> Array:
	return local_runs.filter(func(r): return String(r.get("diff", "normal")) == diff)


func local_best(diff: String) -> int:
	var l := local_list(diff)
	return int(l[0].time_ms) if not l.is_empty() else 0


# ------------------------------------------------------------------ 网络

func _request(method: HTTPClient.Method, path: String, body := {}) -> Dictionary:
	if server_url == "":
		return {"error": "offline"}
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var data := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var err := http.request(server_url + path, ["Content-Type: application/json"], method, data)
	if err != OK:
		http.queue_free()
		return {"error": "network"}
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"error": "network"}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var out: Dictionary = parsed if parsed is Dictionary else {}
	if int(res[1]) >= 400 and not out.has("error"):
		out["error"] = "http_%d" % int(res[1])
	return out


func _cred() -> Dictionary:
	return {"player_id": player_id, "secret": secret}


## 确保有云端身份（第一次联网时自动用当前昵称注册游客账号）
func ensure_registered() -> bool:
	if registered():
		return true
	if not online():
		return false
	var r := await _request(HTTPClient.METHOD_POST, "/api/register", {"nickname": nickname})
	if r.has("error"):
		return false
	player_id = r.player_id
	secret = r.recovery_code
	nickname = r.nickname
	_save()
	return true


func set_nickname(n: String) -> String:
	n = n.strip_edges()
	if n == "":
		return "昵称不能为空"
	if n.length() > 12:
		n = n.substr(0, 12)
	nickname = n
	nick_confirmed = true
	if registered() and server_url != "":
		var r := await _request(HTTPClient.METHOD_POST, "/api/rename", _cred().merged({"nickname": n}))
		if r.has("error") and r.error != "offline":
			_save()
			return "昵称已保存在本机（云端同步失败：%s）" % r.error
	_save()
	return ""


## 用恢复码在新设备上找回身份
func restore(code: String) -> String:
	code = code.strip_edges().to_upper()
	if not online():
		return "云端排行榜未开启"
	var r := await _request(HTTPClient.METHOD_POST, "/api/restore", {"recovery_code": code})
	if r.has("error"):
		return "恢复码无效" if r.error == "bad_code" else "网络错误，请稍后再试"
	player_id = r.player_id
	secret = r.recovery_code
	nickname = r.nickname
	nick_confirmed = true
	_save()
	return ""


## 每局开始：向服务器领本局令牌（服务器记录开局时间，用于校验成绩）
func start_run() -> void:
	_run_sequence += 1
	_finish_result = {}
	_pending_toy = {}
	run_token = ""
	if toy_mode():
		return
	if not online() or Game.autotest and not OS.get_cmdline_user_args().has("--lbtest"):
		return
	if not await ensure_registered():
		return
	var r := await _request(HTTPClient.METHOD_POST, "/api/run/start", _cred().merged({"difficulty": Game.difficulty}))
	run_token = String(r.get("run_token", ""))


## 通关：记本机成绩，并提交到云端（如果开启）
func finish_run(time_ms: int, stats: Dictionary) -> Dictionary:
	# Re-entering a results screen must not save or submit the same run twice.
	while _finish_busy:
		await get_tree().process_frame
	if _finished_sequence == _run_sequence:
		return _finish_result
	_finish_busy = true
	var sequence := _run_sequence
	var diff := String(stats.get("difficulty", Game.difficulty))
	var prev_best := local_best(diff)
	local_runs.append({"time_ms": time_ms, "rating": stats.get("rating", "C"), "date": Time.get_date_string_from_system(), "nick": nickname, "diff": diff})
	local_runs.sort_custom(func(a, b): return int(a.time_ms) < int(b.time_ms))
	# 每个难度最多保留 MAX_LOCAL 条
	var kept: Array = []
	var per := {}
	for r in local_runs:
		var d := String(r.get("diff", "normal"))
		per[d] = int(per.get(d, 0)) + 1
		if per[d] <= MAX_LOCAL:
			kept.append(r)
	local_runs = kept
	_save()
	var local_rank := 0
	var mine := local_list(diff)
	for i in mine.size():
		if int(mine[i].time_ms) == time_ms:
			local_rank = i + 1
			break
	var out := {"local_rank": local_rank, "new_local_best": prev_best == 0 or time_ms < prev_best, "cloud": {}}
	if toy_mode():
		_pending_toy = {"run_id": str(sequence), "difficulty": diff, "time_ms": time_ms}
		out.cloud = await retry_toy_submission()
	elif run_token != "":
		out.cloud = await _request(HTTPClient.METHOD_POST, "/api/run/finish",
			_cred().merged({"run_token": run_token, "time_ms": time_ms, "stats": stats}))
		run_token = ""
	elif online():
		out.cloud = {"error": "no_token"}
	_finish_result = out
	_finished_sequence = sequence
	_finish_busy = false
	return out


func fetch_board(diff: String, limit := 50, force := false) -> Dictionary:
	if toy_mode():
		return await _toy_call("board", {"difficulty": diff, "limit": limit, "force": force})
	return await _request(HTTPClient.METHOD_GET, "/api/leaderboard?limit=%d&difficulty=%s" % [limit, diff])


static func error_text(code: String) -> String:
	match code:
		"toy_unavailable":
			return "请在 B站 Toy 页面打开；当前仅保留本机成绩"
		"not_logged_in":
			return "请先登录 B站，再手动重试提交"
		"307044", "toy_rate_limited":
			return "Toy 请求较多，请稍等再手动刷新或重试"
		"toy_pending":
			return "Toy 仍在处理提交；可稍后点击查询 / 重试，不会重复提交"
		"toy_timeout":
			return "Toy 连接超时，请稍后手动重试"
		"toy_cancelled":
			return "平台操作已取消，成绩仅保存在本机"
		"toy_network":
			return "Toy 连接失败，成绩已保存在本机；可手动重试"
		"toy_bad_response":
			return "Toy 返回格式异常，未显示为成功，请稍后重试"
		"toy_invalid_time":
			return "本局用时不在 Toy 榜范围内，仅保存在本机"
		"test_offline":
			return "测试模式：不连接公共排行榜"
		"offline":
			return "云端排行榜未开启（只记录本机成绩）"
		"network":
			return "网络连接失败，成绩已保存在本机"
		"too_fast", "time_mismatch":
			return "成绩未通过服务器校验"
		"no_token":
			return "开局时未连上服务器，本局只记录在本机"
		"token_used":
			return "本局成绩已提交过"
		"too_many_runs":
			return "提交太频繁，请稍后再试"
	return "云端提交失败（%s），成绩已保存在本机" % code
