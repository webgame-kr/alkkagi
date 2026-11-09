extends SceneTree
## 판정·물리·부품 테스트. 실행:
##   godot --headless --path . -s res://tests/run_tests.gd

const World = preload("res://scripts/sim/world.gd")
const Match = preload("res://scripts/sim/match.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const PartsData = preload("res://scripts/sim/parts_data.gd")

var failures := 0
var passes := 0


func _initialize() -> void:
	var tests := [
		"test_collision_and_knockout", "test_weak_vs_strong", "test_pea_bullet",
		"test_shotgun_three_pellets", "test_magnet_side", "test_retro_returns_inward",
		"test_rocket_pushes_further", "test_stamp_swaps_only_when_weak", "test_decal_mirror_bullet",
		"test_mirror_reflects", "test_mine_arms_next_shot", "test_reel_returns",
		"test_hook_pulls", "test_claw_grips", "test_copier_turret_fires_next_shot",
		"test_chute_brakes", "test_bubble_and_device_limit", "test_parts_once_per_shot",
		"test_layout_all_counts", "test_draft_schedule_and_equip", "test_round_limit_winner",
		"test_last_player_wins", "test_draw_when_nobody_left", "test_bot_matches_finish",
		"test_world_clone_is_independent",
	]
	for t in tests:
		var before := failures
		call(t)
		if failures == before:
			passes += 1
			print("  ok   ", t)
		else:
			print("  FAIL ", t)
	print("\n%d passed, %d failed" % [passes, tests.size() - passes])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("    assertion failed: " + msg)
		print("    ✗ ", msg)


func make_world(shape := "circle", size := 340.0) -> World:
	var w := World.new()
	w.shape = shape
	w.size = size
	w.record_events = true
	return w


func shoot(w: World, id: int, dir: Vector2, power: float) -> void:
	w.launch(id, dir, power)
	w.run_until_settled()
	w.end_shot()


func count_events(w: World, kind: String, part := "") -> int:
	var c := 0
	for e in w.events:
		if e["t"] == kind and (part == "" or e.get("part", "") == part):
			c += 1
	return c


# ── 기본 물리 ────────────────────────────────────────────

func test_collision_and_knockout() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(0, 0), 0)
	var b := w.add_stone(1, Vector2(250, 0), 0)
	shoot(w, a.id, Vector2.RIGHT, 1.0)
	check(not b.alive, "strong head-on hit should knock b off the board")
	check(a.alive, "shooter should stay")
	check(count_events(w, "out") == 1, "one out event")


func test_weak_vs_strong() -> void:
	# 약한 샷은 상대를 판 안에 두고 내 알도 안전, 강한 샷은 떨어뜨리지만 나도 멀리 간다.
	var w := make_world()
	var a := w.add_stone(0, Vector2(-150, 0), 0)
	var b := w.add_stone(1, Vector2(0, 0), 0)
	shoot(w, a.id, Vector2.RIGHT, 0.3)
	check(b.alive and a.alive, "weak shot keeps both on the board")
	var w2 := make_world()
	var a2 := w2.add_stone(0, Vector2(-50, 0), 0)
	var b2 := w2.add_stone(1, Vector2(170, 0), 0)
	shoot(w2, a2.id, Vector2.RIGHT, 1.0)
	check(not b2.alive, "strong shot knocks out from the centre")


func test_pea_bullet() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(150, 0), 0)
	a.parts["weapon"] = "pea"
	w.launch(a.id, Vector2.RIGHT, 0.1)
	check(w.projs.size() == 1, "pea fires one bullet")
	w.run_until_settled()
	check(b.pos.x > 150.0 + 50.0, "bullet pushed b along the line: %.1f" % b.pos.x)
	check(a.pos.x < -100.0, "shooter barely moved (weak shot)")
	check(count_events(w, "bullet_hit") == 1, "one bullet hit")


func test_shotgun_three_pellets() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	a.parts["weapon"] = "shotgun"
	w.add_stone(1, Vector2(-120, 0), 0)
	w.launch(a.id, Vector2.RIGHT, 0.1)
	check(w.projs.size() == 3, "shotgun fires three")
	w.run_until_settled()
	check(count_events(w, "bullet_hit") >= 2, "close target takes several pellets")


func test_magnet_side() -> void:
	# 오른쪽 자석은 진행 방향 오른쪽(화면 아래, +y) 상대만 당긴다.
	var w := make_world()
	var a := w.add_stone(0, Vector2(-100, 0), 0)
	a.parts["aux"] = "magnet"
	a.magnet_side = 1
	var right := w.add_stone(1, Vector2(-60, 150), 0)
	var left := w.add_stone(2, Vector2(-60, -200), 0)
	var y_left := left.pos.y
	w.launch(a.id, Vector2.RIGHT, 0.3)
	check(right.vel.y < -100.0, "right-side stone pulled up toward the shooter")
	check(left.vel == Vector2.ZERO, "left-side stone untouched")
	w.run_until_settled()
	check(is_equal_approx(left.pos.y, y_left), "left stone stayed")


