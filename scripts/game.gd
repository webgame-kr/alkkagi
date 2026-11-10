extends Node2D
## 화면 연출과 입력. 판정은 match.gd, 물리는 world.gd, 부품은 parts.gd 가 맡는다.
## 디자인: 펠트 테이블 위에서 튕기는 가공 금속 퍽 (디자인 시안 「개조 알까기 디자인 시안」).

const Match = preload("res://scripts/sim/match.gd")
const World = preload("res://scripts/sim/world.gd")
const Parts = preload("res://scripts/sim/parts.gd")
const PartsData = preload("res://scripts/sim/parts_data.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const Art = preload("res://scripts/stone_art.gd")
const FxData = preload("res://scripts/fx_data.gd")
const SoundMgr = preload("res://scripts/sound.gd")
const NetMgr = preload("res://scripts/net.gd")

# 팔레트 (디자인 시안의 「테이블과 재질」)
const Themes = preload("res://scripts/themes.gd")
const Arena = preload("res://scripts/arena.gd")
const BRASS := Color("C9A15A")
const INK := Color("0E1013")
const SUB_FELT := Color("E6F2EC")       # 펠트 위 작은 글자
# 아래 색은 고른 맵 테마에서 온다 (_apply_map).
var th: Dictionary = Themes.get_theme("play")
var map_id := "auto"                    # 고른 맵 ("auto" = 공방 따라가기)
var theme_id := "play"                  # 실제로 그리는 테마
var ACCENT := Color("C9A15A")
var ACCENT_INK := Color("0E1013")
var BG_OUT := Color("121417")           # 판 밖
var PAGE_FELT := Color("23463E")        # 도감 화면 바탕
var WARN := Color("D9A441")             # 힘 게이지 채움
var TEXT := Color("F2F4F1")
var SUB := Color("A9B1BA")
var POWER := Color("E9BE62")            # 강조 글자
var PANEL_BG := Color(1, 1, 1, 0.04)
var PANEL_LINE := Color(1, 1, 1, 0.09)
var MUTED := Color("5C6370")
var HINT_GOLD := Color("E3C27E")
var LABEL := Color("C9CED6")
var FG := Color.WHITE                   # 패널 위 반투명 선·바탕의 기준색 (밝은 맵은 진한 색)
var SOLID := Color("0E1013")            # 떠 있는 창 바탕
var _theme_fade := 0.0
var _fade_rect: ColorRect

const MAX_PULL := 3.2        # 칸: 이만큼 당기면 최대 힘
const CANCEL_PULL := 0.65    # 칸: 이보다 짧게 당기면 취소 (점선 원)
const GRAB_R := 0.9          # 칸: 퍽 잡기 판정
const CELL := World.STONE_R * 2.0

var font: Font
var font_semi: Font
var font_bold: Font
var font_display: Font        # 제목·배너용 굵은 제목체 (Black Han Sans)
var m: Match
var settings := {"n": 4, "cpu": [false, true, true, true, true, true, true, true], "timed": false, "speed": 1,
	"friend": [false, false, false, false, false, false, false, false], "workshop": "junk", "mode": "survival"}
## 게임 속도: 퍽이 움직이는 빠르기(재생 배율), CPU가 뜸 들이는 시간, 차례 사이 쉬는 시간.
const SPEEDS := [
	{"name": "느리게", "play": 0.75, "think": 1.0, "aim_show": 1.1, "hold": 0.7},
	{"name": "보통", "play": 1.0, "think": 0.55, "aim_show": 0.75, "hold": 0.4},
	{"name": "빠르게", "play": 1.3, "think": 0.3, "aim_show": 0.45, "hold": 0.2},
]
var turn_hold := 0.0          # 샷이 끝난 뒤 다음 차례까지 잠깐 쉬기
var state := "setup"          # setup | play | result

# 화면 배치
var view_center := Vector2.ZERO
var view_scale := 1.0
var portrait := false
var hud := {}                 # 패널 사각형들

# 조준
var drag_stone := -1
var drag_screen := Vector2.ZERO
var hover_stone := -1
var aim_left := 0.0
var turn_key := ""
var cpu_aim := {}             # CPU가 쏘기 직전 잠깐 보여주는 조준

# 진행
var accum := 0.0
var bot = null
var bot_wait := 0.0
var bot_us := 0
var bot_started := 0
var draft_wait := 0.0
var fx: Array = []
var banner := ""
var banner_t := 0.0
var log_lines: Array = []
var time := 0.0

# 확장: 구름 출발, 충전, 유품, 만화 연출
var drag_cloud := false       # 구름 표식에서 당기는 중
var drag_hold := 0.0          # 누르고 있던 시간 (모으고 쏘는 손바닥 충전)
var relic_mode := false       # 유품 리본 부품을 달 퍽 고르는 중
var slowmo := 0.0             # 만화 연출: 잠깐 느리게
var slowmo_shot := -1

# 개조 선택
var drafting_pid := -1        # 이 기기에서 지금 카드를 고르는 자리
var picked_round := {}        # 자리 → 이번 바퀴에 이미 골랐는지 (온라인 동시 선택)
var pending_picks := {}       # 호스트: 먼저 고른 자리의 장착을 차례가 올 때까지 보관
var draft_part := ""
var draft_stone := -1

# UI
var ui: CanvasLayer
var theme_: Theme
var overlay: Control = null
var menu_btn: Button
var parts_btn: Button
var _panel_sb: StyleBoxFlat
var snd: Node
# 친구 초대 (온라인)
var net: Node
var online := ""              # "" | "host" | "guest"
var my_seats: Array = []      # 이 기기가 두는 자리
var friend_peer := {}         # 호스트: 자리 → 친구 peer id
var host_peer := ""           # 손님: 호스트 peer id
var guest_lobby := {}         # 손님: 호스트가 보낸 대기실 상태
var net_queue: Array = []     # 순서가 매겨진 행동 {seq, a}
var net_seq_out := 0          # 호스트: 지금까지 매긴 순번
var net_applied := 0          # 적용한 마지막 순번
var waiting_req := false      # 손님: 보낸 행동이 돌아오길 기다리는 중
var _net_status_seen := ""
var lobby_col2: Control = null  # 대기실 오른쪽 열
var lobby_preview: Control = null  # 오른쪽 열 맨 위: 이 자리에 판 미리보기를 그린다
var lobby_col: Control = null  # 대기실 왼쪽 열: 매 프레임 세로 위치를 맞춘다 (웹 첫 프레임은 화면 크기가 늦게 잡힌다)
var sound_btn: Button
var ff_btn: Button
var fast_forward := false     # CPU 차례 빠른 진행 (내 차례가 오면 자동으로 꺼진다)
var view_opts := {"shake": true, "hitstop": true, "reduce_motion": false}
var _cancel_state := false    # 조준이 취소 원 안에 있었는지 (소리용)
var _tick_mark := -1          # 마지막으로 째깍 소리를 낸 초


func _ready() -> void:
	font = load("res://fonts/IBMPlexSansKR-Regular.ttf")
	font_semi = load("res://fonts/IBMPlexSansKR-SemiBold.ttf")
	font_bold = load("res://fonts/IBMPlexSansKR-Bold.ttf")
	font_display = load("res://fonts/BlackHanSans-Regular.ttf")
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		map_id = cfg.get_value("view", "map", "auto")
		for k in ["shake", "hitstop", "reduce_motion"]:
			view_opts[k] = cfg.get_value("view", k, view_opts[k])
	if not Themes.THEMES.has(map_id) and map_id != "auto":
		map_id = "auto"
	if not cfg.has_section_key("view", "reduce_motion") and OS.has_feature("web"):
		var rm = JavaScriptBridge.eval("window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches", true)
		view_opts["reduce_motion"] = bool(rm) if rm != null else false
	_set_theme_colors()
	theme_ = _make_theme()
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.set_border_width_all(1)
	_panel_sb.set_corner_radius_all(12)
	_panel_sb.bg_color = PANEL_BG
	_panel_sb.border_color = PANEL_LINE
	snd = SoundMgr.new()
	add_child(snd)
	net = NetMgr.new()
	add_child(net)
	ui = CanvasLayer.new()
	add_child(ui)
	var top := CanvasLayer.new()
	top.layer = 5
	add_child(top)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0, 0, 0, 0)
	top.add_child(_fade_rect)
	menu_btn = _icon_button("menu", func(): _show_settings(false), "메뉴")
	menu_btn.theme = theme_
	menu_btn.add_theme_font_size_override("font_size", 14)
	menu_btn.visible = false
	ui.add_child(menu_btn)
	parts_btn = _icon_button("book", func(): _show_catalog(false), "부품 도감")
	parts_btn.theme = theme_
	parts_btn.add_theme_font_size_override("font_size", 14)
	parts_btn.visible = false
	ui.add_child(parts_btn)
	sound_btn = _icon_button("sound", func(): _toggle_sound(), "소리")
	sound_btn.theme = theme_
	sound_btn.add_theme_font_size_override("font_size", 14)
	sound_btn.custom_minimum_size = Vector2(0, 44)
	sound_btn.visible = false
	ui.add_child(sound_btn)
	ff_btn = _icon_button("ff", func():
		fast_forward = not fast_forward
		_style_icon_btn(ff_btn, fast_forward), "CPU 차례 빠르게")
	ff_btn.theme = theme_
	ff_btn.add_theme_font_size_override("font_size", 14)
	ff_btn.custom_minimum_size = Vector2(0, 44)
	ff_btn.visible = false
	ui.add_child(ff_btn)
	_update_sound_btn()
	get_viewport().size_changed.connect(_layout)
	arena_node = Node2D.new()
	arena_node.show_behind_parent = true
	arena_node.draw.connect(func():
		arena_node.draw_texture_rect(arena_vp.get_texture(), Rect2(-Vector2.ONE * 8.0, get_viewport_rect().size + Vector2.ONE * 16.0), false))
	add_child(arena_node)
	puck_vp = SubViewport.new()
	puck_vp.transparent_bg = true
	puck_vp.disable_3d = true
	puck_vp.size = Vector2i(PUCK_TILE * 8, PUCK_TILE)
	puck_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(puck_vp)
	puck_drawer = Node2D.new()
	puck_drawer.draw.connect(func():
		for i in 8:
			Art.draw_puck_top(puck_drawer, Vector2(PUCK_TILE * (i + 0.5), PUCK_TILE * 0.5), PUCK_U, Match.COLORS[i], i, 0.0, 1.0, 0.0, false))
	puck_vp.add_child(puck_drawer)
	arena_vp = SubViewport.new()
	arena_vp.transparent_bg = false
	arena_vp.disable_3d = true
	arena_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(arena_vp)
	arena_drawer = Node2D.new()
	arena_drawer.draw.connect(_draw_arena_cache)
	arena_vp.add_child(arena_drawer)
	_layout()
	_show_setup()
	_debug_args()
	var room: String = net.room_param() if net.available else ""
	if room != "":
		_join_room(room)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 17
	var normal := _sb(Color(FG, 0.06) if th["dark"] else PANEL_BG, Color(FG, 0.14), 8)
	var hover := _sb(Color(FG, 0.11), Color(FG, 0.24), 8)
	var pressed := _sb(Color(BRASS, 0.22), BRASS, 8)
	for cls in ["Button", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_color("font_hover_pressed_color", cls, TEXT)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", TEXT)
	return t


func _sb(bg: Color, border: Color, radius: int, margin := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin + 4
	sb.content_margin_right = margin + 4
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb


## 개발용: godot --path . -- --auto 4 [--draft] 로 바로 경기를 띄운다 (화면 점검·녹화용).
func _debug_args() -> void:
	var args := OS.get_cmdline_user_args()
	_perf_on = args.has("--perf")
	var wi := args.find("--ws")
	if wi >= 0 and args.size() > wi + 1:
		settings["workshop"] = args[wi + 1]
	var ni := args.find("--n")
	if ni >= 0 and args.size() > ni + 1:
		_set_count(int(args[ni + 1]))
	var mi := args.find("--map")
	if mi >= 0 and args.size() > mi + 1:
		_apply_map(args[mi + 1], false)
	var i := args.find("--auto")
	if i < 0:
		return
	settings["n"] = int(args[i + 1]) if args.size() > i + 1 else 4
	for k in 8:
		settings["cpu"][k] = k > 0 or args.has("--allcpu")
	_start_match()
	var si := args.find("--shots")
	if si >= 0:
		Engine.time_scale = 3.0
		_shot_dir = args[si + 1]
		var t := Timer.new()
		t.wait_time = 1.5
		t.autostart = true
		t.timeout.connect(func():
			_shot_n += 1
			get_viewport().get_texture().get_image().save_png("%s/s%03d.png" % [_shot_dir, _shot_n]))
		add_child(t)
	if args.has("--settings"):
		_show_settings(false)
	if args.has("--catalog"):
		_show_catalog(false)
	if m.phase == "place" and (args.has("--draft") or args.has("--skipplace")):
		for pid in m.n:
			m.place(pid, m.preset(pid, "tri"))
	if args.has("--draft"):
		var guard := 0
		while not m.is_draft_round(m.round_no) or m.phase != "draft":
			m.skip_turn()
			guard += 1
			if guard > 50:
				break
		# 사람(빨강)이 먼저 고르도록 순서를 맞춘다
		m.draft_queue.erase(0)
		m.draft_queue.push_front(0)
	for dbg in ["--pickside", "--pickhover"]:
		if args.has(dbg):
			var kind: String = dbg
			get_tree().create_timer(3.0).timeout.connect(func():
				var part := "magnet" if kind == "--pickside" else "shotgun"
				m.offers[0][0] = part
				_on_card_picked(0, part)
				var mine3: Array = m.world.alive_stones_of(0)
				if kind == "--pickside":
					_pick_stone_for_part(0, mine3[0].id)
				else:
					hover_stone = mine3[0].id)
	if args.has("--sets"):
		var all: Array = m.world.stones
		all[0].parts = {"weapon": "moon_staff", "aux": "star_cloak", "prop": "moon_boots"}
		all[1].parts = {"weapon": "hero_band", "aux": "torn_cape", "prop": "awaken_shoes"}
		all[2].parts = {"weapon": "rubber_fist", "aux": "at_field", "prop": "drift_tire"}
		all[3].parts = {"weapon": "ice_fan", "aux": "mushroom", "prop": "anchor"}
		all[4].parts = {"weapon": "charge_palm", "aux": "log_sub", "prop": "glass_wings"}
		all[5].parts = {"weapon": "echo_bell", "aux": "trap_card", "prop": "flash_step"}
		all[6].parts = {"weapon": "alchemy_glove", "aux": "stopwatch", "prop": "rebound_shoes"}
		all[7].parts = {"weapon": "night_charm", "aux": "wind_knot", "prop": "second_step"}
		m.world.events.append({"t": "manga", "part": "log_sub", "pos": all[4].pos, "owner": all[4].owner, "stone": all[4].id})
		_consume_events()
	if args.has("--moon"):
		var mine2: Array = m.world.alive_stones_of(0)
		mine2[0].parts = {"weapon": "moon_staff", "aux": "star_cloak", "prop": ""}
		if m.phase == "draft":
			m.offers[0] = m.roll_offer(0)
			turn_key = ""
	if args.has("--trex"):
		var mine: Array = m.world.alive_stones_of(0)
		mine[0].parts = {"weapon": "trex_head", "aux": "trex_arm", "prop": "trex_leg"}
		mine[1].parts = {"weapon": "trex_head", "aux": "", "prop": "clockwork"}
		if not args.has("--draft"):
			mine[1].pos += Vector2(160, 0)
		if m.phase == "draft":
			m.offers[0] = m.roll_offer(0)
			turn_key = ""


# ── 배치 ─────────────────────────────────────────────────
## 가로: 판을 가운데, 패널은 네 귀퉁이에 떠 있다 (디자인 「조준 화면」).
## 세로: 위에 차례 카드, 아래에 남은 퍽·부품 패널.

func _layout() -> void:
	# 세로 화면(휴대폰)에서는 기준 해상도를 줄여 글자와 버튼을 키운다.
	var win := get_window()
	var aspect := float(win.size.x) / maxf(1.0, float(win.size.y))
	# 휴대폰 세로 480 · 패드 세로 680 · 휴대폰 가로 1100×600 · 그 밖(패드 가로, PC) 1280×800
	var want := Vector2i(1280, 800)
	if aspect < 1.0 / 1.1:
		want = Vector2i(480, 480) if aspect < 0.62 else Vector2i(680, 680)
	elif aspect > 1.8:
		want = Vector2i(1100, 600)
	if win.content_scale_size != want:
		win.content_scale_size = want
		if overlay != null and state == "setup":
			_show_setup.call_deferred()
	_place()


## 판과 패널 위치. 화면 크기가 바뀐 직후엔 값이 늦게 반영될 수 있어 매 프레임 다시 계산한다.
func _place() -> void:
	var vs := get_viewport_rect().size
	portrait = vs.y > vs.x * 1.1
	var extent := CELL * 9.0
	if m != null:
		extent = m.world.size
	var rail := 1.07  # 레일까지 포함한 바깥 반지름 비율
	if portrait:
		var top := 168.0
		var bottom := vs.y - 206.0
		view_center = Vector2(vs.x * 0.5, (top + bottom) * 0.5)
		var r_px := minf((bottom - top) * 0.5, vs.x * 0.5 - 8.0)
		view_scale = r_px / (extent * rail)
		var half := (vs.x - 36.0) * 0.5
		hud = {"turn": Rect2(12, 12, vs.x - 24, 100),
			"order": Rect2(12, vs.y - 196, half, 184),
			"aimed": Rect2(24 + half, vs.y - 196, half, 184)}
		if menu_btn:
			parts_btn.position = Vector2(vs.x - 12 - 44 - 8 - parts_btn.size.x, 120)
			menu_btn.position = Vector2(vs.x - 12 - 44, 120)
	else:
		var side := 24.0 + 268.0 + 16.0
		var r_px := minf(vs.y * 0.5 - 20.0, vs.x * 0.5 - side)
		view_center = vs * 0.5
		view_scale = r_px / (extent * rail)
		hud = {"turn": Rect2(24, 24, 268, 124),
			"order": Rect2(24, 164, 268, 0),
			"power": Rect2(24, vs.y - 24 - 106, 268, 106),
			"aimed": Rect2(vs.x - 24 - 268, 92, 268, 0),
			"log": Rect2(vs.x - 24 - 268, 0, 268, 0)}
		if menu_btn:
			menu_btn.position = Vector2(vs.x - 24 - 44, 24)
			parts_btn.position = Vector2(vs.x - 24 - 44 - 8 - parts_btn.size.x, 24)
	if menu_btn:
		menu_btn.custom_minimum_size = Vector2(44, 44)
		parts_btn.custom_minimum_size = Vector2(44, 44)
		sound_btn.custom_minimum_size = Vector2(44, 44)
		ff_btn.custom_minimum_size = Vector2(44, 44)
		sound_btn.position = parts_btn.position - Vector2(sound_btn.size.x + 8, 0)
		if ff_btn:
			ff_btn.position = sound_btn.position - Vector2(ff_btn.size.x + 8, 0)
			ff_btn.visible = state == "play" and m != null and _has_cpu()


func w2s(p: Vector2) -> Vector2:
	return view_center + shake_off + p * view_scale


func s2w(p: Vector2) -> Vector2:
	return (p - view_center - shake_off) / view_scale


# ── 경기 시작 ────────────────────────────────────────────

func _start_match(seed_value := -1) -> void:
	if online == "host" and seed_value < 0:
		_host_start()
		return
	if seed_value < 0:
		seed_value = randi()
	if online == "":
		my_seats = []
		for i in settings["n"]:
			if not settings["cpu"][i]:
				my_seats.append(i)
	m = Match.new()
	var ws: String = settings.get("workshop", "junk")
	if ws == "random":
		ws = ["junk", "magic", "toon"][seed_value % 3]
	m.setup(settings["n"], settings["cpu"], seed_value, settings["timed"], {"workshop": ws, "mode": settings.get("mode", "survival"), "placement": true})
	state = "play"
	_refresh_theme()
	turn_hold = 0.0
	net_queue.clear()
	pending_picks.clear()
	picked_round.clear()
	drafting_pid = -1
	net_applied = 0
	net_seq_out = 0
	waiting_req = false
	fx.clear()
	ko_pills.clear()
	vis.clear()
	last_shot.clear()
	round_picks.clear()
	toast_picks.clear()
	confetti.clear()
	win_t = -1.0
	hitstop = 0.0
	shake = 0.0
	log_lines.clear()
	bot = null
	cpu_aim = {}
	drag_stone = -1
	draft_part = ""
	draft_stone = -1
	turn_key = ""
	accum = 0.0
	_logged_out = {}
	_clear_overlay()
	menu_btn.visible = true
	parts_btn.visible = true
	sound_btn.visible = true
	_layout()
	var sp: Dictionary = m.players[m.current_player()]
	_log("%d인전 시작, 선공은 %s" % [m.n, sp.name], sp.color)
	if online != "":
		var mine: Array = []
		for sid in my_seats:
			mine.append(m.players[sid].name)
		_log("온라인 대전 · 내 자리: %s" % ", ".join(mine), BRASS)
	snd.start_music()
	snd.play("round_start", -3.0)
	_show_workshop_intro()


var _perf_acc := 0.0
var _perf_n := 0
var _perf_draw := 0.0
var _perf_proc := 0.0
var _perf_on := false
var _perf_sec := {}


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	if _perf_on:
		_perf_proc += float(Time.get_ticks_usec() - _t0)
		_perf_acc += delta
		_perf_n += 1
		if _perf_acc >= 2.0:
			var secs := ""
			for k in _perf_sec:
				secs += " %s=%.2f" % [k, _perf_sec[k] / _perf_n / 1000.0]
			_perf_sec.clear()
			print("PERF %s fps=%.0f process=%.2fms draw=%.2fms%s state=%s" % [theme_id, _perf_n / _perf_acc, _perf_proc / _perf_n / 1000.0, _perf_draw / _perf_n / 1000.0, secs, state])
			_perf_acc = 0.0
			_perf_n = 0
			_perf_proc = 0.0
			_perf_draw = 0.0


func _process_inner(delta: float) -> void:
	time += delta
	_place()
	if online != "":
		_net_poll()
	if state == "setup" and is_instance_valid(lobby_col):
		# 화면 크기가 실제로 바뀌면 (휴대폰 회전, 웹 첫 프레임) 대기실을 다시 짠다
		if get_viewport_rect().size.distance_to(lobby_built_size) > 2.0 and overlay != null and not overlay.has_meta("settings"):
			if online == "guest":
				_show_guest_lobby()
			else:
				_show_setup()
		_place_lobby(get_viewport_rect().size)
	banner_t = maxf(0.0, banner_t - delta)
	_update_shutter(delta)
	if _theme_fade > 0.0:
		_theme_fade = maxf(0.0, _theme_fade - delta)
		_fade_rect.color.a = _theme_fade / 0.25
	for f in fx:
		f["t"] += delta
	fx = fx.filter(func(f): return f["t"] < f["life"])
	if state == "play" and m != null:
		_update_play(delta)
	_decay_motion(delta)
	_update_arena_cache()
	queue_redraw()


func _sp(k: String) -> float:
	var v: float = SPEEDS[settings.get("speed", 1)][k]
	if fast_forward:
		v = v * 3.0 if k == "play" else v * 0.2
	return v


func _update_play(delta: float) -> void:
	# 개조가 끝나면 「골랐어요」 안내를 바로 닫는다 (온라인 동시 선택)
	if overlay != null and m.phase != "draft" and overlay.has_meta("draft_wait"):
		_clear_overlay()
	if turn_hold > 0.0:
		turn_hold -= delta
		return
	_apply_queue()
	var key := "%s|%d|%d|%d" % [m.phase, m.round_no, m.turn_pos, m.draft_queue.size()]
	if key != turn_key:
		turn_key = key
		_on_phase_changed()
	match m.phase:
		"place":
			_update_place(delta)
		"moving":
			var spd := 1.0
			if slowmo > 0.0:
				slowmo -= delta
				spd = 0.3
			if hitstop > 0.0:
				hitstop -= delta
				spd = 0.0
			accum += minf(delta, 0.05) * spd * _sp("play")
			_motion_tick(delta)
			while accum >= World.DT and m.phase == "moving" and hitstop <= 0.0:
				accum -= World.DT
				m.world.step()
				_consume_events()
				if m.world.is_settled():
					_after_shot()
					break
			var fastest := 0.0
			for st in m.world.stones:
				if st.alive:
					fastest = maxf(fastest, st.vel.length())
			snd.slide(fastest)
		"draft":
			var pid := m.current_drafter()
			if m.players[pid].cpu and _drives_cpu():
				draft_wait -= delta
				if draft_wait <= 0.0:
					var rng := RandomNumberGenerator.new()
					rng.seed = randi()
					var c := Bot.choose_draft(m, pid, rng)
					_apply_equip(pid, c["part"], c["stone"], c["side"])
		"aim":
			var pid := m.current_player()
			if drag_stone >= 0:
				drag_hold += delta
			if m.players[pid].cpu:
				if _drives_cpu():
					_update_cpu(delta, pid)
			elif _is_mine(pid) and m.aim_limit > 0.0 and not waiting_req:
				aim_left -= delta
				var sec := int(ceil(aim_left))
				if sec <= 3 and sec >= 1 and sec != _tick_mark:
					_tick_mark = sec
					snd.play("timer_warning" if sec == 3 else "timer_tick", -2.0)
				if aim_left <= 0.0:
					drag_stone = -1
					_act({"k": "skip", "pid": pid})
		"over":
			if state == "play":
				if win_t < 0.0:
					win_t = time
					snd.slide(0.0)
					if not m.winners.is_empty():
						snd.play("victory")
						_spawn_confetti()
				elif time - win_t > (1.8 if not m.winners.is_empty() else 0.3):
					_show_result()


func _update_cpu(delta: float, pid: int) -> void:
	if not cpu_aim.is_empty():
		cpu_aim["t"] -= delta
		if cpu_aim["t"] <= 0.0:
			var c: Dictionary = cpu_aim
			cpu_aim = {}
			_act({"k": "shot", "pid": pid, "stone": c["stone"], "dir": [c["dir"].x, c["dir"].y], "power": c["power"], "charged": true})
		return
	if bot == null:
		bot_wait -= delta
		if bot_wait > 0.0:
			return
		for t in m.relic_targets(pid):
			_act({"k": "relic", "pid": pid, "stone": t.id})
			break
		bot = Bot.new()
		bot.begin(m, pid, randi())
		bot_started = Time.get_ticks_msec()
		return
	# 프레임당 약 6ms 만큼만 생각한다 (화면이 멈추지 않게).
	var t0 := Time.get_ticks_usec()
	var finished := false
	while not finished and Time.get_ticks_usec() - t0 < 3000:
		finished = bot.think_step(1)
	bot_us += Time.get_ticks_usec() - t0
	# 느린 기기(웹)에서도 CPU가 오래 멈춰 보이지 않게, 1초가 지나면 지금까지 본 최선으로 쏜다
	if not finished and Time.get_ticks_msec() - bot_started > 1000:
		bot.finish_now()
		finished = true
	if finished:
		var r: Dictionary = bot.result()
		bot_us = 0
		bot = null
		if r.is_empty():
			_act({"k": "skip", "pid": pid})
		else:
			cpu_aim = r.duplicate()
			cpu_aim["t"] = _sp("aim_show")


func _on_phase_changed() -> void:
	match m.phase:
		"place":
			_begin_placing()
		"aim":
			# 개조가 끝났으니 「골랐어요」 안내는 닫는다 (온라인 동시 선택)
			if overlay != null and overlay.has_meta("draft_wait"):
				_clear_overlay()
			if not round_picks.is_empty():
				toast_picks = round_picks.duplicate()
				toast_t = time
				round_picks.clear()
			aim_left = m.aim_limit
			bot = null
			bot_wait = _sp("think")
			var p: Dictionary = m.players[m.current_player()]
			if _is_mine(p.id):
				_banner("내 차례", p.color, "알을 당겨 조준하세요")
				if fast_forward:
					fast_forward = false
					_style_icon_btn(ff_btn, false)
			else:
				_banner("%s 차례" % p.name, p.color)
			relic_mode = false
			_tick_mark = -1
			snd.play("turn_start", -8.0)
			if _is_mine(p.id) and not m.relic_targets(p.id).is_empty():
				_show_relic_hint(p.id)
		"draft":
			var pid := m.current_drafter()
			draft_part = ""
			draft_stone = -1
			draft_wait = _sp("think") + 0.4
			if online == "":
				# 혼자 할 때도 동시에 고르는 것처럼: 사람이 먼저 고르고, CPU는 바로 이어서 고른다 (공개는 바퀴 끝에 함께)
				draft_wait = 0.08
				if m.draft_queue.size() == m.order.size():
					var people: Array = []
					var cpus: Array = []
					for q in m.draft_queue:
						(cpus if m.players[q].cpu else people).append(q)
					m.draft_queue = people + cpus
					pid = m.current_drafter()
			if m.draft_queue.size() == m.order.size():
				_banner("%d바퀴" % m.round_no, ACCENT, "부품을 하나 골라요")
				if m.round_no > 1:
					snd.play("round_start", -4.0)
			snd.play("part_offer", -4.0)
			if online != "":
				if online != "guest" and m.players[pid].cpu:
					draft_wait = 0.25
				_online_draft_ui()
			elif _is_mine(pid):
				drafting_pid = pid
				_show_draft_cards(pid)
			else:
				_clear_overlay()


func _after_shot() -> void:
	var shooter_owner: int = m.world.shot.owner if m.world.shot != null else -1
	var outs: Array = m.world.knockouts.duplicate()
	m.finish_shot()
	turn_hold = _sp("hold") + (0.4 if not outs.is_empty() else 0.0)
	_consume_events()
	if shooter_owner < 0:
		return
	for k in outs:
		var cz: Dictionary = k.get("cause", {})
		var victim: String = m.players[int(k["owner"])].name
		if cz.has("owner") and int(cz["owner"]) != int(k["owner"]):
			var att: Dictionary = m.players[int(cz["owner"])]
			var how := _part_word(str(cz["part"]))
			if cz.get("chain", false):
				how += " 연쇄"
			_log("%s %s %s 퍽을 떨어뜨렸어요" % [_j(att.name, "이", "가"), _j(how, "으로", "로"), victim], att.color)
		else:
			_log("%s 퍽이 떨어졌어요" % victim, m.players[int(k["owner"])].color)
	for pid in m.out_order:
		if not _logged_out.has(pid):
			_logged_out[pid] = true
			_log("%s 탈락했어요" % _j(m.players[pid].name, "이", "가"), m.players[pid].color)


var _logged_out := {}
var _shot_dir := ""
var _shot_n := 0


func _log(s: String, col := SUB) -> void:
	log_lines.append({"t": s, "c": col, "at": time})
	if log_lines.size() > 40:
		log_lines.pop_front()


## 받침에 따라 조사 고르기: _j("빨강", "이", "가") → "빨강이"
static func _j(word: String, with_final: String, without_final: String) -> String:
	if word.is_empty():
		return word
	var c := word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0:
		return word + with_final
	return word + without_final


var banner_sub := ""


func _banner(s: String, c := TEXT, sub := "") -> void:
	banner_sub = sub
	banner = s
	banner_t = 0.85 if not _reduced() else 0.6
	_banner_col = c


var _banner_col := TEXT


# ── 연출용 사건 ──────────────────────────────────────────

func _consume_events() -> void:
	for e in m.world.events:
		var owner_col: Color = m.players[e["owner"]].color if e.has("owner") and e["owner"] >= 0 and e["owner"] < m.players.size() else TEXT
		match e["t"]:
			"hit":
				_on_hit(e)
			"bullet_hit":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.3, "r": 16.0, "c": owner_col.lightened(0.4)})
			"launch":
				var ls = m.world.get_stone(m.world.shot.stone_id) if m.world.shot != null else null
				if ls != null:
					last_shot[ls.owner] = ls.id
					var vv: Dictionary = vis.get(ls.id, {})
					vv["pop_t"] = time
					vv["sq_dir"] = m.world.shot.dir
					vv["vf"] = m.world.shot.dir.angle()
					vis[ls.id] = vv
			"out":
				snd.play("puck_fall")
				var ks = m.world.get_stone(int(e.get("stone", -1)))
				if ks != null:
					var kv: Dictionary = vis.get(ks.id, {})
					fx.append({"k": "ko", "pos": e["pos"], "t": 0.0, "life": 0.55, "c": owner_col, "parts": ks.parts.duplicate(),
						"owner": int(e["owner"]), "facing": float(kv.get("vf", ks.facing)), "out": m.world.outward(e["pos"])})
				hud_pop[int(e["owner"])] = time
				fx.append({"k": "text", "pos": e["pos"], "t": 0.0, "life": 0.9, "text": "탈락!", "c": owner_col, "size": 30, "pop": true})
				var why := _cause_text(e.get("cause", {}), int(e["owner"]))
				var cc: Dictionary = e.get("cause", {})
				ko_pills.append({"t": time, "text": "%s 알 탈락 · %s" % [m.players[int(e["owner"])].name, why],
					"c": m.players[int(cc["owner"])].color if cc.has("owner") else SUB})
				if ko_pills.size() > 3:
					ko_pills.pop_front()
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.6, "r": 46.0, "c": owner_col})
			"part":
				var big: bool = e.get("big", false)
				var part_id: String = e.get("part", "")
				var fd: Array = FxData.FX.get(part_id, [])
				var fam: String = fd[0] if not fd.is_empty() else ("trex" if part_id == "mecha" else ("magic" if part_id == "moon_set" else ("awaken" if part_id == "hero_set" else "mech")))
				if not PartsData.is_anime(part_id):
					snd.play_part(part_id, fam)
				if not fd.is_empty() and not PartsData.is_anime(part_id):
					fx.append({"k": "fam", "fam": fam, "pos": e["pos"], "t": 0.0, "life": 0.2 if fam == "mech" else 0.6,
						"word": fd[1], "c": Color(fd[2])})
				elif fam != "mech":
					fx.append({"k": "fam", "fam": fam, "pos": e["pos"], "t": 0.0, "life": 0.8, "word": "", "c": Color("FF6B4A") if fam == "trex" else (Color("B7C8FF") if fam == "magic" else Color("FF8A4A"))})
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -30), "t": 0.0, "life": 1.6 if big else 1.1, "text": e.get("text", ""), "c": POWER if big else owner_col.lightened(0.35), "size": 28 if big else 16})
				if big:
					fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.7, "r": 70.0, "c": POWER})
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.4, "r": 30.0, "c": owner_col.lightened(0.3)})
				if e.has("from"):
					fx.append({"k": "line", "a": e["from"], "b": e["pos"], "t": 0.0, "life": 0.45, "c": owner_col.lightened(0.5)})
			"reflect":
				snd.play("rail_bump", -2.0)
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.5, "r": 36.0, "c": Color(0.75, 0.95, 1.0)})
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -28), "t": 0.0, "life": 1.0, "text": "반사!", "c": Color(0.75, 0.95, 1.0), "size": 20})
			"boom":
				snd.play("puck_hit_heavy", 2.0, 0.7)
				fx.append({"k": "boom", "pos": e["pos"], "t": 0.0, "life": 0.55, "r": e["radius"], "c": Color(1.0, 0.6, 0.15)})
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -30), "t": 0.0, "life": 1.0, "text": "쾅!", "c": Color(1.0, 0.75, 0.3), "size": 28})
			"device":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.4, "r": 22.0, "c": owner_col})
			"umbrella":
				fx.append({"k": "fan", "pos": e["pos"], "dir": e["dir"], "t": 0.0, "life": 0.5, "r": e["radius"], "c": Color("E1E6EB")})
			"manga":
				snd.play("fx_parody_stamp", -1.0)
				if m.world.shot_no != slowmo_shot and not _all_cpu():
					snd.play("fx_parody_slowmo", -3.0)
				var sid: int = e.get("stone", -1)
				var info: Dictionary = PartsData.get_part(e["part"])
				fx.append({"k": "manga", "stone": sid, "pos": e["pos"], "t": 0.0, "life": 0.7,
					"text": info.get("sfx", ""), "c": Color(info.get("sfx_color", "#F2A23A"))})
				if m.world.shot_no != slowmo_shot and not _all_cpu():
					slowmo_shot = m.world.shot_no
					slowmo = 0.15
			"mark":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.5, "r": 28.0, "c": Color("B7C8FF")})
			"cone":
				fx.append({"k": "fan", "pos": e["pos"], "dir": e["dir"], "t": 0.0, "life": 0.45, "r": e["radius"], "c": Color("FF8A4A")})
			"beam":
				snd.play("fx_magic_cast", -2.0, 1.3)
				fx.append({"k": "beam", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.5, "c": Color("7FD8FF")})
			"hexbreak":
				snd.play("rail_bump", -3.0, 1.3)
				fx.append({"k": "hex", "pos": e["pos"], "t": 0.0, "life": 0.5, "c": Color("F28A2E")})
			"magic_circle":
				snd.play("fx_magic_circle", -4.0)
				fx.append({"k": "circle", "pos": e["pos"], "t": 0.0, "life": 0.7, "c": Color("B7C8FF")})
			"thread", "line_fx":
				fx.append({"k": "line", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.6, "c": Color("E9DCC4") if e["t"] == "thread" else Color("9A86D8")})
			"splat":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.4, "r": 24.0, "c": Color("2A2F45")})
			"respawn":
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -30), "t": 0.0, "life": 1.2, "text": "복귀", "c": owner_col.lightened(0.3), "size": 18})
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.6, "r": 40.0, "c": owner_col})
			"ripple":
				for k in 3:
					fx.append({"k": "ring", "pos": e["pos"], "t": -0.08 * k, "life": 0.5, "r": e["radius"] * 0.8, "c": Color(BRASS, 0.9)})
	m.world.events.clear()


