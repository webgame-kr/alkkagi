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
	"friend": [false, false, false, false, false, false, false, false], "workshop": "junk", "mode": "survival",
	"teams": [0, 1, 0, 1, 0, 1, 0, 1], "parcel_every": 2, "parcel_goal": 3}
## 게임 속도: 퍽이 움직이는 빠르기(재생 배율), CPU가 뜸 들이는 시간, 차례 사이 쉬는 시간.
const SPEEDS := [
	{"name": "느리게", "play": 0.75, "think": 1.0, "aim_show": 1.1, "hold": 0.7},
	{"name": "보통", "play": 1.0, "think": 0.55, "aim_show": 0.75, "hold": 0.4},
	{"name": "빠르게", "play": 1.3, "think": 0.3, "aim_show": 0.45, "hold": 0.2},
]
var turn_hold := 0.0          # 샷이 끝난 뒤 다음 차례까지 잠깐 쉬기
var last_fastest := 9999.0    # 지난 프레임에 가장 빠른 알의 속도
const TAIL_SPEED := 70.0      # 이보다 느리면 거의 멈춘 것으로 보고 빨리 감기
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
	slot_colors = Match.COLORS.duplicate()
	puck_vp = SubViewport.new()
	puck_vp.transparent_bg = true
	puck_vp.disable_3d = true
	puck_vp.size = Vector2i(PUCK_TILE * 8, PUCK_TILE)
	puck_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(puck_vp)
	puck_drawer = Node2D.new()
	puck_drawer.draw.connect(func():
		for i in 8:
			Art.draw_puck_top(puck_drawer, Vector2(PUCK_TILE * (i + 0.5), PUCK_TILE * 0.5), PUCK_U, slot_colors[i], i, 0.0, 1.0, 0.0, false))
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
	_load_profile()
	_ensure_room_arrays()
	var args0 := OS.get_cmdline_user_args()
	var room: String = net.room_param() if net.available else ""
	if room != "":
		if str(my_profile["nick"]) == "":
			my_profile["nick"] = "친구"
		_join_room(room)
	elif args0.is_empty():
		_show_home()
	else:
		_reset_room(4)
		for i in range(1, 4):
			settings["cpu"][i] = true
			settings["empty"][i] = false
		_show_setup()
	_debug_args()


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
	if args.has("--derby"):
		settings["mode"] = "derby"
	if args.has("--crown"):
		settings["mode"] = "crown"
	if args.has("--parcel"):
		settings["mode"] = "parcel"
	var wi := args.find("--ws")
	if wi >= 0 and args.size() > wi + 1:
		settings["workshop"] = args[wi + 1]
	var ni := args.find("--n")
	if ni >= 0 and args.size() > ni + 1:
		_set_count(int(args[ni + 1]))
	var mi := args.find("--map")
	if mi >= 0 and args.size() > mi + 1:
		_apply_map(args[mi + 1], false)
	if args.has("--home"):
		_show_home()
	if args.has("--picker"):
		_show_puck_picker("home")
	if args.has("--join"):
		_show_join("TEK7")
	if args.has("--solo"):
		# 혼자 연습 기본 흐름 확인용: 기본 설정 그대로 시작
		my_profile["form"] = "coin"
		my_profile["color"] = 1
		my_profile["symbol"] = 4
		_start_solo()
		_start_from_room()
	if args.has("--roomdemo"):
		# 대기실 모습 확인용: 친구 자리 둘, CPU 하나
		settings["n"] = 8
		for k0 in 8:
			settings["empty"][k0] = k0 >= 5
			settings["cpu"][k0] = k0 == 2
			settings["friend"][k0] = false
		settings["prof"][1] = {"nick": "민지", "form": "cap", "color": 0, "symbol": 0, "kind": "local"}
		settings["prof"][3] = {"nick": "도윤", "form": "coin", "color": 3, "symbol": 3, "kind": "local"}
		settings["prof"][4] = {"nick": "하린", "form": "marble", "color": 4, "symbol": 4, "kind": "local"}
		my_profile["form"] = "glass"
		my_profile["color"] = 1
		my_profile["symbol"] = 1
		my_profile["nick"] = "나"
		_show_setup()
		if args.has("--roomstart"):
			settings["skins"] = false
			_start_from_room()
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
	var wsg := args.find("--wsgallery")
	if wsg >= 0:
		# 신규 공방 부품 확인용: 공방 부품을 알마다 나눠 단다 (홀수 알은 강화)
		var wsk: String = args[wsg + 1]
		var pool: Array = PartsData.WORKSHOPS[wsk]["parts"]
		var by: Dictionary = {"weapon": [], "aux": [], "prop": []}
		for id in pool:
			by[PartsData.slot_of(id)].append(id)
		var kk := 0
		for st in m.world.stones:
			for slot in PartsData.SLOTS:
				var arr0: Array = by[slot]
				st.parts[slot] = arr0[kk % arr0.size()]
				st.ups[slot] = kk % 2 == 1 and PartsData.upgradable(arr0[kk % arr0.size()])
			kk += 1
		m.world.stones[0].parts = {"weapon": pool[0], "aux": pool[1], "prop": pool[2]}
		m.world.stones[0].ups = {}
	if args.has("--upgallery"):
		# 강화 외형 확인용: 모든 알에 강화 부품을 나눠 단다
		var ids: Array = Art.ArtUp.SHAPES.keys()
		var by_slot := {"weapon": [], "aux": [], "prop": []}
		for id in ids:
			by_slot[PartsData.slot_of(id)].append(id)
		var k := 0
		for st in m.world.stones:
			for slot in PartsData.SLOTS:
				var arr: Array = by_slot[slot]
				if arr.is_empty():
					continue
				st.parts[slot] = arr[k % arr.size()]
				st.ups[slot] = true
			k += 1
	if args.has("--upcard"):
		get_tree().create_timer(2.5).timeout.connect(func():
			var st0 = m.world.alive_stones_of(0)[0]
			st0.parts["weapon"] = "pea"
			st0.ups["aux"] = false
			m.world.alive_stones_of(0)[1].parts["aux"] = "magnet"
			m.world.alive_stones_of(0)[1].ups["aux"] = true
			m.offers[0][2] = "up:pea"
			_show_draft_cards(0))
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
	if args.has("--grit"):
		var hs = m.world.alive_stones_of(0)
		hs[0].parts = {"weapon": "hero_band", "aux": "torn_cape", "prop": "awaken_shoes"}
		hs[0].status["grit"] = 3
		hs[1].parts["aux"] = "torn_cape"
		hs[1].status["grit"] = 1
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
	match_started_t = time
	mode_alerts.clear()
	late_tag.clear()
	crown_fly = {}
	parcel_fly = {}
	if seed_value < 0:
		seed_value = randi()
	var use_plan := not plan.is_empty()
	var n_play: int = int(plan["n"]) if use_plan else int(settings["n"])
	var cpu_flags: Array = plan["cpu"] if use_plan else settings["cpu"]
	if online == "":
		my_seats = []
		for i in n_play:
			if not cpu_flags[i]:
				my_seats.append(i)
	if not use_plan:
		cpu_levels = []
	m = Match.new()
	var ws: String = settings.get("workshop", "junk")
	if ws == "random":
		ws = ["junk", "magic", "toon", "lab", "clock", "pirate"][seed_value % 6]
	var md0: String = settings.get("mode", "survival")
	m.setup(n_play, cpu_flags, seed_value, settings["timed"], {"workshop": ws, "mode": md0, "placement": true,
		"teams": plan.get("teams", settings.get("teams", [])), "parcel_every": settings.get("parcel_every", 2), "parcel_goal": settings.get("parcel_goal", 3),
		"profiles": plan.get("profiles", []), "stones": int(settings.get("stones", 3)) if (use_plan and (md0 == "survival" or md0 == "derby")) else 0,
		"crown_goal": int(settings.get("crown_goal", 5))})
	if use_plan:
		m.aim_limit = float(plan.get("aim", 0.0))
	_apply_slot_styles_from_match()
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
	set_alerts.clear()
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
	var sp: Dictionary = m.players[m.first_player()]
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
	_take_crown_scores()
	_take_parcel_events()
	_take_order_log()
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
		"moving", "fx":
			var spd := 1.0
			if slowmo > 0.0:
				slowmo -= delta
				spd = 0.3
			if hitstop > 0.0:
				hitstop -= delta
				spd = 0.0
			# 알이 거의 멈춘 꼬리 구간은 빨리 감는다 (PACE-01: 기다리는 시간 줄이기, 결과는 그대로)
			if last_fastest < TAIL_SPEED and m.world.projs.is_empty() and slowmo <= 0.0:
				spd *= 3.0
			accum += minf(delta, 0.05) * spd * _sp("play")
			_motion_tick(delta)
			while accum >= World.DT and (m.phase == "moving" or m.phase == "fx") and hitstop <= 0.0:
				accum -= World.DT
				m.world.step()
				_consume_events()
				if m.world.is_settled():
					if m.phase == "fx":
						_after_fx()
					else:
						_after_shot()
					break
			var fastest := 0.0
			for st in m.world.stones:
				if st.alive:
					fastest = maxf(fastest, st.vel.length())
			snd.slide(fastest)
			last_fastest = fastest
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


## CPU가 생각하는 최대 시간 (ms). 사람이 많을수록, 빠르게일수록 짧게 (PACE-01).
func _bot_budget_ms() -> int:
	var ms := 900
	if settings.get("speed", 1) == 2 or fast_forward:
		ms = 450
	if m != null and m.n >= 6:
		ms = int(ms * 0.7)
	return ms


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
		if pid < cpu_levels.size():
			bot.aim_error = [1.9, 1.0, 0.45][clampi(int(cpu_levels[pid]), 0, 2)]
		bot_started = Time.get_ticks_msec()
		return
	# 프레임당 약 6ms 만큼만 생각한다 (화면이 멈추지 않게).
	var t0 := Time.get_ticks_usec()
	var finished := false
	while not finished and Time.get_ticks_usec() - t0 < 3000:
		finished = bot.think_step(1)
	bot_us += Time.get_ticks_usec() - t0
	# 느린 기기(웹)에서도 CPU가 오래 멈춰 보이지 않게, 1초가 지나면 지금까지 본 최선으로 쏜다
	if not finished and Time.get_ticks_msec() - bot_started > _bot_budget_ms():
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
			cpu_aim["t"] = _sp("aim_show") * (0.7 if m.n >= 6 else 1.0)