func test_retro_returns_inward() -> void:
	# 가장자리 상대를 세게 쳐도 역추진이면 나는 판 안에 남는다.
	var plain := make_world()
	var a := plain.add_stone(0, Vector2(150, 0), 0)
	plain.add_stone(1, Vector2(290, 0), 0)
	shoot(plain, a.id, Vector2.RIGHT, 1.0)
	var w := make_world()
	var r := w.add_stone(0, Vector2(150, 0), 0)
	var t := w.add_stone(1, Vector2(290, 0), 0)
	r.parts["prop"] = "retro"
	shoot(w, r.id, Vector2.RIGHT, 1.0)
	check(not t.alive, "target knocked out")
	check(r.alive, "retro shooter survives")
	check(r.pos.x < 250.0, "retro pulled back inward: %.1f" % r.pos.x)
	check(count_events(w, "part", "retro") == 1, "retro fired once")


func test_rocket_pushes_further() -> void:
	var p := make_world()
	var a := p.add_stone(0, Vector2(-200, 0), 0)
	var b := p.add_stone(1, Vector2(-100, 0), 0)
	shoot(p, a.id, Vector2.RIGHT, 0.45)
	var w := make_world()
	var a2 := w.add_stone(0, Vector2(-200, 0), 0)
	var b2 := w.add_stone(1, Vector2(-100, 0), 0)
	a2.parts["prop"] = "rocket"
	shoot(w, a2.id, Vector2.RIGHT, 0.45)
	check(count_events(w, "part", "rocket") == 1, "rocket fired")
	check(a2.pos.x > a.pos.x + 30.0, "rocket shooter travels further after the hit: %.0f vs %.0f" % [a2.pos.x, a.pos.x])
	check(not b2.alive or b2.pos.x > b.pos.x, "and pushes the target further")


func test_stamp_swaps_only_when_weak() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-100, 0), 0)
	var b := w.add_stone(1, Vector2(0, 0), 0)
	a.parts["weapon"] = "stamp"
	shoot(w, a.id, Vector2.RIGHT, 0.35)
	check(count_events(w, "part", "stamp") == 1, "weak shot swaps")
	check(a.pos.x > b.pos.x, "shooter now sits where the target was")
	check(a.vel == Vector2.ZERO and b.vel == Vector2.ZERO, "both stopped")
	var w2 := make_world()
	var a2 := w2.add_stone(0, Vector2(-100, 0), 0)
	w2.add_stone(1, Vector2(0, 0), 0)
	a2.parts["weapon"] = "stamp"
	shoot(w2, a2.id, Vector2.RIGHT, 0.7)
	check(count_events(w2, "part", "stamp") == 0, "strong shot is a normal hit")


func test_decal_mirror_bullet() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 100), 0)
	a.parts["weapon"] = "pea"
	a.parts["aux"] = "decal"
	var mirror_target := w.add_stone(1, Vector2(100, -100), 0)
	w.launch(a.id, Vector2.RIGHT, 0.05)
	check(w.projs.size() == 2, "pea + decal = two bullets")
	var dec = w.projs[1]
	check(dec.source == "decal" and dec.vel.x < 0.0, "mirror bullet flies the opposite way")
	w.run_until_settled()
	check(mirror_target.pos.x < 100.0 - 50.0, "mirror bullet hit the stone across the centre")
	# 무기 없이 데칼코마니만 있으면 아무것도 나가지 않는다
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(0, 0), 0)
	b.parts["aux"] = "decal"
	w2.launch(b.id, Vector2.RIGHT, 0.2)
	check(w2.projs.is_empty(), "decal needs a bullet weapon")
	check(PartsData.unmet_need("decal", b.parts) != "", "unmet need reported")


func test_mirror_reflects() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-200, -150), 0)
	w.place_device("mirror", 1, 99, Vector2(0, 0), Vector2(-1, -1).normalized(), 5)
	a.parts["weapon"] = "pea"
	w.launch(a.id, Vector2.RIGHT, 0.05)
	w.run_until_settled()
	check(count_events(w, "reflect") == 1, "bullet reflected")
	check(w.devices.is_empty(), "mirror folds after one reflection")
	check(b.alive, "b alive")
	# 오른쪽으로 가던 탄이 (-1,-1) 법선 거울에 맞으면 위쪽(-y)으로 꺾인다
	var hit_pos := Vector2.ZERO
	for e in w.events:
		if e["t"] == "reflect":
			hit_pos = e["pos"]
	check(absf(hit_pos.x) < 5.0, "reflected at the mirror")


