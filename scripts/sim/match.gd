extends RefCounted
## 경기 관리: 차례, 바퀴, 탈락자, 부품 선택. 물리는 world.gd 에 맡긴다.

const World = preload("res://scripts/sim/world.gd")
const PartsData = preload("res://scripts/sim/parts_data.gd")

const COLORS := [Color("E0533D"), Color("3D6FD1"), Color("E9B935"), Color("38A672"),
	Color("8A68D1"), Color("E5823A"), Color("52B6CC"), Color("D45C99")]
const NAMES := ["빨강", "파랑", "노랑", "초록", "보라", "주황", "하늘", "분홍"]
## 판 크기는 퍽 지름(1칸)으로 잡는다. 2인 한 변 16칸, 3~4인 지름 18칸, 5~8인 지름 24칸.
const CELL := World.STONE_R * 2.0
const OFFER_COUNT := 3
const AIM_LIMIT := 8.0

var n := 4
var players: Array = []       # {id, name, color, cpu, out, out_round}
var world: World
var round_no := 1
var max_rounds := 0           # 0 = 바퀴 제한 없음: 한 사람만 남을 때까지
var draft_rounds: Array = []  # 비어 있으면 매 바퀴 개조
var first_draft_round := 2    # 1바퀴는 맨 알로 두고, 2바퀴부터 개조한다 (모든 모드)
var aim_limit := 0.0          # 0 = 제한 없음
var start_seat := 0
var order: Array = []         # 이번 바퀴의 차례 (플레이어 id)
var turn_pos := 0
var phase := "aim"            # draft | aim | moving | over
var draft_queue: Array = []
var offers := {}              # pid -> [part id ×3]
var winners: Array = []
var end_reason := ""          # last | limit | draw
var out_order: Array = []     # 탈락한 순서 (플레이어 id)
var shots := 0
var rng := RandomNumberGenerator.new()
var workshop := "junk"        # 오늘의 공방 (parts_data WORKSHOPS)
var match_parts: Array = []
var gimmick_rng: RandomNumberGenerator   # 이번 판에 나오는 부품 (공용 4 + 전용 10)
var mode := "survival"        # survival(최후 생존전) | derby(개조 더비)
var scores: Array = []        # 개조 더비: 상대 알을 떨어뜨린 점수
var homes := {}               # 개조 더비: 알 id → 시작 자리 (떨어진 알이 돌아올 곳)
const DERBY_ROUNDS_SMALL := 8 # 2~4인
const DERBY_ROUNDS_BIG := 6   # 5~8인


func setup(n_players: int, cpu_flags: Array, seed_value: int, timed: bool, opts := {}) -> void:
	n = clampi(n_players, 2, 8)
	workshop = str(opts.get("workshop", "junk"))
	mode = str(opts.get("mode", "survival"))
	scores = []
	for i in n:
		scores.append(0)
	rng.seed = seed_value
	# 이번 판의 부품은 따로 뽑는다 (본 난수 순서를 흔들지 않게)
	var prng := RandomNumberGenerator.new()
	prng.seed = seed_value * 31 + 7
	match_parts = PartsData.match_pool(workshop, prng)
	gimmick_rng = prng
	players.clear()
	for i in n:
		players.append({"id": i, "name": NAMES[i], "color": COLORS[i],
			"cpu": bool(cpu_flags[i]) if i < cpu_flags.size() else false, "out": false, "out_round": 0,
			"reserved": "", "focus": -1, "relic": "", "relic_turn": false})
	world = World.new()
	if n == 2:
		world.shape = "square"
		world.size = CELL * 8.0
	elif n <= 4:
		world.shape = "circle"
		world.size = CELL * 9.0
	else:
		world.shape = "circle"
		world.size = CELL * 12.0
	aim_limit = AIM_LIMIT if timed else 0.0
	_place_stones()
	world.gimmicks = World.Gm.generate(workshop, n, world, gimmick_rng)
	homes.clear()
	for st in world.stones:
		homes[st.id] = st.pos
	max_rounds = 0
	if mode == "derby":
		max_rounds = DERBY_ROUNDS_SMALL if n <= 4 else DERBY_ROUNDS_BIG
	start_seat = rng.randi_range(0, n - 1)
	round_no = 1
	winners.clear()
	out_order.clear()
	shots = 0
	placements.clear()
	if bool(opts.get("placement", false)):
		# 시작 배치 선택: 1바퀴 전에 모두가 자기 구역에 알을 놓는다
		phase = "place"
		return
	_begin_round()