# ── 입력 ─────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if state != "play" or m == null:
		return
	if m.phase == "place":
		_place_input(event)
		return
	if event is InputEventMouseMotion:
		var wp := s2w(event.position)
		hover_stone = _stone_at(wp, -1)
		if drag_stone >= 0:
			drag_screen = event.position
			var cancel_now := _aim_of(drag_stone, drag_screen).is_empty()
			if cancel_now and not _cancel_state:
				snd.play("aim_cancel", -6.0)
			_cancel_state = cancel_now
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var wp2 := s2w(event.position)
	if event.pressed and not m.world.gimmicks.is_empty() and event.position.y < 70 and event.position.x > get_viewport_rect().size.x * 0.5 + 140:
		gimmick_tip = 0 if gimmick_tip < 0 else -1
		return
	if event.pressed:
		hover_stone = _stone_at(wp2, -1)
	if m.phase == "draft" and draft_part != "" and draft_stone < 0:
		if event.pressed:
			var pid := drafting_pid
			var sid := _stone_at(wp2, pid)
			if sid >= 0:
				_pick_stone_for_part(pid, sid)
		return
	if m.phase != "aim" or not _is_mine(m.current_player()) or turn_hold > 0.0 or waiting_req:
		return
	if relic_mode:
		if event.pressed:
			var rs := _stone_at(wp2, m.current_player())
			if rs >= 0:
				_equip_relic(rs)
		return
	if event.pressed:
		var sid2 := _stone_at(wp2, m.current_player())
		drag_cloud = false
		if sid2 < 0:
			sid2 = _cloud_at(wp2, m.current_player())
			drag_cloud = sid2 >= 0
		if sid2 >= 0:
			drag_stone = sid2
			drag_screen = event.position
			drag_hold = 0.0
			_cancel_state = true
			snd.play("flick_pull", -4.0)
	elif drag_stone >= 0:
		var aim := _aim_of(drag_stone, event.position)
		var sid3 := drag_stone
		drag_stone = -1
		if not aim.is_empty():
			_act({"k": "shot", "pid": m.current_player(), "stone": sid3, "dir": [aim["dir"].x, aim["dir"].y],
				"power": aim["power"], "charged": _charged(sid3), "from_cloud": drag_cloud})
		else:
			snd.play("aim_cancel", -4.0)
		drag_cloud = false


func _stone_at(wp: Vector2, owner: int) -> int:
	var best := -1
	var best_d := CELL * GRAB_R
	for s in m.world.stones:
		if not s.alive or (owner >= 0 and s.owner != owner):
			continue
		var d: float = s.pos.distance_to(wp)
		if d < best_d:
			best_d = d
			best = s.id
	return best


## 구름 우편함: 비어 있는 내 구름 표식을 누르면 그 알을 거기서 쏜다.
func _cloud_at(wp: Vector2, owner: int) -> int:
	for d in m.world.devices:
		if d.kind == "cloud" and d.owner == owner and d.pos.distance_to(wp) < World.STONE_R * 1.4:
			var st = m.world.get_stone(d.stone_id)
			if st != null and st.alive and _free_spot(d.pos, st.id):
				return st.id
	return -1


func _free_spot(p: Vector2, ignore_id: int) -> bool:
	for o in m.world.stones:
		if o.alive and o.id != ignore_id and o.pos.distance_to(p) < World.STONE_R * 2.0:
			return false
	return true


## 지금 조준 중인 알의 출발점 (구름에서 당기면 구름 자리).
func _origin_of(stone_id: int) -> Vector2:
	var s = m.world.get_stone(stone_id)
	if drag_cloud and drag_stone == stone_id:
		var c = m.world.cloud_of(stone_id)
		if c != null:
			return c.pos
	return s.pos


func _charged(stone_id: int) -> bool:
	var s = m.world.get_stone(stone_id)
	return s != null and s.parts["weapon"] == "charge_palm" and drag_hold >= PartsData.num("charge_palm", "charge")


func _all_cpu() -> bool:
	for p in m.players:
		if not p.cpu:
			return false
	return true


## 손 위치로 조준을 계산한다. 알 가까이 되돌아오면 취소(빈 사전).
func _aim_of(stone_id: int, screen_pos: Vector2) -> Dictionary:
	var sp := w2s(_origin_of(stone_id))
	var pull := sp - screen_pos
	var dist := pull.length()
	var cells := dist / (CELL * view_scale)
	if cells < CANCEL_PULL:
		return {}
	# 힘 비율 p: (당긴 거리 − 0.65) ÷ (3.2 − 0.65). 속도 곡선은 world.launch 가 맡는다.
	var t := clampf((cells - CANCEL_PULL) / (MAX_PULL - CANCEL_PULL), 0.0, 1.0)
	return {"dir": pull.normalized(), "power": t}


# ── 개조 선택 ────────────────────────────────────────────

func _on_card_picked(pid: int, part: String) -> void:
	draft_part = part
	draft_stone = -1
	var mine: Array = m.world.alive_stones_of(pid)
	if mine.size() == 1:
		_pick_stone_for_part(pid, mine[0].id)
	else:
		_show_stone_hint(pid)


func _pick_stone_for_part(pid: int, sid: int) -> void:
	if draft_part == "bookmark":
		draft_stone = sid
		_show_bookmark_choice(pid)
		return
	if PartsData.SIDE_PARTS.has(draft_part):
		draft_stone = sid
		_show_side_choice(pid)
	else:
		_apply_equip(pid, draft_part, sid, 1)


func _apply_equip(pid: int, part: String, sid: int, side: int, reserve := "") -> void:
	if online != "" and not m.players[pid].cpu:
		picked_round[pid] = m.round_no
		draft_part = ""
		draft_stone = -1
		drafting_pid = -1
		_clear_overlay()
	_act({"k": "equip", "pid": pid, "part": part, "stone": sid, "side": side, "reserve": reserve})
	if online != "" and not m.players[pid].cpu:
		_online_draft_ui()


## 온라인: 내 자리 중 아직 안 고른 자리의 카드를 바로 보여준다 (모두 동시에 고르고, 차례대로 공개).
func _online_draft_ui() -> void:
	if m == null or m.phase != "draft":
		return
	for p in m.draft_queue:
		if my_seats.has(p) and not m.players[p].cpu and picked_round.get(p, -1) != m.round_no:
			if drafting_pid != p or overlay == null:
				drafting_pid = p
				draft_part = ""
				draft_stone = -1
				_show_draft_cards(p)
			return
	drafting_pid = -1
	var waiting := false
	for p in my_seats:
		if picked_round.get(p, -1) == m.round_no:
			waiting = true
	if waiting and overlay == null:
		var v := _hint_panel(my_seats[0])
		overlay.set_meta("draft_wait", true)
		v.add_child(_label("골랐어요. 모두 고르면 차례대로 공개돼요.", 16, TEXT, 1))


func _do_equip(pid: int, part: String, sid: int, side: int, reserve := "") -> void:
	var s = m.world.get_stone(sid)
	var slot := PartsData.slot_of(part)
	var old: String = s.parts[slot]
	if m.equip(pid, part, sid, side, reserve):
		if part == "bookmark" and m.players[pid].reserved != "":
			_log("%s 다음 선택에 %s 예약했어요" % [_j(m.players[pid].name, "이", "가"), _j(PartsData.part_name(m.players[pid].reserved), "을", "를")], m.players[pid].color)
		var nm := PartsData.part_name(part)
		var txt := nm
		if PartsData.SIDE_PARTS.has(part):
			txt += "(왼쪽)" if side < 0 else "(오른쪽)"
		var pl: Dictionary = m.players[pid]
		round_picks.append({"pid": pid, "part": nm, "id": part, "round": m.round_no})
		var line := "%d바퀴 시작, %s %s 달았어요" % [m.round_no, _j(pl.name, "이", "가"), _j(nm, "을", "를")]
		if old != "":
			line += " (%s 교체)" % PartsData.part_name(old)
		_log(line, pl.color)
		var set_txt := PartsData.set_label(s.parts)
		if set_txt != "":
			_log(set_txt, BRASS)
		var done_set2 := PartsData.set_of(part)
		if done_set2 != "" and PartsData.set_complete(s.parts, done_set2):
			snd.play("set_complete")
			if done_set2 == "trex":
				snd.play("fx_trex_roar", -2.0)
		elif done_set2 != "" and PartsData.set_progress(s.parts, done_set2)["count"] >= 2:
			snd.play("set_progress", -3.0)
		else:
			get_tree().create_timer(0.0 if _reduced() else 0.285).timeout.connect(func(): snd.play("part_equip", -3.0))
		# 장착 모션: 부품이 슬롯 바깥에서 미끄러져 들어오고, 75% 지점에서 딸깍 + 불꽃 10개
		var vv: Dictionary = vis.get(sid, {})
		vv["equip_t"] = time
		vv["equip_part"] = part
		vis[sid] = vv
		var spos: Vector2 = s.pos
		get_tree().create_timer(0.0 if _reduced() else 0.285).timeout.connect(func():
			for i in 10:
				fx.append({"k": "spark", "pos": spos, "vel": Vector2.from_angle(TAU * i / 10.0 + randf() * 0.3) * randf_range(70.0, 130.0),
					"t": 0.0, "life": randf_range(0.25, 0.45), "c": th["spark"]}))
		fx.append({"k": "text", "pos": s.pos + Vector2(0, -34), "t": 0.0, "life": 1.3, "text": txt, "c": pl.color.lightened(0.35), "size": 20})
		var done_set := PartsData.set_of(part)
		if done_set != "" and PartsData.set_complete(s.parts, done_set):
			fx.append({"k": "text", "pos": s.pos + Vector2(0, -58), "t": 0.0, "life": 1.8, "text": PartsData.SETS[done_set]["name"] + "!", "c": POWER, "size": 24})
			fx.append({"k": "ring", "pos": s.pos, "t": 0.0, "life": 0.8, "r": 60.0, "c": POWER})
		fx.append({"k": "ring", "pos": s.pos, "t": 0.0, "life": 0.5, "r": 34.0, "c": pl.color})
	if online == "":
		draft_part = ""
		draft_stone = -1
		_clear_overlay()


# ── 그리기 ───────────────────────────────────────────────

func _draw() -> void:
	var _t0 := Time.get_ticks_usec()
	_draw_inner()
	_perf_draw += float(Time.get_ticks_usec() - _t0)


func _draw_inner() -> void:
	var vs := get_viewport_rect().size
	if m == null:
		# 배경은 arena_node 가 그려 둔다
		# 로비 왼쪽 열 바탕: 어떤 맵에서도 글자가 읽히게 HUD 패널 색을 깐다
		if state == "setup" and is_instance_valid(lobby_col):
			for lc in [lobby_col, lobby_col2]:
				if is_instance_valid(lc):
					var lr: Rect2 = lc.get_global_rect().grow(22)
					lr.size.y = minf(lr.size.y, vs.y - lr.position.y + 40.0)
					_round_rect(lr, PANEL_BG, 14, PANEL_LINE)
		if state == "setup" and not portrait:
			pass
		return
	_draw_board()
	_draw_gimmicks()
	_draw_devices()
	_draw_aim_under()
	var _ts := Time.get_ticks_usec()
	if m.phase == "place":
		_draw_placing()
	for s in m.world.stones:
		if s.alive and m.phase != "place":
			_draw_stone(s)
	_perf_sec["stones"] = _perf_sec.get("stones", 0.0) + float(Time.get_ticks_usec() - _ts)
	_ts = Time.get_ticks_usec()
	_draw_projs()
	_draw_fx()
	_draw_aim_over()
	_draw_draft_marks()
	_perf_sec["fx"] = _perf_sec.get("fx", 0.0) + float(Time.get_ticks_usec() - _ts)
	_ts = Time.get_ticks_usec()
	if banner_t > 0.0:
		_draw_banner(vs)
	_draw_hud(vs)
	_perf_sec["hud"] = _perf_sec.get("hud", 0.0) + float(Time.get_ticks_usec() - _ts)
	_draw_confetti()


## 설정·도감 화면 바탕: 펠트 위의 100px / 20px 격자.
func _draw_page_felt(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), PAGE_FELT)
	var x := 0.0
	while x < vs.x:
		draw_line(Vector2(x, 0), Vector2(x, vs.y), Color(1, 1, 1, 0.08 if int(round(x)) % 100 == 0 else 0.035), 1.0)
		x += 20.0
	var y := 0.0
	while y < vs.y:
		draw_line(Vector2(0, y), Vector2(vs.x, y), Color(1, 1, 1, 0.08 if int(round(y)) % 100 == 0 else 0.035), 1.0)
		y += 20.0


