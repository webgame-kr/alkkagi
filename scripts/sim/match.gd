extends RefCounted
## 경기 관리: 차례, 바퀴, 탈락자, 부품 선택. 물리는 world.gd 에 맡긴다.

const World = preload("res://scripts/sim/world.gd")
const PartsData = preload("res://scripts/sim/parts_data.gd")

const COLORS := [Color("E0533D"), Color("3D6FD1"), Color("E3B23C"), Color("3FA27A"),
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
var max_rounds := 8
var draft_rounds: Array = [2, 3, 4]
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


func setup(n_players: int, cpu_flags: Array, seed_value: int, timed: bool) -> void:
	n = clampi(n_players, 2, 8)
	rng.seed = seed_value
	players.clear()
	for i in n:
		players.append({"id": i, "name": NAMES[i], "color": COLORS[i],
			"cpu": bool(cpu_flags[i]) if i < cpu_flags.size() else false, "out": false, "out_round": 0})
	world = World.new()
	if n == 2:
		world.shape = "square"
		world.size = CELL * 8.0
		max_rounds = 12
		draft_rounds = [2, 3, 4]
	elif n <= 4:
		world.shape = "circle"
		world.size = CELL * 9.0
		max_rounds = 8
		draft_rounds = [2, 3, 4]
	else:
		world.shape = "circle"
		world.size = CELL * 12.0
		max_rounds = 6
		draft_rounds = [1, 2, 3]
	aim_limit = AIM_LIMIT if timed else 0.0
	_place_stones()
	start_seat = rng.randi_range(0, n - 1)
	round_no = 1
	winners.clear()
	out_order.clear()
	shots = 0
	_begin_round()


## 시작 구역: 판 가장자리를 따라 같은 간격.
## 2인은 자기 쪽 변에서 4칸 안쪽에 한 줄로 3개(2.5칸 간격),
## 원형은 가장자리에서 4칸과 5.5칸, 중심을 향해 앞뒤로 2개.
func _place_stones() -> void:
	if world.shape == "square":
		for p in 2:
			var y := (world.size - CELL * 4.0) * (1.0 if p == 0 else -1.0)
			for k in 3:
				world.add_stone(p, Vector2((k - 1) * CELL * 2.5, y), -PI / 2.0 if p == 0 else PI / 2.0)
		return
	for p in n:
		var ang := PI / 2.0 + TAU * p / n
		var radial := Vector2.from_angle(ang)
		for depth in [4.0, 5.5]:
			world.add_stone(p, radial * (world.size - CELL * depth), ang + PI)


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
	return draft_rounds.has(r)


# ── 바퀴 ─────────────────────────────────────────────────

func _begin_round() -> void:
	world.round_no = round_no
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


## 후보 세 개. 살아 있는 내 알에 티라노 부품이 붙어 있으면,
## 아직 안 달린 티라노 부품 하나를 한 자리에 넣고 나머지 두 자리는 일반 부품으로 채운다.
func roll_offer(pid: int) -> Array:
	var out: Array = []
	var missing := trex_missing(pid)
	if not missing.is_empty():
		out.append(missing[rng.randi_range(0, missing.size() - 1)])
	var pool: Array = []
	for id in PartsData.ids():
		if out.is_empty() or PartsData.set_of(id) == "":
			if not out.has(id):
				pool.append(id)
	while out.size() < OFFER_COUNT and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out


## 티라노 부품을 가장 많이 단 살아 있는 내 알 기준으로, 아직 없는 티라노 부품. 없으면 빈 배열.
func trex_missing(pid: int) -> Array:
	var best: Array = []
	var best_n := 0
	for s in world.alive_stones_of(pid):
		var pr := PartsData.set_progress(s.parts)
		if pr["count"] > best_n and pr["count"] < pr["total"]:
			best_n = pr["count"]
			best = pr["missing"]
	return best


## 고른 부품을 살아 있는 내 알에 단다. 같은 슬롯의 기존 부품은 교체된다.
func equip(pid: int, part_id: String, stone_id: int, side := 1) -> bool:
	if phase != "draft" or current_drafter() != pid:
		return false
	if not offers.get(pid, []).has(part_id):
		return false
	var s = world.get_stone(stone_id)
	if s == null or not s.alive or s.owner != pid:
		return false
	s.parts[PartsData.slot_of(part_id)] = part_id
	if PartsData.SIDE_PARTS.has(part_id):
		if PartsData.slot_of(part_id) == "prop":
			s.prop_side = 1 if side >= 0 else -1
		else:
			s.magnet_side = 1 if side >= 0 else -1
	draft_queue.pop_front()
	if draft_queue.is_empty():
		phase = "aim"
	return true


# ── 샷 ───────────────────────────────────────────────────

func shoot(stone_id: int, dir: Vector2, power: float) -> bool:
	if phase != "aim":
		return false
	var s = world.get_stone(stone_id)
	if s == null or not s.alive or s.owner != current_player():
		return false
	world.launch(stone_id, dir, power)
	phase = "moving"
	shots += 1
	return true


## 모든 움직임이 끝난 뒤 부른다: 탈락 정리 → 승패 확인 → 다음 차례.
func finish_shot() -> void:
	world.end_shot()
	_settle_turn()


## 조준 시간이 끝나면 그 턴은 넘어간다.
func skip_turn() -> void:
	if phase != "aim":
		return
	_settle_turn()


func _settle_turn() -> void:
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
	while turn_pos < order.size() and players[order[turn_pos]].out:
		turn_pos += 1
	if turn_pos < order.size():
		phase = "aim"
		return
	# 바퀴 끝
	round_no += 1
	if round_no > max_rounds:
		_finish_by_count()
		return
	start_seat = (start_seat + 1) % n
	_begin_round()


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