func _on_phase_changed() -> void:
	match m.phase:
		"place":
			_begin_placing()
		"aim":
			# 개조가 끝났으니 「골랐어요」 안내는 닫는다 (온라인 동시 선택)
			if overlay != null and overlay.has_meta("draft_wait"):
				_clear_overlay()
			# 바퀴 시작은 차례대로: 개조 공개 → 세트 알림 → 차례 시작 (UI-04)
			if not round_picks.is_empty():
				toast_picks = round_picks.duplicate()
				toast_t = time
				round_picks.clear()
				turn_hold = 0.6 if _reduced() else 1.4
				turn_key = ""
				return
			if not set_alerts.is_empty():
				for al in set_alerts:
					var st_a = m.world.get_stone(int(al["stone"]))
					if st_a == null or not st_a.alive:
						continue
					fx.append({"k": "text", "pos": st_a.pos + Vector2(0, -40), "t": 0.0, "life": 1.6, "text": al["text"], "c": POWER, "size": 26})
					fx.append({"k": "ring", "pos": st_a.pos, "t": 0.0, "life": 0.8, "r": 60.0, "c": POWER})
				set_alerts.clear()
				snd.play("set_complete", -4.0)
				turn_hold = 0.4 if _reduced() else 1.1
				turn_key = ""
				return
			aim_left = m.aim_limit
			_consume_events()
			bot = null
			bot_wait = _sp("think") * (0.6 if m.n >= 6 else 1.0)
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
			snd.play("turn_start", -2.0 if _is_mine(p.id) else -8.0)
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
	last_fastest = 9999.0
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
				ko_pills.append({"t": time, "text": "%s 알 %s · %s" % [m.players[int(e["owner"])].name, "탈락" if m.mode == "survival" else "추락", why],
					"c": m.players[int(cc["owner"])].color if cc.has("owner") else SUB})
				if ko_pills.size() > 3:
					ko_pills.pop_front()
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.6, "r": 46.0, "c": owner_col})
			"part":
				var big: bool = e.get("big", false)
				var part_id: String = e.get("part", "")
				if part_id == "hero_set":
					# 라스트 컷: 0.3초 만화 컷 정지
					hitstop = maxf(hitstop, 0.3)
					shake = maxf(shake, 6.0)
					snd.play("fx_parody_stamp", 0.0)
					fx.append({"k": "manga", "stone": int(e.get("stone", -1)), "pos": e["pos"], "t": 0.0, "life": 0.6, "text": "라스트 컷", "c": Color("F08A3C")})
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
			"grit":
				snd.play("fx_awaken_flame", -6.0, 1.0 + 0.08 * int(e["grit"]))
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -48), "t": 0.0, "life": 1.2, "text": "투지 %d · %s" % [int(e["grit"]), e.get("text", "")], "c": Color("F08A3C"), "size": 16})
			"merge":
				snd.play("puck_hit_heavy", 0.0, 0.7)
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.6, "r": 60.0, "c": Color("B6F23C")})
				_log("%s 알 둘이 합체했어요" % m.players[int(e["owner"])].name, m.players[int(e["owner"])].color)
			"split":
				snd.play("puck_hit_light", 0.0, 1.4)
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.5, "r": 50.0, "c": Color("B6F23C")})
				_log("%s 알이 둘로 갈라졌어요" % m.players[int(e["owner"])].name, m.players[int(e["owner"])].color)
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
			"crown":
				_on_crown_event(e)
			"walker", "replay":
				_on_clock_event(e)
			"shell", "cannonball", "swing", "jump":
				_on_pirate_event(e)
			"parcel":
				_on_parcel_event(e)
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
	if shutter_t >= 0.0 and ((event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		if _skip_intro():
			get_viewport().set_input_as_handled()
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
	if event.pressed and not m.world.gimmicks.is_empty():
		for gi in gimmick_rects.size():
			if (gimmick_rects[gi] as Rect2).has_point(event.position):
				gimmick_tip = gi if gimmick_tip != gi else -1
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
		if sid2 >= 0 and not m.bonus_active.is_empty() and sid2 != int(m.bonus_active["stone"]):
			sid2 = -1   # 정각 덤 차례: 같은 알만
		var other := _stone_at(wp2, -1)
		if remote_pick >= 0 and other >= 0 and _remote_targets(remote_pick).has(other):
			sid2 = other   # 리모컨 조종 단계: 고른 상대 알을 당긴다
		remote_pick = -1
		if sid2 < 0:
			if other >= 0 and m.remote_holder(m.current_player(), m.world.get_stone(other)) != null:
				sid2 = other
		if sid2 >= 0 and m.world.get_stone(sid2).owner != m.current_player():
			_banner("리모컨!", ACCENT, "%s 알을 대신 쏴요" % m.players[m.world.get_stone(sid2).owner].name)
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
		elif not drag_cloud and not _remote_targets(sid3).is_empty():
			# 리모컨 단 알을 당기지 않고 누르기만 하면: 조종할 상대 알 고르기
			remote_pick = sid3
			snd.play("ui_toggle", -4.0)
			_banner("리모컨", ACCENT, "조종할 상대 알을 누르세요 (점선 고리)")
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
	if PartsData.is_up(part):
		mine = _up_targets(pid, part)
	if mine.size() == 1:
		_pick_stone_for_part(pid, mine[0].id)
	else:
		_show_stone_hint(pid)


func _pick_stone_for_part(pid: int, sid: int) -> void:
	if draft_part == "bookmark":
		draft_stone = sid
		_show_bookmark_choice(pid)
		return
	if PartsData.is_up(draft_part):
		if not _up_targets(pid, draft_part).any(func(x): return x.id == sid):
			return
		_apply_equip(pid, draft_part, sid, 1)
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
	if part == "":
		if m.equip(pid, "", -1):
			var pl1: Dictionary = m.players[pid]
			round_picks.append({"pid": pid, "part": "고르지 않음", "id": "", "round": m.round_no})
			_log("%d바퀴 시작, %s 부품을 고르지 않고 넘겼어요" % [m.round_no, _j(pl1.name, "이", "가")], pl1.color)
		if online == "":
			draft_part = ""
			draft_stone = -1
			_clear_overlay()
		return
	var s = m.world.get_stone(sid)
	if PartsData.is_up(part):
		if m.equip(pid, part, sid, side, reserve):
			var pl0: Dictionary = m.players[pid]
			round_picks.append({"pid": pid, "part": PartsData.part_name(part), "id": PartsData.base_of(part), "round": m.round_no})
			_log("%d바퀴 시작, %s %s ★ 강화했어요" % [m.round_no, _j(pl0.name, "이", "가"), PartsData.part_name(PartsData.base_of(part))], pl0.color)
			snd.play("set_progress", -2.0, 1.15)
			fx.append({"k": "text", "pos": s.pos + Vector2(0, -34), "t": 0.0, "life": 1.4, "text": "★ 강화", "c": BRASS.lightened(0.2), "size": 22})
			for i in 12:
				fx.append({"k": "spark", "pos": s.pos, "vel": Vector2.from_angle(TAU * i / 12.0) * randf_range(80.0, 150.0), "t": 0.0, "life": randf_range(0.3, 0.5), "c": Color("FFD27A")})
		if online == "":
			draft_part = ""
			draft_stone = -1
			_clear_overlay()
		return
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
			# 세트 알림은 개조 공개가 끝난 뒤에 따로 (UI-04)
			set_alerts.append({"stone": sid, "text": PartsData.SETS[done_set]["name"] + "!"})
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
				if is_instance_valid(lc) and not (lc is PanelContainer):
					var lr: Rect2 = lc.get_global_rect().grow(22)
					lr.size.y = minf(lr.size.y, vs.y - lr.position.y + 40.0)
					_round_rect(lr, PANEL_BG, 14, PANEL_LINE)
		if state == "setup" and not portrait:
			pass
		return
	_draw_board()
	_draw_gimmicks()
	_draw_devices()
	_draw_pirate_board()
	_draw_clock_things()
	_draw_crown_floor()
	_draw_parcel()
	_draw_aim_under()
	var _ts := Time.get_ticks_usec()
	if m.phase == "place":
		_draw_placing()
	for s in m.world.stones:
		if s.alive and m.phase != "place":
			_draw_stone(s)
	_draw_crown_held()
	_perf_sec["stones"] = _perf_sec.get("stones", 0.0) + float(Time.get_ticks_usec() - _ts)
	_ts = Time.get_ticks_usec()
	_draw_projs()
	_draw_fx()
	_draw_aim_over()
	_draw_remote_marks()
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
	var crown_mode: bool = settings.get("mode", "survival") == "crown"
	var parcel_mode: bool = settings.get("mode", "survival") == "parcel"
	var square := n == 2 and not crown_mode and not parcel_mode
	var units := 16.0 if square else (18.0 if n <= 4 else 20.0)
	var u := 2.0 * half / units
	var r := u * 0.5
	Arena.board(ci, c, half, u, square, th, time)
	if parcel_mode:
		_draw_parcel_halves(ci, c, half - 0.2 * u, u)
	var pucks: Array = []
	if square:
		for i in 2:
			var y := c.y + (1.0 if i == 0 else -1.0) * (half - 4.0 * u)
			for j in 4:
				pucks.append([i, Vector2(c.x + (j - 1.5) * 2.5 * u, y)])
	else:
		var R := half / u
		var pm := Match.new() if parcel_mode else null
		if parcel_mode:
			pm.n = n
			pm.mode = "parcel"
			for i0 in n:
				pm.players.append({"id": i0, "team": int(settings["teams"][i0])})
		for i in n:
			var a := deg_to_rad(90.0 + 360.0 * i / n) if not parcel_mode else pm.seat_angle(i)
			var rad := Vector2(cos(a), sin(a))
			var tg := rad.orthogonal()
			pucks.append([i, c + rad * (R - 4.0) * u + tg * Match.SIDE_GAP * u])
			pucks.append([i, c + rad * (R - 4.0) * u - tg * Match.SIDE_GAP * u])
			if not crown_mode and not parcel_mode:
				pucks.append([i, c + rad * (R - 5.5) * u])
	if crown_mode:
		_draw_crown_icon(ci, c, u * 1.1, 1.0)
	if parcel_mode:
		_draw_parcel_box(ci, c, u * 0.65, 0.0, -1, 1.0)
	for pk in pucks:
		var i: int = pk[0]
		if not settings["cpu"][i]:
			ci.draw_arc(pk[1], r + 4, 0, TAU, 24, th["outline"], 3.0, true)
			ci.draw_arc(pk[1], r + 5.5, 0, TAU, 24, BRASS, 2.0, true)
		Art.draw_puck_shadow(ci, pk[1], r)
		Art.draw_puck_top(ci, pk[1], r, Match.TEAM_COLORS[int(settings["teams"][i])] if parcel_mode else Match.COLORS[i], i, -PI / 2)
	# 판 정보: 판 · 퍽 · 개조 · 조준
	var timed: bool = settings["timed"]
	var info := [["판", "정사각 16칸" if square else "지름 %d칸" % int(units)], ["퍽", "%d개씩" % (2 if (crown_mode or parcel_mode) else (4 if square else 3))],
		["개조", "1·2·3바퀴" if (crown_mode or parcel_mode) else "2바퀴부터"], ["조준", "10초 제한" if timed else "제한 없음"]]
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
		Art.draw(self, s.parts, s.magnet_side, col, 0.3, s.owner, true, s.ups)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	var u := World.STONE_R * view_scale
	if World.Hero.is_hero(s):
		_draw_grit(p + Vector2(0, -(World.STONE_R * m.world.size_of(s) + 16) * view_scale), World.Hero.grit(s), World.Hero.lastcut_ready(s), 1.0)
	if s.mods.has("repel"):
		draw_arc(p, (World.STONE_R * m.world.size_of(s) + 5) * view_scale, 0, TAU, 32, Color("B6F23C", 0.8 + 0.2 * sin(time * 6.0)), 3.0, true)
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
	# 끈끈이로 붙은 알: 연두색 실
	for g in m.world.glue:
		var ga = m.world.get_stone(g["a"])
		var gb = m.world.get_stone(g["b"])
		if ga != null and gb != null and ga.alive and gb.alive:
			draw_line(w2s(ga.pos), w2s(gb.pos), Color("B6F23C", 0.85), 5.0, true)
	for d in m.world.devices:
		if d.kind == "decoy":
			# 미끼 풍선: 주인 알과 똑같이 생긴 풍선 (실이 달림)
			var dp := w2s(d.pos)
			draw_line(dp + Vector2(0, World.STONE_R * view_scale * d.scale), dp + Vector2(4, World.STONE_R * view_scale * d.scale + 14), Color(0, 0, 0, 0.5), 1.5, true)
			_hud_icon(dp, World.STONE_R * 2.0 * view_scale * d.scale / 0.86, m.players[d.owner].color, d.owner, 0.92)
			continue
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
			"lastcut":
				var la := w2s(item["a"])
				var lb := w2s(item["b"])
				draw_line(la, lb, Color("F08A3C", 0.35), 18.0 * view_scale, true)
				draw_dashed_line(la, lb, Color("F08A3C"), 4.0, 12.0)
				_text_outline(lb + (la - lb).normalized() * 30.0 + Vector2(0, -16), "라스트 컷", 16, Color("F08A3C"), true)
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
			if int(s.status.get("smoke", -1)) >= m.round_no:
				b = a.lerp(b, 0.5)   # 연막: 조준선이 절반만 보인다
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


	_draw_pirate_aim(info)


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
		return {"stone": s, "power": aim["power"], "dir": aim["dir"], "finger": drag_screen, "preview": pv, "origin": _origin_of(drag_stone)}
	if not cpu_aim.is_empty():
		var s2 = m.world.get_stone(cpu_aim["stone"])
		return {"stone": s2, "power": cpu_aim["power"], "dir": cpu_aim["dir"],
			"preview": Parts.aim_preview(m.world, s2, cpu_aim["dir"], cpu_aim["power"])}
	return {}


func _draw_draft_marks() -> void:
	if m.phase != "draft" or draft_part == "" or drafting_pid < 0:
		return
	var pid := drafting_pid
	var slot := PartsData.slot_of(draft_part)
	var col: Color = m.players[pid].color
	var cands: Array = _up_targets(pid, draft_part) if PartsData.is_up(draft_part) else m.world.alive_stones_of(pid)
	for s in cands:
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
		demo[slot] = PartsData.base_of(draft_part)
		draw_set_transform(p, facing, Vector2.ONE * view_scale)
		Art.skip_body = true
		var demo_up: Dictionary = s.ups.duplicate()
		demo_up[slot] = PartsData.is_up(draft_part)
		Art.draw(self, demo, s.magnet_side, col, 0.75, pid, true, demo_up)
		Art.skip_body = false
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var cur: String = s.parts[slot]
		var line1 := "%s · %s → %s" % [PartsData.SLOT_LABEL[slot], "비어 있음" if cur == "" else PartsData.part_name(cur), PartsData.part_name(draft_part)]
		var line2 := "이 알에 달아요" if cur == "" else "지금 부품과 바꿔요"
		if PartsData.is_up(draft_part):
			line2 = "이 알의 %s ★ 강화" % PartsData.part_name(cur)
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
		if m.mode == "crown":
			_draw_crown_forecast(vs)
		elif m.mode == "parcel":
			_draw_parcel_clock(vs)
		else:
			_draw_timeline(vs)
	_draw_mode_alerts(vs)
	_draw_wind_vane(vs)
	_draw_turn_end_chip(vs)
	_draw_reserved_card()
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
				if m.mode == "crown" and m.phase == "aim":
					sub = _crown_hint(pid)
				elif m.mode == "parcel" and m.phase == "aim":
					sub = _parcel_hint(pid)
		"fx":
			pid = m.current_player()
			title = _fx_title()
			sub = "효과가 터지는 중이에요"
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
	if m.mode == "crown":
		_txt(Vector2(r.end.x - 18, y), "%d점 선취" % m.crown_goal, 13, SUB, font, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	elif m.mode == "parcel":
		_txt(Vector2(r.end.x - 18, y), "%d점 선취" % m.parcel_goal, 13, SUB, font, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	elif m.max_rounds > 0:
		_txt(Vector2(r.end.x - 18, y), "%d바퀴까지" % m.max_rounds, 13, SUB, font, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_txt(Vector2(r.end.x - 18, y), "한 명 남을 때까지", 13, SUB, font, 150, HORIZONTAL_ALIGNMENT_RIGHT)
	# 바퀴 진행: 제한이 없으면 남은 사람 수로 보여준다
	var seg_r := Rect2(r.position.x + 18, y + 8, r.size.x - 36, 5)
	var n := m.max_rounds if m.max_rounds > 0 else m.n
	var lit := m.round_no if m.max_rounds > 0 else m.alive_players().size()
	if m.mode == "parcel":
		n = m.parcel_goal
		lit = maxi(int(m.team_scores[0]), int(m.team_scores[1]))
	if m.mode == "crown":
		# 왕관 쟁탈전: 선두의 점수
		n = m.crown_goal
		lit = 0
		for sc0 in m.scores:
			lit = maxi(lit, int(sc0))
	var gap := 3.0
	var w := (seg_r.size.x - gap * (n - 1)) / n
	for i2 in n:
		draw_rect(Rect2(seg_r.position.x + i2 * (w + gap), seg_r.position.y, w, 5), BRASS if i2 < lit else Color(FG, 0.14))
	# 세로 화면: 힘을 카드 오른쪽 위에
	if portrait and m.phase == "aim":
		var info := _current_aim()
		if not info.is_empty() and not info.has("cancel"):
			_txt(Vector2(r.end.x - 16, r.position.y + 42), "%d%%" % int(round(info["power"] * 100)), 22, POWER, font_bold, 80, HORIZONTAL_ALIGNMENT_RIGHT)
	# 조준 남은 시간: 줄어드는 막대와 숫자 (PACE-02). 마지막 3초는 빨갛게 깜빡인다
	if m.phase == "aim" and m.aim_limit > 0.0 and not m.players[m.current_player()].cpu and _is_mine(m.current_player()) and not (portrait and drag_stone >= 0):
		var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
		var warn := aim_left <= 3.0
		var tc: Color = Art.RED if warn else POWER
		if warn:
			tc = Color(tc, 0.6 + 0.4 * absf(sin(time * 8.0)))
		var bar := Rect2(r.position.x + 12, r.end.y - 9, r.size.x - 24, 6)
		_round_rect(bar, Color(FG, 0.12), 3)
		_round_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), tc, 3)
		_txt(Vector2(r.end.x - 16, r.position.y + 40), "%d" % int(ceil(maxf(aim_left, 0.0))), 26, tc, font_bold, 60, HORIZONTAL_ALIGNMENT_RIGHT)
		_txt(Vector2(r.end.x - 16, r.position.y + 58), "초", 11, Color(SUB, 0.9), font, 60, HORIZONTAL_ALIGNMENT_RIGHT)


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
	var team_h := 84.0 if m.mode == "parcel" else 0.0
	if not portrait:
		r.size.y = 14 + 24 + rows.size() * row_h + 10 + team_h
		hud["order_end"] = r.end.y
	_panel(r)
	if team_h > 0.0:
		_draw_team_scores(Rect2(r.position + Vector2(10, 8), Vector2(r.size.x - 20, team_h - 8)))
		r.position.y += team_h
	_txt(r.position + Vector2(18, 27), "차례 순서" + (" · 이번 구간" if m.mode == "parcel" else ""), 13, SUB, font_semi)
	if m.mode == "crown":
		_txt(Vector2(r.end.x - 18, r.position.y + 27), "%d점 선취" % m.crown_goal, 13, SUB, font, 100, HORIZONTAL_ALIGNMENT_RIGHT)
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
		if m.mode == "crown":
			_draw_crown_row(row, pid, nx + name_w + 8, cy, a, pid == cur, i)
			y += row_h
			i += 1
			continue
		if m.mode == "derby":
			# 더비: 사람/CPU 대신 점수를 이름 옆 자기 칸에 (UI-01: 「지금」「다음」과 붙지 않게)
			_txt(Vector2(nx + name_w + 8, cy + 5), "%d점" % m.scores[pid], 14, Color(POWER, a), font_bold, 40)
		else:
			_txt(Vector2(nx + name_w + 8, cy + 4), _seat_word(pid), 12, Color(SUB, a), font, 40)
		var gmax := -1
		for hs in m.world.alive_stones_of(pid):
			if World.Hero.is_hero(hs):
				gmax = maxi(gmax, World.Hero.grit(hs))
		if gmax >= 0 and not portrait:
			_draw_grit(Vector2(nx + name_w + 54, cy - 1), gmax, false, 0.62)
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
			if late_tag.has(pid) and int(late_tag[pid]) >= m.world.turn_no - 1 and pid != cur:
				var lt := "늦잠 ↓1"
				var lw := font_bold.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0
				var lr := Rect2(right - 12 - left * 12 - lw - 46.0, cy - 10, lw, 20)
				_round_rect(lr, Color("7B4FD6"), 10)
				draw_string(font_bold, lr.position + Vector2(0, 14), lt, HORIZONTAL_ALIGNMENT_CENTER, lw, 11, Color.WHITE)
			if m.mode == "parcel" and m.phase != "draft" and m.is_settle_round() and not m.order.is_empty() and pid == m.order[m.order.size() - 1] and pid != cur:
				tag = "정산 직전"
			if tag != "" and not portrait:
				_txt(Vector2(right - 12 - left * 12, cy + 4), tag, 12, HINT_GOLD if tag == "지금" else SUB, font_semi, 70, HORIZONTAL_ALIGNMENT_RIGHT)
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
		if id != "" and s.ups.get(slot, false):
			nm += " ★"
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
func _puck_pic(parts: Dictionary, col: Color, symbol: int, size: Vector2, scale: float, mside := 1, ups := {}) -> Control:
	var pic := Control.new()
	pic.custom_minimum_size = size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func():
		pic.draw_set_transform(pic.size * 0.5 + Vector2(0, 2 * scale), -PI / 2.0, Vector2.ONE * scale)
		Art.draw(pic, parts, mside, col, 1.0, symbol, true, ups)
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
	_show_room()


func _show_setup_old() -> void:
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
	mv.add_child(_seg([["survival", "생존전"], ["derby", "더비"], ["crown", "왕관"], ["parcel", "택배"]], cur_mode, func(k):
		settings["mode"] = k
		if k == "parcel":
			_fix_parcel_count()
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
	for n in ([4, 6, 8] if cur_mode == "parcel" else range(2, 9)):
		counts.append([n, str(n)])
	nv.add_child(_seg(counts, settings["n"], func(k): _set_count(k)))
	mr.add_child(nv)
	col.add_child(mr)
	if cur_mode == "crown":
		col.add_child(_label("알 2개 · 왕관을 얻으면 1점, 남의 차례를 버틸 때마다 1점 · 5점 선취 · 떨어진 알은 다음 차례에 복귀", 12, SUB))
	if cur_mode == "derby":
		col.add_child(_label("정해진 %d바퀴 동안 모두 계속 둡니다. 떨어진 퍽은 다음 바퀴에 부품을 단 채 돌아오고, 상대 퍽을 떨어뜨리면 1점." % (Match.DERBY_ROUNDS_SMALL if settings["n"] <= 4 else Match.DERBY_ROUNDS_BIG), 12, SUB))
	# 자리 (택배 쟁탈전은 팀 나누기)
	if cur_mode == "parcel":
		col.add_child(_team_panel(narrow))
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
	if cur_mode != "parcel":
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
	var is_up := PartsData.is_up(part)
	if is_up:
		badges.add_child(_badge("강화", BRASS, INK))
		var ub := b.get_theme_stylebox("normal").duplicate()
		ub.border_color = BRASS
		ub.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", ub)
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
	demo[slot] = PartsData.base_of(part)
	var pic := _puck_pic(demo, m.players[pid].color, pid, Vector2(0, 92 if compact else 104), 0.86 if compact else 0.98, 1, {slot: true} if is_up else {})
	if is_up:
		pic.draw.connect(func(): _draw_star(pic, Vector2(pic.size.x * 0.5 + 34, 18), 11.0))
	pic_box.add_child(pic)
	var name_l := _label(d["name"], 16 if compact else 17, TEXT, 2)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	var one: String = d["when"] + " · " + str(d["desc"]).split(". ")[0].trim_suffix(".")
	if is_up:
		one = "지금: %s\n강화 후: %s" % [str(d["desc"]).split(". ")[0].trim_suffix("."), PartsData.UPGRADES.get(PartsData.base_of(part), "")]
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
	var fl := _label("이미 단 부품을 ★로 키워요" if is_up else ("빈 슬롯에 바로 장착" if fit else "기존 부품과 교체"), 13, BRASS.darkened(0.2) if is_up else (ok_col if fit else TEXT), 2)
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
	# 고르지 않기: 지금 알 그대로 두고 넘긴다
	var skip_row := HBoxContainer.new()
	skip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var skip_b := _button("이번엔 고르지 않기", func(): _apply_equip(pid, "", -1, 1))
	skip_b.custom_minimum_size = Vector2(220, 44)
	skip_b.add_theme_font_size_override("font_size", 16)
	skip_b.tooltip_text = "부품을 달지 않고 지금 알 그대로 이번 바퀴를 시작해요"
	skip_row.add_child(skip_b)
	v.add_child(skip_row)
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
	demo[d["slot"]] = PartsData.base_of(draft_part)
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
	_record_result()
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
	elif m.mode == "parcel":
		var wt: int = m.team_of(m.winners[0])
		title = "%s 팀 승리" % Match.TEAM_NAMES[wt]
		col = Match.TEAM_COLORS[wt]
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
	var reason := {"score": "점수 " + " · ".join(score_line), "last": "마지막 생존", "limit": "최대 %d바퀴 도달 · 남은 퍽이 가장 많은 사람이 승리" % m.max_rounds, "draw": "한 발에 모두 떨어졌습니다", "crown": "왕관 %d점 선취" % m.crown_goal, "parcel": "택배 %d점 선취 · %d : %d" % [m.parcel_goal, m.team_scores[0], m.team_scores[1]]}
	box.add_child(_label(reason.get(m.end_reason, ""), 15, SUB))
	# 순위: 남은 퍽 많은 순, 그다음 늦게 탈락한 순
	var rank: Array = []
	for p in m.players:
		if not p.out:
			rank.append(p.id)
	if m.mode == "derby" or m.mode == "crown":
		rank.sort_custom(func(a, b): return m.scores[a] > m.scores[b])
	elif m.mode == "parcel":
		var tch: Dictionary = m.world.parcel.get("touch", {})
		rank.sort_custom(func(a, b):
			if m.team_scores[m.team_of(a)] != m.team_scores[m.team_of(b)]:
				return m.team_scores[m.team_of(a)] > m.team_scores[m.team_of(b)]
			return int(tch.get(a, 0)) > int(tch.get(b, 0)))
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
		if m.mode == "parcel":
			r.add_child(_nw(_label("택배 접촉 %d" % int(m.world.parcel.get("touch", {}).get(pid, 0)), 13, SUB)))
		if m.mode == "crown":
			var cs: Dictionary = m.crown_stats[pid]
			r.add_child(_nw(_label("획득 %d · 방어 %d" % [cs["gain"], cs["defend"]], 13, SUB)))
		var right_txt: String = ("%d점" % m.scores[pid]) if (m.mode == "derby" or m.mode == "crown" or m.mode == "parcel") else (("퍽 %d개" % m.stones_left(pid)) if not p.out else "%d바퀴 탈락" % p.out_round)
		r.add_child(_nw(_label(right_txt, 15, SUB)))
		box.add_child(r)
		i += 1
	var secs := int(time - match_started_t)
	var tail := "%d바퀴 · %d발 · 시간 %d분 %02d초" % [m.round_no, m.shots, secs / 60, secs % 60]
	if m.mode == "crown":
		var steals := 0
		for cs2 in m.crown_stats:
			steals += int(cs2["steal"])
		tail += " · 강탈 %d회" % steals
	if m.mode == "parcel":
		tail += " · 정산 %d회 · 무득점 %d" % [m.parcel_stats["settles"], m.parcel_stats["zero"]]
	box.add_child(_label(tail, 13, SUB))
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
	room_peer.clear()
	net.host()
	_show_setup()


func _host_msg(from: String, d: Dictionary) -> void:
	match str(d.get("t", "")):
		"_joined":
			pass
		"hello":
			if _seat_of_peer(from) < 0:
				_host_assign(from)
			var seat0 := _seat_of_peer(from)
			if seat0 >= 0:
				_host_set_prof(seat0, d.get("prof", {}), from)
		"prof":
			var seat1 := _seat_of_peer(from)
			if seat1 >= 0 and state == "setup":
				_host_set_prof(seat1, d.get("prof", {}), from)
		"ready":
			var seat2r := _seat_of_peer(from)
			if seat2r >= 0 and state == "setup":
				settings["ready"][seat2r] = bool(d.get("on", false))
				_host_broadcast_lobby()
				_show_setup()
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


## 친구가 고른 알: 색이 겹치면 남은 색 중 가까운 색으로 바꾸고 알려 준다.
func _host_set_prof(seat: int, pf, peer: String) -> void:
	if not (pf is Dictionary):
		return
	var p2: Dictionary = (pf as Dictionary).duplicate()
	var used := {}
	for i in settings["n"]:
		if i != seat and not settings["empty"][i] and settings["prof"][i] is Dictionary and not (settings["prof"][i] as Dictionary).is_empty():
			used[int(settings["prof"][i].get("color", -1))] = true
	var want := int(p2.get("color", 0))
	var got := _nearest_free_color(want, used)
	if got != want:
		net.send_to(peer, {"t": "note", "text": "색이 겹쳐서 %s으로 바꿨어요" % Match.NAMES[got]})
	p2["color"] = got
	p2["kind"] = "friend"
	# 같은 닉네임은 뒤에 숫자
	var nick := str(p2.get("nick", "친구"))
	for i in settings["n"]:
		if i != seat and settings["prof"][i] is Dictionary and str(settings["prof"][i].get("nick", "")) == nick:
			p2["nick"] = nick + str(seat + 1)
	settings["prof"][seat] = p2
	settings["ready"][seat] = false
	_host_broadcast_lobby()
	if state == "setup":
		_show_setup()


func _seat_of_peer(peer: String) -> int:
	for seat in friend_peer:
		if friend_peer[seat] == peer:
			return seat
	return -1


func _host_assign(peer: String) -> void:
	if state != "setup":
		if not pending_join.has(peer):
			pending_join.append(peer)
		net.send_to(peer, {"t": "note", "text": "지금 경기 중이에요, 끝나면 들어갈 수 있어요"})
		return
	_ensure_room_arrays()
	var seat := -1
	for i in settings["n"]:
		if settings["friend"][i] and not friend_peer.has(i):
			seat = i
			break
	if seat < 0:
		for i in range(1, settings["n"]):
			if settings["empty"][i]:
				settings["empty"][i] = false
				settings["friend"][i] = true
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
		net.send_to(peer, {"t": "full", "why": "방이 꽉 찼어요 (%d/%d)" % [settings["n"], settings["n"]]})
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
	_refresh_seat_profiles()
	var cfg := {}
	for k in ["mode", "workshop", "aim", "stones", "fill", "skins", "crown_goal", "parcel_every", "parcel_goal"]:
		cfg[k] = settings.get(k)
	return {"t": "lobby", "n": settings["n"], "kinds": kinds, "timed": settings["timed"], "speed": settings["speed"], "seats": _room_seats(), "cfg": cfg,
		"workshop": settings.get("workshop", "junk"), "mode": settings.get("mode", "survival"), "map": map_id,
		"teams": settings.get("teams", []), "parcel_every": settings.get("parcel_every", 2), "parcel_goal": settings.get("parcel_goal", 3)}


func _host_broadcast_lobby() -> void:
	if online != "host":
		return
	for seat in friend_peer:
		var msg := _lobby_state()
		msg["seat"] = seat
		net.send_to(friend_peer[seat], msg)


func _host_start() -> void:
	if plan.is_empty():
		_compose_plan()
	var cpu: Array = plan["cpu"].duplicate()
	var owners := {}
	my_seats = []
	for i in int(plan["n"]):
		if friend_peer.has(i):
			owners[str(i)] = friend_peer[i]
		elif bool(plan["friend"][i]):
			cpu[i] = true   # 아직 안 들어온 친구 자리는 CPU가 맡는다
		elif not cpu[i]:
			my_seats.append(i)
	plan["cpu"] = cpu
	var seed_value := randi()
	net.broadcast({"t": "start", "seed": seed_value, "n": settings["n"], "cpu": cpu, "timed": settings["timed"],
		"workshop": settings.get("workshop", "junk"), "mode": settings.get("mode", "survival"),
		"speed": settings["speed"], "owners": owners, "map": map_id, "plan": plan,
		"stones": settings.get("stones", 3), "crown_goal": settings.get("crown_goal", 5), "skins": settings.get("skins", false),
		"teams": settings.get("teams", []), "parcel_every": settings.get("parcel_every", 2), "parcel_goal": settings.get("parcel_goal", 3)})
	_start_match(seed_value)


func _back_to_lobby() -> void:
	plan = {}
	if not room_peer.is_empty() or online == "host":
		friend_peer = room_peer.duplicate()
	_ensure_room_arrays()
	for i in 8:
		settings["ready"][i] = false
	if online == "host":
		var waiting := pending_join.duplicate()
		pending_join.clear()
		state = "setup"
		for pj in waiting:
			_host_assign(pj)
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
			net.send_to(from, {"t": "hello", "prof": my_profile})
		"note":
			_banner(str(d.get("text", "")))
		"lobby":
			host_peer = from
			guest_lobby = d
			my_seat = int(d.get("seat", 0))
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
			settings["teams"] = d.get("teams", settings["teams"])
			settings["parcel_every"] = int(d.get("parcel_every", 2))
			settings["parcel_goal"] = int(d.get("parcel_goal", 3))
			if str(d.get("map", map_id)) != map_id:
				_apply_map(str(d.get("map", map_id)), false)
			for i in 8:
				settings["cpu"][i] = i < d["cpu"].size() and bool(d["cpu"][i])
			plan = d.get("plan", {})
			if not plan.is_empty():
				plan["cpu"] = d["cpu"]
			settings["stones"] = int(d.get("stones", 3))
			settings["crown_goal"] = int(d.get("crown_goal", 5))
			settings["skins"] = bool(d.get("skins", false))
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
	_show_room()


func _show_guest_lobby_old() -> void:
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
		col.add_child(_label("오늘의 공방: %s%s" % [ws_name, {"derby": "  ·  개조 더비", "crown": "  ·  왕관 쟁탈전", "parcel": "  ·  택배 쟁탈전"}.get(str(guest_lobby.get("mode", "")), "")], 15, HINT_GOLD, 1))
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
	var row := GridContainer.new()
	row.columns = 1 if narrow_w else 3
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	for key in ["junk", "magic", "toon", "lab", "clock", "pirate"]:
		var card := _workshop_card(key, cur == key)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
	v.add_child(row)
	if cur == "random":
		v.add_child(_label("공방을 열 때 여섯 공방 중 하나가 정해집니다.", 13, SUB))
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
	# 5인 이상이면 자리 목록이 두 줄이 되므로 공방 카드를 낮춰 「공방 열기」가 화면 안에 (UI-05)
	var compact_ws: bool = int(settings.get("n", 4)) > 4 or settings.get("mode", "survival") != "survival"
	var tiny_ws: bool = settings.get("mode", "survival") == "parcel"   # 팀 나누기 칸이 길어서 대표 부품 그림은 뺀다
	b.custom_minimum_size = Vector2(0, 96 if tiny_ws else (146 if compact_ws else 176))
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
		"pirate":
			ssb.bg_color = Color("F3EAD3")
			ssb.border_color = Color("6B4523")
			ssb.set_border_width_all(3)
			scol = Color("2A1E12")
		"clock":
			ssb.bg_color = Color("141A2E")
			ssb.border_color = Color("E2C27A")
			ssb.set_border_width_all(3)
			scol = Color("F3EAD3")
		"lab":
			ssb.bg_color = Color("FFFFFF")
			ssb.border_color = Color("B6F23C")
			ssb.set_border_width_all(4)
			scol = Color("16191C")
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
	if not compact_ws:
		var tag := _label(info.get("tag", ""), 12, SUB)
		tag.custom_minimum_size = Vector2(0, 18)
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
		var pic := _puck_pic(demo, Art.NEUTRAL, -1, Vector2(0, 40), 0.4)
		cell.add_child(pic)
		var nm := _nw(_label(PartsData.part_name(pid), 10, SUB))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(0, 0)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nm)
		reps.add_child(cell)
	if not tiny_ws:
		box.add_child(reps)
	var set_id: String = info.get("set", "")
	var gms: Array = []
	for gk in World.Gm.BY_WORKSHOP.get(key, []):
		gms.append(World.Gm.name_of(gk))
	var line := _nw(_label((("세트 · " + PartsData.SETS[set_id]["name"]) if set_id != "" else "규칙 파괴 부품") + ("   기믹 · " + "·".join(gms) if not gms.is_empty() else ""), 11, ACCENT, 2))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.clip_text = true
	box.add_child(line)
	b.add_child(box)
	return b


## 공방 소개: 셔터가 내려와 있다가 1.3초 뒤 올라간다 (디자인 「오늘의 공방」).
var shutter: Control = null
var shutter_t := -1.0


func _show_workshop_intro() -> void:
	_clear_overlay()
	match_no += 1
	turn_hold = INTRO_CLOSED + INTRO_OPEN
	shutter_t = 0.0
	_intro_sounds()
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
	if shutter_t > INTRO_CLOSED + INTRO_OPEN:
		shutter_t = -1.0
		shutter.visible = false
	shutter.queue_redraw()


func _draw_shutter() -> void:
	var vs := shutter.size
	if m != null and m.workshop == "lab":
		_draw_lab_doors(vs)
		return
	if m != null and m.workshop == "magic":
		_draw_magic_curtain(vs)
		return
	if m != null and m.workshop == "clock":
		_draw_clock_intro(vs)
		return
	if m != null and m.workshop == "pirate":
		_draw_pirate_intro(vs)
		return
	if m != null and m.workshop == "toon":
		_draw_manga_cover(vs)
		return
	var k := _intro_k()
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
	var sub := "오늘의 공방" + _mode_suffix()
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
	if part == "remote":
		return "리모컨"
	if part == "mecha":
		return "물고 던지기"
	if part == "moon_set":
		return "궤도 마법"
	return PartsData.part_name(part) if PartsData.CATALOG.has(part) else part


## 낙하 지점에 띄울 글: "보라 · 콩알총", "초록 · 몸통 충돌", "보라 · 콩알총 → 연쇄 충돌"
func _cause_text(c: Dictionary, victim_owner: int) -> String:
	if not c.has("owner"):
		if str(c.get("part", "")).begins_with("gm_"):
			return _part_word(str(c["part"]))
		return "판 밖으로"
	var att: String = m.players[int(c["owner"])].name
	if int(c["owner"]) == victim_owner:
		att = "스스로"
	if str(c["part"]).begins_with("gm_"):
		return "%s · %s의 샷" % [_part_word(str(c["part"])), m.players[int(c["owner"])].name]
	if str(c["part"]) == "remote" and int(c.get("of", -1)) >= 0:
		return "%s · 리모컨(%s 알)" % [m.players[int(c["owner"])].name, m.players[int(c["of"])].name]
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
	for key in ["survival", "derby", "crown"]:
		var on: bool = cur == key
		var k: String = key
		var b := _button({"survival": "최후 생존전", "derby": "개조 더비", "crown": "왕관 쟁탈전"}[key], func():
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
	if cur == "crown":
		v.add_child(_label("알 2개 · 왕관을 줍거나 빼앗아 살아남으면 1점, 다른 사람 차례를 버틸 때마다 1점. 5점 선취.", 12, SUB))
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
	var size_k := 1.0
	if sid >= 0 and m != null:
		var stz = m.world.get_stone(sid)
		if stz != null:
			size_k = m.world.size_of(stz)
	u *= size_k
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
	draw_set_transform_matrix(base * Transform2D(facing, Vector2.ONE * view_scale * size_k, 0.0, Vector2.ZERO))
	Art.skip_body = true
	var stn0 = m.world.get_stone(sid) if (sid >= 0 and m != null) else null
	Art.draw(self, parts, mside, col, alpha, symbol, true, stn0.ups if stn0 != null and stn0.parts == parts else extra.get("ups", {}))
	Art.skip_body = false
	draw_set_transform_matrix(base)
	if sid >= 0:
		var stn = m.world.get_stone(sid) if m != null else null
		if stn != null and not stn.ups.is_empty():
			draw_set_transform_matrix(Transform2D.IDENTITY)
			var k3 := 0
			for slot3 in PartsData.SLOTS:
				if stn.ups.get(slot3, false):
					_draw_star(self, pc + Vector2(u * 0.95 + k3 * u * 0.55, -u * 0.95), u * 0.32)
					k3 += 1
			draw_set_transform_matrix(base)
	if not Art.is_set_form(parts):
		if not Art.mono and symbol >= 0 and symbol < 8 and puck_vp != null and col == slot_colors[symbol]:
			# 미리 구워 둔 퍽 몸통 + 정면 홈만 따로
			var tile := float(PUCK_TILE)
			var sz := tile * u / PUCK_U
			draw_texture_rect_region(puck_vp.get_texture(), Rect2(-Vector2.ONE * sz * 0.5, Vector2.ONE * sz), Rect2(tile * symbol, 0, tile, tile), Color(1, 1, 1, alpha))
			Art.draw_front_mark(self, Vector2.ZERO, u, facing, alpha, symbol, col)
		else:
			Art.draw_puck_top(self, Vector2.ZERO, u, col, symbol, facing, alpha)
		if Art.ws_set_of(parts) != "":
			draw_set_transform_matrix(base * Transform2D(facing, Vector2.ONE * view_scale * size_k, 0.0, Vector2.ZERO))
			Art.draw_front(self, parts, col, alpha)
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
		box.add_child(_setting_toggle("조준 10초 제한", "시간이 끝나면 차례가 넘어가요", settings["timed"], func(on: bool): settings["timed"] = on))
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
var set_alerts: Array = []     # 개조 공개 뒤에 띄울 세트 완성 알림
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
	# 칸이 좁으면 열을 줄인다 (UI-03: 이름이 세로로 쪼개지지 않게)
	while cols > 2 and cw < 140.0:
		cols -= 1
		cw = (width - 24.0 - 8.0 * (cols - 1)) / cols
	rows = int(ceil(float(n) / cols))
	var ch := 56.0
	var top := 96.0 + (32.0 if not m.world.gimmicks.is_empty() else 0.0) + _parcel_line_h()   # 기믹 칩 아래로
	var r := Rect2(vs.x * 0.5 - width * 0.5, (top if not portrait else 124.0) + dy, width, 46.0 + rows * (ch + 8.0) + 6.0)
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
		# 위 줄: 색 점 + 이름, 오른쪽에 부품 그림 · 아래 줄: 부품 이름 (칸 폭 전체)
		draw_circle(Vector2(cx + 14, cy + 17), 7, Color(Art.outline, a))
		draw_circle(Vector2(cx + 14, cy + 17), 6, Color(pl.color, a))
		draw_string(font, Vector2(cx + 26, cy + 22), pl.name, HORIZONTAL_ALIGNMENT_LEFT, cw - 60, 12, Color(SUB, a))
		var pid_part: String = pk.get("id", "")
		if pid_part != "":
			var demo := {"weapon": "", "aux": "", "prop": ""}
			demo[PartsData.slot_of(pid_part)] = pid_part
			draw_set_transform(Vector2(cell.end.x - 22, cy + 18), -PI / 2.0, Vector2.ONE * 0.36)
			Art.draw(self, demo, 1, Art.NEUTRAL, a, -1)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		var lines := _wrap(str(pk["part"]), font_bold, 13, cw - 16)
		var ln0: String = lines[0] if not lines.is_empty() else ""
		if lines.size() > 1:
			ln0 = ln0.trim_suffix(" ") + "…"
		draw_string(font_bold, Vector2(cx + 8, cy + 44), ln0, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(TEXT, a))


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
	Art.skin = m.workshop if (m != null and state != "setup" and settings.get("skins", false)) else ""
	var pkey := theme_id + Art.skin + str(slot_colors) + str(Art.slot_symbols) + str(Art.slot_forms)
	if pkey != _puck_key:
		_puck_key = pkey
		puck_drawer.queue_redraw()
		puck_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_arena_cache() -> void:
	var vs := get_viewport_rect().size
	Arena.background(arena_drawer, Rect2(-Vector2.ONE * 8.0, vs + Vector2.ONE * 16.0), th, time)
	if m != null:
		var w := m.world
		Arena.board(arena_drawer, view_center, w.size * view_scale, CELL * view_scale, w.shape != "circle", th, time)
		if m.mode == "parcel":
			_draw_parcel_halves(arena_drawer, view_center, w.size * view_scale, CELL * view_scale)
			for t in 2:
				var lp := view_center + Vector2((-0.48 if t == 0 else 0.48) * w.size * view_scale, -0.62 * w.size * view_scale)
				arena_drawer.draw_string(font_display, lp - Vector2(80, 0), "%s 진영" % Match.TEAM_NAMES[t], HORIZONTAL_ALIGNMENT_CENTER, 160, 18, Color(Match.TEAM_COLORS[t].darkened(0.2), 0.7))


## HUD 퍽 아이콘: 구워 둔 퍽 그림을 작게 붙인다.
func _hud_icon(center: Vector2, size: float, col: Color, symbol: int, alpha := 1.0) -> void:
	if puck_vp == null or symbol < 0 or symbol >= 8 or col != slot_colors[symbol]:
		Art.draw_icon(self, center, size, col, symbol, alpha)
		return
	var u := size * 0.5 * 0.86
	Art.draw_puck_shadow(self, center, u, alpha)
	var tile := float(PUCK_TILE)
	var sz := tile * u / PUCK_U
	draw_texture_rect_region(puck_vp.get_texture(), Rect2(center + Vector2(0, -0.08 * u) - Vector2.ONE * sz * 0.5, Vector2.ONE * sz), Rect2(tile * symbol, 0, tile, tile), Color(1, 1, 1, alpha))
	Art.draw_front_mark(self, center + Vector2(0, -0.08 * u), u, -PI / 2.0, alpha, symbol, col)


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
	var y := (104.0 + (30.0 if not m.world.gimmicks.is_empty() else 0.0) + _parcel_line_h()) if not portrait else 130.0
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
			"gwell":
				for it in g["items"]:
					var cw := w2s(it["pos"])
					var rw: float = float(it["r"]) * k
					draw_circle(cw, rw, Color("6A50B8", 0.16))
					for arm in 4:
						var pts := PackedVector2Array()
						for i in 18:
							var t := float(i) / 17.0
							var a := time * 1.2 + arm * TAU / 4.0 + t * 3.2
							pts.append(cw + Vector2.from_angle(a) * rw * (1.0 - t * 0.9))
						draw_polyline(pts, Color("B7A2FF", 0.55), 2.0, true)
					draw_circle(cw, rw * 0.12, Color("2A1A55", 0.9))
					draw_arc(cw, rw, 0, TAU, 48, Color("B7A2FF", 0.35), 1.5, true)
			"twins":
				for it in g["items"]:
					var ct := w2s(it["pos"])
					var rt: float = float(it["r"]) * k
					draw_circle(ct, rt, Color("2A2463", 0.55))
					draw_arc(ct, rt, 0, TAU, 32, Color("C9D5FF", 0.9), 2.5, true)
					draw_arc(ct, rt * 0.65, time, time + TAU * 0.75, 20, Color("C9D5FF", 0.7), 1.5, true)
					var tri := PackedVector2Array()
					for i in 4:
						tri.append(ct + Vector2.from_angle(-PI / 2.0 + TAU * i / 3.0 - time * 0.6) * rt * 0.5)
					draw_polyline(tri, Color("C9D5FF", 0.8), 1.5, true)
			"meteor":
				for it in g["items"]:
					var cm := w2s(it["pos"])
					var rm: float = float(it["r"]) * k
					var pulse := 0.5 + 0.5 * sin(time * 5.0)
					draw_circle(cm, rm, Color("FF4F4F", 0.12 + 0.06 * pulse))
					var segs := 24
					for i in segs:
						var a0 := TAU * i / segs + time * 0.5
						draw_arc(cm, rm, a0, a0 + TAU / segs * 0.55, 3, Color("FF5A5A", 0.9), 2.5, true)
					_text_outline(cm + Vector2(0, 6), "!", 22, Color("FF5A5A"), true)
				for h in g.get("hits", []):
					if not h.has("t"):
						h["t"] = time
						snd.play("puck_hit_heavy", 2.0, 0.6)
						shake = maxf(shake, 6.0)
					var ht: float = time - float(h["t"])
					if ht < 0.8:
						var hp := w2s(h["pos"])
						draw_circle(hp, (40.0 + 140.0 * ht) * k, Color("FFB347", 0.5 * (1.0 - ht / 0.8)))
						_text_outline(hp + Vector2(0, -40), "별똥별!", 22, Color("FFD27A", 1.0 - ht / 0.8), true)
			"cutline":
				for it in g["items"]:
					var n3: Vector2 = it["n"]
					var along: Vector2 = n3.orthogonal()
					var L := m.world.size * 2.2
					var seg := Arena.clip_segment(w2s(it["pos"] - along * L), w2s(it["pos"] + along * L), view_center + shake_off, m.world.size * view_scale, m.world.shape != "circle")
					if seg.is_empty():
						continue
					var cnt := 22
					for i in cnt:
						var q: Vector2 = seg[0].lerp(seg[1], (i + 0.5) / cnt)
						var ln := (18.0 + 14.0 * absf(sin(i * 1.7))) * k
						draw_line(q + n3 * 4.0, q + n3 * ln, Color("111111", 0.45), 1.5, true)
					draw_line(seg[0], seg[1], Color("111111", 0.9), 5.0, true)
			"blocks":
				for it in g["items"]:
					var cb := w2s(it["pos"])
					var rb: float = float(it["r"]) * k
					var rr := Rect2(cb - Vector2(rb, rb * 0.85), Vector2(rb * 2.0, rb * 1.7))
					draw_rect(Rect2(rr.position + Vector2(4, 4), rr.size), Color("111111"))
					draw_rect(rr, Color("FFFDF6"))
					draw_rect(rr, Color("111111"), false, 2.5)
					draw_string(font_display, Vector2(rr.position.x, rr.position.y + rr.size.y * 0.78), str(it["word"]), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, int(rb * 1.25), Color("E04E3A"))
					if int(it["hp"]) <= 1:
						draw_polyline(PackedVector2Array([rr.position + Vector2(rr.size.x * 0.2, 0), rr.get_center(), rr.position + Vector2(rr.size.x * 0.7, rr.size.y)]), Color("111111"), 2.0, true)
			"nextch":
				for it in g["items"]:
					var a1: float = float(it["ang"]) - float(it["half"])
					var a2: float = float(it["ang"]) + float(it["half"])
					var Rn := m.world.size * view_scale
					var c0 := view_center + shake_off
					for side in [0.0, PI]:
						draw_arc(c0, Rn + 6.0, a1 + side, a2 + side, 24, Color("E04E3A", 0.9), 10.0, false)
						var stripes := 10
						for i in stripes:
							var aa: float = lerpf(a1, a2, (i + 0.5) / stripes) + side
							draw_line(c0 + Vector2.from_angle(aa) * (Rn + 1.0), c0 + Vector2.from_angle(aa + 0.03) * (Rn + 11.0), Color.WHITE, 2.0, true)
					var lp := c0 + Vector2.from_angle(float(it["ang"])) * (Rn - 26.0)
					_text_outline(lp, "다음 화에 계속", 13, Color("E04E3A"), true)
			"zerog":
				for it in g["items"]:
					var cz := w2s(it["pos"])
					var rz: float = float(it["r"]) * k
					draw_circle(cz, rz, Color("9BE7FF", 0.18))
					draw_arc(cz, rz, 0, TAU, 48, Color("6BC8FF", 0.6), 2.0, true)
					for i in 7:
						var bp := cz + Vector2.from_angle(i * 2.4 + time * 0.4) * rz * (0.25 + 0.1 * i) + Vector2(0, -fmod(time * 12.0 + i * 9.0, 20.0))
						draw_arc(bp, 3.0 + i % 3, 0, TAU, 10, Color("6BC8FF", 0.7), 1.2, true)
			"sizering":
				for it in g["items"]:
					var cs := w2s(it["pos"])
					var rs: float = float(it["r"]) * k
					var rc: Color = Color("E0533D") if it["big"] else Color("3D6FD1")
					draw_arc(cs, rs, 0, TAU, 32, rc, 6.0, true)
					draw_arc(cs, rs * 0.7, 0, TAU, 32, Color(rc, 0.4), 2.0, true)
					_text_outline(cs + Vector2(0, 6), "커짐" if it["big"] else "작아짐", 12, rc, true)
			"pendulum", "clockhand", "cuckoo":
				_draw_clock_gimmick(g)
			"turntable":
				for it in g["items"]:
					var ctt := w2s(it["pos"])
					var rtt: float = float(it["r"]) * k
					draw_circle(ctt, rtt, Color(0.85, 0.88, 0.9, 0.55))
					var teeth := 24
					for i in teeth:
						var ta := float(it["ang"]) + TAU * i / teeth
						draw_line(ctt + Vector2.from_angle(ta) * rtt, ctt + Vector2.from_angle(ta) * (rtt + 7.0), Color("3A3F45"), 3.0, true)
					draw_arc(ctt, rtt, 0, TAU, 64, Color("3A3F45"), 2.0, true)
					for i in 4:
						var sa := float(it["ang"]) + PI / 2.0 * i
						draw_line(ctt + Vector2.from_angle(sa) * rtt * 0.2, ctt + Vector2.from_angle(sa) * rtt * 0.85, Color(0, 0, 0, 0.12), 2.0, true)
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
	# 바퀴 표시줄 바로 아래 가운데 (UI-02: 오른쪽 위 버튼과 겹치지 않게)
	var widths: Array = []
	var total := 0.0
	for g0 in m.world.gimmicks:
		var w0 := font_semi.get_string_size(World.Gm.name_of(g0["kind"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34.0
		widths.append(w0)
		total += w0 + 6.0
	var x := vs.x * 0.5 - (total - 6.0) * 0.5
	var mouse := get_local_mouse_position()
	var shown := -1
	gimmick_rects.clear()
	for i in m.world.gimmicks.size():
		var g: Dictionary = m.world.gimmicks[i]
		var nm := World.Gm.name_of(g["kind"])
		var w: float = widths[i]
		var r := Rect2(x, GIMMICK_CHIP_Y + _parcel_line_h(), w, 28)
		gimmick_rects.append(r)
		_round_rect(r, Color(SOLID, 0.95), 15, ACCENT)
		draw_circle(r.position + Vector2(15, 14), 6, ACCENT)
		draw_string(font_semi, r.position + Vector2(26, 19), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		if r.has_point(mouse) or gimmick_tip == i:
			shown = i
			var desc: String = World.Gm.INFO.get(g["kind"], {}).get("desc", "")
			var dw := font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
			var dr := Rect2(minf(r.position.x, vs.x - dw - 12), r.end.y + 6, dw, 30)
			_round_rect(dr, Color(SOLID, 0.98), 8, PANEL_LINE)
			draw_string(font, dr.position + Vector2(12, 20), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		x += w + 6.0



const GIMMICK_CHIP_Y := 92.0
var gimmick_rects: Array = []


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


func _up_targets(pid: int, card: String) -> Array:
	var base := PartsData.base_of(card)
	var slot := PartsData.slot_of(card)
	var out: Array = []
	for st in m.world.alive_stones_of(pid):
		if st.parts[slot] == base and not st.ups.get(slot, false):
			out.append(st)
	return out


func _draw_star(ci: CanvasItem, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * rr)
	ci.draw_colored_polygon(pts, Color("F2C94C"))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color("5A3A10"), maxf(1.0, r * 0.14), true)


## 연구소: 셔터 대신 실험실 문이 좌우로 열린다.
func _draw_lab_doors(vs: Vector2) -> void:
	var k := _intro_k()
	var half := vs.x * 0.5
	var off := half * 1.02 * k
	for side in [-1, 1]:
		var x0: float = (0.0 - off) if side < 0 else (half + off)
		var r := Rect2(x0, 0, half, vs.y)
		shutter.draw_rect(r, Color("EEF2F3"))
		shutter.draw_rect(Rect2(r.position.x, vs.y * 0.18, half, 18), Color("B6F23C"))
		shutter.draw_rect(Rect2(r.position.x, vs.y * 0.82, half, 18), Color("B6F23C"))
		var edge: float = r.end.x - 6.0 if side < 0 else r.position.x
		shutter.draw_rect(Rect2(edge, 0, 6, vs.y), Color("1A1D21"))
		shutter.draw_circle(Vector2(edge + (-30.0 if side < 0 else 36.0), vs.y * 0.5), 10, Color("8A929C"))
	if m == null:
		return
	var info: Dictionary = PartsData.WORKSHOPS["lab"]
	var nm: String = info["name"]
	var bw := font_display.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x + 60.0
	var box := Rect2(vs.x * 0.5 - bw * 0.5, vs.y * 0.5 - 60, bw, 120)
	var a := 1.0 - k
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, a)
	sb.border_color = Color(0.71, 0.95, 0.24, a)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.draw(shutter.get_canvas_item(), box)
	shutter.draw_string(font_bold, Vector2(box.position.x, box.position.y + 30), "오늘의 공방 · 출입 주의", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 14, Color(0.37, 0.56, 0.05, a))
	shutter.draw_string(font_display, Vector2(box.position.x, box.position.y + 82), nm, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 44, Color(0.09, 0.1, 0.11, a))
	var gn: Array = []
	for g in m.world.gimmicks:
		gn.append(World.Gm.name_of(g["kind"]))
	if not gn.is_empty():
		shutter.draw_string(font_semi, Vector2(box.position.x, box.end.y + 30), "맵 기믹 · " + " · ".join(gn), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 16, Color(0.09, 0.1, 0.11, a))


## 투지 표시: 불꽃 세 칸. 다 차고 세트가 완성되면 빛나며 「라스트 컷 준비」.
func _draw_grit(c: Vector2, g: int, ready: bool, k: float) -> void:
	var gap := 14.0 * k
	for i in 3:
		var fc := c + Vector2((i - 1) * gap, 0)
		var lit := i < g
		var h := 9.0 * k
		var pts := PackedVector2Array([fc + Vector2(0, -h), fc + Vector2(h * 0.55, -h * 0.1), fc + Vector2(h * 0.45, h * 0.55), fc + Vector2(0, h * 0.75), fc + Vector2(-h * 0.45, h * 0.55), fc + Vector2(-h * 0.55, -h * 0.1)])
		if lit:
			if ready:
				draw_circle(fc, h * (1.1 + 0.15 * sin(time * 8.0)), Color("FFB347", 0.35))
			draw_colored_polygon(pts, Color("F08A3C"))
			draw_circle(fc + Vector2(0, h * 0.25), h * 0.28, Color("FFD27A"))
		pts.append(pts[0])
		draw_polyline(pts, Color("5A2A10") if lit else Color(0.5, 0.5, 0.5, 0.7), maxf(1.0, 1.4 * k), true)
	if ready and k >= 1.0:
		_text_outline(c + Vector2(0, -16), "라스트 컷 준비", 12, Color("F08A3C"), true)


# ── 공방 입장 (디자인 「입장 · 마법 상점」「입장 · 만화 창고」) ──
# 고물 정비소: 셔터가 위로 · 마법 상점: 커튼이 양옆으로 · 만화 창고: 표지가 넘어감 · 연구소: 문이 좌우로
const INTRO_CLOSED := 1.3   # 닫힌 화면
const INTRO_OPEN := 0.9     # 열리는 시간. 누르면 바로 열린다
var match_no := 0           # 오늘 몇 판째 (만화 창고 표지의 「제 N화」)
var intro_opened := false


func _intro_k() -> float:
	if shutter_t <= INTRO_CLOSED:
		return 0.0
	var e := clampf((shutter_t - INTRO_CLOSED) / INTRO_OPEN, 0.0, 1.0)
	return e * e * e * (e * (6.0 * e - 15.0) + 10.0)


## 입장 화면을 누르면 바로 열린다.
func _skip_intro() -> bool:
	if shutter_t < 0.0 or shutter_t >= INTRO_CLOSED:
		return false
	shutter_t = INTRO_CLOSED
	turn_hold = minf(turn_hold, INTRO_OPEN)
	_intro_open_sound()
	return true


func _intro_sounds() -> void:
	intro_opened = false
	var ws: String = m.workshop if m != null else ""
	if ws == "magic":
		# 딸랑 종소리 세 음
		var pitches := [1.5, 1.68, 2.0]
		for i in 3:
			var pt: float = pitches[i]
			get_tree().create_timer(0.12 + 0.16 * i).timeout.connect(func(): snd.play("set_progress", -6.0, pt))
	elif ws == "toon":
		snd.play("flick_pull", -5.0, 1.35)   # 종이 펄럭
	elif ws == "clock":
		for i in 4:
			get_tree().create_timer(0.2 + 0.28 * i).timeout.connect(func(): snd.play("timer_tick", -8.0, 0.9))   # 째깍
	elif ws == "pirate":
		snd.play("puck_slide_loop", -10.0, 0.5)   # 파도
	get_tree().create_timer(INTRO_CLOSED).timeout.connect(_intro_open_sound)


func _intro_open_sound() -> void:
	if m == null or intro_opened or shutter_t < 0.0:
		return
	intro_opened = true
	match m.workshop:
		"magic":
			snd.play("flick_pull", -6.0, 0.55)   # 천 스치는 소리
		"clock":
			snd.play("set_complete", -2.0, 0.55)   # 댕
		"pirate":
			snd.play("flick_pull", -4.0, 0.6)   # 돛이 부풀고 날아감
		"toon":
			snd.play("flick_release", -2.0, 0.6)  # 책장 넘기는 소리와 쿵
			get_tree().create_timer(0.35).timeout.connect(func(): snd.play("fx_parody_stamp", -4.0, 0.8))


## 마법 상점: 별이 박힌 보라 벨벳 커튼이 양옆으로 걷히고, 위쪽 주름 장식이 올라간다.
func _draw_magic_curtain(vs: Vector2) -> void:
	var k := _intro_k()
	var half := vs.x * 0.5
	var pleat := 26.0
	var val_h := 34.0
	for side in [-1, 1]:
		# 주름이 접히며 가장자리로 몰리고, 끝에는 화면 밖으로 빠진다
		var w: float = half * lerpf(1.0, 0.16, minf(1.0, k * 1.35))
		var slide: float = w * 1.05 * clampf((k - 0.55) / 0.45, 0.0, 1.0)
		var x0: float = (0.0 - slide) if side < 0 else (vs.x - w + slide)
		var n := int(ceil(half / pleat))
		var pw: float = w / float(n)
		for i in n:
			var px: float = x0 + i * pw
			var shade := Color("3B2477") if i % 2 == 0 else Color("4E3196")
			shutter.draw_rect(Rect2(px, 0, pw + 0.5, vs.y), shade)
			shutter.draw_rect(Rect2(px + pw * 0.35, 0, pw * 0.3, vs.y), Color("5C3DAE", 0.55))
			shutter.draw_rect(Rect2(px, 0, 2.0, vs.y), Color("23154A", 0.7))
			var sy := 30.0 + (i % 2) * 22.0
			while sy < vs.y - 20.0:
				shutter.draw_circle(Vector2(px + pw * 0.5, sy), 1.4, Color("E9DFFF", 0.75))
				sy += 44.0
		# 가운데 맞닿는 곳 그림자
		var inner: float = (x0 + w - 10.0) if side < 0 else x0
		shutter.draw_rect(Rect2(inner, 0, 10, vs.y), Color(0.08, 0.04, 0.18, 0.45))
		# 아래 금색 술 장식
		var fy := vs.y - 14.0
		shutter.draw_rect(Rect2(x0, fy, w, 14), Color("B8913F"))
		var fx0: float = x0
		while fx0 < x0 + w:
			shutter.draw_line(Vector2(fx0, fy + 2), Vector2(fx0, vs.y), Color("E3C26E"), 1.5)
			fx0 += 4.0
	# 위쪽 주름 장식 (물결 테두리): 열리면 위로 올라간다
	var vy := -val_h * 1.6 * k
	shutter.draw_rect(Rect2(0, vy, vs.x, val_h), Color("2A1A5C"))
	var bx := 0.0
	while bx < vs.x:
		shutter.draw_circle(Vector2(bx + 14.0, vy + val_h), 14.0, Color("2A1A5C"))
		bx += 28.0
	shutter.draw_rect(Rect2(0, vy + val_h - 4, vs.x, 3), Color("B8913F", 0.7))
	if m == null:
		return
	# 간판: 흐려지며 위로 떠오른다
	var a := 1.0 - clampf(k * 1.6, 0.0, 1.0)
	if a <= 0.01:
		return
	var info: Dictionary = PartsData.WORKSHOPS["magic"]
	var nm: String = info["name"]
	var names: Array = []
	for pid in info["rep"]:
		names.append(PartsData.part_name(pid))
	var bw := maxf(font_display.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x, font.get_string_size(" · ".join(names), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x) + 64.0
	var box := Rect2(vs.x * 0.5 - bw * 0.5, vs.y * 0.5 - 62 - 50.0 * k, bw, 124)
	for g in 4:
		var sbg := StyleBoxFlat.new()
		sbg.bg_color = Color(0.72, 0.62, 1.0, 0.07 * a)
		sbg.set_corner_radius_all(12 + g * 5)
		sbg.draw(shutter.get_canvas_item(), box.grow(4.0 + g * 5.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.2, 0.96 * a)
	sb.border_color = Color(0.72, 0.62, 1.0, a)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.draw(shutter.get_canvas_item(), box)
	var sub := "오늘의 공방" + _mode_suffix()
	shutter.draw_string(font_bold, Vector2(box.position.x, box.position.y + 28), sub, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, Color(0.78, 0.7, 1.0, a))
	shutter.draw_string(font_display, Vector2(box.position.x, box.position.y + 78), nm, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 44, Color(0.97, 0.96, 1.0, a))
	shutter.draw_string(font, Vector2(box.position.x, box.position.y + 106), " · ".join(names), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 14, Color(0.8, 0.78, 0.92, a))
	_draw_intro_gimmicks(vs, box.end.y + 28.0, Color(0.72, 0.62, 1.0, a), Color(0.09, 0.07, 0.2, a))


## 만화 창고: 잡지 표지가 덮고 있다가 왼쪽을 축으로 책장처럼 넘어간다. 「제 N화」 = 오늘 몇 판째.
func _draw_manga_cover(vs: Vector2) -> void:
	var k := _intro_k()
	if k >= 0.999:
		return
	var ang := k * PI * 0.5
	var c := cos(ang)
	# 왼쪽 축으로 넘어가며 오른쪽 끝이 살짝 들린다
	shutter.draw_set_transform_matrix(Transform2D(Vector2(c, -0.14 * sin(ang)), Vector2(0, 1), Vector2.ZERO))
	var r := Rect2(Vector2.ZERO, vs)
	shutter.draw_rect(r, Color("F6F3EC"))
	# 집중선: 한가운데 커다란 알을 향해
	var center := Vector2(vs.x * 0.62, vs.y * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var far := vs.length()
	var page := PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)])
	for i in 84:
		var t := TAU * i / 84.0 + rng.randf_range(-0.02, 0.02)
		var inner := rng.randf_range(100.0, 170.0)
		var w0 := rng.randf_range(0.006, 0.017)
		var p1 := center + Vector2.from_angle(t) * inner
		var p2 := center + Vector2.from_angle(t - w0) * far
		var p3 := center + Vector2.from_angle(t + w0) * far
		# 표지 밖으로 나가지 않게 자른다
		for piece in Geometry2D.intersect_polygons(PackedVector2Array([p1, p2, p3]), page):
			shutter.draw_colored_polygon(piece, Color("15171A"))
	var me: int = int(my_seats[0]) if not my_seats.is_empty() else 0
	var col := Color("E0533D")
	if m != null and me < m.players.size():
		col = m.players[me].color
	var pr := minf(vs.y * 0.13, 70.0)
	shutter.draw_circle(center + Vector2(4, 10), pr, Color(0, 0, 0, 0.3))
	Art.draw_puck_top(shutter, center, pr, col, me, -PI / 2.0, 1.0)
	# 빨간 테두리
	shutter.draw_rect(r.grow(-6), Color("D2452F"), false, 12.0)
	# 제목 상자
	if m != null:
		var info: Dictionary = PartsData.WORKSHOPS["toon"]
		var nm: String = info["name"]
		var names: Array = []
		for pid in info["rep"]:
			names.append(PartsData.part_name(pid))
		var sub := "오늘의 공방 특별 연재 · " + " · ".join(names)
		if m.mode != "survival":
			sub = _mode_suffix().trim_prefix("  ·  ") + " · " + sub
		var bw := maxf(font_display.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x, font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 36.0
		bw = minf(bw, maxf(vs.x * 0.5, 240.0))
		var box := Rect2(maxf(24.0, vs.x * 0.08), vs.y * 0.5 - 70, bw, 132)
		shutter.draw_rect(Rect2(box.position + Vector2(6, 6), box.size), Color("15171A"))
		shutter.draw_rect(box, Color("FFFFFF"))
		shutter.draw_rect(box, Color("15171A"), false, 3.0)
		var tag := "제 %d화" % match_no
		var tw := font_bold.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0
		shutter.draw_rect(Rect2(box.position + Vector2(16, 14), Vector2(tw, 22)), Color("15171A"))
		shutter.draw_string(font_bold, box.position + Vector2(24, 30), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		shutter.draw_string(font_display, box.position + Vector2(16, 84), nm, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28, 40, Color("15171A"))
		shutter.draw_string(font, box.position + Vector2(16, 114), sub, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28, 12, Color("3A3D42"))
		_draw_intro_gimmicks(vs, box.end.y + 30.0, Color("15171A"), Color("FFFFFF"), box.get_center().x)
	# 넘어가며 어두워진다
	if k > 0.0:
		shutter.draw_rect(r, Color(0, 0, 0, 0.55 * k))
	shutter.draw_set_transform_matrix(Transform2D.IDENTITY)
	if k > 0.0:
		shutter.draw_rect(Rect2(vs.x * c, 0, 18.0, vs.y), Color(0, 0, 0, 0.25 * (1.0 - k)))


## 입장 화면의 맵 기믹 알림 (있을 때만).
func _draw_intro_gimmicks(vs: Vector2, gy: float, bg: Color, fg: Color, cx := -1.0) -> void:
	if m == null or m.world.gimmicks.is_empty():
		return
	var gn: Array = []
	for g in m.world.gimmicks:
		gn.append(World.Gm.name_of(g["kind"]))
	var gt := "맵 기믹 · " + " · ".join(gn)
	var gw := font_bold.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 36.0
	if cx < 0.0:
		cx = vs.x * 0.5
	var gr := Rect2(cx - gw * 0.5, gy, gw, 34)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = bg
	sb2.set_corner_radius_all(17)
	sb2.draw(shutter.get_canvas_item(), gr)
	shutter.draw_string(font_bold, Vector2(gr.position.x, gr.position.y + 23), gt, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 15, fg)


## 리모컨: 내 차례에 리모컨 단 알이 있으면 조종할 수 있는 상대 알을 점선 고리로 보여 준다.
var remote_pick := -1


func _remote_targets(holder_id: int) -> Array:
	var out: Array = []
	if m == null:
		return out
	var h = m.world.get_stone(holder_id)
	if h == null or not h.alive or h.parts.get("weapon", "") != "remote":
		return out
	for o in m.world.stones:
		if o.alive and o.owner != h.owner and m.remote_holder(h.owner, o) == h:
			out.append(o.id)
	return out


func _draw_remote_marks() -> void:
	if m == null or m.phase != "aim" or not _is_mine(m.current_player()) or drag_stone >= 0:
		if m != null and m.phase != "aim":
			remote_pick = -1
		return
	for h in m.world.alive_stones_of(m.current_player()):
		if h.parts.get("weapon", "") != "remote":
			continue
		var tg := _remote_targets(h.id)
		if tg.is_empty():
			continue
		var on: bool = remote_pick == h.id
		var hp: Vector2 = w2s(h.pos)
		var col := Color(ACCENT, 1.0 if on else 0.55)
		if on:
			draw_arc(hp, (World.STONE_R + 9) * view_scale, 0, TAU, 40, ACCENT, 3.0, true)
		for tid in tg:
			var t = m.world.get_stone(tid)
			var tp := w2s(t.pos)
			var rr := (World.STONE_R * m.world.size_of(t) + 8 + (2.0 * sin(time * 6.0) if on else 0.0)) * view_scale
			var segs := 16
			for i in segs:
				if i % 2 == 0:
					draw_arc(tp, rr, TAU * i / segs + time * 0.6, TAU * (i + 1) / segs + time * 0.6, 4, col, 2.5 if on else 1.8, true)
			if on:
				draw_dashed_line(hp, tp, Color(ACCENT, 0.7), 2.0, 8.0)


# ── 왕관 쟁탈전 화면 (디자인 「왕관 쟁탈전 · 경기 화면」「택배·왕관 상태와 알림」) ──
var match_started_t := 0.0
var mode_alerts: Array = []    # 큰 점수 알림 카드 {title, sub, bg, border, ink, t0}
var crown_fly := {}            # 왕관이 포물선을 그리며 날아가는 중 {from, to | stone, t0}
var crown_drop_pos := Vector2.ZERO
const CROWN_FLY_T := 0.45
const ALERT_LIFE := 1.7
const CROWN_GOLD := Color("F2C14E")


func _mode_suffix() -> String:
	if m == null:
		return ""
	return {"derby": "  ·  개조 더비", "crown": "  ·  왕관 쟁탈전", "parcel": "  ·  택배 쟁탈전"}.get(m.mode, "")


## 왕관 아이콘: s = 반 폭
func _draw_crown_icon(ci: CanvasItem, c: Vector2, s: float, a: float, gray := false) -> void:
	var fill := Color("B9BEC6") if gray else CROWN_GOLD
	var ol := Color(0.1, 0.11, 0.13, a)
	var body := PackedVector2Array([c + Vector2(-s, 0.4 * s), c + Vector2(-s, -0.45 * s), c + Vector2(-0.5 * s, 0.02 * s),
		c + Vector2(0, -0.62 * s), c + Vector2(0.5 * s, 0.02 * s), c + Vector2(s, -0.45 * s), c + Vector2(s, 0.4 * s)])
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0.4 * s), c + Vector2(s, 0.4 * s), c + Vector2(s, 0.62 * s), c + Vector2(-s, 0.62 * s)]), Color(fill.darkened(0.15), a))
	ci.draw_colored_polygon(body, Color(fill, a))
	var line := body.duplicate()
	line.append(body[0])
	var lw := maxf(1.2, 0.13 * s)
	ci.draw_polyline(line, ol, lw, true)
	ci.draw_rect(Rect2(c + Vector2(-s, 0.4 * s), Vector2(2 * s, 0.22 * s)), ol, false, lw)
	for tip in [Vector2(-s, -0.45 * s), Vector2(0, -0.62 * s), Vector2(s, -0.45 * s)]:
		ci.draw_circle(c + tip, 0.13 * s, Color(fill.lightened(0.2), a))
		ci.draw_arc(c + tip, 0.13 * s, 0, TAU, 10, ol, maxf(1.0, lw * 0.7), true)
	if not gray:
		ci.draw_circle(c + Vector2(0, 0.12 * s), 0.14 * s, Color("D2452F", a))


func _crown_flying() -> bool:
	return not crown_fly.is_empty() and time - float(crown_fly["t0"]) < CROWN_FLY_T


## 중앙 왕관 자리(금색 점선 원)와 바닥 왕관
func _draw_crown_floor() -> void:
	if m == null or m.world.crown.is_empty() or m.phase == "place":
		return
	var c: Dictionary = m.world.crown
	var home := w2s(Vector2.ZERO)
	var hr := World.Crown.CELL * 1.1 * view_scale
	var segs := 24
	for i in segs:
		if i % 2 == 0:
			draw_arc(home, hr, TAU * i / segs, TAU * (i + 1) / segs, 4, Color(CROWN_GOLD, 0.75), 2.0, true)
	if _crown_flying():
		return
	var u := World.STONE_R * view_scale
	match str(c["state"]):
		"floor":
			var p := w2s(c["pos"])
			draw_circle(p + Vector2(0, u * 0.35), u * 0.75, Color(0, 0, 0, 0.18))
			for k in 4:
				var sp := p + Vector2.from_angle(time * 1.2 + TAU * k / 4.0) * u * 1.15
				_draw_star(self, sp, u * 0.14)
			_draw_crown_icon(self, p + Vector2(0, sin(time * 3.0) * u * 0.06), u * 0.62, 1.0)
		"wait":
			_draw_crown_icon(self, home, u * 0.55, 0.6, true)
			_txt(home + Vector2(0, u * 1.1), "대기", 12, Color(SUB, 0.9), font_semi, 60, HORIZONTAL_ALIGNMENT_CENTER)


## 왕관 보유 알: 금색 고리 + 머리 위 왕관. 빼앗기거나 중앙으로 돌아갈 때는 포물선으로 날아간다.
func _draw_crown_held() -> void:
	if m == null or m.world.crown.is_empty() or m.phase == "place":
		return
	var u := World.STONE_R * view_scale
	if _crown_flying():
		var k := clampf((time - float(crown_fly["t0"])) / CROWN_FLY_T, 0.0, 1.0)
		var to: Vector2 = crown_fly.get("to", Vector2.ZERO)
		if crown_fly.has("stone"):
			var ts = m.world.get_stone(int(crown_fly["stone"]))
			if ts != null:
				to = ts.pos + Vector2(0, -(World.STONE_R + 14.0))
		var a: Vector2 = w2s(crown_fly["from"])
		var b: Vector2 = w2s(to)
		var p := a.lerp(b, k) + Vector2(0, -sin(PI * k) * 70.0 * view_scale)
		# 지나간 자리: 금색 점선
		for j in 6:
			var kj := k * j / 6.0
			draw_circle(a.lerp(b, kj) + Vector2(0, -sin(PI * kj) * 70.0 * view_scale), 2.0, Color(CROWN_GOLD, 0.7))
		_draw_crown_icon(self, p, u * 0.55, 1.0)
		return
	var h = World.Crown.holder_stone(m.world)
	if h == null or not h.alive:
		return
	var p2 := w2s(h.pos)
	var rr := (World.STONE_R * m.world.size_of(h) + 7.0) * view_scale
	draw_arc(p2, rr + 1.5, 0, TAU, 40, Color(0, 0, 0, 0.3), 5.0, true)
	draw_arc(p2, rr, 0, TAU, 40, CROWN_GOLD, 3.0, true)
	var top := p2 + Vector2(0, -(World.STONE_R * m.world.size_of(h) + 12.0 + 2.0 * sin(time * 3.0)) * view_scale)
	_draw_crown_icon(self, top, u * 0.5, 1.0)


func _crown_hint(pid: int) -> String:
	var c: Dictionary = m.world.crown
	var h = World.Crown.holder_stone(m.world)
	if h == null:
		return "가운데 왕관에 직접 닿으면 획득 +1" if c["state"] == "floor" else "왕관이 가운데로 돌아가는 중이에요"
	if h.owner == pid:
		return "왕관을 지키세요 · 남의 차례가 끝날 때마다 +1"
	return "%s의 왕관 알에 직접 부딪히면 강탈" % m.players[h.owner].name


## 위쪽 가운데: 「이번 차례가 끝나면」 누가 몇 점을 얻는지 미리 보여 준다.
func _draw_crown_forecast(vs: Vector2) -> void:
	var c: Dictionary = m.world.crown
	var cur := m.current_player() if m.phase != "draft" else -1
	var h = World.Crown.holder_stone(m.world)
	var title := "이번 차례가 끝나면"
	var sub := ""
	if m.phase == "draft":
		title = "%d바퀴 개조" % m.round_no
		sub = "개조가 끝나면 차례가 시작돼요 · %d점 선취" % m.crown_goal
	elif h == null:
		sub = ("바닥 왕관 · %s 직접 닿고 살아남으면 +1" % _j(m.players[cur].name, "이", "가")) if c["state"] == "floor" and cur >= 0 else "왕관이 가운데로 돌아가요 · 점수 없음"
	elif h.owner == cur:
		var taken: bool = m.phase == "moving" and m.world.shot != null and int(m.world.shot.ex.get("crown_taker", -1)) == cur
		sub = ("살아남으면 %s +1 (획득)" % m.players[cur].name) if taken else ("%s의 왕관 · 이번 차례엔 점수 없음" % m.players[cur].name)
	else:
		sub = "왕관이 그대로면 %s +1 (방어)" % m.players[h.owner].name
	var w := maxf(font_bold.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 84.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 24, w, 60)
	_panel(r)
	_draw_crown_icon(self, r.position + Vector2(34, 31), 15.0, 1.0)
	_txt(r.position + Vector2(62, 26), title, 15, TEXT, font_bold)
	_txt(r.position + Vector2(62, 46), sub, 12, SUB, font)


## 차례 목록 한 줄 (왕관 쟁탈전): 보유자는 금색으로, 오른쪽에 5칸 점수 막대와 점수.
func _draw_crown_row(row: Rect2, pid: int, x: float, cy: float, a: float, is_cur: bool, i: int) -> void:
	var p: Dictionary = m.players[pid]
	var h = World.Crown.holder_stone(m.world)
	if h != null and h.owner == pid:
		_round_rect(row, Color(CROWN_GOLD, 0.16), 8)
		_draw_crown_icon(self, Vector2(x + 10, cy - 1), 9.0, a)
	var right := row.end.x - 8
	var score: int = m.scores[pid]
	_txt(Vector2(right, cy + 6), "%d" % score, 16, Color(TEXT, a), font_bold, 30, HORIZONTAL_ALIGNMENT_RIGHT)
	var bw := 11.0
	var x0 := right - 22.0 - m.crown_goal * (bw + 3.0)
	for k in m.crown_goal:
		var br := Rect2(x0 + k * (bw + 3.0), cy - bw * 0.5, bw, bw)
		draw_rect(br, Color(p.color, a) if k < score else Color(FG, 0.12 * a))
		draw_rect(br, Color(0.1, 0.1, 0.12, 0.7 * a), false, 1.2)
	var tag := ""
	if is_cur:
		tag = "지금"
	elif i == 1 and m.phase != "draft":
		tag = "다음"
	if tag != "" and not portrait:
		_txt(Vector2(x0 - 6, cy + 4), tag, 12, HINT_GOLD if tag == "지금" else SUB, font_semi, 40, HORIZONTAL_ALIGNMENT_RIGHT)


func _on_crown_event(e: Dictionary) -> void:
	var u := World.STONE_R
	match str(e.get("kind", "")):
		"take":
			fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -44), "t": 0.0, "life": 1.0, "text": "왕관!", "c": CROWN_GOLD, "size": 22})
			for k in 10:
				fx.append({"k": "spark", "pos": e["pos"], "vel": Vector2.from_angle(TAU * k / 10.0) * randf_range(80.0, 140.0), "t": 0.0, "life": 0.4, "c": CROWN_GOLD})
			snd.play("set_progress", -4.0, 1.3)
		"steal":
			# 강탈 순간엔 「강탈!」만. 점수는 샷이 끝나고 살아남은 걸 확인한 뒤에.
			fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -48), "t": 0.0, "life": 1.0, "text": "강탈!", "c": Color("E0533D"), "size": 26})
			crown_fly = {"from": e["from"] + Vector2(0, -(u + 14.0)), "stone": int(e["stone"]), "t0": time}
			snd.play("fx_parody_stamp", -3.0, 1.1)
		"drop":
			crown_drop_pos = e["pos"]
			fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -40), "t": 0.0, "life": 1.0, "text": "왕관 추락", "c": Color("B9BEC6"), "size": 18})
		"home":
			crown_fly = {"from": crown_drop_pos, "to": e["pos"], "t0": time}
			_push_alert("왕관 추락", "중앙으로 복귀", Color("ECE7DD"), Color("8A8F96"), Color("4A4E55"))