## 로비 오른쪽: 고른 인원의 판 크기와 시작 배치. 사람 자리는 밝은 테두리.
## 대기실 배치 미리보기: 자기 칸(lobby_preview)에 한 번만 그린다 (매 프레임 다시 그리지 않음).
func _draw_lobby_preview(ci: Control) -> void:
	var n: int = settings["n"]
	var pr := Rect2(Vector2.ZERO, ci.size)
	var half := minf(pr.size.x * 0.5 - 18.0, (pr.size.y - 150.0) * 0.5)
	var c := Vector2(pr.get_center().x, 12.0 + half + 8.0)
	var square := n == 2
	var units := 16.0 if square else (18.0 if n <= 4 else 24.0)
	var u := 2.0 * half / units
	var r := u * 0.5
	Arena.board(ci, c, half, u, square, th, time)
	var pucks: Array = []
	if square:
		for i in 2:
			var y := c.y + (1.0 if i == 0 else -1.0) * (half - 4.0 * u)
			for j in 4:
				pucks.append([i, Vector2(c.x + (j - 1.5) * 2.5 * u, y)])
	else:
		var R := half / u
		for i in n:
			var a := deg_to_rad(90.0 + 360.0 * i / n)
			var rad := Vector2(cos(a), sin(a))
			var tg := rad.orthogonal()
			pucks.append([i, c + rad * (R - 4.0) * u + tg * Match.SIDE_GAP * u])
			pucks.append([i, c + rad * (R - 4.0) * u - tg * Match.SIDE_GAP * u])
			pucks.append([i, c + rad * (R - 5.5) * u])
	for pk in pucks:
		var i: int = pk[0]
		if not settings["cpu"][i]:
			ci.draw_arc(pk[1], r + 4, 0, TAU, 24, th["outline"], 3.0, true)
			ci.draw_arc(pk[1], r + 5.5, 0, TAU, 24, BRASS, 2.0, true)
		Art.draw_puck_shadow(ci, pk[1], r)
		Art.draw_puck_top(ci, pk[1], r, Match.COLORS[i], i, -PI / 2)
	# 판 정보: 판 · 퍽 · 개조 · 조준
	var timed: bool = settings["timed"]
	var info := [["판", "정사각 16칸" if square else "지름 %d칸" % int(units)], ["퍽", "%d개씩" % (4 if square else 3)],
		["개조", "2바퀴부터"], ["조준", "8초 제한" if timed else "제한 없음"]]
	var x0 := 24.0
	var y0 := c.y + half + 52.0
	var cw := (pr.size.x - 48.0) / 4.0
	for k in 4:
		var x := x0 + k * cw
		ci.draw_string(font, Vector2(x, y0), info[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SUB)
		ci.draw_string(font_bold, Vector2(x, y0 + 26), _fit(info[k][1], font_bold, 17, cw - 8), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, TEXT)
	var note := "경기장 모습은 고른 공방을 따라가요. 다른 맵과 게임 속도, 조준 시간은 설정에서 바꿀 수 있어요."
	var ly := y0 + 62.0
	for ln in _wrap(note, font, 13, pr.size.x - 48.0):
		ci.draw_string(font, Vector2(x0, ly), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SUB)
		ly += 20.0


func _draw_board() -> void:
	var w := m.world
	if str(th.get("deco", "")) == "magic" and not _reduced():
		Arena.magic_live(self, view_center + shake_off, w.size * view_scale, CELL * view_scale, time)
	# 판 자체는 arena_node 가 그려 둔 것을 쓴다 (매 프레임 다시 그리지 않음)
	# 위험 구역 깜빡임: 퍽이 가장자리 띠에서 움직이면 그 방향 호
	for f in fx:
		if f["k"] == "danger":
			var u2: float = f["t"] / f["life"]
			var R2 := w.size * view_scale
			if w.shape == "circle":
				draw_arc(view_center + shake_off, R2 - 0.5 * CELL * view_scale, f["ang"] - 0.22, f["ang"] + 0.22, 12, Color(th["danger"], 0.55 * (1.0 - u2)), CELL * view_scale, true)
			else:
				var pp: Vector2 = w2s(f["pos"])
				draw_circle(pp, CELL * view_scale, Color(th["danger"], 0.35 * (1.0 - u2)))


func _draw_grid_circle(c: Vector2, R: float, g: float) -> void:
	var col := Color(1, 1, 1, 0.06)
	var d := g
	var off := 0.0
	while off < R:
		for sgn in ([1.0, -1.0] if off > 0.0 else [1.0]):
			var o: float = off * sgn
			var h := sqrt(maxf(0.0, R * R - o * o))
			draw_line(c + Vector2(o, -h), c + Vector2(o, h), col, 1.0)
			draw_line(c + Vector2(-h, o), c + Vector2(h, o), col, 1.0)
		off += d


func _dotted_circle(c: Vector2, r: float, col: Color) -> void:
	var n := int(TAU * r / 8.0)
	for i in n:
		draw_circle(c + Vector2.from_angle(TAU * i / n) * r, 1.0, col)


func _round_rect(r: Rect2, col: Color, radius: int, border := Color(0, 0, 0, 0)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	sb.draw(get_canvas_item(), r)


func _draw_stone(s) -> void:
	var col: Color = m.players[s.owner].color
	var facing: float = s.facing
	var at: Vector2 = s.pos
	if drag_stone == s.id:
		var aim := _aim_of(s.id, drag_screen)
		if not aim.is_empty():
			facing = aim["dir"].angle()
		at = _origin_of(s.id)
	elif not cpu_aim.is_empty() and cpu_aim["stone"] == s.id:
		facing = cpu_aim["dir"].angle()
	elif vis.has(s.id) and vis[s.id].has("vf"):
		facing = vis[s.id]["vf"]
	var p := w2s(at)
	var manga = null
	for f in fx:
		if f["k"] == "manga" and f["stone"] == s.id:
			manga = f
	if manga != null:
		_draw_manga_back(p, manga)
	if drag_cloud and drag_stone == s.id:
		draw_set_transform(w2s(s.pos), s.facing, Vector2.ONE * view_scale)
		Art.draw(self, s.parts, s.magnet_side, col, 0.3, s.owner)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	var u := World.STONE_R * view_scale
	# 지금 차례인 퍽: 숨 쉬는 주인 색 고리 (1.35u ± 0.12u, 초당 4라디안)
	if m.phase == "aim" and s.owner == m.current_player() and drag_stone < 0:
		var ph := sin(time * 4.0)
		var ra := 0.35 + 0.4 * (0.5 + 0.5 * ph)
		if _is_mine(s.owner):
			draw_arc(p, 1.18 * u, 0, TAU, 40, Color(BRASS, 0.95), maxf(2.0, 0.14 * u), true)
		draw_arc(p, (1.35 + 0.12 * ph) * u, 0, TAU, 48, Color(col, ra), maxf(2.0, 0.12 * u), true)
		if m.aim_limit > 0.0 and not m.players[s.owner].cpu:
			var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
			draw_arc(p, 1.62 * u, -PI / 2, -PI / 2 + TAU * frac, 40, Color(POWER, 0.85), 3.0, true)
	# 충전 (모으고 쏘는 손바닥)
	if drag_stone == s.id and s.parts["weapon"] == "charge_palm":
		var cf := clampf(drag_hold / PartsData.num("charge_palm", "charge"), 0.0, 1.0)
		draw_arc(p, (World.STONE_R + 10) * view_scale, -PI / 2, -PI / 2 + TAU * cf, 32, Color("7FD8FF") if cf < 1.0 else Color.WHITE, 3.0, true)
		if cf >= 1.0:
			draw_circle(p, (World.STONE_R + 14) * view_scale, Color("7FD8FF", 0.15 + 0.1 * sin(time * 12.0)))
	if manga != null:
		Art.mono = true
	_draw_puck_at(p, s.id, s.parts, s.magnet_side, col, s.owner, facing, 1.0)
	Art.mono = false
	# 상태 표시: 봉인, 저주, 표식, 시간 정지
	var badges: Array = []
	if s.status.has("sealed"):
		badges.append(["봉인", Color("9A86D8")])
	if s.status.has("cursed"):
		badges.append(["저주", Color("8A68D1")])
	if m.world.shot != null and m.world.shot.ex.get("marks", {}).has(s.id):
		draw_arc(p, (World.STONE_R + 4) * view_scale, 0, TAU, 24, Color("B7C8FF"), 2.0, true)
	if m.world.shot != null and m.world.shot.ex.get("frozen", {}).has(s.id):
		draw_arc(p, (World.STONE_R + 3) * view_scale, 0, TAU, 24, Color(1, 1, 1, 0.8), 3.0, true)
	for i in badges.size():
		_small_label(p + Vector2(0, -(World.STONE_R + 12) * view_scale - 14 * i), badges[i][0], badges[i][1])
	if manga != null:
		_draw_manga_front(p, manga)


## 계열별 발동 연출 (디자인 시안 「부품 발동 연출」).
## 기계: 황동 불꽃과 흰 섬광 (0.2초) · 티라노: 붉은 빛과 포효 파동 · 마법: 달빛 마법진과 별 조각
## 각성: 불꽃 기운 · 시스템: 표식 하나와 짧은 반짝임. 효과음 글자는 옆에 작게.
func _draw_family_fx(f: Dictionary, u: float) -> void:
	var p := w2s(f["pos"])
	var c: Color = f["c"]
	var k := view_scale
	var a := 1.0 - u
	match f["fam"]:
		"mech":
			var r := (10.0 + 10.0 * u) * k
			var star := PackedVector2Array()
			for i in 16:
				star.append(p + Vector2.from_angle(TAU * i / 16.0) * (r if i % 2 == 0 else r * 0.42))
			draw_colored_polygon(star, Color(c, 0.95 * a))
			draw_circle(p, r * 0.32, Color(1, 1, 1, a))
		"trex":
			draw_circle(p, (18.0 + 30.0 * u) * k, Color(c, 0.22 * a))
			for i in 2:
				var rr := (22.0 + 40.0 * u + i * 12.0) * k
				draw_arc(p, rr, 0, TAU, 32, Color(c, 0.8 * a), 2.5, true)
		"magic":
			var mr := 30.0 * k
			draw_circle(p, mr, Color(c, 0.08 * a))
			draw_arc(p, mr, 0, TAU, 40, Color(c, 0.85 * a), 1.6, true)
			_dashed_ring(p, mr * 0.88, Color(c, 0.8 * a))
			var st := PackedVector2Array()
			for i in 10:
				st.append(p + Vector2.from_angle(-PI / 2 + TAU * i / 10.0) * (mr * 0.72 if i % 2 == 0 else mr * 0.3))
			draw_colored_polygon(st, Color(c, 0.22 * a))
			for i in 5:
				var sp2 := p + Vector2.from_angle(TAU * i / 5.0 + u * 1.5) * mr * (1.0 + 0.5 * u)
				draw_circle(sp2, 2.0, Color(1, 1, 1, a))
		"awaken":
			for i in 10:
				var ang := TAU * i / 10.0 + time * 3.0
				var base := p + Vector2.from_angle(ang) * 22.0 * k
				var tip := p + Vector2.from_angle(ang) * (34.0 + 8.0 * sin(time * 20.0 + i)) * k
				draw_colored_polygon(PackedVector2Array([base + Vector2.from_angle(ang + 1.6) * 4 * k, tip, base - Vector2.from_angle(ang + 1.6) * 4 * k]), Color(c, 0.8 * a))
		"system":
			var d := 9.0 * k * (1.0 + 0.3 * u)
			var dia := PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)])
			draw_colored_polygon(dia, Color(c, 0.9 * a))
			for i in 4:
				var sp3 := p + Vector2.from_angle(TAU * i / 4.0 + PI / 4.0) * (14.0 + 10.0 * u) * k
				draw_line(sp3 - Vector2(3, 0), sp3 + Vector2(3, 0), Color(1, 1, 1, a), 1.5)
				draw_line(sp3 - Vector2(0, 3), sp3 + Vector2(0, 3), Color(1, 1, 1, a), 1.5)
	if f["word"] != "":
		var wp := p + Vector2(16, -10) * maxf(1.0, k)
		var alpha := 1.0 if f["fam"] != "mech" else clampf(1.6 - u, 0.0, 1.0)
		draw_string_outline(font_bold, wp, f["word"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(INK, alpha))
		draw_string(font_bold, wp, f["word"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(c, alpha))


## 만화 발동 연출: 뒤에서 충격 모양이 터지고 집중선이 퍼진다.
func _draw_manga_back(p: Vector2, f: Dictionary) -> void:
	var u: float = f["t"] / f["life"]
	var r := World.STONE_R * view_scale
	var a := 1.0 if u < 0.7 else (1.0 - u) / 0.3
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f["pos"].x * 13 + f["pos"].y * 7)
	for i in 28:
		var ang := TAU * i / 28.0 + rng.randf() * 0.1
		var r0 := r * (2.4 + rng.randf() * 0.6)
		var r1 := r * (4.2 + rng.randf() * 1.4)
		draw_line(p + Vector2.from_angle(ang) * r0, p + Vector2.from_angle(ang) * r1, Color(1, 1, 1, 0.55 * a), 0.8 + rng.randf() * 1.2, true)
	var star := PackedVector2Array()
	for i in 32:
		var ang2 := TAU * i / 32.0
		var rr := r * (2.2 if i % 2 == 0 else 1.75) * (0.85 + 0.15 * minf(1.0, u * 6.0))
		star.append(p + Vector2.from_angle(ang2) * rr)
	draw_colored_polygon(star, Color("F5F3EE", a))
	star.append(star[0])
	draw_polyline(star, Color(0.07, 0.07, 0.07, a), 2.0, true)


func _draw_manga_front(p: Vector2, f: Dictionary) -> void:
	var u: float = f["t"] / f["life"]
	var a := 1.0 if u < 0.7 else (1.0 - u) / 0.3
	if f["text"] == "":
		return
	var pos := p + Vector2(-World.STONE_R * 3.2 * view_scale, -World.STONE_R * 2.2 * view_scale)
	draw_set_transform(pos, deg_to_rad(-9.0), Vector2.ONE)
	draw_string_outline(font_bold, Vector2.ZERO, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color(0.07, 0.07, 0.07, a))
	draw_string(font_bold, Vector2.ZERO, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(f["c"], a))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_devices() -> void:
	for d in m.world.devices:
		var col: Color = m.players[d.owner].color
		var p := w2s(d.pos)
		var k := view_scale
		match d.kind:
			"mirror":
				var half := PartsData.num("umbrella", "half_len") * k
				var along: Vector2 = d.dir.orthogonal()
				var back: Vector2 = -d.dir
				var pts := PackedVector2Array()
				for i in 9:
					var t := -1.0 + i / 4.0
					pts.append(p + along * half * t + back * (1.0 - t * t) * 12.0 * k)
				draw_polyline(pts, INK, 5.0 * k, true)
				draw_polyline(pts, Color(col, 0.8), 2.5 * k, true)
				draw_line(p - along * half, p + along * half, INK, 6.0 * k, true)
				draw_line(p - along * half, p + along * half, Color("E1E6EB"), 3.5 * k, true)
				draw_line(p - along * half * 0.6, p + along * half * 0.2, Color(1, 1, 1, 0.6 + 0.3 * sin(time * 4)), 1.5, true)
				_small_label(p + back * 26 * k, _left_text(d), SUB_FELT)
			"mine":
				var blink := 0.5 + 0.5 * sin(time * (8.0 if d.armed else 2.0))
				if d.armed:
					_dotted_circle(p, (World.STONE_R + PartsData.num("mine", "radius")) * k, Color(Art.RED, 0.45))
				draw_circle(p + Vector2(0, 2), 11 * k, Color(0, 0, 0, 0.35))
				draw_circle(p, 11 * k, Art.STEEL_D)
				draw_arc(p, 11 * k, 0, TAU, 24, INK, 2.0, true)
				draw_arc(p, 7 * k, 0, TAU, 20, Color(col, 0.9), 2.0, true)
				draw_circle(p, 3.5 * k, Color(Art.RED, 0.6 + 0.4 * blink))
				_small_label(p + Vector2(0, 24 * k), _left_text(d), SUB_FELT)
			"bubble":
				var r := PartsData.num("bubble", "radius") * k
				draw_circle(p, r, Color(0.749, 0.890, 0.918, 0.55))
				draw_arc(p, r, 0, TAU, 28, INK, 2.0, true)
				draw_arc(p + Vector2(-r * 0.2, -r * 0.2), r * 0.55, PI * 1.05, PI * 1.45, 8, Color(1, 1, 1, 0.8), 2.0, true)
				draw_arc(p, r + 3, 0, TAU, 28, Color(col, 0.7), 1.5, true)
			"circle":
				var cr2 := (World.STONE_R + PartsData.num("star_cloak", "radius")) * k * 0.7
				draw_circle(p, cr2, Color("3B3F7A", 0.45))
				draw_arc(p, cr2, 0, TAU, 32, Color("B7C8FF", 0.9), 2.0, true)
				draw_arc(p, cr2 * 0.65, 0, TAU, 24, Color("B7C8FF", 0.5), 1.2, true)
				for i in 5:
					draw_circle(p + Vector2.from_angle(TAU * i / 5.0 + time * 0.6) * cr2 * 0.82, 2.0, Color.WHITE)
				_small_label(p + Vector2(0, cr2 + 14), _left_text(d), SUB_FELT)
			"net":
				var along: Vector2 = d.dir.orthogonal()
				var a0 := w2s(d.pos - along * d.length)
				var b0 := w2s(d.pos + along * d.length)
				draw_line(a0, b0, Color(BRASS, 0.9), 3.0, true)
				var steps2 := int(d.length * 2.0 / 12.0)
				for i in steps2:
					var c2 := a0.lerp(b0, (i + 0.5) / steps2)
					draw_line(c2 - d.dir * 5 * k, c2 + d.dir * 3 * k, Color("F2F4F1", 0.9), 1.5, true)
				_small_label(w2s(d.pos - d.dir * 18.0), "안전망", HINT_GOLD)
			"ice":
				var pts2 := PackedVector2Array([p])
				var half := deg_to_rad(PartsData.num("ice_fan", "spread_deg") * 0.5)
				for i in 13:
					pts2.append(p + Vector2.from_angle(d.dir.angle() - half + 2.0 * half * i / 12.0) * d.length * k)
				draw_colored_polygon(pts2, Color("BFE3EA", 0.22))
				pts2.append(p)
				draw_polyline(pts2, Color("BFE3EA", 0.6), 1.5, true)
			"card":
				draw_set_transform(p, 0.2, Vector2.ONE * k)
				draw_rect(Rect2(-11, -15, 22, 30), Color("5B2A6E"))
				draw_rect(Rect2(-11, -15, 22, 30), Color("E3C27E"), false, 2.0)
				draw_rect(Rect2(-6, -9, 12, 18), Color("C04A9A", 0.7), false, 1.5)
				draw_set_transform_matrix(Transform2D.IDENTITY)
				_small_label(p + Vector2(0, 26 * k), _left_text(d) if d.expires_round > 0 else "", SUB_FELT)
			"mushroom":
				draw_circle(p + Vector2(0, 3 * k), 9 * k, Color("EDE3CF"))
				draw_arc(p - Vector2(0, 2 * k), 12 * k, PI, TAU, 16, Color("C9452F"), 9.0 * k, true)
				draw_circle(p + Vector2(-5, -6) * k, 2.0 * k, Color.WHITE)
				draw_circle(p + Vector2(5, -7) * k, 1.6 * k, Color.WHITE)
			"wind":
				var wd: Vector2 = d.dir
				for i in 3:
					var o := wd.orthogonal() * (i - 1) * 9.0 * k
					draw_line(p + o - wd * 16 * k, p + o + wd * 12 * k, Color("DDE8F0", 0.7), 2.0, true)
				draw_colored_polygon(PackedVector2Array([p + wd * 20 * k, p + wd * 10 * k + wd.orthogonal() * 7 * k, p + wd * 10 * k - wd.orthogonal() * 7 * k]), Color("DDE8F0", 0.85))
				_small_label(p + Vector2(0, 26 * k), _left_text(d), SUB_FELT)
			"well":
				var wr := PartsData.num("moon_well", "radius") * k
				draw_circle(p, wr, Color("262A55", 0.55))
				draw_arc(p, wr, 0, TAU, 32, Color("B7C8FF", 0.7), 2.0, true)
				draw_arc(p + Vector2(4, -3) * k, wr * 0.35, PI * 0.6, PI * 1.6, 10, Color("F2F4F1", 0.85), 2.0, true)
				_small_label(p + Vector2(0, wr + 14), _left_text(d), SUB_FELT)
			"wall":
				var al: Vector2 = d.dir.orthogonal()
				var wa := w2s(d.pos - al * d.length)
				var wb := w2s(d.pos + al * d.length)
				draw_line(wa, wb, INK, 13.0 * k, true)
				draw_line(wa, wb, Color("8A8F96"), 10.0 * k, true)
				for i in 4:
					var c3 := wa.lerp(wb, (i + 0.5) / 4.0)
					draw_line(c3 - d.dir * 4 * k, c3 + d.dir * 4 * k, Color("5E636B"), 1.5, true)
			"log":
				var la: Vector2 = d.dir.orthogonal()
				draw_line(p - la * 18 * k, p + la * 18 * k, Color("6B4A2B"), 16.0 * k, true)
				draw_circle(p + la * 18 * k, 8 * k, Color("C9A26F"))
				draw_arc(p + la * 18 * k, 4 * k, 0, TAU, 12, Color("6B4A2B"), 1.5, true)
			"cloud":
				var cc: Color = Color(col, 0.9)
				for o in [Vector2(-8, 2), Vector2(0, -4), Vector2(8, 2), Vector2(0, 4)]:
					draw_circle(p + o * k, 9 * k, Color("F2F4F1", 0.75))
				draw_arc(p, 16 * k, 0, TAU, 24, cc, 1.5, true)
			"slick":
				var a2 := p
				var b2 := w2s(d.pos + d.dir * d.length)
				var hw := PartsData.num("roller", "width") * 0.5 * k
				# 펠트 안으로 잘라서 그린다 (레일 밖으로 나가지 않게)
				var cl := Arena.clip_segment(a2, b2, view_center + shake_off, m.world.size * view_scale - hw, m.world.shape != "circle")
				if cl.is_empty():
					continue
				a2 = cl[0]
				b2 = cl[1]
				var nn: Vector2 = d.dir.orthogonal() * hw
				draw_colored_polygon(PackedVector2Array([a2 + nn, b2 + nn, b2 - nn, a2 - nn]), Color("8FD0C8", 0.22))
				draw_line(a2 + nn, b2 + nn, Color("8FD0C8", 0.55), 1.5, true)
				draw_line(a2 - nn, b2 - nn, Color("8FD0C8", 0.55), 1.5, true)
				var steps := int(d.length / 24.0)
				for i in steps:
					var c0 := a2.lerp(b2, (i + 0.5) / steps)
					draw_line(c0 - nn * 0.6, c0 + nn * 0.6 + (b2 - a2).normalized() * 6, Color(1, 1, 1, 0.18), 2.0, true)
				_small_label(b2 + (b2 - a2).normalized() * 14, _left_text(d), SUB_FELT)
			"groove":
				var a3 := p
				var b3 := w2s(d.pos + d.dir * d.length)
				var n3: Vector2 = d.dir.orthogonal() * 5.0 * k
				var cl3 := Arena.clip_segment(a3, b3, view_center + shake_off, m.world.size * view_scale - 6.0 * k, m.world.shape != "circle")
				if cl3.is_empty():
					continue
				a3 = cl3[0]
				b3 = cl3[1]
				draw_line(a3 + n3, b3 + n3, Color(0, 0, 0, 0.45), 3.0, true)
				draw_line(a3 - n3, b3 - n3, Color(0, 0, 0, 0.45), 3.0, true)
				var dd: Vector2 = (b3 - a3).normalized()
				var cnt := int(a3.distance_to(b3) / 16.0)
				for i in cnt:
					var c1 := a3.lerp(b3, (i + 0.5) / maxf(1, cnt))
					draw_polyline(PackedVector2Array([c1 - dd * 3 + n3, c1 + dd * 3, c1 - dd * 3 - n3]), Color(Art.STEEL, 0.5), 1.5, true)
				_small_label(b3 + dd * 14, _left_text(d), SUB_FELT)
			"turret":
				var dir: Vector2 = d.dir
				draw_set_transform(p, dir.angle(), Vector2.ONE * k)
				draw_rect(Rect2(-11, -9, 20, 18), Art.STEEL)
				draw_rect(Rect2(-11, -9, 20, 18), INK, false, 2.0)
				draw_polyline(PackedVector2Array([Vector2(-7, -5), Vector2(-2, 0), Vector2(-6, 3), Vector2(-1, 7)]), INK, 1.5)
				draw_rect(Rect2(9, -3, 13, 6), Art.STEEL_D)
				draw_rect(Rect2(9, -3, 13, 6), INK, false, 1.5)
				draw_rect(Rect2(-14, -6, 3, 12), col)
				draw_set_transform_matrix(Transform2D.IDENTITY)
				draw_dashed_line(p + dir * 26 * k, p + dir * 80 * k, Color(col.lightened(0.25), 0.7), 2.0, 6.0)


func _left_text(d) -> String:
	if d.expires_round < 0:
		return ""
	var left: int = d.expires_round - m.round_no + 1
	return "%d바퀴" % left


func _draw_projs() -> void:
	for p in m.world.projs:
		var col: Color = m.players[p.owner].color.lightened(0.25)
		var sp := w2s(p.pos)
		if p.kind == "bullet":
			var tail: Vector2 = sp - p.vel.normalized() * 30.0 * view_scale
			draw_line(tail, sp, Color(col, 0.75), 4.0 * view_scale, true)
			draw_circle(sp, 5.0 * view_scale, INK)
			draw_circle(sp, 3.5 * view_scale, TEXT if p.source != "decal" else Color(col.lightened(0.5)))
			if p.source == "reflect":
				draw_arc(sp, 9 * view_scale, 0, TAU, 12, Color("E1E6EB"), 1.5)
		elif p.kind == "orb":
			draw_circle(sp, 10 * view_scale, Color("B7C8FF", 0.3))
			draw_circle(sp, 5 * view_scale, Color("E8EEFF"))
		elif p.kind == "fist":
			var owner_s = m.world.get_stone(p.ignore_id)
			if owner_s != null:
				var os := w2s(owner_s.pos)
				draw_line(os, sp, INK, 7.0 * view_scale, true)
				draw_line(os, sp, Color("D9A77E"), 4.0 * view_scale, true)
			draw_circle(sp, 9 * view_scale, Color("D9A77E"))
			draw_arc(sp, 9 * view_scale, 0, TAU, 16, INK, 2.0, true)
		elif p.kind == "ink" or p.kind == "ink2":
			draw_circle(sp, p.radius * view_scale, Color("1E2233"))
			draw_circle(sp - p.vel.normalized() * 6 * view_scale, p.radius * 0.6 * view_scale, Color("1E2233", 0.6))
		elif p.kind == "sucker":
			var dv: Vector2 = p.vel.normalized()
			draw_line(sp - dv * 18 * view_scale, sp, Color(col, 0.6), 2.0, true)
			draw_arc(sp, 7 * view_scale, dv.angle() - 1.3, dv.angle() + 1.3, 10, Art.RED, 4.0 * view_scale, true)
		elif p.kind == "umbrella":
			var du: Vector2 = p.vel.normalized()
			var tri := PackedVector2Array([sp + du * 12 * view_scale, sp - du * 10 * view_scale + du.orthogonal() * 5 * view_scale, sp - du * 10 * view_scale - du.orthogonal() * 5 * view_scale])
			draw_colored_polygon(tri, Color("E1E6EB"))
			tri.append(tri[0])
			draw_polyline(tri, INK, 1.5, true)
		else:
			var r := World.RUBBER_R * view_scale
			draw_circle(sp, r, BRASS)
			draw_arc(sp, r, 0, TAU, 16, INK, 2.0, true)


func _draw_fx() -> void:
	for f in fx:
		if f["t"] < 0.0:
			continue
		var u: float = f["t"] / f["life"]
		var c: Color = f["c"]
		match f["k"]:
			"spark":
				var sp0 := w2s(f["pos"] + f["vel"] * f["t"] * (1.0 - u * 0.5))
				var dv: Vector2 = f["vel"].normalized() * 5.0 * (1.0 - u) * view_scale
				draw_line(sp0 - dv, sp0 + dv, Color(c, 1.0 - u), 2.0 * (1.0 - u * 0.5), true)
			"ghost":
				draw_circle(w2s(f["pos"]), World.STONE_R * view_scale * 0.92, Color(c, 0.28 * (1.0 - u)))
			"ko":
				var kp: Vector2 = w2s(f["pos"])
				var e2 := u * u
				var od: Vector2 = f["out"]
				_draw_puck_at(kp, -1, f["parts"], 1, c, f["owner"], f["facing"], 1.0 - e2,
					{"scale": 1.0 - 0.6 * u, "sq": 0.35 * u, "sq_dir": od})
			"ring":
				draw_arc(w2s(f["pos"]), f["r"] * view_scale * (0.6 + u * 0.8), 0, TAU, 32, Color(c, 1.0 - u), 3.0, true)
			"boom":
				draw_circle(w2s(f["pos"]), f["r"] * view_scale * (0.3 + u * 0.7), Color(c, 0.3 * (1.0 - u)))
				draw_arc(w2s(f["pos"]), f["r"] * view_scale * (0.3 + u * 0.7), 0, TAU, 40, Color(c, 1.0 - u), 4.0, true)
			"line":
				draw_line(w2s(f["a"]), w2s(f["b"]), Color(c, 0.9 * (1.0 - u)), 3.0, true)
			"fam":
				_draw_family_fx(f, u)
			"manga":
				if f["stone"] < 0:
					var mp := w2s(f["pos"])
					_draw_manga_back(mp, f)
					_draw_manga_front(mp, f)
			"beam":
				draw_line(w2s(f["a"]), w2s(f["b"]), Color(c, 0.35 * (1.0 - u)), 18.0 * view_scale, true)
				draw_line(w2s(f["a"]), w2s(f["b"]), Color(1, 1, 1, 1.0 - u), 4.0 * view_scale, true)
			"hex":
				var hp := w2s(f["pos"])
				for i in 6:
					var ang := TAU * i / 6.0
					var c0 := hp + Vector2.from_angle(ang) * (14.0 + 30.0 * u) * view_scale
					draw_line(c0, c0 + Vector2.from_angle(ang + 2.0) * 10.0 * view_scale, Color(c, 1.0 - u), 2.5, true)
			"circle":
				var cp := w2s(f["pos"])
				var cr := 34.0 * view_scale * (0.6 + 0.6 * u)
				draw_arc(cp, cr, 0, TAU, 32, Color(c, 1.0 - u), 2.5, true)
				for i in 5:
					draw_circle(cp + Vector2.from_angle(TAU * i / 5.0 + u * 2.0) * cr, 2.5, Color(1, 1, 1, 1.0 - u))
			"fan":
				var base: float = f["dir"].angle()
				var rr: float = f["r"] * view_scale * (0.4 + 0.6 * u)
				draw_arc(w2s(f["pos"]), rr, base - 1.2, base + 1.2, 20, Color(c, 1.0 - u), 4.0, true)
			"text":
				var p := w2s(f["pos"]) + Vector2(0, -24.0 * u)
				var fsz: int = f["size"]
				if f.get("pop", false):
					# 튀어나왔다(0~0.2) 위로 사라짐
					var popk := clampf(f["t"] / 0.2, 0.0, 1.0)
					fsz = int(fsz * (0.6 + 0.4 * _ease_back(popk)))
					p = w2s(f["pos"]) + Vector2(0, -40.0 * maxf(0.0, u - 0.3))
				_text_outline(p, f["text"], fsz, Color(c, clampf(2.0 - 2.0 * u, 0.0, 1.0)), true)


## 바닥에 깔리는 조준 정보: 자석 작동 범위.
func _draw_aim_under() -> void:
	var info := _current_aim()
	if info.is_empty():
		return
	var col: Color = m.players[info["stone"].owner].color
	for item in info["preview"]:
		if item["k"] == "magnet":
			var c := w2s(item["a"])
			var r: float = item["r"] * view_scale
			var base: float = item["dir"].angle()
			var pts := PackedVector2Array([c])
			for i in 25:
				pts.append(c + Vector2.from_angle(base - PI / 2 + PI * i / 24.0) * r)
			draw_colored_polygon(pts, Color(col, 0.14))
			pts.append(c)
			for i in pts.size() - 1:
				if i % 2 == 0:
					draw_line(pts[i], pts[i + 1], col.lightened(0.25), 1.5, true)


## 조준선: 진행 방향(길이가 곧 힘), 총탄 사선, 반대편 보조 사선, 취소 원, 새총 줄.
func _draw_aim_over() -> void:
	var info := _current_aim()
	if info.is_empty():
		return
	var s = info["stone"]
	var col: Color = m.players[s.owner].color
	var line_col := col.lightened(0.25)
	var sp := w2s(info.get("origin", s.pos))
	for item in info["preview"]:
		match item["k"]:
			"bullet":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), line_col, 2.5, 9.0)
			"decal":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color(line_col, 0.5), 2.5, 9.0)
				_dashed_ring(w2s(item["a"]), 8.0, Color(line_col, 0.8))
			"hook":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color(Art.STEEL, 0.6), 2.0, 4.0)
			"target":
				_dashed_ring(w2s(item["a"]), (World.STONE_R + 6) * view_scale, line_col)
			"note":
				_text_outline(sp + Vector2(0, (World.STONE_R + 30) * view_scale + 12), item["text"], 15, TEXT, true)
			"sucker":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color(Art.RED, 0.8), 2.5, 6.0)
			"umbrella":
				var ua := w2s(item["a"])
				var ub := w2s(item["b"])
				draw_dashed_line(ua, ub, Color("E1E6EB", 0.8), 2.0, 7.0)
				var ud := (ub - ua).normalized()
				draw_arc(ub, item["r"] * view_scale, ud.angle() - 1.2, ud.angle() + 1.2, 20, Color("E1E6EB", 0.7), 2.0, true)
			"clock":
				var cp := w2s(item["a"])
				_dashed_ring(cp, World.STONE_R * view_scale, Color(BRASS, 0.95))
				_text_outline(cp + Vector2(0, -(World.STONE_R + 8) * view_scale), "딸깍", 13, BRASS, true)
			"mecha":
				_draw_mecha_aim(s, item)
			"land":
				var lp := w2s(item["a"])
				var lc: Color = Color("4A5BD8").lightened(0.3) if item["ok"] else Art.RED
				_dashed_ring(lp, World.STONE_R * view_scale, lc)
				draw_dashed_line(w2s(item["from"]), lp, Color(lc, 0.6), 1.5, 5.0)
				_text_outline(lp + Vector2(0, -(World.STONE_R + 8) * view_scale), "착지" if item["ok"] else "착지 막힘", 13, lc, true)
			"turn":
				var ta := w2s(item["a"])
				draw_dashed_line(sp, ta, Color(Art.STEEL, 0.6), 2.0, 6.0)
				draw_line(ta, w2s(item["b"]), Color(BRASS, 0.9), 2.5, true)
				_dashed_ring(ta, 6.0, BRASS)
				_text_outline(ta + Vector2(0, -12), "꺾임", 13, BRASS, true)
			"orb":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color("B7C8FF", 0.75), 2.0, 5.0)
			"fist":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color("D9A77E", 0.85), 3.0, 8.0)
				draw_circle(w2s(item["b"]), 6, Color("D9A77E", 0.85))
	if info.has("finger"):
		var f: Vector2 = info["finger"]
		_dashed_ring(sp, CELL * CANCEL_PULL * view_scale, Color(1, 1, 1, 0.3))
		var d: Vector2 = (sp - f).normalized()
		var side := d.orthogonal() * World.STONE_R * 0.95 * view_scale
		var bw := maxf(2.0, 0.14 * World.STONE_R * view_scale)
		draw_line(sp + side, f, Color(BRASS.darkened(0.35), 0.9), bw + 1.5, true)
		draw_line(sp - side, f, Color(BRASS.darkened(0.35), 0.9), bw + 1.5, true)
		draw_line(sp + side, f, BRASS, bw, true)
		draw_line(sp - side, f, BRASS, bw, true)
		draw_circle(f, 16, Color(1, 1, 1, 0.12))
		draw_arc(f, 16, 0, TAU, 24, Color(1, 1, 1, 0.7), 1.5, true)
	for item in info["preview"]:
		if item["k"] == "move":
			var a := w2s(item["a"])
			var b := w2s(item["b"])
			var pw: float = item.get("power", 0.0)
			var acol := Color.WHITE if pw < 0.6 else (Color("FFD27A") if pw < 0.85 else Color("FF7A5C"))
			if pw > 0.9 and not _reduced():
				b += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			var dd := (b - a).normalized()
			a += dd * (World.STONE_R + 4) * view_scale
			draw_line(a, b, INK, 7.0, true)
			draw_line(a, b, acol, 3.5, true)
			var head := PackedVector2Array([b + dd * 14, b + dd.orthogonal() * 8 - dd * 2, b - dd.orthogonal() * 8 - dd * 2])
			draw_colored_polygon(head, acol)
			head.append(head[0])
			draw_polyline(head, INK, 2.0, true)


