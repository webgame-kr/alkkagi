extends Node2D
## 화면 연출과 입력. 판정은 match.gd, 물리는 world.gd, 부품은 parts.gd 가 맡는다.
## 디자인: 펠트 테이블 위에서 튕기는 가공 금속 퍽 (디자인 시안 「개조 알까기 디자인 시안」).

const Match = preload("res://scripts/sim/match.gd")
const World = preload("res://scripts/sim/world.gd")
const Parts = preload("res://scripts/sim/parts.gd")
const PartsData = preload("res://scripts/sim/parts_data.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const Art = preload("res://scripts/stone_art.gd")

# 팔레트 (디자인 시안의 「테이블과 재질」)
const BG_OUT := Color("121417")          # 판 밖
const FELT := Color("1F4A44")
const FELT_LIGHT := Color("2A5E56")
const FELT_DARK := Color("1A3F3A")
const PAGE_FELT := Color("23463E")       # 설정·도감 화면 바탕
const RAIL := Color("5A3A24")            # 월넛 레일
const RAIL_OUT := Color("2E1D12")
const RAIL_IN := Color("7A5233")
const WARN := Color("D9A441")            # 경고 띠
const BRASS := Color("C9A15A")
const INK := Color("0E1013")
const TEXT := Color("F2F4F1")
const SUB := Color("A9B1BA")
const SUB_FELT := Color("B9CCC4")
const POWER := Color("E9BE62")
const PANEL_BG := Color(1, 1, 1, 0.04)
const PANEL_LINE := Color(1, 1, 1, 0.09)
const MUTED := Color("5C6370")
const HINT_GOLD := Color("E3C27E")
const LABEL := Color("C9CED6")

const MAX_DRAG := 150.0      # 화면 px: 이만큼 당기면 최대 힘
const CANCEL_R := 2.0        # 퍽 반지름의 몇 배 안으로 돌아오면 조준 취소 (점선 원)
const CELL := World.STONE_R * 2.0

var font: Font
var font_semi: Font
var font_bold: Font
var m: Match
var settings := {"n": 4, "cpu": [false, true, true, true, true, true, true, true], "timed": false}
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
var draft_part := ""
var draft_stone := -1

# UI
var ui: CanvasLayer
var theme_: Theme
var overlay: Control = null
var menu_btn: Button
var parts_btn: Button
var _panel_sb: StyleBoxFlat


func _ready() -> void:
	font = load("res://fonts/IBMPlexSansKR-Regular.ttf")
	font_semi = load("res://fonts/IBMPlexSansKR-SemiBold.ttf")
	font_bold = load("res://fonts/IBMPlexSansKR-Bold.ttf")
	theme_ = _make_theme()
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = PANEL_BG
	_panel_sb.border_color = PANEL_LINE
	_panel_sb.set_border_width_all(1)
	_panel_sb.set_corner_radius_all(12)
	ui = CanvasLayer.new()
	add_child(ui)
	menu_btn = _button("≡", func(): _show_setup())
	menu_btn.tooltip_text = "처음으로"
	menu_btn.theme = theme_
	menu_btn.add_theme_font_size_override("font_size", 14)
	menu_btn.visible = false
	ui.add_child(menu_btn)
	parts_btn = _button("부품 도감", func(): _show_catalog(false))
	parts_btn.theme = theme_
	parts_btn.add_theme_font_size_override("font_size", 14)
	parts_btn.visible = false
	ui.add_child(parts_btn)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_setup()
	_debug_args()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 17
	var normal := _sb(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.14), 8)
	var hover := _sb(Color(1, 1, 1, 0.11), Color(1, 1, 1, 0.24), 8)
	var pressed := _sb(Color(BRASS, 0.22), BRASS, 8)
	for cls in ["Button", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
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
	if args.has("--catalog"):
		_show_catalog(false)
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
	var want := Vector2i(480, 480) if win.size.y > win.size.x * 1.1 else Vector2i(1280, 800)
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
		parts_btn.custom_minimum_size = Vector2(0, 44)


func w2s(p: Vector2) -> Vector2:
	return view_center + p * view_scale


func s2w(p: Vector2) -> Vector2:
	return (p - view_center) / view_scale


# ── 경기 시작 ────────────────────────────────────────────

func _start_match() -> void:
	m = Match.new()
	m.setup(settings["n"], settings["cpu"], randi(), settings["timed"])
	state = "play"
	fx.clear()
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
	_layout()
	var sp: Dictionary = m.players[m.current_player()]
	_log("%d인전 시작, 선공은 %s" % [m.n, sp.name], sp.color)


func _process(delta: float) -> void:
	time += delta
	_place()
	banner_t = maxf(0.0, banner_t - delta)
	for f in fx:
		f["t"] += delta
	fx = fx.filter(func(f): return f["t"] < f["life"])
	if state == "play" and m != null:
		_update_play(delta)
	queue_redraw()


func _update_play(delta: float) -> void:
	var key := "%s|%d|%d|%d" % [m.phase, m.round_no, m.turn_pos, m.draft_queue.size()]
	if key != turn_key:
		turn_key = key
		_on_phase_changed()
	match m.phase:
		"moving":
			var spd := 1.0
			if slowmo > 0.0:
				slowmo -= delta
				spd = 0.3
			accum += minf(delta, 0.05) * spd
			while accum >= World.DT and m.phase == "moving":
				accum -= World.DT
				m.world.step()
				_consume_events()
				if m.world.is_settled():
					_after_shot()
					break
		"draft":
			var pid := m.current_drafter()
			if m.players[pid].cpu:
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
				_update_cpu(delta, pid)
			elif m.aim_limit > 0.0:
				aim_left -= delta
				if aim_left <= 0.0:
					drag_stone = -1
					_log("%s 시간 초과, 차례를 넘겨요" % m.players[pid].name, m.players[pid].color)
					_banner("시간 초과")
					m.skip_turn()
		"over":
			if state == "play":
				_show_result()


func _update_cpu(delta: float, pid: int) -> void:
	if not cpu_aim.is_empty():
		cpu_aim["t"] -= delta
		if cpu_aim["t"] <= 0.0:
			var c: Dictionary = cpu_aim
			cpu_aim = {}
			m.shoot(c["stone"], c["dir"], c["power"], {"charged": true})
		return
	if bot == null:
		bot_wait -= delta
		if bot_wait > 0.0:
			return
		for t in m.relic_targets(pid):
			var part: String = m.players[pid].relic
			if m.equip_relic(pid, t.id):
				_log("%s 유품 %s 달았어요" % [_j(m.players[pid].name, "이", "가"), _j(PartsData.part_name(part), "을", "를")], m.players[pid].color)
			break
		bot = Bot.new()
		bot.begin(m, pid, randi())
		return
	# 프레임당 약 6ms 만큼만 생각한다 (화면이 멈추지 않게).
	var t0 := Time.get_ticks_usec()
	var finished := false
	while not finished and Time.get_ticks_usec() - t0 < 6000:
		finished = bot.think_step(1)
	bot_us += Time.get_ticks_usec() - t0
	if finished:
		var r: Dictionary = bot.result()
		bot_us = 0
		bot = null
		if r.is_empty():
			m.skip_turn()
		else:
			cpu_aim = r.duplicate()
			cpu_aim["t"] = 0.65


func _on_phase_changed() -> void:
	match m.phase:
		"aim":
			aim_left = m.aim_limit
			bot = null
			bot_wait = 0.45
			var p: Dictionary = m.players[m.current_player()]
			_banner("%s 차례" % p.name, p.color)
			relic_mode = false
			if not p.cpu and not m.relic_targets(p.id).is_empty():
				_show_relic_hint(p.id)
		"draft":
			var pid := m.current_drafter()
			draft_part = ""
			draft_stone = -1
			draft_wait = 0.7
			if m.draft_queue.size() == m.order.size():
				_banner("%d바퀴 · 개조 시간" % m.round_no)
			if m.players[pid].cpu:
				_clear_overlay()
			else:
				_show_draft_cards(pid)


func _after_shot() -> void:
	var shooter_owner: int = m.world.shot.owner if m.world.shot != null else -1
	var outs: Array = m.world.knockouts.duplicate()
	m.finish_shot()
	_consume_events()
	if shooter_owner < 0:
		return
	var who: String = m.players[shooter_owner].name
	var by_owner := {}
	for k in outs:
		by_owner[k["owner"]] = by_owner.get(k["owner"], 0) + 1
	for o in by_owner:
		var col: Color = m.players[shooter_owner].color
		if o == shooter_owner:
			_log("%s 퍽 %d개가 스스로 떨어졌어요" % [who, by_owner[o]], col)
		else:
			_log("%s %s 퍽 %d개를 떨어뜨렸어요" % [_j(who, "이", "가"), m.players[o].name, by_owner[o]], col)
	for pid in m.out_order:
		if not _logged_out.has(pid):
			_logged_out[pid] = true
			_log("%s 탈락했어요" % _j(m.players[pid].name, "이", "가"), m.players[pid].color)


var _logged_out := {}
var _shot_dir := ""
var _shot_n := 0


func _log(s: String, col := SUB) -> void:
	log_lines.append({"t": s, "c": col})
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


func _banner(s: String, c := TEXT) -> void:
	banner = s
	banner_t = 1.3
	_banner_col = c


var _banner_col := TEXT


# ── 연출용 사건 ──────────────────────────────────────────

func _consume_events() -> void:
	for e in m.world.events:
		var owner_col: Color = m.players[e["owner"]].color if e.has("owner") and e["owner"] >= 0 and e["owner"] < m.players.size() else TEXT
		match e["t"]:
			"hit":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.25, "r": 8.0 + minf(e["strength"], 1200.0) / 60.0, "c": Color(1, 1, 1, 0.8)})
			"bullet_hit":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.3, "r": 16.0, "c": owner_col.lightened(0.4)})
			"out":
				fx.append({"k": "text", "pos": e["pos"], "t": 0.0, "life": 1.4, "text": "탈락!", "c": owner_col, "size": 30})
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.6, "r": 46.0, "c": owner_col})
			"part":
				var big: bool = e.get("big", false)
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -30), "t": 0.0, "life": 1.6 if big else 1.1, "text": e.get("text", ""), "c": POWER if big else owner_col.lightened(0.35), "size": 28 if big else 20})
				if big:
					fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.7, "r": 70.0, "c": POWER})
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.4, "r": 30.0, "c": owner_col.lightened(0.3)})
				if e.has("from"):
					fx.append({"k": "line", "a": e["from"], "b": e["pos"], "t": 0.0, "life": 0.45, "c": owner_col.lightened(0.5)})
			"reflect":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.5, "r": 36.0, "c": Color(0.75, 0.95, 1.0)})
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -28), "t": 0.0, "life": 1.0, "text": "반사!", "c": Color(0.75, 0.95, 1.0), "size": 20})
			"boom":
				fx.append({"k": "boom", "pos": e["pos"], "t": 0.0, "life": 0.55, "r": e["radius"], "c": Color(1.0, 0.6, 0.15)})
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -30), "t": 0.0, "life": 1.0, "text": "쾅!", "c": Color(1.0, 0.75, 0.3), "size": 28})
			"device":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.4, "r": 22.0, "c": owner_col})
			"umbrella":
				fx.append({"k": "fan", "pos": e["pos"], "dir": e["dir"], "t": 0.0, "life": 0.5, "r": e["radius"], "c": Color("E1E6EB")})
			"manga":
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
				fx.append({"k": "beam", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.5, "c": Color("7FD8FF")})
			"hexbreak":
				fx.append({"k": "hex", "pos": e["pos"], "t": 0.0, "life": 0.5, "c": Color("F28A2E")})
			"magic_circle":
				fx.append({"k": "circle", "pos": e["pos"], "t": 0.0, "life": 0.7, "c": Color("B7C8FF")})
			"thread", "line_fx":
				fx.append({"k": "line", "a": e["a"], "b": e["b"], "t": 0.0, "life": 0.6, "c": Color("E9DCC4") if e["t"] == "thread" else Color("9A86D8")})
			"splat":
				fx.append({"k": "ring", "pos": e["pos"], "t": 0.0, "life": 0.4, "r": 24.0, "c": Color("2A2F45")})
			"ripple":
				for k in 3:
					fx.append({"k": "ring", "pos": e["pos"], "t": -0.08 * k, "life": 0.5, "r": e["radius"] * 0.8, "c": Color(BRASS, 0.9)})
	m.world.events.clear()


