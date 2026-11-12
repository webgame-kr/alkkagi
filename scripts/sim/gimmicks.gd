extends RefCounted
## 맵 기믹 (확장 기획 「맵 기믹」). 판을 시작할 때 공방의 기믹 중 1개(5~8인은 2개)를 꺼내 놓는다.
## 기믹은 누구의 것도 아니다. 기믹 때문에 떨어진 알은 「기믹 이름 · 쏜 사람의 샷」으로 적는다.
## 모든 계산은 결정적이다 (온라인에서 같은 시드면 같은 판).

const CELL := 44.0
const TIME_K := 2.5          # parts.gd 와 같은 시간 배율 (사양의 초당 값 × 2.5)

## 공방별 기믹 3종
const BY_WORKSHOP := {
	"junk": ["oil", "bolt", "belt"],
	"magic": ["gwell", "twins", "meteor"],
	"toon": ["cutline", "blocks", "nextch"],
	"lab": ["zerog", "sizering", "turntable"],
	"clock": ["pendulum", "cuckoo", "clockhand"],
}

const INFO := {
	"oil": {"name": "기름 웅덩이", "desc": "안에서는 마찰이 30%로 줄어 훨씬 멀리 미끄러져요"},
	"bolt": {"name": "범퍼 볼트", "desc": "움직이지 않는 볼트. 부딪힌 알을 120% 속도로 튕겨 내요"},
	"belt": {"name": "컨베이어 띠", "desc": "띠 위의 알은 화살표 쪽으로 실려 가요. 바퀴마다 방향이 뒤집혀요"},
	"gwell": {"name": "중력 우물", "desc": "범위 안을 지나는 알의 진행 방향이 우물 중심 쪽으로 휘어요"},
	"twins": {"name": "쌍둥이 마법진", "desc": "한쪽에 들어간 알은 다른 쪽에서 같은 속도와 방향으로 나와요"},
	"meteor": {"name": "별똥별 표식", "desc": "바퀴가 끝날 때 붉은 원 안의 알을 바깥쪽으로 3칸 밀어내요"},
	"cutline": {"name": "컷 경계선", "desc": "집중선 쪽으로 넘으면 1.5배 빨라지고, 반대로 넘으면 0.7배로 느려져요"},
	"blocks": {"name": "효과음 블록", "desc": "움직이지 않는 글자 블록. 두 번 맞으면 부서져요"},
	"nextch": {"name": "다음 화 테두리", "desc": "이 구간으로 넘어간 알은 반대편에서 다시 들어와요 (알마다 한 번)"},
	"zerog": {"name": "무중력 구역", "desc": "안에서는 마찰이 없어 속도가 줄지 않아요"},
	"sizering": {"name": "크기 변환 링", "desc": "파란 링을 지나면 작아지고, 빨간 링을 지나면 커져요 (바퀴가 끝날 때까지)"},
	"pendulum": {"name": "흔들 진자", "desc": "차례가 끝날 때마다 추가 좌우 끝을 오가며 지나는 길의 알을 밀어내요. 다음 자리는 점선"},
	"cuckoo": {"name": "뻐꾸기 시계", "desc": "3·5바퀴 시작에 판 위 모든 알을 가리키는 방향으로 1칸 밀어요. 한 바퀴 전부터 화살표로 예고"},
	"clockhand": {"name": "시곗바늘 막대", "desc": "차례가 끝날 때마다 30도씩 돌며 쓸고 지나간 자리의 알을 밀어내요"},
	"turntable": {"name": "회전 원판", "desc": "샷이 끝날 때마다 가운데 원판이 45도 돌고, 위의 알도 함께 돌아요"},
}

const OIL_R := 1.5 * CELL
const OIL_FRICTION := 0.3
const BOLT_R := 0.4 * CELL
const BOLT_BOUNCE := 1.2
const BELT_HALF := 0.75 * CELL
const BELT_SPEED := 1.5 * CELL * TIME_K
const BELT_TIME := 0.8        # 샷마다 띠가 알을 나르는 시간 (초, 판 시간)
const WELL_R := 2.5 * CELL    # 중력 우물 영향 범위 (지름 5칸)
const WELL_TURN := 3.2        # 초당 휘는 각 (rad, 판 시간)
const TWIN_R := 0.7 * CELL
const METEOR_R := 1.5 * CELL
const METEOR_PUSH := 3.0 * CELL
const BLOCK_R := 0.75 * CELL
const NEXT_HALF := PI / 6.0   # 60도 구간


static func name_of(kind: String) -> String:
	return INFO.get(kind, {}).get("name", kind)