## 메카 티라노 조준: 팔이 닿는 측면(주인 색 부채꼴)과 던질 방향(황동 점선).
## 끌어올 자리가 막힐 것 같으면 부채꼴을 회색 빗금으로.
func _draw_mecha_aim(s, item: Dictionary) -> void:
	var dir: Vector2 = item["dir"]
	var c := w2s(s.pos)
	var r := 96.0 * view_scale
	var base := dir.angle() + PI / 2.0
	var spread := deg_to_rad(35.0)
	var blocked := _mecha_blocked(s, dir)
	var col: Color = m.players[s.owner].color
	var pts := PackedVector2Array([c])
	for i in 13:
		pts.append(c + Vector2.from_angle(base - spread + 2.0 * spread * i / 12.0) * r)
	draw_colored_polygon(pts, Color(Art.NEUTRAL, 0.18) if blocked else Color(col, 0.16))
	pts.append(c)
	for i in pts.size() - 1:
		if i % 2 == 0:
			draw_line(pts[i], pts[i + 1], Color(Art.NEUTRAL, 0.8) if blocked else col.lightened(0.25), 1.5, true)
	if blocked:
		for i in 6:
			var t := (i + 1) / 7.0
			var q := c + Vector2.from_angle(base) * r * t
			var o := Vector2.from_angle(base + PI / 2.0) * r * 0.25 * t
			draw_line(q - o, q + o + Vector2.from_angle(base) * 8, Color(Art.NEUTRAL, 0.7), 1.2, true)
	var e := w2s(item["edge"])
	var start := c + dir * (World.STONE_R + 20) * view_scale
	draw_dashed_line(start, e, BRASS, 2.5, 9.0)
	draw_colored_polygon(PackedVector2Array([e + dir * 4, e - dir * 12 + dir.orthogonal() * 7, e - dir * 12 - dir.orthogonal() * 7]), BRASS)
	_text_outline(c + Vector2(0, (World.STONE_R + 34) * view_scale + 14), "자리가 막혀 일반 충돌" if blocked else "옆을 스치면 물고 던지기", 14, Color(Art.NEUTRAL) if blocked else POWER, true)


## 직선으로 갈 때 처음 옆면으로 닿을 상대 앞자리가 막혀 있는지 (대략).
func _mecha_blocked(s, dir: Vector2) -> bool:
	var R := World.STONE_R
	var best_along := INF
	var target = null
	for t in m.world.stones:
		if not t.alive or t.id == s.id or t.owner == s.owner:
			continue
		var off: Vector2 = t.pos - s.pos
		var along := off.dot(dir)
		var perp := absf(off.cross(dir))
		if along > 0.0 and perp < 2.0 * R and perp > 2.0 * R * 0.6 and along < best_along:
			best_along = along
			target = t
	if target == null:
		return false
	var off2: Vector2 = target.pos - s.pos
	var perp2 := absf(off2.cross(dir))
	var hit_at: Vector2 = s.pos + dir * (off2.dot(dir) - sqrt(maxf(0.0, 4.0 * R * R - perp2 * perp2)))
	var spot := hit_at + dir * (2.0 * R + 1.0)
	if not m.world.is_inside(spot):
		return true
	for o in m.world.stones:
		if o.alive and o.id != s.id and o.id != target.id and o.pos.distance_to(spot) < 2.0 * R:
			return true
	return false


func _dashed_ring(c: Vector2, r: float, col: Color) -> void:
	var segs := maxi(12, int(TAU * r / 9.0))
	for i in segs:
		if i % 2 == 0:
			draw_arc(c, r, TAU * i / segs, TAU * (i + 1) / segs, 3, col, 1.5, true)


func _current_aim() -> Dictionary:
	if m.phase != "aim":
		return {}
	if drag_stone >= 0:
		var s = m.world.get_stone(drag_stone)
		var aim := _aim_of(drag_stone, drag_screen)
		if aim.is_empty():
			return {"stone": s, "power": 0.0, "finger": drag_screen, "preview": [], "cancel": true}
		var saved: Vector2 = s.pos
		s.pos = _origin_of(drag_stone)
		var pv := Parts.aim_preview(m.world, s, aim["dir"], aim["power"])
		s.pos = saved
		return {"stone": s, "power": aim["power"], "finger": drag_screen, "preview": pv, "origin": _origin_of(drag_stone)}
	if not cpu_aim.is_empty():
		var s2 = m.world.get_stone(cpu_aim["stone"])
		return {"stone": s2, "power": cpu_aim["power"],
			"preview": Parts.aim_preview(m.world, s2, cpu_aim["dir"], cpu_aim["power"])}
	return {}


func _draw_draft_marks() -> void:
	if m.phase != "draft" or draft_part == "" or drafting_pid < 0:
		return
	var pid := drafting_pid
	var slot := PartsData.slot_of(draft_part)
	var col: Color = m.players[pid].color
	for s in m.world.alive_stones_of(pid):
		var p := w2s(s.pos)
		var facing: float = vis.get(s.id, {}).get("vf", s.facing)
		# 자석팔·딱지 방패 같은 옆 부품: 고른 알 양쪽에 반투명 미리보기 + 쏘는 방향
		if draft_stone >= 0:
			if s.id != draft_stone:
				continue
			draw_arc(p, (World.STONE_R + 10) * view_scale, 0, TAU, 40, Color(BRASS, 0.95), 3.0, true)
			for side in [-1, 1]:
				var only := {"weapon": "", "aux": "", "prop": ""}
				only[slot] = draft_part
				draw_set_transform(p, facing, Vector2.ONE * view_scale)
				Art.skip_body = true
				Art.draw(self, only, side, col, 0.4, pid)
				Art.skip_body = false
				draw_set_transform_matrix(Transform2D.IDENTITY)
			var fd := Vector2.from_angle(facing)
			var tip := p + fd * (World.STONE_R * 4.2) * view_scale
			draw_dashed_line(p + fd * (World.STONE_R + 12) * view_scale, tip, Color(1, 1, 1, 0.9), 2.5, 6.0)
			draw_colored_polygon(PackedVector2Array([tip + fd * 12, tip + fd.orthogonal() * 7, tip - fd.orthogonal() * 7]), Color(1, 1, 1, 0.95))
			_text_outline(tip + fd * 14 + Vector2(34, 6), "쏘는 방향", 14, Color.WHITE, true)
			_text_outline(p + Vector2(0, (World.STONE_R + 40) * view_scale + 14), "반투명한 쪽은 아직 안 고른 자리", 13, Color.WHITE, true)
			continue
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		draw_arc(p, (World.STONE_R + 8 + pulse * 3) * view_scale, 0, TAU, 40, Color(BRASS, 0.95), 3.0, true)
		if hover_stone != s.id:
			continue
		# 손을 올린 알: 부품을 미리 달아 보이고, 말풍선으로 무엇이 바뀌는지
		var demo := {"weapon": "", "aux": "", "prop": ""}
		demo[slot] = draft_part
		draw_set_transform(p, facing, Vector2.ONE * view_scale)
		Art.skip_body = true
		Art.draw(self, demo, s.magnet_side, col, 0.75, pid)
		Art.skip_body = false
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var cur: String = s.parts[slot]
		var line1 := "%s · %s → %s" % [PartsData.SLOT_LABEL[slot], "비어 있음" if cur == "" else PartsData.part_name(cur), PartsData.part_name(draft_part)]
		var line2 := "이 알에 달아요" if cur == "" else "지금 부품과 바꿔요"
		var sid_set := PartsData.set_of(draft_part)
		if sid_set != "":
			var tmp: Dictionary = s.parts.duplicate()
			tmp[slot] = draft_part
			line2 += " · " + PartsData.set_label(tmp, sid_set)
		var bw := maxf(font_bold.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 32.0
		var br := Rect2(p + Vector2(-bw * 0.5, -(World.STONE_R + 26) * view_scale - 62), Vector2(bw, 56))
		_round_rect(Rect2(br.position + Vector2(0, 3), br.size), Color(0, 0, 0, 0.18), 10)
		_round_rect(br, Color(SOLID, 0.98), 10, PANEL_LINE)
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - 8, br.end.y - 1), Vector2(p.x + 8, br.end.y - 1), Vector2(p.x, br.end.y + 9)]), Color(SOLID, 0.98))
		draw_string(font_bold, br.position + Vector2(16, 24), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)
		draw_string(font, br.position + Vector2(16, 44), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SUB)


# ── HUD: 떠 있는 패널 ────────────────────────────────────

func _panel(r: Rect2) -> void:
	match str(th.get("panel_style", "")):
		"manga":
			draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color("111111"))
			draw_rect(r, Color(th["panel"], 1.0))
			draw_rect(r, Color("111111"), false, 2.0)
		"junk":
			_panel_sb.draw(get_canvas_item(), r)
			var y0 := r.position.y + 2.0
			draw_line(Vector2(r.position.x + 6.0, y0), Vector2(r.end.x - 6.0, y0), Color("1A1A1A"), 4.0)
			draw_dashed_line(Vector2(r.position.x + 6.0, y0), Vector2(r.end.x - 6.0, y0), Color("FFC23D"), 4.0, 8.0, false)
		"magic":
			for k in 4:
				_round_rect(r.grow(2.0 + k * 4.0), Color(183 / 255.0, 200 / 255.0, 1.0, 0.045), 14 + k * 4)
			_panel_sb.draw(get_canvas_item(), r)
		_:
			_panel_sb.draw(get_canvas_item(), r)


func _txt(pos: Vector2, t: String, size: int, col: Color, f: Font = null, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var ff: Font = f if f != null else font
	if width > 0.0 and align == HORIZONTAL_ALIGNMENT_LEFT:
		t = _fit(t, ff, size, width)
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width > 0.0:
		pos.x -= width  # 오른쪽 정렬은 pos.x 를 오른쪽 끝으로 본다
	draw_string(ff, pos, t, align, width, size, col)


var _text_cache := {}


## 글자 맞춤·줄바꿈 결과는 같은 입력이면 같으니 기억해 둔다 (매 프레임 글자 폭을 재지 않게).
func _fit(t: String, f: Font, size: int, maxw: float) -> String:
	var key := "f|%s|%d|%d|%d" % [t, f.get_instance_id(), size, int(maxw)]
	if _text_cache.has(key):
		return _text_cache[key]
	var out := t
	if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw:
		var s := t
		while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw:
			s = s.substr(0, s.length() - 1)
		out = s + "…"
	if _text_cache.size() > 4000:
		_text_cache.clear()
	_text_cache[key] = out
	return out


## 패널에 보여줄 퍽: 조준 중 > 손을 올린 퍽 > CPU가 고른 퍽 > 지금 차례의 첫 퍽.
func _focus_stone():
	if drag_stone >= 0:
		return m.world.get_stone(drag_stone)
	if hover_stone >= 0:
		var h = m.world.get_stone(hover_stone)
		if h != null and h.alive:
			return h
	if not cpu_aim.is_empty():
		return m.world.get_stone(cpu_aim["stone"])
	# 움직이는 중이면 쏜 퍽, 아니면 그 사람이 마지막으로 쏜 퍽
	if m.phase == "moving" and m.world.shot != null:
		var sh = m.world.get_stone(m.world.shot.stone_id)
		if sh != null and sh.alive:
			return sh
	var pid := m.current_player() if m.phase != "draft" else m.current_drafter()
	if pid >= 0 and last_shot.has(pid):
		var ls = m.world.get_stone(last_shot[pid])
		if ls != null and ls.alive:
			return ls
	if pid >= 0:
		var mine: Array = m.world.alive_stones_of(pid)
		if not mine.is_empty():
			return mine[0]
	return null


func _draw_hud(vs: Vector2) -> void:
	if not portrait:
		_draw_timeline(vs)
	_draw_ko_pills(vs)
	_draw_gimmick_chips(vs)
	_draw_toast(vs)
	_draw_turn_card(hud["turn"])
	_draw_order(hud["order"])
	_draw_aimed(hud["aimed"])
	if not portrait:
		_draw_power(hud["power"])
		_draw_log()


func _draw_turn_card(r: Rect2) -> void:
	var pid := -1
	var title := ""
	var sub := ""
	match m.phase:
		"aim", "moving":
			pid = m.current_player()
			title = "%s 차례" % m.players[pid].name
			if m.players[pid].cpu:
				sub = "CPU가 생각 중이에요" if m.phase == "aim" else "CPU가 쐈어요"
			elif not _is_mine(pid):
				sub = "친구가 조준하고 있어요" if m.phase == "aim" else "퍽이 멈추길 기다려요"
			else:
				title = "내 차례"
				sub = "알을 당겨 조준하세요" if m.phase == "aim" else "움직이는 중"
		"place":
			pid = placing_pid
			title = "자리 잡기"
			sub = "알을 끌어 내 구역에 놓으세요" if placing_pid >= 0 else "모두 놓을 때까지 기다려요"
		"draft":
			pid = m.current_drafter()
			if drafting_pid >= 0:
				pid = drafting_pid
			title = "%s 개조" % m.players[pid].name
			sub = "후보 세 개 중 하나를 골라요"
			if pid == drafting_pid and draft_part != "":
				var pn := PartsData.part_name(draft_part)
				sub = ("%s 달 쪽을 고르세요" if draft_stone >= 0 else "%s 달 알을 고르세요") % _j(pn, "을", "를")
		_:
			title = "경기 끝"
	if pid >= 0 and _is_mine(pid) and (m.phase == "aim" or m.phase == "draft") and not _reduced():
		# 내 차례: 주인 색 테두리가 맥박처럼 퍼진다 (1.2초)
		var ph := 0.5 - 0.5 * cos(TAU * fmod(time, 1.2) / 1.2)
		_round_rect(r.grow(6.0 * ph), Color(m.players[pid].color, 0.25 * ph), 14)
	_panel(r)
	if pid >= 0 and _is_mine(pid) and (m.phase == "aim" or m.phase == "draft"):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = m.players[pid].color
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.draw(get_canvas_item(), r)
	var x := r.position.x + 18
	if pid >= 0:
		_hud_icon(r.position + Vector2(18 + 24, 18 + 24), 48, m.players[pid].color, pid)
		x += 62
	if title != _turn_title_seen:
		_turn_title_seen = title
		_turn_title_t = time
	var tk := clampf((time - _turn_title_t) / 0.25, 0.0, 1.0)
	var tx := (1.0 - (1.0 - pow(1.0 - tk, 3.0))) * 14.0 if not _reduced() else 0.0
	_txt(Vector2(x + tx, r.position.y + 42), title, 24, Color(TEXT, tk), font_display, r.end.x - x - 12)
	_txt(Vector2(x + tx, r.position.y + 64), sub, 14, Color(SUB, tk), font, r.end.x - x - 12)
	# 바퀴 진행
	var y := r.position.y + 96
	_txt(Vector2(r.position.x + 18, y), "%d바퀴째" % m.round_no, 13, LABEL, font_semi)
	if m.max_rounds > 0:
		_txt(Vector2(r.end.x - 18, y), "%d바퀴까지" % m.max_rounds, 13, SUB, font, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_txt(Vector2(r.end.x - 18, y), "한 명 남을 때까지", 13, SUB, font, 150, HORIZONTAL_ALIGNMENT_RIGHT)
	# 바퀴 진행: 제한이 없으면 남은 사람 수로 보여준다
	var seg_r := Rect2(r.position.x + 18, y + 8, r.size.x - 36, 5)
	var n := m.max_rounds if m.max_rounds > 0 else m.n
	var lit := m.round_no if m.max_rounds > 0 else m.alive_players().size()
	var gap := 3.0
	var w := (seg_r.size.x - gap * (n - 1)) / n
	for i2 in n:
		draw_rect(Rect2(seg_r.position.x + i2 * (w + gap), seg_r.position.y, w, 5), BRASS if i2 < lit else Color(FG, 0.14))
	# 세로 화면: 힘을 카드 오른쪽 위에
	if portrait and m.phase == "aim":
		var info := _current_aim()
		if not info.is_empty() and not info.has("cancel"):
			_txt(Vector2(r.end.x - 16, r.position.y + 42), "%d%%" % int(round(info["power"] * 100)), 22, POWER, font_bold, 80, HORIZONTAL_ALIGNMENT_RIGHT)
	if m.phase == "aim" and m.aim_limit > 0.0 and not m.players[m.current_player()].cpu:
		var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
		draw_rect(Rect2(r.position.x + 12, r.end.y - 5, (r.size.x - 24) * frac, 3), POWER if frac > 0.3 else Art.RED)


## 차례 순서: 이번 바퀴 순서대로, 지금 차례가 맨 위. 탈락한 사람은 아래에 흐리게.
func _draw_order(r: Rect2) -> void:
	var rows: Array = []
	var cur := m.current_player() if m.phase != "draft" else m.current_drafter()
	var seq: Array = m.order.duplicate()
	if m.phase == "draft":
		seq = m.draft_queue.duplicate()
		for pid in m.order:
			if not seq.has(pid):
				seq.append(pid)
	var start := seq.find(cur)
	if start < 0:
		start = 0
	for k in seq.size():
		var pid: int = seq[(start + k) % seq.size()]
		if not rows.has(pid) and not m.players[pid].out:
			rows.append(pid)
	for p in m.players:
		if not rows.has(p.id):
			rows.append(p.id)
	var row_h := 40.0
	var fs := 15
	if not portrait and hud.has("power"):
		row_h = clampf((hud["power"].position.y - 12.0 - r.position.y - 48.0) / maxf(1.0, rows.size()), 22.0, 40.0)
		fs = 15 if row_h >= 32.0 else 13
	if portrait:
		row_h = clampf((r.size.y - 36.0) / rows.size(), 17.0, 30.0)
		fs = 13 if row_h < 24.0 else 14
	if not portrait:
		r.size.y = 14 + 24 + rows.size() * row_h + 10
		hud["order_end"] = r.end.y
	_panel(r)
	_txt(r.position + Vector2(18, 27), "차례 순서", 13, SUB, font_semi)
	var y := r.position.y + 36
	var i := 0
	for pid in rows:
		var p: Dictionary = m.players[pid]
		var a := 0.4 if p.out else 1.0
		var row := Rect2(r.position.x + 10, y, r.size.x - 20, row_h - 2)
		if pid == cur and not p.out:
			_round_rect(row, Color(FG, 0.07), 8)
		var cy := y + row_h * 0.5 - 1
		_hud_icon(Vector2(row.position.x + 8 + 12, cy), minf(24.0, row_h - 6), p.color, pid, a)
		var nx := row.position.x + 44
		_txt(Vector2(nx, cy + fs * 0.36), p.name, fs, Color(TEXT, a), font_bold if pid == cur else font, 70)
		var name_w := (font_bold if pid == cur else font).get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_txt(Vector2(nx + name_w + 8, cy + 4), _seat_word(pid), 12, Color(SUB, a), font, 40)
		if m.mode == "derby":
			_txt(Vector2(row.end.x - 70, cy + 5), "%d점" % m.scores[pid], 14, POWER, font_bold, 40, HORIZONTAL_ALIGNMENT_RIGHT)
		var right := row.end.x - 8
		if p.out:
			_txt(Vector2(right, cy + 4), "탈락", 12, Color(SUB, 0.8), font, 50, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			var left := m.stones_left(pid)
			for k2 in left:
				draw_circle(Vector2(right - 4 - k2 * 12, cy), 4.0, p.color)
			# 방금 잃은 퍽 점: 커졌다 사라짐 (0.35초)
			var pt: float = time - float(hud_pop.get(pid, -9.0))
			if pt >= 0.0 and pt < 0.35 and not _reduced():
				var k3 := pt / 0.35
				draw_circle(Vector2(right - 4 - left * 12, cy), 4.0 * (1.0 + 1.2 * k3), Color(p.color, 1.0 - k3))
			var tag := ""
			if pid == cur:
				tag = "지금"
			elif i == 1 and m.phase != "draft":
				tag = "다음"
			if tag != "" and not portrait:
				_txt(Vector2(right - 12 - left * 12, cy + 4), tag, 12, HINT_GOLD if tag == "지금" else SUB, font_semi, 40, HORIZONTAL_ALIGNMENT_RIGHT)
		y += row_h
		i += 1


func _draw_log() -> void:
	if log_lines.is_empty():
		return
	var shown: Array = log_lines.slice(maxi(0, log_lines.size() - 3))
	shown.reverse()
	var r: Rect2 = hud["log"]
	var lh := 22.0
	var lines: Array = []
	for e in shown:
		lines.append(_wrap(e["t"], font, 14, r.size.x - 54))
	var total := 0
	for l in lines:
		total += l.size()
	r.size.y = 14 + 24 + total * lh + 12
	r.position.y = get_viewport_rect().size.y - 24 - r.size.y
	if r.position.y < hud.get("aimed_end", 0.0) + 12:
		return
	_panel(r)
	_txt(r.position + Vector2(18, 27), "기록", 13, SUB, font_semi)
	var y := r.position.y + 54
	for k in shown.size():
		var e: Dictionary = shown[k]
		var age: float = clampf((time - float(e.get("at", -9.0))) / 0.3, 0.0, 1.0)
		var ex := 12.0 * (1.0 - (1.0 - pow(1.0 - age, 3.0))) if not _reduced() else 0.0
		draw_circle(Vector2(r.position.x + 22 + ex, y - 5), 4, Color(e["c"], age))
		for ln in lines[k]:
			_txt(Vector2(r.position.x + 36 + ex, y), ln, 14, Color(TEXT if k == 0 else SUB, age), font)
			y += lh


## 폭에 맞춰 줄바꿈 (글자 단위).
func _wrap(t: String, f: Font, size: int, maxw: float) -> Array:
	var key := "w|%s|%d|%d|%d" % [t, f.get_instance_id(), size, int(maxw)]
	if _text_cache.has(key):
		return _text_cache[key]
	var lines := _wrap_raw(t, f, size, maxw)
	_text_cache[key] = lines
	return lines


func _wrap_raw(t: String, f: Font, size: int, maxw: float) -> Array:
	var out: Array = []
	var cur := ""
	for ch in t:
		if f.get_string_size(cur + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw and cur != "":
			out.append(cur)
			cur = ch.strip_edges(true, false) if ch == " " else ch
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func _segments(r: Rect2, frac: float) -> void:
	var n := 10
	var gap := 3.0
	var w := (r.size.x - gap * (n - 1)) / n
	var lit := int(round(frac * n))
	for i in n:
		var rr := Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y)
		var fc: Color = BRASS if i < 6 else Color("F0A23A")
		_round_rect(rr, fc if i < lit else Color(FG, 0.12), 2)


func _draw_power(r: Rect2) -> void:
	if m.phase != "aim":
		return
	var info := _current_aim()
	var pw: float = info.get("power", 0.0) if not info.is_empty() else 0.0
	_panel(r)
	_txt(r.position + Vector2(18, 30), "힘", 13, SUB, font_semi)
	var label := "%d%%" % int(round(pw * 100)) if not info.is_empty() and not info.has("cancel") else ("취소" if info.has("cancel") else "—")
	_txt(Vector2(r.end.x - 18, r.position.y + 36), label, 22, POWER, font_bold, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	_segments(Rect2(r.position.x + 18, r.position.y + 46, r.size.x - 36, 12), pw)
	var kind := ""
	if not info.is_empty() and not info.has("cancel"):
		kind = "위치를 다듬는 샷" if pw < 0.35 else ("밀어내는 샷" if pw < 0.7 else "판 밖으로 보내는 샷")
	_txt(Vector2(r.position.x + 18, r.position.y + 80), kind if kind != "" else "알을 당겨 힘을 정해요", 13, TEXT if kind != "" else SUB, font_semi, r.size.x - 36)
	_txt(Vector2(r.position.x + 18, r.position.y + 98), "점선 원 안으로 되돌리면 취소", 12, SUB, font, r.size.x - 36)


## 조준 중인 퍽 (또는 손을 올린 퍽)의 부품.
func _draw_aimed(r: Rect2) -> void:
	if m.phase == "place":
		return
	var s = _focus_stone()
	var empty: bool = s == null or (s.parts["weapon"] == "" and s.parts["aux"] == "" and s.parts["prop"] == "")
	var set_txt: String = PartsData.set_label(s.parts) if s != null else ""
	var first_hint := ""
	if empty and m.round_no < m.first_draft_round:
		first_hint = "첫 개조는 %d바퀴가 시작될 때 해요." % m.first_draft_round
	var step := 34.0
	if not portrait:
		r.size.y = 14 + 26 + 3 * step + 8 + (62.0 if set_txt != "" else 0.0) + (50.0 if first_hint != "" else 0.0)
		hud["aimed_end"] = r.end.y
	_panel(r)
	var head_t := "조준 중인 알" if drag_stone >= 0 or (m.phase == "aim" and not m.players[m.current_player()].cpu and hover_stone < 0) else "이 알의 부품"
	_txt(r.position + Vector2(50, 27), head_t, 14, TEXT, font_bold)
	_txt(Vector2(r.end.x - 16, r.position.y + 27), "노란 고리", 12, POWER, font_semi, 80, HORIZONTAL_ALIGNMENT_RIGHT)
	if s == null:
		return
	_hud_icon(Vector2(r.position.x + 30, r.position.y + 22), 22, m.players[s.owner].color, s.owner)
	# 지금 보여주는 알을 판 위에 노란 고리로 표시 (패널 제목 옆 「노란 고리」)
	if m.phase != "draft":
		var fp := w2s(s.pos)
		var fr := (World.STONE_R + 8) * view_scale
		draw_arc(fp, fr, 0, TAU, 40, Color(0, 0, 0, 0.35), 5.0, true)
		draw_arc(fp, fr, 0, TAU, 40, Color("F2C94C"), 3.0, true)
	var y := r.position.y + 40 + step * 0.5
	if portrait:
		step = minf(34.0, (r.size.y - 50.0 - (26.0 if set_txt != "" else 0.0)) / 3.0)
	for slot in PartsData.SLOTS:
		var id: String = s.parts[slot]
		Art.draw_slot_icon(self, Vector2(r.position.x + 18 + 11, y), 22, slot)
		_txt(Vector2(r.position.x + 50, y + 5), PartsData.SLOT_LABEL[slot], 13, SUB, font)
		var nm := PartsData.part_name(id) if id != "" else "비어 있음"
		if PartsData.SIDE_PARTS.has(id):
			var sd: int = s.prop_side if slot == "prop" else s.magnet_side
			nm += " (왼쪽)" if sd < 0 else " (오른쪽)"
		_txt(Vector2(r.position.x + 90, y + 5), nm, 15, TEXT if id != "" else MUTED, font_semi, r.size.x - 102)
		if id != "" and PartsData.unmet_need(id, s.parts) != "":
			_txt(Vector2(r.end.x - 14, y + 5), "⚠", 13, POWER, font, 20, HORIZONTAL_ALIGNMENT_RIGHT)
		y += step
	if set_txt != "":
		# 세트 진행 막대: 이름 · n/3 · 세 칸 · 필요한 부품 (디자인 「오늘의 공방」)
		var sp := PartsData.set_progress(s.parts)
		var sx := r.position.x + 18
		var sw := r.size.x - 36
		draw_line(Vector2(sx, y - 8), Vector2(sx + sw, y - 8), PANEL_LINE, 1.0)
		_txt(Vector2(sx, y + 8), PartsData.SETS[sp["set"]]["name"], 13, TEXT, font_semi, sw - 40)
		_txt(Vector2(sx + sw, y + 8), "%d/%d" % [sp["count"], sp["total"]], 13, ACCENT, font_bold, 40, HORIZONTAL_ALIGNMENT_RIGHT)
		var tot: int = sp["total"]
		var gw := (sw - 3.0 * (tot - 1)) / tot
		for k in tot:
			_round_rect(Rect2(sx + k * (gw + 3.0), y + 15, gw, 5), ACCENT if k < sp["count"] else Color(FG, 0.14), 2)
		if sp["count"] >= tot:
			_txt(Vector2(sx, y + 38), "완성", 12, ACCENT, font_bold, sw)
		else:
			var miss: Array = []
			for mp in sp["missing"]:
				miss.append(PartsData.SETS[sp["set"]].get("short", {}).get(mp, PartsData.part_name(mp)))
			_txt(Vector2(sx, y + 38), "·".join(miss) + " 필요", 12, SUB, font, sw)
		y += 62
	if first_hint != "":
		var hb := Rect2(r.position.x + 14, y - 8, r.size.x - 28, 40)
		_round_rect(hb, Color(BRASS, 0.12), 8)
		_txt(Vector2(hb.position.x + 12, hb.position.y + 25), first_hint, 13, HINT_GOLD, font, hb.size.x - 24)


func _small_label(p: Vector2, t: String, c: Color) -> void:
	if t == "":
		return
	_text_outline(p, t, 13, c, true)


func _text_outline(p: Vector2, t: String, size: int, c: Color, center: bool) -> void:
	var width := font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := p - Vector2(width * 0.5 if center else 0.0, 0)
	draw_string_outline(font_bold, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(INK, c.a * 0.85))
	draw_string(font_bold, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


# ── UI 화면 ──────────────────────────────────────────────

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): snd.play("ui_click", -6.0))
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _sb(BRASS, BRASS.darkened(0.3), 8))
	b.add_theme_stylebox_override("hover", _sb(BRASS.lightened(0.12), BRASS, 8))
	b.add_theme_stylebox_override("pressed", _sb(BRASS.darkened(0.12), BRASS, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, INK)
	b.add_theme_font_override("font", font_bold)
	return b


func _label(text: String, size := 17, col := TEXT, weight := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if weight == 1:
		l.add_theme_font_override("font", font_semi)
	elif weight == 3:
		l.add_theme_font_override("font", font_display)
	elif weight >= 2:
		l.add_theme_font_override("font", font_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 가로 줄(HBox) 안의 라벨은 줄바꿈을 끈다 (안 그러면 폭이 0이 되어 한 글자씩 꺾인다).
func _nw(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _panel_style(bg := PANEL_BG, border := PANEL_LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	match str(th.get("panel_style", "")):
		"manga":
			sb.border_color = Color("111111")
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(4)
			sb.shadow_color = Color("111111")
			sb.shadow_size = 1
			sb.shadow_offset = Vector2(4, 4)
		"junk":
			sb.border_width_top = 4
			sb.border_color = Color("FFC23D")
		"magic":
			sb.shadow_color = Color(183 / 255.0, 200 / 255.0, 1.0, 0.18)
			sb.shadow_size = 18
	sb.set_content_margin_all(22)
	return sb


## 퍽 그림 컨트롤. parts 가 비어 있으면 무늬만.
func _puck_pic(parts: Dictionary, col: Color, symbol: int, size: Vector2, scale: float, mside := 1) -> Control:
	var pic := Control.new()
	pic.custom_minimum_size = size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func():
		pic.draw_set_transform(pic.size * 0.5 + Vector2(0, 2 * scale), -PI / 2.0, Vector2.ONE * scale)
		Art.draw(pic, parts, mside, col, 1.0, symbol)
		pic.draw_set_transform_matrix(Transform2D.IDENTITY))
	return pic


func _icon_pic(col: Color, symbol: int, size: float) -> Control:
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(size + 4, size + 6)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func(): Art.draw_icon(pic, pic.size * 0.5, size, col, symbol))
	return pic


func _clear_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


## dim: 뒤를 가리고 입력을 막을지. 아니면 판을 누를 수 있게 둔다.
func _new_overlay(dim: bool) -> Control:
	_clear_overlay()
	var root := Control.new()
	root.theme = theme_
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP if dim else Control.MOUSE_FILTER_IGNORE
	if dim:
		var bg := ColorRect.new()
		bg.color = Color(BG_OUT, 0.72)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
	ui.add_child(root)
	overlay = root
	if not _reduced() and state != "setup":
		root.modulate.a = 0.0
		create_tween().tween_property(root, "modulate:a", 1.0, 0.14)
	return root


func _centered_panel(root: Control, min_w: float, bg := Color(SOLID, 0.9)) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var vs := get_viewport_rect().size
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(bg))
	pc.custom_minimum_size = Vector2(minf(min_w, vs.x - 24), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	pc.add_child(box)
	cc.add_child(pc)
	return box


func _show_setup() -> void:
	if online == "guest":
		_show_guest_lobby()
		return
	state = "setup"
	m = null
	menu_btn.visible = false
	parts_btn.visible = false
	sound_btn.visible = false
	var root := _lobby_root()
	var vs := get_viewport_rect().size
	var narrow := vs.x < 900
	# 디자인 「로비」: 왼쪽 판(공방·모드·인원·자리·시작), 오른쪽 판(경기장 미리보기·판 정보)
	var width := minf(620.0, vs.x * 0.5 - 56.0) if not narrow else vs.x - 32.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16 if (not narrow and vs.y >= 760.0) else 12)
	col.custom_minimum_size = Vector2(width, 0)
	col.position = Vector2(56.0 if not narrow else 16.0, 24.0)
	root.add_child(col)
	# 제목 + 아이콘 (친구 초대 · 소리 · 설정)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := _nw(_label("개조 알까기", 46 if not narrow else 36, TEXT, 3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var inv := _icon_button("invite", func():
		if online == "":
			_start_hosting(), "친구 초대 링크 만들기")
	inv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(inv)
	var sb_ := _icon_button("sound" if snd.enabled else "mute", func():
		_toggle_sound()
		_show_setup(), "소리 켜짐" if snd.enabled else "소리 꺼짐")
	sb_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sb_)
	var gear := _icon_button("gear", func(): _show_settings(true), "설정 (맵 · 게임 속도 · 조준 시간 · 소리)")
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gear)
	col.add_child(head)
	if online == "host":
		col.add_child(_invite_row())
	# 오늘의 공방
	col.add_child(_workshop_row())
	# 모드 · 인원
	var mr: BoxContainer = HBoxContainer.new() if not narrow else VBoxContainer.new()
	mr.add_theme_constant_override("separation", 16 if not narrow else 10)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.size_flags_stretch_ratio = 0.85
	mv.add_child(_label("모드", 14, LABEL, 1))
	var cur_mode: String = settings.get("mode", "survival")
	mv.add_child(_seg([["survival", "최후 생존전"], ["derby", "개조 더비"]], cur_mode, func(k):
		settings["mode"] = k
		if online == "host":
			_host_broadcast_lobby()
		_show_setup()))
	mr.add_child(mv)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 8)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_stretch_ratio = 1.15
	nv.add_child(_label("인원", 14, LABEL, 1))
	var counts: Array = []
	for n in range(2, 9):
		counts.append([n, str(n)])
	nv.add_child(_seg(counts, settings["n"], func(k): _set_count(k)))
	mr.add_child(nv)
	col.add_child(mr)
	if cur_mode == "derby":
		col.add_child(_label("정해진 %d바퀴 동안 모두 계속 둡니다. 떨어진 퍽은 다음 바퀴에 부품을 단 채 돌아오고, 상대 퍽을 떨어뜨리면 1점." % (Match.DERBY_ROUNDS_SMALL if settings["n"] <= 4 else Match.DERBY_ROUNDS_BIG), 12, SUB))
	# 자리
	var g2 := VBoxContainer.new()
	g2.add_theme_constant_override("separation", 8)
	var hr := HBoxContainer.new()
	var sl := _nw(_label("자리 · 눌러서 사람/CPU%s 바꾸기" % ("/친구" if online == "host" else ""), 14, LABEL, 1))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(sl)
	var humans := 0
	for i in settings["n"]:
		if not settings["cpu"][i]:
			humans += 1
	hr.add_child(_nw(_label("사람 %d명, CPU %d명" % [humans, settings["n"] - humans], 13, SUB)))
	g2.add_child(hr)
	var grid := GridContainer.new()
	grid.columns = 2 if (narrow or settings["n"] <= 2) else 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in settings["n"]:
		grid.add_child(_seat_button(i))
	g2.add_child(grid)
	col.add_child(g2)
	# 시작
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	var start := _primary(_button("공방 열기", func(): _start_match()))
	start.custom_minimum_size = Vector2(0, 56)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.add_theme_font_override("font", font_display)
	start.add_theme_font_size_override("font_size", 22)
	row2.add_child(start)
	var cat := _button("부품 도감", func(): _show_catalog(true))
	cat.custom_minimum_size = Vector2(130, 56)
	cat.add_theme_font_override("font", font_semi)
	row2.add_child(cat)
	col.add_child(row2)
	# 오른쪽: 경기장 미리보기
	if not narrow:
		var col2 := VBoxContainer.new()
		var w2 := vs.x - 56.0 * 2.0 - width - 48.0
		col2.custom_minimum_size = Vector2(w2, 0)
		col2.position = Vector2(vs.x - 56.0 - w2, 24.0)
		root.add_child(col2)
		lobby_preview = Control.new()
		lobby_preview.custom_minimum_size = Vector2(w2, minf(vs.y - 96.0, w2 + 150.0))
		lobby_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lp := lobby_preview
		lp.draw.connect(func(): _draw_lobby_preview(lp))
		col2.add_child(lobby_preview)
		lobby_col2 = col2
	else:
		lobby_preview = null
	lobby_col = col