## 경기 관리가 쌓은 점수(획득·방어)를 큰 알림으로
func _take_crown_scores() -> void:
	if m == null or m.crown_events.is_empty():
		return
	for ev in m.crown_events:
		var pl: Dictionary = m.players[int(ev["pid"])]
		var sc: int = m.scores[pl.id]
		if ev["kind"] == "gain":
			_push_alert("왕관 획득!", "%s +1" % pl.name, Color("FFF1C2"), Color("E9B935"), Color("8A5A12"))
			_log("%s 왕관 획득 +1 (%d점)" % [_j(pl.name, "이", "가"), sc], pl.color)
		else:
			_push_alert("왕관 방어!", "%s +1" % pl.name, pl.color.lerp(Color.WHITE, 0.8), pl.color, pl.color.darkened(0.35))
			_log("%s 왕관을 지켜 +1 (%d점)" % [_j(pl.name, "이", "가"), sc], pl.color)
		snd.play("set_progress", -3.0, 1.15)
	m.crown_events.clear()


func _push_alert(title: String, sub: String, bg: Color, border: Color, ink: Color) -> void:
	var t0 := time
	for al in mode_alerts:
		t0 = maxf(t0, float(al["t0"]) + ALERT_LIFE * 0.7)
	mode_alerts.append({"title": title, "sub": sub, "bg": bg, "border": border, "ink": ink, "t0": t0})


