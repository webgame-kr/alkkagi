extends RefCounted
## CPU 플레이어. 후보 샷을 세계 복제본에서 실제로 돌려 보고 가장 좋은 것을 고른다.
## 한 번에 한 후보씩 평가(think_step)하므로 화면이 멈추지 않는다.

const PartsData = preload("res://scripts/sim/parts_data.gd")
const Crown = preload("res://scripts/sim/crown.gd")
const Parcel = preload("res://scripts/sim/parcel.gd")
const World = preload("res://scripts/sim/world.gd")

const POWERS := [0.45, 0.7, 0.95]
const ANGLES_DEG := [-5.0, 0.0, 5.0]
const MAX_TARGETS := 4
const MAX_CANDIDATES := 40    # 웹(느린 환경)에서도 1초 안팎에 끝나도록 후보 수를 제한한다

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
	if not m.bonus_active.is_empty():
		# 정각 덤 차례: 같은 알만
		mine = mine.filter(func(x): return x.id == int(m.bonus_active["stone"]))
	for s in mine:
		var targets: Array = []
		var my_team: int = m.team_of(pid) if m.mode == "parcel" else -1
		for t in w.stones:
			if t.alive and t.owner != pid and (my_team < 0 or m.team_of(t.owner) != my_team):
				targets.append(t)
		# 택배 쟁탈전: 택배 뒤로 돌아가 우리 진영 쪽으로 미는 샷을 먼저 본다
		if my_team >= 0 and w.parcel["state"] == "field":
			var pp: Vector2 = w.parcel["pos"]
			var home_dir := Vector2(-1.0 if my_team == 0 else 1.0, 0.0)
			var push_dir: Vector2 = (home_dir - pp.normalized() * 0.15 * pp.length() / w.size).normalized()
			var contact: Vector2 = pp - push_dir * (w.radius_of(s) + Parcel.R) * 0.95
			for aim_pt in [contact, pp]:
				var adir: Vector2 = (aim_pt - s.pos)
				if adir.length() < 1.0:
					continue
				for ang1 in [-3.0, 0.0, 3.0]:
					for pw1 in [0.45, 0.65, 0.85]:
						candidates.append({"stone": s.id, "dir": adir.normalized().rotated(deg_to_rad(ang1)), "power": pw1, "h": -200.0 + adir.length() * 0.05 + absf(ang1)})
		targets.sort_custom(func(a, b): return a.pos.distance_to(s.pos) < b.pos.distance_to(s.pos))
		targets = targets.slice(0, MAX_TARGETS)
		# 왕관 쟁탈전: 보유 알은 늘 후보에, 바닥 왕관은 직접 주우러 가는 샷을 먼저 본다
		if not w.crown.is_empty():
			var ch = Crown.holder_stone(w)
			if ch != null and ch.owner != pid and not targets.has(ch):
				targets.push_front(ch)
			if w.crown["state"] == "floor" and Crown.is_base(w, s):
				var cdir: Vector2 = (w.crown["pos"] - s.pos)
				var dist := cdir.length()
				for ang0 in [-4.0, 0.0, 4.0]:
					for pw0 in [0.25, 0.4, 0.55]:
						candidates.append({"stone": s.id, "dir": cdir.normalized().rotated(deg_to_rad(ang0)), "power": pw0, "h": -50.0 + dist * 0.05 + absf(ang0)})
		var crown_h = Crown.holder_stone(w) if not w.crown.is_empty() else null
		for t in targets:
			var base: Vector2 = (t.pos - s.pos).normalized()
			var bonus := -150.0 if (crown_h != null and t == crown_h and t.owner != pid) else 0.0
			for ang in ANGLES_DEG:
				for pw in POWERS:
					# 유망도: 가까운 상대일수록, 그 상대가 판 끝에 가까울수록, 정면(0도)일수록 먼저 본다
					var h: float = t.pos.distance_to(s.pos) + w.edge_distance(t.pos) * 1.5 + absf(ang) * 6.0 + absf(pw - 0.7) * 40.0
					candidates.append({"stone": s.id, "dir": base.rotated(deg_to_rad(ang)), "power": pw, "h": h + bonus})
		# 자석팔은 상대 옆을 스치는 샷이 핵심이라 옆으로 비껴 쏘는 후보를 더한다.
		if s.parts["aux"] == "magnet" and not targets.is_empty():
			var base2: Vector2 = (targets[0].pos - s.pos).normalized()
			for ang2 in [-35.0, 35.0]:
				candidates.append({"stone": s.id, "dir": base2.rotated(deg_to_rad(ang2)), "power": 0.6, "h": 0.0})
	candidates.sort_custom(func(a, b): return a["h"] < b["h"])
	if candidates.size() > MAX_CANDIDATES:
		candidates = candidates.slice(0, MAX_CANDIDATES)
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
	w.run_until_settled(5.0)
	w.end_shot()
	if m.workshop == "clock":
		# 태엽 시계탑: 이번 차례가 끝날 때 터질 일(진자 · 시곗바늘 · 표식)까지 보고 고른다
		w.turn_no = m.world.turn_no
		if World.Clock.turn_end(w, pid):
			w.run_until_settled(4.0)
	var score := 0.0
	var crown_mode: bool = not m.world.crown.is_empty() or m.mode == "parcel"
	if not m.world.crown.is_empty():
		score += _crown_value(m, w)
	var my_team: int = m.team_of(pid) if m.mode == "parcel" else -1
	if my_team >= 0:
		score += _parcel_value(m, w, my_team)
	var k_lose := 0.35 if crown_mode else 1.0   # 왕관 쟁탈전은 떨어져도 돌아오므로 덜 무겁게
	for p in m.players:
		if p.out:
			continue
		var after: int = w.alive_stones_of(p.id).size()
		var lost: int = before[p.id] - after
		if p.id == pid or (my_team >= 0 and m.team_of(p.id) == my_team):
			score -= lost * 140.0 * k_lose * (1.0 if p.id == pid else 0.7)
			if after == 0:
				score -= 1000.0
		else:
			score += lost * 100.0 * k_lose
			if after == 0 and before[p.id] > 0 and not crown_mode:
				score += 60.0
			# 상대 알을 가장자리로 몰아 둔 것도 약간 쳐준다.
			for s in w.alive_stones_of(p.id):
				score += clampf(80.0 - w.edge_distance(s.pos), 0.0, 80.0) * 0.12
	for s in w.alive_stones_of(pid):
		score += clampf(w.edge_distance(s.pos), 0.0, 120.0) * 0.08
	return score + rng.randf() * 3.0