func test_mine_arms_next_shot() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-100, 0), 0)
	a.parts["aux"] = "mine"
	shoot(w, a.id, Vector2.RIGHT, 0.3)
	check(w.devices.size() == 1 and w.devices[0].kind == "mine", "mine placed where the stone stopped")
	var mine_pos: Vector2 = w.devices[0].pos
	check(mine_pos.distance_to(a.pos) < 1.0, "mine under the stone")
	var c := w.add_stone(1, mine_pos + Vector2(0, 120), 0)
	w.round_no = 2
	# 지뢰 위에 있던 알은 떠나도 터지지 않는다. 다른 알이 오면 터진다.
	shoot(w, c.id, Vector2.UP, 0.5)
	check(count_events(w, "boom") == 1, "mine exploded on contact")
	check(w.devices.is_empty(), "mine gone")


func test_reel_returns() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(0, 0), 0)
	a.parts["prop"] = "reel"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	check(count_events(w, "part", "reel") == 1, "reel fired")
	check(a.pos.distance_to(Vector2(-200, 0)) < 120.0, "reeled back near the start: %s" % str(a.pos))


func test_hook_pulls() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	var b := w.add_stone(1, Vector2(100, 0), 0)
	a.parts["weapon"] = "hook"
	w.launch(a.id, Vector2.RIGHT, 0.05)
	check(b.vel.x < -300.0, "hook yanks the first opponent toward me")


func test_claw_grips() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-100, 0), 0)
	var b := w.add_stone(1, Vector2(0, 0), 0)
	a.parts["weapon"] = "claw"
	w.launch(a.id, Vector2.RIGHT, 0.6)
	for i in 30:
		w.step()
	check(w.shot.grip_timer > 0.0, "grip active")
	check(absf(b.pos.distance_to(a.pos) - 44.5) < 1.0, "target held in front")
	w.run_until_settled()


func test_copier_turret_fires_next_shot() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var a2 := w.add_stone(0, Vector2(-200, 200), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["weapon"] = "copier"
	shoot(w, a.id, Vector2.RIGHT, 0.45)
	check(w.devices.size() == 1 and w.devices[0].kind == "turret", "turret placed")
	w.events.clear()
	w.launch(a2.id, Vector2.UP, 0.1)
	check(w.projs.size() == 1 and w.projs[0].source == "turret", "turret fires with my next shot")
	check(w.devices.is_empty(), "turret gone after firing")
	w.run_until_settled()


func test_chute_brakes() -> void:
	var plain := make_world()
	var p := plain.add_stone(0, Vector2(0, 0), 0)
	shoot(plain, p.id, Vector2.RIGHT, 0.95)
	check(not p.alive, "without chute it slides off")
	var w := make_world()
	var a := w.add_stone(0, Vector2(0, 0), 0)
	a.parts["prop"] = "chute"
	shoot(w, a.id, Vector2.RIGHT, 0.95)
	check(a.alive, "chute brakes in the edge zone")
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(200, 0), 0)
	b.parts["prop"] = "chute"
	shoot(w2, b.id, Vector2.RIGHT, 1.0)
	check(not b.alive, "too fast still falls")


func test_bubble_and_device_limit() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	a.parts["aux"] = "bubble"
	shoot(w, a.id, Vector2.RIGHT, 0.5)
	check(w.devices.size() == 1 and w.devices[0].kind == "bubble", "bubble left on the path")
	check(w.devices[0].pos.x > -250.0 and w.devices[0].pos.x < a.pos.x, "bubble mid-path")
	shoot(w, a.id, Vector2.LEFT, 0.3)
	check(w.devices.size() == 1, "one bubble per part: the old one is replaced")


func test_parts_once_per_shot() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	w.add_stone(2, Vector2(-100, 60), 0)
	a.parts["prop"] = "rocket"
	a.parts["aux"] = "bumper"
	shoot(w, a.id, Vector2.RIGHT, 0.8)
	check(count_events(w, "part", "rocket") <= 1, "rocket at most once")
	check(count_events(w, "part", "bumper") <= 1, "bumper at most once")


# ── 경기 ─────────────────────────────────────────────────

func test_layout_all_counts() -> void:
	for n in range(2, 9):
		var m := Match.new()
		m.setup(n, [], 7, false)
		var per := 3 if n == 2 else 2
		check(m.world.stones.size() == n * per, "%d players: stone count" % n)
		for s in m.world.stones:
			check(m.world.edge_distance(s.pos) > 80.0, "%d players: stones well inside" % n)
			for o in m.world.stones:
				if o.id != s.id:
					check(o.pos.distance_to(s.pos) > 50.0, "%d players: no overlap" % n)
	var m2 := Match.new()
	m2.setup(2, [], 1, false)
	check(m2.world.shape == "square" and m2.max_rounds == 12, "2p square, 12 rounds")
	var m6 := Match.new()
	m6.setup(6, [], 1, true)
	check(m6.world.size > 340.0 and m6.max_rounds == 6 and m6.aim_limit == 8.0, "6p wide circle, 6 rounds, timer")