## 큰 알림 카드: 살짝 기울어 튀어나왔다가 사라진다.
func _draw_mode_alerts(vs: Vector2) -> void:
	var keep: Array = []
	for al in mode_alerts:
		var age := time - float(al["t0"])
		if age > ALERT_LIFE:
			continue
		keep.append(al)
		if age < 0.0:
			continue
		var k := clampf(age / 0.18, 0.0, 1.0)
		var sc := 1.0 if _reduced() else 0.7 + 0.3 * _ease_back(k)
		var a := clampf((ALERT_LIFE - age) / 0.3, 0.0, 1.0)
		var tw := font_display.get_string_size(al["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var w := maxf(tw, 120.0) + 56.0
		var c := Vector2(vs.x * 0.5, vs.y * 0.34)
		draw_set_transform(c, -0.05, Vector2.ONE * sc)
		var box := Rect2(-w * 0.5, -40, w, 80)
		_round_rect(Rect2(box.position + Vector2(4, 6), box.size), Color(0, 0, 0, 0.25 * a), 12)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(al["bg"], a)
		sb.border_color = Color(al["border"], a)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.draw(get_canvas_item(), box)
		var ink: Color = al["ink"]
		draw_string(font_display, Vector2(-w * 0.5, 6), al["title"], HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color(ink, a))
		draw_string(font_bold, Vector2(-w * 0.5, 30), al["sub"], HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(ink, a))
		draw_set_transform_matrix(Transform2D.IDENTITY)
	mode_alerts = keep


# ── 택배 쟁탈전: 로비 (디자인 「모드 고르기와 팀 나누기」) ──
const PARCEL_RED_BG := Color("F3B3A8")
const PARCEL_RED_LINE := Color("EE9A8C")
const PARCEL_BLUE_BG := Color("B5C8F0")
const PARCEL_BLUE_DOT := Color("93AEE6")


## 팀전은 4·6·8인만. 다른 인원이면 가까운 짝수로 맞추고 팀을 반반으로.
func _fix_parcel_count() -> void:
	var n: int = settings["n"]
	if not [4, 6, 8].has(n):
		settings["n"] = clampi(n + (n % 2), 4, 8)
		settings["timed"] = settings["n"] >= 5
	_balance_teams()


func _balance_teams() -> void:
	var n: int = settings["n"]
	var cnt := [0, 0]
	for i in n:
		cnt[int(settings["teams"][i])] += 1
	if cnt[0] != cnt[1]:
		for i in 8:
			settings["teams"][i] = i % 2


func _team_label(i: int) -> String:
	var t: int = int(settings["teams"][i])
	var k := 1
	for j in i:
		if int(settings["teams"][j]) == t:
			k += 1
	return "%s %d" % [Match.TEAM_NAMES[t], k]


## 팀 나누기: 두 칸. ⇄ 는 같은 줄의 상대 팀 사람과 자리를 바꾼다. 「무작위로 섞기」.
func _team_panel(narrow: bool) -> Control:
	_balance_teams()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var hr := HBoxContainer.new()
	var hl := _nw(_label("팀 나누기 · ⇄ 를 누르면 반대 팀과 맞바꿔요", 14, LABEL, 1))
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(hl)
	var shuffle := _button("무작위로 섞기", func():
		var ids: Array = range(settings["n"])
		ids.shuffle()
		for k in ids.size():
			settings["teams"][ids[k]] = k % 2
		if online == "host":
			_host_broadcast_lobby()
		_show_setup())
	shuffle.flat = true
	shuffle.add_theme_color_override("font_color", HINT_GOLD)
	shuffle.add_theme_font_size_override("font_size", 13)
	hr.add_child(shuffle)
	v.add_child(hr)
	var cols: BoxContainer = HBoxContainer.new() if not narrow else VBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	for t in 2:
		var box := PanelContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tc: Color = Match.TEAM_COLORS[t]
		var sb := _sb(Color(tc, 0.12), tc, 10)
		sb.set_border_width_all(2)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		box.add_theme_stylebox_override("panel", sb)
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 6)
		bv.add_child(_label("%s 팀" % Match.TEAM_NAMES[t], 14, tc.lightened(0.15), 1))
		for i in settings["n"]:
			if int(settings["teams"][i]) == t and not settings.get("empty", [false, false, false, false, false, false, false, false])[i]:
				bv.add_child(_team_member_row(i))
		box.add_child(bv)
		cols.add_child(box)
	v.add_child(cols)
	# 정산 간격 · 목표 점수 (테스트용 설정)
	var opt := HBoxContainer.new()
	opt.add_theme_constant_override("separation", 10)
	for spec in [["정산", "parcel_every", [[1, "1바퀴"], [2, "2바퀴"]]], ["목표", "parcel_goal", [[3, "3점"], [5, "5점"]]]]:
		var ov := HBoxContainer.new()
		ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ov.add_theme_constant_override("separation", 8)
		var ol := _nw(_label(spec[0], 13, LABEL, 1))
		ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ov.add_child(ol)
		var key: String = spec[1]
		var sg := _seg(spec[2], int(settings.get(key, 2)), func(k):
			settings[key] = k
			if online == "host":
				_host_broadcast_lobby()
			_show_setup())
		sg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ov.add_child(sg)
		opt.add_child(ov)
	v.add_child(opt)
	return v


func _team_member_row(i: int) -> Control:
	var friend: bool = settings["friend"][i] and online == "host"
	var human: bool = not settings["cpu"][i] and not friend
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.custom_minimum_size = Vector2(0, 28)
	var ic := _icon_pic(Match.TEAM_COLORS[int(settings["teams"][i])], i, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var nm := _nw(_label(_team_label(i), 14, TEXT))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.size_flags_vertical = Control.SIZE_FILL
	h.add_child(nm)
	var word := "사람" if human else "CPU"
	if friend:
		word = "친구" if friend_peer.has(i) else "친구 대기"
	var pill := _button(word, func(): _toggle_cpu(i))
	pill.custom_minimum_size = Vector2(52, 24)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_font_size_override("font_size", 12)
	var pc := BRASS if human else (Color("7FB2FF") if friend else Color(FG, 0.1))
	for st_name in ["normal", "hover", "pressed"]:
		var psb := _sb(pc if st_name == "normal" else pc.lightened(0.1), Color(0, 0, 0, 0), 999)
		psb.content_margin_top = 1
		psb.content_margin_bottom = 1
		pill.add_theme_stylebox_override(st_name, psb)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		pill.add_theme_color_override(c, INK if human or friend else LABEL)
	h.add_child(pill)
	var sw := _button("⇄", func(): _swap_team(i))
	sw.tooltip_text = "반대 팀과 맞바꾸기"
	sw.custom_minimum_size = Vector2(30, 24)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.flat = true
	h.add_child(sw)
	return h


## i 와 반대 팀의 같은 순번 사람을 맞바꾼다 (팀 인원은 그대로).
func _swap_team(i: int) -> void:
	snd.play("ui_toggle")
	var t: int = int(settings["teams"][i])
	var my_k := 0
	for j in i:
		if int(settings["teams"][j]) == t:
			my_k += 1
	var others: Array = []
	for j in settings["n"]:
		if int(settings["teams"][j]) != t:
			others.append(j)
	if others.is_empty():
		return
	var o: int = others[mini(my_k, others.size() - 1)]
	settings["teams"][i] = 1 - t
	settings["teams"][o] = t
	if online == "host":
		_host_broadcast_lobby()
	_show_setup()


## 진영 두 쪽: 빨강은 사선, 파랑은 점무늬. 가운데 폭 1칸 중립 띠는 점선 테두리. c·R 은 화면 좌표.
func _draw_parcel_halves(ci: CanvasItem, c: Vector2, R: float, u: float) -> void:
	var nh := 0.5 * u   # 중립 띠 반 폭 (1칸 = u)
	for side in [-1, 1]:
		var pts := PackedVector2Array()
		for k in 33:
			var a: float = -PI / 2.0 + PI * k / 32.0
			var p := Vector2(cos(a) * float(side), sin(a)) * R
			if absf(p.x) < nh:
				p.x = nh * side
			pts.append(c + p)
		ci.draw_colored_polygon(pts, Color(PARCEL_RED_BG if side < 0 else PARCEL_BLUE_BG, 0.55))
	# 빨강 사선
	var step := 14.0
	var t := -2.0 * R
	while t < 2.0 * R:
		# 선 x - y = t 를 왼쪽 반원(x <= -nh) 안으로 자른다
		var seg := _clip_line_half(Vector2(t, 0), Vector2(1, 1).normalized(), R, nh, -1)
		if not seg.is_empty():
			ci.draw_line(c + seg[0], c + seg[1], Color(PARCEL_RED_LINE, 0.7), 4.0)
		t += step
	# 파랑 점무늬
	var y := -R
	while y < R:
		var x := nh + 7.0
		while x < R:
			if Vector2(x, y).length() < R - 4.0:
				ci.draw_circle(c + Vector2(x, y), 2.4, Color(PARCEL_BLUE_DOT, 0.75))
			x += 14.0
		y += 14.0
	# 중립 띠: 크림색, 점선 테두리
	var band := PackedVector2Array()
	for k in 17:
		var yy: float = -R + 2.0 * R * k / 16.0
		band.append(c + Vector2(-nh, yy * sqrt(maxf(0.0, 1.0 - (nh * nh) / (R * R)))))
	for k in 17:
		var yy2: float = R - 2.0 * R * k / 16.0
		band.append(c + Vector2(nh, yy2 * sqrt(maxf(0.0, 1.0 - (nh * nh) / (R * R)))))
	ci.draw_colored_polygon(band, Color("F5EFE2", 0.92))
	for sx in [-nh, nh]:
		var hh := sqrt(maxf(0.0, R * R - sx * sx))
		ci.draw_dashed_line(c + Vector2(sx, -hh), c + Vector2(sx, hh), Color("2A1E12", 0.7), 2.0, 8.0)


## 직선 (p + d·s) 을 반지름 R 원 안, x 가 중립 띠 바깥 side 쪽인 부분으로 자른다. [a, b] 또는 [].
func _clip_line_half(p: Vector2, d: Vector2, R: float, nh: float, side: int) -> Array:
	var b := p.dot(d)
	var cc := p.dot(p) - R * R
	var disc := b * b - cc
	if disc <= 0.0:
		return []
	var s0 := -b - sqrt(disc)
	var s1 := -b + sqrt(disc)
	# x 조건: side<0 이면 x <= -nh
	var lim := -nh if side < 0 else nh
	if absf(d.x) > 0.0001:
		var sx := (lim - p.x) / d.x
		if side < 0:
			if d.x > 0.0:
				s1 = minf(s1, sx)
			else:
				s0 = maxf(s0, sx)
		else:
			if d.x > 0.0:
				s0 = maxf(s0, sx)
			else:
				s1 = minf(s1, sx)
	if s1 <= s0:
		return []
	return [p + d * s0, p + d * s1]


## 골판지 택배 상자. half = 반 폭(화면), glow_team: 지금 있는 진영의 팀 색 테두리 (-1 없음), wait: 점선 유령
func _draw_parcel_box(ci: CanvasItem, c: Vector2, half: float, ang: float, glow_team: int, a: float, wait := false) -> void:
	var xf := Transform2D(ang, c)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var pts := PackedVector2Array()
	for q in corners:
		pts.append(xf * (q * half))
	if glow_team >= 0:
		var gp := PackedVector2Array()
		for q in corners:
			gp.append(xf * (q * (half + 7.0)))
		gp.append(gp[0])
		ci.draw_polyline(gp, Color(Match.TEAM_COLORS[glow_team], 0.9 * a), 4.0, true)
	if wait:
		var dp := pts.duplicate()
		dp.append(dp[0])
		for k in 4:
			ci.draw_dashed_line(dp[k], dp[k + 1], Color(0.3, 0.3, 0.3, 0.8 * a), 2.0, 6.0)
		ci.draw_colored_polygon(pts, Color(0.92, 0.9, 0.86, 0.5 * a))
		return
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(3, 5))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.3 * a))
	ci.draw_colored_polygon(pts, Color("C99A62", a))
	# 테이프 십자
	var tw := half * 0.32
	ci.draw_line(xf * Vector2(-half, 0), xf * Vector2(half, 0), Color("E8D49A", a), tw)
	ci.draw_line(xf * Vector2(0, -half), xf * Vector2(0, half), Color("E8D49A", a), tw)
	var ol := pts.duplicate()
	ol.append(ol[0])
	ci.draw_polyline(ol, Color(0.1, 0.11, 0.13, a), maxf(1.5, half * 0.11), true)
	ci.draw_circle(xf * Vector2.ZERO, maxf(1.5, half * 0.14), Color(0.1, 0.11, 0.13, a))


