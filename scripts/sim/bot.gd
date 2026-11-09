extends RefCounted
## CPU 플레이어. 후보 샷을 세계 복제본에서 실제로 돌려 보고 가장 좋은 것을 고른다.
## 한 번에 한 후보씩 평가(think_step)하므로 화면이 멈추지 않는다.

const PartsData = preload("res://scripts/sim/parts_data.gd")

const POWERS := [0.45, 0.7, 0.95]
const ANGLES_DEG := [-5.0, 0.0, 5.0]
const MAX_TARGETS := 4

var match_ref
var pid := -1
var candidates: Array = []
var index := 0
var best: Dictionary = {}
var best_score := -INF
var rng := RandomNumberGenerator.new()


func begin(m, player_id: int, seed_value: int) -> void:
	match_ref = m
	pid = player_id
	rng.seed = seed_value
	candidates.clear()
	index = 0
	best = {}
	best_score = -INF
	var w = m.world
	var mine: Array = w.alive_stones_of(pid)
	for s in mine:
		var targets: Array = []
		for t in w.stones:
			if t.alive and t.owner != pid:
				targets.append(t)
		targets.sort_custom(func(a, b): return a.pos.distance_to(s.pos) < b.pos.distance_to(s.pos))
		targets = targets.slice(0, MAX_TARGETS)
		for t in targets:
			var base: Vector2 = (t.pos - s.pos).normalized()
			for ang in ANGLES_DEG:
				for pw in POWERS:
					candidates.append({"stone": s.id, "dir": base.rotated(deg_to_rad(ang)), "power": pw})
		# 자석팔은 상대 옆을 스치는 샷이 핵심이라 옆으로 비껴 쏘는 후보를 더한다.
		if s.parts["aux"] == "magnet" and not targets.is_empty():
			var base2: Vector2 = (targets[0].pos - s.pos).normalized()
			for ang2 in [-35.0, 35.0]:
				candidates.append({"stone": s.id, "dir": base2.rotated(deg_to_rad(ang2)), "power": 0.6})
	if candidates.is_empty() and not mine.is_empty():
		candidates.append({"stone": mine[0].id, "dir": (-mine[0].pos).normalized(), "power": 0.2})


func done() -> bool:
	return index >= candidates.size()


## 후보 몇 개를 평가한다. 끝났으면 true.
func think_step(count := 2) -> bool:
	for _i in count:
		if done():
			return true
		var c: Dictionary = candidates[index]
		index += 1
		var sc := evaluate(c)
		if sc > best_score:
			best_score = sc
			best = c
	return done()


func evaluate(c: Dictionary) -> float:
	var m = match_ref
	var w = m.world.clone()
	var before := {}
	for p in m.players:
		before[p.id] = w.alive_stones_of(p.id).size()
	w.launch(c["stone"], c["dir"], c["power"], {"charged": true})
	w.run_until_settled(8.0)
	w.end_shot()
	var score := 0.0
	for p in m.players:
		if p.out:
			continue
		var after: int = w.alive_stones_of(p.id).size()
		var lost: int = before[p.id] - after
		if p.id == pid:
			score -= lost * 140.0
			if after == 0:
				score -= 1000.0
		else:
			score += lost * 100.0
			if after == 0 and before[p.id] > 0:
				score += 60.0
			# 상대 알을 가장자리로 몰아 둔 것도 약간 쳐준다.
			for s in w.alive_stones_of(p.id):
				score += clampf(80.0 - w.edge_distance(s.pos), 0.0, 80.0) * 0.12
	for s in w.alive_stones_of(pid):
		score += clampf(w.edge_distance(s.pos), 0.0, 120.0) * 0.08
	return score + rng.randf() * 3.0


## 사람처럼 약간 빗나가게: 각도와 힘에 오차를 섞는다. aim_error = 0 이면 계산한 그대로.
var aim_error := 1.0


func result() -> Dictionary:
	if best.is_empty() or aim_error <= 0.0:
		return best
	var r := best.duplicate()
	r["dir"] = (r["dir"] as Vector2).rotated(deg_to_rad(rng.randfn(0.0, 2.2 * aim_error)))
	r["power"] = clampf(r["power"] * (1.0 + rng.randfn(0.0, 0.06 * aim_error)), 0.05, 1.0)
	return r


# ── 개조 선택 ────────────────────────────────────────────

const PRIORITY := {"pea": 8, "shotgun": 7, "retro": 8, "magnet": 7, "rocket": 6, "nose": 6,
	"hook": 6, "claw": 5, "chute": 6, "reel": 5, "bumper": 5, "carousel": 5, "mine": 5,
	"umbrella": 3, "spring": 4, "flipper": 4, "bubble": 4, "copier": 4, "stamp": 3, "decal": 5,
	"trex_head": 6, "trex_arm": 5, "trex_leg": 5, "sucker": 4, "umbrella_gun": 5, "roller": 4,
	"shield": 4, "tambourine": 5, "track": 3, "crab": 5, "clockwork": 4, "brake": 4}


## {part, stone, side}
static func choose_draft(m, player_id: int, rand: RandomNumberGenerator) -> Dictionary:
	var w = m.world
	var mine: Array = w.alive_stones_of(player_id)
	var best_choice := {}
	var best_val := -INF
	for part in m.offers.get(player_id, []):
		var slot := PartsData.slot_of(part)
		for s in mine:
			var val: float = PRIORITY.get(part, 4)
			if s.parts[slot] == "":
				val += 3.0
			else:
				val -= PRIORITY.get(s.parts[slot], 4) * 0.8
			var tmp: Dictionary = s.parts.duplicate()
			tmp[slot] = part
			if PartsData.unmet_need(part, tmp) != "":
				val -= 6.0
			# 세트를 모으는 중이면 같은 알에 이어 붙이는 쪽을 크게 쳐준다.
			if PartsData.set_of(part) != "":
				var have: int = PartsData.set_progress(s.parts, PartsData.set_of(part))["count"]
				val += have * 4.0
			# 이미 부품이 있는 알에 몰아 다는 쪽을 약간 선호 (조합)
			var filled := 0
			for k in tmp:
				if tmp[k] != "":
					filled += 1
			val += filled * 0.6 + w.edge_distance(s.pos) * 0.004 + rand.randf() * 1.5
			if val > best_val:
				best_val = val
				best_choice = {"part": part, "stone": s.id, "side": 1 if rand.randf() < 0.5 else -1}
	return best_choice
