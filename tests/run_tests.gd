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
		"test_trex_head_bites_forward", "test_sucker_brakes_moving_stone", "test_umbrella_gun_wide_push",
		"test_roller_slick_strip", "test_trex_arm_pulls_front", "test_shield_deflects_bullet",
		"test_tambourine_ripple", "test_track_groove_bends", "test_trex_leg_reduces_recoil",
		"test_crab_hops_sideways", "test_clockwork_boost", "test_brake_stops",
		"test_mecha_throw", "test_mecha_frontal_is_plain_bite", "test_trex_draft_rule", "test_set_label",
		"test_mecha_blocked_is_normal_hit", "test_scissors_seal_next_launch", "test_bookmark_reserve",
		"test_edge_sewer_net", "test_drift_tire", "test_flash_step", "test_log_sub", "test_trap_card",
		"test_shadow_scale", "test_night_charm_curse", "test_anchor_returns", "test_moon_orbit_magic",
		"test_hero_last_cut", "test_relic_ribbon", "test_set_recommend_priority", "test_rubber_fist",
		"test_ink_split", "test_echo_bell", "test_stopwatch_freeze", "test_glass_wings", "test_side_scroll",
		"test_cloud_mailbox", "test_ice_and_wall", "test_star_cloak_circle", "test_moon_well",
		"test_mushroom_and_wind", "test_second_step", "test_rebound_and_string", "test_at_field_and_beam",
		"test_hero_band_and_shoes", "test_all_parts_have_art",
		"test_workshop_pools", "test_offer_fits_empty_slots", "test_min_power_moves_one_cell",
		"test_knockout_causes", "test_derby_mode",
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
	w.launch(a.id, Vector2.RIGHT, 0.0)
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
	shoot(p, a.id, Vector2.RIGHT, 0.3)
	var w := make_world()
	var a2 := w.add_stone(0, Vector2(-200, 0), 0)
	var b2 := w.add_stone(1, Vector2(-100, 0), 0)
	a2.parts["prop"] = "rocket"
	shoot(w, a2.id, Vector2.RIGHT, 0.3)
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
	shoot(plain, p.id, Vector2.RIGHT, 0.8)
	check(not p.alive, "without chute it slides off")
	var w := make_world()
	var a := w.add_stone(0, Vector2(0, 0), 0)
	a.parts["prop"] = "chute"
	shoot(w, a.id, Vector2.RIGHT, 0.8)
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
		var per := 4 if n == 2 else 3
		check(m.world.stones.size() == n * per, "%d players: stone count" % n)
		for s in m.world.stones:
			check(m.world.edge_distance(s.pos) > 80.0, "%d players: stones well inside" % n)
			for o in m.world.stones:
				if o.id != s.id:
					check(o.pos.distance_to(s.pos) > 50.0, "%d players: no overlap" % n)
	var m2 := Match.new()
	m2.setup(2, [], 1, false)
	check(m2.world.shape == "square" and m2.max_rounds == 0, "2p square, no round limit")
	var m6 := Match.new()
	m6.setup(6, [], 1, true)
	check(m6.world.size > 340.0 and m6.max_rounds == 0 and m6.aim_limit == 8.0, "6p wide circle, no limit, timer")


func test_draft_schedule_and_equip() -> void:
	var m := Match.new()
	m.setup(4, [], 3, false)
	# 1바퀴는 맨 알로 쏘고, 2바퀴부터 개조
	check(m.phase == "aim" and m.round_no == 1, "round 1 starts bare: %s" % m.phase)
	for i in 4:
		m.skip_turn()
	check(m.phase == "draft" and m.round_no == 2, "draft from round 2")
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
	# 매 바퀴 개조
	_finish_draft(m)
	for i in 4:
		m.skip_turn()
	check(m.round_no == 3 and m.phase == "draft", "draft again at round 3")
	_finish_draft(m)
	for i in 4:
		m.skip_turn()
	check(m.round_no == 4 and m.phase == "draft", "and every round after")
	# 시작 자리는 바퀴마다 넘어간다
	var m3 := Match.new()
	m3.setup(3, [], 5, false)
	_finish_draft(m3)
	var first: int = m3.order[0]
	for i in 3:
		m3.skip_turn()
	_finish_draft(m3)
	check(m3.order[0] == (first + 1) % 3, "start seat rotates")


func _finish_draft(m) -> void:
	if m.phase == "draft":
		m.draft_queue.clear()
		m.phase = "aim"


func test_round_limit_winner() -> void:
	var m := Match.new()
	m.setup(3, [], 9, false)
	m.max_rounds = 8                  # 제한을 켠 경우의 판정 (기본은 제한 없음)
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
	_finish_draft(m)
	for s in m.world.stones:
		if s.owner != 2:
			s.alive = false
	m.skip_turn()
	check(m.phase == "over" and m.winners == [2] and m.end_reason == "last", "last one standing wins")