## 판 시작 때 기믹을 고르고 놓는다. 반환: [{kind, items:[...]}]
static func generate(ws: String, n_players: int, w, rng: RandomNumberGenerator) -> Array:
	var kinds: Array = BY_WORKSHOP.get(ws, []).duplicate()
	if not w.parcel.is_empty():
		# 택배 쟁탈전: 목표물 처리까지 달라지는 기믹은 뺀다 (크기 변환·회전 원판·다음 화 예고)
		for k0 in ["sizering", "turntable", "nextch"]:
			kinds.erase(k0)
	if kinds.is_empty():
		return []
	var count := 1 if n_players <= 4 else 2
	var out: Array = []
	for i in mini(count, kinds.size()):
		var k := rng.randi_range(0, kinds.size() - 1)
		var kind: String = kinds[k]
		kinds.remove_at(k)
		out.append(_keep_out_of_zones(_place(kind, w, rng), w))
	return out


## 시작 구역(가장자리에서 6.5칸 안쪽까지)에 걸치지 않게 안쪽으로 당긴다.
static func _keep_out_of_zones(g: Dictionary, w) -> Dictionary:
	if g["kind"] == "meteor" or g["kind"] == "turntable":
		return g
	for it in g["items"]:
		if not it.has("pos"):
			continue
		var p: Vector2 = it["pos"]
		var r: float = float(it.get("r", 0.0))
		if g["kind"] == "gwell":
			r = 0.6 * CELL   # 우물은 가운데 몸통만 (끌어당기는 범위는 넓게 걸쳐도 된다)
		var lim: float = maxf(1.05 * CELL, w.size - 6.6 * CELL - r)   # 판 중심 1칸 안은 계속 피한다
		if p.length() > lim:
			it["pos"] = p.normalized() * lim if p.length() > 0.001 else p
		# 왕관 쟁탈전: 가운데 왕관 자리는 비워 둔다
		if not w.crown.is_empty() or not w.parcel.is_empty():
			var need: float = 2.0 * CELL + r * 0.6
			var q: Vector2 = it["pos"]
			if q.length() < need:
				it["pos"] = (q.normalized() if q.length() > 0.001 else Vector2.RIGHT) * need
	return g


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
		"gwell":
			var d3 := rng.randf_range(ring.x, ring.y)
			return {"kind": "gwell", "items": [{"pos": Vector2.from_angle(base) * d3, "r": WELL_R}]}
		"twins":
			var d4 := rng.randf_range(ring.x + 0.3 * CELL, ring.y + 0.3 * CELL)
			return {"kind": "twins", "items": [{"pos": Vector2.from_angle(base) * d4, "r": TWIN_R}, {"pos": Vector2.from_angle(base + PI + rng.randf_range(-0.5, 0.5)) * d4, "r": TWIN_R}]}
		"meteor":
			return {"kind": "meteor", "items": [{"pos": _meteor_spot(w, rng.randi()), "r": METEOR_R}], "seed": rng.randi(), "hits": []}
		"cutline":
			var nrm := Vector2.from_angle(base)
			return {"kind": "cutline", "items": [{"pos": nrm * rng.randf_range(-0.6, 0.6) * CELL, "n": nrm}]}
		"blocks":
			var items5: Array = []
			var words := ["쾅", "펑"]
			for i in 2:
				var a5 := base + PI * i + rng.randf_range(-0.4, 0.4)
				var d5 := rng.randf_range(ring.x + 0.4 * CELL, ring.y)
				items5.append({"pos": Vector2.from_angle(a5) * d5, "r": BLOCK_R, "hp": 2, "word": words[i]})
			return {"kind": "blocks", "items": items5}
		"nextch":
			return {"kind": "nextch", "items": [{"ang": base, "half": NEXT_HALF}], "used": []}
		"zerog":
			var d6 := rng.randf_range(ring.x, ring.y)
			return {"kind": "zerog", "items": [{"pos": Vector2.from_angle(base) * d6, "r": 2.0 * CELL}]}
		"sizering":
			var d7 := rng.randf_range(ring.x + 0.3 * CELL, ring.y + 0.3 * CELL)
			return {"kind": "sizering", "items": [{"pos": Vector2.from_angle(base) * d7, "r": 0.8 * CELL, "big": false}, {"pos": Vector2.from_angle(base + PI) * d7, "r": 0.8 * CELL, "big": true}]}
		"turntable":
			return {"kind": "turntable", "items": [{"pos": Vector2.ZERO, "r": 3.0 * CELL, "ang": 0.0}]}
		"pendulum":
			var c0 := Vector2.from_angle(base) * rng.randf_range(0.0, 1.2) * CELL
			var half := maxf(1.6 * CELL, w.size - 6.8 * CELL)
			var ax := Vector2.from_angle(base).orthogonal()
			return {"kind": "pendulum", "items": [{"a": c0 - ax * half, "b": c0 + ax * half, "at": 0, "r": 0.75 * CELL}]}
		"cuckoo":
			return {"kind": "cuckoo", "items": [], "dir": snappedf(base, PI / 4.0)}
		"clockhand":
			return {"kind": "clockhand", "items": [{"ang": base, "len": maxf(2.0 * CELL, w.size - 3.0 * CELL)}]}
	return {"kind": kind, "items": []}


