extends Node2D
## 화면 연출과 입력. 판정은 match.gd, 물리는 world.gd, 부품은 parts.gd 가 맡는다.

const Match = preload("res://scripts/sim/match.gd")
const World = preload("res://scripts/sim/world.gd")
const Parts = preload("res://scripts/sim/parts.gd")
const PartsData = preload("res://scripts/sim/parts_data.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const Art = preload("res://scripts/stone_art.gd")

const BOARD_COL := Color("c99a62")
const BOARD_INNER := Color("d8ad76")
const EDGE_COL := Color("c08d55")
const TEXT := Color("eef0f3")
const SUB := Color("9aa3ad")
const PANEL_BG := Color(0.10, 0.11, 0.135, 0.94)
const MAX_DRAG := 150.0      # 화면 px: 이만큼 당기면 최대 힘
const CANCEL_R := 1.15       # 알 반지름의 몇 배 안으로 돌아오면 조준 취소

var font: Font
var font_bold: Font
var m: Match
var settings := {"n": 4, "cpu": [false, true, true, true, true, true, true, true], "timed": false}
var state := "setup"          # setup | play | result

# 화면 배치
var view_center := Vector2.ZERO
var view_scale := 1.0
var panel_rect := Rect2()
var portrait := false

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


func _ready() -> void:
	font = load("res://fonts/NotoSansKR.ttf")
	var fb := FontVariation.new()
	fb.base_font = font
	fb.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 760}
	font_bold = fb
	theme_ = Theme.new()
	theme_.default_font = font
	theme_.default_font_size = 18
	ui = CanvasLayer.new()
	add_child(ui)
	menu_btn = _button("≡ 처음으로", func(): _show_setup())
	menu_btn.position = Vector2(12, 10)
	menu_btn.theme = theme_
	menu_btn.visible = false
	ui.add_child(menu_btn)
	parts_btn = _button("부품 도감", func(): _show_catalog(false))
	parts_btn.theme = theme_
	parts_btn.visible = false
	ui.add_child(parts_btn)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_setup()
	_debug_args()


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
	var board_area: Rect2
	if portrait:
		var ph := clampf(vs.y * 0.24, 200.0, 300.0)
		panel_rect = Rect2(0, vs.y - ph, vs.x, ph)
		board_area = Rect2(0, 54, vs.x, vs.y - ph - 54)
	else:
		var pw := clampf(vs.x * 0.27, 290.0, 380.0)
		panel_rect = Rect2(vs.x - pw, 0, pw, vs.y)
		board_area = Rect2(0, 50, vs.x - pw, vs.y - 50)
	view_center = board_area.get_center()
	var extent := 340.0
	if m != null:
		extent = m.world.size * (1.0 if m.world.shape == "circle" else 1.05)
	view_scale = minf(board_area.size.x, board_area.size.y) / (2.0 * (extent + 26.0))
	if parts_btn:
		parts_btn.position = Vector2(140, 10)


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
			_log("%s 자기 알 %d개 추락" % [who, by_owner[o]])
		else:
			_log("%s → %s 알 %d개 탈락" % [who, m.players[o].name, by_owner[o]])
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
	draw_rect(Rect2(Vector2.ZERO, vs), Color("16191e"))
	if m == null:
		_draw_title_backdrop(vs)
		return
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
	_draw_hover_card()
	_draw_top_bar(vs)
	_draw_panel()
	if banner_t > 0.0:
		var a := clampf(banner_t / 0.4, 0.0, 1.0)
		_text_outline(Vector2(view_center.x, 96 if not portrait else 100), banner, 34, Color(_banner_col, a), true)