func test_draw_when_nobody_left() -> void:
	var m := Match.new()
	m.setup(2, [], 2, false)
	_finish_draft(m)
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


# ── 신규 부품 ────────────────────────────────────────────

func test_trex_head_bites_forward() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-150, 0), 0)
	var b := w.add_stone(1, Vector2(-60, 0), 0)
	a.parts["weapon"] = "trex_head"
	shoot(w, a.id, Vector2.RIGHT, 0.5)
	check(count_events(w, "part", "trex_head") == 1, "head bites on frontal hit")
	var p := make_world()
	var a2 := p.add_stone(0, Vector2(-150, 0), 0)
	var b2 := p.add_stone(1, Vector2(-60, 0), 0)
	shoot(p, a2.id, Vector2.RIGHT, 0.5)
	check(b.pos.x > b2.pos.x + 60.0, "bitten stone is thrown further than a plain hit")


func test_sucker_brakes_moving_stone() -> void:
	# 달아나는 알을 빨판이 따라잡아 감속시킨다.
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	var b := w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["weapon"] = "sucker"
	w.launch(a.id, Vector2(0, -1), 0.05)
	w.projs.clear()
	w.spawn_proj("sucker", 0, Vector2(-220, 0), Vector2.RIGHT, 1150.0, 7.0, 0.0, a.id)
	b.vel = Vector2(500, 0)
	w.run_until_settled()
	var p := make_world()
	var b2 := p.add_stone(1, Vector2(-100, 0), 0)
	b2.vel = Vector2(500, 0)
	p.run_until_settled()
	check(count_events(w, "part", "sucker") >= 1, "sucker braked the runner")
	check(b.pos.x < b2.pos.x - 40.0, "suckered stone stops sooner: %.0f vs %.0f" % [b.pos.x, b2.pos.x])
	# 서 있는 알은 표시만 되고, 나중에 움직이면 감속
	var q := make_world()
	var c := q.add_stone(0, Vector2(-250, 0), 0)
	var d := q.add_stone(1, Vector2(0, 0), 0)
	c.parts["weapon"] = "sucker"
	q.launch(c.id, Vector2.RIGHT, 0.05)
	for i in 40:
		q.step()
	check(q.shot.sucker.has(d.id), "standing stone gets the sucker mark")



func test_umbrella_gun_wide_push() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	var b := w.add_stone(1, Vector2(-20, 60), 0)
	var c := w.add_stone(2, Vector2(-20, -60), 0)
	a.parts["weapon"] = "umbrella_gun"
	w.launch(a.id, Vector2.RIGHT, 0.05)
	w.run_until_settled()
	check(count_events(w, "umbrella") == 1, "umbrella opened")
	check(b.pos.x > -20.0 + 30.0 and c.pos.x > -20.0 + 30.0, "both side stones pushed forward")


func test_roller_slick_strip() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-120, 0), 0)
	a.parts["weapon"] = "roller"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	var slick = null
	for d in w.devices:
		if d.kind == "slick":
			slick = d
	check(slick != null and slick.length > 100.0, "slick strip left behind the hit stone")
	# 띠 위로 같은 힘으로 굴리면 더 멀리 간다
	var q := make_world()
	var d2 = q.place_device("slick", 0, 9, Vector2(-200, 100), Vector2.RIGHT, 5)
	d2.length = 200.0
	var c := q.add_stone(2, Vector2(-200, 100), 0)
	c.vel = Vector2.RIGHT * 300.0
	q.run_until_settled()
	var p := make_world()
	var c2 := p.add_stone(2, Vector2(-200, 100), 0)
	c2.vel = Vector2.RIGHT * 300.0
	p.run_until_settled()
	check(c.pos.x > c2.pos.x + 40.0, "slides further on the strip: %.0f vs %.0f" % [c.pos.x, c2.pos.x])



func test_trex_arm_pulls_front() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-120, 38), 0)
	a.parts["aux"] = "trex_arm"
	w.launch(a.id, Vector2.RIGHT, 0.5)
	var pulled := false
	for i in 200:
		w.step()
		if count_events(w, "part", "trex_arm") > 0:
			pulled = true
			break
	check(pulled, "arm grabs on a side hit")
	check(absf(b.pos.y - a.pos.y) < 8.0 and b.pos.x > a.pos.x, "target now in front of the shooter")


func test_shield_deflects_bullet() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(50, 0), 0)
	a.parts["weapon"] = "pea"
	b.parts["aux"] = "shield"
	b.magnet_side = 1
	w.launch(a.id, Vector2.RIGHT, 0.05)
	w.run_until_settled()
	check(count_events(w, "part", "shield") == 1, "shield flipped")
	check(b.pos.distance_to(Vector2(50, 0)) < 1.0, "shielded stone not pushed")