## 시작 구역: 판 가장자리를 따라 같은 간격.
## 2인은 자기 쪽 변에서 4칸 안쪽에 한 줄로 4개(2.5칸 간격),
## 원형은 가장자리에서 4칸에 좌우로 두 개, 5.5칸에 하나 (중심을 향한 삼각형).
const SIDE_GAP := 1.25        # 원형 앞줄 두 퍽의 좌우 간격 (칸, 중심선에서)


func stones_per_player() -> int:
	return 4 if n == 2 else 3


func _place_stones() -> void:
	if world.shape == "square":
		for p in 2:
			var y := (world.size - CELL * 4.0) * (1.0 if p == 0 else -1.0)
			for k in 4:
				world.add_stone(p, Vector2((k - 1.5) * CELL * 2.5, y), -PI / 2.0 if p == 0 else PI / 2.0)
		return
	for p in n:
		var ang := PI / 2.0 + TAU * p / n
		var radial := Vector2.from_angle(ang)
		var tang := radial.orthogonal()
		var front := radial * (world.size - CELL * 4.0)
		world.add_stone(p, front + tang * CELL * SIDE_GAP, ang + PI)
		world.add_stone(p, front - tang * CELL * SIDE_GAP, ang + PI)
		world.add_stone(p, radial * (world.size - CELL * 5.5), ang + PI)


func stones_left(pid: int) -> int:
	return world.alive_stones_of(pid).size()


func alive_players() -> Array:
	var out: Array = []
	for p in players:
		if not p.out:
			out.append(p.id)
	return out


func current_player() -> int:
	if turn_pos < order.size():
		return order[turn_pos]
	return -1


func current_drafter() -> int:
	return draft_queue[0] if not draft_queue.is_empty() else -1


func is_draft_round(r: int) -> bool:
	return r >= first_draft_round and (draft_rounds.is_empty() or draft_rounds.has(r))


# ── 바퀴 ─────────────────────────────────────────────────

func _begin_round() -> void:
	if mode == "derby" and round_no > 1:
		_respawn()
	world.round_no = round_no
	if round_no > 1:
		World.Gm.on_round(world)
	world.expire_devices()
	order.clear()
	for k in n:
		var pid := (start_seat + k) % n
		if not players[pid].out:
			order.append(pid)
	turn_pos = 0
	if is_draft_round(round_no):
		draft_queue = order.duplicate()
		offers.clear()
		for pid in draft_queue:
			offers[pid] = roll_offer(pid)
		phase = "draft"
	else:
		phase = "aim"
		_mark_relic_turn()


func _mark_relic_turn() -> void:
	var cur := current_player()
	if cur >= 0 and players[cur].relic != "":
		players[cur].relic_turn = true


## 유품 리본으로 회수한 부품을 달 수 있는 알 (그 슬롯이 빈 살아 있는 알).
func relic_targets(pid: int) -> Array:
	var part: String = players[pid].relic
	if part == "" or not players[pid].relic_turn:
		return []
	var slot := PartsData.slot_of(part)
	return world.alive_stones_of(pid).filter(func(s): return s.parts[slot] == "")


func equip_relic(pid: int, stone_id: int) -> bool:
	if phase != "aim" or current_player() != pid:
		return false
	var part: String = players[pid].relic
	var s = world.get_stone(stone_id)
	if part == "" or s == null or not relic_targets(pid).has(s):
		return false
	s.parts[PartsData.slot_of(part)] = part
	players[pid].relic = ""
	players[pid].relic_turn = false
	return true