## 택배 쟁탈전 판단: 택배가 우리 진영 깊이 있을수록 좋다. 정산이 가까울수록 크게 친다.
## 상대 진영에 있던 택배를 판 밖으로 보내는 것도 정산 직전엔 쓸 만하다.
func _parcel_value(m, w, team: int) -> float:
	var sign := -1.0 if team == 0 else 1.0
	var urgency := 1.0 + 2.0 / maxf(1.0, float(m.turns_to_settle()))
	var before_x: float = (m.world.parcel["pos"] as Vector2).x * sign
	if w.parcel["state"] != "field":
		return (40.0 if before_x < -Parcel.NEUTRAL_HALF else -80.0) * urgency
	var x: float = (w.parcel["pos"] as Vector2).x * sign
	var v := clampf(x / Parcel.CELL, -6.0, 6.0) * 30.0
	if x > Parcel.NEUTRAL_HALF:
		v += 60.0
	elif x < -Parcel.NEUTRAL_HALF:
		v -= 60.0
	# 가장자리에 붙은 택배는 떨어지기 쉽다
	v -= clampf(1.5 * Parcel.CELL - w.edge_distance(w.parcel["pos"]), 0.0, 66.0) * 0.8
	return v * urgency


## 왕관 쟁탈전 판단: 바닥 왕관은 줍고, 상대 왕관은 몸통으로 빼앗거나 (승리 직전이면) 떨어뜨리고, 내 왕관은 지킨다.
func _crown_value(m, w) -> float:
	var before_h = Crown.holder_stone(m.world)
	var after_h = Crown.holder_stone(w)
	var v := 0.0
	if after_h != null and after_h.owner == pid:
		v += 320.0 if (before_h == null or before_h.owner != pid) else 140.0
		v += clampf(w.edge_distance(after_h.pos), 0.0, 160.0) * 0.6   # 가장자리에서 멀리
	elif before_h != null and before_h.owner == pid:
		v -= 260.0
	if before_h != null and before_h.owner != pid and (after_h == null or after_h.owner != before_h.owner):
		v += 150.0 + (220.0 if int(m.scores[before_h.owner]) >= int(m.crown_goal) - 1 else 0.0)
	return v


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