func test_tambourine_ripple() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	var near := w.add_stone(2, Vector2(-120, 80), 0)
	a.parts["aux"] = "tambourine"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	check(count_events(w, "ripple") == 1, "ripple")
	check(near.pos.distance_to(Vector2(-120, 80)) > 10.0, "nearby untouched stone nudged")


func test_track_groove_bends() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	a.parts["aux"] = "track"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	var g = null
	for d in w.devices:
		if d.kind == "groove":
			g = d
	check(g != null and g.length > 40.0, "groove left on the end of the path")
	# 손으로 놓은 홈을 비스듬히 가로지르면 꺾인다
	var q := make_world()
	var d2 = q.place_device("groove", 0, 9, Vector2(-100, 0), Vector2.RIGHT, 5)
	d2.length = 140.0
	var c := q.add_stone(1, Vector2(-30, 120), 0)
	q.round_no = 2
	var dir := Vector2(0.35, -1).normalized()
	q.launch(c.id, dir, 0.5)
	q.run_until_settled()
	check(count_events(q, "part", "track") == 1, "a stone crossing the groove is bent")
	check(q.devices.is_empty(), "groove used up")



func test_trex_leg_reduces_recoil() -> void:
	var p := make_world()
	var a := p.add_stone(0, Vector2(-200, 0), 0)
	p.add_stone(1, Vector2(-100, 15), 0)
	shoot(p, a.id, Vector2.RIGHT, 0.8)
	var w := make_world()
	var a2 := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 15), 0)
	a2.parts["prop"] = "trex_leg"
	shoot(w, a2.id, Vector2.RIGHT, 0.8)
	check(count_events(w, "part", "trex_leg") == 1, "leg fired")
	var st := Vector2(-200, 0)
	check(a2.pos.distance_to(st) < a.pos.distance_to(st) - 3.0, "slides less after the hit: %s vs %s" % [a2.pos, a.pos])



func test_crab_hops_sideways() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["prop"] = "crab"
	a.prop_side = -1
	shoot(w, a.id, Vector2.RIGHT, 0.5)
	check(a.pos.y < -60.0, "hopped to the left (−y): %.0f" % a.pos.y)


func test_clockwork_boost() -> void:
	var p := make_world()
	var a := p.add_stone(0, Vector2(-250, 0), 0)
	shoot(p, a.id, Vector2.RIGHT, 0.4)
	var w := make_world()
	var b := w.add_stone(0, Vector2(-250, 0), 0)
	b.parts["prop"] = "clockwork"
	shoot(w, b.id, Vector2.RIGHT, 0.4)
	check(count_events(w, "part", "clockwork") == 1, "clockwork kicked in")
	check(b.pos.x > a.pos.x + 80.0, "weak shot goes further after the boost")
	var q := make_world()
	var c := q.add_stone(0, Vector2(-250, 0), 0)
	c.parts["prop"] = "clockwork"
	shoot(q, c.id, Vector2.RIGHT, 0.8)
	check(count_events(q, "part", "clockwork") == 0, "strong shot: no clockwork")


func test_brake_stops() -> void:
	var p := make_world()
	var a := p.add_stone(0, Vector2(-250, 0), 0)
	shoot(p, a.id, Vector2.RIGHT, 0.6)
	var w := make_world()
	var b := w.add_stone(0, Vector2(-250, 0), 0)
	b.parts["prop"] = "brake"
	shoot(w, b.id, Vector2.RIGHT, 0.6)
	check(count_events(w, "part", "brake") == 1, "brake fired")
	check(b.pos.x < a.pos.x - 15.0, "stops short of a free slide")


func _trex(s) -> void:
	s.parts = {"weapon": "trex_head", "aux": "trex_arm", "prop": "trex_leg"}


func test_mecha_throw() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-110, 38), 0)
	_trex(a)
	check(PartsData.set_complete(a.parts), "set complete")
	shoot(w, a.id, Vector2.RIGHT, 0.55)
	check(count_events(w, "part", "mecha") == 1, "bite-and-throw fired once")
	check(count_events(w, "part", "trex_head") == 0 and count_events(w, "part", "trex_arm") == 0, "consumes head and arm")
	check(not b.alive or b.pos.x > 150.0, "thrown along the aim line: %.0f" % b.pos.x)
	check(a.pos.x < -80.0, "the T-rex holds its ground")


func test_mecha_frontal_is_plain_bite() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-110, 0), 0)
	_trex(a)
	shoot(w, a.id, Vector2.RIGHT, 0.55)
	check(count_events(w, "part", "mecha") == 0, "frontal hit: no throw")
	check(count_events(w, "part", "trex_head") == 1, "frontal hit: plain bite")