## 분절 버튼: options = [[값, 글자], ...]
func _seg(options: Array, cur, cb: Callable) -> Control:
	var seg := PanelContainer.new()
	var segsb := _sb(Color(FG, 0.06), Color(FG, 0.1), 10)
	segsb.set_content_margin_all(4)
	seg.add_theme_stylebox_override("panel", segsb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	seg.add_child(row)
	for o in options:
		var val = o[0]
		var on: bool = val == cur
		var b := _button(str(o[1]), func(): cb.call(val))
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", font_semi)
		b.add_theme_font_size_override("font_size", 16)
		var st := _sb(BRASS if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 7)
		st.set_border_width_all(0)
		b.add_theme_stylebox_override("normal", st)
		var sth := _sb(BRASS.lightened(0.1) if on else Color(FG, 0.08), Color(0, 0, 0, 0), 7)
		sth.set_border_width_all(0)
		b.add_theme_stylebox_override("hover", sth)
		b.add_theme_stylebox_override("pressed", sth)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, INK if on else TEXT)
		row.add_child(b)
	return seg


func _seat_button(i: int) -> Button:
	var friend: bool = settings["friend"][i] and online == "host"
	var human: bool = not settings["cpu"][i] and not friend
	var b := _button("", func(): _toggle_cpu(i))
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = "%s 자리, 지금 %s. 눌러서 바꾸기" % [Match.NAMES[i], "사람" if human else "CPU"]
	var border := Color(BRASS, 0.7) if human else (Color("7FB2FF", 0.7) if friend else Color(FG, 0.12))
	b.add_theme_stylebox_override("normal", _sb(Color(FG, 0.05), border, 8))
	b.add_theme_stylebox_override("hover", _sb(Color(FG, 0.09), border, 8))
	b.add_theme_stylebox_override("pressed", _sb(Color(FG, 0.09), border, 8))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -8
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ic := _icon_pic(Match.COLORS[i], i, 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var nm := _nw(_label(Match.NAMES[i], 15, TEXT))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.size_flags_vertical = Control.SIZE_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	var pill := PanelContainer.new()
	var psb := _sb(BRASS if human else (Color("7FB2FF") if friend else Color(FG, 0.1)), Color(0, 0, 0, 0), 999)
	psb.set_border_width_all(0)
	psb.content_margin_left = 10
	psb.content_margin_right = 10
	psb.content_margin_top = 2
	psb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", psb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var word := "사람" if human else "CPU"
	if friend:
		word = "친구 · 접속" if friend_peer.has(i) else "친구 · 대기"
	var pl := _nw(_label(word, 13, INK if human or friend else LABEL, 1))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.custom_minimum_size = Vector2(28, 0)
	pill.add_child(pl)
	h.add_child(pill)
	return b


func _toggle_sound() -> void:
	snd.set_enabled(not snd.enabled)
	_update_sound_btn()
	snd.play("ui_toggle")


func _update_sound_btn() -> void:
	if sound_btn:
		sound_btn.set_meta("icon", "sound" if snd.enabled else "mute")
		sound_btn.tooltip_text = "소리 켜짐" if snd.enabled else "소리 꺼짐"
		sound_btn.queue_redraw()
		for c in sound_btn.get_children():
			(c as Control).queue_redraw()


func _set_count(n: int) -> void:
	snd.play("ui_toggle")
	settings["n"] = n
	settings["timed"] = n >= 5
	for seat in friend_peer.keys():
		if seat >= n:
			net.send_to(friend_peer[seat], {"t": "full"})
			friend_peer.erase(seat)
	if online == "host":
		_host_broadcast_lobby()
	_show_setup()


func _toggle_cpu(i: int) -> void:
	snd.play("ui_toggle")
	if online == "host":
		# 사람 → CPU → 친구 → 사람
		if settings["friend"][i]:
			settings["friend"][i] = false
			settings["cpu"][i] = false
			if friend_peer.has(i):
				net.send_to(friend_peer[i], {"t": "full"})
				friend_peer.erase(i)
		elif settings["cpu"][i]:
			settings["cpu"][i] = false
			settings["friend"][i] = true
		else:
			settings["cpu"][i] = true
		_host_broadcast_lobby()
	else:
		settings["cpu"][i] = not settings["cpu"][i]
	_show_setup()


func _show_catalog(from_setup: bool) -> void:
	var prev_overlay_was_draft := m != null and m.phase == "draft"
	var root := _new_overlay(true)
	if from_setup:
		root.get_child(0).color = Color(PAGE_FELT, 0.6)
	var cc := MarginContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		cc.add_theme_constant_override("margin_" + side, 24)
	root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.92)))
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var head := HBoxContainer.new()
	var title := _nw(_label("퍽과 부품 · %d종" % PartsData.ids().size(), 26, TEXT, 2))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("닫기", func():
		if from_setup:
			_show_setup()
		else:
			_clear_overlay()
			if prev_overlay_was_draft and m != null and m.phase == "draft" and not m.players[m.current_drafter()].cpu:
				_show_draft_cards(m.current_drafter())))
	v.add_child(head)
	v.add_child(_label("퍽 하나에 무기(앞)·보조(옆)·추진(뒤) 슬롯이 하나씩. 같은 슬롯에 새 부품을 달면 교체된다. 쏜 퍽의 부품은 한 샷에 한 번씩 작동한다.", 14, SUB))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var vs := get_viewport_rect().size
	var cols := 1 if vs.x < 640 else (2 if vs.x < 1000 else 3)
	for slot in PartsData.SLOTS:
		var sh := HBoxContainer.new()
		sh.add_theme_constant_override("separation", 10)
		var si := Control.new()
		si.custom_minimum_size = Vector2(28, 28)
		si.draw.connect(func(): Art.draw_slot_icon(si, si.size * 0.5, 28, slot))
		sh.add_child(si)
		sh.add_child(_nw(_label(PartsData.SLOT_LABEL[slot], 20, TEXT, 1)))
		list.add_child(sh)
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 10)
		for id in PartsData.ids():
			var d := PartsData.get_part(id)
			if d["slot"] != slot:
				continue
			var cell := HBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_constant_override("separation", 10)
			var demo := {"weapon": "", "aux": "", "prop": ""}
			demo[slot] = id
			cell.add_child(_puck_pic(demo, Art.NEUTRAL, -1, Vector2(96, 112), 1.05))
			var tv := VBoxContainer.new()
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_child(_label(d["name"], 17, TEXT, 1))
			tv.add_child(_label(d["when"], 13, BRASS))
			tv.add_child(_label(d["desc"], 13, SUB))
			cell.add_child(tv)
			grid.add_child(cell)
		list.add_child(grid)
	# 세트
	var how := {"trex": "상대 옆을 스치듯 쏴서 팔이 먼저 닿으면 한 번: 팔이 끌어오고, 머리가 물어 조준 방향으로 던지고, 다리가 버텨 반동을 줄인다. 끌어올 자리가 막혀 있으면 일반 충돌, 정면으로 먼저 받으면 머리의 기본 물기.",
		"moon": "지팡이의 빛 구슬로 표식을 남긴 상대와 첫 충돌하면, 그 자리의 마법진이 상대를 접선 방향으로 튕기고 내 알은 장화로 앞으로 도약한다.",
		"hero": "세 부품을 단 알이 내 마지막 알이면, 첫 상대 알이 떨어지는 순간 망토가 내 알을 멈추고 운동화가 조준 반대 방향으로 짧게 튕겨낸다. 머리띠의 충격파는 약한 샷에서 그대로 쓴다."}
	for set_id in PartsData.SETS:
		var st: Dictionary = PartsData.SETS[set_id]
		list.add_child(_label("%s · %s" % [st["name"], st["move"]], 20, TEXT, 1))
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 14)
		var sp: Array = st["parts"]
		srow.add_child(_puck_pic({"weapon": sp[0], "aux": sp[1], "prop": sp[2]}, Match.COLORS[0], 0, Vector2(130, 150), 1.3))
		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var names: Array = []
		for pid2 in sp:
			names.append(PartsData.part_name(pid2))
		sv.add_child(_label("%s를 한 퍽에 모두 달면 변신하고 「%s」가 열린다." % ["·".join(names), st["move"]], 15, TEXT))
		sv.add_child(_label(how.get(set_id, ""), 13, SUB))
		srow.add_child(sv)
		list.add_child(srow)
	list.add_child(_label("미완성 세트 부품을 단 살아 있는 퍽이 있으면 다음 개조 후보 한 자리는 그 퍽에 빠진 세트 부품이다. 여러 퍽이 모으고 있으면 많이 모은 퍽, 같으면 지난번에 장착한 퍽이 우선.", 13, BRASS))


func _part_card(pid: int, part: String, compact := false) -> Button:
	var d := PartsData.get_part(part)
	var slot: String = d["slot"]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	var nb := _panel_style(Color(SOLID, 0.97), PANEL_LINE)
	nb.set_corner_radius_all(14 if th.get("panel_style", "") != "manga" else 6)
	nb.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", nb)
	var hb := nb.duplicate()
	hb.border_color = BRASS
	hb.set_border_width_all(5)
	hb.shadow_color = Color(BRASS, 0.35)
	hb.shadow_size = 6
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", hb)
	b.pressed.connect(func(): _on_card_picked(pid, part))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4 if compact else 6)
	var pic_box: Container = v
	if compact:
		var hb2 := HBoxContainer.new()
		hb2.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb2.offset_left = 8
		hb2.offset_right = -10
		hb2.offset_top = 8
		hb2.offset_bottom = -8
		hb2.add_theme_constant_override("separation", 8)
		hb2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lp := VBoxContainer.new()
		lp.custom_minimum_size = Vector2(92, 0)
		lp.alignment = BoxContainer.ALIGNMENT_CENTER
		lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb2.add_child(lp)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		hb2.add_child(v)
		b.add_child(hb2)
		pic_box = lp
	else:
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 12
		v.offset_right = -12
		v.offset_top = 14
		v.offset_bottom = -12
		b.add_child(v)
	# 배지: 슬롯 · 세트 n/3
	var badges := HBoxContainer.new()
	badges.alignment = BoxContainer.ALIGNMENT_BEGIN if compact else BoxContainer.ALIGNMENT_CENTER
	badges.add_theme_constant_override("separation", 4)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges.add_child(_badge(PartsData.SLOT_LABEL[slot], Color(FG, 0.12), TEXT))
	var set_id := PartsData.set_of(part)
	if set_id != "":
		var best := 0
		for st in m.world.alive_stones_of(pid):
			var c: int = PartsData.set_progress(st.parts, set_id)["count"]
			if c < 3 and not st.parts.values().has(part):
				best = maxi(best, c)
		badges.add_child(_badge("%s %d/3" % [PartsData.SETS[set_id]["name"], best + 1], ACCENT, ACCENT_INK))
	v.add_child(badges)
	var demo := {"weapon": "", "aux": "", "prop": ""}
	demo[slot] = part
	pic_box.add_child(_puck_pic(demo, m.players[pid].color, pid, Vector2(0, 92 if compact else 104), 0.86 if compact else 0.98))
	var name_l := _label(d["name"], 16 if compact else 17, TEXT, 2)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	var one: String = d["when"] + " · " + str(d["desc"]).split(". ")[0].trim_suffix(".")
	var desc_l := _label(one, 12, SUB)
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	desc_l.custom_minimum_size = Vector2(0, 0 if compact else 34)
	for l in [name_l, desc_l]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	# 움직임 그림 상자 (디자인 「개조 화면」): 내 알과 부품이 만드는 움직임
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(0, 66)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var akind := _motion_of(part)
	var pcol: Color = m.players[pid].color
	arrow.draw.connect(func():
		_round_rect_on(arrow, Rect2(Vector2.ZERO, arrow.size), Color(FG, 0.06), 10)
		var k := 2.6
		arrow.draw_set_transform(Vector2(arrow.size.x * 0.5 - 19.0 * k, arrow.size.y * 0.5 - 9.0 * k), 0.0, Vector2.ONE * k)
		_draw_motion(arrow, akind, pcol)
		arrow.draw_set_transform_matrix(Transform2D.IDENTITY))
	if compact:
		arrow.queue_free()
	else:
		v.add_child(arrow)
	# 빈 슬롯에 바로 장착 / 기존 부품과 교체
	var fit := false
	for st in m.world.alive_stones_of(pid):
		if st.parts[slot] == "":
			fit = true
	var ok_col := Color("2F8F5B") if not th["dark"] else Color("7FD1A8")
	var fl := _label("빈 슬롯에 바로 장착" if fit else "기존 부품과 교체", 13, ok_col if fit else TEXT, 2)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fl)
	var need: String = d.get("needs", "")
	if need != "":
		var any_ok := false
		for s2 in m.world.alive_stones_of(pid):
			var tmp: Dictionary = s2.parts.duplicate()
			tmp[slot] = part
			if PartsData.unmet_need(part, tmp) == "":
				any_ok = true
		var nl := _label("조건 충족" if any_ok else "⚠ " + PartsData.unmet_need(part, {}), 12, Color("7FD1A8") if any_ok else POWER)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nl)
	return b


func _badge(t: String, bg: Color, fg: Color) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var l := _nw(_label(t, 11, fg, 2))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