## CPU 성향 (BAL-02): 자리마다 다르게 해서 모두 같은 부품을 고르지 않게.
##   attack 공격(무기), survive 생존(보조·추진, 버티는 부품), set 세트 모으기, gimmick 공방 전용·특이한 부품
const STYLES := ["attack", "survive", "set", "gimmick"]
const SURVIVE_PARTS := ["brake", "anchor", "retro", "at_field", "torn_cape", "rebound_shoes", "chute", "shield", "bumper", "log_sub", "weight"]


static func style_of(player_id: int) -> String:
	return STYLES[(player_id * 3 + 1) % STYLES.size()]


static func _style_bonus(style: String, part: String) -> float:
	var slot := PartsData.slot_of(part)
	match style:
		"attack":
			return 2.5 if slot == "weapon" else 0.0
		"survive":
			return 3.0 if SURVIVE_PARTS.has(part) else (1.0 if slot != "weapon" else 0.0)
		"set":
			return 2.0 if PartsData.set_of(part) != "" else 0.0
		"gimmick":
			return 2.5 if not PartsData.COMMON_PARTS.has(part) else -1.5
	return 0.0


## {part, stone, side}
static func choose_draft(m, player_id: int, rand: RandomNumberGenerator) -> Dictionary:
	var w = m.world
	var mine: Array = w.alive_stones_of(player_id)
	var style := style_of(player_id)
	# 판 위에 이미 많은 부품은 덜 고른다 (모두 역추진 로켓을 다는 일 막기)
	var on_board := {}
	for st in w.stones:
		if st.alive:
			for sl in st.parts:
				var pp: String = st.parts[sl]
				if pp != "":
					on_board[pp] = int(on_board.get(pp, 0)) + 1
	var best_choice := {}
	var best_val := -INF
	for part in m.offers.get(player_id, []):
		var slot := PartsData.slot_of(part)
		if PartsData.is_up(part):
			# 강화 카드: 그 부품을 단 알 중 가장자리에서 먼 알
			for s0 in mine:
				if s0.parts[slot] == PartsData.base_of(part) and not s0.ups.get(slot, false):
					var v0: float = PRIORITY.get(PartsData.base_of(part), 4) + 2.5 + rand.randf() * 1.5
					if v0 > best_val:
						best_val = v0
						best_choice = {"part": part, "stone": s0.id, "side": 1}
			continue
		var flavor: float = _style_bonus(style, part) - 1.2 * float(on_board.get(part, 0))
		for s in mine:
			var val: float = PRIORITY.get(part, 4) + flavor
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
				val += have * (5.5 if style == "set" else 4.0)
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


## 시간이 다 됐을 때: 지금까지 본 것 중 가장 좋은 후보로 끝낸다.
func finish_now() -> void:
	if best.is_empty() and index < candidates.size():
		think_step(1)
	index = candidates.size()
