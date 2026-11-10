extends RefCounted
## 왕관 쟁탈전 (기획 「신규 모드 · 왕관 쟁탈전」).
## 왕관은 바닥(중앙)에 있거나, 알 하나가 머리에 이고 있다. 상태는 world.crown 에 둔다 (비어 있으면 이 모드가 아님).
##   floor: 바닥에 있음 (pos) · held: holder 알이 보유 · gone: 이번 샷에 떨어져 샷이 끝나면 중앙으로 · wait: 중앙이 막혀 대기
## 줍기: 이번 차례에 직접 쏜 기본 알이 닿으면. 빼앗기: 직접 쏜 기본 알이 보유 알과 몸통 충돌하면 (한 샷에 한 번).
## 총알·폭발·소환물·간접 충돌·복제된 알·리모컨으로는 줍거나 빼앗지 못한다.

const CELL := 44.0
const PICK_R := 0.6 * CELL     # 바닥 왕관을 줍는 거리 (알 반지름에 더한다)
const GOAL := 5                # 먼저 5점
const HOME_SPOTS := 9          # 중앙 + 둘레 8곳


static func on(w) -> bool:
	return not w.crown.is_empty()


static func make(base_count: int) -> Dictionary:
	return {"state": "floor", "holder": -1, "pos": Vector2.ZERO, "base_n": base_count}


static func holder_stone(w):
	if not on(w) or w.crown["state"] != "held":
		return null
	return w.get_stone(int(w.crown["holder"]))


## 처음부터 있던 기본 알만 (분열 조각 같은 복제 알은 id 가 그 뒤에 붙는다)
static func is_base(w, s) -> bool:
	return s.id < int(w.crown["base_n"])


## 이번 샷에 직접 쏜, 쏜 사람 자신의 기본 알 (리모컨으로 쏜 남의 알은 아님)
static func _direct(w, s) -> bool:
	return w.shot != null and s.id == w.shot.stone_id and s.owner == w.shot.owner and is_base(w, s) and s.alive


static func on_launch(w, _s) -> void:
	if not on(w):
		return
	w.shot.ex["crown_start"] = int(w.crown["holder"]) if w.crown["state"] == "held" else -1


## 몸통 충돌 직후: 직접 쏜 알이 상대의 왕관 알에 부딪히면 빼앗는다.
static func on_hit(w, a, b) -> void:
	if not on(w) or w.shot == null or w.shot.ex.get("crown_moved", false) or w.crown["state"] != "held":
		return
	var me = null
	var other = null
	if _direct(w, a):
		me = a
		other = b
	elif _direct(w, b):
		me = b
		other = a
	else:
		return
	if other.id != int(w.crown["holder"]) or other.owner == me.owner:
		return
	w.crown["holder"] = me.id
	w.shot.ex["crown_moved"] = true
	w.shot.ex["crown_taker"] = me.owner
	w.shot.ex["crown_steal"] = true
	w.emit({"t": "crown", "kind": "steal", "from": other.pos, "pos": me.pos, "owner": me.owner, "victim": other.owner, "stone": me.id})


## 매 물리 단계 끝: 보유 알이 사라졌으면 왕관을 잃고, 바닥 왕관은 직접 쏜 알이 닿으면 줍는다.
static func after_step(w) -> void:
	if not on(w):
		return
	var c: Dictionary = w.crown
	if c["state"] == "held":
		var h = w.get_stone(int(c["holder"]))
		if h == null or not h.alive:
			var at: Vector2 = h.pos if h != null else Vector2.ZERO
			c["state"] = "gone"
			c["holder"] = -1
			w.emit({"t": "crown", "kind": "drop", "pos": at, "owner": h.owner if h != null else -1})
		return
	if c["state"] != "floor" or w.shot == null or w.shot.ex.get("crown_moved", false):
		return
	var s = w.shooter()
	if s == null or not _direct(w, s):
		return
	if s.pos.distance_to(c["pos"]) <= w.radius_of(s) + PICK_R:
		c["state"] = "held"
		c["holder"] = s.id
		w.shot.ex["crown_moved"] = true
		w.shot.ex["crown_taker"] = s.owner
		w.emit({"t": "crown", "kind": "take", "pos": s.pos, "owner": s.owner, "stone": s.id})


## 샷이 끝나면: 떨어진(또는 대기 중인) 왕관을 중앙의 빈 자리로. 다 막혀 있으면 대기.
static func end_shot(w) -> void:
	if not on(w):
		return
	var c: Dictionary = w.crown
	if c["state"] != "gone" and c["state"] != "wait":
		return
	var spot = home_spot(w)
	if spot == null:
		c["state"] = "wait"
		return
	c["state"] = "floor"
	c["pos"] = spot
	w.emit({"t": "crown", "kind": "home", "pos": spot})


static func home_spot(w):
	for i in HOME_SPOTS:
		var p := Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * (i - 1) / 8.0) * CELL * 1.3
		var free := true
		for s in w.stones:
			if s.alive and s.pos.distance_to(p) < w.radius_of(s) + PICK_R * 0.6:
				free = false
				break
		if free:
			return p
	return null