func _draw_title_backdrop(vs: Vector2) -> void:
	var c := vs * 0.5
	draw_circle(c, minf(vs.x, vs.y) * 0.42, Color(BOARD_COL, 0.12))
	for i in 8:
		var ang := time * 0.25 + TAU * i / 8.0
		var p := c + Vector2.from_angle(ang) * minf(vs.x, vs.y) * 0.34
		draw_set_transform(p, ang + PI, Vector2.ONE * 1.4)
		var parts := {"weapon": ["pea", "shotgun", "hook", "claw", "nose", "stamp", "copier", "pea"][i],
			"aux": ["magnet", "bumper", "decal", "umbrella", "spring", "carousel", "bubble", "mine"][i],
			"prop": ["rocket", "retro", "reel", "chute", "rocket", "retro", "reel", "chute"][i]}
		Art.draw(self, parts, 1, Match.COLORS[i], 0.35)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_board() -> void:
	var w := m.world
	var k := view_scale
	if w.shape == "circle":
		draw_circle(view_center + Vector2(0, 8), w.size * k + 10, Color(0, 0, 0, 0.35))
		draw_circle(view_center, w.size * k + 9, Color("5a3d22"))
		draw_circle(view_center, w.size * k, EDGE_COL)
		draw_circle(view_center, (w.size - World.EDGE_ZONE) * k, BOARD_INNER)
		_dashed_circle(view_center, (w.size - World.EDGE_ZONE) * k, Color(0.45, 0.28, 0.12, 0.45))
		for i in 5:
			draw_arc(view_center, (w.size * (0.2 + i * 0.15)) * k, 0, TAU, 96, Color(0.55, 0.38, 0.2, 0.18), 1.5, true)
		draw_circle(view_center, 4.0, Color(0.5, 0.33, 0.18, 0.5))
	else:
		var h := w.size * k
		draw_rect(Rect2(view_center - Vector2(h + 10, h + 2), Vector2(2 * h + 20, 2 * h + 20)), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(view_center - Vector2(h + 9, h + 9), Vector2(2 * h + 18, 2 * h + 18)), Color("5a3d22"))
		draw_rect(Rect2(view_center - Vector2(h, h), Vector2(2 * h, 2 * h)), EDGE_COL)
		var h2 := (w.size - World.EDGE_ZONE) * k
		draw_rect(Rect2(view_center - Vector2(h2, h2), Vector2(2 * h2, 2 * h2)), BOARD_INNER)
		var corners := [Vector2(-h2, -h2), Vector2(h2, -h2), Vector2(h2, h2), Vector2(-h2, h2)]
		for i in 4:
			draw_dashed_line(view_center + corners[i], view_center + corners[(i + 1) % 4], Color(0.45, 0.28, 0.12, 0.45), 2.0, 10.0)
		var h3 := h2
		for i in range(1, 6):
			var x := -h3 + 2 * h3 * i / 6.0
			draw_line(view_center + Vector2(x, -h3), view_center + Vector2(x, h3), Color(0.55, 0.38, 0.2, 0.15), 1.5)
			draw_line(view_center + Vector2(-h3, x), view_center + Vector2(h3, x), Color(0.55, 0.38, 0.2, 0.15), 1.5)


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
	# 지금 차례인 알 표시
	if m.phase == "aim" and s.owner == m.current_player():
		var pulse := 0.5 + 0.5 * sin(time * 5.0)
		draw_arc(p, (World.STONE_R + 7 + pulse * 3) * view_scale, 0, TAU, 40, Color(col.lightened(0.4), 0.85), 2.5, true)
		if m.aim_limit > 0.0 and not m.players[s.owner].cpu:
			var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
			draw_arc(p, (World.STONE_R + 13) * view_scale, -PI / 2, -PI / 2 + TAU * frac, 40, Color(1, 1, 1, 0.7), 3.0, true)
	draw_set_transform(p, facing, Vector2.ONE * view_scale)
	Art.draw(self, s.parts, s.magnet_side, col)
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
				draw_polyline(pts, Color(col, 0.6), 4.0 * k, true)
				draw_line(p - along * half, p + along * half, Color(0.85, 0.97, 1.0), 4.0 * k, true)
				draw_line(p - along * half, p + along * half, Color(1, 1, 1, 0.5 + 0.3 * sin(time * 4)), 1.5, true)
				_small_label(p + back * 22 * k, _left_text(d), col)
			"mine":
				var blink := 0.5 + 0.5 * sin(time * (8.0 if d.armed else 2.0))
				if d.armed:
					draw_arc(p, (World.STONE_R + PartsData.num("mine", "radius")) * k, 0, TAU, 32, Color(1, 0.3, 0.2, 0.25), 1.5, true)
				draw_circle(p, 11 * k, Color("2a2c31"))
				draw_arc(p, 11 * k, 0, TAU, 24, col, 2.5, true)
				draw_circle(p, 4 * k, Color(1, 0.25 + 0.3 * blink, 0.2))
				_small_label(p + Vector2(0, 20 * k), _left_text(d), col)
			"bubble":
				var r := PartsData.num("bubble", "radius") * k
				draw_circle(p, r, Color(0.6, 0.9, 1.0, 0.35))
				draw_arc(p, r, 0, TAU, 28, Color(0.8, 0.97, 1.0, 0.9), 2.0, true)
				draw_circle(p + Vector2(-r * 0.35, -r * 0.35), r * 0.25, Color(1, 1, 1, 0.8))
				draw_arc(p, r + 3, 0, TAU, 28, Color(col, 0.7), 1.5, true)
			"turret":
				var dir: Vector2 = d.dir
				draw_set_transform(p, dir.angle(), Vector2.ONE * k)
				draw_rect(Rect2(-9, -9, 18, 18), Color("d7d9dd"))
				draw_rect(Rect2(-9, -9, 18, 18), col, false, 2.5)
				draw_rect(Rect2(6, -3, 14, 6), Color("2a2c31"))
				draw_set_transform_matrix(Transform2D.IDENTITY)
				draw_dashed_line(p + dir * 22 * k, p + dir * 70 * k, Color(col, 0.6), 2.0, 6.0)


