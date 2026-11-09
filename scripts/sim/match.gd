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
var max_rounds := 0           # 0 = 바퀴 제한 없음: 한 사람만 남을 때까지
var draft_rounds: Array = []  # 비어 있으면 매 바퀴 개조
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
	start_seat = rng.randi_range(0, n - 1)
	round_no = 1
	winners.clear()
	out_order.clear()
	shots = 0
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
	return draft_rounds.is_empty() or draft_rounds.has(r)


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
	var pool: Array = []
	for id in PartsData.ids():
		if missing.is_empty() or PartsData.set_of(id) == "":
			if not out.has(id):
				pool.append(id)
	while out.size() < OFFER_COUNT and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
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
		_mark_relic_turn()
		return
	# 바퀴 끝
	round_no += 1
	if max_rounds > 0 and round_no > max_rounds:
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