func _show_draft_cards(pid: int) -> void:
	var p: Dictionary = m.players[pid]
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var width := minf(760.0, vs.x - 24.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(width, 0)
	v.position = Vector2((vs.x - width) * 0.5, 0)
	root.add_child(v)
	var title := _label("%d바퀴 개조" % m.round_no + ("" if my_seats.size() <= 1 else " · " + p.name), 34, Color.WHITE, 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	title.add_theme_constant_override("shadow_offset_y", 2)
	v.add_child(title)
	var sub := _label("후보 하나를 골라 살아 있는 내 알에 붙여요 · 모두 동시에 골라요", 15, Color(1, 1, 1, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	sub.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	var stack := portrait and vs.x < 640
	var holder: BoxContainer = VBoxContainer.new() if stack else HBoxContainer.new()
	holder.add_theme_constant_override("separation", 12)
	v.add_child(holder)
	var k := 0
	for part in m.offers[pid]:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(0, 132 if stack else 352)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(cell)
		var card := _part_card(pid, part, stack)
		cell.add_child(card)
		_deal_card(card, k)
		card.mouse_entered.connect(func():
			if not _reduced():
				create_tween().tween_property(card, "position:y", -6.0, 0.15))
		card.mouse_exited.connect(func():
			create_tween().tween_property(card, "position:y", 0.0, 0.15))
		k += 1
	snd.play("part_offer", -6.0)
	root.add_child(_draft_status_bar(pid))
	await get_tree().process_frame
	if is_instance_valid(v):
		var h := v.size.y
		v.position.y = clampf(vs.y * 0.5 - h * 0.5, 8, vs.y - h - 8)


## 카드 나눠주기: 아래에서 올라오며 뒤집힌다 (0.45초, 카드마다 0.09초씩 늦게).
func _deal_card(card: Control, k: int) -> void:
	if _reduced():
		return
	card.modulate.a = 0.0
	card.position.y = 40.0
	card.scale = Vector2(0.2, 1.0)
	card.pivot_offset = Vector2(110, 160)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.18).set_delay(k * 0.06)
	tw.tween_property(card, "position:y", 0.0, 0.32).set_delay(k * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale:x", 1.0, 0.32).set_delay(k * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hint_panel(pid: int) -> VBoxContainer:
	var root := _new_overlay(false)
	var pc := PanelContainer.new()
	var sb := _panel_style(Color(SOLID, 0.92), Color(m.players[pid].color, 0.8))
	sb.set_content_margin_all(16)
	pc.add_theme_stylebox_override("panel", sb)
	var vs := get_viewport_rect().size
	pc.custom_minimum_size = Vector2(minf(420, vs.x - 24), 0)
	root.add_child(pc)
	# 화면 아래 가운데 (차례 목록·패널과 겹치지 않게)
	pc.resized.connect(func(): pc.position = Vector2(vs.x * 0.5 - pc.size.x * 0.5, vs.y - pc.size.y - 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	return v


func _show_stone_hint(pid: int) -> void:
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var pc := PanelContainer.new()
	var sb := _panel_style(Color(SOLID, 0.95), PANEL_LINE)
	sb.content_margin_left = 16
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	root.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	var d := PartsData.get_part(draft_part)
	var demo := {"weapon": "", "aux": "", "prop": ""}
	demo[d["slot"]] = draft_part
	h.add_child(_puck_pic(demo, Art.NEUTRAL, -1, Vector2(40, 40), 0.42))
	var hl := _nw(_label("%s 달 알을 누르세요" % _j(d["name"], "을", "를"), 16, TEXT, 2))
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	var again := _button("다시 고르기", func(): _show_draft_cards(pid))
	again.add_theme_font_size_override("font_size", 13)
	again.custom_minimum_size = Vector2(0, 32)
	h.add_child(again)
	await get_tree().process_frame
	if is_instance_valid(pc):
		pc.position = Vector2(vs.x * 0.5 - pc.size.x * 0.5, vs.y - pc.size.y - 16)


func _show_bookmark_choice(pid: int) -> void:
	var v := _hint_panel(pid)
	v.add_child(_label("운명의 책갈피: 다음 선택에 예약할 후보를 고르세요", 17, TEXT, 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var sid := draft_stone
	for other in m.offers[pid]:
		if other == "bookmark":
			continue
		var o: String = other
		h.add_child(_button(PartsData.part_name(o), func(): _apply_equip(pid, "bookmark", sid, 1, o)))
	h.add_child(_button("다시 고르기", func(): _show_draft_cards(pid)))
	v.add_child(h)


func _show_relic_hint(pid: int) -> void:
	relic_mode = true
	var v := _hint_panel(pid)
	var part: String = m.players[pid].relic
	v.add_child(_label("유품 리본: %s 달 퍽을 누르세요 (빈 %s 슬롯)" % [_j(PartsData.part_name(part), "을", "를"), PartsData.SLOT_LABEL[PartsData.slot_of(part)]], 16, TEXT, 1))
	v.add_child(_button("이번엔 안 달기", func():
		relic_mode = false
		_clear_overlay()))


func _equip_relic(sid: int) -> void:
	_act({"k": "relic", "pid": m.current_player(), "stone": sid})


func _do_equip_relic(pid: int, sid: int) -> void:
	var part: String = m.players[pid].relic
	if m.equip_relic(pid, sid):
		relic_mode = false
		if _is_mine(pid):
			_clear_overlay()
		var st = m.world.get_stone(sid)
		_log("%s 유품 %s 달았어요" % [_j(m.players[pid].name, "이", "가"), _j(PartsData.part_name(part), "을", "를")], m.players[pid].color)
		fx.append({"k": "ring", "pos": st.pos, "t": 0.0, "life": 0.6, "r": 40.0, "c": POWER})


func _show_side_choice(pid: int) -> void:
	# 디자인 「자석팔 방향」: 퍽 양옆에 왼쪽/오른쪽 버튼, 아래에 다시 고르기
	var root := _new_overlay(false)
	var sid := draft_stone
	var part := draft_part
	var st = m.world.get_stone(sid)
	var p := w2s(st.pos)
	var off := (World.STONE_R * 2.2) * view_scale + 12.0
	var lb := _button("◀ 왼쪽", func(): _apply_equip(pid, part, sid, -1))
	var rb := _primary(_button("오른쪽 ▶", func(): _apply_equip(pid, part, sid, 1)))
	for b2 in [lb, rb]:
		b2.custom_minimum_size = Vector2(96, 46)
		b2.add_theme_font_override("font", font_bold)
		b2.add_theme_font_size_override("font_size", 16)
		root.add_child(b2)
	lb.resized.connect(func(): lb.position = Vector2(p.x - off - lb.size.x, p.y - lb.size.y * 0.5))
	rb.resized.connect(func(): rb.position = Vector2(p.x + off, p.y - rb.size.y * 0.5))
	lb.position = Vector2(p.x - off - 96, p.y - 23)
	rb.position = Vector2(p.x + off, p.y - 23)
	var again := _button("다시 고르기", func(): _show_draft_cards(pid))
	again.add_theme_font_size_override("font_size", 13)
	root.add_child(again)
	var vs := get_viewport_rect().size
	again.position = Vector2(vs.x * 0.5 - 50.0, vs.y - 58.0)
	again.resized.connect(func(): again.position = Vector2(vs.x * 0.5 - again.size.x * 0.5, vs.y - again.size.y - 18))


func _show_result() -> void:
	state = "result"
	snd.slide(0.0)
	if m.winners.is_empty():
		snd.play("draw")
	drag_stone = -1
	var root := _new_overlay(true)
	var box := _centered_panel(root, 520)
	var title := ""
	var col := TEXT
	if m.winners.is_empty():
		title = "무승부"
	elif m.winners.size() == 1:
		var wp: int = m.winners[0]
		title = "내가 이겼어요" if _is_mine(wp) and my_seats.size() == 1 else "%s 승리" % m.players[wp].name
		col = m.players[wp].color
	else:
		var names: Array = []
		for w in m.winners:
			names.append(m.players[w].name)
		title = "공동 승리: " + ", ".join(names)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	if m.winners.size() == 1:
		head.add_child(_icon_pic(m.players[m.winners[0]].color, m.winners[0], 48))
	var tl := _label(title, 48, col, 3)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_color_override("font_outline_color", Color(th["outline"], 0.6))
	tl.add_theme_constant_override("outline_size", 4)
	head.add_child(tl)
	box.add_child(head)
	root.get_child(0).color = Color(0, 0, 0, 0.25)
	# 승리 창: 작게 시작해 튀어나온다
	var pc_: Control = box.get_parent()
	if not _reduced():
		pc_.pivot_offset = Vector2(260, 160)
		pc_.scale = Vector2(0.8, 0.8)
		pc_.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pc_, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pc_, "modulate:a", 1.0, 0.25)
	var score_line: Array = []
	for pp in m.players:
		score_line.append("%s %d" % [pp.name, m.scores[pp.id]])
	var reason := {"score": "점수 " + " · ".join(score_line), "last": "마지막 생존", "limit": "최대 %d바퀴 도달 · 남은 퍽이 가장 많은 사람이 승리" % m.max_rounds, "draw": "한 발에 모두 떨어졌습니다"}
	box.add_child(_label(reason.get(m.end_reason, ""), 15, SUB))
	# 순위: 남은 퍽 많은 순, 그다음 늦게 탈락한 순
	var rank: Array = []
	for p in m.players:
		if not p.out:
			rank.append(p.id)
	if m.mode == "derby":
		rank.sort_custom(func(a, b): return m.scores[a] > m.scores[b])
	else:
		rank.sort_custom(func(a, b): return m.stones_left(a) > m.stones_left(b))
	var outs: Array = m.out_order.duplicate()
	outs.reverse()
	rank.append_array(outs)
	var i := 1
	for pid in rank:
		var p: Dictionary = m.players[pid]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		r.add_child(_nw(_label("%d" % i, 16, SUB, 1)))
		r.add_child(_icon_pic(p.color, pid, 22))
		var nm := _label(p.name, 17, Color(TEXT, 1.0 if not p.out else 0.6), 1)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nm)
		var right_txt: String = ("%d점" % m.scores[pid]) if m.mode == "derby" else (("퍽 %d개" % m.stones_left(pid)) if not p.out else "%d바퀴 탈락" % p.out_round)
		r.add_child(_nw(_label(right_txt, 15, SUB)))
		box.add_child(r)
		i += 1
	box.add_child(_label("%d바퀴 · %d발" % [m.round_no, m.shots], 13, SUB))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if online == "guest":
		box.add_child(_label("호스트가 다음 판을 고르고 있어요.", 15, HINT_GOLD))
		var leave := _button("방 나가기", func(): _leave_online())
		leave.custom_minimum_size = Vector2(140, 52)
		row.add_child(leave)
		box.add_child(row)
		return
	var again := _primary(_button("바로 재대결", func(): _start_match()))
	again.custom_minimum_size = Vector2(200, 52)
	again.add_theme_font_size_override("font_size", 19)
	row.add_child(again)
	var back := _button("다시 고르기", func(): _back_to_lobby())
	back.custom_minimum_size = Vector2(140, 52)
	row.add_child(back)
	box.add_child(row)


# ── 친구 초대 (온라인) ───────────────────────────────────
## 물리는 같은 입력이면 같은 결과가 나오므로, 기기끼리는 행동(발사·장착·유품·건너뛰기)만 주고받는다.
## 호스트가 모든 행동에 순번을 매겨 뿌리고, 모든 기기는 그 순서대로 같은 판에 적용한다.
## CPU는 호스트만 계산한다. 연결은 PeerJS 공개 시그널 서버로 호스트-친구를 직접 잇는다 (web/alkkagi_net.js).

func _is_mine(pid: int) -> bool:
	if m.players[pid].cpu:
		return false
	return my_seats.has(pid)


func _drives_cpu() -> bool:
	return online != "guest"


func _seat_word(pid: int) -> String:
	if m.players[pid].cpu:
		return "CPU"
	if online == "":
		return "사람"
	return "나" if my_seats.has(pid) else "친구"


## 행동 하나. 혼자 둘 때는 바로 적용, 온라인이면 호스트가 순번을 매겨 모두에게 보낸다.
func _act(a: Dictionary) -> void:
	if online == "":
		_apply_action(a)
		return
	a = JSON.parse_string(JSON.stringify(a))  # 모든 기기가 똑같은 숫자를 쓰게 한 번 직렬화
	if online == "guest":
		if str(a.get("k", "")) != "equip" and str(a.get("k", "")) != "place":
			waiting_req = true
		net.send_to(host_peer, {"t": "req", "a": a})
		return
	if str(a.get("k", "")) == "equip":
		pending_picks[int(a["pid"])] = a
		return
	_host_seq(a)


func _host_seq(a: Dictionary) -> void:
	net_seq_out += 1
	var msg := {"t": "act", "seq": net_seq_out, "a": a}
	net.broadcast(msg)
	net_queue.append(msg)


func _can_apply(a: Dictionary) -> bool:
	if m == null or turn_hold > 0.0:
		return false
	var pid := int(a.get("pid", -1))
	match str(a.get("k", "")):
		"equip":
			return m.phase == "draft" and m.current_drafter() == pid
		"place":
			return m.phase == "place" and not m.placements.has(pid)
		_:
			return m.phase == "aim" and m.current_player() == pid


func _apply_queue() -> void:
	if online == "":
		return
	# 호스트: 미리 고른 장착은 그 자리 차례가 오면 순번을 매긴다
	if online == "host" and m != null and m.phase == "draft":
		var cur := m.current_drafter()
		if pending_picks.has(cur):
			var pick: Dictionary = pending_picks[cur]
			pending_picks.erase(cur)
			_host_seq(pick)
	net_queue.sort_custom(func(x, y): return int(x["seq"]) < int(y["seq"]))
	while not net_queue.is_empty():
		var msg: Dictionary = net_queue[0]
		var seq := int(msg["seq"])
		if seq <= net_applied:
			net_queue.pop_front()
			continue
		if seq != net_applied + 1 or not _can_apply(msg["a"]):
			break
		net_queue.pop_front()
		net_applied = seq
		waiting_req = false
		_apply_action(msg["a"])


func _apply_action(a: Dictionary) -> void:
	var pid := int(a.get("pid", -1))
	match str(a.get("k", "")):
		"shot":
			var dir := Vector2(float(a["dir"][0]), float(a["dir"][1]))
			var power := float(a["power"])
			snd.play("flick_release", lerpf(-8.0, 0.0, power))
			cpu_aim = {}
			m.shoot(int(a["stone"]), dir, power, {"charged": bool(a.get("charged", false)), "from_cloud": bool(a.get("from_cloud", false))})
		"equip":
			_do_equip(pid, str(a["part"]), int(a["stone"]), int(a.get("side", 1)), str(a.get("reserve", "")))
		"relic":
			_do_equip_relic(pid, int(a["stone"]))
		"place":
			var pts: Array = []
			for q in a["pos"]:
				pts.append(Vector2(float(q[0]), float(q[1])))
			if m.place(pid, pts):
				place_sent.erase(pid)
				if m.phase != "place":
					_on_placed()
		"skip":
			_log("%s 시간 초과, 차례를 넘겨요" % m.players[pid].name, m.players[pid].color)
			_banner("시간 초과")
			m.skip_turn()


func _net_poll() -> void:
	var st: String = net.status()
	if st != _net_status_seen:
		_net_status_seen = st
		if state == "setup":
			_show_setup()
	for item in net.poll():
		var from: String = str(item.get("from", ""))
		var d = item.get("data", {})
		if not (d is Dictionary):
			continue
		if online == "host":
			_host_msg(from, d)
		elif online == "guest":
			_guest_msg(from, d)


# 호스트 ─────────────────────────────────────────────────

func _start_hosting() -> void:
	if not net.available:
		_banner("친구 초대는 웹 버전에서만 돼요")
		return
	online = "host"
	friend_peer.clear()
	net.host()
	# 사람 자리 말고 하나는 친구 자리로 준비해 둔다
	var has_friend := false
	for i in settings["n"]:
		has_friend = has_friend or settings["friend"][i]
	if not has_friend:
		for i in range(1, settings["n"]):
			if settings["cpu"][i]:
				settings["cpu"][i] = false
				settings["friend"][i] = true
				break
	_show_setup()


func _host_msg(from: String, d: Dictionary) -> void:
	match str(d.get("t", "")):
		"_joined", "hello":
			if _seat_of_peer(from) < 0:
				_host_assign(from)
		"req":
			var a: Dictionary = d.get("a", {})
			var seat := _seat_of_peer(from)
			if state == "play" and seat >= 0 and int(a.get("pid", -1)) == seat:
				if str(a.get("k", "")) == "equip":
					pending_picks[seat] = a
				else:
					_host_seq(a)
		"_left":
			var seat2 := _seat_of_peer(from)
			if seat2 < 0:
				return
			friend_peer.erase(seat2)
			if state == "play" or state == "result":
				m.players[seat2].cpu = true
				net.broadcast({"t": "cpu", "seat": seat2})
				_log("%s 연결이 끊겨 CPU가 대신 둬요" % m.players[seat2].name, m.players[seat2].color)
			else:
				_host_broadcast_lobby()
				_show_setup()


func _seat_of_peer(peer: String) -> int:
	for seat in friend_peer:
		if friend_peer[seat] == peer:
			return seat
	return -1


func _host_assign(peer: String) -> void:
	if state != "setup":
		net.send_to(peer, {"t": "full", "why": "이미 경기 중이에요"})
		return
	var seat := -1
	for i in settings["n"]:
		if settings["friend"][i] and not friend_peer.has(i):
			seat = i
			break
	if seat < 0:
		for i in range(1, settings["n"]):
			if settings["cpu"][i]:
				settings["cpu"][i] = false
				settings["friend"][i] = true
				seat = i
				break
	if seat < 0:
		net.send_to(peer, {"t": "full", "why": "빈 자리가 없어요"})
		return
	friend_peer[seat] = peer
	snd.play("part_equip", -4.0)
	_host_broadcast_lobby()
	_show_setup()


func _lobby_state() -> Dictionary:
	var kinds: Array = []
	for i in settings["n"]:
		if settings["friend"][i]:
			kinds.append("friend" if friend_peer.has(i) else "wait")
		elif settings["cpu"][i]:
			kinds.append("cpu")
		else:
			kinds.append("host")
	return {"t": "lobby", "n": settings["n"], "kinds": kinds, "timed": settings["timed"], "speed": settings["speed"],
		"workshop": settings.get("workshop", "junk"), "mode": settings.get("mode", "survival"), "map": map_id}


func _host_broadcast_lobby() -> void:
	if online != "host":
		return
	for seat in friend_peer:
		var msg := _lobby_state()
		msg["seat"] = seat
		net.send_to(friend_peer[seat], msg)


func _host_start() -> void:
	# 아직 안 들어온 친구 자리는 CPU가 맡는다
	for i in settings["n"]:
		if settings["friend"][i] and not friend_peer.has(i):
			settings["friend"][i] = false
			settings["cpu"][i] = true
	var cpu: Array = []
	var owners := {}
	my_seats = []
	for i in settings["n"]:
		cpu.append(settings["cpu"][i])
		if friend_peer.has(i):
			owners[str(i)] = friend_peer[i]
		elif not settings["cpu"][i]:
			my_seats.append(i)
	var seed_value := randi()
	net.broadcast({"t": "start", "seed": seed_value, "n": settings["n"], "cpu": cpu, "timed": settings["timed"],
		"workshop": settings.get("workshop", "junk"), "mode": settings.get("mode", "survival"),
		"speed": settings["speed"], "owners": owners, "map": map_id})
	_start_match(seed_value)


func _back_to_lobby() -> void:
	if online == "host":
		net.broadcast({"t": "tosetup"})
		for i in settings["n"]:
			if friend_peer.has(i):
				settings["friend"][i] = true
				settings["cpu"][i] = false
		_show_setup()
		_host_broadcast_lobby()
		return
	_show_setup()


func _invite_row() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	if online != "host":
		var b := _button("친구 초대 링크 만들기", func(): _start_hosting())
		b.custom_minimum_size = Vector2(0, 40)
		v.add_child(b)
		return v
	var st: String = net.status()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var lbl := _nw(_label("친구 초대", 14, LABEL, 1))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lbl)
	head.add_child(_nw(_label("친구 %d명 접속" % friend_peer.size(), 13, SUB)))
	head.add_child(_button("초대 닫기", func(): _leave_online()))
	v.add_child(head)
	if st == "hosting":
		var url: String = net.invite_url(net.code())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var link := LineEdit.new()
		link.text = url
		link.editable = false
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(link)
		row.add_child(_button("링크 복사", func():
			net.copy(url)
			_banner("링크를 복사했어요")))
		v.add_child(row)
		v.add_child(_label("자리를 누르면 사람 → CPU → 친구 순으로 바뀝니다. 링크로 들어온 친구가 친구 자리에 앉아요.", 12, SUB))
	elif st == "error":
		v.add_child(_label("연결 오류: " + net.error_text(), 13, Art.RED))
	else:
		v.add_child(_label("초대 링크를 만드는 중…", 13, SUB))
	return v


func _leave_online() -> void:
	net.close()
	online = ""
	friend_peer.clear()
	host_peer = ""
	my_seats = []
	for i in 8:
		settings["friend"][i] = false
	if state == "play" or state == "result":
		_show_setup()
		return
	_show_setup()


# 손님 ───────────────────────────────────────────────────

func _join_room(code: String) -> void:
	online = "guest"
	guest_lobby = {}
	net.join(code)
	_show_setup()


func _guest_msg(from: String, d: Dictionary) -> void:
	match str(d.get("t", "")):
		"_open":
			host_peer = from
			net.send_to(from, {"t": "hello"})
		"lobby":
			host_peer = from
			guest_lobby = d
			if str(d.get("map", map_id)) != map_id:
				_apply_map(str(d.get("map", map_id)), false)
			settings["n"] = int(d["n"])
			for i in 8:
				settings["cpu"][i] = i < d["kinds"].size() and d["kinds"][i] == "cpu"
			if state == "setup":
				_show_setup()
		"full":
			guest_lobby = {"full": str(d.get("why", "빈 자리가 없어요"))}
			if state == "setup":
				_show_setup()
		"start":
			settings["n"] = int(d["n"])
			settings["timed"] = bool(d["timed"])
			settings["speed"] = int(d["speed"])
			settings["workshop"] = str(d.get("workshop", "junk"))
			settings["mode"] = str(d.get("mode", "survival"))
			if str(d.get("map", map_id)) != map_id:
				_apply_map(str(d.get("map", map_id)), false)
			for i in 8:
				settings["cpu"][i] = i < d["cpu"].size() and bool(d["cpu"][i])
			my_seats = []
			var me: String = net.my_id()
			for k in d["owners"]:
				if str(d["owners"][k]) == me:
					my_seats.append(int(k))
			_start_match(int(d["seed"]))
		"act":
			if state == "play":
				net_queue.append(d)
		"cpu":
			if m != null:
				var seat := int(d["seat"])
				m.players[seat].cpu = true
				_log("%s 연결이 끊겨 CPU가 대신 둬요" % m.players[seat].name, m.players[seat].color)
		"tosetup":
			state = "setup"
			m = null
			_show_setup()
		"_left":
			_leave_online()
			_banner("호스트와 연결이 끊겼어요")


func _show_guest_lobby() -> void:
	state = "setup"
	m = null
	menu_btn.visible = false
	parts_btn.visible = false
	sound_btn.visible = false
	var root := _lobby_root()
	var vs := get_viewport_rect().size
	var narrow := vs.x < 900
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.custom_minimum_size = Vector2(540.0 if not narrow else vs.x - 32.0, 0)
	col.position = Vector2(72, maxf(40.0, (vs.y - 600.0) * 0.5)) if not narrow else Vector2(16, 24)
	root.add_child(col)
	lobby_col = col
	col.add_child(_label("개조 알까기", 44, TEXT, 2))
	var st: String = net.status()
	if guest_lobby.has("full"):
		col.add_child(_label("들어갈 수 없어요: " + guest_lobby["full"], 17, Art.RED, 1))
	elif st == "error":
		col.add_child(_label("연결하지 못했어요: " + net.error_text(), 17, Art.RED, 1))
	elif guest_lobby.is_empty():
		col.add_child(_label("친구 방에 연결하는 중…", 18, TEXT, 1))
	else:
		var seat := int(guest_lobby.get("seat", -1))
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 12)
		if seat >= 0:
			hr.add_child(_icon_pic(Match.COLORS[seat], seat, 36))
			hr.add_child(_nw(_label("내 자리: %s" % Match.NAMES[seat], 22, TEXT, 2)))
		col.add_child(hr)
		col.add_child(_label("호스트가 시작하길 기다리고 있어요. 친구 %d인전." % int(guest_lobby["n"]), 16, SUB))
		var ws_key: String = str(guest_lobby.get("workshop", "junk"))
		var ws_name: String = "무작위 공방" if ws_key == "random" else PartsData.WORKSHOPS.get(ws_key, PartsData.WORKSHOPS["junk"])["name"]
		col.add_child(_label("오늘의 공방: %s%s" % [ws_name, "  ·  개조 더비" if str(guest_lobby.get("mode", "")) == "derby" else ""], 15, HINT_GOLD, 1))
		col.add_child(_map_row(true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		var words := {"host": "호스트", "cpu": "CPU", "friend": "친구", "wait": "빈 자리"}
		for i in guest_lobby["kinds"].size():
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			h.add_child(_icon_pic(Match.COLORS[i], i, 22))
			var k: String = guest_lobby["kinds"][i]
			h.add_child(_nw(_label("%s · %s" % [Match.NAMES[i], "나" if i == seat else words.get(k, k)], 15, TEXT if i == seat else SUB, 1 if i == seat else 0)))
			grid.add_child(h)
		col.add_child(grid)
	var leave := _button("나가기", func(): _leave_online())
	leave.custom_minimum_size = Vector2(140, 46)
	col.add_child(leave)


# ── 오늘의 공방 ──────────────────────────────────────────

const WS_SHORT := {"junk": "정비소", "magic": "마법 상점", "toon": "만화 창고", "all": "전체", "random": "무작위"}


func _workshop_row() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	var lbl := _nw(_label("오늘의 공방", 16, TEXT, 1))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lbl)
	var cur: String = settings.get("workshop", "junk")
	var link := _button("무작위로 고르기 ✓" if cur == "random" else "무작위로 고르기", func(): _pick_workshop("random"))
	link.flat = true
	link.add_theme_font_override("font", font_semi)
	link.add_theme_font_size_override("font_size", 14)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		link.add_theme_color_override(c, POWER)
	link.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	link.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	link.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	head.add_child(link)
	v.add_child(head)
	var narrow_w := get_viewport_rect().size.x < 600.0
	var row: BoxContainer = VBoxContainer.new() if narrow_w else HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for key in ["junk", "magic", "toon"]:
		row.add_child(_workshop_card(key, cur == key))
	v.add_child(row)
	if cur == "random":
		v.add_child(_label("공방을 열 때 세 공방 중 하나가 정해집니다.", 13, SUB))
	elif cur == "all":
		v.add_child(_label("전체 부품 섞기: " + PartsData.WORKSHOPS["all"]["desc"] + " (설정에서 끌 수 있어요)", 13, SUB))
	return v


func _pick_workshop(k: String) -> void:
	snd.play("ui_toggle")
	settings["workshop"] = k
	if online == "host":
		_host_broadcast_lobby()
	if Themes.resolve(map_id, _cur_ws()) != theme_id:
		_apply_map(map_id, false)
	else:
		_show_setup()


## 공방 간판 카드: 간판 · 한 줄 소개 · 대표 부품 셋 · 세트 (디자인 「오늘의 공방」 시작 화면).
func _workshop_card(key: String, on: bool) -> Control:
	var info: Dictionary = PartsData.WORKSHOPS[key]
	var b := _button("", func(): _pick_workshop(key))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 214)
	b.clip_contents = true
	var nb := _sb(Color(FG, 0.05), ACCENT if on else Color(FG, 0.14), 12)
	nb.set_border_width_all(3 if on else 2)
	if on:
		nb.shadow_color = Color(ACCENT, 0.25)
		nb.shadow_size = 4
	b.add_theme_stylebox_override("normal", nb)
	var hb := nb.duplicate()
	hb.bg_color = Color(FG, 0.09)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", hb)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 간판
	var sign := PanelContainer.new()
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := StyleBoxFlat.new()
	ssb.set_corner_radius_all(8)
	ssb.content_margin_top = 6
	ssb.content_margin_bottom = 6
	var scol := Color.WHITE
	match key:
		"junk":
			ssb.bg_color = Color("1A1D20")
			ssb.border_color = Color("FFC23D")
			ssb.set_border_width_all(4)
			scol = Color("FFC23D")
		"magic":
			ssb.bg_color = Color("4A3A8E")
			ssb.border_color = Color("6A50B8")
			ssb.set_border_width_all(2)
			scol = Color("F1EEFF")
		"toon":
			ssb.bg_color = Color("FFFDF6")
			ssb.border_color = Color("111111")
			ssb.set_border_width_all(2)
			ssb.set_corner_radius_all(3)
			ssb.shadow_color = Color("111111")
			ssb.shadow_size = 1
			ssb.shadow_offset = Vector2(3, 3)
			scol = Color("111111")
	sign.add_theme_stylebox_override("panel", ssb)
	var sl := _nw(_label(info["name"], 18, scol, 3))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_child(sl)
	box.add_child(sign)
	var tag := _label(info.get("tag", ""), 12, SUB)
	tag.custom_minimum_size = Vector2(0, 34)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)
	# 대표 부품 셋
	var reps := HBoxContainer.new()
	reps.add_theme_constant_override("separation", 2)
	reps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pid in info["rep"]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var demo := {"weapon": "", "aux": "", "prop": ""}
		demo[PartsData.slot_of(pid)] = pid
		var pic := _puck_pic(demo, Art.NEUTRAL, -1, Vector2(0, 52), 0.5)
		cell.add_child(pic)
		var nm := _label(PartsData.part_name(pid), 10, SUB)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nm)
		reps.add_child(cell)
	box.add_child(reps)
	var set_id: String = info.get("set", "")
	var line := _nw(_label(("세트: " + PartsData.SETS[set_id]["name"]) if set_id != "" else "단품끼리 조합", 12, ACCENT if not th["dark"] or true else BRASS, 2))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	b.add_child(box)
	return b


## 공방 소개: 셔터가 내려와 있다가 1.3초 뒤 올라간다 (디자인 「오늘의 공방」).
var shutter: Control = null
var shutter_t := -1.0


func _show_workshop_intro() -> void:
	_clear_overlay()
	turn_hold = 1.6
	shutter_t = 0.0
	if shutter == null:
		shutter = Control.new()
		shutter.set_anchors_preset(Control.PRESET_FULL_RECT)
		shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shutter.draw.connect(_draw_shutter)
		_fade_rect.get_parent().add_child(shutter)
	shutter.visible = true
	snd.play("round_start", -2.0, 0.7)


func _update_shutter(delta: float) -> void:
	if shutter_t < 0.0 or shutter == null:
		return
	shutter_t += delta
	if shutter_t > 1.6:
		shutter_t = -1.0
		shutter.visible = false
	shutter.queue_redraw()


func _draw_shutter() -> void:
	var vs := shutter.size
	var k := 0.0
	if shutter_t > 0.95:
		var e := clampf((shutter_t - 0.95) / 0.6, 0.0, 1.0)
		k = e * e * e * (e * (6.0 * e - 15.0) + 10.0)
	var oy := -vs.y * 1.02 * k
	# 셔터 날: 18px 회색, 4px 홈, 18px 밝은 회색
	var y := 0.0
	while y < vs.y:
		shutter.draw_rect(Rect2(0, y + oy, vs.x, 18), Color("8E959C"))
		shutter.draw_rect(Rect2(0, y + 18 + oy, vs.x, 4), Color("6F767D"))
		shutter.draw_rect(Rect2(0, y + 22 + oy, vs.x, 18), Color("A1A8AE"))
		y += 40.0
	shutter.draw_rect(Rect2(0, vs.y - 10 + oy, vs.x, 10), Color("5A6068"))
	if m == null:
		return
	var info: Dictionary = PartsData.WORKSHOPS.get(m.workshop, PartsData.WORKSHOPS["junk"])
	var names: Array = []
	for pid in info["rep"]:
		names.append(PartsData.part_name(pid))
	var big := 48
	var nm: String = info["name"]
	var bw := maxf(font_display.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x, font.get_string_size(" · ".join(names), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x) + 68.0
	var excl: Array = m.match_parts.filter(func(x): return not PartsData.COMMON_PARTS.has(x)) if m.workshop != "all" else []
	bw = maxf(bw, excl.size() * 44.0 + 48.0)
	var box := Rect2(vs.x * 0.5 - bw * 0.5, vs.y * 0.5 - 66 + oy, bw, 132 + (74.0 if not excl.is_empty() else 0.0))
	shutter.draw_rect(Rect2(box.position + Vector2(0, 10), box.size), Color(0, 0, 0, 0.25))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1A1D20")
	sb.border_color = Color("FFC23D")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.draw(shutter.get_canvas_item(), box)
	var sub := "오늘의 공방" + ("  ·  개조 더비" if m.mode == "derby" else "")
	shutter.draw_string(font_bold, Vector2(box.position.x, box.position.y + 32), sub, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 14, Color("FFC23D"))
	shutter.draw_string(font_display, Vector2(box.position.x, box.position.y + 86), nm, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, big, Color("F2F4F1"))
	shutter.draw_string(font, Vector2(box.position.x, box.position.y + 114), " · ".join(names), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, Color("C9CED6"))
	if not m.world.gimmicks.is_empty():
		var gn: Array = []
		for g in m.world.gimmicks:
			gn.append(World.Gm.name_of(g["kind"]))
		var gy := box.end.y + 30.0
		var gt := "맵 기믹 · " + " · ".join(gn)
		var gw := font_bold.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 40.0
		var gr := Rect2(vs.x * 0.5 - gw * 0.5, gy, gw, 38)
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color("FFC23D")
		sb2.set_corner_radius_all(19)
		sb2.draw(shutter.get_canvas_item(), gr)
		shutter.draw_string(font_bold, Vector2(gr.position.x, gr.position.y + 25), gt, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 16, Color("1A1A1A"))
	# 이번 판의 전용 부품 (작은 아이콘 줄)
	if not excl.is_empty():
		shutter.draw_string(font_semi, Vector2(box.position.x, box.position.y + 140), "이번 판의 전용 부품", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 12, Color("FFC23D"))
		var x0 := box.get_center().x - (excl.size() - 1) * 22.0
		for i in excl.size():
			var demo := {"weapon": "", "aux": "", "prop": ""}
			demo[PartsData.slot_of(excl[i])] = excl[i]
			shutter.draw_set_transform(Vector2(x0 + i * 44.0, box.position.y + 170), -PI / 2.0, Vector2.ONE * 0.45)
			Art.draw(shutter, demo, 1, Art.NEUTRAL, 1.0, -1)
			shutter.draw_set_transform_matrix(Transform2D.IDENTITY)


# ── 개조 카드의 움직임 화살표 ────────────────────────────

const MOTION := {"pea": "fwd", "shotgun": "fan", "claw": "grab", "nose": "push", "magnet": "pull", "bumper": "side",
	"flipper": "side", "rocket": "fwd2", "retro": "back", "chute": "stop", "hook": "pull", "sucker": "stop",
	"brake": "stop", "mine": "ring", "trex_head": "grab", "trex_arm": "pull", "trex_leg": "stop",
	"moon_staff": "fwd", "star_cloak": "turn", "moon_boots": "jump", "shadow_scale": "side", "night_charm": "back",
	"anchor": "back", "drift_tire": "turn", "flash_step": "jump", "log_sub": "side", "trap_card": "back",
	"rubber_fist": "fwd2", "charge_palm": "fwd2", "reel": "back", "crab": "side", "side_scroll": "turn",
	"glass_wings": "turn", "clockwork": "fwd2", "umbrella_gun": "fan", "echo_bell": "ring", "tambourine": "ring",
	"awaken_shoes": "fwd2", "torn_cape": "stop", "hero_band": "fan", "second_step": "back", "carousel": "turn"}


func _motion_of(part: String) -> String:
	if MOTION.has(part):
		return MOTION[part]
	return {"weapon": "fwd", "aux": "ring", "prop": "fwd2"}.get(PartsData.slot_of(part), "fwd")


func _arrow_tip(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	ci.draw_line(a, b, col, 2.0, true)
	var d := (b - a).normalized()
	ci.draw_colored_polygon(PackedVector2Array([b + d * 3, b - d * 3 + d.orthogonal() * 3.5, b - d * 3 - d.orthogonal() * 3.5]), col)


## 작은 화살표: 오른쪽이 정면. 퍽(점)에서 어떤 움직임이 나오는지.
func _draw_motion(ci: CanvasItem, kind: String, puck_col := Color(0, 0, 0, 0)) -> void:
	var c := Vector2(10, 9)
	var col := POWER if puck_col.a == 0.0 else BRASS
	if puck_col.a > 0.0:
		ci.draw_circle(c, 5.2, Art.outline)
		ci.draw_circle(c, 4.4, puck_col)
	else:
		ci.draw_circle(c, 4.5, Color(Art.NEUTRAL))
	match kind:
		"fwd":
			_arrow_tip(ci, c + Vector2(7, 0), c + Vector2(26, 0), col)
		"fwd2":
			_arrow_tip(ci, c + Vector2(7, 0), c + Vector2(28, 0), col)
			ci.draw_line(c + Vector2(12, -4), c + Vector2(18, -4), col, 1.5)
			ci.draw_line(c + Vector2(12, 4), c + Vector2(18, 4), col, 1.5)
		"back":
			_arrow_tip(ci, c + Vector2(26, 0), c + Vector2(9, 0), col)
		"fan":
			for a in [-0.4, 0.0, 0.4]:
				_arrow_tip(ci, c + Vector2.from_angle(a) * 7, c + Vector2.from_angle(a) * 24, col)
		"pull":
			_arrow_tip(ci, c + Vector2(28, 0), c + Vector2(9, 0), col)
		"push":
			ci.draw_circle(c + Vector2(14, 0), 4.0, Color(Art.STEEL))
			_arrow_tip(ci, c + Vector2(19, 0), c + Vector2(29, 0), col)
		"grab":
			ci.draw_circle(c + Vector2(13, 0), 4.0, Color(Art.STEEL))
			ci.draw_arc(c + Vector2(13, 0), 6.5, -1.2, 1.2, 8, col, 2.0, true)
			_arrow_tip(ci, c + Vector2(21, 0), c + Vector2(29, 0), col)
		"side":
			_arrow_tip(ci, c + Vector2(4, 0), c + Vector2(4, -8), col)
			_arrow_tip(ci, c + Vector2(4, 0), c + Vector2(4, 8), col)
		"stop":
			ci.draw_line(c + Vector2(7, 0), c + Vector2(20, 0), col, 2.0)
			ci.draw_line(c + Vector2(22, -6), c + Vector2(22, 6), col, 3.0)
		"jump":
			var pts := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				pts.append(c + Vector2(6 + 22 * t, -9 * sin(PI * t)))
			ci.draw_polyline(pts, col, 2.0, true)
			ci.draw_circle(c + Vector2(28, 0), 2.5, col)
		"turn":
			ci.draw_line(c + Vector2(7, 0), c + Vector2(20, 0), col, 2.0)
			_arrow_tip(ci, c + Vector2(20, 0), c + Vector2(20, 8), col)
		"ring":
			for r in [7.0, 11.0]:
				ci.draw_arc(c, r, -1.0, 1.0, 10, col, 1.5, true)


# ── 탈락 원인 ────────────────────────────────────────────

func _part_word(part: String) -> String:
	if part.begins_with("gm_"):
		return World.Gm.name_of(part.substr(3))
	if part == "body":
		return "몸통 충돌"
	if part == "mecha":
		return "물고 던지기"
	if part == "moon_set":
		return "궤도 마법"
	return PartsData.part_name(part) if PartsData.CATALOG.has(part) else part


## 낙하 지점에 띄울 글: "보라 · 콩알총", "초록 · 몸통 충돌", "보라 · 콩알총 → 연쇄 충돌"
func _cause_text(c: Dictionary, victim_owner: int) -> String:
	if not c.has("owner"):
		return "판 밖으로"
	var att: String = m.players[int(c["owner"])].name
	if int(c["owner"]) == victim_owner:
		att = "스스로"
	if str(c["part"]).begins_with("gm_"):
		return "%s · %s의 샷" % [_part_word(str(c["part"])), m.players[int(c["owner"])].name]
	var t := "%s · %s" % [att, _part_word(str(c["part"]))]
	if c.get("chain", false) and str(c["part"]) != "body":
		t += " → 연쇄 충돌"
	elif c.get("chain", false):
		t = "%s · 연쇄 충돌" % att
	return t


func _has_cpu() -> bool:
	for p in m.players:
		if p.cpu and not p.out:
			return true
	return false


func _mode_row() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := _nw(_label("모드", 14, LABEL, 1))
	lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(lbl)
	var cur: String = settings.get("mode", "survival")
	for key in ["survival", "derby"]:
		var on: bool = cur == key
		var k: String = key
		var b := _button("최후 생존전" if key == "survival" else "개조 더비", func():
			snd.play("ui_toggle")
			settings["mode"] = k
			if online == "host":
				_host_broadcast_lobby()
			_show_setup())
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", _sb(BRASS if on else Color(FG, 0.05), Color(FG, 0.1), 8))
		b.add_theme_stylebox_override("hover", _sb(BRASS.lightened(0.1) if on else Color(FG, 0.1), Color(FG, 0.14), 8))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, INK if on else TEXT)
		row.add_child(b)
	v.add_child(row)
	if cur == "derby":
		v.add_child(_label("정해진 %d바퀴 동안 모두 계속 둡니다. 떨어진 퍽은 다음 바퀴에 부품을 단 채 돌아오고, 상대 퍽을 떨어뜨리면 1점." % (Match.DERBY_ROUNDS_SMALL if settings["n"] <= 4 else Match.DERBY_ROUNDS_BIG), 12, SUB))
	return v


# ── 맵 테마 ──────────────────────────────────────────────

func _cur_ws() -> String:
	if m != null:
		return m.workshop
	var w: String = settings.get("workshop", "junk")
	return "junk" if w == "random" else w


func _set_theme_colors() -> void:
	theme_id = Themes.resolve(map_id, _cur_ws())
	th = Themes.get_theme(theme_id)
	ACCENT = th.get("accent", BRASS)
	ACCENT_INK = th.get("accent_ink", INK)
	var dark: bool = th["dark"]
	BG_OUT = th["bg"]
	TEXT = th["text"]
	SUB = th["sub"]
	LABEL = TEXT.lerp(SUB, 0.35)
	MUTED = SUB.lerp(th["bg"], 0.35)
	PANEL_BG = th["panel"]
	PANEL_LINE = th["line"]
	WARN = th["gauge"]
	POWER = th["gold"]
	HINT_GOLD = th["gold"]
	FG = Color.WHITE if dark else th["text"]
	SOLID = Color(th["panel"], 1.0)
	PAGE_FELT = th["bg"]
	Art.outline = th["outline"]
	Art.shadow = th["shadow"]


## 맵을 바꾼다: 색을 다시 읽고, 버튼 테마와 열려 있는 화면을 새로 만든다. 경기는 멈추지 않는다.
## 공방이 바뀌었을 때: 「공방 따라가기」면 경기장을 다시 고른다.
func _refresh_theme() -> void:
	if Themes.resolve(map_id, _cur_ws()) != theme_id:
		_apply_map(map_id, false)


func _apply_map(id: String, save := true) -> void:
	if not Themes.THEMES.has(id) and id != "auto":
		return
	_fade_rect.color = Color(BG_OUT, 1.0)
	_theme_fade = 0.25
	map_id = id
	_set_theme_colors()
	theme_ = _make_theme()
	for b in [menu_btn, parts_btn, sound_btn, ff_btn]:
		b.theme = theme_
		_style_icon_btn(b, b == ff_btn and fast_forward)
	_panel_sb.bg_color = PANEL_BG
	_panel_sb.border_color = PANEL_LINE
	if save:
		_save_view()
	if overlay != null and overlay.has_meta("settings"):
		_show_settings(state == "setup")
	elif state == "setup":
		_show_setup()
	elif overlay != null:
		overlay.theme = theme_


func _save_view() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("view", "map", map_id)
	for k in view_opts:
		cfg.set_value("view", k, view_opts[k])
	cfg.save("user://settings.cfg")


# ── 퍽 그리기와 모션 ─────────────────────────────────────
var vis := {}                 # 알 id → {sq_dir, sq, pop_t, equip_t, equip_part, vf, trail}
var shake_off := Vector2.ZERO
var hud_pop := {}
var last_shot := {}            # 플레이어 → 마지막으로 쏜 퍽 (부품 패널 기본)             # 플레이어 → 남은 퍽 점이 사라지기 시작한 시각
var _trail_t := 0.0
var shake := 0.0
var hitstop := 0.0
var win_t := -1.0


## 퍽 한 개: 그림자(제자리) → 부품(정면 방향으로 회전) → 몸통(화면 공간, 각인은 똑바로).
## 눌림·튐·떠오름은 여기서 한 번에 얹는다.
func _draw_puck_at(p: Vector2, sid: int, parts: Dictionary, mside: int, col: Color, symbol: int, facing: float, alpha: float, extra := {}) -> void:
	var u := World.STONE_R * view_scale
	var st: Dictionary = vis.get(sid, {})
	var scl: float = extra.get("scale", 1.0)
	var sq: float = extra.get("sq", 0.0)
	var sq_dir: Vector2 = extra.get("sq_dir", Vector2.RIGHT)
	var lift: float = extra.get("lift", 0.0)
	if not _reduced():
		if st.get("sq", 0.0) > 0.002 and sq == 0.0:
			sq = st["sq"]
			sq_dir = st["sq_dir"]
		var pt: float = time - float(st.get("pop_t", -9.0))
		if pt >= 0.0 and pt < 0.17:
			var k := pt / 0.17
			scl *= 1.0 + 0.14 * sin(PI * k)
			sq = -0.22 * (1.0 - k)
			sq_dir = st.get("sq_dir", Vector2.RIGHT)
		# 조준 당기기: 당기는 쪽으로 눌림
		if drag_stone == sid and extra.is_empty():
			var aim := _aim_of(sid, drag_screen)
			if not aim.is_empty() and not aim.has("cancel"):
				sq = 0.12 * float(aim.get("power", 0.0))
				sq_dir = -aim["dir"]
		var dt0: float = time - float(st.get("drop_t", -9.0))
		if dt0 >= 0.0 and dt0 < 0.32:
			var kd := dt0 / 0.32
			scl *= 1.0 + 0.35 * (1.0 - kd * kd)
			lift += 0.9 * u * (1.0 - kd * kd)
		var et: float = time - float(st.get("equip_t", -9.0))
		if et >= 0.285 and et < 0.45:
			lift += 0.25 * u * sin(PI * (et - 0.285) / 0.165)
	if win_t >= 0.0 and m != null and m.winners.has(symbol) and sid >= 0:
		var wt := clampf((time - win_t) / 0.6, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - wt, 3.0)
		lift += 0.5 * u * e
		scl *= 1.0 + 0.25 * e
	var q := Transform2D.IDENTITY.scaled(Vector2.ONE * scl)
	if absf(sq) > 0.001:
		var d := sq_dir.normalized()
		var pp := d.orthogonal()
		var a1 := 1.0 - sq
		var a2 := 1.0 + sq * 0.5
		var bx := Vector2(d.x * d.x * a1 + pp.x * pp.x * a2, d.y * d.x * a1 + pp.y * pp.x * a2)
		var by := Vector2(d.x * d.y * a1 + pp.x * pp.y * a2, d.y * d.y * a1 + pp.y * pp.y * a2)
		q = Transform2D(bx * scl, by * scl, Vector2.ZERO)
	Art.draw_puck_shadow(self, p, u * scl, alpha)
	var pc := p + Vector2(0, -lift)
	var base := Transform2D(q.x, q.y, pc)
	draw_set_transform_matrix(base * Transform2D(facing, Vector2.ONE * view_scale, 0.0, Vector2.ZERO))
	Art.skip_body = true
	Art.draw(self, parts, mside, col, alpha, symbol)
	Art.skip_body = false
	draw_set_transform_matrix(base)
	if not Art.is_set_form(parts):
		if not Art.mono and symbol >= 0 and symbol < 8 and puck_vp != null:
			# 미리 구워 둔 퍽 몸통 + 정면 홈만 따로
			var tile := float(PUCK_TILE)
			var sz := tile * u / PUCK_U
			draw_texture_rect_region(puck_vp.get_texture(), Rect2(-Vector2.ONE * sz * 0.5, Vector2.ONE * sz), Rect2(tile * symbol, 0, tile, tile), Color(1, 1, 1, alpha))
			Art.draw_notch(self, Vector2.ZERO, u, facing, alpha)
		else:
			Art.draw_puck_top(self, Vector2.ZERO, u, col, symbol, facing, alpha)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# 부품 장착: 슬롯 바깥 1.6u 에서 미끄러져 들어온다 (0.38초, 살짝 넘쳤다 돌아옴)
	if not _reduced():
		var et2: float = time - float(st.get("equip_t", -9.0))
		if et2 >= 0.0 and et2 < 0.38 and st.has("equip_part"):
			var k2 := et2 / 0.38
			var back := 1.0 - _ease_back(k2)
			var slot_ang: float = {"weapon": 0.0, "aux": PI / 2.0, "prop": PI}.get(PartsData.slot_of(st["equip_part"]), 0.0)
			var off := Vector2.from_angle(facing + slot_ang) * 1.6 * u * back
			draw_set_transform_matrix(Transform2D(facing, Vector2.ONE * view_scale, 0.0, pc + off))
			var only := {"weapon": "", "aux": "", "prop": ""}
			only[PartsData.slot_of(st["equip_part"])] = st["equip_part"]
			Art.skip_body = true
			Art.draw(self, only, mside, col, alpha * (1.0 - k2 * 0.3), symbol)
			Art.skip_body = false
			draw_set_transform_matrix(Transform2D.IDENTITY)


func _ease_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


func _reduced() -> bool:
	return bool(view_opts.get("reduce_motion", false))


## 충돌: 히트스톱·흔들림·눌림·불꽃·소리가 충격 세기 J(칸/초)에 비례한다.
func _on_hit(e: Dictionary) -> void:
	var J: float = float(e["strength"]) / (CELL * Parts.TIME_K)
	snd.play("puck_hit_heavy" if J >= 4.0 else "puck_hit_light", lerpf(-16.0, 0.0, clampf(J / 10.0, 0.0, 1.0)), randf_range(0.92, 1.08))
	if J > 2.0 and view_opts["hitstop"] and not _reduced():
		hitstop = maxf(hitstop, minf(0.09, 0.02 + 0.008 * J))
	if view_opts["shake"] and not _reduced():
		shake = maxf(shake, minf(6.0, 0.55 * J))
	if not _reduced() and e.has("n"):
		var amt := minf(0.32, 0.035 * J)
		for id in [e["a"], e["b"]]:
			var vv: Dictionary = vis.get(id, {})
			if amt > float(vv.get("sq", 0.0)):
				vv["sq"] = amt
				vv["sq_dir"] = e["n"]
			vis[id] = vv
	var nrm: Vector2 = e.get("n", Vector2.RIGHT)
	var cnt := mini(18, int(4.0 + 1.4 * J))
	for i in cnt:
		var side := 1.0 if i % 2 == 0 else -1.0
		var dirv := nrm.orthogonal().rotated(randf_range(-0.5, 0.5)) * side
		fx.append({"k": "spark", "pos": e["pos"], "vel": dirv * randf_range(60.0, 140.0 + 12.0 * J), "t": 0.0,
			"life": randf_range(0.25, 0.5), "c": th["spark"]})


## 움직이는 동안: 정면이 진행 방향을 따라가고, 잔상과 위험 구역 깜빡임을 남긴다.
func _motion_tick(delta: float) -> void:
	var w := m.world
	for st in w.stones:
		if not st.alive:
			continue
		var vv: Dictionary = vis.get(st.id, {})
		var sp: float = st.vel.length()
		var cur: float = vv.get("vf", st.facing)
		if sp > 1.0:
			vv["vf"] = lerp_angle(cur, st.vel.angle(), minf(1.0, 3.0 * delta))
		else:
			vv["vf"] = lerp_angle(cur, st.facing, minf(1.0, 10.0 * delta))
		if sp >= 2.5 * CELL * Parts.TIME_K and not _reduced():
			vv["trail"] = float(vv.get("trail", 0.0)) + delta
			if vv["trail"] >= 0.035:
				vv["trail"] = 0.0
				fx.append({"k": "ghost", "pos": st.pos, "t": 0.0, "life": 0.22, "c": m.players[st.owner].color})
		if sp > 1.0 and w.edge_distance(st.pos) < World.EDGE_ZONE:
			var last: float = vv.get("danger_t", -9.0)
			if time - last > 0.12:
				vv["danger_t"] = time
				fx.append({"k": "danger", "ang": st.pos.angle(), "pos": st.pos, "t": 0.0, "life": 0.3, "c": th["danger"]})
		vis[st.id] = vv


func _decay_motion(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - 30.0 * delta)
		shake_off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	else:
		shake_off = Vector2.ZERO
	var k := pow(0.0008, delta)
	for id in vis:
		var vv: Dictionary = vis[id]
		if vv.get("sq", 0.0) > 0.0:
			vv["sq"] = float(vv["sq"]) * k


# ── 차례 배너 · 승리 색종이 ───────────────────────────────

## 「○○ 차례」: 왼쪽에서 들어와 가운데 머물다 오른쪽으로 빠진다 (1.05초, -8도 기울임).
func _draw_banner(vs: Vector2) -> void:
	var total := 0.85 if not _reduced() else 0.6
	var k := 1.0 - banner_t / total
	var y := view_center.y - 40.0 if not portrait else 160.0
	var x := view_center.x
	var a := 1.0
	if not _reduced():
		# 판 안에서만 미끄러진다 (옆 패널 위로 지나가지 않게)
		var span := 160.0
		if k < 0.22:
			var e := 1.0 - pow(1.0 - k / 0.22, 3.0)
			x = lerpf(view_center.x - span, view_center.x, e)
			a = e
		elif k > 0.78:
			var e2 := pow((k - 0.78) / 0.22, 2.0)
			x = lerpf(view_center.x, view_center.x + span, e2)
			a = 1.0 - e2
	else:
		a = clampf(banner_t / 0.3, 0.0, 1.0)
	var fsz := 56 if banner_sub != "" or banner.length() <= 8 else 40
	if portrait:
		fsz = int(fsz * 0.7)
	var w := font_display.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 64.0
	draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, deg_to_rad(-8.0), Vector2(x, y)))
	# 큰 글자 + 그림자 (디자인: 굵은 제목체, 아래로 3px 그림자)
	draw_string(font_display, Vector2(-w * 0.5, 3 + 3), banner, HORIZONTAL_ALIGNMENT_CENTER, w, fsz, Color(0, 0, 0, 0.35 * a))
	draw_string_outline(font_display, Vector2(-w * 0.5, 3), banner, HORIZONTAL_ALIGNMENT_CENTER, w, fsz, 6, Color(th["outline"], 0.8 * a))
	draw_string(font_display, Vector2(-w * 0.5, 3), banner, HORIZONTAL_ALIGNMENT_CENTER, w, fsz, Color(_banner_col, a))
	if banner_sub != "":
		var sw := w + 200.0
		draw_string(font_bold, Vector2(-sw * 0.5, 3 + 34 + 2), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, sw, 16, Color(0, 0, 0, 0.4 * a))
		draw_string(font_bold, Vector2(-sw * 0.5, 3 + 34), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, sw, 16, Color(1, 1, 1, a))
	draw_set_transform_matrix(Transform2D.IDENTITY)


var confetti: Array = []


func _spawn_confetti() -> void:
	if _reduced():
		return
	var vs := get_viewport_rect().size
	var wc: Color = m.players[m.winners[0]].color
	for i in 120:
		var c: Color = wc if randf() < 0.6 else th["spark"]
		confetti.append({"p": Vector2(randf() * vs.x, -20.0 - randf() * vs.y * 0.6), "v": Vector2(randf_range(-60, 60), randf_range(80, 220)),
			"rot": randf() * TAU, "spin": randf_range(-6, 6), "c": c, "s": randf_range(5, 10)})


func _draw_confetti() -> void:
	if confetti.is_empty():
		return
	var dt := get_process_delta_time()
	var age := time - win_t
	var alive: Array = []
	for c in confetti:
		c["v"].y += 160.0 * dt
		c["v"].x += sin(time * 3.0 + c["rot"]) * 20.0 * dt
		c["p"] += c["v"] * dt
		c["rot"] += c["spin"] * dt
		var a := clampf((3.0 - age) / 0.6, 0.0, 1.0)
		if a <= 0.0:
			continue
		draw_set_transform(c["p"], c["rot"], Vector2(1.0, 0.55 + 0.45 * absf(sin(c["rot"] * 2.0))))
		draw_rect(Rect2(Vector2(-c["s"] * 0.5, -c["s"] * 0.3), Vector2(c["s"], c["s"] * 0.6)), Color(c["c"], a))
		alive.append(c)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	confetti = alive


# ── 맵 선택 · 설정 ───────────────────────────────────────

## 3칸 선택 막대: 각 칸에 작은 경기장 썸네일(지름 40px)과 이름. locked: 손님 화면 (방장이 고른 맵).
func _map_row(locked: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var hr := HBoxContainer.new()
	var ml := _nw(_label("맵", 14, LABEL, 1))
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(ml)
	if locked:
		hr.add_child(_nw(_label("방장이 고른 맵", 13, SUB)))
	v.add_child(hr)
	var seg := PanelContainer.new()
	var segsb := _sb(Color(FG, 0.05), Color(FG, 0.1), 10)
	segsb.set_content_margin_all(4)
	seg.add_theme_stylebox_override("panel", segsb)
	var narrow_m := get_viewport_rect().size.x < 600.0
	var row: Container = HBoxContainer.new()
	if narrow_m:
		var gr := GridContainer.new()
		gr.columns = 2
		gr.add_theme_constant_override("h_separation", 6)
		gr.add_theme_constant_override("v_separation", 6)
		row = gr
	else:
		row.add_theme_constant_override("separation", 6)
	seg.add_child(row)
	for id in Themes.ORDER:
		var on: bool = id == map_id
		var mid: String = id
		var b := _button("", func():
			if locked or mid == map_id:
				return
			snd.play("ui_toggle")
			_apply_map(mid)
			if online == "host":
				_host_broadcast_lobby())
		b.disabled = locked and not on
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "그날 공방의 경기장을 씁니다" if mid == "auto" else ""
		var st := _sb(BRASS if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 7)
		st.set_border_width_all(0)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("disabled", st)
		var sth := _sb(BRASS.lightened(0.1) if on else Color(FG, 0.08), Color(0, 0, 0, 0), 7)
		sth.set_border_width_all(0)
		b.add_theme_stylebox_override("hover", sth)
		b.add_theme_stylebox_override("pressed", sth)
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var thumb := Control.new()
		thumb.custom_minimum_size = Vector2(40, 44)
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tdata: Dictionary = Themes.get_theme(Themes.resolve(mid, _cur_ws()))
		thumb.draw.connect(func():
			var c := thumb.size * 0.5
			thumb.draw_circle(c, 20.0, tdata["bg"])
			Arena.board(thumb, c, 14.0, 3.2, false, tdata))
		inner.add_child(thumb)
		var nl := _nw(_label(Themes.AUTO_NAME if mid == "auto" else Themes.THEMES[mid]["name"], 13, INK if on else TEXT, 1))
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(nl)
		b.add_child(inner)
		row.add_child(b)
	v.add_child(seg)
	return v


func _toggle_row(text: String, desc: String, key: String) -> Control:
	var h := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_label(text, 16, TEXT, 1))
	if desc != "":
		tv.add_child(_label(desc, 12, SUB))
	h.add_child(tv)
	var cb := CheckButton.new()
	cb.button_pressed = bool(view_opts[key])
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool):
		snd.play("ui_toggle")
		view_opts[key] = on
		_save_view()
		if key == "reduce_motion":
			shake = 0.0
			hitstop = 0.0)
	h.add_child(cb)
	return h