func test_trex_draft_rule() -> void:
	var m := Match.new()
	m.setup(4, [], 11, false)
	var s = m.world.alive_stones_of(0)[0]
	s.parts["aux"] = "trex_arm"
	for i in 30:
		var offer := m.roll_offer(0)
		var trex := 0
		for id in offer:
			if PartsData.set_of(id) == "trex":
				trex += 1
				check(id != "trex_arm", "offers a missing T-rex part, not one already on")
		check(trex == 1 and offer.size() == 3, "exactly one T-rex slot, two normal parts")
	check(m.roll_offer(1).size() == 3, "players without T-rex parts get any three")
	# 자리 고르기: 게걸음은 추진 좌우, 딱지 방패는 보조 좌우
	m.round_no = 2
	m.phase = "draft"
	m.draft_queue = [0]
	m.offers[0] = ["crab", "pea", "rocket"]
	m.equip(0, "crab", s.id, -1)
	check(s.prop_side == -1 and s.magnet_side == 1, "crab side stored as prop_side")


func test_set_label() -> void:
	var parts := {"weapon": "trex_head", "aux": "trex_arm", "prop": ""}
	check(PartsData.set_label(parts) == "메카 티라노 2/3 · 다리 필요", "label: " + PartsData.set_label(parts))
	parts["prop"] = "trex_leg"
	check(PartsData.set_label(parts).begins_with("메카 티라노 완성"), "complete label")
	check(PartsData.set_label({"weapon": "", "aux": "", "prop": ""}) == "", "no label without T-rex parts")
	var moon := {"weapon": "moon_staff", "aux": "star_cloak", "prop": ""}
	check(PartsData.set_label(moon) == "달그림자 마도사 2/3 · 장화 필요", "moon label: " + PartsData.set_label(moon))
	check(not PartsData.set_complete(moon) and PartsData.set_progress(moon)["set"] == "moon", "progress follows the stone's own set")
	moon["prop"] = "moon_boots"
	check(PartsData.set_complete(moon) and not PartsData.set_complete(moon, "trex"), "complete moon set is not a T-rex")


# ── 확장 부품 ────────────────────────────────────────────

func test_mecha_blocked_is_normal_hit() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-110, 38), 0)
	w.add_stone(2, Vector2(-110 + 6, 0), 0)  # 앞자리를 막는 알
	_trex(a)
	shoot(w, a.id, Vector2.RIGHT, 0.55)
	check(count_events(w, "part", "mecha") == 0, "blocked pull: no bite-and-throw")


func test_scissors_seal_next_launch() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["weapon"] = "shadow_scissors"
	b.parts["weapon"] = "pea"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	check(b.status.get("sealed", "") == "weapon", "weapon slot sealed")
	w.events.clear()
	w.launch(b.id, Vector2.UP, 0.1)
	check(w.projs.is_empty(), "sealed pea does not fire")
	w.run_until_settled()
	w.end_shot()
	check(b.parts["weapon"] == "pea" and not b.status.has("sealed"), "seal lasts one launch")


func test_bookmark_reserve() -> void:
	var m := Match.new()
	m.setup(4, [], 21, false)
	m.phase = "draft"
	m.draft_queue = [0]
	m.offers[0] = ["bookmark", "rocket", "pea"]
	var s = m.world.alive_stones_of(0)[0]
	check(m.equip(0, "bookmark", s.id, 1, "pea"), "equip bookmark")
	check(m.players[0].reserved == "pea", "pea reserved")
	var offer := m.roll_offer(0)
	check(offer.has("pea") and offer.size() == 3, "reserved part offered next time")
	check(m.players[0].reserved == "", "reservation used up")


func test_edge_sewer_net() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(150, 0), 0)
	var b := w.add_stone(1, Vector2(250, 0), 0)
	a.parts["prop"] = "edge_sewer"
	shoot(w, a.id, Vector2.RIGHT, 1.0)
	check(count_events(w, "part", "edge_sewer") >= 2, "net placed and caught a stone")
	check(b.alive, "target bounced back in by the net")


func test_drift_tire() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(0, 250), 0)
	a.parts["prop"] = "drift_tire"
	shoot(w, a.id, Vector2(1, 0.25).normalized(), 1.0)
	check(count_events(w, "part", "drift_tire") == 1, "drifted along the edge")
	check(count_events(w, "manga") >= 1, "anime part triggers the manga effect")
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(0, 0), 0)
	b.parts["prop"] = "drift_tire"
	shoot(w2, b.id, Vector2.RIGHT, 1.0)
	check(not b.alive, "head-on: still falls")


