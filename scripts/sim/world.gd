extends RefCounted
## 물리 세계: 알, 탄환, 판에 남는 장치.
## 화면과 무관하게 고정 간격(DT)으로 돌아가므로 결과가 항상 같고, 복제해서 미리 돌려볼 수 있다.
## 판의 중심은 (0, 0)이다.

const Parts = preload("res://scripts/sim/parts.gd")
const PartsDataRef = preload("res://scripts/sim/parts_data.gd")
const Ex = preload("res://scripts/sim/expansion.gd")
const Gm = preload("res://scripts/sim/gimmicks.gd")

const STONE_R := 22.0
const MAX_SPEED := Parts.LAUNCH_V
const FRICTION := Parts.FRICTION   # 고정 감속 px/s²
const DRAG := Parts.DRAG           # 속도에 비례하는 감속 1/s
const RESTITUTION := 0.7         # 사양 0.9 → 템포 조정 (4인 평균 약 6.7바퀴)
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
	var magnet_side := 1      # 보조 좌우(자석팔·딱지 방패): 1 = 진행 방향 오른쪽, -1 = 왼쪽
	var prop_side := 1        # 추진 좌우(게걸음 바퀴, 옆구리 주문서)
	var status := {}          # 다음 발사까지 남는 상태: sealed(봉인된 슬롯), cursed(저주 건 플레이어)
	var cause := {}           # 이번 샷에 이 알을 마지막으로 민 원인 {owner, part, chain} (탈락 원인 표시)
	var ups := {}             # 강화(★)된 슬롯 {slot: true}. 그 슬롯 부품이 바뀌면 사라진다

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
		s.prop_side = prop_side
		s.status = status.duplicate()
		s.ups = ups.duplicate()
		return s


class Proj:
	var kind := "bullet"      # bullet | rubber | sucker | umbrella
	var travelled := 0.0
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
		p.travelled = travelled
		return p


class Device:
	var id := 0
	var kind := ""            # mirror | mine | bubble | turret | slick | groove
	var length := 0.0         # 띠·홈의 길이 (pos 에서 dir 방향으로), 장치별 보조 값
	var expires_shot := -1    # 이 샷이 끝나면 사라짐 (shot_no 기준). -1 = 없음
	var scale := 1.0          # 강화(★)된 부품이 만든 장치의 배율 (범위·발수)
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
		d.length = length
		d.expires_shot = expires_shot
		d.scale = scale
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
	var sucker := {}          # 빨판이 붙은 알 id: 다음에 움직이면 한 번 감속
	var shield_used := {}     # 딱지 방패를 쓴 알 id
	var clock_timer := -1.0   # 딸깍 태엽 가속까지 남은 시간
	var brake_armed := false  # 도장 브레이크: 기준 속도를 넘었었는지
	var ex := {}              # 확장 부품의 이번 샷 상태 (expansion.gd)

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
		c.sucker = sucker.duplicate()
		c.shield_used = shield_used.duplicate()
		c.clock_timer = clock_timer
		c.brake_armed = brake_armed
		c.ex = ex.duplicate(true)
		return c


var shape := "circle"         # circle | square
var size := 340.0             # 원의 반지름 또는 정사각형 한 변의 절반
var stones: Array = []
var projs: Array = []
var devices: Array = []
var gimmicks: Array = []      # 맵 기믹 (gimmicks.gd)
var next_device_id := 1
var round_no := 1
var shot: ShotCtx = null
var record_events := true
var events: Array = []        # 화면 연출용 사건 목록. 화면이 읽고 비운다.
var knockouts: Array = []     # 이번 샷에 떨어진 알 {stone, owner}
var shot_no := 0              # 지금까지 쏜 횟수 (샷 단위로 사라지는 장치용)
var relics: Array = []        # 유품 리본으로 회수한 부품 {owner, part}. 경기 관리가 가져간다.


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
	w.gimmicks = gimmicks.duplicate(true)
	w.next_device_id = next_device_id
	w.round_no = round_no
	w.shot_no = shot_no
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


## 부품이 다른 알을 민 사건이면, 그 알에 원인을 적는다 (탈락 원인 표시용).
const TARGETING := ["hook", "magnet", "flipper", "nose", "claw", "carousel", "bumper", "trex_head", "trex_arm",
	"mecha", "stamp", "sucker", "shadow_scale", "moon_set", "star_cloak", "mushroom", "trap_card", "wind_knot",
	"moon_well", "night_charm", "rubber_fist", "string_doll", "moon_staff", "bubble", "track", "log_sub"]