# ── 택배 쟁탈전: 경기 화면 (디자인 「택배 쟁탈전 · 경기 화면」「택배·왕관 상태와 알림」) ──
var parcel_fly := {}           # 택배가 중앙으로 날아가는 중 {from, to, t0}
var parcel_dropped := false
const PARCEL_FLY_T := 0.5


## 위쪽 정산 예측 줄 높이 (기믹 칩 등을 그만큼 내린다)
func _parcel_line_h() -> float:
	return 36.0 if (m != null and m.mode == "parcel" and not portrait) else 0.0


func _draw_parcel() -> void:
	if m == null or m.world.parcel.is_empty() or m.phase == "place":
		return
	var pc: Dictionary = m.world.parcel
	var half := World.Parcel.R * 0.86 * view_scale
	if not parcel_fly.is_empty() and time - float(parcel_fly["t0"]) < PARCEL_FLY_T:
		var k := clampf((time - float(parcel_fly["t0"])) / PARCEL_FLY_T, 0.0, 1.0)
		var a := w2s(parcel_fly["from"])
		var b := w2s(parcel_fly["to"])
		var p := a.lerp(b, k) + Vector2(0, -sin(PI * k) * 60.0 * view_scale)
		# 지나간 자리: 점선
		for j in 6:
			var kj := k * j / 6.0
			draw_circle(a.lerp(b, kj) + Vector2(0, -sin(PI * kj) * 60.0 * view_scale), 2.0, Color(0.2, 0.2, 0.2, 0.5))
		_draw_parcel_box(self, p, half * (1.0 + 0.15 * sin(PI * k)), k * TAU * 0.5, -1, 1.0)
		return
	match str(pc["state"]):
		"field":
			_draw_parcel_box(self, w2s(pc["pos"]), half, float(pc["ang"]), World.Parcel.side_team(m.world), 1.0)
		"wait":
			var c := w2s(Vector2.ZERO)
			_draw_parcel_box(self, c, half, 0.0, -1, 1.0, true)
			_txt(c + Vector2(0, half + 18), "대기", 12, SUB, font_semi, 60, HORIZONTAL_ALIGNMENT_CENTER)


func _parcel_hint(pid: int) -> String:
	var t: int = m.team_of(pid)
	var side := World.Parcel.side_team(m.world)
	var dir := "왼쪽" if t == 0 else "오른쪽"
	if side == t:
		return "택배가 우리 진영에 있어요 · 정산까지 지키세요"
	return "택배 뒤로 돌아가 우리 진영(%s)으로 미세요" % dir


## 위쪽 가운데: 정산까지 남은 차례(점) + 아래 「지금 정산하면 ○○ +1」
func _draw_parcel_clock(vs: Vector2) -> void:
	var total: int = m.order.size() * m.parcel_every
	var left: int = m.turns_to_settle() if m.phase != "draft" else total
	left = clampi(left, 0, total)
	var dot := 16.0
	var gap := 5.0
	var w := 96.0 + total * (dot + gap) + 70.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 24, w, 56)
	_panel(r)
	_txt(r.position + Vector2(18, 26), "정산까지", 14, TEXT, font_bold)
	_txt(r.position + Vector2(18, 44), "%d바퀴마다" % m.parcel_every, 11, SUB)
	var x0 := r.position.x + 96.0
	for i in total:
		var c := Vector2(x0 + i * (dot + gap) + dot * 0.5, r.position.y + 28)
		var on := i < left
		draw_circle(c, dot * 0.5, BRASS if on else Color(0, 0, 0, 0))
		draw_arc(c, dot * 0.5, 0, TAU, 20, Color(TEXT, 0.8), 2.0, true)
	_txt(Vector2(r.end.x - 16, r.position.y + 36), "%d차례" % left, 18, TEXT, font_bold, 70, HORIZONTAL_ALIGNMENT_RIGHT)
	# 정산 예측 알약
	var side := World.Parcel.side_team(m.world)
	var txt := "지금 정산하면 %s +1" % (Match.TEAM_NAMES[side] + " 팀") if side >= 0 else ("택배 대기 중 · 무득점" if m.world.parcel["state"] != "field" else "지금 정산하면 무득점 (중립)")
	var pw := font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 30.0
	var pr := Rect2(vs.x * 0.5 - pw * 0.5, 88, pw, 28)
	var tc: Color = Match.TEAM_COLORS[side] if side >= 0 else Color("8A8F96")
	_round_rect(pr, tc.lerp(Color.WHITE, 0.78), 14, tc)
	draw_string(font_bold, pr.position + Vector2(0, 19), txt, HORIZONTAL_ALIGNMENT_CENTER, pw, 13, Color("2A1E12"))


## 차례 목록 위: 두 팀의 점수 (목표 칸 + 숫자)
func _draw_team_scores(r: Rect2) -> void:
	_txt(r.position + Vector2(8, 16), "택배 쟁탈전", 13, SUB, font_semi)
	_txt(Vector2(r.end.x - 8, r.position.y + 16), "%d점 선취" % m.parcel_goal, 12, SUB, font, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	for t in 2:
		var y := r.position.y + 28 + t * 26
		var tc: Color = Match.TEAM_COLORS[t]
		draw_rect(Rect2(r.position.x + 8, y, 8, 22), tc)
		_txt(Vector2(r.position.x + 24, y + 16), "%s 팀" % Match.TEAM_NAMES[t], 15, TEXT, font_bold)
		var sc: int = m.team_scores[t]
		_txt(Vector2(r.end.x - 8, y + 18), "%d" % sc, 20, TEXT, font_bold, 30, HORIZONTAL_ALIGNMENT_RIGHT)
		var bw := 12.0
		var x0 := r.end.x - 34.0 - m.parcel_goal * (bw + 3.0)
		for k in m.parcel_goal:
			var br := Rect2(x0 + k * (bw + 3.0), y + 5, bw, bw)
			draw_rect(br, tc if k < sc else Color(FG, 0.12))
			draw_rect(br, Color(0.1, 0.1, 0.12, 0.7), false, 1.2)


func _on_parcel_event(e: Dictionary) -> void:
	match str(e.get("kind", "")):
		"drop":
			parcel_dropped = true
			fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -36), "t": 0.0, "life": 1.0, "text": "택배 추락", "c": Color("C99A62"), "size": 18})
		"home":
			parcel_fly = {"from": e.get("from", Vector2.ZERO), "to": e["pos"], "t0": time}
			if parcel_dropped:
				_push_alert("택배 추락", "중앙으로 복귀", Color("ECE7DD"), Color("8A8F96"), Color("4A4E55"))
			parcel_dropped = false


## 정산 알림: 화면이 잠깐 멈추고 판정
func _take_parcel_events() -> void:
	if m == null or m.parcel_events.is_empty():
		return
	for ev in m.parcel_events:
		var t: int = int(ev["team"])
		var sc: Array = ev["scores"]
		var at: Vector2 = ev.get("pos", Vector2.ZERO)
		fx.append({"k": "text", "pos": at + Vector2(0, -40), "t": 0.0, "life": 1.2, "text": "정산!", "c": Color("2A1E12"), "size": 26})
		if t >= 0:
			var tc: Color = Match.TEAM_COLORS[t]
			_push_alert("정산! %s 팀 +1" % Match.TEAM_NAMES[t], "%d : %d" % [sc[0], sc[1]], tc.lerp(Color.WHITE, 0.82), tc, tc.darkened(0.3))
			fx.append({"k": "text", "pos": at + Vector2(0, -70), "t": 0.0, "life": 1.2, "text": "+1", "c": tc, "size": 28})
			_log("정산: %s 팀 +1 (%d : %d)" % [Match.TEAM_NAMES[t], sc[0], sc[1]], tc)
			snd.play("set_complete", -4.0)
		else:
			_push_alert("정산! 무득점", "%d : %d" % [sc[0], sc[1]], Color("ECE7DD"), Color("8A8F96"), Color("4A4E55"))
			_log("정산: 무득점 (%d : %d)" % [sc[0], sc[1]], SUB)
			snd.play("fx_parody_stamp", -6.0, 0.9)
		turn_hold = maxf(turn_hold, 0.6 if _reduced() else 1.3)
	m.parcel_events.clear()


# ── 태엽 시계탑 화면 ─────────────────────────────────────
const CLOCK_GOLD := Color("E2C27A")
var bonus_shown := -1
var late_tag := {}             # 늦잠 열쇠로 밀린 사람 → 표시할 차례 번호까지


## 차례 이벤트의 움직임이 다 멈췄을 때
func _after_fx() -> void:
	last_fastest = 9999.0
	var outs: Array = m.world.knockouts.duplicate()
	m.finish_fx()
	_consume_events()
	turn_hold = maxf(turn_hold, _sp("hold") + (0.3 if not outs.is_empty() else 0.0))
	for k in outs:
		var cz: Dictionary = k.get("cause", {})
		var victim: String = m.players[int(k["owner"])].name
		_log("%s 퍽이 %s 떨어졌어요" % [victim, _j(_part_word(str(cz.get("part", "body"))), "으로", "로")], m.players[int(k["owner"])].color)


func _fx_title() -> String:
	match m.fx_stage:
		"round_start":
			return "바퀴 시작 장치"
		"turn_start":
			return "차례 시작 장치"
		_:
			return "차례 끝 장치"


## 차례 순서가 바뀌었을 때 (늦잠 열쇠 · 순서 바꾸개) · 정각 덤 차례 안내
func _take_order_log() -> void:
	if m == null:
		return
	for ev in m.order_log:
		var pl: Dictionary = m.players[int(ev["pid"])]
		match str(ev["kind"]):
			"delay":
				late_tag[int(ev["pid"])] = m.world.turn_no
				_log("늦잠! %s 차례가 한 칸 뒤로 밀렸어요" % pl.name, pl.color)
				_banner("늦잠!", pl.color, "%s 차례가 한 칸 뒤로" % pl.name)
			"delay_next":
				late_tag[int(ev["pid"])] = m.world.turn_no + m.order.size()
				_log("늦잠! %s 다음 바퀴 차례가 한 칸 뒤로 밀려요" % pl.name, pl.color)
			"chest":
				_log("보물 상자! %s 다음 개조 후보 +1장" % pl.name, pl.color)
			"swap":
				_log("순서 바꾸기! %s 이번 바퀴 맨 끝으로" % _j(pl.name, "은", "는"), pl.color)
				_banner("순서 바꾸기", pl.color, "%s 이번 바퀴 맨 끝으로" % _j(pl.name, "은", "는"))
	m.order_log.clear()
	if m.phase == "aim" and not m.bonus_active.is_empty() and bonus_shown != m.world.turn_no:
		bonus_shown = m.world.turn_no
		var bp: Dictionary = m.players[int(m.bonus_active["pid"])]
		_banner("정각!", CLOCK_GOLD, "%s 같은 알로 한 번 더 (힘 70%%)" % bp.name)
		snd.play("set_complete", -4.0, 1.2)


## 시계탑 기믹 (진자 · 뻐꾸기 · 시곗바늘) 과 판 위 장치 (화살 · 쥐 · 자명종 · 캡슐)
func _draw_clock_gimmick(g: Dictionary) -> void:
	var k := view_scale
	match str(g["kind"]):
		"pendulum":
			var it: Dictionary = g["items"][0]
			var a := w2s(it["a"])
			var b := w2s(it["b"])
			var at: int = int(it["at"])
			var cur := a if at == 0 else b
			var nxt := b if at == 0 else a
			draw_dashed_line(a, b, Color(CLOCK_GOLD, 0.35), 2.0, 10.0)
			# 다음 자리: 점선 원
			var rr: float = float(it["r"]) * k
			for i in 16:
				if i % 2 == 0:
					draw_arc(nxt, rr, TAU * i / 16.0, TAU * (i + 1) / 16.0, 4, Color(CLOCK_GOLD, 0.7), 2.0, true)
			# 매단 점: 줄의 가운데에서 판 끝 쪽으로
			var mid: Vector2 = ((it["a"] as Vector2) + (it["b"] as Vector2)) * 0.5
			var axis: Vector2 = ((it["b"] as Vector2) - (it["a"] as Vector2)).orthogonal().normalized()
			var piv := w2s(mid - axis * (m.world.size - CELL * 0.4 - mid.dot(-axis)))
			draw_line(piv, cur, Color("C9A15A"), 3.0, true)
			draw_circle(piv, 5.0, Color("C9A15A"))
			_text_outline(nxt + Vector2(0, -rr - 10.0), "다음 위치", 11, Color("F3EAD3"), true)
			draw_circle(cur + Vector2(0, rr * 0.25), rr * 1.02, Color(0, 0, 0, 0.35))
			draw_circle(cur, rr, Color("B8913F"))
			draw_circle(cur + Vector2(-rr * 0.3, -rr * 0.3), rr * 0.35, Color("E2C27A"))
			draw_arc(cur, rr, 0, TAU, 28, Art.outline, 2.0, true)
		"clockhand":
			var it2: Dictionary = g["items"][0]
			var ang: float = float(it2["ang"])
			var L: float = float(it2["len"])
			var c := w2s(Vector2.ZERO)
			var tip := w2s(Vector2.from_angle(ang) * L)
			# 다음 30도 부채꼴 예고
			var pts := PackedVector2Array([c])
			for i in 9:
				pts.append(c + Vector2.from_angle(ang + deg_to_rad(30.0) * i / 8.0) * L * k)
			draw_colored_polygon(pts, Color(CLOCK_GOLD, 0.08))
			draw_line(c + Vector2(3, 4), tip + Vector2(3, 4), Color(0, 0, 0, 0.3), 10.0 * k, true)
			draw_line(c, tip, Color("1E2030"), 8.0 * k, true)
			poly_arrow(tip, Vector2.from_angle(ang), 9.0 * k, Color("1E2030"))
			draw_circle(c, 12.0 * k, Color("C9A15A"))
			draw_arc(c, 12.0 * k, 0, TAU, 20, Art.outline, 2.0, true)
			_text_outline(c + Vector2.from_angle(ang + deg_to_rad(15.0)) * L * 0.55 * k, "차례마다 30°", 11, CLOCK_GOLD, true)
		"cuckoo":
			var dir := Vector2.from_angle(float(g["dir"]))
			var edge := w2s(-dir * (m.world.size + CELL * 0.9))
			# 뻐꾸기 집 (판 바깥, 미는 방향의 반대편)
			var hs := 18.0 * k
			draw_rect(Rect2(edge - Vector2(hs, hs * 0.8), Vector2(hs * 2.0, hs * 1.8)), Color("6B4523"))
			draw_colored_polygon(PackedVector2Array([edge + Vector2(-hs * 1.2, -hs * 0.8), edge + Vector2(hs * 1.2, -hs * 0.8), edge + Vector2(0, -hs * 1.8)]), Color("8A6237"))
			draw_circle(edge + Vector2(0, -hs * 0.05), hs * 0.45, Color("F3EAD3"))
			# 예고: 3·5바퀴 시작 한 바퀴 전부터 큰 화살표
			var soon: bool = m.round_no == 2 or m.round_no == 4
			var al := 0.65 + 0.3 * sin(time * 5.0) if soon else 0.25
			var c2 := w2s(Vector2.ZERO)
			draw_line(c2 - dir * CELL * 2.0 * k, c2 + dir * CELL * 2.0 * k, Color(CLOCK_GOLD, al), 6.0 * k, true)
			poly_arrow(c2 + dir * CELL * 2.0 * k, dir, 16.0 * k, Color(CLOCK_GOLD, al))
			if soon:
				_text_outline(c2 + Vector2(0, -CELL * 2.6 * k), "다음 바퀴 뻐꾹! 모두 1칸", 14, CLOCK_GOLD, true)
				for st0 in m.world.stones:
					if st0.alive:
						var sp0 := w2s(st0.pos)
						draw_line(sp0 + dir * World.STONE_R * k, sp0 + dir * (World.STONE_R + 18.0) * k, CLOCK_GOLD, 2.5, true)
						poly_arrow(sp0 + dir * (World.STONE_R + 18.0) * k, dir, 6.0, CLOCK_GOLD)


func poly_arrow(tip: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip + dir * s, tip - dir * s * 0.2 + side * s * 0.7, tip - dir * s * 0.2 - side * s * 0.7]), col)


## 차례를 넘는 물체와 알 위 표식
func _draw_clock_things() -> void:
	if m == null or (m.world.clock.is_empty() and m.world.pirate.is_empty()):
		return
	var k := view_scale
	var st: Dictionary = m.world.clock
	for wk in st.get("walkers", []):
		var p := w2s(wk["pos"])
		var dir: Vector2 = wk["dir"]
		var nxt := w2s((wk["pos"] as Vector2) + dir * (2.5 if wk["kind"] == "arrow" else 2.0) * CELL)
		draw_dashed_line(p, nxt, Color(CLOCK_GOLD, 0.45), 2.0, 8.0)
		if wk["kind"] == "arrow":
			draw_line(p - dir * 16.0 * k, p + dir * 10.0 * k, Color("8A6237"), 3.0, true)
			poly_arrow(p + dir * 10.0 * k, dir, 7.0 * k, Color("C3C9D0"))
		else:
			draw_circle(p, 9.0 * k, Color("A7ADB4"))
			draw_circle(p + dir * 7.0 * k, 4.0 * k, Color("E7B7B0"))
			draw_arc(p, 9.0 * k, 0, TAU, 16, Art.outline, 1.5, true)
		_status_badge(p + Vector2(-12.0, -14.0) * k, int(wk["left"]))
	for al in st.get("alarms", []):
		var ap := w2s(al["pos"])
		draw_arc(ap, float(al.get("r", 2.0)) * CELL * k, 0, TAU, 40, Color(m.players[int(al["owner"])].color, 0.3), 2.0, true)
		draw_circle(ap, 8.0 * k, Color("D2452F"))
		draw_circle(ap, 5.5 * k, Color("F3EAD3"))
		_text_outline(ap + Vector2(0, -14.0 * k), "따르릉 다음 바퀴", 11, CLOCK_GOLD, true)
	for s in m.world.stones:
		var u := World.STONE_R * k
		if s.status.has("capsule") and not s.status.has("capsule_used"):
			var cp := w2s(s.status["capsule"])
			for i in 12:
				if i % 2 == 0:
					draw_arc(cp, u * 0.9, TAU * i / 12.0, TAU * (i + 1) / 12.0, 4, Color(m.players[s.owner].color, 0.6), 1.5, true)
			draw_rect(Rect2(cp - Vector2(4, 6) * k, Vector2(8, 12) * k), Color("9FC4E8"))
		if not s.alive:
			continue
		var p2 := w2s(s.pos)
		if s.status.has("bow"):
			var b: Dictionary = s.status["bow"]
			draw_dashed_line(p2, p2 + (b["dir"] as Vector2) * 3.0 * CELL * k, Color(m.players[s.owner].color, 0.7), 2.0, 8.0)
		var icons := _status_list(s)
		var shown := icons.slice(0, 2)
		var x0 := p2 + Vector2(u * 0.75, -u * 0.9)
		for ic in shown:
			_draw_status_icon(x0, ic["kind"], u * 0.4)
			if int(ic.get("n", 0)) > 0:
				_status_badge(x0 + Vector2(-u * 1.5, 0), int(ic["n"]))
			x0 += Vector2(u * 0.82, 0)
		if icons.size() > 2:
			_text_outline(x0 + Vector2(-u * 0.2, 4), "+%d" % (icons.size() - 2), 11, TEXT, true)