# ── 입력 ─────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if state != "play" or m == null:
		return
	if event is InputEventMouseMotion:
		var wp := s2w(event.position)
		hover_stone = _stone_at(wp, -1)
		if drag_stone >= 0:
			drag_screen = event.position
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var wp2 := s2w(event.position)
	if event.pressed:
		hover_stone = _stone_at(wp2, -1)
	if m.phase == "draft" and draft_part != "" and draft_stone < 0:
		if event.pressed:
			var pid := m.current_drafter()
			var sid := _stone_at(wp2, pid)
			if sid >= 0:
				_pick_stone_for_part(pid, sid)
		return
	if m.phase != "aim" or m.players[m.current_player()].cpu:
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
	elif drag_stone >= 0:
		var aim := _aim_of(drag_stone, event.position)
		var sid3 := drag_stone
		drag_stone = -1
		if not aim.is_empty():
			m.shoot(sid3, aim["dir"], aim["power"], {"charged": _charged(sid3), "from_cloud": drag_cloud})
		drag_cloud = false


func _stone_at(wp: Vector2, owner: int) -> int:
	var best := -1
	var best_d := World.STONE_R * 1.6
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
	if dist < World.STONE_R * CANCEL_R * view_scale:
		return {}
	return {"dir": pull.normalized(), "power": clampf(dist / MAX_DRAG, 0.05, 1.0)}


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
		var line := "%d바퀴 시작, %s %s 달았어요" % [m.round_no, _j(pl.name, "이", "가"), _j(nm, "을", "를")]
		if old != "":
			line += " (%s 교체)" % PartsData.part_name(old)
		_log(line, pl.color)
		var set_txt := PartsData.set_label(s.parts)
		if set_txt != "":
			_log(set_txt, BRASS)
		fx.append({"k": "text", "pos": s.pos + Vector2(0, -34), "t": 0.0, "life": 1.3, "text": txt, "c": pl.color.lightened(0.35), "size": 20})
		if PartsData.set_complete(s.parts):
			fx.append({"k": "text", "pos": s.pos + Vector2(0, -58), "t": 0.0, "life": 1.8, "text": "메카 티라노!", "c": POWER, "size": 24})
			fx.append({"k": "ring", "pos": s.pos, "t": 0.0, "life": 0.8, "r": 60.0, "c": POWER})
		fx.append({"k": "ring", "pos": s.pos, "t": 0.0, "life": 0.5, "r": 34.0, "c": pl.color})
	draft_part = ""
	draft_stone = -1
	_clear_overlay()


