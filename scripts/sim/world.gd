extends RefCounted
## 물리 세계: 알, 탄환, 판에 남는 장치.
## 화면과 무관하게 고정 간격(DT)으로 돌아가므로 결과가 항상 같고, 복제해서 미리 돌려볼 수 있다.
## 판의 중심은 (0, 0)이다.

const Parts = preload("res://scripts/sim/parts.gd")
const PartsDataRef = preload("res://scripts/sim/parts_data.gd")

const STONE_R := 22.0
const MAX_SPEED := 1120.0
const FRICTION := 950.0       # 고정 감속 px/s²
const DRAG := 0.35            # 속도에 비례하는 감속 1/s
const RESTITUTION := 0.6
const STOP_SPEED := 6.0
const DT := 1.0 / 120.0
const EDGE_ZONE := 44.0       # 판 끝 경고 띠(1칸). 낙하산이 여기서 작동한다
const BULLET_SPEED := 1500.0
const BULLET_R := 5.0
const RUBBER_R := 10.0
const MAX_SHOT_TIME := 14.0


class Stone:
	var id := 0
	var owner := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var alive := true
	var facing := 0.0
	var parts := {"weapon": "", "aux": "", "prop": ""}
	var magnet_side := 1      # 1 = 진행 방향 오른쪽, -1 = 왼쪽

	func copy() -> Stone:
		var s := Stone.new()
		s.id = id
		s.owner = owner
		s.pos = pos
		s.vel = vel
		s.alive = alive
		s.facing = facing
		s.parts = parts.duplicate()
		s.magnet_side = magnet_side
		return s


class Proj:
	var kind := "bullet"      # bullet | rubber
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius := 5.0
	var owner := 0
	var source := "weapon"    # weapon | decal | turret | reflect | spring
	var power := 0.0
	var ignore_id := -1
	var age := 0.0
	var alive := true
	var trail_from := Vector2.ZERO

	func copy() -> Proj:
		var p := Proj.new()
		p.kind = kind
		p.pos = pos
		p.vel = vel
		p.radius = radius
		p.owner = owner
		p.source = source
		p.power = power
		p.ignore_id = ignore_id
		p.age = age
		p.alive = alive
		p.trail_from = trail_from
		return p


class Device:
	var id := 0
	var kind := ""            # mirror | mine | bubble | turret
	var owner := 0
	var stone_id := -1        # 이 장치를 만든 알 (부품당 하나 유지용)
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT  # 거울의 법선, 포탑의 조준 방향
	var expires_round := -1   # 이 바퀴가 끝나면 사라짐. -1 = 만료 없음
	var armed := false
	var inside := {}          # 이미 닿아 있던 알 id (지뢰·방울)

	func copy() -> Device:
		var d := Device.new()
		d.id = id
		d.kind = kind
		d.owner = owner
		d.stone_id = stone_id
		d.pos = pos
		d.dir = dir
		d.expires_round = expires_round
		d.armed = armed
		d.inside = inside.duplicate()
		return d


class ShotCtx:
	var stone_id := -1
	var owner := -1
	var start := Vector2.ZERO
	var dir := Vector2.RIGHT
	var power := 0.0
	var time := 0.0
	var contacted := false
	var used := {}            # 이번 샷에 이미 작동한 부품
	var chute_used := {}      # 낙하산을 쓴 알 id
	var swapped := false
	var grip_id := -1
	var grip_timer := 0.0
	var grip_offset := Vector2.ZERO
	var reel_timer := 0.0
	var path: Array = []
	var path_clock := 0.0

	func copy() -> ShotCtx:
		var c := ShotCtx.new()
		c.stone_id = stone_id
		c.owner = owner
		c.start = start
		c.dir = dir
		c.power = power
		c.time = time
		c.contacted = contacted
		c.used = used.duplicate()
		c.chute_used = chute_used.duplicate()
		c.swapped = swapped
		c.grip_id = grip_id
		c.grip_timer = grip_timer
		c.grip_offset = grip_offset
		c.reel_timer = reel_timer
		c.path = path.duplicate()
		c.path_clock = path_clock
		return c