func _draw_status_icon(c: Vector2, kind: String, r: float) -> void:
	draw_circle(c, r, Color.WHITE)
	draw_arc(c, r, 0, TAU, 16, Color("1A1D21"), 1.8, true)
	var ink := Color("1A1D21")
	match kind:
		"hand":
			draw_line(c + Vector2(0, r * 0.6), c + Vector2(0, -r * 0.6), ink, 2.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(-r * 0.35, -r * 0.2), c + Vector2(r * 0.35, -r * 0.2)]), ink)
		"bomb":
			draw_arc(c, r * 0.6, 0, TAU, 14, ink, 1.6, true)
			draw_line(c, c + Vector2(0, -r * 0.4), ink, 1.6, true)
			draw_line(c, c + Vector2(r * 0.3, 0), ink, 1.6, true)
		"power":
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.25), Vector2(r * 1.2, r * 0.5)), Color("8CCB16"))
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.25), Vector2(r * 1.2, r * 0.5)), ink, false, 1.2)
		"capsule":
			draw_rect(Rect2(c + Vector2(-r * 0.3, -r * 0.55), Vector2(r * 0.6, r * 1.1)), Color("C3C9D0"))
			draw_rect(Rect2(c + Vector2(-r * 0.3, -r * 0.55), Vector2(r * 0.6, r * 1.1)), ink, false, 1.2)
		"bow":
			draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.6, -r * 0.6), ink, 2.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.7, -r * 0.7), c + Vector2(r * 0.15, -r * 0.6), c + Vector2(r * 0.6, -r * 0.15)]), ink)
		"hourglass":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.6), c + Vector2(r * 0.5, -r * 0.6), c, c + Vector2(r * 0.5, r * 0.6), c + Vector2(-r * 0.5, r * 0.6), c]), Color("E2C27A"))
		"parrot":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, r * 0.4), c + Vector2(r * 0.5, -r * 0.5), c + Vector2(r * 0.1, r * 0.3)]), Color("2FA35A"))
		"flag":
			draw_line(c + Vector2(-r * 0.3, r * 0.6), c + Vector2(-r * 0.3, -r * 0.6), ink, 1.6, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.6), c + Vector2(r * 0.5, -r * 0.35), c + Vector2(-r * 0.3, -r * 0.1)]), Color("D2452F"))
		"chain":
			draw_arc(c + Vector2(-r * 0.28, 0), r * 0.3, 0, TAU, 10, ink, 1.6, true)
			draw_arc(c + Vector2(r * 0.28, 0), r * 0.3, 0, TAU, 10, ink, 1.6, true)
		"smoke":
			draw_circle(c + Vector2(-r * 0.2, r * 0.1), r * 0.35, Color("B9BEC6"))
			draw_circle(c + Vector2(r * 0.25, -r * 0.15), r * 0.3, Color("D5D9DE"))


## 차례 이벤트 연출: 진자·시곗바늘·화살·쥐가 지나간 자리, 다시보기 잔상
func _on_clock_event(e: Dictionary) -> void:
	match str(e["t"]):
		"walker":
			fx.append({"k": "line", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.6, "c": CLOCK_GOLD})
			snd.play("fx_mech_spring", -6.0, 0.8)
		"replay":
			var path: Array = e["path"]
			for i in range(path.size() - 1):
				fx.append({"k": "line", "a": path[i], "b": path[i + 1], "t": -0.02 * i, "life": 0.7, "c": Color(m.players[int(e["owner"])].color, 0.8)})
			snd.play("fx_magic_shadow", -6.0, 1.2)


## 입장: 시계 문자판이 12시를 가리키는 순간 둘로 갈라진다.
func _draw_clock_intro(vs: Vector2) -> void:
	var k := _intro_k()
	var half := vs.x * 0.5
	var off := half * 1.05 * k
	var c := vs * 0.5
	var R := maxf(vs.x, vs.y) * 0.62
	for side in [-1, 1]:
		var dx: float = -off if side < 0 else off
		var r := Rect2((0.0 if side < 0 else half) + dx, 0, half, vs.y)
		shutter.draw_rect(r, Color("1B2148"))
		# 거대한 문자판 반쪽 (화면을 거의 덮는다)
		var pts := PackedVector2Array()
		for i in 49:
			var a: float = -PI / 2.0 + PI * i / 48.0
			pts.append(c + Vector2(dx, 0) + Vector2(cos(a) * float(side), sin(a)) * R)
		shutter.draw_colored_polygon(pts, Color("F4F1E8"))
		shutter.draw_polyline(pts, Color("C9A15A"), 14.0, true)
		if k > 0.0:
			shutter.draw_line(pts[0], pts[pts.size() - 1], Color("1E2030", 0.6), 3.0)
		for h in 12:
			var ha := -PI / 2.0 + TAU * h / 12.0
			var hp := Vector2.from_angle(ha)
			if (hp.x >= -0.01 and side > 0) or (hp.x <= 0.01 and side < 0):
				var p1 := c + Vector2(dx, 0) + hp * R * 0.82
				var p2 := c + Vector2(dx, 0) + hp * R * 0.92
				shutter.draw_line(p1, p2, Color("1E2030"), 10.0 if h % 3 == 0 else 6.0, true)
	if k <= 0.0:
		# 바늘: 11시 58분에서 12시로
		var t := clampf(shutter_t / INTRO_CLOSED, 0.0, 1.0)
		var minute := -PI / 2.0 - TAU * (2.0 / 60.0) * (1.0 - t)
		var hour := -PI / 2.0 - TAU * (2.0 / 720.0) * (1.0 - t)
		shutter.draw_line(c, c + Vector2.from_angle(hour) * R * 0.45, Color("1E2030"), 16.0, true)
		shutter.draw_line(c, c + Vector2.from_angle(minute) * R * 0.7, Color("1E2030"), 10.0, true)
		shutter.draw_circle(c, 14.0, Color("C9A15A"))
		if m != null:
			var nm: String = PartsData.WORKSHOPS["clock"]["name"]
			var bw := font_display.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x + 56.0
			var box := Rect2(c.x - bw * 0.5, c.y + R * 0.2, bw, 92)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("1B2148")
			sb.border_color = Color("C9A15A")
			sb.set_border_width_all(4)
			sb.set_corner_radius_all(10)
			sb.draw(shutter.get_canvas_item(), box)
			shutter.draw_string(font_bold, box.position + Vector2(0, 26), "오늘의 공방" + _mode_suffix(), HORIZONTAL_ALIGNMENT_CENTER, bw, 13, Color("E2C27A"))
			shutter.draw_string(font_display, box.position + Vector2(0, 70), nm, HORIZONTAL_ALIGNMENT_CENTER, bw, 36, Color("F4F1E8"))
			_draw_intro_gimmicks(vs, box.end.y + 16.0, Color("C9A15A"), Color("1B2148"))
	elif k < 0.5:
		# 12시 정각: 「댕」
		_text_outline(Vector2(c.x, c.y - 40.0), "댕!", 48, Color("F2C14E"), true)


# ── 해적 선착장 화면 ─────────────────────────────────────
const SEA_COL := Color("3E8FB0")
const DECK_WOOD := Color("9A6A3A")
var _simpath_key := ""
var _simpath: PackedVector2Array = PackedVector2Array()


## 판 위: 밀물 · 구멍 · 널빤지 · 판자 · 상자 · 술통 · 사슬 · 소용돌이 · 나무 상자
func _draw_pirate_board() -> void:
	if m == null or m.world.pirate.is_empty():
		return
	var w = m.world
	var pr: Dictionary = w.pirate
	var k := view_scale
	var c := w2s(Vector2.ZERO)
	var R: float = w.size * k
	if World.Pirate.has_tide(w):
		if int(pr.get("tide", 0)) > 0:
			# 밀물: 가장자리 1칸이 물에 잠김
			draw_arc(c, R - CELL * k * 0.5, 0, TAU, 96, Color(SEA_COL, 0.75), CELL * k, false)
			for i in 24:
				var a := TAU * i / 24.0 + time * 0.3
				draw_arc(c, R - CELL * k * 0.5, a, a + 0.12, 4, Color(1, 1, 1, 0.35), 2.0, true)
		elif World.Pirate.tide_round(m.round_no + 1):
			# 다음 바퀴 밀물 예고: 물결무늬
			for i in 36:
				var a2 := TAU * i / 36.0
				var rr := R - CELL * k * 0.5 + sin(time * 3.0 + i) * 3.0
				draw_arc(c, rr, a2, a2 + 0.1, 4, Color(SEA_COL, 0.6), 3.0, true)
	for g in w.gimmicks:
		match str(g["kind"]):
			"whirlpool":
				var it: Dictionary = g["items"][0]
				var wc := w2s(it["pos"])
				var wr: float = float(it["r"]) * k
				draw_circle(wc, wr, Color(SEA_COL, 0.22))
				for j in 3:
					var pts := PackedVector2Array()
					for q in 30:
						var t := q / 29.0
						pts.append(wc + Vector2.from_angle(-time * 1.4 + TAU * j / 3.0 + t * 5.0) * wr * (1.0 - t * 0.9))
					draw_polyline(pts, Color(1, 1, 1, 0.45), 2.0, true)
				draw_arc(wc, CELL * k, 0, TAU, 32, Color(1, 1, 1, 0.35), 1.5, true)
			"crates":
				for it2 in g["items"]:
					var cp := w2s(it2["pos"])
					var hs := World.Pirate.CRATE_R * k * 0.92
					var wnd := World.Pirate.wind(w)
					draw_dashed_line(cp, cp + wnd * CELL * k, Color(1, 1, 1, 0.5), 2.0, 6.0)
					draw_rect(Rect2(cp - Vector2(hs, hs) + Vector2(3, 4), Vector2.ONE * hs * 2.0), Color(0, 0, 0, 0.3))
					draw_rect(Rect2(cp - Vector2(hs, hs), Vector2.ONE * hs * 2.0), DECK_WOOD)
					draw_line(cp + Vector2(-hs, -hs), cp + Vector2(hs, hs), Color("6B4523"), 3.0)
					draw_line(cp + Vector2(hs, -hs), cp + Vector2(-hs, hs), Color("6B4523"), 3.0)
					draw_rect(Rect2(cp - Vector2(hs, hs), Vector2.ONE * hs * 2.0), Art.outline, false, 2.0)
	for pk in pr.get("planks", []):
		var o: Vector2 = pk["dir"]
		var base: Vector2 = pk["pos"]
		var side := o.orthogonal()
		var pts2 := PackedVector2Array([w2s(base - o * CELL * 0.4 + side * CELL * 0.8), w2s(base + o * CELL * 1.5 + side * CELL * 0.8),
			w2s(base + o * CELL * 1.5 - side * CELL * 0.8), w2s(base - o * CELL * 0.4 - side * CELL * 0.8)])
		draw_colored_polygon(pts2, Color("B98A55"))
		for q2 in 3:
			var off := side * CELL * (-0.53 + q2 * 0.53)
			draw_line(w2s(base - o * CELL * 0.4 + off), w2s(base + o * CELL * 1.5 + off), Color(0, 0, 0, 0.2), 1.0)
		pts2.append(pts2[0])
		draw_polyline(pts2, Art.outline, 2.0, true)
		_text_outline(w2s(base + o * CELL * 1.0) + Vector2(0, 18), "경계 +%d칸" % (2 if float(pk.get("len", 1.6)) > 2.0 else 1), 12, Color.WHITE, true)
	for h in pr.get("holes", []):
		var hp := w2s(h["pos"])
		var hr := World.Pirate.HOLE_R * k
		var jag := PackedVector2Array()
		for q3 in 14:
			var a3 := TAU * q3 / 14.0
			jag.append(hp + Vector2.from_angle(a3) * hr * (0.85 + 0.2 * float(q3 % 2)))
		draw_colored_polygon(jag, Color("0E2A36"))
		draw_circle(hp, hr * 0.6, Color(SEA_COL.darkened(0.4), 0.9))
		jag.append(jag[0])
		draw_polyline(jag, Color("6B4523"), 2.0, true)
		for q6 in 20:
			if q6 % 2 == 0:
				draw_arc(hp, hr * 1.18, TAU * q6 / 20.0, TAU * (q6 + 1) / 20.0, 4, Color("F2C14E"), 2.0, true)
		var left_r: int = maxi(1, int(h["until"]) - m.round_no + 1)
		var tag := "%d바퀴" % left_r
		var tr := Rect2(hp + Vector2(hr * 0.7, -hr * 1.4), Vector2(44, 20))
		_round_rect(tr, Color("2A1E12"), 10)
		draw_string(font_bold, tr.position + Vector2(0, 14), tag, HORIZONTAL_ALIGNMENT_CENTER, 44, 11, Color("F2C14E"))
	for rp in pr.get("ramps", []):
		var rc := w2s(rp["pos"])
		var rd: Vector2 = rp["dir"]
		var rs := rd.orthogonal()
		var tri := PackedVector2Array([rc - rd * 16.0 * k + rs * 14.0 * k, rc - rd * 16.0 * k - rs * 14.0 * k, rc + rd * 16.0 * k - rs * 14.0 * k, rc + rd * 16.0 * k + rs * 14.0 * k])
		draw_colored_polygon(tri, Color("C79A63"))
		draw_line(rc - rd * 16.0 * k, rc + rd * 16.0 * k, Color("6B4523"), 2.0, true)
		tri.append(tri[0])
		draw_polyline(tri, Art.outline, 1.5, true)
	for ch in pr.get("chests", []):
		var cc := w2s(ch["pos"])
		draw_arc(cc, (CELL + World.STONE_R) * k, 0, TAU, 40, Color("F2C14E", 0.4), 2.0, true)
		draw_rect(Rect2(cc - Vector2(11, 8) * k, Vector2(22, 16) * k), DECK_WOOD)
		draw_rect(Rect2(cc - Vector2(11, 8) * k, Vector2(22, 6) * k), Color("6B4523"))
		draw_rect(Rect2(cc - Vector2(2, 2) * k, Vector2(4, 5) * k), Color("F2C14E"))
		draw_rect(Rect2(cc - Vector2(11, 8) * k, Vector2(22, 16) * k), Art.outline, false, 1.5)
	for b in pr.get("barrels", []):
		var bp := w2s(b["pos"])
		var br := World.Pirate.BARREL_R * k
		draw_circle(bp, br, DECK_WOOD)
		draw_arc(bp, br * 0.7, 0, TAU, 20, Color("3A3F45"), 2.0, true)
		draw_arc(bp, br, 0, TAU, 20, Art.outline, 2.0, true)
	for rope in pr.get("ropes", []):
		var a = w.get_stone(int(rope["a"]))
		var bb = w.get_stone(int(rope["b"]))
		if a == null or bb == null or not a.alive or not bb.alive:
			continue
		var pa := w2s(a.pos)
		var pb := w2s(bb.pos)
		var n := int(pa.distance_to(pb) / 7.0)
		for q4 in n:
			var t2 := float(q4) / maxf(1.0, n)
			draw_arc(pa.lerp(pb, t2), 3.2, 0, TAU, 8, Color("5A6068"), 2.0, true)
	# 알 위 표식: 깃발 · 앵무새 · 연막 · 의족
	for s in w.stones:
		if not s.alive:
			continue
		var sp := w2s(s.pos)
		var u := World.STONE_R * k
		if int(s.status.get("flag", -1)) >= m.round_no:
			draw_line(sp + Vector2(u * 0.4, 0), sp + Vector2(u * 0.4, -u * 1.6), Color("6B4523"), 2.0, true)
			var wnd2 := World.Pirate.wind(w)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(u * 0.4, -u * 1.6), sp + Vector2(u * 0.4, -u * 1.0), sp + Vector2(u * 0.4, -u * 1.3) + wnd2 * u * 0.8]), Color("D2452F"))
		if s.status.has("smoke") and int(s.status["smoke"]) >= m.round_no:
			for q5 in 3:
				draw_circle(sp + Vector2.from_angle(time * 0.6 + TAU * q5 / 3.0) * u * 0.6, u * 0.55, Color(0.85, 0.87, 0.9, 0.35))
		if s.status.has("anchored"):
			draw_arc(sp, u * 1.12, 0, TAU, 24, Color("6B4523"), 3.0, true)
	for s2 in w.stones:
		for key in ["parrot", "parrot_next"]:
			if s2.alive and s2.status.has(key):
				var tgt = w.get_stone(int(s2.status[key]))
				if tgt != null and tgt.alive:
					var tp := w2s(tgt.pos) + Vector2(0, -World.STONE_R * k * 1.2)
					draw_circle(tp, 6.0 * k, Color("2FA35A"))
					draw_circle(tp + Vector2(4, -3) * k, 3.5 * k, Color("E0533D"))
					draw_arc(tp, 6.0 * k, 0, TAU, 12, Art.outline, 1.2, true)


## 위쪽: 풍향계 (이번 바퀴 바람 + 다음 바퀴 예고)
func _draw_wind_vane(vs: Vector2) -> void:
	if m == null or m.world.pirate.is_empty() or portrait:
		return
	var r := Rect2(vs.x * 0.5 + 124.0, 22, 262, 66)
	_panel(r)
	var c := r.position + Vector2(36, 33)
	var wd := World.Pirate.wind(m.world)
	draw_circle(c, 25, Color("F3EAD3"))
	draw_arc(c, 25, 0, TAU, 32, Color("2A1E12"), 2.5, true)
	for k in 4:
		var lp := c + Vector2.from_angle(-PI / 2.0 + PI / 2.0 * k) * 18.0
		draw_string(font_bold, lp + Vector2(-6, 4), ["북", "동", "남", "서"][k], HORIZONTAL_ALIGNMENT_CENTER, 12, 9, Color("2A1E12"))
	draw_line(c - wd * 18, c + wd * 18, SEA_COL, 4.0, true)
	draw_circle(c + wd * 18, 4.5, SEA_COL)
	draw_arc(c + wd * 18, 4.5, 0, TAU, 10, Color("2A1E12"), 1.5, true)
	draw_circle(c, 3.0, Color("2A1E12"))
	_txt(r.position + Vector2(72, 24), "오늘의 바람 · " + _wind_name(wd), 14, TEXT, font_bold, r.size.x - 80)
	_txt(r.position + Vector2(72, 42), _wind_users(), 11, SUB, font, r.size.x - 80)
	var nd := World.Pirate.wind_of(m.world, m.round_no + 1)
	var nc := r.position + Vector2(82, 57)
	draw_circle(nc, 8, Color("F3EAD3"))
	draw_arc(nc, 8, 0, TAU, 16, Color("2A1E12"), 1.5, true)
	draw_line(nc - nd * 5, nc + nd * 5, SEA_COL, 2.0, true)
	_txt(r.position + Vector2(96, 62), "다음 바퀴: " + _wind_name(nd), 12, TEXT, font_semi)


func _wind_name(d: Vector2) -> String:
	var idx := int(round(fposmod(d.angle(), TAU) / (PI / 4.0))) % 8
	return ["동", "남동", "남", "남서", "서", "북서", "북", "북동"][idx]


## 「바람을 받는 부품 3종, 나무 상자」: 이번 판에 나오는 바람 받는 것
func _wind_users() -> String:
	var n := 0
	for pid in ["wind_sail", "flag_signal", "oar"]:
		if m.match_parts.has(pid):
			n += 1
	var t := "바람을 받는 부품 %d종" % n
	for g in m.world.gimmicks:
		if g["kind"] == "crates":
			t += ", 나무 상자"
		elif g["kind"] == "whirlpool":
			t += ", 소용돌이"
	return t


## 망원경 · 바람돛 · 앵무새 유도: 실제로 미리 굴려 본 경로 (첫 충돌 이후까지)
func _draw_pirate_aim(info: Dictionary) -> void:
	var s = info["stone"]
	if m.world.pirate.is_empty() or info.has("cancel") or not info.has("dir"):
		return
	var need: bool = s.parts.get("weapon", "") == "spyglass" or s.parts.get("prop", "") == "wind_sail" or s.status.has("parrot_next")
	if not need:
		return
	var dir: Vector2 = info["dir"]
	var pw: float = info["power"]
	var key := "%d|%d|%d|%d" % [s.id, int(round(rad_to_deg(dir.angle()))), int(round(pw * 50.0)), m.world.turn_no]
	if key != _simpath_key:
		_simpath_key = key
		_simpath = PackedVector2Array()
		var w = m.world.clone()
		w.launch(s.id, dir, pw, {"charged": true})
		var t := 0.0
		var clk := 0.0
		while t < 3.0 and not w.is_settled():
			w.step()
			t += World.DT
			clk += World.DT
			var ss = w.get_stone(s.id)
			if ss == null or not ss.alive:
				break
			if clk >= 0.05:
				clk = 0.0
				_simpath.append(ss.pos)
	var col: Color = m.players[s.owner].color.lightened(0.35)
	for i in _simpath.size():
		if i % 2 == 0:
			draw_circle(w2s(_simpath[i]), 2.6, Color(col, 0.85))
	if not _simpath.is_empty():
		_dashed_ring(w2s(_simpath[_simpath.size() - 1]), World.STONE_R * view_scale, Color(col, 0.8))


func _on_pirate_event(e: Dictionary) -> void:
	match str(e["t"]):
		"shell":
			fx.append({"k": "line", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.5, "c": Color("2A2E35")})
			snd.play("fx_mech_shot", -2.0, 0.6)
		"cannonball":
			fx.append({"k": "line", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.6, "c": Color("1A1D21")})
			shake = maxf(shake, 6.0)
			snd.play("fx_mech_shot", 0.0, 0.5)
		"swing":
			fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.5, "r": 50.0, "c": Color("D8C08A")})
		"jump":
			fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -36), "t": 0.0, "life": 0.8, "text": "점프!", "c": Color("F2C14E"), "size": 18})
			snd.play("fx_mech_spring", -4.0, 1.3)


## 입장: 돛이 위에서 아래로 펼쳐졌다가 바람에 날려 간다.
func _draw_pirate_intro(vs: Vector2) -> void:
	var t := shutter_t
	var k := _intro_k()
	# 1.3~1.8초: 아랫단이 부풀어 오르며 갑판이 드러남 · 1.8~2.2초: 오른쪽 위로 날아감
	var lift := clampf((t - INTRO_CLOSED) / 0.5, 0.0, 1.0)
	var fly := clampf((t - INTRO_CLOSED - 0.5) / 0.4, 0.0, 1.0)
	var fe := fly * fly
	var sc := 1.0 - 0.75 * fe
	var origin := Vector2(vs.x * (1.0 - sc) * 0.5, 0) + Vector2(vs.x * 0.7, -vs.y * 0.55) * fe
	var bottom := vs.y * (1.0 - 0.45 * lift)
	var bulge := vs.y * 0.18 * lift
	var pts := PackedVector2Array()
	pts.append(origin + Vector2(0, 0))
	pts.append(origin + Vector2(vs.x * sc, 0))
	for i in 25:
		var x := 1.0 - float(i) / 24.0
		var y := bottom - sin(PI * x) * bulge
		pts.append(origin + Vector2(vs.x * x, y) * sc)
	shutter.draw_colored_polygon(pts, Color("F3E6C8", 1.0 - fe * 0.3))
	# 돛천 이음매
	for j in range(1, 7):
		var x2 := vs.x * j / 7.0
		var y2 := bottom - sin(PI * x2 / vs.x) * bulge
		shutter.draw_line(origin + Vector2(x2, 0) * sc, origin + Vector2(x2, y2) * sc, Color(0.55, 0.45, 0.3, 0.35), 2.0)
	pts.append(pts[0])
	shutter.draw_polyline(pts, Color("8A6F3E"), 3.0, true)
	shutter.draw_rect(Rect2(origin, Vector2(vs.x * sc, 14.0 * sc)), Color("6B4523"))
	if m != null and lift < 0.6:
		var a := 1.0 - lift / 0.6
		var nm: String = PartsData.WORKSHOPS["pirate"]["name"]
		var bw := font_display.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x + 56.0
		var box := Rect2(vs.x * 0.5 - bw * 0.5, vs.y * 0.42, bw, 92)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.29, 0.18, 0.1, a)
		sb.border_color = Color(0.89, 0.76, 0.48, a)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(10)
		sb.draw(shutter.get_canvas_item(), box)
		shutter.draw_string(font_bold, box.position + Vector2(0, 26), "오늘의 공방" + _mode_suffix(), HORIZONTAL_ALIGNMENT_CENTER, bw, 13, Color(0.89, 0.76, 0.48, a))
		shutter.draw_string(font_display, box.position + Vector2(0, 70), nm, HORIZONTAL_ALIGNMENT_CENTER, bw, 36, Color(0.95, 0.9, 0.8, a))
		if a > 0.99:
			_draw_intro_gimmicks(vs, box.end.y + 16.0, SEA_COL, Color.WHITE)
	if k > 0.0 and k < 0.2:
		pass


## 알에 붙은 상태: [{kind, n(남은 차례)}]
func _status_list(s) -> Array:
	var out: Array = []
	if s.status.has("hand_mark"):
		out.append({"kind": "hand", "n": 1})
	if s.status.has("bomb"):
		out.append({"kind": "bomb", "n": 1 if m.round_no > int(s.status["bomb"]["round"]) else 2})
	if float(s.status.get("minute", 0.0)) > 0.0 or float(s.status.get("shock", 0.0)) > 20.0:
		out.append({"kind": "power", "n": 0})
	if s.status.has("capsule") and not s.status.has("capsule_used"):
		out.append({"kind": "capsule", "n": 0})
	if s.status.has("bow"):
		out.append({"kind": "bow", "n": 1})
	if s.status.has("hourglass"):
		out.append({"kind": "hourglass", "n": 1})
	if s.status.has("parrot_next") or s.status.has("parrot"):
		out.append({"kind": "parrot", "n": 0})
	if int(s.status.get("flag", -1)) >= m.round_no:
		out.append({"kind": "flag", "n": int(s.status["flag"]) - m.round_no + 1})
	if not m.world.pirate.is_empty():
		for rope in m.world.pirate.get("ropes", []):
			if int(rope["a"]) == s.id or int(rope["b"]) == s.id:
				out.append({"kind": "chain", "n": int(rope["until"]) - m.round_no + 1})
				break
	if int(s.status.get("smoke", -1)) >= m.round_no:
		out.append({"kind": "smoke", "n": int(s.status["smoke"]) - m.round_no + 1})
	return out