# ── 그리기 ───────────────────────────────────────────────

func _draw() -> void:
	var vs := get_viewport_rect().size
	if m == null:
		draw_rect(Rect2(Vector2.ZERO, vs), BG_OUT)
		if state == "setup" and not portrait:
			_draw_lobby_preview(vs)
		return
	draw_rect(Rect2(Vector2.ZERO, vs), BG_OUT)
	_draw_board()
	_draw_devices()
	_draw_aim_under()
	for s in m.world.stones:
		if s.alive:
			_draw_stone(s)
	_draw_projs()
	_draw_fx()
	_draw_aim_over()
	_draw_draft_marks()
	_draw_hud(vs)
	if banner_t > 0.0:
		var a := clampf(banner_t / 0.4, 0.0, 1.0)
		var y := view_center.y - 40.0 if not portrait else 160.0
		_text_outline(Vector2(view_center.x, y), banner, 30, Color(_banner_col, a), true)


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
func _draw_lobby_preview(vs: Vector2) -> void:
	var n: int = settings["n"]
	var top := maxf(40.0, (vs.y - 680.0) * 0.5 + 40.0)
	var c := Vector2(vs.x - 120.0 - 230.0, top + 230.0)
	var half := 218.0
	var square := n == 2
	var units := 16.0 if square else (18.0 if n <= 4 else 24.0)
	var u := 2.0 * half / units
	var r := u * 0.5
	if square:
		_round_rect(Rect2(c - Vector2(half + 11, half + 5), Vector2(2 * half + 22, 2 * half + 22)), Color(0, 0, 0, 0.5), 8)
		_round_rect(Rect2(c - Vector2(half + 11, half + 11), Vector2(2 * half + 22, 2 * half + 22)), RAIL, 8, RAIL_OUT)
		draw_rect(Rect2(c - Vector2(half, half), Vector2(2 * half, 2 * half)), FELT)
		draw_rect(Rect2(c - Vector2(half, half), Vector2(2 * half, 2 * half)), INK, false, 2.0)
		draw_rect(Rect2(c - Vector2(half - u, half - u), Vector2(2 * (half - u), 2 * (half - u))), Color(WARN, 0.45), false, 1.5)
	else:
		draw_circle(c + Vector2(0, 6), half + 14, Color(0, 0, 0, 0.5))
		draw_circle(c, half + 11, RAIL)
		draw_arc(c, half + 11, 0, TAU, 96, RAIL_OUT, 2.0, true)
		var light := c + Vector2(-0.1, -0.2) * half
		for i in 24:
			var t := float(i) / 24.0
			draw_circle(c.lerp(light, t), half * (1.0 - t * 0.92), FELT_DARK.lerp(FELT_LIGHT, t * 0.95))
		draw_arc(c, half, 0, TAU, 96, INK, 2.0, true)
		draw_arc(c, half - u, 0, TAU, 96, Color(WARN, 0.45), 1.5, true)
	var pucks: Array = []
	if square:
		for i in 2:
			var y := c.y + (1.0 if i == 0 else -1.0) * (half - 4.0 * u)
			for j in 3:
				pucks.append([i, Vector2(c.x + (j - 1) * 2.5 * u, y)])
	else:
		var R := half / u
		for i in n:
			var a := deg_to_rad(90.0 + 360.0 * i / n)
			for rr in [R - 4.0, R - 5.5]:
				pucks.append([i, c + Vector2(cos(a), sin(a)) * rr * u])
	for pk in pucks:
		var i: int = pk[0]
		if not settings["cpu"][i]:
			draw_arc(pk[1], r + 4, 0, TAU, 24, BG_OUT, 3.0, true)
			draw_arc(pk[1], r + 5.5, 0, TAU, 24, BRASS, 2.0, true)
		Art.draw_icon(self, pk[1], 2 * r, Match.COLORS[i], i)
	# 판 정보
	var info := [["판", "정사각 16칸" if square else "원형 지름 %d칸" % int(units)], ["퍽", "%d개씩" % (3 if square else 2)],
		["최대", "%d바퀴" % (12 if square else (8 if n <= 4 else 6))], ["개조", "1, 2, 3바퀴" if n >= 5 else "2, 3, 4바퀴"]]
	var x0 := c.x - 230.0
	var y0 := c.y + 230.0 + 40.0
	for k in 4:
		var x := x0 + k * 118.0
		_txt(Vector2(x, y0), info[k][0], 13, SUB, font)
		_txt(Vector2(x, y0 + 24), info[k][1], 15, TEXT, font_semi, 110)
	_txt(Vector2(x0, y0 + 64), "밝은 테두리가 사람 자리예요. 인원을 바꾸면 판 크기와 시작 배치가 함께 바뀝니다.", 13, SUB, font, 460)