func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var segs := 72
	for i in segs:
		if i % 2 == 0:
			draw_arc(c, r, TAU * i / segs, TAU * (i + 1) / segs, 4, col, 2.0, true)


func _left_text(d) -> String:
	if d.expires_round < 0:
		return ""
	var left: int = d.expires_round - m.round_no + 1
	return "%d바퀴" % left


func _draw_projs() -> void:
	for p in m.world.projs:
		var col: Color = m.players[p.owner].color.lightened(0.45)
		var sp := w2s(p.pos)
		if p.kind == "bullet":
			var tail: Vector2 = sp - p.vel.normalized() * 26.0 * view_scale
			draw_line(tail, sp, Color(col, 0.7), 4.0 * view_scale, true)
			draw_circle(sp, 4.5 * view_scale, Color(1, 1, 0.9) if p.source != "decal" else Color(0.95, 0.8, 1.0))
			if p.source == "reflect":
				draw_arc(sp, 8 * view_scale, 0, TAU, 12, Color(0.75, 0.95, 1.0), 1.5)
		else:
			draw_circle(sp, World.RUBBER_R * view_scale, Color(0.95, 0.45, 0.65))
			draw_arc(sp, World.RUBBER_R * view_scale, 0, TAU, 16, col, 2.0, true)


func _draw_fx() -> void:
	for f in fx:
		var u: float = f["t"] / f["life"]
		var c: Color = f["c"]
		match f["k"]:
			"ring":
				draw_arc(w2s(f["pos"]), f["r"] * view_scale * (0.6 + u * 0.8), 0, TAU, 32, Color(c, 1.0 - u), 3.0, true)
			"boom":
				draw_circle(w2s(f["pos"]), f["r"] * view_scale * (0.3 + u * 0.7), Color(c, 0.35 * (1.0 - u)))
				draw_arc(w2s(f["pos"]), f["r"] * view_scale * (0.3 + u * 0.7), 0, TAU, 40, Color(c, 1.0 - u), 4.0, true)
			"line":
				draw_line(w2s(f["a"]), w2s(f["b"]), Color(c, 0.9 * (1.0 - u)), 3.0, true)
			"text":
				var p := w2s(f["pos"]) + Vector2(0, -24.0 * u)
				_text_outline(p, f["text"], f["size"], Color(c, clampf(2.0 - 2.0 * u, 0.0, 1.0)), true)