## 후보 세 개.
## - 운명의 책갈피로 예약한 부품이 있으면 한 자리.
## - 미완성 세트 부품을 단 살아 있는 알이 있으면, 그 알에 빠진 세트 부품 하나가 한 자리.
##   여러 알이 모으고 있으면 장착 수가 많은 알, 동률이면 지난번에 장착한 알이 우선.
## - 둘이 같은 부품이면 한 자리로 합친다. 나머지는 일반 부품(세트 추천이 있으면 세트 부품 제외).
func roll_offer(pid: int) -> Array:
	var out: Array = []
	var p: Dictionary = players[pid]
	if p.reserved != "":
		out.append(p.reserved)
		p.reserved = ""
	var missing := set_missing(pid)
	if not missing.is_empty():
		var pick: String = missing[rng.randi_range(0, missing.size() - 1)]
		if not out.has(pick):
			out.append(pick)
	# 오늘의 공방 부품 중에서. 세 개 중 적어도 둘은 살아 있는 내 알의 빈 슬롯에 바로 붙일 수 있게.
	var pool: Array = []
	for id in match_parts:
		if missing.is_empty() or PartsData.set_of(id) == "":
			if not out.has(id):
				pool.append(id)
	var fits := func(id: String) -> bool:
		var slot := PartsData.slot_of(id)
		for st in world.alive_stones_of(pid):
			if st.parts[slot] == "":
				return true
		return false
	var fit_count := 0
	for id in out:
		if fits.call(id):
			fit_count += 1
	while out.size() < OFFER_COUNT and not pool.is_empty():
		var candidates: Array = pool
		# 후보 중 공용 부품은 최대 1장 (나머지는 공방 전용)
		var commons := out.filter(func(x): return PartsData.COMMON_PARTS.has(x)).size()
		if commons >= 1 and workshop != "all":
			var excl_only: Array = candidates.filter(func(x): return not PartsData.COMMON_PARTS.has(x))
			if not excl_only.is_empty():
				candidates = excl_only
		if fit_count < 2:
			var fitting0: Array = candidates.filter(func(x): return fits.call(x))
			if not fitting0.is_empty():
				candidates = fitting0
		var pick2: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		out.append(pick2)
		pool.erase(pick2)
		if fits.call(pick2):
			fit_count += 1
	return out


## 세트를 모으는 살아 있는 내 알 중 우선인 알의, 아직 없는 세트 부품. 없으면 빈 배열.
func set_missing(pid: int) -> Array:
	var best: Array = []
	var best_n := 0
	var best_focus := false
	for s in world.alive_stones_of(pid):
		var sid := PartsData.main_set(s.parts)
		if sid == "":
			continue
		var pr := PartsData.set_progress(s.parts, sid)
		if pr["count"] >= pr["total"]:
			continue
		var focus: bool = s.id == players[pid].focus
		if pr["count"] > best_n or (pr["count"] == best_n and focus and not best_focus):
			best_n = pr["count"]
			best = pr["missing"]
			best_focus = focus
	return best


## 예전 이름 (티라노만 있던 때).
func trex_missing(pid: int) -> Array:
	return set_missing(pid)


## 고른 부품을 살아 있는 내 알에 단다. 같은 슬롯의 기존 부품은 교체된다.
func equip(pid: int, part_id: String, stone_id: int, side := 1, reserve := "") -> bool:
	if phase != "draft" or current_drafter() != pid:
		return false
	if not offers.get(pid, []).has(part_id):
		return false
	var s = world.get_stone(stone_id)
	if s == null or not s.alive or s.owner != pid:
		return false
	s.parts[PartsData.slot_of(part_id)] = part_id
	players[pid].focus = stone_id
	# 운명의 책갈피: 이번에 고르지 않은 후보 하나를 다음 선택에 예약.
	if part_id == "bookmark":
		var rest: Array = offers[pid].filter(func(x): return x != part_id)
		if reserve == "" or not rest.has(reserve):
			reserve = rest[0] if not rest.is_empty() else ""
		players[pid].reserved = reserve
	if PartsData.SIDE_PARTS.has(part_id):
		if PartsData.slot_of(part_id) == "prop":
			s.prop_side = 1 if side >= 0 else -1
		else:
			s.magnet_side = 1 if side >= 0 else -1
	draft_queue.pop_front()
	if draft_queue.is_empty():
		phase = "aim"
		_mark_relic_turn()
	return true