func _draw_board() -> void:
	var w := m.world
	var k := view_scale
	var c := view_center
	var R := w.size * k
	var rail := R * 16.0 / 300.0
	if w.shape == "circle":
		draw_circle(c + Vector2(0, 8), R + rail + 6, Color(0, 0, 0, 0.5))
		draw_circle(c, R + rail, RAIL)
		draw_arc(c, R + rail, 0, TAU, 128, RAIL_OUT, 2.0, true)
		draw_arc(c, R + rail * 0.69, 0, TAU, 128, RAIL_IN, 2.0, true)
		# 펠트: 왼쪽 위가 밝은 방사형 그라데이션
		var light := c + Vector2(-0.1, -0.2) * R
		var steps := 28
		for i in steps:
			var t := float(i) / steps
			draw_circle(c.lerp(light, t), R * (1.0 - t * 0.92), FELT_DARK.lerp(FELT_LIGHT, t * 0.95))
		_draw_grid_circle(c, R, CELL * k)
		draw_arc(c, R, 0, TAU, 128, INK, 2.0, true)
		# 경고 띠: 판 끝 1칸
		var band := World.EDGE_ZONE * k
		draw_arc(c, R - band * 0.5, 0, TAU, 128, Color(WARN, 0.13), band, true)
		draw_arc(c, R - band, 0, TAU, 128, Color(WARN, 0.45), 1.5, true)
		_dotted_circle(c, R - 1.6 * CELL * k, Color(WARN, 0.6))
	else:
		var tl := c - Vector2(R, R)
		_round_rect(Rect2(tl - Vector2(rail + 3, rail - 5), Vector2(2 * (R + rail) + 6, 2 * (R + rail) + 6)), Color(0, 0, 0, 0.5), 8)
		_round_rect(Rect2(tl - Vector2(rail, rail), Vector2(2 * (R + rail), 2 * (R + rail))), RAIL, 6, RAIL_OUT)
		draw_rect(Rect2(tl, Vector2(2 * R, 2 * R)), FELT_DARK)
		var light := c + Vector2(-0.1, -0.2) * R
		var steps := 28
		for i in steps:
			var t := float(i) / steps
			draw_circle(c.lerp(light, t), R * (1.0 - t * 0.92) * 0.98, FELT_DARK.lerp(FELT_LIGHT, t * 0.95))
		var g := CELL * k
		var x := -R + g
		while x < R - 0.5:
			draw_line(c + Vector2(x, -R), c + Vector2(x, R), Color(1, 1, 1, 0.06), 1.0)
			draw_line(c + Vector2(-R, x), c + Vector2(R, x), Color(1, 1, 1, 0.06), 1.0)
			x += g
		draw_rect(Rect2(tl, Vector2(2 * R, 2 * R)), INK, false, 2.0)
		var band := World.EDGE_ZONE * k
		draw_rect(Rect2(tl + Vector2(band, band) * 0.5, Vector2(2 * R - band, 2 * R - band)), Color(WARN, 0.13), false, band)
		draw_rect(Rect2(tl + Vector2(band, band), Vector2(2 * R - 2 * band, 2 * R - 2 * band)), Color(WARN, 0.45), false, 1.5)
	draw_arc(c, 5, 0, TAU, 20, Color(1, 1, 1, 0.18), 1.5, true)


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
	# 지금 차례인 퍽 표시
	if m.phase == "aim" and s.owner == m.current_player() and drag_stone < 0:
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		draw_arc(p, (World.STONE_R + 6 + pulse * 3) * view_scale, 0, TAU, 40, Color(col.lightened(0.35), 0.55 + 0.3 * pulse), 2.0, true)
		if m.aim_limit > 0.0 and not m.players[s.owner].cpu:
			var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
			draw_arc(p, (World.STONE_R + 13) * view_scale, -PI / 2, -PI / 2 + TAU * frac, 40, Color(POWER, 0.85), 3.0, true)
	# 충전 (모으고 쏘는 손바닥)
	if drag_stone == s.id and s.parts["weapon"] == "charge_palm":
		var cf := clampf(drag_hold / PartsData.num("charge_palm", "charge"), 0.0, 1.0)
		draw_arc(p, (World.STONE_R + 10) * view_scale, -PI / 2, -PI / 2 + TAU * cf, 32, Color("7FD8FF") if cf < 1.0 else Color.WHITE, 3.0, true)
		if cf >= 1.0:
			draw_circle(p, (World.STONE_R + 14) * view_scale, Color("7FD8FF", 0.15 + 0.1 * sin(time * 12.0)))
	if manga != null:
		Art.mono = true
	draw_set_transform(p, facing, Vector2.ONE * view_scale)
	Art.draw(self, s.parts, s.magnet_side, col, 1.0, s.owner)
	draw_set_transform_matrix(Transform2D.IDENTITY)
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
			"ring":
				draw_arc(w2s(f["pos"]), f["r"] * view_scale * (0.6 + u * 0.8), 0, TAU, 32, Color(c, 1.0 - u), 3.0, true)
			"boom":
				draw_circle(w2s(f["pos"]), f["r"] * view_scale * (0.3 + u * 0.7), Color(c, 0.3 * (1.0 - u)))
				draw_arc(w2s(f["pos"]), f["r"] * view_scale * (0.3 + u * 0.7), 0, TAU, 40, Color(c, 1.0 - u), 4.0, true)
			"line":
				draw_line(w2s(f["a"]), w2s(f["b"]), Color(c, 0.9 * (1.0 - u)), 3.0, true)
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
				_text_outline(p, f["text"], f["size"], Color(c, clampf(2.0 - 2.0 * u, 0.0, 1.0)), true)


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
		_dashed_ring(sp, World.STONE_R * CANCEL_R * view_scale, Color(1, 1, 1, 0.3))
		var d: Vector2 = (sp - f).normalized()
		var side := d.orthogonal() * World.STONE_R * 0.8 * view_scale
		draw_line(sp + side, f, BRASS, 2.5, true)
		draw_line(sp - side, f, BRASS, 2.5, true)
		draw_circle(f, 16, Color(1, 1, 1, 0.12))
		draw_arc(f, 16, 0, TAU, 24, Color(1, 1, 1, 0.7), 1.5, true)
	for item in info["preview"]:
		if item["k"] == "move":
			var a := w2s(item["a"])
			var b := w2s(item["b"])
			var dd := (b - a).normalized()
			a += dd * (World.STONE_R + 4) * view_scale
			draw_line(a, b, INK, 7.0, true)
			draw_line(a, b, TEXT, 3.5, true)
			var head := PackedVector2Array([b + dd * 14, b + dd.orthogonal() * 8 - dd * 2, b - dd.orthogonal() * 8 - dd * 2])
			draw_colored_polygon(head, TEXT)
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
	if m.phase != "draft" or draft_part == "":
		return
	var pid := m.current_drafter()
	var slot := PartsData.slot_of(draft_part)
	for s in m.world.alive_stones_of(pid):
		var p := w2s(s.pos)
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		draw_arc(p, (World.STONE_R + 8 + pulse * 4) * view_scale, 0, TAU, 40, Color(BRASS, 0.95), 3.0, true)
		var cur: String = s.parts[slot]
		var t := "%s: %s" % [PartsData.SLOT_LABEL[slot], "비어 있음" if cur == "" else PartsData.part_name(cur) + " → 교체"]
		_small_label(p + Vector2(0, (World.STONE_R + 26) * view_scale + 8), t, TEXT)
		if draft_stone == s.id:
			draw_arc(p, (World.STONE_R + 16) * view_scale, 0, TAU, 40, POWER, 3.0, true)