const AREA := {"boom": "mine", "umbrella": "umbrella_gun", "beam": "charge_palm", "hexbreak": "at_field", "cone": "hero_band"}


func emit(ev: Dictionary) -> void:
	if record_events:
		events.append(ev)
		_note_cause(ev)


func _note_cause(ev: Dictionary) -> void:
	if shot == null:
		return
	var t: String = ev.get("t", "")
	var owner: int = ev.get("owner", shot.owner)
	if t == "part" and TARGETING.has(ev.get("part", "")):
		var tgt := _nearest_other(ev["pos"], STONE_R * 3.0)
		if tgt != null:
			tgt.cause = {"owner": owner, "part": ev["part"]}
	elif t == "bullet_hit":
		var tgt2 := _nearest_other(ev["pos"], STONE_R + 12.0, false)
		if tgt2 != null:
			var part := "pea"
			match str(ev.get("source", "weapon")):
				"decal":
					part = "decal"
				"turret":
					part = "copier"
				"reflect":
					part = "umbrella"
				"deflect":
					part = "shield"
				_:
					var sh := shooter()
					if sh != null and sh.parts["weapon"] != "":
						part = sh.parts["weapon"]
			tgt2.cause = {"owner": owner, "part": part}
	elif AREA.has(t) or t == "ripple":
		var part2: String = AREA.get(t, "tambourine")
		var c: Vector2 = ev.get("pos", ev.get("a", Vector2.ZERO))
		var rr: float = ev.get("radius", 160.0)
		for o in stones:
			if o.alive and o.id != shot.stone_id and o.pos.distance_to(c) < rr + STONE_R:
				o.cause = {"owner": owner, "part": part2}


func _nearest_other(p: Vector2, range_len: float, skip_shooter := true) -> Stone:
	var best: Stone = null
	var bd := range_len
	for o in stones:
		if not o.alive or (skip_shooter and shot != null and o.id == shot.stone_id):
			continue
		var d: float = o.pos.distance_to(p)
		if d < bd:
			bd = d
			best = o
	return best


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


func spawn_proj(kind: String, owner: int, pos: Vector2, dir: Vector2, speed: float, radius: float, power: float, ignore_id: int) -> void:
	var p := Proj.new()
	p.kind = kind
	p.pos = pos
	p.trail_from = pos
	p.vel = dir.normalized() * speed
	p.radius = radius
	p.owner = owner
	p.source = kind
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

func launch(stone_id: int, dir: Vector2, power: float, opts := {}) -> void:
	var s := get_stone(stone_id)
	if s == null or not s.alive:
		return
	dir = dir.normalized()
	power = clampf(power, 0.0, 1.0)
	shot = ShotCtx.new()
	shot.stone_id = s.id
	shot.owner = s.owner
	shot.start = s.pos
	shot.dir = dir
	shot.power = power
	shot.path = [s.pos]
	shot_no += 1
	knockouts.clear()
	for o in stones:
		o.cause = {}
	s.vel = dir * Parts.launch_speed(power) * (0.75 if int(s.status.get("slow", -1)) >= round_no else 1.0)
	s.facing = dir.angle()
	emit({"t": "launch", "pos": s.pos, "owner": s.owner, "power": power})
	# 지뢰·방울은 다음 샷부터 작동한다. 지금 닿아 있는 알은 떠날 때까지 무시.
	for d in devices:
		if d.kind == "mine" or d.kind == "bubble" or d.kind == "groove":
			if not d.armed:
				d.armed = true
				d.inside = {}
				for o in stones:
					var on: bool = o.pos.distance_to(d.pos) < STONE_R + _device_radius(d)
					if d.kind == "groove":
						on = _on_strip(d, o.pos, STONE_R * 0.6)
					if o.alive and on:
						d.inside[o.id] = true
	Ex.arm_devices(self)
	Ex.on_launch_pre(self, s, opts)
	# 이 플레이어의 포탑이 함께 쏜다 (포탑 탄은 다른 부품을 다시 발동시키지 않는다).
	for d in devices.duplicate():
		if d.kind == "turret" and d.owner == s.owner:
			spawn_bullet(d.owner, d.pos + d.dir * 10.0, d.dir, PartsDataRef.num("copier", "power"), "turret", -1)
			if d.scale >= 2.0:
				spawn_bullet(d.owner, d.pos - d.dir * 8.0, d.dir, PartsDataRef.num("copier", "power"), "turret", -1)
			emit({"t": "part", "part": "copier", "pos": d.pos, "owner": d.owner, "text": "포탑 발사"})
			devices.erase(d)
	Parts.on_launch(self, s)
	Ex.on_launch(self, s)