func _status_badge(c: Vector2, n: int) -> void:
	var r := Rect2(c - Vector2(8, 8), Vector2(16, 16))
	draw_rect(r, Color("1A1D21"))
	draw_string(font_bold, r.position + Vector2(0, 13), "%d" % n, HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color("F2C14E"))


## 예약 효과 카드: 손을 올린 알에 예약된 효과가 있으면 「다음 차례에 발동」
func _draw_reserved_card() -> void:
	if m == null or hover_stone < 0 or (m.world.clock.is_empty() and m.world.pirate.is_empty()):
		return
	var s = m.world.get_stone(hover_stone)
	if s == null or not s.alive:
		return
	var what := ""
	var n := 0
	if s.status.has("bomb"):
		what = "시한 태엽 · %s 차례 끝" % m.players[s.owner].name
		n = 1 if m.round_no > int(s.status["bomb"]["round"]) else 2
	elif s.status.has("hand_mark"):
		what = "시침 표식 · %s 차례 끝" % m.players[s.owner].name
		n = 1
	elif s.status.has("bow"):
		what = "예약 석궁 · %s 차례 시작" % m.players[s.owner].name
		n = 1
	elif s.status.has("hourglass"):
		what = "모래시계 충격 · %s 차례 시작" % m.players[s.owner].name
		n = 1
	if what == "":
		return
	var p := w2s(s.pos) + Vector2(World.STONE_R * view_scale + 14, -30)
	var w := font.get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 92.0
	var r := Rect2(p, Vector2(maxf(w, 200.0), 56))
	_panel(r)
	draw_arc(r.position + Vector2(24, 28), 11, 0, TAU, 20, CLOCK_GOLD, 2.5, true)
	draw_line(r.position + Vector2(24, 28), r.position + Vector2(24, 21), TEXT, 2.0, true)
	draw_line(r.position + Vector2(24, 28), r.position + Vector2(29, 30), TEXT, 2.0, true)
	_txt(r.position + Vector2(44, 24), "다음 차례에 발동", 14, TEXT, font_bold)
	_txt(r.position + Vector2(44, 42), what, 12, SUB, font)
	_txt(Vector2(r.end.x - 14, r.position.y + 36), "%d" % n, 20, TEXT, font_bold, 30, HORIZONTAL_ALIGNMENT_RIGHT)


## 이번 차례가 끝날 때 터질 효과 수 (위쪽 바퀴 줄 옆 「차례 끝 3건」)
func _turn_end_count() -> int:
	if m == null or m.phase != "aim":
		return 0
	var cur := m.current_player()
	var n := 0
	for s in m.world.stones:
		if not s.alive:
			continue
		if s.owner == cur and s.status.has("hand_mark") and int(s.status["hand_mark"]["turn"]) < m.world.turn_no:
			n += 1
		if s.owner == cur and s.status.has("bomb") and int(s.status["bomb"]["round"]) < m.round_no:
			n += 1
		if s.owner != cur and s.status.has("metro") and s.parts.get("aux", "") == "metronome":
			n += 1
	var st: Dictionary = m.world.clock
	n += st.get("walkers", []).size()
	for rp in st.get("replays", []):
		if int(rp["owner"]) != cur:
			n += 1
	for g in m.world.gimmicks:
		if g["kind"] in ["pendulum", "clockhand", "crates"]:
			n += 1
	return n


func _draw_turn_end_chip(vs: Vector2) -> void:
	var n := _turn_end_count()
	if n <= 0 or portrait:
		return
	var t := "차례 끝 %d건" % n
	var w := font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 40.0
	var r := Rect2(vs.x * 0.5 - 112.0 - 12.0 - w, 40, w, 30)
	_round_rect(r, Color(SOLID, 0.95), 15, CLOCK_GOLD)
	draw_arc(r.position + Vector2(15, 15), 6, 0, TAU, 12, CLOCK_GOLD, 2.0, true)
	draw_string(font_bold, r.position + Vector2(26, 20), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)


# ══ 방 만들기 · 알 고르기 (기획 「방 만들기·알 고르기」, 디자인 「방 · 시작 화면 / 코드로 들어가기 / 대기실 / 알 고르기」) ══
## 대기실이 중심: 방을 만들어도, 코드로 들어와도, 판이 끝나도 모두 대기실로. 알 고르기는 어디서든 오간다.
## 자리 모델: settings.n = 자리 수(최대 인원), 자리마다 cpu / friend / empty / 그 밖(이 기기의 사람).
## settings.prof[i] = {nick, form, color, symbol, level}, settings.ready[i] = 준비 완료.
const PROFILE_PATH := "user://profile.cfg"
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # 헷갈리는 0 O 1 I L 은 쓰지 않는다
const SYMBOL_NAMES := ["원", "세모", "네모", "마름모", "육각", "십자", "두 줄", "갈매기"]
const FORM_ORDER := ["metal", "glass", "cap", "button", "hockey", "marble", "coin"]
const FORM_LOCK := {"button": ["games", 5, "아무 모드 5판"], "hockey": ["parcel", 3, "택배 쟁탈전 3승"], "marble": ["crown", 3, "왕관 쟁탈전 3승"], "coin": ["derby", 3, "개조 더비 3승"]}
const CPU_LEVELS := ["쉬움", "보통", "어려움"]
var my_profile := {"nick": "", "form": "metal", "color": 0, "symbol": 0}
var my_stats := {"games": 0, "wins": {}}
var slot_colors: Array = []
var room_peer := {}           # 대기실 자리 → 친구 연결 (경기 중 friend_peer 는 경기 자리 기준)
var match_seats: Array = []   # 경기 자리(pid) → 대기실 자리
var cpu_levels: Array = []    # 경기 자리 → CPU 난이도 0~2
var pending_join: Array = []  # 경기 중에 들어온 친구: 판이 끝나면 대기실로
var my_seat := 0              # 손님: 대기실에서 내 자리
var room_note := ""


func _load_profile() -> void:
	var cf := ConfigFile.new()
	if cf.load(PROFILE_PATH) == OK:
		my_profile["nick"] = str(cf.get_value("me", "nick", ""))
		my_profile["form"] = str(cf.get_value("me", "form", "metal"))
		my_profile["color"] = int(cf.get_value("me", "color", 0))
		my_profile["symbol"] = int(cf.get_value("me", "symbol", 0))
		var st = cf.get_value("me", "stats", {})
		if st is Dictionary:
			my_stats = st
	if not my_stats.has("wins"):
		my_stats["wins"] = {}


func _save_profile() -> void:
	var cf := ConfigFile.new()
	for k in ["nick", "form", "color", "symbol"]:
		cf.set_value("me", k, my_profile[k])
	cf.set_value("me", "stats", my_stats)
	cf.save(PROFILE_PATH)


func _form_unlocked(form: String) -> bool:
	if not FORM_LOCK.has(form):
		return true
	var need: Array = FORM_LOCK[form]
	if need[0] == "games":
		return int(my_stats.get("games", 0)) >= int(need[1])
	return int(my_stats["wins"].get(need[0], 0)) >= int(need[1])


## 판이 끝났을 때: 내 판 수 · 모드별 승리 (형태 잠금 풀기)
func _record_result() -> void:
	if m == null or my_seats.is_empty():
		return
	my_stats["games"] = int(my_stats.get("games", 0)) + 1
	for pid in my_seats:
		if m.winners.has(pid):
			my_stats["wins"][m.mode] = int(my_stats["wins"].get(m.mode, 0)) + 1
			break
	_save_profile()


func _ensure_room_arrays() -> void:
	for key in ["empty", "ready"]:
		if not settings.has(key):
			settings[key] = [false, false, false, false, false, false, false, false]
	if not settings.has("prof"):
		settings["prof"] = [{}, {}, {}, {}, {}, {}, {}, {}]
	for k in {"aim": "auto", "stones": 3, "fill": false, "skins": true, "crown_goal": 5}:
		pass
	if not settings.has("aim"):
		settings["aim"] = "auto"
	if not settings.has("stones"):
		settings["stones"] = 3
	if not settings.has("fill"):
		settings["fill"] = false
	if not settings.has("skins"):
		settings["skins"] = false
	if not settings.has("crown_goal"):
		settings["crown_goal"] = 5


func _seat_kind(i: int) -> String:
	if settings["empty"][i]:
		return "empty"
	if settings["friend"][i]:
		return "friend" if friend_peer.has(i) else "wait"
	if settings["cpu"][i]:
		return "cpu"
	return "me" if i == 0 or online == "" else "me"


## 자리마다 보여 줄 알: 이 기기 사람은 내 알, CPU 는 남는 색으로 자동.
func _refresh_seat_profiles() -> void:
	_ensure_room_arrays()
	if online == "guest":
		return
	var used := {}
	for i in settings["n"]:
		var k := _seat_kind(i)
		if k == "me" and i == 0:
			var p0: Dictionary = my_profile.duplicate()
			settings["prof"][i] = p0
		elif k == "me":
			var ph: Dictionary = settings["prof"][i] if settings["prof"][i] is Dictionary else {}
			if ph.is_empty() or str(ph.get("kind", "")) != "local":
				settings["prof"][i] = {"nick": "사람 %d" % (i + 1), "form": "metal", "color": -1, "symbol": i % 8, "kind": "local"}
		elif k == "cpu":
			var pc: Dictionary = settings["prof"][i] if settings["prof"][i] is Dictionary else {}
			if str(pc.get("kind", "")) != "cpu":
				settings["prof"][i] = {"nick": "CPU", "form": "metal", "color": -1, "symbol": i % 8, "kind": "cpu", "level": 1}
	# 색 겹침: 먼저 고른 사람(앞 자리)이 우선, 겹치거나 비어 있으면 남은 색
	for i in settings["n"]:
		if settings["empty"][i] or not (settings["prof"][i] is Dictionary) or (settings["prof"][i] as Dictionary).is_empty():
			continue
		var c := int(settings["prof"][i].get("color", -1))
		if c < 0 or used.has(c):
			c = _nearest_free_color(c, used)
		settings["prof"][i]["color"] = c
		used[c] = true
	_apply_slot_styles_from_room()


func _nearest_free_color(want: int, used: Dictionary) -> int:
	if want >= 0 and not used.has(want):
		return want
	for d in 8:
		for c in [want + d, want - d]:
			var cc: int = posmod(c, 8) if want >= 0 else d
			if not used.has(cc):
				return cc
	return 0


## 대기실 자리 모습 → 그림 표(Art.slot_*). 자리 번호가 곧 그림 칸 번호.
func _apply_slot_styles_from_room() -> void:
	for i in 8:
		var pf = settings["prof"][i] if i < settings["n"] else {}
		var ok: bool = pf is Dictionary and not (pf as Dictionary).is_empty()
		slot_colors[i] = Match.COLORS[int(pf.get("color", i))] if ok else Match.COLORS[i]
		Art.slot_symbols[i] = int(pf.get("symbol", i)) if ok else i
		Art.slot_forms[i] = str(pf.get("form", "metal")) if ok else "metal"


## 경기 자리 모습 → 그림 표 (팀전 색 포함)
func _apply_slot_styles_from_match() -> void:
	if OS.get_cmdline_user_args().has("--dbgslot"):
		print("SLOT ", m.players.map(func(p): return [p.get("form", "-"), p.get("symbol", -1), p.name]))
	for i in 8:
		if m != null and i < m.n:
			slot_colors[i] = m.players[i].color
			Art.slot_symbols[i] = int(m.players[i].get("symbol", i))
			Art.slot_forms[i] = str(m.players[i].get("form", "metal"))
		else:
			slot_colors[i] = Match.COLORS[i]
			Art.slot_symbols[i] = i
			Art.slot_forms[i] = "metal"


## 알 하나 그림 컨트롤
func _puck_view(prof: Dictionary, size: float, team_col := Color(0, 0, 0, 0)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var u := size * 0.42
		var col: Color = team_col if team_col.a > 0.0 else Match.COLORS[clampi(int(prof.get("color", 0)), 0, 7)]
		Art.draw_puck_shadow(c, c.size * 0.5, u)
		Art.draw_puck_form(c, c.size * 0.5 + Vector2(0, -0.06 * u), u, col, int(prof.get("symbol", 0)), str(prof.get("form", "metal")), -PI / 2.0))
	return c


# ── 시작 화면 ────────────────────────────────────────────
func _show_home() -> void:
	state = "home"
	m = null
	menu_btn.visible = false
	parts_btn.visible = false
	sound_btn.visible = false
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var narrow := vs.x < 900
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.position = Vector2(80.0 if not narrow else 24.0, maxf(40.0, vs.y * 0.12))
	col.custom_minimum_size = Vector2(minf(440.0, vs.x - 48.0), 0)
	root.add_child(col)
	var title := _nw(_label("개조 알까기", 64 if not narrow else 44, TEXT, 3))
	col.add_child(title)
	col.add_child(_label("알을 튕겨 판 밖으로, 부품으로 개조해서.", 17, SUB))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)
	var make := _primary(_button("방 만들기", func(): _create_room()))
	make.custom_minimum_size = Vector2(0, 64)
	make.add_theme_font_size_override("font_size", 22)
	col.add_child(make)
	var join := _button("방 코드로 들어가기", func(): _show_join(""))
	join.custom_minimum_size = Vector2(0, 58)
	join.add_theme_font_size_override("font_size", 19)
	col.add_child(join)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var solo := _button("혼자 연습 (CPU)", func(): _start_solo())
	solo.custom_minimum_size = Vector2(0, 52)
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(solo)
	var deco := _button("알 꾸미기", func(): _show_puck_picker("home"))
	deco.custom_minimum_size = Vector2(0, 52)
	deco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(deco)
	col.add_child(row)
	col.add_child(_label("친구가 보낸 링크로 들어오면 이 화면 없이 바로 대기실로 가요.", 13, SUB))
	# 오른쪽: 여러 형태의 알을 흩어 놓은 판
	if not narrow:
		var art := Control.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2(vs.x * 0.52, vs.y * 0.18)
		art.size = Vector2(vs.x * 0.42, vs.y * 0.6)
		art.draw.connect(func():
			var c0 := art.size * 0.5
			var rx := art.size.x * 0.48
			var ry := art.size.y * 0.46
			var pts := PackedVector2Array()
			for i in 48:
				pts.append(c0 + Vector2(cos(TAU * i / 48.0) * rx, sin(TAU * i / 48.0) * ry))
			art.draw_colored_polygon(pts, Color("2E6F5E"))
			pts.append(pts[0])
			art.draw_polyline(pts, Color("C9A15A"), 10.0, true)
			var spots := [[Vector2(-0.5, -0.25), "metal", 0, 0, 0.1], [Vector2(-0.02, -0.45), "glass", 1, 1, 0.085], [Vector2(0.5, -0.1), "cap", 2, 2, 0.08],
				[Vector2(-0.15, 0.32), "coin", 3, 3, 0.075], [Vector2(0.38, 0.42), "metal", 4, 4, 0.085]]
			for sp in spots:
				var p: Vector2 = c0 + Vector2(sp[0].x * rx, sp[0].y * ry)
				var u: float = art.size.y * float(sp[4])
				Art.draw_puck_shadow(art, p, u)
				Art.draw_puck_form(art, p, u, Match.COLORS[int(sp[2])], int(sp[3]), str(sp[1]), -PI / 2.0))
		root.add_child(art)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 8)
	icons.position = Vector2(vs.x - 24.0 - 96.0, 24.0)
	icons.add_child(_icon_button("gear", func(): _show_settings(false), "설정"))
	icons.add_child(_icon_button("sound" if snd.enabled else "mute", func():
		_toggle_sound()
		_show_home(), "소리"))
	root.add_child(icons)
	if str(my_profile.get("nick", "")) == "":
		_ask_nick()


## 처음 실행: 닉네임을 한 번 묻고, 기본 알(금속 퍽, 무작위 색·기호)을 정해 둔다.
func _ask_nick() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	overlay.add_child(root)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.96)))
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(minf(420.0, get_viewport_rect().size.x - 40.0), 0)
	pc.add_child(v)
	v.add_child(_label("닉네임을 정해 주세요", 22, TEXT, 2))
	v.add_child(_label("방에서 친구들에게 보이는 이름이에요. 나중에 알 꾸미기에서 바꿀 수 있어요.", 13, SUB))
	var le := LineEdit.new()
	le.max_length = 10
	le.placeholder_text = "알까기왕"
	le.custom_minimum_size = Vector2(0, 48)
	le.add_theme_font_size_override("font_size", 18)
	v.add_child(le)
	var ok := _primary(_button("좋아요", func():
		var t := le.text.strip_edges()
		my_profile["nick"] = t if t != "" else "알까기왕"
		my_profile["color"] = randi() % 8
		my_profile["symbol"] = randi() % 8
		_save_profile()
		root.queue_free()))
	ok.custom_minimum_size = Vector2(0, 50)
	v.add_child(ok)
	le.grab_focus()


func _create_room() -> void:
	_reset_room(4)
	if net.available:
		_start_hosting()
	else:
		_show_setup()


func _start_solo() -> void:
	if online != "":
		_leave_online()
	_reset_room(4)
	for i in range(1, 4):
		settings["cpu"][i] = true
		settings["empty"][i] = false
	_show_setup()


## 새 방: 내 자리 하나, 나머지는 빈 자리
func _reset_room(n: int) -> void:
	_ensure_room_arrays()
	settings["n"] = n
	for i in 8:
		settings["cpu"][i] = false
		settings["friend"][i] = false
		settings["empty"][i] = i > 0
		settings["ready"][i] = false
		settings["prof"][i] = {}
	settings["timed"] = false


# ── 코드로 들어가기 ──────────────────────────────────────
func _show_join(prefill: String) -> void:
	state = "join"
	var root := _new_overlay(true)
	var box := _centered_panel(root, minf(640.0, get_viewport_rect().size.x - 32.0))
	box.add_theme_constant_override("separation", 16)
	var t := _label("방 코드로 들어가기", 26, TEXT, 2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(_label("방장이 알려준 6자리 코드를 입력하세요. 숫자 0과 영문 O처럼 헷갈리는 글자는 쓰지 않아요.", 14, SUB))
	var code := LineEdit.new()
	code.max_length = 6
	code.text = prefill.to_upper()
	code.placeholder_text = "TEK7RA"
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.custom_minimum_size = Vector2(0, 76)
	code.add_theme_font_override("font", font_display)
	code.add_theme_font_size_override("font_size", 40)
	code.text_changed.connect(func(tx: String):
		var clean := ""
		for ch in tx.to_upper():
			if CODE_CHARS.contains(ch):
				clean += ch
		if clean != tx:
			code.text = clean
			code.caret_column = clean.length())
	box.add_child(code)
	box.add_child(_label("닉네임", 13, LABEL, 1))
	var nick := LineEdit.new()
	nick.max_length = 10
	nick.text = str(my_profile["nick"])
	nick.custom_minimum_size = Vector2(0, 48)
	nick.add_theme_font_size_override("font_size", 16)
	box.add_child(nick)
	var me := HBoxContainer.new()
	me.add_theme_constant_override("separation", 14)
	me.add_child(_puck_view(my_profile, 56))
	var mv := VBoxContainer.new()
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_child(_label("내 알 · %s · %s %s" % [Art.FORM_NAMES.get(my_profile["form"], "금속 퍽"), Match.NAMES[int(my_profile["color"])], SYMBOL_NAMES[int(my_profile["symbol"])]], 14, TEXT, 2))
	mv.add_child(_label("방에 같은 색이 있으면 들어간 뒤 다른 색을 골라요", 12, SUB))
	me.add_child(mv)
	me.add_child(_button("바꾸기", func():
		my_profile["nick"] = nick.text.strip_edges() if nick.text.strip_edges() != "" else my_profile["nick"]
		_show_puck_picker("join:" + code.text)))
	box.add_child(me)
	var go := _primary(_button("들어가기", func():
		if code.text.length() != 6:
			_banner("코드 6자리를 모두 넣어 주세요")
			return
		var nt := nick.text.strip_edges()
		if nt != "":
			my_profile["nick"] = nt
			_save_profile()
		_join_room(code.text.to_lower())))
	go.custom_minimum_size = Vector2(0, 58)
	go.add_theme_font_size_override("font_size", 20)
	box.add_child(go)
	box.add_child(_button("뒤로", func(): _show_home()))
	code.grab_focus()


# ── 알 고르기 ────────────────────────────────────────────
## from: "home" (기본 알로 저장) · "room" (이 방에서만, 「기본으로도 저장」 선택) · "join:<코드>"
var picker_prof := {}
var picker_from := ""
var picker_save := true
var picker_skin := ""


func _show_puck_picker(from: String) -> void:
	picker_from = from
	picker_prof = my_profile.duplicate()
	if from == "room" and online == "guest" and guest_lobby.has("seats"):
		var mine: Dictionary = guest_lobby["seats"][my_seat].get("prof", {})
		if not mine.is_empty():
			picker_prof = mine.duplicate()
	picker_save = from != "room"
	_build_picker()


func _taken_colors() -> Dictionary:
	# 이 방에서 다른 사람이 쓰는 색 → 이름
	var out := {}
	if picker_from != "room":
		return out
	if online == "guest" and guest_lobby.has("seats"):
		var seats: Array = guest_lobby["seats"]
		for i in seats.size():
			if i == my_seat or str(seats[i].get("kind", "")) == "empty":
				continue
			var pf: Dictionary = seats[i].get("prof", {})
			if not pf.is_empty():
				out[int(pf.get("color", -1))] = str(pf.get("nick", ""))
		return out
	for i in range(1, settings["n"]):
		if settings["empty"][i]:
			continue
		var pf2 = settings["prof"][i]
		if pf2 is Dictionary and not pf2.is_empty():
			out[int(pf2.get("color", -1))] = str(pf2.get("nick", ""))
	return out


func _build_picker() -> void:
	var root := _new_overlay(true)
	var vs := get_viewport_rect().size
	var narrow := vs.x < 900
	var wrap: BoxContainer = HBoxContainer.new() if not narrow else VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 20)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, 24 if not narrow else 12)
	sc.add_child(holder)
	holder.add_child(wrap)
	# 왼쪽: 크게 미리보기 + 실제 판 크기
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.95)))
	lp.custom_minimum_size = Vector2(380 if not narrow else 0, 0)
	wrap.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	lp.add_child(lv)
	lv.add_child(_label("내 알", 24, TEXT, 2))
	var big := Control.new()
	big.custom_minimum_size = Vector2(320, 300 if not narrow else 220)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.draw.connect(func():
		var c0 := big.size * 0.5
		var R := minf(big.size.x, big.size.y) * 0.48
		big.draw_circle(c0, R + 8, Color("C9A15A"))
		big.draw_circle(c0, R, Color("2E6F5E"))
		var col: Color = Match.COLORS[int(picker_prof["color"])]
		var skin_before: String = Art.skin
		Art.skin = picker_skin
		var u := R * 0.5
		Art.draw_puck_shadow(big, c0, u)
		if picker_skin != "":
			Art.draw_puck_form(big, c0, u, col, int(picker_prof["symbol"]), "metal", -PI / 2.0)
		else:
			Art.draw_puck_form(big, c0, u, col, int(picker_prof["symbol"]), str(picker_prof["form"]), -PI / 2.0)
		# 실제 크기 (판 위에서 보이는 크기)
		var su := 15.0
		var sp := c0 + Vector2(-R * 0.62, R * 0.62)
		Art.draw_puck_shadow(big, sp, su)
		Art.draw_puck_form(big, sp, su, col, int(picker_prof["symbol"]), "metal" if picker_skin != "" else str(picker_prof["form"]), -PI / 2.0)
		big.draw_string(font, sp + Vector2(24, 6), "실제 크기", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		Art.skin = skin_before)
	lv.add_child(big)
	var desc := PanelContainer.new()
	desc.add_theme_stylebox_override("panel", _sb(Color(FG, 0.05), Color(FG, 0.12), 10))
	var dv := VBoxContainer.new()
	desc.add_child(dv)
	dv.add_child(_label("%s · %s · %s" % [Art.FORM_NAMES.get(picker_prof["form"], ""), Match.NAMES[int(picker_prof["color"])], SYMBOL_NAMES[int(picker_prof["symbol"])]], 16, TEXT, 2))
	dv.add_child(_label("판 위에서는 이 모습에 부품이 붙고, 공방 스킨을 켠 방에서는 공방 재질로 바뀌어요.", 12, SUB))
	lv.add_child(desc)
	var skr := HBoxContainer.new()
	skr.alignment = BoxContainer.ALIGNMENT_CENTER
	skr.add_theme_constant_override("separation", 6)
	skr.add_child(_nw(_label("미리보기 공방", 13, SUB)))
	skr.add_child(_seg([["", "기본"], ["clock", "시계탑"], ["pirate", "선착장"], ["magic", "마법"]], picker_skin, func(k):
		picker_skin = k
		_build_picker()))
	lv.add_child(skr)
	# 오른쪽: 형태 → 색 → 기호
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.95)))
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	rp.add_child(rv)
	rv.add_child(_label("형태", 18, TEXT, 2))
	var fg := GridContainer.new()
	fg.columns = 7 if not narrow else 4
	fg.add_theme_constant_override("h_separation", 8)
	fg.add_theme_constant_override("v_separation", 8)
	for form in FORM_ORDER:
		var f: String = form
		var unlocked := _form_unlocked(f)
		var b := _button("", func():
			if not _form_unlocked(f):
				_banner("잠긴 형태", ACCENT, FORM_LOCK[f][2] + "하면 열려요")
				return
			picker_prof["form"] = f
			_build_picker())
		b.custom_minimum_size = Vector2(84, 104)
		var on: bool = picker_prof["form"] == f
		b.add_theme_stylebox_override("normal", _sb(Color(BRASS, 0.18) if on else Color(FG, 0.05), BRASS if on else Color(FG, 0.12), 10))
		var bv := VBoxContainer.new()
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pv := _puck_view({"form": f, "color": picker_prof["color"], "symbol": picker_prof["symbol"]}, 48)
		pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pv.modulate.a = 1.0 if unlocked else 0.45
		bv.add_child(pv)
		var nl := _label(Art.FORM_NAMES[f], 12, TEXT, 1)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(nl)
		if not unlocked:
			var ll := _label("🔒 " + str(FORM_LOCK[f][2]), 10, SUB)
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bv.add_child(ll)
		b.add_child(bv)
		fg.add_child(b)
	rv.add_child(fg)
	var ch := HBoxContainer.new()
	var cl := _nw(_label("색", 18, TEXT, 2))
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(cl)
	if picker_from == "room":
		ch.add_child(_nw(_label("흐린 색은 이 방에서 이미 쓰는 색이에요", 12, SUB)))
	rv.add_child(ch)
	var taken := _taken_colors()
	var cg := HBoxContainer.new()
	cg.add_theme_constant_override("separation", 10)
	for ci in 8:
		var cidx: int = ci
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		var b2 := _button("✓" if int(picker_prof["color"]) == ci else "", func():
			if taken.has(cidx):
				_banner("%s 님이 쓰는 색이에요" % taken[cidx])
				return
			picker_prof["color"] = cidx
			_build_picker())
		b2.custom_minimum_size = Vector2(48, 48)
		var cc: Color = Match.COLORS[ci]
		var sbx := _sb(Color(cc, 0.35 if taken.has(ci) else 1.0), INK if int(picker_prof["color"]) == ci else Color(0, 0, 0, 0.2), 24)
		sbx.set_border_width_all(4 if int(picker_prof["color"]) == ci else 1)
		b2.add_theme_stylebox_override("normal", sbx)
		b2.add_theme_stylebox_override("hover", sbx)
		b2.add_theme_color_override("font_color", Color.WHITE)
		cv.add_child(b2)
		var nm := _label(str(taken.get(ci, Match.NAMES[ci])), 11, SUB)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.custom_minimum_size = Vector2(48, 0)
		nm.clip_text = true
		cv.add_child(nm)
		cg.add_child(cv)
	rv.add_child(cg)
	var sh := HBoxContainer.new()
	var sl := _nw(_label("각인 기호", 18, TEXT, 2))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sl)
	sh.add_child(_nw(_label("색이 비슷해도 기호로 구별돼요 · 기호는 겹쳐도 괜찮아요", 12, SUB)))
	rv.add_child(sh)
	var sg := HBoxContainer.new()
	sg.add_theme_constant_override("separation", 8)
	for si in 8:
		var sidx: int = si
		var b3 := _button("", func():
			picker_prof["symbol"] = sidx
			_build_picker())
		b3.custom_minimum_size = Vector2(46, 46)
		var on3: bool = int(picker_prof["symbol"]) == si
		b3.add_theme_stylebox_override("normal", _sb(Color(BRASS, 0.18) if on3 else Color(FG, 0.05), BRASS if on3 else Color(FG, 0.12), 10))
		var sv := Control.new()
		sv.set_anchors_preset(Control.PRESET_FULL_RECT)
		sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sv.draw.connect(func(): Art.draw_symbol(sv, sidx, TEXT, 1.0, sv.size * 0.5, 1.2, false))
		b3.add_child(sv)
		sg.add_child(b3)
	rv.add_child(sg)
	if picker_from == "room":
		var keep := CheckBox.new()
		keep.text = "기본 알로도 저장"
		keep.button_pressed = picker_save
		keep.toggled.connect(func(on: bool): picker_save = on)
		rv.add_child(keep)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(spacer)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 12)
	br.add_child(_button("뒤로", func(): _picker_back()))
	br.add_child(_button("무작위", func():
		var free_forms := FORM_ORDER.filter(func(x): return _form_unlocked(x))
		picker_prof["form"] = free_forms[randi() % free_forms.size()]
		var cs: Array = range(8).filter(func(x): return not taken.has(x))
		picker_prof["color"] = cs[randi() % cs.size()] if not cs.is_empty() else 0
		picker_prof["symbol"] = randi() % 8
		_build_picker()))
	var ok := _primary(_button("이 알로 하기", func(): _picker_done()))
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.custom_minimum_size = Vector2(0, 54)
	ok.add_theme_font_size_override("font_size", 19)
	br.add_child(ok)
	rv.add_child(br)