var shape := "circle"         # circle | square
var size := 340.0             # 원의 반지름 또는 정사각형 한 변의 절반
var stones: Array = []
var projs: Array = []
var devices: Array = []
var next_device_id := 1
var round_no := 1
var shot: ShotCtx = null
var record_events := true
var events: Array = []        # 화면 연출용 사건 목록. 화면이 읽고 비운다.
var knockouts: Array = []     # 이번 샷에 떨어진 알 {stone, owner}


func clone():
	var w = get_script().new()
	w.shape = shape
	w.size = size
	for s in stones:
		w.stones.append(s.copy())
	for p in projs:
		w.projs.append(p.copy())
	for d in devices:
		w.devices.append(d.copy())
	w.next_device_id = next_device_id
	w.round_no = round_no
	w.shot = shot.copy() if shot != null else null
	w.record_events = false
	return w


# ── 판 ───────────────────────────────────────────────────

func is_inside(p: Vector2) -> bool:
	if shape == "circle":
		return p.length() <= size
	return absf(p.x) <= size and absf(p.y) <= size


func edge_distance(p: Vector2) -> float:
	if shape == "circle":
		return size - p.length()
	return size - maxf(absf(p.x), absf(p.y))


func outward(p: Vector2) -> Vector2:
	if shape == "circle":
		return p.normalized() if p.length() > 0.001 else Vector2.RIGHT
	if absf(p.x) >= absf(p.y):
		return Vector2(signf(p.x) if p.x != 0.0 else 1.0, 0.0)
	return Vector2(0.0, signf(p.y))


## 판 안의 점 p에서 dir 방향으로 판 끝까지의 거리.
func ray_to_edge(p: Vector2, dir: Vector2) -> float:
	if shape == "circle":
		var b := p.dot(dir)
		var c := p.length_squared() - size * size
		var disc := b * b - c
		if disc < 0.0:
			return 0.0
		return maxf(0.0, -b + sqrt(disc))
	var best := INF
	if dir.x > 0.0001:
		best = minf(best, (size - p.x) / dir.x)
	elif dir.x < -0.0001:
		best = minf(best, (-size - p.x) / dir.x)
	if dir.y > 0.0001:
		best = minf(best, (size - p.y) / dir.y)
	elif dir.y < -0.0001:
		best = minf(best, (-size - p.y) / dir.y)
	return maxf(0.0, best)


# ── 조회 ─────────────────────────────────────────────────

func get_stone(id: int) -> Stone:
	for s in stones:
		if s.id == id:
			return s
	return null


func alive_stones_of(owner: int) -> Array:
	var out: Array = []
	for s in stones:
		if s.alive and s.owner == owner:
			out.append(s)
	return out


func shooter() -> Stone:
	if shot == null:
		return null
	return get_stone(shot.stone_id)


func emit(ev: Dictionary) -> void:
	if record_events:
		events.append(ev)


# ── 생성 ─────────────────────────────────────────────────

func add_stone(owner: int, pos: Vector2, facing: float) -> Stone:
	var s := Stone.new()
	s.id = stones.size()
	s.owner = owner
	s.pos = pos
	s.facing = facing
	stones.append(s)
	return s


func spawn_bullet(owner: int, pos: Vector2, dir: Vector2, power: float, source: String, ignore_id: int) -> void:
	var p := Proj.new()
	p.kind = "bullet"
	p.pos = pos
	p.trail_from = pos
	p.vel = dir.normalized() * BULLET_SPEED
	p.radius = BULLET_R
	p.owner = owner
	p.source = source
	p.power = power
	p.ignore_id = ignore_id
	projs.append(p)


func spawn_rubber(owner: int, pos: Vector2, dir: Vector2, speed: float, power: float, ignore_id: int) -> void:
	var p := Proj.new()
	p.kind = "rubber"
	p.pos = pos
	p.trail_from = pos
	p.vel = dir.normalized() * speed
	p.radius = RUBBER_R
	p.owner = owner
	p.source = "spring"
	p.power = power
	p.ignore_id = ignore_id
	projs.append(p)