## 구름 우편함: 표식 자리가 비어 있으면 그 알을 그리로 옮긴다 (발사 직전).
func move_to_cloud(stone_id: int) -> bool:
	var s := get_stone(stone_id)
	if s == null:
		return false
	for d in devices:
		if d.kind == "cloud" and d.stone_id == stone_id:
			for o in stones:
				if o.alive and o.id != s.id and o.pos.distance_to(d.pos) < STONE_R * 2.0:
					return false
			s.pos = d.pos
			return true
	return false


func cloud_of(stone_id: int):
	for d in devices:
		if d.kind == "cloud" and d.stone_id == stone_id:
			return d
	return null



## 샷이 끝났을 때(모든 움직임이 멈춘 뒤) 부른다.
func end_shot() -> void:
	if shot == null:
		return
	var s := shooter()
	if s != null and s.alive:
		Parts.on_stop(self, s)
	Ex.on_end(self, s)
	shot = null


func is_settled() -> bool:
	if not projs.is_empty():
		return false
	if shot != null and (shot.grip_timer > 0.0 or shot.reel_timer > 0.0 or shot.clock_timer > 0.0):
		return false
	if Ex.busy(self):
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
		shot.clock_timer = -1.0
		shot.ex.erase("beam_timer")
		shot.ex.erase("echo")
		shot.ex.erase("freeze_t")
		shot.ex["retracing"] = false


func step() -> void:
	var dt := DT
	if shot != null:
		shot.time += dt
		if shot.time > MAX_SHOT_TIME:
			force_stop()
			return
	_update_reel(dt)
	_update_shot_timers(dt)
	Ex.timers(self, dt)
	Ex.before_move(self, dt)
	Gm.before_move(self, dt)
	for s in stones:
		if not s.alive or Ex.is_frozen(self, s):
			continue
		var sp: float = s.vel.length()
		if sp > 0.0:
			var gk := Gm.friction_scale(self, s.pos)
			var fr := FRICTION * _friction_scale(s.pos) * Ex.friction_scale(self, s.pos) * gk
			var ns := sp - fr * dt - sp * DRAG * gk * dt
			if ns < STOP_SPEED:
				s.vel = Vector2.ZERO
			else:
				s.vel *= ns / sp
				s.pos += s.vel * dt
	_hold_grip(dt)
	_collide_stones()
	Gm.collide(self)
	_check_parachutes()
	_update_projs(dt)
	_check_devices()
	Ex.check_devices(self)
	_check_out()
	Ex.after_step(self)
	_record_path(dt)


# ── 내부 처리 ────────────────────────────────────────────

## 페인트 롤러 띠 위에서는 마찰이 줄어든다.
func _friction_scale(p: Vector2) -> float:
	for d in devices:
		if d.kind == "slick" and _on_strip(d, p, PartsDataRef.num("roller", "width") * 0.5):
			return PartsDataRef.num("roller", "friction")
	return 1.0


func _on_strip(d, p: Vector2, half_w: float) -> bool:
	var off: Vector2 = p - d.pos
	var along: float = off.dot(d.dir)
	if along < 0.0 or along > d.length:
		return false
	return absf(off.cross(d.dir)) <= half_w


