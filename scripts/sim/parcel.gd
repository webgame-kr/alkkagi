extends RefCounted
## 택배 쟁탈전의 택배 (기획 「신규 모드 · 택배 쟁탈전」).
## 팀 색이 없는 상자. 알 지름의 1.3배, 질량 1.5배. 플레이어 알의 몸통 충돌로만 움직인다
## (총알·폭발·소환물·맵 기믹·크기 효과는 받지 않는다). 바닥 마찰과 판 경계만 적용.
## 상태는 world.parcel 에 둔다 (비어 있으면 이 모드가 아님).
##   field: 판 위 · gone: 이번 샷에 떨어짐 (샷이 끝나면 중앙으로) · wait: 중앙이 막혀 대기

const CELL := 44.0
const R := 22.0 * 1.3          # 충돌 반지름 (알의 1.3배)
const MASS := 1.5
const NEUTRAL_HALF := 0.5 * CELL   # 중앙선 양옆 0.5칸씩 = 중립 띠 폭 1칸


static func on(w) -> bool:
	return not w.parcel.is_empty()


static func make() -> Dictionary:
	return {"state": "field", "pos": Vector2.ZERO, "vel": Vector2.ZERO, "ang": 0.0, "touch": {}}


## 지금 정산하면 점수를 얻을 팀 (0: 왼쪽 빨강 진영, 1: 오른쪽 파랑 진영, -1: 중립·대기)
static func side_team(w) -> int:
	if not on(w) or w.parcel["state"] != "field":
		return -1
	var x: float = (w.parcel["pos"] as Vector2).x
	if x < -NEUTRAL_HALF:
		return 0
	if x > NEUTRAL_HALF:
		return 1
	return -1


## 매 물리 단계: 알과 같은 마찰로 미끄러진다. 판 밖으로 나가면 떨어진다.
static func move(w, dt: float) -> void:
	if not on(w) or w.parcel["state"] != "field":
		return
	var p: Dictionary = w.parcel
	var v: Vector2 = p["vel"]
	var sp := v.length()
	if sp <= 0.0:
		return
	var ns: float = sp - w.FRICTION * dt - sp * w.DRAG * dt
	if ns < w.STOP_SPEED:
		p["vel"] = Vector2.ZERO
		return
	v *= ns / sp
	p["vel"] = v
	p["pos"] = (p["pos"] as Vector2) + v * dt
	p["ang"] = float(p["ang"]) + sp * dt * 0.004 * (1.0 if v.x >= 0.0 else -1.0)


## 알 몸통과의 충돌 (알끼리와 같은 반발 계수)
static func collide(w) -> void:
	if not on(w) or w.parcel["state"] != "field":
		return
	var p: Dictionary = w.parcel
	for s in w.stones:
		if not s.alive:
			continue
		var pv: Vector2 = p["vel"]
		if s.vel == Vector2.ZERO and pv == Vector2.ZERO:
			continue
		var d: Vector2 = (p["pos"] as Vector2) - s.pos
		var min_d: float = w.radius_of(s) + R
		var dist := d.length()
		if dist >= min_d:
			continue
		var nrm := d / dist if dist > 0.0001 else Vector2.RIGHT
		var ms: float = w.mass_of(s)
		var overlap := min_d - dist
		s.pos -= nrm * overlap * MASS / (ms + MASS)
		p["pos"] = (p["pos"] as Vector2) + nrm * overlap * ms / (ms + MASS)
		var rel: float = (s.vel - pv).dot(nrm)
		if rel <= 0.0:
			continue
		var imp: float = rel * (1.0 + w.RESTITUTION) / (1.0 / ms + 1.0 / MASS)
		s.vel -= nrm * imp / ms
		p["vel"] = pv + nrm * imp / MASS
		if w.shot != null:
			var t: Dictionary = w.shot.ex.get("parcel_touch", {})
			t[s.owner] = true
			w.shot.ex["parcel_touch"] = t
		w.emit({"t": "hit", "pos": s.pos + nrm * w.radius_of(s), "strength": rel, "a": s.id, "b": -1, "n": nrm})


static func check_out(w) -> void:
	if not on(w) or w.parcel["state"] != "field":
		return
	if not w.is_inside(w.parcel["pos"]):
		w.parcel["state"] = "gone"
		w.parcel["vel"] = Vector2.ZERO
		w.emit({"t": "parcel", "kind": "drop", "pos": w.parcel["pos"]})


static func moving(w) -> bool:
	return on(w) and w.parcel["state"] == "field" and w.parcel["vel"] != Vector2.ZERO


## 샷이 끝나면: 몸통 접촉 기록, 떨어진 택배는 중앙으로.
static func end_shot(w) -> void:
	if not on(w):
		return
	if w.shot != null:
		var touch: Dictionary = w.parcel["touch"]
		for owner in w.shot.ex.get("parcel_touch", {}):
			touch[owner] = int(touch.get(owner, 0)) + 1
	if w.parcel["state"] == "gone" or w.parcel["state"] == "wait":
		send_home(w)


## 택배를 중앙(막혔으면 중립 띠 안의 가까운 빈 곳)으로. 자리가 없으면 대기.
static func send_home(w) -> void:
	var from: Vector2 = w.parcel["pos"]
	var spot = home_spot(w)
	w.parcel["vel"] = Vector2.ZERO
	if spot == null:
		w.parcel["state"] = "wait"
		return
	w.parcel["state"] = "field"
	w.parcel["pos"] = spot
	w.parcel["ang"] = 0.0
	w.emit({"t": "parcel", "kind": "home", "pos": spot, "from": from})


static func home_spot(w):
	for i in 7:
		# 중앙, 그다음 중립 띠를 따라 위아래로
		var p := Vector2(0, (int((i + 1) / 2)) * CELL * 1.4 * (1.0 if i % 2 == 1 else -1.0))
		var free := true
		for s in w.stones:
			if s.alive and s.pos.distance_to(p) < w.radius_of(s) + R + 2.0:
				free = false
				break
		if free:
			return p
	return null
