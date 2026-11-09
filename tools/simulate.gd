extends SceneTree
## CPU끼리 여러 판을 돌려 경기 길이, 탈락 속도, 부품 작동 횟수를 본다.
##   godot --headless --path . -s res://tools/simulate.gd -- <인원> <판 수> [verbose]

const Match = preload("res://scripts/sim/match.gd")
const Bot = preload("res://scripts/sim/bot.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 4
	var games := int(args[1]) if args.size() > 1 else 20
	var verbose := args.size() > 2
	var rounds_sum := 0
	var shots_sum := 0
	var limit_count := 0
	var draw_count := 0
	var first_out_round := 0
	var shots_with_ko := 0
	var self_ko := 0
	var part_fires := {}
	var t0 := Time.get_ticks_msec()
	for g in games:
		var m := Match.new()
		var flags := []
		for i in n:
			flags.append(true)
		m.setup(n, flags, 1000 + g, false)
		var rng := RandomNumberGenerator.new()
		rng.seed = g
		var guard := 0
		var first_out := 0
		while m.phase != "over" and guard < 500:
			guard += 1
			if m.phase == "draft":
				var pid := m.current_drafter()
				var c := Bot.choose_draft(m, pid, rng)
				m.equip(pid, c["part"], c["stone"], c["side"])
				continue
			var bot := Bot.new()
			var shooter := m.current_player()
			bot.begin(m, shooter, g * 1000 + guard)
			while not bot.think_step(8):
				pass
			var r := bot.result()
			m.shoot(r["stone"], r["dir"], r["power"])
			m.world.record_events = true
			m.world.run_until_settled()
			for e in m.world.events:
				if e["t"] == "part":
					part_fires[e["part"]] = part_fires.get(e["part"], 0) + 1
			m.world.events.clear()
			var kos: Array = m.world.knockouts.duplicate()
			if not kos.is_empty():
				shots_with_ko += 1
			for k in kos:
				if k["owner"] == shooter:
					self_ko += 1
			if verbose:
				var left := []
				for p in m.players:
					left.append(m.stones_left(p.id))
				print("R%d P%d power=%.2f score=%.0f ko=%d left=%s" % [m.round_no, shooter, r["power"], bot.best_score, kos.size(), str(left)])
			m.finish_shot()
			if first_out == 0 and not m.out_order.is_empty():
				first_out = m.round_no
		rounds_sum += m.round_no
		shots_sum += m.shots
		first_out_round += first_out
		if m.end_reason == "limit":
			limit_count += 1
		if m.end_reason == "draw":
			draw_count += 1
	print("%d인 %d판 · 평균 %.1f바퀴 %.1f발 · 첫 탈락 %.1f바퀴 · 바퀴 제한 종료 %d%% · 무승부 %d · 탈락 나온 샷 %.0f%% · 자멸 %d · %.1fs" % [
		n, games, float(rounds_sum) / games, float(shots_sum) / games, float(first_out_round) / games,
		100 * limit_count / games, draw_count, 100.0 * shots_with_ko / maxf(1, shots_sum), self_ko,
		(Time.get_ticks_msec() - t0) / 1000.0])
	var keys := part_fires.keys()
	keys.sort_custom(func(a, b): return part_fires[a] > part_fires[b])
	var s := ""
	for k in keys:
		s += "%s:%d " % [k, part_fires[k]]
	print("부품 작동: ", s)
	quit(0)