## 바닥에 깔리는 조준 정보 (자석 범위).
func _draw_aim_under() -> void:
	var info := _current_aim()
	if info.is_empty():
		return
	for item in info["preview"]:
		if item["k"] == "magnet":
			var c := w2s(item["a"])
			var r: float = item["r"] * view_scale
			var base: float = item["dir"].angle()
			var pts := PackedVector2Array([c])
			for i in 25:
				pts.append(c + Vector2.from_angle(base - PI / 2 + PI * i / 24.0) * r)
			draw_colored_polygon(pts, Color(0.95, 0.3, 0.3, 0.12))
			draw_arc(c, r, base - PI / 2, base + PI / 2, 24, Color(0.95, 0.4, 0.4, 0.5), 2.0, true)


func _draw_aim_over() -> void:
	var info := _current_aim()
	if info.is_empty():
		return
	var s = info["stone"]
	var col: Color = m.players[s.owner].color
	if info.has("finger"):
		draw_line(w2s(s.pos), info["finger"], Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(info["finger"], 6, Color(1, 1, 1, 0.5))
	for item in info["preview"]:
		match item["k"]:
			"move":
				var a := w2s(item["a"])
				var b := w2s(item["b"])
				draw_line(a, b, Color(col.lightened(0.3), 0.9), 5.0, true)
				var d := (b - a).normalized()
				draw_colored_polygon(PackedVector2Array([b + d * 14, b + d.orthogonal() * 9, b - d.orthogonal() * 9]), col.lightened(0.3))
			"bullet":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color(1, 0.95, 0.6, 0.85), 2.0, 8.0)
			"decal":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color(0.85, 0.6, 1.0, 0.85), 2.0, 8.0)
				draw_circle(w2s(item["a"]), 5, Color(0.85, 0.6, 1.0, 0.9))
			"hook":
				draw_dashed_line(w2s(item["a"]), w2s(item["b"]), Color(0.8, 0.8, 0.85, 0.6), 2.0, 4.0)
			"target":
				draw_arc(w2s(item["a"]), (World.STONE_R + 6) * view_scale, 0, TAU, 32, Color(1, 0.4, 0.35, 0.95), 3.0, true)
			"note":
				_text_outline(w2s(item["a"]) + Vector2(0, 44 * view_scale + 10), item["text"], 16, Color(1, 1, 1, 0.9), true)
	_text_outline(w2s(s.pos) + Vector2(0, -(World.STONE_R + 20) * view_scale - 6), "%d%%" % int(round(info["power"] * 100)), 18, Color.WHITE, true)


func _current_aim() -> Dictionary:
	if m.phase != "aim":
		return {}
	if drag_stone >= 0:
		var s = m.world.get_stone(drag_stone)
		var aim := _aim_of(drag_stone, drag_screen)
		if aim.is_empty():
			return {}
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
		draw_arc(p, (World.STONE_R + 8 + pulse * 4) * view_scale, 0, TAU, 40, Color(1, 1, 1, 0.9), 3.0, true)
		var cur: String = s.parts[slot]
		var t := "%s: %s" % [PartsData.SLOT_LABEL[slot], "비어 있음" if cur == "" else PartsData.part_name(cur) + " → 교체"]
		_small_label(p + Vector2(0, (World.STONE_R + 22) * view_scale), t, TEXT)
		if draft_stone == s.id:
			draw_arc(p, (World.STONE_R + 16) * view_scale, 0, TAU, 40, Color(1, 0.9, 0.3), 3.0, true)


