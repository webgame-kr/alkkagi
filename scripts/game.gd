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
const PANEL_BG := Color(14 / 255.0, 16 / 255.0, 19 / 255.0, 0.78)
const PANEL_LINE := Color(1, 1, 1, 0.1)

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
	_panel_sb.set_corner_radius_all(10)
	ui = CanvasLayer.new()
	add_child(ui)
	menu_btn = _button("처음으로", func(): _show_setup())
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
	var vs := get_viewport_rect().size
	portrait = vs.y > vs.x * 1.1
	var extent := CELL * 9.0
	if m != null:
		extent = m.world.size
	var rail := 1.07  # 레일까지 포함한 바깥 반지름 비율
	if portrait:
		var top := 124.0
		var bottom := vs.y - 196.0
		view_center = Vector2(vs.x * 0.5, (top + bottom) * 0.5)
		var r_px := minf((bottom - top) * 0.5, vs.x * 0.5 - 8.0)
		view_scale = r_px / (extent * rail)
		var half := (vs.x - 36.0) * 0.5
		hud = {"turn": Rect2(12, 12, vs.x - 24, 66),
			"left": Rect2(12, vs.y - 184, half, 172),
			"parts": Rect2(24 + half, vs.y - 184, half, 172)}
		if menu_btn:
			menu_btn.position = Vector2(12, 86)
			parts_btn.position = Vector2(108, 86)
	else:
		var side := 24.0 + 232.0 + 16.0
		var r_px := minf(vs.y * 0.5 - 20.0, vs.x * 0.5 - side)
		view_center = vs * 0.5
		view_scale = r_px / (extent * rail)
		hud = {"turn": Rect2(24, 24, 268, 76),
			"legend": Rect2(24, 168, 232, 0),
			"power": Rect2(24, vs.y - 24 - 72, 232, 72),
			"left": Rect2(vs.x - 24 - 232, 24, 232, 0),
			"parts": Rect2(vs.x - 24 - 232, vs.y - 24 - 150, 232, 150)}
		if menu_btn:
			menu_btn.position = Vector2(24, 112)
			parts_btn.position = Vector2(120, 112)


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
	_log("%d인전 시작 · 선공 %s" % [m.n, m.players[m.current_player()].name])


func _process(delta: float) -> void:
	time += delta
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
			accum += minf(delta, 0.05)
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
			if m.players[pid].cpu:
				_update_cpu(delta, pid)
			elif m.aim_limit > 0.0:
				aim_left -= delta
				if aim_left <= 0.0:
					drag_stone = -1
					_log("%s 시간 초과 — 턴을 넘깁니다" % m.players[pid].name)
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
			m.shoot(c["stone"], c["dir"], c["power"])
		return
	if bot == null:
		bot_wait -= delta
		if bot_wait > 0.0:
			return
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
		if o == shooter_owner:
			_log("%s 자기 퍽 %d개 추락" % [who, by_owner[o]])
		else:
			_log("%s → %s 퍽 %d개 탈락" % [who, m.players[o].name, by_owner[o]])
	for pid in m.out_order:
		if not _logged_out.has(pid):
			_logged_out[pid] = true
			_log("%s 탈락" % m.players[pid].name)


var _logged_out := {}
var _shot_dir := ""
var _shot_n := 0


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 40:
		log_lines.pop_front()


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
				fx.append({"k": "text", "pos": e["pos"] + Vector2(0, -30), "t": 0.0, "life": 1.1, "text": e.get("text", ""), "c": owner_col.lightened(0.35), "size": 20})
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
	if event.pressed:
		var sid2 := _stone_at(wp2, m.current_player())
		if sid2 >= 0:
			drag_stone = sid2
			drag_screen = event.position
	elif drag_stone >= 0:
		var aim := _aim_of(drag_stone, event.position)
		var sid3 := drag_stone
		drag_stone = -1
		if not aim.is_empty():
			m.shoot(sid3, aim["dir"], aim["power"])


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