func _volume_row(text: String, kind: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _nw(_label(text, 15, TEXT))
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(snd.vol[kind])
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 28)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v: float): snd.set_volume(kind, v))
	sl.drag_ended.connect(func(_c: bool):
		if kind == "ui":
			snd.play("ui_click")
		elif kind == "sfx":
			snd.play("puck_hit_light"))
	h.add_child(sl)
	return h


## 메뉴(≡) 안 설정. 경기 중에도 맵을 바꿀 수 있고, 경기는 멈추지 않는다.
func _show_settings(from_setup: bool) -> void:
	var root := _new_overlay(true)
	root.set_meta("settings", true)
	var box := _centered_panel(root, 480, Color(SOLID, 0.96))
	box.add_child(_label("설정", 24, TEXT, 2))
	box.add_child(_map_row(online == "guest"))
	box.add_child(HSeparator.new())
	var spr := HBoxContainer.new()
	spr.add_theme_constant_override("separation", 10)
	var spl := _nw(_label("게임 속도", 16, TEXT, 1))
	spl.custom_minimum_size = Vector2(110, 0)
	spr.add_child(spl)
	var sp_opts: Array = []
	for i in SPEEDS.size():
		sp_opts.append([i, SPEEDS[i]["name"]])
	var spseg := _seg(sp_opts, settings.get("speed", 1), func(k):
		settings["speed"] = k
		_show_settings(from_setup))
	spseg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spr.add_child(spseg)
	box.add_child(spr)
	if from_setup:
		box.add_child(_setting_toggle("조준 8초 제한", "시간이 끝나면 차례가 넘어가요", settings["timed"], func(on: bool): settings["timed"] = on))
		box.add_child(_setting_toggle("전체 부품 섞기", "공방 대신 66종을 모두 섞어서 냅니다", settings.get("workshop", "junk") == "all", func(on: bool):
			settings["workshop"] = "all" if on else "junk"
			if online == "host":
				_host_broadcast_lobby()))
	box.add_child(HSeparator.new())
	box.add_child(_toggle_row("화면 흔들림", "세게 부딪히면 화면이 흔들려요", "shake"))
	box.add_child(_toggle_row("히트스톱", "충돌 순간 아주 잠깐 멈춰요", "hitstop"))
	box.add_child(_toggle_row("움직임 줄이기", "흔들림·멈춤·눌림을 끄고 배너를 바로 처리해요", "reduce_motion"))
	box.add_child(HSeparator.new())
	box.add_child(_label("소리", 14, LABEL, 1))
	box.add_child(_volume_row("효과음", "sfx"))
	box.add_child(_volume_row("배경음악", "music"))
	box.add_child(_volume_row("화면 소리", "ui"))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	if not from_setup:
		var home := _button("처음으로", func():
			_clear_overlay()
			_show_setup())
		home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		home.custom_minimum_size = Vector2(0, 44)
		btns.add_child(home)
	var close := _primary(_button("닫기" if from_setup else "계속하기", func():
		_clear_overlay()
		if from_setup:
			_show_setup()
		else:
			turn_key = ""))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.custom_minimum_size = Vector2(0, 44)
	btns.add_child(close)
	box.add_child(btns)


## 위쪽 가운데: 바퀴 칩. 지난 바퀴는 흐리게, 지금 바퀴는 강조색.
func _draw_timeline(vs: Vector2) -> void:
	var cur := m.round_no
	var first := 1
	var last := m.max_rounds
	if last <= 0:
		first = maxi(1, cur - 2)
		last = first + 5
	var n := last - first + 1
	var cw := 30.0
	var gap := 4.0
	var w := n * cw + (n - 1) * gap + 24.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 24, w, 62)
	_panel(r)
	for i in n:
		var rd := first + i
		var cr := Rect2(r.position.x + 12 + i * (cw + gap), r.position.y + 9, cw, 24)
		var col := Color(FG, 0.14)
		var tc := SUB
		if rd < cur:
			col = Color(th["accent_bg"])
		elif rd == cur:
			col = ACCENT
			tc = ACCENT_INK
		_round_rect(cr, col, 6)
		draw_string(font_semi, Vector2(cr.position.x, cr.position.y + 17), str(rd), HORIZONTAL_ALIGNMENT_CENTER, cw, 12, tc)
	var txt := "%d바퀴째" % cur
	if cur < m.first_draft_round:
		txt += " · 맨 알"
	if m.max_rounds > 0:
		txt += " · %d바퀴까지" % m.max_rounds
	else:
		txt += " · 한 명 남을 때까지"
	draw_string(font_semi, Vector2(r.position.x, r.position.y + 52), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, SUB)