func _draw_hover_card() -> void:
	if hover_stone < 0 or drag_stone >= 0:
		return
	var s = m.world.get_stone(hover_stone)
	if s == null or not s.alive:
		return
	var lines: Array = []
	for slot in PartsData.SLOTS:
		var pid_: String = s.parts[slot]
		var nm := PartsData.part_name(pid_)
		if pid_ == "magnet":
			nm += " (왼쪽)" if s.magnet_side < 0 else " (오른쪽)"
		var warn := PartsData.unmet_need(pid_, s.parts) if pid_ != "" else ""
		lines.append(["%s  %s" % [PartsData.SLOT_LABEL[slot], nm], warn])
	var p := w2s(s.pos) + Vector2(30, -20)
	var wbox := 210.0
	var hbox := 18.0 + lines.size() * 24.0
	for l in lines:
		if l[1] != "":
			hbox += 20
	var vs := get_viewport_rect().size
	p.x = minf(p.x, vs.x - wbox - 8)
	p.y = clampf(p.y, 8, vs.y - hbox - 8)
	draw_rect(Rect2(p, Vector2(wbox, hbox)), Color(0.08, 0.09, 0.11, 0.92))
	draw_rect(Rect2(p, Vector2(wbox, 4)), m.players[s.owner].color)
	var y := p.y + 28
	for l in lines:
		draw_string(font, Vector2(p.x + 10, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, wbox - 16, 16, TEXT)
		y += 24
		if l[1] != "":
			draw_string(font, Vector2(p.x + 10, y - 4), "⚠ " + l[1], HORIZONTAL_ALIGNMENT_LEFT, wbox - 16, 12, Color(1, 0.75, 0.4))
			y += 20


func _draw_top_bar(vs: Vector2) -> void:
	var t := "%d / %d바퀴" % [m.round_no, m.max_rounds]
	if m.is_draft_round(m.round_no):
		t += " · 개조"
	if portrait:
		var tw := font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_text_outline(Vector2(vs.x - 14 - tw, 32), t, 18, SUB, false)
	else:
		_text_outline(Vector2(view_center.x, 34), t, 20, SUB, true)


func _draw_panel() -> void:
	var r := panel_rect
	draw_rect(r, PANEL_BG)
	var x := r.position.x + 18
	var y := r.position.y + 34
	var w := r.size.x - 36
	# 차례
	var line := ""
	var col := TEXT
	match m.phase:
		"aim", "moving":
			var p: Dictionary = m.players[m.current_player()]
			line = "%s 차례%s" % [p.name, " (CPU)" if p.cpu else ""]
			col = p.color
		"draft":
			var p2: Dictionary = m.players[m.current_drafter()]
			line = "%s 개조 중" % p2.name
			col = p2.color
		"over":
			line = "경기 끝"
	draw_string(font_bold, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, 24, col)
	y += 12
	if m.phase == "aim" and m.aim_limit > 0.0 and not m.players[m.current_player()].cpu:
		var frac := clampf(aim_left / m.aim_limit, 0.0, 1.0)
		draw_rect(Rect2(x, y, w, 6), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(x, y, w * frac, 6), Color(1, 0.8, 0.3) if frac > 0.3 else Color(1, 0.35, 0.3))
	y += 20
	var hint := ""
	if m.phase == "aim" and not m.players[m.current_player()].cpu:
		hint = "내 알을 누른 채 뒤로 당겼다 놓기 · 알 가까이 되돌리면 취소"
	elif m.phase == "aim":
		hint = "생각 중…"
	if hint != "":
		draw_string(font, Vector2(x, y), hint, HORIZONTAL_ALIGNMENT_LEFT, w, 13, SUB)
	y += 16
	# 플레이어 목록
	var cols := 1 if not portrait else 2
	var cw := w / cols
	var row_h := 22.0 + 17.0 * (3 if m.n == 2 else 2)
	if portrait:
		row_h = 20.0 + 15.0 * (3 if m.n == 2 else 2)
	var start_y := y
	var max_rows := int((r.end.y - y - (110 if not portrait else 8)) / row_h)
	max_rows = maxi(1, max_rows)
	for i in m.n:
		var p: Dictionary = m.players[i]
		var cx := x + (i % cols) * cw if portrait else x
		var cy := start_y + (i / cols if portrait else i) * row_h
		if (i / cols if portrait else i) >= max_rows:
			continue
		var alpha := 0.4 if p.out else 1.0
		draw_circle(Vector2(cx + 7, cy + 12), 7, Color(p.color, alpha))
		var name_s: String = p.name + (" CPU" if p.cpu else "")
		draw_string(font_bold, Vector2(cx + 22, cy + 18), name_s, HORIZONTAL_ALIGNMENT_LEFT, cw - 90, 16, Color(TEXT, alpha))
		var left := m.stones_left(i)
		if p.out:
			draw_string(font, Vector2(cx + cw - 70, cy + 18), "탈락", HORIZONTAL_ALIGNMENT_RIGHT, 60, 14, Color(1, 0.5, 0.5, 0.8))
		else:
			for k in left:
				draw_circle(Vector2(cx + cw - 16 - k * 14, cy + 12), 5, p.color)
		var sy := cy + 36
		var fs := 12 if portrait else 13
		for s in m.world.stones:
			if s.owner != i or not s.alive:
				continue
			var names: Array = []
			for slot in PartsData.SLOTS:
				if s.parts[slot] != "":
					var nm := PartsData.part_name(s.parts[slot])
					if s.parts[slot] == "magnet":
						nm += "(좌)" if s.magnet_side < 0 else "(우)"
					names.append(nm)
			draw_string(font, Vector2(cx + 22, sy), "· " + (" + ".join(names) if not names.is_empty() else "일반 알"), HORIZONTAL_ALIGNMENT_LEFT, cw - 30, fs, Color(SUB, alpha))
			sy += 15 if portrait else 17
	# 기록
	if not portrait:
		var ly := r.end.y - 96
		draw_line(Vector2(x, ly - 18), Vector2(x + w, ly - 18), Color(1, 1, 1, 0.08), 1)
		var shown := log_lines.slice(maxi(0, log_lines.size() - 5))
		for l in shown:
			draw_string(font, Vector2(x, ly), l, HORIZONTAL_ALIGNMENT_LEFT, w, 13, SUB)
			ly += 18


func _small_label(p: Vector2, t: String, c: Color) -> void:
	if t == "":
		return
	_text_outline(p, t, 13, c, true)


func _text_outline(p: Vector2, t: String, size: int, c: Color, center: bool) -> void:
	var width := font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := p - Vector2(width * 0.5 if center else 0.0, 0)
	draw_string_outline(font_bold, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, c.a * 0.75))
	draw_string(font_bold, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


# ── UI 화면 ──────────────────────────────────────────────

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _label(text: String, size := 18, col := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _panel_style(bg := PANEL_BG, border := Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	return sb


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
		bg.color = Color(0.05, 0.06, 0.08, 0.78)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
	ui.add_child(root)
	overlay = root
	return root


func _centered_panel(root: Control, min_w: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var vs := get_viewport_rect().size
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
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
	var box := _centered_panel(root, 620)
	box.add_child(_label("개조 알까기", 40, TEXT, true))
	box.add_child(_label("알을 튕겨 상대를 판 밖으로. 바퀴마다 부품을 골라 내 알을 개조한다.", 16, SUB))
	box.add_child(_label("인원", 16, SUB, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var narrow := get_viewport_rect().size.x < 640
	for n in range(2, 9):
		var b := _button("%d인" % n, func(): _set_count(n))
		b.toggle_mode = true
		b.button_pressed = settings["n"] == n
		b.custom_minimum_size = Vector2(50 if narrow else 62, 44)
		row.add_child(b)
	box.add_child(row)
	box.add_child(_label("자리 (눌러서 사람/CPU 바꾸기)", 16, SUB, true))
	var grid := GridContainer.new()
	grid.columns = 2 if narrow else 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in settings["n"]:
		var b2 := _button("", func(): _toggle_cpu(i))
		b2.text = "%s · %s" % [Match.NAMES[i], "CPU" if settings["cpu"][i] else "사람"]
		b2.add_theme_color_override("font_color", Match.COLORS[i].lightened(0.25))
		b2.add_theme_color_override("font_hover_color", Match.COLORS[i].lightened(0.45))
		b2.custom_minimum_size = Vector2(0 if narrow else 134, 44)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b2)
	box.add_child(grid)
	var cb := CheckButton.new()
	cb.text = "조준 8초 제한 (시간이 끝나면 턴 넘김)"
	cb.button_pressed = settings["timed"]
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v): settings["timed"] = v)
	box.add_child(cb)
	var info := "판: %s · 알 %d개씩 · 최대 %d바퀴 · 개조: %s바퀴 시작" % [
		"정사각형" if settings["n"] == 2 else ("원형" if settings["n"] <= 4 else "넓은 원형"),
		3 if settings["n"] == 2 else 2,
		12 if settings["n"] == 2 else (8 if settings["n"] <= 4 else 6),
		"2·3·4" if settings["n"] <= 4 else "1·2·3"]
	box.add_child(_label(info, 15, SUB))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var start := _button("시작", func(): _start_match())
	start.custom_minimum_size = Vector2(200, 54)
	start.add_theme_font_size_override("font_size", 22)
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
	var cc := MarginContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		cc.add_theme_constant_override("margin_" + side, 24)
	root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var head := HBoxContainer.new()
	var title := _label("부품 도감 · 20종", 26, TEXT, true)
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
	v.add_child(_label("알 하나에 무기·보조·추진 슬롯이 하나씩. 같은 슬롯에 새 부품을 달면 교체된다. 발사한 알의 부품은 한 샷에 한 번씩 작동한다.", 14, SUB))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for slot in PartsData.SLOTS:
		list.add_child(_label(PartsData.SLOT_LABEL[slot], 18, Color(1, 0.85, 0.5), true))
		for id in PartsData.ids():
			var d := PartsData.get_part(id)
			if d["slot"] != slot:
				continue
			list.add_child(_label("%s  —  %s · %s" % [d["name"], d["when"], d["desc"]], 15, TEXT))


func _part_card(pid: int, part: String) -> Button:
	var d := PartsData.get_part(part)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(190, 272)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _on_card_picked(pid, part))
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 12)
	b.add_child(mc)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	mc.add_child(v)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(0, 64)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var demo := {"weapon": "", "aux": "", "prop": ""}
	demo[d["slot"]] = part
	var pcol: Color = m.players[pid].color
	pic.draw.connect(func():
		pic.draw_set_transform(Vector2(44, 32), -0.35, Vector2.ONE * 1.25)
		Art.draw(pic, demo, 1, pcol)
		pic.draw_set_transform_matrix(Transform2D.IDENTITY))
	v.add_child(pic)
	var slot_l := _label(PartsData.SLOT_LABEL[d["slot"]] + " · " + d["when"], 13, Color(1, 0.85, 0.5))
	var name_l := _label(d["name"], 21, TEXT, true)
	var desc_l := _label(d["desc"], 14, SUB)
	for l in [slot_l, name_l, desc_l]:
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
		var nl := _label(("조건 충족" if any_ok else "⚠ ") + ("" if any_ok else PartsData.unmet_need(part, {})), 13, Color(0.5, 0.9, 0.6) if any_ok else Color(1, 0.7, 0.4))
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nl)
	return b