# ── HUD: 떠 있는 패널 ────────────────────────────────────

func _panel(r: Rect2) -> void:
	_panel_sb.draw(get_canvas_item(), r)


func _txt(pos: Vector2, t: String, size: int, col: Color, f: Font = null, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var ff: Font = f if f != null else font
	if width > 0.0 and align == HORIZONTAL_ALIGNMENT_LEFT:
		t = _fit(t, ff, size, width)
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width > 0.0:
		pos.x -= width  # 오른쪽 정렬은 pos.x 를 오른쪽 끝으로 본다
	draw_string(ff, pos, t, align, width, size, col)


func _fit(t: String, f: Font, size: int, maxw: float) -> String:
	if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= maxw:
		return t
	var s := t
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw:
		s = s.substr(0, s.length() - 1)
	return s + "…"


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
	var pid := m.current_player() if m.phase != "draft" else m.current_drafter()
	if pid >= 0:
		var mine: Array = m.world.alive_stones_of(pid)
		if not mine.is_empty():
			return mine[0]
	return null


func _draw_hud(vs: Vector2) -> void:
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
			else:
				sub = "퍽 하나를 당겨 조준하세요" if m.phase == "aim" else "퍽이 멈추길 기다려요"
		"draft":
			pid = m.current_drafter()
			title = "%s 개조" % m.players[pid].name
			sub = "후보 세 개 중 하나를 골라요"
		_:
			title = "경기 끝"
	_panel(r)
	var x := r.position.x + 18
	if pid >= 0:
		Art.draw_icon(self, r.position + Vector2(18 + 24, 18 + 24), 48, m.players[pid].color, pid)
		x += 62
	_txt(Vector2(x, r.position.y + 42), title, 24, TEXT, font_bold, r.end.x - x - 12)
	_txt(Vector2(x, r.position.y + 64), sub, 14, SUB, font, r.end.x - x - 12)
	# 바퀴 진행
	var y := r.position.y + 96
	_txt(Vector2(r.position.x + 18, y), "%d바퀴째" % m.round_no, 13, LABEL, font_semi)
	_txt(Vector2(r.end.x - 18, y), "%d바퀴까지" % m.max_rounds, 13, SUB, font, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	var seg_r := Rect2(r.position.x + 18, y + 8, r.size.x - 36, 5)
	var n := m.max_rounds
	var gap := 3.0
	var w := (seg_r.size.x - gap * (n - 1)) / n
	for i in n:
		draw_rect(Rect2(seg_r.position.x + i * (w + gap), seg_r.position.y, w, 5), BRASS if i < m.round_no else Color(1, 1, 1, 0.14))
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
			_round_rect(row, Color(1, 1, 1, 0.07), 8)
		var cy := y + row_h * 0.5 - 1
		Art.draw_icon(self, Vector2(row.position.x + 8 + 12, cy), minf(24.0, row_h - 6), p.color, pid, a)
		var nx := row.position.x + 44
		_txt(Vector2(nx, cy + fs * 0.36), p.name, fs, Color(TEXT, a), font_bold if pid == cur else font, 70)
		var name_w := (font_bold if pid == cur else font).get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_txt(Vector2(nx + name_w + 8, cy + 4), "CPU" if p.cpu else "사람", 12, Color(SUB, a), font, 40)
		var right := row.end.x - 8
		if p.out:
			_txt(Vector2(right, cy + 4), "탈락", 12, Color(SUB, 0.8), font, 50, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			var left := m.stones_left(pid)
			for k2 in left:
				draw_circle(Vector2(right - 4 - k2 * 12, cy), 4.0, p.color)
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
		draw_circle(Vector2(r.position.x + 22, y - 5), 4, e["c"])
		for ln in lines[k]:
			_txt(Vector2(r.position.x + 36, y), ln, 14, TEXT if k == 0 else SUB, font)
			y += lh


## 폭에 맞춰 줄바꿈 (글자 단위).
func _wrap(t: String, f: Font, size: int, maxw: float) -> Array:
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
		draw_rect(rr, WARN if i < lit else Color(1, 1, 1, 0.12))


func _draw_power(r: Rect2) -> void:
	if m.phase != "aim":
		return
	var info := _current_aim()
	var pw: float = info.get("power", 0.0) if not info.is_empty() else 0.0
	_panel(r)
	_txt(r.position + Vector2(18, 30), "힘", 13, SUB, font_semi)
	var label := "%d%%" % int(round(pw * 100)) if not info.is_empty() and not info.has("cancel") else ("취소" if info.has("cancel") else "—")
	_txt(Vector2(r.end.x - 18, r.position.y + 36), label, 22, POWER, font_bold, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	_segments(Rect2(r.position.x + 18, r.position.y + 48, r.size.x - 36, 12), pw)
	_txt(Vector2(r.position.x + 18, r.position.y + 88), "점선 원 안으로 되돌리면 조준을 취소해요.", 13, SUB, font, r.size.x - 36)


## 조준 중인 퍽 (또는 손을 올린 퍽)의 부품.
func _draw_aimed(r: Rect2) -> void:
	var s = _focus_stone()
	var empty: bool = s == null or (s.parts["weapon"] == "" and s.parts["aux"] == "" and s.parts["prop"] == "")
	var set_txt: String = PartsData.set_label(s.parts) if s != null else ""
	var first_hint := ""
	if empty and m.round_no < (m.draft_rounds[0] if not m.draft_rounds.is_empty() else 99):
		first_hint = "첫 개조는 %d바퀴가 시작될 때 해요." % m.draft_rounds[0]
	var step := 34.0
	if not portrait:
		r.size.y = 14 + 26 + 3 * step + 8 + (30.0 if set_txt != "" else 0.0) + (50.0 if first_hint != "" else 0.0)
		hud["aimed_end"] = r.end.y
	_panel(r)
	_txt(r.position + Vector2(18, 27), "조준 중인 퍽" if drag_stone >= 0 or (m.phase == "aim" and not m.players[m.current_player()].cpu and hover_stone < 0) else "이 퍽의 부품", 13, SUB, font_semi)
	if s == null:
		return
	Art.draw_icon(self, Vector2(r.end.x - 28, r.position.y + 22), 22, m.players[s.owner].color, s.owner)
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
		_txt(Vector2(r.position.x + 18, y + 6), set_txt, 13, POWER, font_semi, r.size.x - 36)
		y += 30
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
	return root


func _centered_panel(root: Control, min_w: float, bg := Color(14 / 255.0, 16 / 255.0, 19 / 255.0, 0.9)) -> VBoxContainer:
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
	state = "setup"
	m = null
	menu_btn.visible = false
	parts_btn.visible = false
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var narrow := vs.x < 900
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26 if not narrow else 18)
	var width := 540.0 if not narrow else vs.x - 32.0
	col.custom_minimum_size = Vector2(width, 0)
	col.position = Vector2(72, maxf(40.0, (vs.y - 680.0) * 0.5 + 56.0)) if not narrow else Vector2(16, 24)
	root.add_child(col)
	# 제목
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_label("개조 알까기", 44, TEXT, 2))
	head.add_child(_label("퍽을 튕겨 상대를 판 밖으로. 바퀴마다 부품을 골라 개조합니다.", 16, SUB))
	col.add_child(head)
	# 인원: 분절 버튼
	var g1 := VBoxContainer.new()
	g1.add_theme_constant_override("separation", 10)
	g1.add_child(_label("인원", 14, LABEL, 1))
	var seg := PanelContainer.new()
	var segsb := _sb(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), 10)
	segsb.set_content_margin_all(4)
	seg.add_theme_stylebox_override("panel", segsb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	seg.add_child(row)
	for n in range(2, 9):
		var b := _button("%d인" % n, func(): _set_count(n))
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", font_semi)
		b.add_theme_font_size_override("font_size", 16)
		var on: bool = settings["n"] == n
		var st := _sb(BRASS if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 7)
		st.set_border_width_all(0)
		b.add_theme_stylebox_override("normal", st)
		var sth := _sb(BRASS.lightened(0.1) if on else Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 7)
		sth.set_border_width_all(0)
		b.add_theme_stylebox_override("hover", sth)
		b.add_theme_stylebox_override("pressed", sth)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, INK if on else TEXT)
		row.add_child(b)
	g1.add_child(seg)
	col.add_child(g1)
	# 자리
	var g2 := VBoxContainer.new()
	g2.add_theme_constant_override("separation", 10)
	var hr := HBoxContainer.new()
	var sl := _nw(_label("자리", 14, LABEL, 1))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(sl)
	var humans := 0
	for i in settings["n"]:
		if not settings["cpu"][i]:
			humans += 1
	hr.add_child(_nw(_label("사람 %d명, CPU %d명" % [humans, settings["n"] - humans], 13, SUB)))
	g2.add_child(hr)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in settings["n"]:
		grid.add_child(_seat_button(i))
	g2.add_child(grid)
	g2.add_child(_label("자리를 누르면 사람과 CPU가 바뀝니다.", 13, SUB))
	col.add_child(g2)
	# 조준 시간 제한
	var tp := PanelContainer.new()
	var tsb := _sb(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), 10)
	tsb.set_content_margin_all(12)
	tp.add_theme_stylebox_override("panel", tsb)
	var th := HBoxContainer.new()
	tp.add_child(th)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 2)
	tv.add_child(_label("조준 8초 제한", 15, TEXT, 1))
	tv.add_child(_label("시간이 끝나면 차례가 넘어갑니다", 13, SUB))
	th.add_child(tv)
	var cb := CheckButton.new()
	cb.button_pressed = settings["timed"]
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v): settings["timed"] = v)
	th.add_child(cb)
	col.add_child(tp)
	# 시작
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	var start := _primary(_button("시작", func(): _start_match()))
	start.custom_minimum_size = Vector2(0, 52)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.add_theme_font_size_override("font_size", 18)
	row2.add_child(start)
	var cat := _button("부품 도감", func(): _show_catalog(true))
	cat.custom_minimum_size = Vector2(130, 52)
	cat.add_theme_font_override("font", font_semi)
	var csb := _sb(Color(0, 0, 0, 0), Color(1, 1, 1, 0.18), 10)
	cat.add_theme_stylebox_override("normal", csb)
	row2.add_child(cat)
	col.add_child(row2)