func test_flash_step() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-80, 0), 0)
	a.parts["prop"] = "flash_step"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	check(count_events(w, "part", "flash_step") == 1, "teleported")
	check(a.pos.x > b.pos.x, "ended up beyond the first stone")
	check(b.pos.distance_to(Vector2(-80, 0)) < 1.0, "first stone untouched")


func test_log_sub() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-80, 0), 0)
	b.parts["aux"] = "log_sub"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	check(count_events(w, "part", "log_sub") == 1, "log substitution")
	check(absf(b.pos.y) > 30.0, "defender slipped sideways")
	check(a.pos.x < -120.0, "attacker bounced off the log")


func test_trap_card() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	a.parts["aux"] = "trap_card"
	shoot(w, a.id, Vector2.RIGHT, 0.3)
	var card = null
	for d in w.devices:
		if d.kind == "card":
			card = d
	check(card != null, "card placed")
	if card == null:
		return
	a.pos += Vector2(0, -150)
	var c := w.add_stone(1, card.pos + Vector2(150, 0), 0)
	shoot(w, c.id, Vector2.LEFT, 0.6)
	check(count_events(w, "part", "trap_card") >= 1 and c.pos.x > card.pos.x, "stepping stone bounced back")


func test_shadow_scale() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-100, 0), 0)
	var u := w.add_stone(2, Vector2(-100, 90), 0)
	a.parts["aux"] = "shadow_scale"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	check(u.pos.distance_to(Vector2(-100, 90)) > 15.0, "share of the hit went to the neighbour")


func test_night_charm_curse() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["weapon"] = "night_charm"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	check(b.status.get("cursed", -1) == 0, "cursed")
	var behind := w.add_stone(2, b.pos + Vector2(-80, 0), 0)
	var before := behind.pos
	shoot(w, b.id, Vector2.RIGHT, 0.2)
	check(behind.pos.distance_to(before) > 20.0, "shadow pushed the stone behind on the next launch")
	check(not b.status.has("cursed"), "curse used up")


func test_anchor_returns() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["prop"] = "anchor"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	check(a.pos.distance_to(Vector2(-200, 0)) < 1.0, "returned to the start")


func _moon(s) -> void:
	s.parts = {"weapon": "moon_staff", "aux": "star_cloak", "prop": "moon_boots"}


func test_moon_orbit_magic() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-60, 0), 0)
	_moon(a)
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	check(count_events(w, "mark") >= 1, "orb marked the target")
	check(count_events(w, "part", "moon_set") == 1, "orbit magic fired")
	check(absf(b.pos.y) > 40.0, "target flung along the tangent")


func _hero(s) -> void:
	s.parts = {"weapon": "hero_band", "aux": "torn_cape", "prop": "awaken_shoes"}


func test_hero_last_cut() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(100, 0), 0)
	var b := w.add_stone(1, Vector2(250, 0), 0)
	_hero(a)
	shoot(w, a.id, Vector2.RIGHT, 0.9)
	check(not b.alive, "target knocked out")
	check(count_events(w, "part", "hero_set") == 1, "last cut fired")
	check(a.alive and a.pos.x < 250.0, "hero stopped and stepped back")


func test_relic_ribbon() -> void:
	var m := Match.new()
	m.setup(2, [], 31, false)
	_finish_draft(m)
	var mine: Array = m.world.alive_stones_of(0)
	mine[0].parts = {"weapon": "pea", "aux": "relic_ribbon", "prop": ""}
	mine[0].alive = false
	m.world.relics.append({"owner": 0, "part": "pea"})
	while m.current_player() != 0 and m.phase != "over":
		m.skip_turn()
	m.skip_turn()
	while m.current_player() != 0 and m.phase != "over":
		if m.phase == "draft":
			m.draft_queue.clear()
			m.phase = "aim"
			m._mark_relic_turn()
			continue
		m.skip_turn()
	check(m.players[0].relic == "pea", "relic kept for my next turn")
	var targets := m.relic_targets(0)
	check(not targets.is_empty(), "stones with an empty weapon slot")
	check(m.equip_relic(0, targets[0].id) and targets[0].parts["weapon"] == "pea", "relic equipped")


func test_set_recommend_priority() -> void:
	var m := Match.new()
	m.setup(4, [], 41, false)
	var mine: Array = m.world.alive_stones_of(0)
	mine[0].parts = {"weapon": "moon_staff", "aux": "", "prop": ""}
	mine[1].parts = {"weapon": "hero_band", "aux": "torn_cape", "prop": ""}
	for i in 20:
		var offer := m.roll_offer(0)
		check(offer.has("awaken_shoes"), "the stone with more set parts wins")
	mine[1].parts = {"weapon": "hero_band", "aux": "", "prop": ""}
	m.players[0].focus = mine[0].id
	for i in 20:
		var o2 := m.roll_offer(0)
		check(o2.has("star_cloak") or o2.has("moon_boots"), "tie: last equipped stone wins")