static func has(w, kind: String) -> bool:
	for g in w.gimmicks:
		if g["kind"] == kind:
			return true
	return false


## 마찰 배율 (기름 웅덩이)
static func friction_scale(w, p: Vector2) -> float:
	for g in w.gimmicks:
		if g["kind"] == "zerog":
			for it in g["items"]:
				if p.distance_to(it["pos"]) < it["r"]:
					return 0.0
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
			"sizering":
				for it in g["items"]:
					for s in w.stones:
						if s.alive and s.vel != Vector2.ZERO and s.pos.distance_to(it["pos"]) < float(it["r"]) * 0.6:
							var key := "ring_big" if it["big"] else "ring_small"
							if not s.mods.has(key):
								s.mods.erase("ring_small" if it["big"] else "ring_big")
								s.mods[key] = {"size": 1.3 if it["big"] else 0.7, "mass": 1.3 if it["big"] else 0.7, "until": w.round_no}
								w.emit({"t": "part", "part": "gm_sizering", "pos": s.pos, "owner": s.owner, "text": "커졌다!" if it["big"] else "작아졌다!"})
			"gwell":
				for it in g["items"]:
					for s in w.stones:
						if not s.alive or s.vel == Vector2.ZERO:
							continue
						var to: Vector2 = it["pos"] - s.pos
						if to.length() < it["r"] and to.length() > 4.0:
							var diff := angle_difference(s.vel.angle(), to.angle())
							s.vel = s.vel.rotated(clampf(diff, -WELL_TURN * dt, WELL_TURN * dt))
							_mark(w, s, "gm_gwell")
			"twins":
				var its: Array = g["items"]
				for s2 in w.stones:
					if not s2.alive or s2.vel == Vector2.ZERO:
						continue
					var key := "twin:%d" % s2.id
					if w.shot.used.has(key):
						continue
					for k in 2:
						if s2.pos.distance_to(its[k]["pos"]) < float(its[k]["r"]) * 0.8:
							var outp: Vector2 = its[1 - k]["pos"] + s2.vel.normalized() * (float(its[k]["r"]) + w.STONE_R + 2.0)
							if w.is_inside(outp):
								w.shot.used[key] = 1
								var from: Vector2 = s2.pos
								s2.pos = outp
								_mark(w, s2, "gm_twins")
								w.emit({"t": "part", "part": "gm_twins", "pos": outp, "owner": w.shot.owner, "text": "쌍둥이 마법진", "from": from})
							break
			"cutline":
				for it3 in g["items"]:
					var n3: Vector2 = it3["n"]
					for s3 in w.stones:
						if not s3.alive or s3.vel == Vector2.ZERO:
							continue
						var now: float = (s3.pos - it3["pos"]).dot(n3)
						var nxt: float = (s3.pos + s3.vel * dt - it3["pos"]).dot(n3)
						if signf(now) != signf(nxt) and now != 0.0:
							s3.vel *= 1.5 if nxt > 0.0 else 0.7
							if s3.vel.length() > w.MAX_SPEED:
								s3.vel = s3.vel.normalized() * w.MAX_SPEED
							_mark(w, s3, "gm_cutline")
							w.emit({"t": "part", "part": "gm_cutline", "pos": s3.pos, "owner": w.shot.owner, "text": "슈욱!" if nxt > 0.0 else "끼익"})
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


## 범퍼 볼트 · 효과음 블록: 정적 장애물. 볼트는 1.2배로 튕기고, 블록은 두 번 맞으면 부서진다.
static func collide(w) -> void:
	for g in w.gimmicks:
		if g["kind"] == "blocks":
			_collide_blocks(w, g)
			continue
		if g["kind"] != "bolt":
			continue
		for it in g["items"]:
			var bp: Vector2 = it["pos"]
			for s in w.stones:
				if not s.alive:
					continue
				var rr: float = w.radius_of(s) + float(it["r"])
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
		if g["kind"] == "bolt" or g["kind"] == "blocks":
			for it in g["items"]:
				if p.distance_to(it["pos"]) < w.STONE_R + float(it["r"]) + margin:
					return true
	return false