## 딸깍 태엽, 도장 브레이크, 빨판.
func _update_shot_timers(dt: float) -> void:
	if shot == null:
		return
	var s := shooter()
	if s != null and s.alive:
		if shot.clock_timer > 0.0:
			shot.clock_timer -= dt
			if shot.clock_timer <= 0.0:
				s.vel += shot.dir * PartsDataRef.num("clockwork", "power")
				emit({"t": "part", "part": "clockwork", "pos": s.pos, "owner": s.owner, "text": "딸깍!"})
		if s.parts["prop"] == "brake" and not shot.used.has("brake"):
			var th := PartsDataRef.num("brake", "threshold")
			var sp := s.vel.length()
			if sp > th:
				shot.brake_armed = true
			elif shot.brake_armed and sp > 0.0:
				shot.used["brake"] = true
				s.vel = Vector2.ZERO
				shot.reel_timer = 0.0
				emit({"t": "part", "part": "brake", "pos": s.pos, "owner": s.owner, "text": "도장 브레이크"})
	for id in shot.sucker.keys():
		var t := get_stone(id)
		if t == null or not t.alive:
			shot.sucker.erase(id)
			continue
		if t.vel.length() > 60.0:
			t.vel *= PartsDataRef.num("sucker", "brake")
			shot.sucker.erase(id)
			emit({"t": "part", "part": "sucker", "pos": t.pos, "owner": shot.owner, "text": "빨판 감속"})


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
			if _is_grip_pair(a, b) or Ex.is_frozen(self, a) or Ex.is_frozen(self, b):
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= min_d:
				continue
			var nrm := d / dist if dist > 0.0001 else Vector2.RIGHT
			if (a.vel - b.vel).dot(nrm) > 0.0 and Ex.pre_collision(self, a, b, nrm):
				continue
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
			emit({"t": "hit", "pos": a.pos + nrm * STONE_R, "strength": rel, "a": a.id, "b": b.id, "n": nrm})
			if shot != null and record_events:
				if a.id == shot.stone_id:
					b.cause = {"owner": shot.owner, "part": "body"}
				elif b.id == shot.stone_id:
					a.cause = {"owner": shot.owner, "part": "body"}
				else:
					var src: Stone = a if va.length() >= vb.length() else b
					var dst: Stone = b if src == a else a
					if not src.cause.is_empty():
						dst.cause = {"owner": src.cause["owner"], "part": src.cause["part"], "chain": true}
			if shot != null:
				if a.id == shot.stone_id:
					Parts.on_contact(self, a, b, nrm, va, vb)
				elif b.id == shot.stone_id:
					Parts.on_contact(self, b, a, -nrm, vb, va)
				Ex.post_collision(self, a, b, a.pos + nrm * STONE_R)


func _check_parachutes() -> void:
	if shot == null:
		return
	for s in stones:
		if not s.alive or s.parts["prop"] != "chute" or s.vel == Vector2.ZERO:
			continue
		var chute_n: int = int(shot.chute_used.get(s.id, 0))
		if chute_n >= (2 if Parts.up(s, "chute") else 1):
			continue
		if edge_distance(s.pos) < EDGE_ZONE and s.vel.dot(outward(s.pos)) > 0.0:
			shot.chute_used[s.id] = chute_n + 1
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
		p.travelled += p.vel.length() * dt
		if Ex.handles(p.kind):
			Ex.update_proj(self, p, dt)
			if p.alive and (not _inside_margin(p.pos, 80.0) or p.age > 3.0):
				p.alive = false
			continue
		if p.kind == "umbrella" and p.travelled >= PartsDataRef.num("umbrella_gun", "open_dist"):
			_open_umbrella(p)
			continue
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
				if p.kind == "umbrella":
					_open_umbrella(p)
					break
				if p.kind == "sucker":
					p.alive = false
					if shot != null and Parts.up(shooter(), "sucker") and s.id != shot.stone_id:
						# ★ 맞은 알을 멈추고 내 쪽으로 1칸 당긴다
						var sh := shooter()
						s.vel = (sh.pos - s.pos).normalized() * 260.0
						emit({"t": "part", "part": "sucker", "pos": s.pos, "owner": p.owner, "text": "빨판 당기기"})
						break
					if s.vel.length() > 40.0:
						s.vel *= PartsDataRef.num("sucker", "brake")
						emit({"t": "part", "part": "sucker", "pos": s.pos, "owner": p.owner, "text": "빨판 감속"})
					elif shot != null:
						shot.sucker[s.id] = true
						emit({"t": "part", "part": "sucker", "pos": s.pos, "owner": p.owner, "text": "빨판"})
					break
				if p.kind == "bullet" and _shield_deflect(s, p):
					break
				s.vel += p.vel.normalized() * p.power
				p.alive = false
				emit({"t": "bullet_hit", "pos": p.pos, "owner": p.owner, "target": s.owner, "source": p.source})
				break
		if p.alive and (not _inside_margin(p.pos, 80.0) or p.age > 2.5):
			p.alive = false
	projs = projs.filter(func(q): return q.alive)