func _seat_button(i: int) -> Button:
	var human: bool = not settings["cpu"][i]
	var b := _button("", func(): _toggle_cpu(i))
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = "%s 자리, 지금 %s. 눌러서 바꾸기" % [Match.NAMES[i], "사람" if human else "CPU"]
	var border := Color(BRASS, 0.7) if human else Color(1, 1, 1, 0.12)
	b.add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.05), border, 8))
	b.add_theme_stylebox_override("hover", _sb(Color(1, 1, 1, 0.09), border, 8))
	b.add_theme_stylebox_override("pressed", _sb(Color(1, 1, 1, 0.09), border, 8))
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
	var psb := _sb(BRASS if human else Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 999)
	psb.set_border_width_all(0)
	psb.content_margin_left = 10
	psb.content_margin_right = 10
	psb.content_margin_top = 2
	psb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", psb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pl := _nw(_label("사람" if human else "CPU", 13, INK if human else LABEL, 1))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.custom_minimum_size = Vector2(28, 0)
	pill.add_child(pl)
	h.add_child(pill)
	return b


func _set_count(n: int) -> void:
	settings["n"] = n
	settings["timed"] = n >= 5
	_show_setup()


func _toggle_cpu(i: int) -> void:
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
	pc.add_theme_stylebox_override("panel", _panel_style(Color(14 / 255.0, 16 / 255.0, 19 / 255.0, 0.92)))
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