static func _collide_blocks(w, g: Dictionary) -> void:
	for it in g["items"].duplicate():
		var bp: Vector2 = it["pos"]
		for s in w.stones:
			if not s.alive:
				continue
			var rr: float = w.radius_of(s) + float(it["r"])
			var d: Vector2 = s.pos - bp
			var dist := d.length()
			if dist >= rr or dist < 0.0001:
				continue
			var nrm := d / dist
			s.pos = bp + nrm * rr
			var vn: float = s.vel.dot(nrm)
			if vn < 0.0:
				s.vel = (s.vel - 2.0 * vn * nrm) * 0.85
				it["hp"] = int(it["hp"]) - 1
				w.emit({"t": "hit", "pos": bp + nrm * float(it["r"]), "strength": -vn * 1.5, "a": s.id, "b": s.id, "n": nrm, "gimmick": "blocks"})
				_mark(w, s, "gm_blocks")
				if int(it["hp"]) <= 0:
					g["items"].erase(it)
					w.emit({"t": "part", "part": "gm_blocks", "pos": bp, "owner": w.shot.owner if w.shot != null else -1, "text": str(it["word"]) + "! 와장창", "big": true})
					break


## 다음 화 테두리: 이 구간으로 넘어간 알은 반대편에서 다시 들어온다 (판마다 알 하나에 한 번).
static func save_from_edge(w, s) -> bool:
	for g in w.gimmicks:
		if g["kind"] != "nextch":
			continue
		if g["used"].has(s.id):
			continue
		for it in g["items"]:
			if absf(angle_difference(s.pos.angle(), float(it["ang"]))) <= float(it["half"]):
				g["used"].append(s.id)
				var from: Vector2 = s.pos
				var back: Vector2 = -s.pos.normalized()
				s.pos = back * (w.size - w.STONE_R - 6.0) if w.shape == "circle" else -s.pos * 0.9
				if w.record_events:
					w.emit({"t": "part", "part": "gm_nextch", "pos": s.pos, "owner": s.owner, "text": "다음 화에 계속!", "from": from, "big": true})
				return true
	return false


## 별똥별 표식: 판 위 무작위 자리 (시작 구역 제외).
static func _meteor_spot(w, seed_v: int) -> Vector2:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var ring := _ring(w)
	return Vector2.from_angle(r.randf() * TAU) * r.randf_range(ring.x, ring.y + 1.0 * CELL)


## 바퀴가 끝날 때: 별똥별이 떨어져 원 안의 알을 바깥쪽으로 민다. 판 밖으로 나간 알 목록을 돌려준다.
static func meteor_fall(w, round_no: int) -> Array:
	var fallen: Array = []
	for g in w.gimmicks:
		if g["kind"] != "meteor":
			continue
		for it in g["items"]:
			var c: Vector2 = it["pos"]
			for s in w.stones:
				if not s.alive or s.pos.distance_to(c) > float(it["r"]) + w.STONE_R * 0.5:
					continue
				var away: Vector2 = (s.pos - c).normalized() if s.pos.distance_to(c) > 1.0 else s.pos.normalized()
				s.pos += away * METEOR_PUSH
				if not w.is_inside(s.pos) and not save_from_edge(w, s):
					s.alive = false
					fallen.append(s)
					w.emit({"t": "out", "pos": s.pos, "owner": s.owner, "cause": {"part": "gm_meteor"}, "stone": s.id})
			g["hits"] = [{"pos": c, "round": round_no}]
			it["pos"] = _meteor_spot(w, int(g["seed"]) + round_no * 97)
	return fallen



## 샷이 끝날 때: 회전 원판이 45도 돌고 위의 알도 함께 돈다.
static func after_shot(w) -> void:
	for g in w.gimmicks:
		if g["kind"] != "turntable":
			continue
		for it in g["items"]:
			it["ang"] = float(it["ang"]) + PI / 4.0
			for s in w.stones:
				if s.alive and s.pos.distance_to(it["pos"]) < float(it["r"]):
					s.pos = it["pos"] + (s.pos - it["pos"]).rotated(PI / 4.0)
					s.facing += PI / 4.0
			for d in w.devices:
				if d.pos.distance_to(it["pos"]) < float(it["r"]):
					d.pos = it["pos"] + (d.pos - it["pos"]).rotated(PI / 4.0)