## 손 위치로 조준을 계산한다. 알 가까이 되돌아오면 취소(빈 사전).
func _aim_of(stone_id: int, screen_pos: Vector2) -> Dictionary:
	var s = m.world.get_stone(stone_id)
	var sp := w2s(s.pos)
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
	if draft_part == "magnet":
		draft_stone = sid
		_show_side_choice(pid)
	else:
		_apply_equip(pid, draft_part, sid, 1)


func _apply_equip(pid: int, part: String, sid: int, side: int) -> void:
	var s = m.world.get_stone(sid)
	var slot := PartsData.slot_of(part)
	var old: String = s.parts[slot]
	if m.equip(pid, part, sid, side):
		var txt := PartsData.part_name(part)
		if part == "magnet":
			txt += "(왼쪽)" if side < 0 else "(오른쪽)"
		_log("%s: %s 장착%s" % [m.players[pid].name, txt, ("  (%s 교체)" % PartsData.part_name(old)) if old != "" else ""])
		fx.append({"k": "text", "pos": s.pos + Vector2(0, -34), "t": 0.0, "life": 1.3, "text": txt, "c": m.players[pid].color.lightened(0.35), "size": 20})
		fx.append({"k": "ring", "pos": s.pos, "t": 0.0, "life": 0.5, "r": 34.0, "c": m.players[pid].color})
	draft_part = ""
	draft_stone = -1
	_clear_overlay()


# ── 그리기 ───────────────────────────────────────────────

func _draw() -> void:
	var vs := get_viewport_rect().size
	if m == null:
		_draw_page_felt(vs)
		_draw_title_backdrop(vs)
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
		var y := view_center.y - 40.0 if not portrait else 112.0
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


func _draw_title_backdrop(vs: Vector2) -> void:
	var c := vs * 0.5
	var rr := minf(vs.x, vs.y) * 0.40
	for i in 8:
		var ang := time * 0.2 + TAU * i / 8.0
		var p := c + Vector2.from_angle(ang) * rr
		draw_set_transform(p, ang + PI, Vector2.ONE * 1.5)
		var parts := {"weapon": ["pea", "shotgun", "hook", "claw", "nose", "stamp", "copier", "pea"][i],
			"aux": ["magnet", "bumper", "decal", "umbrella", "spring", "carousel", "bubble", "mine"][i],
			"prop": ["rocket", "retro", "reel", "chute", "rocket", "retro", "reel", "chute"][i]}
		Art.draw(self, parts, 1, Match.COLORS[i], 0.55, i)
		draw_set_transform_matrix(Transform2D.IDENTITY)


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
	if drag_stone == s.id:
		var aim := _aim_of(s.id, drag_screen)
		if not aim.is_empty():
			facing = aim["dir"].angle()
	elif not cpu_aim.is_empty() and cpu_aim["stone"] == s.id:
		facing = cpu_aim["dir"].angle()
	var p := w2s(s.pos)
	# 지금 차례인 퍽 표시
	if m.phase == "aim" and s.owner == m.current_player() and drag_stone < 0:
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		draw_arc(p, (World.STONE_R + 6 + pulse * 3) * view_scale, 0, TAU, 40, Color(col.lightened(0.35), 0.55 + 0.3 * pulse), 2.0, true)
		if m.aim_limit > 0.0 and not m.players[s.owner].cpu:
			var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
			draw_arc(p, (World.STONE_R + 13) * view_scale, -PI / 2, -PI / 2 + TAU * frac, 40, Color(POWER, 0.85), 3.0, true)
	draw_set_transform(p, facing, Vector2.ONE * view_scale)
	Art.draw(self, s.parts, s.magnet_side, col, 1.0, s.owner)
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
		else:
			var r := World.RUBBER_R * view_scale
			draw_circle(sp, r, BRASS)
			draw_arc(sp, r, 0, TAU, 16, INK, 2.0, true)


