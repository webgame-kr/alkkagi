extends RefCounted
## 맵 기믹 (확장 기획 「맵 기믹」). 판을 시작할 때 공방의 기믹 중 1개(5~8인은 2개)를 꺼내 놓는다.
## 기믹은 누구의 것도 아니다. 기믹 때문에 떨어진 알은 「기믹 이름 · 쏜 사람의 샷」으로 적는다.
## 모든 계산은 결정적이다 (온라인에서 같은 시드면 같은 판).

const CELL := 44.0
const TIME_K := 2.5          # parts.gd 와 같은 시간 배율 (사양의 초당 값 × 2.5)

## 공방별 기믹 3종
const BY_WORKSHOP := {
	"junk": ["oil", "bolt", "belt"],
	"magic": [],
	"toon": [],
}

const INFO := {
	"oil": {"name": "기름 웅덩이", "desc": "안에서는 마찰이 30%로 줄어 훨씬 멀리 미끄러져요"},
	"bolt": {"name": "범퍼 볼트", "desc": "움직이지 않는 볼트. 부딪힌 알을 120% 속도로 튕겨 내요"},
	"belt": {"name": "컨베이어 띠", "desc": "띠 위의 알은 화살표 쪽으로 실려 가요. 바퀴마다 방향이 뒤집혀요"},
}

const OIL_R := 1.5 * CELL
const OIL_FRICTION := 0.3
const BOLT_R := 0.4 * CELL
const BOLT_BOUNCE := 1.2
const BELT_HALF := 0.75 * CELL
const BELT_SPEED := 1.5 * CELL * TIME_K
const BELT_TIME := 0.8        # 샷마다 띠가 알을 나르는 시간 (초, 판 시간)


static func name_of(kind: String) -> String:
	return INFO.get(kind, {}).get("name", kind)


## 판 시작 때 기믹을 고르고 놓는다. 반환: [{kind, items:[...]}]
static func generate(ws: String, n_players: int, w, rng: RandomNumberGenerator) -> Array:
	var kinds: Array = BY_WORKSHOP.get(ws, []).duplicate()
	if kinds.is_empty():
		return []
	var count := 1 if n_players <= 4 else 2
	var out: Array = []
	for i in mini(count, kinds.size()):
		var k := rng.randi_range(0, kinds.size() - 1)
		var kind: String = kinds[k]
		kinds.remove_at(k)
		out.append(_place(kind, w, rng))
	return out


## 시작 구역(가장자리에서 6.5칸 안쪽까지)과 판 중심 1칸 안은 피한다. 여러 개는 판 양쪽에 고르게.
static func _ring(w) -> Vector2:
	var max_d: float = maxf(1.6 * CELL, w.size - 6.5 * CELL)
	return Vector2(1.2 * CELL, max_d)


static func _place(kind: String, w, rng: RandomNumberGenerator) -> Dictionary:
	var ring := _ring(w)
	var base := rng.randf() * TAU
	match kind:
		"oil":
			var items: Array = []
			for i in 2:
				var a := base + PI * i + rng.randf_range(-0.4, 0.4)
				var d := rng.randf_range(ring.x + 0.4 * CELL, ring.y + 0.3 * CELL)
				items.append({"pos": Vector2.from_angle(a) * d, "r": OIL_R})
			return {"kind": "oil", "items": items}
		"bolt":
			var items2: Array = []
			for i in 3:
				var a2 := base + TAU * i / 3.0 + rng.randf_range(-0.25, 0.25)
				var d2 := rng.randf_range(ring.x + 0.3 * CELL, ring.y)
				items2.append({"pos": Vector2.from_angle(a2) * d2, "r": BOLT_R})
			return {"kind": "bolt", "items": items2}
		"belt":
			var dir := Vector2.from_angle(base)
			var off := rng.randf_range(-0.8, 0.8) * CELL
			var p0 := dir.orthogonal() * off
			return {"kind": "belt", "items": [{"pos": p0, "dir": dir if rng.randf() < 0.5 else -dir}]}
	return {"kind": kind, "items": []}


static func has(w, kind: String) -> bool:
	for g in w.gimmicks:
		if g["kind"] == kind:
			return true
	return false


## 마찰 배율 (기름 웅덩이)
static func friction_scale(w, p: Vector2) -> float:
	for g in w.gimmicks:
		if g["kind"] == "oil":
			for it in g["items"]:
				if p.distance_to(it["pos"]) < it["r"]:
					return OIL_FRICTION
	return 1.0


static func on_belt(it: Dictionary, p: Vector2) -> bool:
	var dir: Vector2 = it["dir"]
	return absf((p - it["pos"]).dot(dir.orthogonal())) < BELT_HALF


## 샷이 도는 동안 매 물리 단계: 컨베이어가 띠 위 알을 나르고, 기름 웅덩이를 지난 알에 원인을 남긴다.
static func before_move(w, dt: float) -> void:
	if w.shot == null:
		return
	for g in w.gimmicks:
		match g["kind"]:
			"belt":
				if w.shot.time > BELT_TIME:
					continue
				for it in g["items"]:
					var dir: Vector2 = it["dir"]
					for s in w.stones:
						if not s.alive or not on_belt(it, s.pos):
							continue
						var along: float = s.vel.dot(dir)
						if along < BELT_SPEED:
							s.vel += dir * (BELT_SPEED - along)
						if s.id != w.shot.stone_id:
							_mark(w, s, "gm_belt")
			"oil":
				for it2 in g["items"]:
					for s2 in w.stones:
						if s2.alive and s2.vel != Vector2.ZERO and s2.pos.distance_to(it2["pos"]) < it2["r"]:
							_mark(w, s2, "gm_oil")


## 범퍼 볼트: 정적 장애물. 다가오던 알을 반사하고 1.2배로 튕긴다.
static func collide(w) -> void:
	for g in w.gimmicks:
		if g["kind"] != "bolt":
			continue
		for it in g["items"]:
			var bp: Vector2 = it["pos"]
			var rr: float = w.STONE_R + float(it["r"])
			for s in w.stones:
				if not s.alive:
					continue
				var d: Vector2 = s.pos - bp
				var dist := d.length()
				if dist >= rr or dist < 0.0001:
					continue
				var nrm := d / dist
				s.pos = bp + nrm * rr
				var vn: float = s.vel.dot(nrm)
				if vn < 0.0:
					s.vel = (s.vel - 2.0 * vn * nrm) * BOLT_BOUNCE
					if s.vel.length() > w.MAX_SPEED:
						s.vel = s.vel.normalized() * w.MAX_SPEED
					w.emit({"t": "hit", "pos": bp + nrm * float(it["r"]), "strength": -vn * 2.0, "a": s.id, "b": s.id, "n": nrm, "gimmick": "bolt"})
					if w.shot != null:
						_mark(w, s, "gm_bolt")


static func _mark(w, s, part: String) -> void:
	if w.shot == null or not w.record_events:
		return
	s.cause = {"owner": w.shot.owner, "part": part}


## 바퀴가 바뀔 때: 컨베이어 방향이 뒤집힌다.
static func on_round(w) -> void:
	for g in w.gimmicks:
		if g["kind"] == "belt":
			for it in g["items"]:
				it["dir"] = -(it["dir"] as Vector2)


## 알을 놓을 수 있는지 (장애물과 0.5칸 이상)
static func blocks(w, p: Vector2, margin := 0.5 * CELL) -> bool:
	for g in w.gimmicks:
		if g["kind"] == "bolt":
			for it in g["items"]:
				if p.distance_to(it["pos"]) < w.STONE_R + float(it["r"]) + margin:
					return true
	return false