## 같은 알이 같은 종류의 장치를 새로 놓으면 이전 것은 사라진다.
func place_device(kind: String, owner: int, stone_id: int, pos: Vector2, dir: Vector2, expires_round: int) -> Device:
	for d in devices.duplicate():
		if d.kind == kind and d.stone_id == stone_id:
			devices.erase(d)
	var d := Device.new()
	d.id = next_device_id
	next_device_id += 1
	d.kind = kind
	d.owner = owner
	d.stone_id = stone_id
	d.pos = pos
	d.dir = dir
	d.expires_round = expires_round
	devices.append(d)
	emit({"t": "device", "kind": kind, "pos": pos, "owner": owner})
	return d


## 바퀴가 바뀔 때 부른다. 기한이 지난 장치를 걷는다.
func expire_devices() -> void:
	for d in devices.duplicate():
		if d.expires_round >= 0 and d.expires_round < round_no:
			devices.erase(d)
			emit({"t": "expire", "kind": d.kind, "pos": d.pos, "owner": d.owner})


# ── 샷 ───────────────────────────────────────────────────

func launch(stone_id: int, dir: Vector2, power: float) -> void:
	var s := get_stone(stone_id)
	if s == null or not s.alive:
		return
	dir = dir.normalized()
	power = clampf(power, 0.05, 1.0)
	shot = ShotCtx.new()
	shot.stone_id = s.id
	shot.owner = s.owner
	shot.start = s.pos
	shot.dir = dir
	shot.power = power
	shot.path = [s.pos]
	knockouts.clear()
	s.vel = dir * MAX_SPEED * power
	s.facing = dir.angle()
	emit({"t": "launch", "pos": s.pos, "owner": s.owner, "power": power})
	# 지뢰·방울은 다음 샷부터 작동한다. 지금 닿아 있는 알은 떠날 때까지 무시.
	for d in devices:
		if d.kind == "mine" or d.kind == "bubble":
			if not d.armed:
				d.armed = true
				d.inside = {}
				for o in stones:
					if o.alive and o.pos.distance_to(d.pos) < STONE_R + _device_radius(d):
						d.inside[o.id] = true
	# 이 플레이어의 포탑이 함께 쏜다 (포탑 탄은 다른 부품을 다시 발동시키지 않는다).
	for d in devices.duplicate():
		if d.kind == "turret" and d.owner == s.owner:
			spawn_bullet(d.owner, d.pos + d.dir * 10.0, d.dir, PartsDataRef.num("copier", "power"), "turret", -1)
			emit({"t": "part", "part": "copier", "pos": d.pos, "owner": d.owner, "text": "포탑 발사"})
			devices.erase(d)
	Parts.on_launch(self, s)



## 샷이 끝났을 때(모든 움직임이 멈춘 뒤) 부른다.
func end_shot() -> void:
	if shot == null:
		return
	var s := shooter()
	if s != null and s.alive:
		Parts.on_stop(self, s)
	shot = null


func is_settled() -> bool:
	if not projs.is_empty():
		return false
	if shot != null and (shot.grip_timer > 0.0 or shot.reel_timer > 0.0):
		return false
	for s in stones:
		if s.alive and s.vel != Vector2.ZERO:
			return false
	return true


## 다 멈출 때까지 돌린다. 미리보기와 테스트용.
func run_until_settled(max_time := MAX_SHOT_TIME) -> void:
	var t := 0.0
	while not is_settled() and t < max_time:
		step()
		t += DT
	if not is_settled():
		force_stop()


func force_stop() -> void:
	projs.clear()
	for s in stones:
		s.vel = Vector2.ZERO
	if shot != null:
		shot.grip_timer = 0.0
		shot.reel_timer = 0.0


func step() -> void:
	var dt := DT
	if shot != null:
		shot.time += dt
		if shot.time > MAX_SHOT_TIME:
			force_stop()
			return
	_update_reel(dt)
	for s in stones:
		if not s.alive:
			continue
		var sp: float = s.vel.length()
		if sp > 0.0:
			var ns := sp - FRICTION * dt - sp * DRAG * dt
			if ns < STOP_SPEED:
				s.vel = Vector2.ZERO
			else:
				s.vel *= ns / sp
				s.pos += s.vel * dt
	_hold_grip(dt)
	_collide_stones()
	_check_parachutes()
	_update_projs(dt)
	_check_devices()
	_check_out()
	_record_path(dt)