func _draw_fx() -> void:
	for f in fx:
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
	var sp := w2s(s.pos)
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
		return {"stone": s, "power": aim["power"], "finger": drag_screen,
			"preview": Parts.aim_preview(m.world, s, aim["dir"], aim["power"])}
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
	_draw_remaining(hud["left"])
	_draw_parts_panel(hud["parts"])
	if not portrait:
		_draw_legend(hud["legend"])
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
				sub = "CPU · " + ("생각 중…" if m.phase == "aim" else "%d바퀴째, %d바퀴까지" % [m.round_no, m.max_rounds])
			else:
				sub = "%d바퀴째, %d바퀴까지" % [m.round_no, m.max_rounds]
		"draft":
			pid = m.current_drafter()
			title = "%s 개조" % m.players[pid].name
			sub = "%d바퀴 시작 · 부품 고르기" % m.round_no
		_:
			title = "경기 끝"
			sub = "%d바퀴" % m.round_no
	_panel(r)
	if pid >= 0:
		Art.draw_icon(self, r.position + Vector2(14 + 22, r.size.y * 0.5 - 1), 44, m.players[pid].color, pid)
	var x := r.position.x + 72
	_txt(Vector2(x, r.position.y + 33), title, 22, TEXT, font_bold, r.size.x - 84)
	_txt(Vector2(x, r.position.y + 56), sub, 14, SUB, font, r.size.x - 84)
	# 세로 화면: 힘을 카드 오른쪽에
	if portrait and m.phase == "aim":
		var info := _current_aim()
		if not info.is_empty():
			var pw := int(round(info["power"] * 100))
			_txt(Vector2(r.end.x - 16, r.position.y + 33), "%d%%" % pw, 22, POWER, font_bold, 80, HORIZONTAL_ALIGNMENT_RIGHT)
			_segments(Rect2(r.end.x - 116, r.position.y + 44, 100, 8), info["power"])
	if m.phase == "aim" and m.aim_limit > 0.0 and not m.players[m.current_player()].cpu:
		var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
		draw_rect(Rect2(r.position.x + 10, r.end.y - 6, (r.size.x - 20) * frac, 3), POWER if frac > 0.3 else Art.RED)


