extends "res://scripts/autoload/online.gd"
## TEST DOUBLE ONLY. Test directory excluded by all release presets.
func toy_mode() -> bool:
	return true
func _toy_call(op: String, _payload: Dictionary = {}) -> Dictionary:
	await get_tree().process_frame
	match op:
		"profile": return {"nickname": "离线模拟账号", "avatar": ""}
		"board": return {"entries": [{"nickname": "离线模拟甲", "rank": 1, "time_ms": 76000, "me": false}, {"nickname": "离线模拟乙", "rank": 2, "time_ms": 81000, "me": true}], "cached": false}
		"submit": return {"error": "not_logged_in"}
	return {"error": "test_offline"}