# ── 샷 ───────────────────────────────────────────────────

## opts: charged(모으고 쏘는 손바닥 충전), from_cloud(구름 우편함 자리에서 출발).
func shoot(stone_id: int, dir: Vector2, power: float, opts := {}) -> bool:
	if phase != "aim":
		return false
	var s = world.get_stone(stone_id)
	if s == null or not s.alive or s.owner != current_player():
		return false
	if opts.get("from_cloud", false):
		world.move_to_cloud(stone_id)
	world.launch(stone_id, dir, power, opts)
	phase = "moving"
	shots += 1
	return true


## 모든 움직임이 끝난 뒤 부른다: 탈락 정리 → 승패 확인 → 다음 차례.
func finish_shot() -> void:
	# 개조 더비: 상대 알을 떨어뜨리면 쏜 사람에게 1점 (자멸·원인 불명은 0점)
	if mode == "derby" and world.shot != null:
		var shooter_owner: int = world.shot.owner
		for k in world.knockouts:
			var c: Dictionary = k.get("cause", {})
			if int(k["owner"]) != shooter_owner and c.has("owner") and int(c["owner"]) == shooter_owner:
				scores[shooter_owner] += 1
	world.end_shot()
	_settle_turn()


## 조준 시간이 끝나면 그 턴은 넘어간다.
func skip_turn() -> void:
	if phase != "aim":
		return
	_settle_turn()


func _settle_turn() -> void:
	# 유품 리본으로 회수한 부품은 다음 내 차례에만 달 수 있다.
	var cur := current_player()
	if cur >= 0 and players[cur].relic_turn:
		players[cur].relic = ""
		players[cur].relic_turn = false
	for r in world.relics:
		var rp: Dictionary = players[r["owner"]]
		if rp.relic == "":
			rp.relic = r["part"]
	world.relics.clear()
	if mode != "derby":
		for p in players:
			if not p.out and stones_left(p.id) == 0:
				p.out = true
				p.out_round = round_no
				out_order.append(p.id)
		var alive := alive_players()
		if alive.size() == 1:
			_finish([alive[0]], "last")
			return
		if alive.is_empty():
			_finish([], "draw")
			return
	turn_pos += 1
	# 떨어진 자리는 건너뛴다 (더비에서는 이번 바퀴에 알이 하나도 없는 사람도)
	while turn_pos < order.size() and (players[order[turn_pos]].out or stones_left(order[turn_pos]) == 0):
		turn_pos += 1
	if turn_pos < order.size():
		phase = "aim"
		_mark_relic_turn()
		return
	# 바퀴 끝
	round_no += 1
	if max_rounds > 0 and round_no > max_rounds:
		if mode == "derby":
			_finish_by_score()
		else:
			_finish_by_count()
		return
	start_seat = (start_seat + 1) % n
	_begin_round()


## 개조 더비: 떨어진 알은 다음 바퀴 시작에 자기 자리(막혀 있으면 가까운 빈자리)로 돌아온다. 부품은 그대로.
func _respawn() -> void:
	for st in world.stones:
		if st.alive:
			continue
		var home: Vector2 = homes.get(st.id, Vector2.ZERO)
		var spot := _free_near(home)
		st.alive = true
		st.pos = spot
		st.vel = Vector2.ZERO
		st.status = {}
		st.cause = {}
		world.emit({"t": "respawn", "pos": spot, "owner": st.owner, "stone": st.id})