func test_rubber_fist() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	var b := w.add_stone(1, Vector2(-50, 0), 0)
	a.parts["weapon"] = "rubber_fist"
	shoot(w, a.id, Vector2.RIGHT, 0.05)
	check(b.pos.x > -50.0 + 40.0, "fist pushed the first stone")


func test_ink_split() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	w.add_stone(1, Vector2(0, 0), 0)
	var side := w.add_stone(2, Vector2(0, 110), 0)
	a.parts["weapon"] = "ink_drop"
	shoot(w, a.id, Vector2.RIGHT, 0.05)
	check(side.pos.y > 130.0, "split ink pushed the side stone")


func test_echo_bell() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	var c := w.add_stone(2, Vector2(-120, 90), 0)
	a.parts["weapon"] = "echo_bell"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	check(count_events(w, "ripple") == 1 and c.pos.y > 100.0, "delayed shockwave pushed outward")


func test_stopwatch_freeze() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	var c := w.add_stone(2, Vector2(-100, 120), 0)
	a.parts["aux"] = "stopwatch"
	w.launch(a.id, Vector2.RIGHT, 0.5)
	c.vel = Vector2(0, -300)
	var frozen := false
	for i in 80:
		w.step()
		if w.shot.ex.get("frozen", {}).has(c.id):
			frozen = true
			break
	check(frozen, "moving stone nearby frozen")
	w.run_until_settled()
	check(c.pos.y < 100.0, "resumed its motion afterwards")


func test_glass_wings() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(0, 250), 0)
	a.parts["prop"] = "glass_wings"
	shoot(w, a.id, Vector2(1, 0.2).normalized(), 1.0)
	check(count_events(w, "part", "glass_wings") >= 1 and a.alive, "shallow: reflected inside")
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(0, 0), 0)
	b.parts["prop"] = "glass_wings"
	shoot(w2, b.id, Vector2.RIGHT, 1.0)
	check(not b.alive, "head-on: wings break")


func test_side_scroll() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-250, 0), 0)
	a.parts["prop"] = "side_scroll"
	a.prop_side = 1
	shoot(w, a.id, Vector2.RIGHT, 0.7)
	check(count_events(w, "part", "side_scroll") == 1 and a.pos.y > 40.0, "turned 90° to the right (+y)")


func test_cloud_mailbox() -> void:
	var m := Match.new()
	m.setup(2, [], 51, false)
	_finish_draft(m)
	var w = m.world
	var s = w.alive_stones_of(m.current_player())[0]
	s.parts["prop"] = "cloud_mailbox"
	m.shoot(s.id, Vector2(0, -1) if s.owner == 0 else Vector2(0, 1), 0.3)
	w.run_until_settled()
	m.finish_shot()
	var cloud = w.cloud_of(s.id)
	check(cloud != null, "cloud left where it stopped")
	if cloud == null:
		return
	s.pos += Vector2(90, 0)
	check(w.move_to_cloud(s.id) and s.pos == cloud.pos, "can start again from the cloud")


func test_ice_and_wall() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["weapon"] = "ice_fan"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	var ice := false
	for d in w.devices:
		ice = ice or d.kind == "ice"
	check(ice, "ice fan placed for the next shot")
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(-200, 0), 0)
	w2.add_stone(1, Vector2(-120, 0), 0)
	b.parts["weapon"] = "alchemy_glove"
	shoot(w2, b.id, Vector2.RIGHT, 0.9)
	check(count_events(w2, "part", "alchemy_glove") == 1, "stone wall raised")
	var walls := 0
	for d in w2.devices:
		walls += 1 if d.kind == "wall" else 0
	check(walls == 0, "wall gone after the shot")


func test_star_cloak_circle() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["aux"] = "star_cloak"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	var circ = null
	for d in w.devices:
		if d.kind == "circle":
			circ = d
	check(circ != null, "magic circle left")
	if circ == null:
		return
	var c := w.add_stone(2, circ.pos + Vector2(0, 150), 0)
	shoot(w, c.id, Vector2.UP, 0.5)
	check(count_events(w, "magic_circle") >= 1, "a stone stepping in is flung")


func test_moon_well() -> void:
	var w := make_world()
	var d = w.place_device("well", 0, 9, Vector2(0, 0), Vector2.RIGHT, 5)
	var c := w.add_stone(1, Vector2(-150, 0), 0)
	w.launch(c.id, Vector2.RIGHT, 0.6)
	w.run_until_settled()
	check(count_events(w, "part", "moon_well") >= 2, "slowed on entry, pushed on exit")