func _show_draft_cards(pid: int) -> void:
	var p: Dictionary = m.players[pid]
	var root := _new_overlay(false)
	var vs := get_viewport_rect().size
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.11, 0.135, 0.97), p.color))
	var width := minf(760.0, (panel_rect.position.x if not portrait else vs.x) - 24.0)
	pc.custom_minimum_size = Vector2(width, 0)
	pc.position = Vector2(((panel_rect.position.x if not portrait else vs.x) - width) * 0.5, 0)
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	v.add_child(_label("%s 개조 · %d바퀴" % [p.name, m.round_no], 24, p.color.lightened(0.2), true))
	v.add_child(_label("후보 세 개 중 하나를 골라 살아 있는 내 알에 장착합니다. 같은 슬롯의 부품은 교체돼요.", 14, SUB))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if portrait and vs.x < 640:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		for part in m.offers[pid]:
			var c := _part_card(pid, part)
			c.custom_minimum_size = Vector2(0, 205)
			col.add_child(c)
		v.add_child(col)
	else:
		for part in m.offers[pid]:
			row.add_child(_part_card(pid, part))
		v.add_child(row)
	# 판 가운데 아래쪽에 놓는다
	await get_tree().process_frame
	if is_instance_valid(pc):
		var h := pc.size.y
		pc.position.y = clampf(view_center.y - h * 0.5, 8, vs.y - h - 8)


