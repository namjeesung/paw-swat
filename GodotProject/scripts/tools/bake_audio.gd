extends SceneTree
## 离线烘焙音效：把 Sfx 里程序化合成的所有声音预先存成 WAV 放进 assets/sfx/。
## 游戏运行时直接加载，避免第一次播放某个声音时现场合成造成卡顿。
## 用法：godot --headless --path . -s res://scripts/tools/bake_audio.gd

const NAMES := [
	"shot", "shot_buff", "enemy_shot", "hit", "hit_player", "bonk", "cuff", "reload_start", "reload_done",
	"perfect", "jam", "empty", "roll", "dash", "breach", "slowmo", "alert", "telegraph", "ui_hover",
	"ui_click", "ui_deny", "type", "radio", "stamp", "paper", "chime", "bite", "swing", "heartbeat",
	"score", "dodge", "block", "wake", "victory", "fail", "shotgun", "laser", "rocket", "explosion",
	"groan", "splat", "pickup", "alarm", "clank", "transform", "powerup", "shout_fire",
	"music_wave", "music_menu", "music_combat",
]


func _initialize() -> void:
	seed(20261006)
	var synth: Node = load("res://scripts/autoload/sfx.gd").new()
	DirAccess.make_dir_recursive_absolute("res://assets/sfx")
	for n in NAMES:
		var data: PackedFloat32Array = synth._synth(n)
		var w: AudioStreamWAV = synth._to_wav(data, n.begins_with("music_"))
		var err := w.save_to_wav("res://assets/sfx/%s.wav" % n)
		print(n, " -> ", data.size(), " samples ", "ok" if err == OK else "ERR %d" % err)
	synth.free()
	quit()