func test_mushroom_and_wind() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["aux"] = "mushroom"
	shoot(w, a.id, Vector2.RIGHT, 0.4)
	var n := 0
	for d in w.devices:
		n += 1 if d.kind == "mushroom" else 0
	check(n == 2, "two mushrooms planted")
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(-200, 0), 0)
	b.parts["aux"] = "wind_knot"
	shoot(w2, b.id, Vector2.RIGHT, 0.4)
	var wind := false
	for d in w2.devices:
		wind = wind or d.kind == "wind"
	check(wind, "wind left where it stopped")


func test_second_step() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	a.parts["prop"] = "second_step"
	shoot(w, a.id, Vector2.RIGHT, 0.6)
	var p := make_world()
	var b := p.add_stone(0, Vector2(-200, 0), 0)
	shoot(p, b.id, Vector2.RIGHT, 0.6)
	check(count_events(w, "part", "second_step") == 1 and a.pos.x < b.pos.x - 40.0, "retraced part of the path")


func test_rebound_and_string() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	w.add_stone(1, Vector2(-100, 0), 0)
	w.add_stone(2, Vector2(0, 0), 0)
	a.parts["prop"] = "rebound_shoes"
	shoot(w, a.id, Vector2.RIGHT, 0.7)
	check(count_events(w, "part", "rebound_shoes") == 1, "rebound dash")
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(-200, 0), 0)
	w2.add_stone(1, Vector2(-100, 0), 0)
	w2.add_stone(2, Vector2(-100, 100), 0)
	b.parts["weapon"] = "string_doll"
	shoot(w2, b.id, Vector2.RIGHT, 0.9)
	check(count_events(w2, "thread") >= 1, "string tied")


func test_at_field_and_beam() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-100, 0), 0)
	a.parts["aux"] = "at_field"
	shoot(w, a.id, Vector2.RIGHT, 0.5)
	check(count_events(w, "hexbreak") == 1, "barrier hit and broke")
	var w2 := make_world()
	var c := w2.add_stone(0, Vector2(-250, 0), 0)
	var t := w2.add_stone(1, Vector2(150, 0), 0)
	c.parts["weapon"] = "charge_palm"
	w2.launch(c.id, Vector2.RIGHT, 0.2, {"charged": true})
	w2.run_until_settled()
	check(count_events(w2, "beam") == 1 and t.pos.x > 180.0, "charged palm fires a beam")
	var w3 := make_world()
	var d := w3.add_stone(0, Vector2(-250, 0), 0)
	d.parts["weapon"] = "charge_palm"
	shoot(w3, d.id, Vector2.RIGHT, 0.2)
	check(count_events(w3, "beam") == 0, "uncharged: no beam")


func test_hero_band_and_shoes() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(-200, 0), 0)
	var b := w.add_stone(1, Vector2(-80, 0), 0)
	a.parts["weapon"] = "hero_band"
	w.launch(a.id, Vector2.RIGHT, 0.3)
	check(b.vel.x > 100.0, "last-stone weak shot: shockwave first")
	w.run_until_settled()
	var w2 := make_world()
	var c := w2.add_stone(0, Vector2(-200, 0), 0)
	w2.add_stone(0, Vector2(-200, 200), 0)
	var e := w2.add_stone(1, Vector2(-80, 0), 0)
	c.parts["weapon"] = "hero_band"
	w2.launch(c.id, Vector2.RIGHT, 0.3)
	check(e.vel == Vector2.ZERO, "not my last stone: no shockwave")
	w2.run_until_settled()


func test_all_parts_have_art() -> void:
	var Art = load("res://scripts/stone_art.gd")
	var AD = load("res://scripts/art_data.gd")
	var hand := ["pea", "shotgun", "hook", "claw", "nose", "stamp", "copier", "magnet", "bumper", "flipper", "decal",
		"umbrella", "spring", "carousel", "bubble", "mine", "rocket", "retro", "reel", "chute", "trex_head", "sucker",
		"umbrella_gun", "roller", "trex_arm", "shield", "tambourine", "track", "trex_leg", "crab", "clockwork", "brake"]
	for id in PartsData.ids():
		check(hand.has(id) or AD.SHAPES.has(id), "art for " + id)
	check(PartsData.ids().size() == 66, "66 parts: %d" % PartsData.ids().size())


# ── 오늘의 공방 ──────────────────────────────────────────

func test_workshop_pools() -> void:
	for ws in ["junk", "magic", "toon"]:
		var pool := PartsData.workshop_pool(ws)
		var want: int = 10 + PartsData.WORKSHOPS[ws]["parts"].size()
		check(pool.size() == want, "%s: %d parts" % [ws, want])
		var m := Match.new()
		m.setup(4, [], 7, false, {"workshop": ws})
		check(m.workshop == ws, "workshop set")
		for i in 30:
			for id in m.roll_offer(0):
				check(pool.has(id), "%s offers only its parts: %s" % [ws, id])
	check(PartsData.workshop_pool("all").size() == PartsData.ids().size(), "all = every part")


