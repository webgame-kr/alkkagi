extends SceneTree
## 왕관 쟁탈전 CPU 판을 여러 번 돌려 경기 길이와 점수 구성을 본다.
##   godot --headless --path . -s res://tools/sim_crown.gd -- <인원> <판 수> [crown|parcel] [정산 간격]

const Match = preload("res://scripts/sim/match.gd")
const Bot = preload("res://scripts/sim/bot.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 4
	var games := int(args[1]) if args.size() > 1 else 10
	var mode: String = args[2] if args.size() > 2 else "crown"
	var every := int(args[3]) if args.size() > 3 else 2
	var settles := 0
	var zero := 0
	var rounds := 0
	var shots := 0
	var gain := 0
	var defend := 0
	var steal := 0
	var first_taker_won := 0
	for g in games:
		var m := Match.new()
		var flags := []
		for i in n:
			flags.append(true)
		m.setup(n, flags, 500 + g, false, {"mode": mode, "parcel_every": every, "workshop": ["junk", "magic", "toon", "lab"][g % 4]})
		var rng := RandomNumberGenerator.new()
		rng.seed = g
		var first_taker := -1
		var guard := 0
		while m.phase != "over" and guard < 3000:
			guard += 1
			if m.phase == "draft":
				var pid := m.current_drafter()
				var c := Bot.choose_draft(m, pid, rng)
				m.equip(pid, c.get("part", ""), c.get("stone", -1), c.get("side", 1))
				continue
			var bot := Bot.new()
			bot.begin(m, m.current_player(), rng.randi())
			while not bot.think_step(4):
				pass
			var r: Dictionary = bot.result()
			if r.is_empty():
				m.skip_turn()
				continue
			m.shoot(r["stone"], r["dir"], r["power"], {"charged": true})
			m.world.run_until_settled(14.0)
			if mode == "crown" and first_taker < 0 and m.world.crown["state"] == "held":
				first_taker = m.world.get_stone(int(m.world.crown["holder"])).owner
			m.finish_shot()
			m.crown_events.clear()
			m.parcel_events.clear()
		rounds += m.round_no
		settles += int(m.parcel_stats["settles"])
		zero += int(m.parcel_stats["zero"])
		shots += m.shots
		for cs in m.crown_stats:
			gain += cs["gain"]
			defend += cs["defend"]
			steal += cs["steal"]
		if m.winners.has(first_taker):
			first_taker_won += 1
		print("game %d: rounds %d shots %d winner %s scores %s teams %s" % [g, m.round_no, m.shots, str(m.winners), str(m.scores), str(m.team_scores)])
	if mode == "parcel":
		print("PARCEL n=%d every %d: rounds %.1f shots %.1f settles %.1f zero %.1f" % [n, every, float(rounds) / games, float(shots) / games, float(settles) / games, float(zero) / games])
	print("AVG n=%d rounds %.1f shots %.1f | gain %.1f defend %.1f steal %.1f | first taker won %d/%d" % [n, float(rounds) / games, float(shots) / games, float(gain) / games, float(defend) / games, float(steal) / games, first_taker_won, games])
	quit()