# ── 이번 바퀴 개조 공개 ──────────────────────────────────
var round_picks: Array = []
var toast_picks: Array = []
var toast_t := -9.0


## 바퀴 개조가 끝나면 모두가 고른 부품을 위쪽에 잠깐 보여준다 (1.7초).
const TOAST_LIFE := 2.8


## 디자인 「8인 개조 공개」: 제목 · 남은 시간, 아래에 칸마다 색 점 · 이름 · 부품 그림 · 부품 이름.
func _draw_toast(vs: Vector2) -> void:
	var age := time - toast_t
	if toast_picks.is_empty() or age > TOAST_LIFE:
		return
	var a := 1.0
	var dy := 0.0
	if age < 0.2:
		a = age / 0.2
		dy = -10.0 * (1.0 - a)
	elif age > TOAST_LIFE - 0.3:
		a = (TOAST_LIFE - age) / 0.3
	var n := toast_picks.size()
	var cols := mini(4, n) if not portrait else mini(2, n)
	var rows := int(ceil(float(n) / cols))
	var side := 24.0 + 268.0 + 16.0
	var width := minf(vs.x - 2.0 * side, 172.0 * cols + 24.0) if not portrait else vs.x - 24.0
	width = maxf(width, 320.0)
	var cw := (width - 24.0 - 8.0 * (cols - 1)) / cols
	var ch := 54.0
	var r := Rect2(vs.x * 0.5 - width * 0.5, (96.0 if not portrait else 124.0) + dy, width, 46.0 + rows * (ch + 8.0) + 6.0)
	_panel(r)
	var rd: int = toast_picks[0].get("round", m.round_no)
	draw_string(font_bold, Vector2(r.position.x + 16, r.position.y + 28), "%d바퀴 개조 공개" % rd, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(TEXT, a))
	draw_string(font, Vector2(r.position.x, r.position.y + 28), "%d초 뒤 닫혀요" % int(ceil(TOAST_LIFE - age)), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16, 12, Color(SUB, a))
	for i in n:
		var pk: Dictionary = toast_picks[i]
		var cx := r.position.x + 12.0 + (i % cols) * (cw + 8.0)
		var cy := r.position.y + 44.0 + (i / cols) * (ch + 8.0)
		var cell := Rect2(cx, cy, cw, ch)
		_round_rect(cell, Color(FG, 0.05), 8, Color(PANEL_LINE, PANEL_LINE.a * a))
		var pl: Dictionary = m.players[int(pk["pid"])]
		draw_circle(Vector2(cx + 14, cy + ch * 0.5), 7, Color(Art.outline, a))
		draw_circle(Vector2(cx + 14, cy + ch * 0.5), 6, Color(pl.color, a))
		draw_string(font, Vector2(cx + 26, cy + ch * 0.5 + 5), pl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(SUB, a))
		var pid_part: String = pk.get("id", "")
		var ix := cx + 26 + font.get_string_size(pl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18
		if pid_part != "":
			var demo := {"weapon": "", "aux": "", "prop": ""}
			demo[PartsData.slot_of(pid_part)] = pid_part
			draw_set_transform(Vector2(ix, cy + ch * 0.5 + 2), -PI / 2.0, Vector2.ONE * 0.42)
			Art.draw(self, demo, 1, Art.NEUTRAL, a, -1)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		var tx := ix + 18
		var lines := _wrap(str(pk["part"]), font_bold, 13, cell.end.x - tx - 6)
		var ly := cy + ch * 0.5 + 5 - (lines.size() - 1) * 8
		for ln in lines.slice(0, 2):
			draw_string(font_bold, Vector2(tx, ly), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(TEXT, a))
			ly += 16


## 대기실 바탕: 화면보다 길면 위아래로 밀어 볼 수 있게 스크롤 안에 둔다 (휴대폰·패드).
var lobby_inner: Control = null


var lobby_built_size := Vector2.ZERO


func _lobby_root() -> Control:
	lobby_built_size = get_viewport_rect().size
	var over := _new_overlay(false)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.scroll_deadzone = 8
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	over.add_child(sc)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.custom_minimum_size = get_viewport_rect().size
	sc.add_child(inner)
	lobby_inner = inner
	lobby_col2 = null
	return inner


## 대기실 열 세로 위치: 화면에 들어가면 가운데, 넘치면 위에서부터 (스크롤).
func _place_lobby(vs: Vector2) -> void:
	var h := 0.0
	for lc in [lobby_col, lobby_col2]:
		if is_instance_valid(lc):
			h = maxf(h, lc.get_combined_minimum_size().y)
	var y := (vs.y - h) * 0.5 if h + 24.0 < vs.y else 12.0
	for lc in [lobby_col, lobby_col2]:
		if is_instance_valid(lc):
			lc.position.y = maxf(12.0, y if vs.x >= 900 else 12.0)
	if is_instance_valid(lobby_inner):
		lobby_inner.custom_minimum_size = Vector2(vs.x, maxf(vs.y, h + 36.0))

var _turn_title_seen := ""
var _turn_title_t := -9.0


# ── 경기장 캐시 ──────────────────────────────────────────
## 배경과 판은 거의 변하지 않으니 따로 그려 두고, 크기·테마·판이 바뀔 때만 다시 그린다.
## 흔들림은 노드 위치만 옮긴다. 마법 상점의 별·점선만 초당 10번 다시 그린다.
var arena_node: Node2D
var arena_vp: SubViewport
var puck_vp: SubViewport          # 플레이어 8명의 퍽 몸통을 한 줄로 구워 둔 그림
var puck_drawer: Node2D
var _puck_key := ""
const PUCK_TILE := 128
const PUCK_U := 50.0              # 구운 그림 속 퍽 반지름 (옆면 두께까지 칸 안에 들어가게)
var arena_drawer: Node2D
var _arena_key := ""
var _arena_tick := 0.0


func _update_arena_cache() -> void:
	var vs := get_viewport_rect().size
	var key := "%s|%s|%s|%.2f|%s" % [theme_id, vs, view_center, view_scale, (m.world.shape + str(m.world.size)) if m != null else "lobby"]
	var animated := false
	_arena_tick += get_process_delta_time()
	if key != _arena_key or (animated and _arena_tick >= 0.1):
		_arena_key = key
		_arena_tick = 0.0
		# 화면 실제 픽셀 크기로 구워 흐려지지 않게 한다
		var k: float = clampf(get_viewport().get_final_transform().get_scale().x, 0.5, 3.0)
		arena_vp.size = Vector2i(int((vs.x + 16.0) * k), int((vs.y + 16.0) * k))
		arena_drawer.scale = Vector2.ONE * k
		arena_drawer.position = Vector2.ONE * 8.0 * k
		arena_drawer.queue_redraw()
		arena_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		arena_node.queue_redraw()
	arena_node.position = shake_off
	if theme_id != _puck_key:
		_puck_key = theme_id
		puck_drawer.queue_redraw()
		puck_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_arena_cache() -> void:
	var vs := get_viewport_rect().size
	Arena.background(arena_drawer, Rect2(-Vector2.ONE * 8.0, vs + Vector2.ONE * 16.0), th, time)
	if m != null:
		var w := m.world
		Arena.board(arena_drawer, view_center, w.size * view_scale, CELL * view_scale, w.shape != "circle", th, time)


## HUD 퍽 아이콘: 구워 둔 퍽 그림을 작게 붙인다.
func _hud_icon(center: Vector2, size: float, col: Color, symbol: int, alpha := 1.0) -> void:
	if puck_vp == null or symbol < 0 or symbol >= 8 or col != Match.COLORS[symbol]:
		Art.draw_icon(self, center, size, col, symbol, alpha)
		return
	var u := size * 0.5 * 0.86
	Art.draw_puck_shadow(self, center, u, alpha)
	var tile := float(PUCK_TILE)
	var sz := tile * u / PUCK_U
	draw_texture_rect_region(puck_vp.get_texture(), Rect2(center + Vector2(0, -0.08 * u) - Vector2.ONE * sz * 0.5, Vector2.ONE * sz), Rect2(tile * symbol, 0, tile, tile), Color(1, 1, 1, alpha))
	Art.draw_notch(self, center + Vector2(0, -0.08 * u), u, -PI / 2.0, alpha)


# ── 아이콘 버튼 (디자인 「경기 HUD」 오른쪽 위) ─────────────

func _icon_button(kind: String, cb: Callable, tip := "") -> Button:
	var b := _button("", cb)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(44, 44)
	b.set_meta("icon", kind)
	var ic := Control.new()
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(func(): _draw_glyph(ic, str(b.get_meta("icon")), ic.size * 0.5, 9.0, b.get_meta("ink", TEXT)))
	b.add_child(ic)
	_style_icon_btn(b, false)
	return b


func _style_icon_btn(b: Button, on: bool) -> void:
	var nb := _sb(ACCENT if on else Color(SOLID, 0.92), PANEL_LINE, 10)
	b.add_theme_stylebox_override("normal", nb)
	b.add_theme_stylebox_override("hover", _sb(ACCENT.lightened(0.1) if on else Color(SOLID, 1.0), ACCENT, 10))
	b.add_theme_stylebox_override("pressed", _sb(ACCENT, ACCENT, 10))
	b.set_meta("ink", ACCENT_INK if on else TEXT)
	for c in b.get_children():
		(c as Control).queue_redraw()


## 작은 선 아이콘. r: 반 크기(px).
func _draw_glyph(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	var w := 2.0
	match kind:
		"ff":
			for dx in [-r * 0.55, r * 0.35]:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(dx - r * 0.35, -r * 0.6), c + Vector2(dx + r * 0.5, 0), c + Vector2(dx - r * 0.35, r * 0.6)]), col)
		"sound", "mute":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.35), c + Vector2(-r * 0.45, -r * 0.35), c + Vector2(r * 0.1, -r * 0.85), c + Vector2(r * 0.1, r * 0.85), c + Vector2(-r * 0.45, r * 0.35), c + Vector2(-r, r * 0.35)]), col)
			if kind == "sound":
				ci.draw_arc(c + Vector2(r * 0.15, 0), r * 0.45, -0.9, 0.9, 10, col, w, true)
				ci.draw_arc(c + Vector2(r * 0.15, 0), r * 0.85, -0.9, 0.9, 12, col, w, true)
			else:
				ci.draw_line(c + Vector2(r * 0.45, -r * 0.4), c + Vector2(r * 1.05, r * 0.4), col, w, true)
				ci.draw_line(c + Vector2(r * 0.45, r * 0.4), c + Vector2(r * 1.05, -r * 0.4), col, w, true)
		"book":
			var rr := Rect2(c - Vector2(r * 0.65, r * 0.9), Vector2(r * 1.3, r * 1.8))
			ci.draw_rect(rr, col, false, w)
			ci.draw_line(Vector2(rr.position.x, rr.end.y - r * 0.45), Vector2(rr.end.x, rr.end.y - r * 0.45), col, w)
		"menu":
			for dy in [-r * 0.6, 0.0, r * 0.6]:
				ci.draw_line(c + Vector2(-r * 0.8, dy), c + Vector2(r * 0.8, dy), col, w + 0.5, true)
		"invite":
			ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.35), r * 0.38, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, r * 0.85), c + Vector2(-r * 0.85, r * 0.2), c + Vector2(-r * 0.25, r * 0.05), c + Vector2(r * 0.35, r * 0.2), c + Vector2(r * 0.45, r * 0.85)]), col)
			ci.draw_line(c + Vector2(r * 0.75, -r * 0.65), c + Vector2(r * 0.75, -r * 0.05), col, w, true)
			ci.draw_line(c + Vector2(r * 0.45, -r * 0.35), c + Vector2(r * 1.05, -r * 0.35), col, w, true)
		"gear":
			ci.draw_circle(c, r * 0.3, col)
			for k in 8:
				var a := TAU * k / 8.0
				ci.draw_line(c + Vector2.from_angle(a) * r * 0.55, c + Vector2.from_angle(a) * r * 0.95, col, w, true)


func _setting_toggle(text: String, desc: String, val: bool, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_label(text, 16, TEXT, 1))
	if desc != "":
		tv.add_child(_label(desc, 12, SUB))
	h.add_child(tv)
	var cb2 := CheckButton.new()
	cb2.button_pressed = val
	cb2.focus_mode = Control.FOCUS_NONE
	cb2.toggled.connect(func(on: bool):
		snd.play("ui_toggle")
		cb.call(on))
	h.add_child(cb2)
	return h


func _round_rect_on(ci: CanvasItem, r: Rect2, col: Color, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.draw(ci.get_canvas_item(), r)


## 개조 화면 아래: 누가 고르는 중이고 누가 골랐는지 (모두 동시에 고른다).
func _draft_status_bar(me: int) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := get_viewport_rect().size
	var n_alive := 0
	for p in m.players:
		if p.out or m.world.alive_stones_of(p.id).is_empty():
			continue
		n_alive += 1
		var done: bool
		if p.cpu:
			done = true  # CPU는 바로 고른다
		elif _is_mine(p.id):
			done = p.id != me and (picked_round.get(p.id, -1) == m.round_no or not m.draft_queue.has(p.id))
		else:
			done = not m.draft_queue.has(p.id)
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.1)
		sb.set_corner_radius_all(999)
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pc: Color = p.color
		dot.draw.connect(func():
			dot.draw_circle(dot.size * 0.5, 6.0, Color(0, 0, 0, 0.5))
			dot.draw_circle(dot.size * 0.5, 5.0, pc))
		h.add_child(dot)
		h.add_child(_nw(_label(p.name, 13, Color(1, 1, 1, 0.85))))
		h.add_child(_nw(_label("골랐어요" if done else "고르는 중", 13, Color("7FD1A8") if done else Color.WHITE, 2)))
		chip.add_child(h)
		bar.add_child(chip)
	bar.resized.connect(func(): bar.position = Vector2(vs.x * 0.5 - bar.size.x * 0.5, vs.y - bar.size.y - 18))
	return bar


# ── 탈락 말풍선 (디자인 「경기 HUD」): 판 위쪽에 누가 무엇으로 떨어뜨렸는지 ─────
var ko_pills: Array = []


func _draw_ko_pills(vs: Vector2) -> void:
	var y := 104.0 if not portrait else 130.0
	var keep: Array = []
	for pill in ko_pills:
		var age: float = time - float(pill["t"])
		if age > 2.6:
			continue
		keep.append(pill)
		var a := clampf(age / 0.15, 0.0, 1.0) * clampf((2.6 - age) / 0.3, 0.0, 1.0)
		var t: String = pill["text"]
		var w := font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 40.0
		var r := Rect2(view_center.x - w * 0.5, y - 6.0 * (1.0 - clampf(age / 0.15, 0.0, 1.0)), w, 36)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(SOLID, 0.97 * a)
		sb.border_color = Color(pill["c"], a)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(18)
		sb.shadow_color = Color(0, 0, 0, 0.15 * a)
		sb.shadow_size = 4
		sb.draw(get_canvas_item(), r)
		draw_string(font_bold, Vector2(r.position.x, r.position.y + 24), t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(TEXT, a))
		y += 42.0
	ko_pills = keep


# ── 맵 기믹 그리기 ───────────────────────────────────────

func _draw_gimmicks() -> void:
	var k := view_scale
	for g in m.world.gimmicks:
		match str(g["kind"]):
			"oil":
				for it in g["items"]:
					var c := w2s(it["pos"])
					var r: float = float(it["r"]) * k
					var pts := PackedVector2Array()
					for i in 28:
						var a := TAU * i / 28.0
						var wob := 1.0 + 0.08 * sin(a * 3.0 + float(it["pos"].x)) + 0.05 * sin(a * 5.0)
						pts.append(c + Vector2(cos(a) * r * wob, sin(a) * r * 0.82 * wob))
					draw_colored_polygon(pts, Color("15161C", 0.82))
					# 무지갯빛 기름막
					var hues := [Color("FF6BD5"), Color("6BC8FF"), Color("8CFF9B"), Color("FFE36B")]
					for i in hues.size():
						var rr := r * (0.35 + 0.13 * i)
						var a0 := time * 0.3 + i * 1.3
						draw_arc(c + Vector2(-r * 0.12, -r * 0.1), rr, a0, a0 + 1.6, 16, Color(hues[i], 0.35), 2.5, true)
					draw_circle(c + Vector2(-r * 0.35, -r * 0.3), r * 0.12, Color(1, 1, 1, 0.18))
			"bolt":
				for it in g["items"]:
					var c2 := w2s(it["pos"])
					var r2: float = float(it["r"]) * k
					draw_circle(c2 + Vector2(0, r2 * 0.25), r2 * 1.05, Color(0, 0, 0, 0.35))
					draw_circle(c2, r2, Color("9AA0A6"))
					draw_arc(c2, r2, 0, TAU, 24, Art.outline, 2.0, true)
					var hx := PackedVector2Array()
					for i in 6:
						hx.append(c2 + Vector2.from_angle(TAU * i / 6.0 + 0.3) * r2 * 0.55)
					hx.append(hx[0])
					draw_polyline(hx, Color("5A6068"), 2.0, true)
					draw_circle(c2 + Vector2(-r2 * 0.3, -r2 * 0.35), r2 * 0.18, Color(1, 1, 1, 0.5))
			"belt":
				for it in g["items"]:
					var dir: Vector2 = it["dir"]
					var nrm := dir.orthogonal()
					var p0: Vector2 = it["pos"]
					var L := m.world.size * 2.2
					var R := m.world.size * view_scale
					var c0 := view_center + shake_off
					var sq := m.world.shape != "circle"
					# 띠의 양쪽 가장자리를 판 안으로 잘라 사각형으로
					var e1 := Arena.clip_segment(w2s(p0 + nrm * World.Gm.BELT_HALF - dir * L), w2s(p0 + nrm * World.Gm.BELT_HALF + dir * L), c0, R, sq)
					var e2 := Arena.clip_segment(w2s(p0 - nrm * World.Gm.BELT_HALF - dir * L), w2s(p0 - nrm * World.Gm.BELT_HALF + dir * L), c0, R, sq)
					if e1.is_empty() or e2.is_empty():
						continue
					draw_colored_polygon(PackedVector2Array([e1[0], e1[1], e2[1], e2[0]]), Color("2B2F34", 0.78))
					draw_line(e1[0], e1[1], Color("FFC23D", 0.85), 2.0, true)
					draw_line(e2[0], e2[1], Color("FFC23D", 0.85), 2.0, true)
					# 흐르는 화살표 무늬
					var mid := Arena.clip_segment(w2s(p0 - dir * L), w2s(p0 + dir * L), c0, R - 10.0, sq)
					if mid.is_empty():
						continue
					var a1: Vector2 = mid[0]
					var b1: Vector2 = mid[1]
					var sd := (b1 - a1).normalized()
					var len1 := a1.distance_to(b1)
					var step := 1.1 * CELL * k
					var phase := fmod(time * 30.0, step)
					var hw := World.Gm.BELT_HALF * k * 0.55
					var d := phase
					while d < len1:
						var q := a1 + sd * d
						draw_polyline(PackedVector2Array([q - sd * hw * 0.6 + nrm * hw, q + sd * hw * 0.4, q - sd * hw * 0.6 - nrm * hw]), Color("FFC23D", 0.7), 3.0, true)
						d += step


## 위쪽 바퀴 칩 옆: 이번 판의 기믹. 마우스를 올리거나 누르면 한 줄 설명.
var gimmick_tip := -1


func _draw_gimmick_chips(vs: Vector2) -> void:
	if m == null or m.world.gimmicks.is_empty() or portrait:
		return
	var x := vs.x * 0.5 + 150.0
	var mouse := get_local_mouse_position()
	var shown := -1
	for i in m.world.gimmicks.size():
		var g: Dictionary = m.world.gimmicks[i]
		var nm := World.Gm.name_of(g["kind"])
		var w := font_semi.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34.0
		var r := Rect2(x, 34, w, 30)
		_round_rect(r, Color(SOLID, 0.95), 15, ACCENT)
		draw_circle(r.position + Vector2(15, 15), 6, ACCENT)
		draw_string(font_semi, r.position + Vector2(26, 20), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		if r.has_point(mouse) or gimmick_tip == i:
			shown = i
			var desc: String = World.Gm.INFO.get(g["kind"], {}).get("desc", "")
			var dw := font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
			var dr := Rect2(minf(r.position.x, vs.x - dw - 12), r.end.y + 6, dw, 30)
			_round_rect(dr, Color(SOLID, 0.98), 8, PANEL_LINE)
			draw_string(font, dr.position + Vector2(12, 20), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		x += w + 6.0
	gimmick_rects_x = vs.x * 0.5 + 150.0


var gimmick_rects_x := 0.0


# ── 시작 배치 선택 화면 ──────────────────────────────────
var placing_pid := -1          # 이 기기에서 지금 놓고 있는 자리
var place_draft: Array = []    # 놓고 있는 알 위치 (월드)
var place_drag := -1
var place_left := 0.0
var place_touched := false
var place_sent := {}           # 보냈지만 아직 확정 안 된 자리 (온라인)
var cpu_place_wait := 0.0
const PLACE_TIME := 15.0


func _begin_placing() -> void:
	cpu_place_wait = 0.4
	placing_pid = -1
	_next_placer()


## 이 기기의 사람 자리 중 아직 안 놓은 자리를 차례로 (같은 기기 여럿이면 한 명씩, 남의 배치는 안 보인다).
func _next_placer() -> void:
	placing_pid = -1
	for pid in my_seats:
		if not m.players[pid].cpu and not m.placements.has(pid) and not place_sent.has(pid):
			placing_pid = pid
			break
	place_drag = -1
	place_touched = false
	place_left = PLACE_TIME
	if placing_pid >= 0:
		place_draft = m.preset(placing_pid, "tri")
		_show_place_bar()
		if my_seats.size() > 1:
			_banner("%s 자리 잡기" % m.players[placing_pid].name, m.players[placing_pid].color, "다른 사람은 보지 마세요")
	else:
		_clear_overlay()


func _update_place(delta: float) -> void:
	# CPU 자리는 성향대로 바로 놓는다
	if _drives_cpu():
		cpu_place_wait -= delta
		if cpu_place_wait <= 0.0:
			for p in m.players:
				if p.cpu and not m.placements.has(p.id) and not place_sent.has(p.id):
					var r := RandomNumberGenerator.new()
					r.seed = randi()
					_send_place(p.id, m.cpu_placement(p.id, r))
					break
			cpu_place_wait = 0.15
	if placing_pid >= 0:
		place_left -= delta
		if place_left <= 0.0:
			# 시간 끝: 지금 위치로, 손대지 않았거나 잘못 놓였으면 무작위
			if not place_touched or not m.placement_errors(placing_pid, place_draft).is_empty():
				var r2 := RandomNumberGenerator.new()
				r2.seed = randi()
				place_draft = m.preset(placing_pid, "random", r2)
			_confirm_place()


func _send_place(pid: int, pts: Array) -> void:
	place_sent[pid] = true
	var arr: Array = []
	for q in pts:
		arr.append([q.x, q.y])
	_act({"k": "place", "pid": pid, "pos": arr})


func _confirm_place() -> void:
	if placing_pid < 0 or not m.placement_errors(placing_pid, place_draft).is_empty():
		return
	snd.play("part_equip", -4.0)
	var pid := placing_pid
	_send_place(pid, place_draft)
	if m.phase == "place":
		_next_placer()
		if placing_pid < 0:
			_show_place_wait()


func _on_placed() -> void:
	# 모두 놓았다: 가렸던 알이 동시에 「탁」 내려앉는다
	_clear_overlay()
	placing_pid = -1
	for st in m.world.stones:
		var vv: Dictionary = vis.get(st.id, {})
		vv["drop_t"] = time
		vv["vf"] = st.facing
		vis[st.id] = vv
	get_tree().create_timer(0.3).timeout.connect(func(): snd.play("puck_hit_heavy", 0.0, 0.8))
	_log("모두 자리를 잡았어요", ACCENT)
	turn_hold = 0.5


func _place_input(event: InputEvent) -> void:
	if placing_pid < 0:
		return
	if event is InputEventMouseMotion:
		if place_drag >= 0:
			place_draft[place_drag] = s2w(event.position)
			place_touched = true
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var wp := s2w(event.position)
	if event.pressed:
		var best := -1
		var bd := CELL * GRAB_R
		for i in place_draft.size():
			var d: float = wp.distance_to(place_draft[i])
			if d < bd:
				bd = d
				best = i
		place_drag = best
		if best >= 0:
			snd.play("flick_pull", -8.0)
	else:
		if place_drag >= 0:
			snd.play("puck_hit_light", -8.0)
		place_drag = -1
		_show_place_bar()


func _show_place_bar() -> void:
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var pc := PanelContainer.new()
	var sb := _panel_style(Color(SOLID, 0.96), PANEL_LINE)
	sb.content_margin_left = 16
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	root.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var lbl := _nw(_label("빠른 선택", 14, SUB, 1))
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lbl)
	var pid := placing_pid
	for opt in [["line", "일렬"], ["tri", "삼각"], ["spread", "흩어짐"], ["random", "무작위"]]:
		var k: String = opt[0]
		var b := _button(opt[1], func():
			var r := RandomNumberGenerator.new()
			r.seed = randi()
			place_draft = m.preset(pid, k, r)
			place_touched = true
			snd.play("ui_toggle"))
		b.custom_minimum_size = Vector2(68, 40)
		h.add_child(b)
	var ok := _primary(_button("배치 완료", func(): _confirm_place()))
	ok.custom_minimum_size = Vector2(120, 40)
	h.add_child(ok)
	pc.resized.connect(func(): pc.position = Vector2(vs.x * 0.5 - pc.size.x * 0.5, vs.y - pc.size.y - 16))
	pc.position = Vector2(vs.x * 0.5 - 260, vs.y - 76)


func _show_place_wait() -> void:
	var v := _hint_panel(my_seats[0] if not my_seats.is_empty() else 0)
	v.add_child(_label("자리를 잡았어요. 모두 놓으면 동시에 공개돼요.", 16, TEXT, 1))


## 배치 중: 내 구역을 주인 색으로 옅게, 놓는 알은 잘못된 자리면 붉게. 남의 알은 보이지 않는다.
func _draw_placing() -> void:
	var c0 := view_center + shake_off
	var k := view_scale
	for p in m.players:
		var mine: bool = p.id == placing_pid
		var col: Color = p.color
		if m.world.shape == "square":
			var sgn := 1.0 if p.id == 0 else -1.0
			var y1 := (m.world.size - Match.PLACE_OUT * CELL) * sgn
			var y2 := (m.world.size - Match.PLACE_IN * CELL) * sgn
			var x1 := m.world.size - Match.PLACE_IN * CELL
			var rr := Rect2(w2s(Vector2(-x1, minf(y1, y2))), Vector2(2 * x1, absf(y2 - y1)) * k)
			draw_rect(rr, Color(col, 0.18 if mine else 0.05))
			draw_rect(rr, Color(col, 0.7 if mine else 0.2), false, 2.0)
			continue
		var a0 := m.seat_angle(p.id) - PI / m.n
		var a1 := m.seat_angle(p.id) + PI / m.n
		var r_in := (m.world.size - Match.PLACE_OUT * CELL) * k
		var r_out := (m.world.size - Match.PLACE_IN * CELL) * k
		var pts := PackedVector2Array()
		var steps := 24
		for i in steps + 1:
			pts.append(c0 + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * r_out)
		for i in steps + 1:
			pts.append(c0 + Vector2.from_angle(lerpf(a1, a0, float(i) / steps)) * r_in)
		draw_colored_polygon(pts, Color(col, 0.2 if mine else 0.05))
		pts.append(pts[0])
		draw_polyline(pts, Color(col, 0.75 if mine else 0.2), 2.0, true)
	if placing_pid < 0:
		return
	var bad := m.placement_errors(placing_pid, place_draft)
	var pcol: Color = m.players[placing_pid].color
	for i in place_draft.size():
		var sp := w2s(place_draft[i])
		var wrong := bad.has(i)
		_draw_puck_at(sp, -10 - i, {"weapon": "", "aux": "", "prop": ""}, 1, pcol, placing_pid, (-(place_draft[i] as Vector2)).angle(), 1.0,
			{"scale": 1.12 if place_drag == i else 1.0})
		if wrong:
			draw_circle(sp, World.STONE_R * k, Color(Art.RED, 0.55))
			draw_arc(sp, (World.STONE_R + 4) * k, 0, TAU, 32, Art.RED, 3.0, true)
	# 남은 시간
	var vs := get_viewport_rect().size
	var tt := "남은 시간 %d초" % int(ceil(place_left))
	_text_outline(Vector2(vs.x * 0.5, vs.y - 100), tt, 16, Color.WHITE if place_left > 5 else Color("FF7A5C"), true)