func _draw_remaining(r: Rect2) -> void:
	var row := 26.0
	var fs := 15
	if portrait:
		row = 18.0 if m.n > 6 else 22.0
		fs = 13 if m.n > 6 else 14
	var h := 16.0 + 22.0 + row * m.n + 6.0
	if not portrait:
		r.size.y = h
		hud["left_end"] = r.end.y
	_panel(r)
	_txt(r.position + Vector2(18, 28), "남은 퍽", 13, SUB, font_semi)
	var y := r.position.y + 40
	for p in m.players:
		var a := 0.4 if p.out else 1.0
		var cy := y + row * 0.5
		Art.draw_icon(self, Vector2(r.position.x + 18 + 10, cy), row - 4, p.color, p.id, a)
		var name_s: String = p.name + ("  CPU" if p.cpu else "")
		_txt(Vector2(r.position.x + 48, cy + fs * 0.36), name_s, fs, Color(TEXT, a), font, r.size.x - 110)
		if p.out:
			_txt(Vector2(r.end.x - 16, cy + 5), "탈락", 13, Color(SUB, 0.8), font, 60, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			var left := m.stones_left(p.id)
			for k in left:
				draw_circle(Vector2(r.end.x - 18 - k * 13, cy), 4.5, p.color)
		y += row


func _draw_log() -> void:
	if log_lines.is_empty():
		return
	var shown: Array = log_lines.slice(maxi(0, log_lines.size() - 4))
	var r := Rect2(hud["left"].position.x, hud.get("left_end", 200.0) + 12, 232, 18 + shown.size() * 19)
	if r.end.y > hud["parts"].position.y - 12:
		return
	_panel(r)
	var y := r.position.y + 24
	for l in shown:
		_txt(Vector2(r.position.x + 14, y), l, 12, SUB, font, r.size.x - 28)
		y += 19


func _draw_legend(r: Rect2) -> void:
	if m.phase != "aim" or m.players[m.current_player()].cpu:
		return
	var s = _focus_stone()
	if s == null:
		return
	var rows: Array = [["move", "진행 방향, 길이가 곧 힘"]]
	if PartsData.BULLET_WEAPONS.has(s.parts["weapon"]):
		rows.append(["bullet", "총탄 사선"])
		if s.parts["aux"] == "decal":
			rows.append(["decal", "반대편 보조 사선"])
	if s.parts["aux"] == "magnet":
		rows.append(["magnet", "자석 작동 범위"])
	if s.parts["weapon"] == "hook":
		rows.append(["hook", "갈고리 사거리"])
	rows.append(["cancel", "이 안으로 되돌리면 취소"])
	r.size.y = 40 + rows.size() * 26
	_panel(r)
	_txt(r.position + Vector2(18, 28), "조준선", 13, SUB, font_semi)
	var col: Color = m.players[s.owner].color.lightened(0.25)
	var y := r.position.y + 50
	for row in rows:
		var x0 := r.position.x + 18
		match row[0]:
			"move":
				draw_line(Vector2(x0 + 2, y - 5), Vector2(x0 + 34, y - 5), TEXT, 4.0, true)
				draw_colored_polygon(PackedVector2Array([Vector2(x0 + 33, y - 10), Vector2(x0 + 42, y - 5), Vector2(x0 + 33, y)]), TEXT)
			"bullet":
				draw_dashed_line(Vector2(x0 + 2, y - 5), Vector2(x0 + 42, y - 5), col, 2.5, 7.0)
			"decal":
				draw_dashed_line(Vector2(x0 + 2, y - 5), Vector2(x0 + 42, y - 5), Color(col, 0.5), 2.5, 7.0)
			"hook":
				draw_dashed_line(Vector2(x0 + 2, y - 5), Vector2(x0 + 42, y - 5), Color(Art.STEEL, 0.6), 2.0, 4.0)
			"magnet":
				var pts := PackedVector2Array([Vector2(x0 + 2, y), Vector2(x0 + 42, y), Vector2(x0 + 34, y - 10)])
				draw_colored_polygon(pts, Color(col, 0.25))
			"cancel":
				_dashed_ring(Vector2(x0 + 22, y - 5), 5.5, Color(1, 1, 1, 0.5))
		_txt(Vector2(x0 + 56, y), row[1], 14, TEXT, font, r.size.x - 78)
		y += 26


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
	_txt(Vector2(r.end.x - 18, r.position.y + 34), label, 22, POWER, font_bold, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	_segments(Rect2(r.position.x + 18, r.position.y + 46, r.size.x - 36, 12), pw)


func _draw_parts_panel(r: Rect2) -> void:
	var s = _focus_stone()
	_panel(r)
	_txt(r.position + Vector2(18, 28), "이 퍽의 부품", 13, SUB, font_semi)
	if s == null:
		return
	Art.draw_icon(self, Vector2(r.end.x - 26, r.position.y + 22), 20, m.players[s.owner].color, s.owner)
	var y := r.position.y + 54
	var step := 32.0 if not portrait else 36.0
	for slot in PartsData.SLOTS:
		var id: String = s.parts[slot]
		Art.draw_slot_icon(self, Vector2(r.position.x + 30, y - 5), 24, slot)
		_txt(Vector2(r.position.x + 50, y), PartsData.SLOT_LABEL[slot], 13, SUB, font)
		var nm := PartsData.part_name(id) if id != "" else "없음"
		if id == "magnet":
			nm += " (왼쪽)" if s.magnet_side < 0 else " (오른쪽)"
		_txt(Vector2(r.position.x + 88, y), nm, 15, TEXT if id != "" else Color(SUB, 0.7), font_semi if id != "" else font, r.size.x - 100)
		if id != "":
			var warn := PartsData.unmet_need(id, s.parts)
			if warn != "":
				_txt(Vector2(r.position.x + 88, y + 15), "⚠ 탄환 무기 없음", 11, Color(POWER, 0.9), font, r.size.x - 100)
		y += step


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
	var box := _centered_panel(root, 640)
	box.add_child(_label("개조 알까기", 40, TEXT, 2))
	box.add_child(_label("펠트 테이블 위의 금속 퍽을 튕겨 상대를 판 밖으로. 바퀴마다 부품을 골라 내 퍽을 개조한다.", 16, SUB_FELT))
	box.add_child(_label("인원", 15, SUB, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var narrow := get_viewport_rect().size.x < 640
	for n in range(2, 9):
		var b := _button("%d인" % n, func(): _set_count(n))
		b.toggle_mode = true
		b.button_pressed = settings["n"] == n
		b.custom_minimum_size = Vector2(50 if narrow else 64, 44)
		row.add_child(b)
	box.add_child(row)
	box.add_child(_label("자리 (눌러서 사람/CPU 바꾸기)", 15, SUB, 1))
	var grid := GridContainer.new()
	grid.columns = 2 if narrow else 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in settings["n"]:
		var b2 := _button("", func(): _toggle_cpu(i))
		b2.text = "%s · %s" % [Match.NAMES[i], "CPU" if settings["cpu"][i] else "사람"]
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.add_theme_constant_override("h_separation", 8)
		b2.custom_minimum_size = Vector2(0 if narrow else 138, 46)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := _sb(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.14), 8)
		sb.content_margin_left = 40
		b2.add_theme_stylebox_override("normal", sb)
		var sbh := _sb(Color(1, 1, 1, 0.11), Color(1, 1, 1, 0.24), 8)
		sbh.content_margin_left = 40
		b2.add_theme_stylebox_override("hover", sbh)
		b2.add_theme_stylebox_override("pressed", sbh)
		var ic := _icon_pic(Match.COLORS[i], i, 24)
		ic.position = Vector2(8, 8)
		b2.add_child(ic)
		grid.add_child(b2)
	box.add_child(grid)
	var cb := CheckButton.new()
	cb.text = "조준 8초 제한 (시간이 끝나면 턴 넘김)"
	cb.button_pressed = settings["timed"]
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v): settings["timed"] = v)
	box.add_child(cb)
	var info := "판: %s · 퍽 %d개씩 · 최대 %d바퀴 · 개조: %s바퀴 시작" % [
		"정사각형 16칸" if settings["n"] == 2 else ("원형 지름 18칸" if settings["n"] <= 4 else "넓은 원형 지름 24칸"),
		3 if settings["n"] == 2 else 2,
		12 if settings["n"] == 2 else (8 if settings["n"] <= 4 else 6),
		"2·3·4" if settings["n"] <= 4 else "1·2·3"]
	box.add_child(_label(info, 14, SUB))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var start := _primary(_button("시작", func(): _start_match()))
	start.custom_minimum_size = Vector2(200, 54)
	start.add_theme_font_size_override("font_size", 21)
	row2.add_child(start)
	var cat := _button("부품 도감", func(): _show_catalog(true))
	cat.custom_minimum_size = Vector2(140, 54)
	row2.add_child(cat)
	box.add_child(row2)


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
	var title := _nw(_label("퍽과 부품 · 20종", 26, TEXT, 2))
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


func _part_card(pid: int, part: String) -> Button:
	var d := PartsData.get_part(part)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(196, 300)
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


func _show_side_choice(pid: int) -> void:
	var v := _hint_panel(pid)
	v.add_child(_label("자석팔을 어느 쪽에 달까요? (쏘는 방향 기준)", 17, TEXT, 1))
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