## 딱지 방패: 이 알이 처음 맞는 탄환을 장착한 쪽으로 튕겨낸다 (밀리지 않는다).
func _shield_deflect(s: Stone, p: Proj) -> bool:
	if s.parts["aux"] != "shield":
		return false
	if shot != null and shot.shield_used.has(s.id):
		return false
	if shot != null:
		shot.shield_used[s.id] = true
	var d: Vector2 = p.vel.normalized()
	var out := d.rotated(PI / 2.0 * s.magnet_side)
	p.vel = out * p.vel.length()
	p.pos = s.pos + out * (STONE_R + p.radius + 2.0)
	p.ignore_id = s.id
	p.age = 0.0
	p.source = "deflect"
	emit({"t": "part", "part": "shield", "pos": s.pos, "owner": s.owner, "text": "딱지 방패"})
	return true


## 우산총: 펼쳐지며 앞쪽 넓은 범위의 알을 진행 방향으로 민다.
func _open_umbrella(p: Proj) -> void:
	p.alive = false
	var dir: Vector2 = p.vel.normalized()
	var r := PartsDataRef.num("umbrella_gun", "radius")
	var pw := PartsDataRef.num("umbrella_gun", "power")
	for s in stones:
		if not s.alive or s.id == p.ignore_id:
			continue
		var off: Vector2 = s.pos - p.pos
		if off.length() > r + STONE_R:
			continue
		if off.dot(dir) < -STONE_R:
			continue
		var push := dir
		if off.length() > 1.0:
			push = (dir * 0.75 + off.normalized() * 0.25).normalized()
		s.vel += push * pw
	emit({"t": "umbrella", "pos": p.pos, "owner": p.owner, "radius": r, "dir": dir})


func _inside_margin(p: Vector2, margin: float) -> bool:
	if shape == "circle":
		return p.length() <= size + margin
	return absf(p.x) <= size + margin and absf(p.y) <= size + margin


func _device_radius(d: Device) -> float:
	if d.kind == "mine":
		return PartsDataRef.num("mine", "radius") * d.scale
	if d.kind == "bubble":
		return PartsDataRef.num("bubble", "radius")
	return 0.0


func _check_devices() -> void:
	for d in devices.duplicate():
		if d.kind == "groove":
			_check_groove(d)
			continue
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


## 바퀴 자국: 다음 샷부터 처음 홈을 밟은(움직이는) 알이 홈 방향으로 살짝 꺾인다.
func _check_groove(d: Device) -> void:
	if not d.armed:
		return
	var now_inside := {}
	var hit: Stone = null
	for s in stones:
		if not s.alive:
			continue
		if _on_strip(d, s.pos, STONE_R * 0.6):
			now_inside[s.id] = true
			if not d.inside.has(s.id) and s.vel.length() > 30.0 and hit == null:
				hit = s
	d.inside = now_inside
	if hit == null:
		return
	var axis: Vector2 = d.dir if hit.vel.dot(d.dir) >= 0.0 else -d.dir
	var diff := wrapf(axis.angle() - hit.vel.angle(), -PI, PI)
	var turn := deg_to_rad(PartsDataRef.num("track", "turn_deg"))
	hit.vel = hit.vel.rotated(clampf(diff, -turn, turn))
	emit({"t": "part", "part": "track", "pos": hit.pos, "owner": d.owner, "text": "홈에 꺾임"})
	devices.erase(d)


func _explode(d: Device) -> void:
	var blast := PartsDataRef.num("mine", "blast") * d.scale
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
		if s.alive and not is_inside(s.pos) and Ex.save_from_edge(self, s):
			continue
		if s.alive and not is_inside(s.pos):
			s.alive = false
			s.vel = Vector2.ZERO
			knockouts.append({"stone": s.id, "owner": s.owner, "cause": s.cause.duplicate()})
			emit({"t": "out", "pos": s.pos, "owner": s.owner, "cause": s.cause.duplicate(), "stone": s.id})
			Ex.on_out(self, s)
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