func _picker_back() -> void:
	if picker_from == "home":
		_show_home()
	elif picker_from.begins_with("join:"):
		_show_join(picker_from.substr(5))
	else:
		_show_setup()


func _picker_done() -> void:
	var nick: String = my_profile["nick"]
	if picker_from != "room" or picker_save:
		for k in ["form", "color", "symbol"]:
			my_profile[k] = picker_prof[k]
		_save_profile()
	if picker_from == "room":
		var pf := picker_prof.duplicate()
		pf["nick"] = nick
		if online == "guest":
			net.send_to(host_peer, {"t": "prof", "prof": pf})
		else:
			for k in ["form", "color", "symbol"]:
				my_profile[k] = pf[k]
			_refresh_seat_profiles()
			_host_broadcast_lobby()
	_picker_back()


# ── 대기실 ───────────────────────────────────────────────
func _room_settings_changed() -> void:
	# 방장이 설정을 바꾸면 모두의 준비가 풀린다
	for i in 8:
		settings["ready"][i] = false
	if online == "host":
		_host_broadcast_lobby()
	_show_setup()


## 대기실에 보여 줄 자리 목록 [{kind, prof, ready, host}]
func _room_seats() -> Array:
	if online == "guest":
		return guest_lobby.get("seats", [])
	var out: Array = []
	for i in settings["n"]:
		out.append({"kind": _seat_kind(i), "prof": settings["prof"][i] if settings["prof"][i] is Dictionary else {}, "ready": settings["ready"][i] or _seat_kind(i) == "cpu", "host": i == 0 and online != ""})
	return out


func _room_cfg(key: String, def = null):
	if online == "guest":
		return guest_lobby.get("cfg", {}).get(key, def)
	return settings.get(key, def)


func _show_room() -> void:
	state = "setup"
	m = null
	menu_btn.visible = false
	parts_btn.visible = false
	sound_btn.visible = false
	_ensure_room_arrays()
	_refresh_seat_profiles()
	var host_side := online != "guest"
	if online == "guest" and guest_lobby.has("seats"):
		for i in 8:
			var seats0: Array = guest_lobby["seats"]
			if i < seats0.size():
				var pf0: Dictionary = seats0[i].get("prof", {})
				slot_colors[i] = Match.COLORS[int(pf0.get("color", i))]
				Art.slot_symbols[i] = int(pf0.get("symbol", i))
				Art.slot_forms[i] = str(pf0.get("form", "metal"))
	var root := _lobby_root()
	var vs := get_viewport_rect().size
	var narrow := vs.x < 900
	var left_w := (vs.x - 48.0 - 24.0) * 0.6 if not narrow else vs.x - 24.0
	var right_w := (vs.x - 48.0 - 24.0) * 0.4 if not narrow else vs.x - 24.0
	# 왼쪽 판: 방 코드 · 자리 · 아래 버튼
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.92)))
	lp.custom_minimum_size = Vector2(left_w, 0)
	lp.position = Vector2(24.0 if not narrow else 12.0, 24.0)
	root.add_child(lp)
	lobby_col = lp
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	lp.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if online != "":
		hv.add_child(_label("방 코드", 13, SUB, 1))
		var code_txt: String = net.code().to_upper() if net.code() != "" else "······"
		hv.add_child(_nw(_label(code_txt, 46, TEXT, 3)))
	else:
		hv.add_child(_nw(_label("혼자 연습", 34, TEXT, 3)))
		hv.add_child(_label("이 기기에서만 두는 방이에요. 빈 자리는 CPU나 같은 기기 사람으로 채워요.", 12, SUB))
	head.add_child(hv)
	if online != "":
		var link := _button("링크 복사", func():
			net.copy(net.invite_url(net.code()))
			_banner("링크를 복사했어요"))
		link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(link)
		var show := _button("코드 보여주기", func(): _show_code_big())
		show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(show)
	head.add_child(_icon_button("book", func(): _show_catalog(true), "부품 도감"))
	head.add_child(_icon_button("gear", func(): _show_settings(true), "설정 (맵 · 게임 속도 · 소리)"))
	col.add_child(head)
	var seats := _room_seats()
	var filled := 0
	for st in seats:
		if str(st.get("kind", "")) != "empty":
			filled += 1
	var info := HBoxContainer.new()
	var il := _nw(_label("참가자 %d / %d" % [filled, seats.size()], 14, TEXT, 2))
	il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(il)
	info.add_child(_nw(_label("방장이 모드와 공방을 정하고, 모두 준비하면 시작해요" if online != "" else "모드와 공방을 정하고 시작하세요", 12, SUB)))
	col.add_child(info)
	if room_note != "":
		col.add_child(_label(room_note, 13, HINT_GOLD, 1))
	var mode_now: String = _room_cfg("mode", "survival")
	if mode_now == "parcel" and host_side:
		col.add_child(_team_panel(narrow))
	else:
		var grid := GridContainer.new()
		grid.columns = 4 if not narrow else 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for i in seats.size():
			grid.add_child(_seat_card(i, seats[i], host_side))
		col.add_child(grid)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 10)
	bot.add_child(_button("내 알 바꾸기", func(): _show_puck_picker("room")))
	if online == "guest":
		var mine_ready := false
		if seats.size() > my_seat:
			mine_ready = bool(seats[my_seat].get("ready", false))
		var rb := _button("준비 취소" if mine_ready else "준비 완료", func():
			net.send_to(host_peer, {"t": "ready", "on": not mine_ready}))
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.custom_minimum_size = Vector2(0, 52)
		if not mine_ready:
			_primary(rb)
		bot.add_child(rb)
	if online != "":
		bot.add_child(_button("나가기", func():
			_leave_online()
			_show_home()))
	else:
		bot.add_child(_button("처음으로", func(): _show_home()))
	col.add_child(bot)
	# 오른쪽 판: 방 설정 + 시작하기
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.92)))
	rp.custom_minimum_size = Vector2(right_w, 0)
	rp.position = Vector2(lp.position.x + left_w + 24.0, 24.0) if not narrow else Vector2(12.0, 24.0 + 640.0)
	root.add_child(rp)
	lobby_col2 = rp
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	rp.add_child(rv)
	var rh := HBoxContainer.new()
	var rt := _nw(_label("방 설정", 20, TEXT, 2))
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(rt)
	if online != "":
		rh.add_child(_nw(_label("👑 방장만 바꿀 수 있어요", 12, HINT_GOLD)))
	rv.add_child(rh)
	_room_settings_ui(rv, host_side, filled)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sp2)
	if host_side:
		var why := _start_blocker(seats)
		var sb_ := _primary(_button("시작하기" if why == "" else "시작하기", func():
			var w2 := _start_blocker(_room_seats())
			if w2 != "":
				_banner(w2)
				return
			_start_from_room()))
		sb_.custom_minimum_size = Vector2(0, 60)
		sb_.add_theme_font_size_override("font_size", 21)
		if why != "":
			sb_.modulate.a = 0.55
		rv.add_child(sb_)
		if why != "":
			var wl := _label(why, 12, SUB)
			wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rv.add_child(wl)
	else:
		var wl2 := _label("방장이 시작하길 기다리고 있어요", 13, SUB)
		wl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rv.add_child(wl2)


## 시작할 수 없는 이유 (없으면 "")
func _start_blocker(seats: Array) -> String:
	var people := 0
	var waiting: Array = []
	for st in seats:
		var k := str(st.get("kind", ""))
		if k == "empty":
			if settings.get("fill", false):
				people += 1
			continue
		if k == "wait":
			waiting.append("친구 자리")
			continue
		people += 1
		if k == "friend" and not bool(st.get("ready", false)):
			waiting.append(str(st.get("prof", {}).get("nick", "친구")))
	if people < 2:
		return "두 명 이상이어야 시작할 수 있어요 · 빈 자리에 CPU를 넣어 보세요"
	if settings.get("mode", "survival") == "parcel" and not [4, 6, 8].has(people):
		return "택배 쟁탈전은 4·6·8명일 때 가능해요"
	if not waiting.is_empty():
		return "%s 님이 아직 준비 중이에요" % ", ".join(waiting)
	return ""


## 자리 카드: 알 · 닉네임 · 방장/CPU 표시 · 준비 상태. 빈 자리는 「+ CPU」.
func _seat_card(i: int, st: Dictionary, editable: bool) -> Control:
	var kind := str(st.get("kind", "empty"))
	var pf: Dictionary = st.get("prof", {})
	var mine := (online != "guest" and i == 0) or (online == "guest" and i == my_seat)
	var b := _button("", func(): _seat_menu(i, kind))
	b.custom_minimum_size = Vector2(150, 108)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := BRASS if mine else Color(FG, 0.14)
	if kind == "empty":
		var es := _sb(Color(0, 0, 0, 0), Color(FG, 0.25), 12)
		es.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", es)
		var ev := VBoxContainer.new()
		ev.set_anchors_preset(Control.PRESET_FULL_RECT)
		ev.alignment = BoxContainer.ALIGNMENT_CENTER
		ev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var el := _label("빈 자리", 13, SUB)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ev.add_child(el)
		if editable:
			var pl := _label("+ CPU" + ("  ·  + 사람" if online == "" else ""), 13, TEXT, 2)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ev.add_child(pl)
		b.add_child(ev)
		return b
	var sb := _sb(Color(FG, 0.06), border, 12)
	sb.set_border_width_all(3 if mine else 1)
	b.add_theme_stylebox_override("normal", sb)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -8
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not pf.is_empty():
		var pv := _puck_view(pf, 54)
		pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pv)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	var nm := "나" if mine else str(pf.get("nick", "친구"))
	if kind == "wait":
		nm = "친구 자리"
	var nl := _nw(_label(nm, 16, TEXT, 2))
	nl.clip_text = true
	v.add_child(nl)
	var role := "참가자"
	if bool(st.get("host", false)):
		role = "👑 방장"
	elif kind == "cpu":
		role = "CPU · " + CPU_LEVELS[clampi(int(pf.get("level", 1)), 0, 2)]
	elif kind == "wait":
		role = "접속 기다리는 중"
	elif kind == "me" and online == "" and i > 0:
		role = "같은 기기"
	v.add_child(_nw(_label(role, 11, SUB)))
	if online != "" and kind != "wait":
		var rdy: bool = bool(st.get("ready", false)) or bool(st.get("host", false))
		var pill := _label(("준비 완료" if not bool(st.get("host", false)) else "방장") if rdy else "고르는 중", 11, Color.WHITE if rdy else SUB, 2)
		var pp := PanelContainer.new()
		var ps := _sb(Color("2E7D57") if rdy else Color(FG, 0.1), Color(0, 0, 0, 0), 999)
		ps.content_margin_left = 8
		ps.content_margin_right = 8
		ps.content_margin_top = 1
		ps.content_margin_bottom = 1
		pp.add_theme_stylebox_override("panel", ps)
		pp.add_child(pill)
		pp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pp)
	h.add_child(v)
	b.add_child(h)
	return b


## 자리 카드를 눌렀을 때 (방장): 빈 자리는 CPU/사람 넣기, CPU 는 난이도·빼기, 친구는 내보내기
func _seat_menu(i: int, kind: String) -> void:
	if online == "guest":
		if i == my_seat:
			_show_puck_picker("room")
		return
	if i == 0:
		_show_puck_picker("room")
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			root.queue_free())
	root.add_child(dim)
	overlay.add_child(root)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(SOLID, 0.97)))
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(260, 0)
	pc.add_child(v)
	v.add_child(_label("%d번 자리" % (i + 1), 18, TEXT, 2))
	var act := func(f: Callable):
		root.queue_free()
		f.call()
		_room_settings_changed()
	match kind:
		"empty":
			v.add_child(_button("+ CPU 넣기", func(): act.call(func():
				settings["empty"][i] = false
				settings["cpu"][i] = true)))
			if online == "":
				v.add_child(_button("+ 같은 기기 사람", func(): act.call(func():
					settings["empty"][i] = false
					settings["cpu"][i] = false)))
			else:
				v.add_child(_button("친구 자리로 비워 두기", func(): act.call(func():
					settings["empty"][i] = false
					settings["friend"][i] = true)))
		"cpu":
			for lv in 3:
				var lvl: int = lv
				v.add_child(_button("난이도: " + CPU_LEVELS[lv], func(): act.call(func():
					settings["prof"][i]["level"] = lvl)))
			v.add_child(_button("자리 비우기", func(): act.call(func():
				settings["cpu"][i] = false
				settings["empty"][i] = true)))
		"friend", "wait":
			v.add_child(_button("내보내기", func(): act.call(func():
				if room_peer.has(i) or friend_peer.has(i):
					net.send_to(friend_peer.get(i, ""), {"t": "full", "why": "방장이 내보냈어요"})
					friend_peer.erase(i)
				settings["friend"][i] = false
				settings["empty"][i] = true)))
		_:
			v.add_child(_button("자리 비우기", func(): act.call(func():
				settings["empty"][i] = true)))
	v.add_child(_button("닫기", func(): root.queue_free()))


## 방 설정 (방장만 바꾼다). 손님은 같은 화면을 읽기 전용으로.
func _room_settings_ui(rv: VBoxContainer, editable: bool, people: int) -> void:
	var cur_mode: String = _room_cfg("mode", "survival")
	rv.add_child(_label("모드", 13, LABEL, 1))
	var mg := GridContainer.new()
	mg.columns = 2
	mg.add_theme_constant_override("h_separation", 8)
	mg.add_theme_constant_override("v_separation", 8)
	for md in [["survival", "최후 생존전"], ["derby", "개조 더비"], ["parcel", "택배 쟁탈전"], ["crown", "왕관 쟁탈전"]]:
		var key: String = md[0]
		var b := _button(md[1], func():
			if not editable:
				return
			settings["mode"] = key
			if key == "parcel":
				_fix_parcel_count()
			_room_settings_changed())
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := cur_mode == key
		var dim_parcel := key == "parcel" and not [4, 6, 8].has(people) and not on
		b.add_theme_stylebox_override("normal", _sb(BRASS if on else Color(FG, 0.05), Color(FG, 0.12), 8))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, INK if on else (Color(TEXT, 0.45) if dim_parcel else TEXT))
		if dim_parcel:
			b.tooltip_text = "4·6·8명일 때 가능"
		mg.add_child(b)
	rv.add_child(mg)
	var mdesc := {"survival": "마지막까지 살아남기 · 2~8인", "derby": "정해진 바퀴 동안 많이 떨어뜨리기 · 2~8인",
		"parcel": "택배를 우리 진영으로 · 팀전 4·6·8인", "crown": "왕관을 뺏고 버티기 · %d점 선취 · 2~8인" % int(_room_cfg("crown_goal", 5))}
	rv.add_child(_label(mdesc.get(cur_mode, ""), 12, SUB))
	rv.add_child(_label("공방", 13, LABEL, 1))
	var wg := GridContainer.new()
	wg.columns = 4
	wg.add_theme_constant_override("h_separation", 6)
	wg.add_theme_constant_override("v_separation", 6)
	var cur_ws: String = _room_cfg("workshop", "random")
	for ws in [["random", "무작위"], ["junk", "정비소"], ["magic", "마법"], ["toon", "만화"], ["lab", "연구소"], ["clock", "시계탑"], ["pirate", "선착장"]]:
		var wk: String = ws[0]
		var b2 := _button(ws[1], func():
			if editable:
				settings["workshop"] = wk
				_room_settings_changed())
		b2.custom_minimum_size = Vector2(0, 36)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on2 := cur_ws == wk
		b2.add_theme_stylebox_override("normal", _sb(BRASS if on2 else Color(FG, 0.05), Color(FG, 0.12), 8))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b2.add_theme_color_override(c, INK if on2 else TEXT)
		wg.add_child(b2)
	rv.add_child(wg)
	# 작은 설정 칸: 눌러서 다음 값으로
	var opts := GridContainer.new()
	opts.columns = 2
	opts.add_theme_constant_override("h_separation", 8)
	opts.add_theme_constant_override("v_separation", 8)
	var n_now := int(guest_lobby.get("n", settings["n"])) if online == "guest" else int(settings["n"])
	opts.add_child(_opt_cell("최대 인원", "%d명" % n_now, editable, func():
		var nn := n_now + 1
		if nn > 8:
			nn = 2
		_set_room_size(nn)))
	var aim: String = str(_room_cfg("aim", "auto"))
	var aim_txt: String = {"auto": "인원 따라 (5인 이상 12초)", "none": "제한 없음", "8": "8초", "12": "12초"}.get(aim, aim)
	opts.add_child(_opt_cell("조준 시간", aim_txt, editable, func():
		var order := ["auto", "none", "8", "12"]
		settings["aim"] = order[(order.find(aim) + 1) % order.size()]
		_room_settings_changed()))
	if cur_mode == "survival" or cur_mode == "derby":
		var stn := int(_room_cfg("stones", 3))
		opts.add_child(_opt_cell("알 개수", "%d개씩" % stn, editable, func():
			settings["stones"] = 2 if stn == 3 else 3
			_room_settings_changed()))
	if cur_mode == "crown":
		var cg := int(_room_cfg("crown_goal", 5))
		opts.add_child(_opt_cell("목표 점수", "%d점" % cg, editable, func():
			settings["crown_goal"] = {3: 5, 5: 7, 7: 3}.get(cg, 5)
			_room_settings_changed()))
	opts.add_child(_opt_cell("빈 자리", "CPU로 채우기" if bool(_room_cfg("fill", false)) else "비워 두기", editable, func():
		settings["fill"] = not settings.get("fill", false)
		_room_settings_changed()))
	opts.add_child(_opt_cell("공방 스킨", "켜기" if bool(_room_cfg("skins", false)) else "끄기", editable, func():
		settings["skins"] = not settings.get("skins", false)
		_room_settings_changed()))
	rv.add_child(opts)
	if cur_mode == "parcel" and not editable:
		rv.add_child(_label("팀 나누기는 방장이 정해요", 12, SUB))


func _opt_cell(title: String, value: String, editable: bool, cb: Callable) -> Control:
	var b := _button("", func():
		if editable:
			cb.call())
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _sb(Color(FG, 0.05), Color(FG, 0.14), 10))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_label(title, 11, SUB))
	var vl := _nw(_label(value, 15, TEXT, 2))
	vl.clip_text = true
	v.add_child(vl)
	b.add_child(v)
	return b


func _set_room_size(nn: int) -> void:
	var old: int = settings["n"]
	settings["n"] = nn
	for i in range(old, nn):
		settings["empty"][i] = true
		settings["cpu"][i] = false
		settings["friend"][i] = false
	for seat in friend_peer.keys():
		if seat >= nn:
			net.send_to(friend_peer[seat], {"t": "full"})
			friend_peer.erase(seat)
	_room_settings_changed()


## 코드 보여주기: 큰 글씨 전체 화면 (옆 사람에게 보여주기용)
func _show_code_big() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(SOLID, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var l := Label.new()
	l.text = net.code().to_upper()
	l.add_theme_font_override("font", font_display)
	l.add_theme_font_size_override("font_size", int(minf(get_viewport_rect().size.x * 0.16, 220.0)))
	l.add_theme_color_override("font_color", TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(l)
	var hint := _label("눌러서 닫기", 16, SUB)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y -= 60
	root.add_child(hint)
	bg.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			root.queue_free())
	overlay.add_child(root)


func _start_from_room() -> void:
	_compose_plan()
	_start_match()


## 대기실 → 경기: 빈 자리는 빼고(또는 CPU로 채우고) 앞에서부터 경기 자리를 매긴다.
func _compose_plan() -> void:
	_refresh_seat_profiles()
	match_seats.clear()
	var cpu: Array = []
	var friend: Array = []
	var profs: Array = []
	var teams: Array = []
	cpu_levels.clear()
	for i in settings["n"]:
		var k := _seat_kind(i)
		if k == "empty" and not settings.get("fill", false):
			continue
		if k == "wait":
			k = "cpu"
		match_seats.append(i)
		var pf: Dictionary = (settings["prof"][i] as Dictionary).duplicate() if settings["prof"][i] is Dictionary else {}
		if k == "empty":
			k = "cpu"
			pf = {"nick": "CPU", "form": "metal", "color": -1, "symbol": i % 8, "kind": "cpu", "level": 1}
		cpu.append(k == "cpu")
		friend.append(k == "friend")
		profs.append(pf)
		teams.append(int(settings["teams"][i]))
		cpu_levels.append(int(pf.get("level", 1)))
	# 채운 CPU 색 정리 (겹치지 않게)
	var used := {}
	for pf2 in profs:
		var c := int(pf2.get("color", -1))
		if c < 0 or used.has(c):
			c = _nearest_free_color(c, used)
		pf2["color"] = c
		used[c] = true
	var nplay := match_seats.size()
	room_peer = friend_peer.duplicate()
	var fp := {}
	for pid in nplay:
		if room_peer.has(match_seats[pid]):
			fp[pid] = room_peer[match_seats[pid]]
	friend_peer = fp
	plan = {"n": nplay, "cpu": cpu, "friend": friend, "profiles": profs, "teams": teams, "levels": cpu_levels.duplicate()}
	var aim: String = str(settings.get("aim", "auto"))
	plan["aim"] = 0.0 if aim == "none" else (8.0 if aim == "8" else (12.0 if aim == "12" else (12.0 if nplay >= 5 else 0.0)))


var plan := {}   # 이번 판 자리 구성 (대기실이 만들고, 손님은 방장이 보낸 것을 쓴다)