# ── 내부 처리 ────────────────────────────────────────────

func _update_reel(dt: float) -> void:
	if shot == null or shot.reel_timer <= 0.0:
		return
	var s := shooter()
	if s == null or not s.alive:
		shot.reel_timer = 0.0
		return
	var to := shot.start - s.pos
	if to.length() < 24.0:
		shot.reel_timer = 0.0
		s.vel *= 0.3
		return
	var acc := PartsDataRef.num("reel", "accel")
	var cap := PartsDataRef.num("reel", "max_speed")
	s.vel += to.normalized() * acc * dt
	if s.vel.length() > cap:
		s.vel = s.vel.normalized() * cap
	shot.reel_timer -= dt


func _hold_grip(dt: float) -> void:
	if shot == null or shot.grip_timer <= 0.0:
		return
	var s := shooter()
	var t := get_stone(shot.grip_id)
	shot.grip_timer -= dt
	if s == null or t == null or not s.alive or not t.alive or s.vel == Vector2.ZERO or shot.grip_timer <= 0.0:
		shot.grip_timer = 0.0
		if t != null and s != null:
			t.vel = s.vel
		return
	t.pos = s.pos + shot.grip_offset * (STONE_R * 2.0 + 0.5)
	t.vel = s.vel


func _is_grip_pair(a: Stone, b: Stone) -> bool:
	if shot == null or shot.grip_timer <= 0.0:
		return false
	return (a.id == shot.stone_id and b.id == shot.grip_id) or (b.id == shot.stone_id and a.id == shot.grip_id)


func _collide_stones() -> void:
	var n := stones.size()
	var min_d := STONE_R * 2.0
	for i in n:
		var a: Stone = stones[i]
		if not a.alive:
			continue
		for j in range(i + 1, n):
			var b: Stone = stones[j]
			if not b.alive:
				continue
			if a.vel == Vector2.ZERO and b.vel == Vector2.ZERO:
				continue
			if _is_grip_pair(a, b):
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= min_d:
				continue
			var nrm := d / dist if dist > 0.0001 else Vector2.RIGHT
			var overlap := min_d - dist
			a.pos -= nrm * overlap * 0.5
			b.pos += nrm * overlap * 0.5
			var rel := (a.vel - b.vel).dot(nrm)
			if rel <= 0.0:
				continue
			var va := a.vel
			var vb := b.vel
			var imp := rel * (1.0 + RESTITUTION) * 0.5
			a.vel -= nrm * imp
			b.vel += nrm * imp
			emit({"t": "hit", "pos": a.pos + nrm * STONE_R, "strength": rel})
			if shot != null:
				if a.id == shot.stone_id:
					Parts.on_contact(self, a, b, nrm, va)
				elif b.id == shot.stone_id:
					Parts.on_contact(self, b, a, -nrm, vb)


func _check_parachutes() -> void:
	if shot == null:
		return
	for s in stones:
		if not s.alive or s.parts["prop"] != "chute" or s.vel == Vector2.ZERO:
			continue
		if shot.chute_used.has(s.id):
			continue
		if edge_distance(s.pos) < EDGE_ZONE and s.vel.dot(outward(s.pos)) > 0.0:
			shot.chute_used[s.id] = true
			var sp: float = s.vel.length()
			var ns := maxf(0.0, sp - PartsDataRef.num("chute", "power"))
			s.vel = s.vel * (ns / sp) if ns > STOP_SPEED else Vector2.ZERO
			emit({"t": "part", "part": "chute", "pos": s.pos, "owner": s.owner, "text": "낙하산"})