func _free_near(home: Vector2) -> Vector2:
	var r := World.STONE_R * 2.0 + 1.0
	for ring in range(0, 8):
		var tries := 1 if ring == 0 else 8 * ring
		for k in tries:
			var p: Vector2 = home if ring == 0 else home + Vector2.from_angle(TAU * k / tries) * ring * r * 0.75
			if not world.is_inside(p) or world.edge_distance(p) < CELL:
				continue
			var ok := true
			for o in world.stones:
				if o.alive and o.pos.distance_to(p) < r:
					ok = false
					break
			if ok:
				return p
	return home


func _finish_by_score() -> void:
	var best := -1
	for pid in range(n):
		best = maxi(best, scores[pid])
	var w: Array = []
	for pid in range(n):
		if scores[pid] == best:
			w.append(pid)
	round_no = max_rounds
	_finish(w, "score")


func _finish_by_count() -> void:
	var best := 0
	for pid in alive_players():
		best = maxi(best, stones_left(pid))
	var w: Array = []
	for pid in alive_players():
		if stones_left(pid) == best:
			w.append(pid)
	round_no = max_rounds
	_finish(w, "limit")


func _finish(w: Array, reason: String) -> void:
	winners = w
	end_reason = reason
	phase = "over"


# ── 시작 배치 선택 (확장 기획 「시작 배치 선택」) ─────────────
## 자기 구역: 판을 인원수만큼 부채꼴로 나눈 조각, 가장자리에서 2칸 안쪽부터 6.5칸 안쪽까지.
## 내 알끼리는 1칸 이상 (중심 간 2칸), 기믹 장애물과는 0.5칸 이상 떨어져야 한다.
## 모두 놓으면 동시에 공개한다 (그 전까지 남의 배치는 판에 반영되지 않는다).

var placements := {}          # pid → [Vector2, ...] (확정한 배치)
const PLACE_IN := 2.0         # 칸: 가장자리에서 이만큼 안쪽부터
const PLACE_OUT := 6.5        # 칸: 이만큼 안쪽까지
const PLACE_GAP := 2.0        # 칸: 내 알끼리 중심 간 거리


func seat_angle(pid: int) -> float:
	return PI / 2.0 + TAU * pid / n


func in_zone(pid: int, p: Vector2) -> bool:
	if world.shape == "square":
		var sgn := 1.0 if pid == 0 else -1.0
		var depth := world.size - p.y * sgn
		return depth >= PLACE_IN * CELL and depth <= PLACE_OUT * CELL and absf(p.x) <= world.size - PLACE_IN * CELL
	var ed: float = world.size - p.length()
	if ed < PLACE_IN * CELL or ed > PLACE_OUT * CELL:
		return false
	var da := absf(angle_difference(p.angle(), seat_angle(pid)))
	# 경계에서 퍽이 이웃 구역으로 넘지 않게 반지름만큼 각도를 줄인다
	var margin := World.STONE_R / maxf(1.0, p.length())
	return da <= PI / n - margin


## 놓을 수 있는지: 구역 · 간격 · 장애물. 잘못된 알의 번호 목록 (비어 있으면 통과).
func placement_errors(pid: int, pts: Array) -> Array:
	var bad: Array = []
	for i in pts.size():
		var p: Vector2 = pts[i]
		var ok := in_zone(pid, p) and not World.Gm.blocks(world, p)
		for j in pts.size():
			if j != i and p.distance_to(pts[j]) < PLACE_GAP * CELL - 0.01:
				ok = false
		if not ok:
			bad.append(i)
	return bad


## 배치 확정. 모두 확정하면 알을 옮기고 1바퀴를 시작한다. 성공하면 true.
func place(pid: int, pts: Array) -> bool:
	if phase != "place" or placements.has(pid):
		return false
	var mine: Array = world.alive_stones_of(pid)
	if pts.size() != mine.size() or not placement_errors(pid, pts).is_empty():
		return false
	placements[pid] = pts.duplicate()
	if placements.size() >= n:
		_commit_placements()
	return true


func _commit_placements() -> void:
	for pid in placements:
		var mine: Array = world.alive_stones_of(pid)
		var pts: Array = placements[pid]
		for i in mine.size():
			mine[i].pos = pts[i]
			mine[i].facing = (-(pts[i] as Vector2)).angle()
			homes[mine[i].id] = pts[i]
	world.emit({"t": "placed"})
	_begin_round()


