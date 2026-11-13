extends Node
## 효과음과 배경음. game.gd 가 자식으로 붙여 쓴다.
## 소리 파일은 res://sound/ (기획 「gaejo_sounds」). 켜고 끈 상태는 user://settings.cfg 에 저장한다.

const DIR := "res://sound/"
const POOL := 10

## 부품 → 효과음. 없는 부품은 계열(fx_data.gd)로 고른다.
const PART_SOUND := {
	"pea": "fx_mech_shot", "shotgun": "fx_mech_shot", "copier": "fx_mech_shot", "sucker": "fx_mech_shot",
	"umbrella_gun": "fx_mech_shot", "decal": "fx_mech_shot",
	"hook": "fx_mech_hook", "claw": "fx_mech_hook", "stamp": "fx_mech_hook", "carousel": "fx_mech_hook", "trex_arm": "fx_mech_hook",
	"magnet": "fx_mech_magnet",
	"rocket": "fx_mech_rocket", "retro": "fx_mech_rocket", "clockwork": "fx_mech_rocket", "crab": "fx_mech_rocket",
	"brake": "fx_mech_brake", "chute": "fx_mech_brake", "reel": "fx_mech_brake",
	"trex_head": "fx_trex_bite", "trex_leg": "fx_trex_stomp", "mecha": "fx_trex_roar",
	"star_cloak": "fx_magic_circle", "moon_set": "fx_magic_circle", "mushroom": "fx_magic_circle", "moon_well": "fx_magic_circle",
	"night_charm": "fx_magic_shadow", "shadow_scale": "fx_magic_shadow",
	"hero_band": "fx_awaken_flame", "torn_cape": "fx_awaken_flame", "awaken_shoes": "fx_awaken_flame", "hero_set": "fx_awaken_flame",
}
const FAMILY_SOUND := {"mech": "fx_mech_spring", "trex": "fx_trex_bite", "magic": "fx_magic_cast",
	"awaken": "fx_awaken_flame", "system": "fx_system_mark"}

var enabled := true
var hush := false          # 따라잡기 중에는 소리를 내지 않는다
var music_on := true
var vol := {"sfx": 1.0, "music": 1.0, "ui": 1.0}   # 효과음 · 배경음악 · 화면 소리
var _streams := {}
var _pool: Array = []
var _next := 0
var _last := {}
var _music: AudioStreamPlayer
var _slide: AudioStreamPlayer
var _cfg_path := "user://settings.cfg"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_cfg_path) == OK:
		enabled = cfg.get_value("sound", "enabled", true)
		music_on = cfg.get_value("sound", "music", true)
		for k in vol:
			vol[k] = float(cfg.get_value("sound", "vol_" + k, 1.0))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -16.0 + linear_to_db(maxf(vol["music"], 0.001))
	add_child(_music)
	var bgm = _load("bgm_table_loop")
	if bgm is AudioStreamOggVorbis:
		bgm.loop = true
	_music.stream = bgm
	_slide = AudioStreamPlayer.new()
	var sl = _load("puck_slide_loop")
	if sl is AudioStreamWAV:
		sl.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sl.loop_end = sl.get_length() * sl.mix_rate
	_slide.stream = sl
	_slide.volume_db = -60.0
	add_child(_slide)


func _load(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := DIR + name + (".ogg" if name.begins_with("bgm") else ".wav")
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[name] = st
	return st


## 같은 소리는 0.05초 안에 다시 내지 않는다 (충돌이 몰릴 때).
func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if not enabled or hush or name == "":
		return
	var v: float = vol["ui"] if name.begins_with("ui_") else vol["sfx"]
	if v <= 0.01:
		return
	db += linear_to_db(v)
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < 50:
		return
	_last[name] = now
	var st := _load(name)
	if st == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func play_part(part: String, family: String) -> void:
	play(PART_SOUND.get(part, FAMILY_SOUND.get(family, "fx_mech_spring")), -2.0, randf_range(0.96, 1.04))


func start_music() -> void:
	if enabled and music_on and _music.stream != null and not _music.playing:
		_music.play()


## 움직이는 퍽이 있으면 미끄러지는 소리, 빠를수록 크게.
func slide(speed: float) -> void:
	if not enabled or _slide.stream == null:
		if _slide.playing:
			_slide.stop()
		return
	if speed < 20.0:
		if _slide.playing:
			_slide.volume_db = move_toward(_slide.volume_db, -60.0, 6.0)
			if _slide.volume_db <= -59.0:
				_slide.stop()
		return
	if not _slide.playing:
		_slide.volume_db = -40.0
		_slide.play()
	var k := clampf(speed / 1650.0, 0.0, 1.0)
	var target := lerpf(-30.0, -8.0, k) + linear_to_db(maxf(vol["sfx"], 0.001))
	_slide.volume_db = move_toward(_slide.volume_db, target, 3.0)
	_slide.pitch_scale = lerpf(0.85, 1.15, k)


func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		_music.stop()
		_slide.stop()
	else:
		start_music()
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_cfg_path)
	cfg.set_value("sound", "enabled", enabled)
	cfg.set_value("sound", "music", music_on)
	for k in vol:
		cfg.set_value("sound", "vol_" + k, vol[k])
	cfg.save(_cfg_path)


func set_volume(kind: String, v: float) -> void:
	vol[kind] = clampf(v, 0.0, 1.0)
	if kind == "music":
		_music.volume_db = -16.0 + linear_to_db(maxf(vol["music"], 0.001))
		if vol["music"] <= 0.01:
			_music.stop()
		else:
			start_music()
	_save()