func _update_projs(dt: float) -> void:
	for p in projs:
		if not p.alive:
			continue
		p.age += dt
		var prev: Vector2 = p.pos
		p.trail_from = prev
		if p.kind == "rubber":
			var sp: float = p.vel.length()
			var ns := sp - FRICTION * dt
			if ns < 40.0:
				p.alive = false
				continue
			p.vel *= ns / sp
		p.pos += p.vel * dt
		# 거울 반사
		if p.kind == "bullet":
			for d in devices:
				if d.kind != "mirror":
					continue
				var half := PartsDataRef.num("umbrella", "half_len")
				var along: Vector2 = d.dir.orthogonal()
				var m_a: Vector2 = d.pos - along * half
				var m_b: Vector2 = d.pos + along * half
				var hit = Geometry2D.segment_intersects_segment(prev, p.pos, m_a, m_b)
				if hit != null:
					var nrm: Vector2 = d.dir
					p.vel = p.vel - 2.0 * p.vel.dot(nrm) * nrm
					p.pos = hit + p.vel.normalized() * 2.0
					p.source = "reflect"
					p.ignore_id = -1
					emit({"t": "reflect", "pos": hit, "owner": d.owner})
					devices.erase(d)
					break
		# 알 맞힘
		for s in stones:
			if not s.alive:
				continue
			if s.id == p.ignore_id and p.age < 0.15:
				continue
			if s.pos.distance_to(p.pos) < STONE_R + p.radius:
				s.vel += p.vel.normalized() * p.power
				p.alive = false
				emit({"t": "bullet_hit", "pos": p.pos, "owner": p.owner, "target": s.owner, "source": p.source})
				break
		if p.alive and (not _inside_margin(p.pos, 80.0) or p.age > 2.5):
			p.alive = false
	projs = projs.filter(func(q): return q.alive)


func _inside_margin(p: Vector2, margin: float) -> bool:
	if shape == "circle":
		return p.length() <= size + margin
	return absf(p.x) <= size + margin and absf(p.y) <= size + margin


func _device_radius(d: Device) -> float:
	if d.kind == "mine":
		return PartsDataRef.num("mine", "radius")
	if d.kind == "bubble":
		return PartsDataRef.num("bubble", "radius")
	return 0.0


func _check_devices() -> void:
	for d in devices.duplicate():
		if not d.armed:
			continue
		var r := STONE_R + _device_radius(d)
		var touching: Stone = null
		var now_inside := {}
		for s in stones:
			if not s.alive:
				continue
			if s.pos.distance_to(d.pos) < r:
				now_inside[s.id] = true
				if not d.inside.has(s.id) and touching == null:
					touching = s
		d.inside = now_inside
		if touching == null:
			continue
		if d.kind == "mine":
			_explode(d)
		elif d.kind == "bubble":
			var perp := touching.vel.orthogonal().normalized()
			if perp == Vector2.ZERO:
				perp = (touching.pos - d.pos).normalized()
			elif perp.dot(touching.pos - d.pos) < 0.0:
				perp = -perp
			touching.vel += perp * PartsDataRef.num("bubble", "power")
			emit({"t": "part", "part": "bubble", "pos": d.pos, "owner": d.owner, "text": "방울 톡!"})
			devices.erase(d)


func _explode(d: Device) -> void:
	var blast := PartsDataRef.num("mine", "blast")
	var power := PartsDataRef.num("mine", "power")
	for s in stones:
		if not s.alive:
			continue
		var off: Vector2 = s.pos - d.pos
		var dist := off.length()
		if dist > blast:
			continue
		var dirv := off / dist if dist > 0.5 else Vector2.UP
		s.vel += dirv * (220.0 + power * (1.0 - dist / blast))
	emit({"t": "boom", "pos": d.pos, "owner": d.owner, "radius": blast})
	devices.erase(d)


func _check_out() -> void:
	for s in stones:
		if s.alive and not is_inside(s.pos):
			s.alive = false
			s.vel = Vector2.ZERO
			knockouts.append({"stone": s.id, "owner": s.owner})
			emit({"t": "out", "pos": s.pos, "owner": s.owner})
			if shot != null and (shot.grip_id == s.id or shot.stone_id == s.id):
				shot.grip_timer = 0.0
			if shot != null and shot.stone_id == s.id:
				shot.reel_timer = 0.0


func _record_path(dt: float) -> void:
	if shot == null:
		return
	var s := shooter()
	if s == null or not s.alive or s.vel == Vector2.ZERO:
		return
	shot.path_clock += dt
	if shot.path_clock >= 0.04:
		shot.path_clock = 0.0
		shot.path.append(s.pos)