func _part_card(pid: int, part: String) -> Button:
	var d := PartsData.get_part(part)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(196, 326)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _sb(Color("1A1D21"), PANEL_LINE, 10))
	b.add_theme_stylebox_override("hover", _sb(Color("20242A"), BRASS, 10))
	b.add_theme_stylebox_override("pressed", _sb(Color("20242A"), POWER, 10))
	b.pressed.connect(func(): _on_card_picked(pid, part))
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 14)
	b.add_child(mc)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	mc.add_child(v)
	var demo := {"weapon": "", "aux": "", "prop": ""}
	demo[d["slot"]] = part
	v.add_child(_puck_pic(demo, m.players[pid].color, pid, Vector2(0, 124), 1.18))
	var sh := HBoxContainer.new()
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_theme_constant_override("separation", 6)
	var si := Control.new()
	si.custom_minimum_size = Vector2(18, 18)
	si.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot: String = d["slot"]
	si.draw.connect(func(): Art.draw_slot_icon(si, si.size * 0.5, 18, slot))
	sh.add_child(si)
	var slot_l := _label(PartsData.SLOT_LABEL[slot] + " · " + d["when"], 13, BRASS)
	slot_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(slot_l)
	v.add_child(sh)
	var name_l := _label(d["name"], 20, TEXT, 2)
	var desc_l := _label(d["desc"], 14, SUB)
	for l in [name_l, desc_l]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	var tag := ""
	var tag_col := SUB
	if PartsData.set_of(part) != "":
		var best := 0
		for st in m.world.alive_stones_of(pid):
			var c: int = PartsData.set_progress(st.parts)["count"]
			if c < 3:
				best = maxi(best, c)
		if best == 2:
			tag = "고르면 세트 완성 · 메카 티라노"
			tag_col = POWER
		else:
			tag = "티라노 세트 %d/3" % (best + 1)
			tag_col = HINT_GOLD
	elif not m.trex_missing(pid).is_empty():
		tag = "일반 부품"
	if tag != "":
		var tl := _label(tag, 13, tag_col, 1)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tl)
	var need: String = d.get("needs", "")
	if need != "":
		var any_ok := false
		for s in m.world.alive_stones_of(pid):
			var tmp: Dictionary = s.parts.duplicate()
			tmp[d["slot"]] = part
			if PartsData.unmet_need(part, tmp) == "":
				any_ok = true
		var nl := _label("조건 충족" if any_ok else "⚠ " + PartsData.unmet_need(part, {}), 13, Color("7FD1A8") if any_ok else POWER)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nl)
	return b


