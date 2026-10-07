extends SceneTree
var checks := []
func check(condition: bool, description: String) -> void:
 checks.append({"name": description, "passed": condition})
 if condition: print("PASS ", description)
 else: push_error("FAIL " + description)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 await process_frame
 var sfx := root.get_node("Sfx")
 var players: Array = sfx.get("_players")
 check(players.size() == 28, "28 bounded SFX players retained")
 check(players.all(func(p): return p.playback_type == AudioServer.PLAYBACK_TYPE_STREAM), "All SFX players explicitly use Stream enum1")
 var music: AudioStreamPlayer = sfx.get("_music")
 check(music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Music player explicitly uses Stream enum1")
 check(ProjectSettings.get_setting("audio/general/default_playback_type.web") == 0, "Project Web default uses Stream enum0")
 var cache: Dictionary = sfx.get("_cache")
 check(cache.size() == 50, "All 50 baked WAV resources preloaded without first-use synthesis")
 check(cache.values().all(func(stream): return stream is AudioStreamWAV and stream.get_length() > 0), "All cached WAV resources are valid and non-empty")
 for name in ["music_menu", "music_combat", "music_wave"]:
  var stream: AudioStreamWAV = cache.get(name)
  check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end > stream.loop_begin, name + " loop boundaries valid")
 var effect_bus := AudioServer.get_bus_index("Music")
 check(AudioServer.get_bus_effect_count(effect_bus) == 1, "Music low-pass effect retained")
 sfx.muffle(true)
 check(AudioServer.is_bus_effect_enabled(effect_bus, 0), "Bullet-time low-pass enables")
 sfx.muffle(false)
 check(not AudioServer.is_bus_effect_enabled(effect_bus, 0), "Bullet-time low-pass resets")
 for bus in ["SFX", "Music"]:
  var index := AudioServer.get_bus_index(bus)
  sfx.set_volume(bus, 0.0)
  check(AudioServer.is_bus_mute(index), bus + " zero volume explicitly mutes")
  sfx.play("ui_click", -4.0, 1.0, 0.0)
  check(AudioServer.is_bus_mute(index), bus + " play never removes explicit mute")
  sfx.music("menu")
  check(AudioServer.is_bus_mute(index), bus + " music never removes explicit mute")
  sfx.set_volume(bus, 0.5)
  check(not AudioServer.is_bus_mute(index) and absf(AudioServer.get_bus_volume_db(index) - linear_to_db(0.5)) < 0.0001, bus + " nonzero slider maps unchanged to gain")
 sfx.set_volume("SFX", 0.85)
 sfx.set_volume("Music", 0.55)
 sfx.play("ui_click", -4.0, 1.0, 0.0)
 check(players.any(func(p): return p.playing and p.stream == cache["ui_click"] and is_equal_approx(p.volume_db,-4.0)), "UI click preserves original -4dB and requested stream")
 sfx.music("menu")
 check(music.playing and music.stream == cache["music_menu"] and is_equal_approx(music.volume_db,-6.0), "Menu music plays original stream at original -6dB")
 sfx.music("")
 check(not music.playing, "Stopping music works")
 var success := checks.all(func(item): return item.passed)
 var report_path := "user://native-audio-state-results.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report="):
   report_path = arg.substr(9)
 var file := FileAccess.open(report_path, FileAccess.WRITE)
 file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "game_version": ProjectSettings.get_setting("application/config/version"), "scope": "Headless actual Godot resource/player/bus state checks. Does not prove browser playback or audible output.", "checks": checks, "passed": success}, "  ") + "\n")
 file.close()
 print("AUDIO_STATE_TESTS ", checks.size(), " passed=", success)
 for player in players:
  player.stop()
 await create_timer(0.15).timeout
 sfx.queue_free()
 await create_timer(0.15).timeout
 quit(0 if success else 1)