func _show_stone_hint(pid: int) -> void:
	var root := _new_overlay(false)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.11, 0.135, 0.96), m.players[pid].color))
	pc.position = Vector2(12, 58)
	root.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	pc.add_child(h)
	var d := PartsData.get_part(draft_part)
	h.add_child(_label("'%s'(%s)을 달 알을 누르세요" % [d["name"], PartsData.SLOT_LABEL[d["slot"]]], 17, TEXT, true))
	h.add_child(_button("다시 고르기", func(): _show_draft_cards(pid)))


func _show_side_choice(pid: int) -> void:
	var root := _new_overlay(false)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.11, 0.135, 0.96), m.players[pid].color))
	pc.position = Vector2(12, 58)
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	v.add_child(_label("자석팔을 어느 쪽에 달까요? (쏘는 방향 기준)", 17, TEXT, true))
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
		title = "%s 승리!" % m.players[m.winners[0]].name
		col = m.players[m.winners[0]].color
	else:
		var names: Array = []
		for w in m.winners:
			names.append(m.players[w].name)
		title = "공동 승리: " + ", ".join(names)
	box.add_child(_label(title, 36, col.lightened(0.15), true))
	var reason := {"last": "마지막까지 알이 남았습니다", "limit": "최대 %d바퀴 도달 · 남은 알이 가장 많은 사람이 승리" % m.max_rounds, "draw": "한 발에 모두 떨어졌습니다"}
	box.add_child(_label(reason.get(m.end_reason, ""), 16, SUB))
	# 순위: 남은 알 많은 순, 그다음 늦게 탈락한 순
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
		var t := "%d. %s  —  %s" % [i, p.name, ("알 %d개" % m.stones_left(pid)) if not p.out else "%d바퀴 탈락" % p.out_round]
		box.add_child(_label(t, 17, p.color.lightened(0.25)))
		i += 1
	box.add_child(_label("%d바퀴 · %d발" % [m.round_no, m.shots], 14, SUB))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var again := _button("바로 재대결", func(): _start_match())
	again.custom_minimum_size = Vector2(200, 52)
	again.add_theme_font_size_override("font_size", 20)
	row.add_child(again)
	var back := _button("설정으로", func(): _show_setup())
	back.custom_minimum_size = Vector2(140, 52)
	row.add_child(back)
	box.add_child(row)