func test_draft_schedule_and_equip() -> void:
	var m := Match.new()
	m.setup(4, [], 3, false)
	check(m.phase == "aim" and m.round_no == 1, "4p: round 1 has no draft")
	for i in 4:
		m.skip_turn()
	check(m.round_no == 2 and m.phase == "draft", "4p: draft at round 2")
	check(m.draft_queue.size() == 4, "everyone alive picks")
	var pid := m.current_drafter()
	check(pid == m.order[0], "local draft follows the start order")
	var part: String = m.offers[pid][0]
	var s = m.world.alive_stones_of(pid)[0]
	check(m.equip(pid, part, s.id, -1), "equip ok")
	check(s.parts[PartsData.slot_of(part)] == part, "part on the stone")
	check(not m.equip(pid, part, s.id), "cannot pick twice")
	# 슬롯 교체
	var pid2 := m.current_drafter()
	var s2 = m.world.alive_stones_of(pid2)[0]
	s2.parts["weapon"] = "pea"
	m.offers[pid2] = ["shotgun", "rocket", "mine"]
	m.equip(pid2, "shotgun", s2.id)
	check(s2.parts["weapon"] == "shotgun", "same slot replaced")
	var m6 := Match.new()
	m6.setup(6, [], 3, false)
	check(m6.phase == "draft" and m6.round_no == 1, "5-8p: draft from round 1")
	check(m6.draft_rounds == [1, 2, 3], "5-8p schedule")
	# 시작 자리는 바퀴마다 넘어간다
	var m3 := Match.new()
	m3.setup(3, [], 5, false)
	var first: int = m3.order[0]
	for i in 3:
		m3.skip_turn()
	m3.draft_queue.clear()
	m3.phase = "aim"
	check(m3.order[0] == (first + 1) % 3, "start seat rotates")


func test_round_limit_winner() -> void:
	var m := Match.new()
	m.setup(3, [], 9, false)
	m.world.stones[0].alive = false   # 플레이어 0 하나 잃음
	var guard := 0
	while m.phase != "over" and guard < 200:
		guard += 1
		if m.phase == "draft":
			m.draft_queue.clear()
			m.phase = "aim"
		m.skip_turn()
	check(m.phase == "over" and m.end_reason == "limit", "match ends at the round limit")
	check(m.winners.size() == 2 and not m.winners.has(0), "ties share the win, fewer stones lose")


func test_last_player_wins() -> void:
	var m := Match.new()
	m.setup(4, [], 2, false)
	for s in m.world.stones:
		if s.owner != 2:
			s.alive = false
	m.skip_turn()
	check(m.phase == "over" and m.winners == [2] and m.end_reason == "last", "last one standing wins")


func test_draw_when_nobody_left() -> void:
	var m := Match.new()
	m.setup(2, [], 2, false)
	for s in m.world.stones:
		s.alive = false
	m.skip_turn()
	check(m.phase == "over" and m.winners.is_empty() and m.end_reason == "draw", "nobody left = draw")


func test_bot_matches_finish() -> void:
	for n in [2, 4, 8]:
		var m := Match.new()
		var flags := []
		for i in n:
			flags.append(true)
		m.setup(n, flags, 100 + n, false)
		var rng := RandomNumberGenerator.new()
		rng.seed = n
		var guard := 0
		while m.phase != "over" and guard < 400:
			guard += 1
			if m.phase == "draft":
				var pid := m.current_drafter()
				var c := Bot.choose_draft(m, pid, rng)
				check(m.equip(pid, c["part"], c["stone"], c["side"]), "bot equip ok")
			elif m.phase == "aim":
				var bot := Bot.new()
				bot.begin(m, m.current_player(), guard)
				while not bot.think_step(4):
					pass
				var r := bot.result()
				check(m.shoot(r["stone"], r["dir"], r["power"]), "bot shot accepted")
				m.world.run_until_settled()
				m.finish_shot()
		check(m.phase == "over", "%d-player bot match finished (round %d)" % [n, m.round_no])


func test_world_clone_is_independent() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-100, 0), 0)
	w.add_stone(1, Vector2(0, 0), 0)
	var c = w.clone()
	c.launch(a.id, Vector2.RIGHT, 1.0)
	c.run_until_settled()
	check(a.pos == Vector2(-100, 0) and w.shot == null, "original untouched by the preview")
	check(c.events.is_empty(), "clone records no events")