## 빠른 선택: line(일렬) · tri(삼각) · spread(흩어짐) · random(무작위)
func preset(pid: int, kind: String, r: RandomNumberGenerator = null) -> Array:
	var k := stones_per_player()
	var pts: Array = []
	if r == null:
		r = rng
	var center_d := world.size - CELL * (PLACE_IN + PLACE_OUT) * 0.5
	var radial := Vector2.from_angle(seat_angle(pid))
	if world.shape == "square":
		radial = Vector2(0, 1) if pid == 0 else Vector2(0, -1)
	var tang := radial.orthogonal()
	match kind:
		"line":
			for i in k:
				pts.append(radial * center_d + tang * (i - (k - 1) * 0.5) * CELL * 2.1)
		"tri":
			var dd := center_d + CELL * 0.6
			pts.append(radial * (dd - CELL * 1.8))
			pts.append(radial * dd + tang * CELL * 1.1)
			pts.append(radial * dd - tang * CELL * 1.1)
			if k == 4:
				pts.append(radial * (dd + CELL * 1.8))
		"spread":
			var near := world.size - CELL * (PLACE_OUT - 0.4)
			var far := world.size - CELL * (PLACE_IN + 0.5)
			for i in k:
				var t := (i - (k - 1) * 0.5) * (2.6 if world.shape == "square" else 1.0)
				var dist := near if i % 2 == 0 else far
				if world.shape == "square":
					pts.append(radial * dist + tang * t * CELL)
				else:
					var span := (PI / n) * 0.62
					pts.append(Vector2.from_angle(seat_angle(pid) + span * (i - (k - 1) * 0.5) / maxf(1.0, (k - 1) * 0.5)) * dist)
		_:
			for attempt in 200:
				pts.clear()
				for i in k:
					var p := Vector2.ZERO
					for tries in 40:
						if world.shape == "square":
							p = Vector2(r.randf_range(-world.size + CELL * 2.0, world.size - CELL * 2.0), (world.size - r.randf_range(PLACE_IN, PLACE_OUT) * CELL) * (1.0 if pid == 0 else -1.0))
						else:
							var a := seat_angle(pid) + r.randf_range(-1.0, 1.0) * (PI / n) * 0.8
							p = Vector2.from_angle(a) * (world.size - r.randf_range(PLACE_IN + 0.2, PLACE_OUT - 0.2) * CELL)
						var ok := true
						for q in pts:
							if p.distance_to(q) < PLACE_GAP * CELL:
								ok = false
						if ok:
							break
					pts.append(p)
				if placement_errors(pid, pts).is_empty():
					return pts
	if not placement_errors(pid, pts).is_empty():
		# 줄 배치가 장애물에 걸리면 무작위로
		if kind != "random":
			return preset(pid, "random", r)
	return pts


## CPU 성향: 공격형은 구역 안쪽 끝에 넓게, 생존형은 가장자리에서 먼 쪽에 모아서, 기믹 활용형은 기믹 옆에.
func cpu_placement(pid: int, r: RandomNumberGenerator) -> Array:
	var style := pid % 3
	var pts: Array = []
	if style == 0:
		pts = preset(pid, "line", r)
	elif style == 1:
		pts = preset(pid, "tri", r)
	else:
		# 기믹 쪽으로 기울인 무작위 배치 여러 개 중 기믹에 가장 가까운 것
		var best: Array = []
		var best_d := INF
		for i in 12:
			var cand := preset(pid, "random", r)
			if not placement_errors(pid, cand).is_empty():
				continue
			var d := 0.0
			for q in cand:
				d += _nearest_gimmick(q)
			if d < best_d:
				best_d = d
				best = cand
		pts = best if not best.is_empty() else preset(pid, "tri", r)
	return pts


func _nearest_gimmick(p: Vector2) -> float:
	var best := 9999.0
	for g in world.gimmicks:
		for it in g["items"]:
			best = minf(best, p.distance_to(it["pos"]))
	return best