func _show_draft_cards(pid: int) -> void:
	var p: Dictionary = m.players[pid]
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(14 / 255.0, 16 / 255.0, 19 / 255.0, 0.94), Color(p.color, 0.8)))
	var width := minf(780.0, vs.x - 24.0)
	pc.custom_minimum_size = Vector2(width, 0)
	pc.position = Vector2((vs.x - width) * 0.5, 0)
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(_icon_pic(p.color, pid, 36))
	head.add_child(_nw(_label("%s 개조 · %d바퀴" % [p.name, m.round_no], 24, TEXT, 2)))
	v.add_child(head)
	v.add_child(_label("후보 세 개 중 하나를 골라 살아 있는 내 퍽에 장착합니다. 같은 슬롯의 부품은 교체돼요.", 14, SUB))
	for st in m.world.alive_stones_of(pid):
		var lbl := PartsData.set_label(st.parts)
		if lbl != "" and not PartsData.set_complete(st.parts):
			v.add_child(_label("장착 화면 표시: " + lbl, 14, POWER, 1))
			break
	if portrait and vs.x < 640:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		for part in m.offers[pid]:
			var c := _part_card(pid, part)
			c.custom_minimum_size = Vector2(0, 236)
			col.add_child(c)
		v.add_child(col)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		for part in m.offers[pid]:
			row.add_child(_part_card(pid, part))
		v.add_child(row)
	await get_tree().process_frame
	if is_instance_valid(pc):
		var h := pc.size.y
		pc.position.y = clampf(view_center.y - h * 0.5, 8, vs.y - h - 8)


func _hint_panel(pid: int) -> VBoxContainer:
	var root := _new_overlay(false)
	var pc := PanelContainer.new()
	var sb := _panel_style(Color(14 / 255.0, 16 / 255.0, 19 / 255.0, 0.92), Color(m.players[pid].color, 0.8))
	sb.set_content_margin_all(16)
	pc.add_theme_stylebox_override("panel", sb)
	var vs := get_viewport_rect().size
	pc.position = Vector2(24, 112) if not portrait else Vector2(12, 86)
	pc.custom_minimum_size = Vector2(minf(420, vs.x - 24), 0)
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	return v


func _show_stone_hint(pid: int) -> void:
	var v := _hint_panel(pid)
	var d := PartsData.get_part(draft_part)
	v.add_child(_label("'%s'(%s)을 달 퍽을 누르세요" % [d["name"], PartsData.SLOT_LABEL[d["slot"]]], 17, TEXT, 1))
	v.add_child(_button("다시 고르기", func(): _show_draft_cards(pid)))


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
	var pid := m.current_player()
	var part: String = m.players[pid].relic
	if m.equip_relic(pid, sid):
		relic_mode = false
		_clear_overlay()
		var st = m.world.get_stone(sid)
		_log("%s 유품 %s 달았어요" % [_j(m.players[pid].name, "이", "가"), _j(PartsData.part_name(part), "을", "를")], m.players[pid].color)
		fx.append({"k": "ring", "pos": st.pos, "t": 0.0, "life": 0.6, "r": 40.0, "c": POWER})


func _show_side_choice(pid: int) -> void:
	var v := _hint_panel(pid)
	var q := {"magnet": "자석팔을 어느 쪽에 달까요? (쏘는 방향 기준)",
		"shield": "딱지 방패가 탄환을 어느 쪽으로 튕길까요? (쏘는 방향 기준)",
		"side_scroll": "옆구리 주문서가 어느 쪽으로 꺾을까요? (쏘는 방향 기준)",
		"crab": "게걸음 바퀴가 어느 쪽으로 튈까요? (쏘는 방향 기준)"}
	v.add_child(_label(q.get(draft_part, "어느 쪽에 달까요?"), 17, TEXT, 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var sid := draft_stone
	var part := draft_part
	h.add_child(_button("◀ 왼쪽", func(): _apply_equip(pid, part, sid, -1)))
	h.add_child(_button("오른쪽 ▶", func(): _apply_equip(pid, part, sid, 1)))
	h.add_child(_button("다시 고르기", func(): _show_draft_cards(pid)))
	v.add_child(h)


func _show_result() -> void:
	state = "result"
	drag_stone = -1
	var root := _new_overlay(true)
	var box := _centered_panel(root, 520)
	var title := ""
	var col := TEXT
	if m.winners.is_empty():
		title = "무승부"
	elif m.winners.size() == 1:
		title = "%s 승리" % m.players[m.winners[0]].name
		col = m.players[m.winners[0]].color.lightened(0.15)
	else:
		var names: Array = []
		for w in m.winners:
			names.append(m.players[w].name)
		title = "공동 승리: " + ", ".join(names)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	if m.winners.size() == 1:
		head.add_child(_icon_pic(m.players[m.winners[0]].color, m.winners[0], 48))
	var tl := _label(title, 34, col, 2)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	box.add_child(head)
	var reason := {"last": "마지막까지 퍽이 남았습니다", "limit": "최대 %d바퀴 도달 · 남은 퍽이 가장 많은 사람이 승리" % m.max_rounds, "draw": "한 발에 모두 떨어졌습니다"}
	box.add_child(_label(reason.get(m.end_reason, ""), 15, SUB))
	# 순위: 남은 퍽 많은 순, 그다음 늦게 탈락한 순
	var rank: Array = []
	for p in m.players:
		if not p.out:
			rank.append(p.id)
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
		r.add_child(_nw(_label(("퍽 %d개" % m.stones_left(pid)) if not p.out else "%d바퀴 탈락" % p.out_round, 15, SUB)))
		box.add_child(r)
		i += 1
	box.add_child(_label("%d바퀴 · %d발" % [m.round_no, m.shots], 13, SUB))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var again := _primary(_button("바로 재대결", func(): _start_match()))
	again.custom_minimum_size = Vector2(200, 52)
	again.add_theme_font_size_override("font_size", 19)
	row.add_child(again)
	var back := _button("설정으로", func(): _show_setup())
	back.custom_minimum_size = Vector2(140, 52)
	row.add_child(back)
	box.add_child(row)