func test_offer_fits_empty_slots() -> void:
	var m := Match.new()
	m.setup(4, [], 8, false, {"workshop": "junk"})
	var mine: Array = m.world.alive_stones_of(0)
	# 무기·보조는 다 차고 추진만 비어 있는 상황
	for st in mine:
		st.parts = {"weapon": "pea", "aux": "magnet", "prop": ""}
	for i in 40:
		var offer := m.roll_offer(0)
		var fit := 0
		for id in offer:
			if PartsData.slot_of(id) == "prop":
				fit += 1
		check(fit >= 2, "at least two candidates fit an empty slot: %s" % str(offer))


func test_min_power_moves_one_cell() -> void:
	var w := make_world()
	var a := w.add_stone(0, Vector2(0, 0), 0)
	# 1칸만 당긴 샷: p = (1 − 0.65) / (3.2 − 0.65)
	shoot(w, a.id, Vector2.RIGHT, (1.0 - 0.65) / (3.2 - 0.65))
	check(a.pos.x > 44.0 * 3.0, "one-cell pull moves at least three puck widths: %.0f" % a.pos.x)
	var w2 := make_world("circle", 800.0)
	var b := w2.add_stone(0, Vector2(-300, 0), 0)
	shoot(w2, b.id, Vector2.RIGHT, 1.0)
	check(absf(b.pos.x + 300.0 - 455.0) < 20.0, "full pull glides about 10 cells: %.0f" % (b.pos.x + 300.0))


func test_knockout_causes() -> void:
	# 콩알총
	var w := make_world()
	var a := w.add_stone(0, Vector2(-100, 0), 0)
	w.add_stone(1, Vector2(300, 0), 0)
	a.parts["weapon"] = "pea"
	shoot(w, a.id, Vector2.RIGHT, 0.05)
	check(w.knockouts.size() == 1 and w.knockouts[0]["cause"].get("part", "") == "pea", "bullet knockout: %s" % str(w.knockouts))
	# 몸통 충돌
	var w2 := make_world()
	var b := w2.add_stone(0, Vector2(0, 0), 0)
	w2.add_stone(1, Vector2(250, 0), 0)
	shoot(w2, b.id, Vector2.RIGHT, 1.0)
	check(w2.knockouts.size() >= 1 and w2.knockouts[0]["cause"].get("part", "") == "body", "body knockout")
	check(int(w2.knockouts[0]["cause"].get("owner", -1)) == 0, "credited to the shooter")
	# 연쇄
	var w3 := make_world()
	var c := w3.add_stone(0, Vector2(100, 0), 0)
	w3.add_stone(1, Vector2(170, 0), 0)
	w3.add_stone(2, Vector2(260, 0), 0)
	shoot(w3, c.id, Vector2.RIGHT, 1.0)
	var chain := false
	for k in w3.knockouts:
		if int(k["owner"]) == 2 and k["cause"].get("chain", false):
			chain = true
	check(chain, "chain knockout marked: %s" % str(w3.knockouts))


func test_derby_mode() -> void:
	var m := Match.new()
	m.setup(4, [], 12, false, {"mode": "derby"})
	check(m.max_rounds == 8, "derby: fixed rounds")
	_finish_draft(m)
	var shooter: int = m.current_player()
	var victim_owner := (shooter + 1) % 4
	var vic = m.world.alive_stones_of(victim_owner)[0]
	var me = m.world.alive_stones_of(shooter)[0]
	vic.parts["weapon"] = "pea"
	# 내 퍽 바로 앞에 상대 퍽을 놓고 판 밖으로 밀어낸다
	var dir: Vector2 = (-me.pos).normalized()
	vic.pos = me.pos + dir * 60.0
	var target_dir := dir
	m.shoot(me.id, target_dir, 1.0)
	m.world.run_until_settled()
	var fell: bool = not vic.alive
	m.finish_shot()
	if fell:
		check(m.scores[shooter] >= 1, "point for the knockout")
	check(not m.players[victim_owner].out, "nobody is eliminated in derby")
	# 바퀴가 바뀌면 떨어진 퍽이 부품을 단 채 돌아온다
	for p in m.players:
		for st in m.world.alive_stones_of(p.id):
			pass
	vic.alive = false
	var guard := 0
	var r0: int = m.round_no
	while m.round_no == r0 and guard < 50:
		guard += 1
		_finish_draft(m)
		m.skip_turn()
	check(vic.alive and vic.parts["weapon"] == "pea", "respawned with its parts")
	while m.phase != "over" and guard < 400:
		guard += 1
		_finish_draft(m)
		m.skip_turn()
	check(m.phase == "over" and m.end_reason == "score", "ends by score after the fixed rounds")
