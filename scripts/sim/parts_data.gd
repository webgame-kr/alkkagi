extends RefCounted
## 부품 데이터. 슬롯, 발동 시점, 설명, 충격량 같은 수치를 한곳에서 관리한다.
## 효과를 실행하는 코드는 parts.gd 에 있다.

const SLOT_LABEL := {"weapon": "무기", "aux": "보조", "prop": "추진"}
const SLOTS := ["weapon", "aux", "prop"]

## power: 상대 알에 주는 속도 변화(px/s). range: 작동 거리(px).
const CATALOG := {
	# ── 엉뚱한 발명 연구소: 규칙 파괴 부품 ──
	# ── 태엽 시계탑 (세트 「시계공」 + 단품 14) ──
	"hour_hammer": {"name": "시침 망치", "slot": "weapon", "when": "첫 정면 충돌", "set": "clock", "clock": true,
		"desc": "맞힌 알에 시곗바늘 표식. 그 알 주인의 다음 차례가 끝날 때 같은 방향으로 1.5칸 한 번 더 밀린다."},
	"late_key": {"name": "늦잠 열쇠", "slot": "aux", "when": "첫 측면 충돌", "set": "clock", "clock": true,
		"desc": "옆으로 맞힌 상대의 다음 차례를 한 칸 뒤로 미룬다."},
	"minute_spring": {"name": "분침 태엽", "slot": "prop", "when": "발사 순간", "set": "clock", "clock": true,
		"desc": "이번 샷 힘의 절반을 저장해 다음 내 샷에 더한다."},
	"time_spring": {"name": "시한 태엽", "slot": "weapon", "when": "첫 정면 충돌", "clock": true,
		"desc": "맞힌 알에 태엽을 붙인다. 다음 바퀴 그 주인 차례가 끝날 때 터져 바깥쪽으로 1.5칸 밀어낸다."},
	"reserve_bow": {"name": "예약 석궁", "slot": "weapon", "when": "발사 순간", "clock": true,
		"desc": "이번엔 조준만 저장하고, 다음 내 차례가 시작될 때 그 조준 그대로 자동 발사한다."},
	"rewind_watch": {"name": "되감기 회중시계", "slot": "weapon", "when": "첫 정면 충돌", "clock": true,
		"desc": "맞힌 알을 샷이 끝날 때 그 샷이 시작될 때의 자리로 되감는다."},
	"slow_arrow": {"name": "느린 화살", "slot": "weapon", "when": "발사 순간", "clock": true,
		"desc": "판에 남는 화살을 쏜다. 다음 두 차례 동안 차례가 끝날 때마다 2.5칸씩 날며 닿은 알을 민다."},
	"order_swap": {"name": "순서 바꾸개", "slot": "weapon", "when": "첫 정면 충돌", "clock": true,
		"desc": "맞힌 알의 주인이 이번 바퀴에 아직 쏠 차례가 남았으면 이번 바퀴 맨 끝으로 보낸다."},
	"hourglass": {"name": "모래시계 방패", "slot": "aux", "when": "남의 차례에 맞을 때", "clock": true,
		"desc": "내 차례가 아닐 때 처음 맞은 충격을 미뤘다가 다음 내 차례가 시작될 때 받는다."},
	"metronome": {"name": "메트로놈", "slot": "aux", "when": "남의 차례가 끝날 때", "clock": true,
		"desc": "멈춘 뒤 다음 내 차례까지, 남의 차례가 끝날 때마다 좌우로 번갈아 옆 1.5칸 안의 알을 툭 친다."},
	"alarm_clock": {"name": "자명종", "slot": "aux", "when": "알이 멈출 때", "clock": true,
		"desc": "멈춘 자리에 자명종을 둔다. 다음 바퀴가 시작될 때 2칸 안의 알을 시계 쪽으로 끌어모은다."},
	"wind_mouse": {"name": "태엽 장난감 쥐", "slot": "aux", "when": "첫 측면 충돌", "clock": true,
		"desc": "쥐가 떨어져, 다음 두 차례 동안 차례가 끝날 때마다 2칸씩 달리며 부딪힌 알을 민다."},
	"shock_spring": {"name": "충격 태엽", "slot": "aux", "when": "맞을 때", "clock": true,
		"desc": "남의 샷에 맞은 힘을 모아 두었다가 다음 내 샷 힘에 더한다."},
	"slow_spring": {"name": "느림보 태엽", "slot": "prop", "when": "발사 순간", "clock": true,
		"desc": "발사 속도 70%, 대신 감속이 절반이라 오래 굴러간다."},
	"replay_spring": {"name": "다시보기 태엽", "slot": "prop", "when": "다음 상대 차례가 끝날 때", "clock": true,
		"desc": "다음 상대 차례가 끝날 때 내 이번 샷의 잔상이 같은 길을 한 번 더 달리며 닿은 알을 민다."},
	"time_capsule": {"name": "타임캡슐", "slot": "prop", "when": "알이 멈출 때", "clock": true,
		"desc": "처음 멈춘 자리에 캡슐을 묻는다. 이 알이 떨어지면 다음 내 차례가 시작될 때 그 자리로 돌아온다(판당 1회)."},
	"tick_step": {"name": "똑딱 걸음", "slot": "prop", "when": "발사 순간", "clock": true,
		"desc": "세 구간으로 끊어 간다. 구간마다 잠깐 멈췄다가 다시 출발한다."},
	# ── 해적 선착장 (세트 「선장」 + 단품 14) ──
	"parrot_hat": {"name": "앵무새 모자", "slot": "weapon", "when": "발사 순간", "set": "captain", "pirate": true,
		"desc": "앵무새가 정면 첫 상대 알 위에 앉는다. 이 알의 다음 샷은 그 알 쪽으로 살짝 휘어 간다."},
	"hook_hand": {"name": "갈고리손", "slot": "aux", "when": "첫 측면 충돌", "set": "captain", "pirate": true,
		"desc": "옆으로 스친 상대 알에 갈고리를 걸어, 그 알을 축으로 반 바퀴 휘돌며 방향을 튼다."},
	"peg_leg": {"name": "나무 의족", "slot": "prop", "when": "알이 멈출 때", "set": "captain", "pirate": true,
		"desc": "멈추면 바닥에 박혀 다음 내 차례까지 잘 밀리지 않는다. 큰 충격 한 번이면 빠진다."},
	"hole_cannon": {"name": "구멍 대포", "slot": "weapon", "when": "발사 순간", "pirate": true,
		"desc": "정면 3칸 앞(그 사이에 알이 있으면 그 자리)에 포탄을 떨어뜨려 구멍을 낸다(1바퀴). 구멍 위에 멈추거나 느리게 지나면 빠진다."},
	"spyglass": {"name": "망원경", "slot": "weapon", "when": "조준할 때", "pirate": true,
		"desc": "조준할 때 첫 충돌 이후 경로까지 보이고, 그 샷만 힘 +10%."},
	"bolas": {"name": "쇠사슬 볼라스", "slot": "weapon", "when": "닿은 상대 알 둘", "pirate": true,
		"desc": "처음 닿은 상대 알 두 개를 1.5칸 사슬로 묶는다(다음 바퀴 끝까지)."},
	"smoke_powder": {"name": "연막 화약", "slot": "weapon", "when": "발사 순간", "pirate": true,
		"desc": "정면 부채꼴 3칸에 연막. 안의 알은 다음 바퀴 동안 조준선이 절반만 보인다."},
	"flag_signal": {"name": "깃발 신호기", "slot": "weapon", "when": "첫 충돌", "pirate": true,
		"desc": "맞힌 알에 깃발을 꽂아, 다음 두 바퀴 동안 바퀴 시작마다 바람 방향으로 1칸 흘러가게 한다."},
	"rum_barrel": {"name": "술통", "slot": "aux", "when": "첫 측면 충돌", "pirate": true,
		"desc": "통이 떨어져 부딪힌 방향으로 판 끝까지 굴러가며 길 위의 알을 민다."},
	"water_pump": {"name": "물대포 펌프", "slot": "aux", "when": "알이 멈출 때", "pirate": true, "side": true,
		"desc": "멈춘 순간 장착한 쪽 일직선 3칸 안의 알을 조금씩 밀어낸다."},
	"plank_dock": {"name": "널빤지 부두", "slot": "aux", "when": "판 끝에 닿을 때", "pirate": true,
		"desc": "판 끝에 닿은 자리에 널빤지를 깔아 판을 1칸 늘린다(1바퀴, 모두 이용)."},
	"treasure_chest": {"name": "보물 상자", "slot": "aux", "when": "알이 멈출 때", "pirate": true,
		"desc": "멈춘 자리에 상자를 둔다. 다음 바퀴 끝에 상자 1칸 안에 알이 있는 사람은 다음 개조 후보 +1장."},
	"jump_board": {"name": "점프 판자", "slot": "aux", "when": "첫 측면 충돌", "pirate": true,
		"desc": "그 자리에 경사로를 만든다(1바퀴). 지나는 알은 한 번 튀어 올라 바로 앞 알을 넘어간다."},
	"wind_sail": {"name": "바람돛", "slot": "prop", "when": "움직이는 동안", "pirate": true,
		"desc": "경로가 바람 쪽으로 크게 휜다. 바람을 등지면 더 멀리 간다."},
	"lifeboat": {"name": "구명보트", "slot": "prop", "when": "떨어질 때", "pirate": true,
		"desc": "떨어지면 한 번, 다음 내 차례를 쉬는 대신 가장 가까운 판 끝으로 돌아온다."},
	"oar": {"name": "노 젓기", "slot": "prop", "when": "첫 충돌 직후", "pirate": true,
		"desc": "첫 충돌 직후 바람 방향으로 1.5칸 미끄러진다."},
	"helm": {"name": "타륜", "slot": "prop", "when": "알이 멈출 때", "pirate": true,
		"desc": "멈출 때 제자리에서 반 바퀴 돌며 1칸 안의 알을 회전 방향으로 쓸어낸다."},
	"merge_bolt": {"name": "합체 볼트", "slot": "aux", "when": "내 알과 부딪힐 때", "lab": true,
		"desc": "발사한 알이 내 다른 알과 부딪히면 둘이 합쳐 큰 알 하나가 된다. 지름 1.4배, 무게 2배."},
	"decoy": {"name": "미끼 풍선", "slot": "aux", "when": "알이 멈출 때", "lab": true,
		"desc": "멈춘 자리 뒤에 내 알과 똑같이 생긴 풍선을 남긴다(1바퀴). 맞으면 터지며 주변 1.5칸의 알을 민다."},
	"split_capsule": {"name": "분열 캡슐", "slot": "prop", "when": "첫 충돌 직후", "lab": true,
		"desc": "첫 충돌 직후 내 알이 작은 알 둘로 갈라진다. 각각 지름 0.75배, 무게 0.5배, 부품 없음. 판마다 한 번."},
	"weight": {"name": "무게추", "slot": "prop", "when": "늘", "lab": true,
		"desc": "이 알의 무게가 2배. 발사 속도는 0.8배."},
	"shrink_ray": {"name": "축소 광선", "slot": "weapon", "when": "발사 순간", "lab": true,
		"desc": "정면으로 광선을 쏴 처음 맞힌 알을 다음 바퀴가 끝날 때까지 지름 0.7배, 무게 0.5배로 만든다."},
	"remote": {"name": "리모컨", "slot": "weapon", "when": "내 차례", "lab": true,
		"desc": "이 알에서 4칸 안의 상대 알 하나를 내가 조준해 쏜다. 한 번 쓰면 부품이 사라진다."},
	"sticky": {"name": "끈끈이 탄", "slot": "weapon", "when": "발사 순간", "lab": true, "bullet": true, "power": 200.0,
		"desc": "정면으로 쏜 탄에 맞은 상대 알이 내 알에 달라붙어, 다음 내 샷이 끝날 때까지 한 덩어리로 움직인다."},
	"tilter": {"name": "판 기울이개", "slot": "weapon", "when": "발사 순간", "lab": true,
		"desc": "조준 방향으로 판이 기운다. 이번 샷 동안 판 위의 모든 알이 그쪽으로 흘러간다."},
	"coupling": {"name": "자석 커플링", "slot": "aux", "when": "늘", "lab": true,
		"desc": "내 알 두 개를 보이지 않는 줄로 묶는다(최대 3칸). 한 알이 3칸 넘게 멀어지면 다른 알이 끌려온다."},
	"repel": {"name": "반발 코팅", "slot": "aux", "when": "발사 순간", "lab": true,
		"desc": "다음 바퀴가 끝날 때까지 이 알에 부딪힌 알은 2배로 튕겨 나간다."},
	"ghost": {"name": "유령 장치", "slot": "prop", "when": "이번 샷 동안", "lab": true,
		"desc": "이번 샷 동안 상대 알을 통과한다. 멈춘 자리에서 실체화하며 겹쳐 있던 알을 세게 밀쳐낸다."},
	"inflate": {"name": "팽창 풍선", "slot": "prop", "when": "첫 충돌 직후", "lab": true,
		"desc": "첫 충돌 직후 내 알이 다음 바퀴가 끝날 때까지 지름 1.6배로 부푼다."},
	# ── 무기 ──────────────────────────────────────────────
	"pea": {"name": "콩알총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 탄환 한 발. 처음 맞힌 알을 밀고 사라진다.",
		"power": 380.0, "bullet": true},
	"shotgun": {"name": "산탄총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면 부채꼴로 탄환 세 발. 가까운 알은 여러 발을 맞는다.",
		"power": 200.0, "spread_deg": 13.0, "bullet": true},
	"hook": {"name": "갈고리", "slot": "weapon", "when": "발사 직후",
		"desc": "정면의 첫 상대 알을 내 쪽으로 당긴다.",
		"power": 560.0, "range": 440.0},
	"claw": {"name": "집게", "slot": "weapon", "when": "첫 정면 충돌",
		"desc": "정면에서 처음 맞힌 상대 알을 잠깐 붙잡고 함께 밀고 간다.",
		"hold": 0.8},
	"nose": {"name": "고무코", "slot": "weapon", "when": "첫 정면 충돌",
		"desc": "상대를 세게 밀고 내 알은 뒤로 살짝 튕긴다.",
		"power": 400.0, "bounce": 170.0},
	"stamp": {"name": "자리바꿈 도장", "slot": "weapon", "when": "약한 샷의 첫 충돌",
		"desc": "힘 45% 이하로 처음 맞힌 상대 알과 자리를 바꾸고 둘 다 멈춘다.",
		"max_power": 0.45},
	"copier": {"name": "고장 난 복사기", "slot": "weapon", "when": "첫 충돌",
		"desc": "충돌 지점에 포탑을 남긴다. 다음 내 샷 때 설치할 때의 조준 방향으로 한 발 쏘고 사라진다.",
		"power": 380.0},
	# ── 보조 ──────────────────────────────────────────────
	"magnet": {"name": "자석팔", "slot": "aux", "when": "발사 직후",
		"desc": "장착한 쪽의 가까운 상대 알 하나를 끌어당긴다. 장착할 때 좌우를 고른다.",
		"power": 520.0, "range": 300.0},
	"bumper": {"name": "접이식 범퍼", "slot": "aux", "when": "첫 측면 충돌",
		"desc": "범퍼가 펴져 부딪힌 알을 옆으로 민다.",
		"power": 440.0},
	"flipper": {"name": "오리발", "slot": "aux", "when": "첫 충돌 직후",
		"desc": "옆쪽의 가까운 알 하나에 짧은 발차기를 날린다.",
		"power": 420.0, "range": 140.0},
	"decal": {"name": "데칼코마니 포신", "slot": "aux", "when": "무기가 탄환을 쏠 때",
		"desc": "판 중심을 사이에 둔 반대편 대칭 위치에서 대칭 방향으로 보조탄이 나온다.",
		"needs": "bullet"},
	"umbrella": {"name": "거울 우산", "slot": "aux", "when": "첫 충돌",
		"desc": "충돌 지점에 거울을 편다. 다음 바퀴 끝까지, 누구의 탄환이든 한 발을 반사하면 접힌다.",
		"half_len": 42.0},
	"spring": {"name": "스프링 분신", "slot": "aux", "when": "첫 충돌",
		"desc": "옆으로 작은 고무 알을 튕겨 보낸다. 처음 맞힌 알을 밀고 사라진다.",
		"power": 380.0, "speed": 760.0},
	"carousel": {"name": "회전목마 팔", "slot": "aux", "when": "첫 측면 충돌",
		"desc": "부딪힌 상대 알을 잡아 내 반대편으로 휘둘러 던진다.",
		"power": 330.0},
	"bubble": {"name": "버블 프린터", "slot": "aux", "when": "샷이 끝날 때",
		"desc": "지나온 길 중간에 방울을 남긴다. 다음 샷부터 처음 닿은 알을 옆으로 민다.",
		"power": 400.0, "radius": 16.0, "rounds": 1},
	"mine": {"name": "지뢰 배출기", "slot": "aux", "when": "알이 멈출 때",
		"desc": "멈춘 자리에 지뢰를 놓는다. 다음 샷부터 알이 닿으면 터져 주변 알을 밀어낸다.",
		"power": 560.0, "radius": 26.0, "blast": 135.0, "rounds": 2},
	# ── 추진 ──────────────────────────────────────────────
	"rocket": {"name": "로켓", "slot": "prop", "when": "첫 충돌 직후",
		"desc": "발사 방향으로 한 번 더 가속한다.",
		"power": 650.0},
	"retro": {"name": "역추진 로켓", "slot": "prop", "when": "첫 충돌 직후",
		"desc": "발사 반대 방향으로 가속한다. 상대를 치고 판 안쪽으로 빠져나온다.",
		"power": 620.0},
	"reel": {"name": "리턴 릴", "slot": "prop", "when": "첫 충돌 직후",
		"desc": "출발점에 걸어둔 줄이 감겨 내 알을 끌어당긴다. 돌아오는 길에도 부딪힌다.",
		"accel": 2600.0, "max_speed": 820.0, "time": 1.3},
	"chute": {"name": "낙하산", "slot": "prop", "when": "판 끝 구역에 들어갈 때",
		"desc": "내 알이 판 끝 구역에 들어가면 한 번 급제동한다. 너무 빠르면 그대로 떨어질 수 있다.",
		"power": 550.0},
	# ── 신규 무기 ─────────────────────────────────────────
	"trex_head": {"name": "티라노 머리", "slot": "weapon", "when": "첫 정면 충돌", "set": "trex",
		"desc": "정면에서 처음 부딪힌 상대 알을 잠깐 물고 발사 방향으로 밀어낸다.",
		"power": 300.0},
	"sucker": {"name": "빨판총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 빨판을 쏜다. 맞은 알은 이번 샷에 한 번 짧게 감속한다. 도망가는 알을 세워 몸통으로 칠 수 있다.",
		"speed": 1150.0, "brake": 0.3},
	"umbrella_gun": {"name": "우산총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 접힌 우산을 쏜다. 일정 거리를 지나면 펼쳐지며 옆으로 넓은 범위의 알을 민다.",
		"speed": 900.0, "open_dist": 190.0, "radius": 90.0, "power": 340.0},
	"roller": {"name": "페인트 롤러", "slot": "weapon", "when": "첫 정면 충돌",
		"desc": "처음 정면으로 맞은 알 뒤로 미끄러운 띠를 남긴다. 띠 위를 지나는 알은 마찰이 줄어 더 멀리 미끄러진다.",
		"length": 200.0, "width": 44.0, "friction": 0.3, "rounds": 1},
	# ── 신규 보조 ─────────────────────────────────────────
	"trex_arm": {"name": "티라노 팔", "slot": "aux", "when": "첫 측면 충돌", "set": "trex",
		"desc": "옆으로 부딪힌 상대 알 하나를 내 알 앞쪽으로 끌어온다."},
	"shield": {"name": "딱지 방패", "slot": "aux", "when": "처음 탄환을 맞을 때", "side": true,
		"desc": "이 알이 처음 탄환을 맞으면 방패가 뒤집히며 탄환을 옆으로 튕겨낸다. 튕기는 쪽은 장착할 때 고른다."},
	"tambourine": {"name": "탬버린", "slot": "aux", "when": "첫 충돌",
		"desc": "첫 충돌 지점에서 진동이 퍼진다. 직접 부딪히지 않은 가까운 알도 조금씩 밀려난다.",
		"radius": 130.0, "power": 240.0},
	"track": {"name": "바퀴 자국", "slot": "aux", "when": "멈출 때",
		"desc": "멈출 때 지나온 길에 짧은 홈을 남긴다. 다음 샷부터 처음 홈을 밟은 알이 홈 방향으로 살짝 꺾인다.",
		"length": 140.0, "turn_deg": 30.0, "rounds": 1},
	# ── 신규 추진 ─────────────────────────────────────────
	"trex_leg": {"name": "티라노 다리", "slot": "prop", "when": "첫 몸통 충돌 직후", "set": "trex",
		"desc": "첫 몸통 충돌 뒤 두 발로 버텨 내 알의 반동을 줄인다.",
		"keep": 0.25},
	"crab": {"name": "게걸음 바퀴", "slot": "prop", "when": "첫 충돌 직후", "side": true,
		"desc": "첫 충돌 직후 장착할 때 고른 좌우 방향으로 짧게 튄다.",
		"power": 480.0},
	"clockwork": {"name": "딸깍 태엽", "slot": "prop", "when": "약한 샷 뒤 잠깐 뒤",
		"desc": "힘 50% 이하로 쏘면 출발은 느리지만 잠깐 뒤 한 번 가속한다. 가속할 위치를 조준 중 표시한다.",
		"max_power": 0.5, "delay": 0.45, "power": 520.0},
	"brake": {"name": "도장 브레이크", "slot": "prop", "when": "속도가 떨어질 때",
		"desc": "쏜 알의 속도가 일정 수준 아래로 떨어지면 한 번 급정지한다. 다음 턴에 쓸 자리를 정확히 잡기 좋다.",
		"threshold": 260.0},
	# ── 달그림자 마도사 세트 ──────────────────────────────
	"moon_staff": {"name": "달무리 지팡이", "slot": "weapon", "when": "발사 순간", "set": "moon",
		"desc": "정면으로 빛 구슬을 쏜다. 구슬이 지난 알에 표식을 남기고, 이번 샷에서 내 알이 처음 부딪힌 표식 대상을 더 멀리 민다.",
		"speed": 1300.0, "power": 260.0},
	"star_cloak": {"name": "별자리 망토", "slot": "aux", "when": "첫 충돌", "set": "moon",
		"desc": "첫 충돌 지점에 마법진을 남긴다. 다음 샷부터 처음 밟은 알을 원의 접선 방향으로 튕긴다. 누구나 밟는다.",
		"radius": 30.0, "power": 380.0, "rounds": 1},
	"moon_boots": {"name": "월광 장화", "slot": "prop", "when": "첫 충돌 직후", "set": "moon",
		"desc": "첫 충돌 직후 조준 방향으로 짧게 도약한다. 다른 알을 넘어갈 수 있고, 착지할 자리가 비어 있을 때만 뛴다.",
		"dist": 88.0, "speed": 220.0},
	# ── 최후의 주인공 세트 ────────────────────────────────
	"hero_band": {"name": "주인공 머리띠", "slot": "weapon", "when": "투지 1칸 이상일 때 발사", "set": "hero",
		"desc": "투지만큼 강해지는 정면 충격파. 1칸은 짧고 약하게, 3칸은 넓고 세게. 투지는 쓰지 않는다.",
		"max_power": 0.5, "range": 160.0, "power": 330.0},
	"torn_cape": {"name": "찢어진 망토", "slot": "aux", "when": "판 밖으로 나갈 뻔할 때", "set": "hero",
		"desc": "판 밖으로 나갈 뻔하면 가장자리에서 한 번 버틴다. 판마다 한 번, 누구의 샷이든. 버티면 투지 +1."},
	"awaken_shoes": {"name": "각성 운동화", "slot": "prop", "when": "첫 충돌 직후 (투지 1칸)", "set": "hero",
		"desc": "첫 충돌 직후 투지 1칸을 써서 조준 방향으로 한 번 더 돌진한다.",
		"power": 600.0, "back": 420.0},
	# ── 각성·시스템 단품 ──────────────────────────────────
	"ice_fan": {"name": "빙결 부채", "slot": "weapon", "when": "첫 충돌",
		"desc": "첫 충돌 지점에서 앞으로 부채꼴 얼음을 깐다. 다음 샷 동안 그 위를 지나는 알은 마찰이 줄어든다.",
		"radius": 120.0, "spread_deg": 70.0, "friction": 0.3},
	"shadow_scissors": {"name": "그림자 가위", "slot": "weapon", "when": "첫 충돌",
		"desc": "처음 맞힌 상대 알의 부품 하나를 봉인한다(무기 → 보조 → 추진 순). 그 알의 다음 발사 한 번에 그 부품이 작동하지 않는다."},
	"bookmark": {"name": "운명의 책갈피", "slot": "aux", "when": "장착할 때",
		"desc": "장착할 때 이번에 고르지 않은 후보 하나를 다음 부품 선택에 예약한다. 다음 선택이 남아 있을 때 후보에 나온다."},
	"relic_ribbon": {"name": "유품 리본", "slot": "aux", "when": "이 알이 떨어질 때",
		"desc": "이 알이 떨어지면 달려 있던 다른 부품 하나를 회수한다. 다음 내 차례에 살아 있는 알의 빈 슬롯에만 달 수 있다."},
	"cloud_mailbox": {"name": "구름 우편함", "slot": "prop", "when": "멈출 때",
		"desc": "알이 멈춘 자리에 구름 표식을 남긴다. 그 알을 다음에 쏠 때 표식 자리가 비어 있으면 그곳에서 출발할 수 있다."},
	"edge_sewer": {"name": "판끝 재봉틀", "slot": "prop", "when": "첫 충돌",
		"desc": "첫 충돌 지점에서 가장 가까운 판 끝에 짧은 안전망을 친다. 다음 바퀴 시작 전까지 그 구간을 넘는 첫 알을 판 안으로 돌려보낸다.",
		"half_len": 70.0},
	# ── 애니 패러디 단품 (발동하면 그 알이 만화 그림체로) ──
	"drift_tire": {"name": "배수로 타이어", "slot": "prop", "when": "판 끝을 비스듬히 넘을 때", "anime": true, "sfx": "끼이익", "sfx_color": "#E04E3A",
		"desc": "판 끝을 비스듬히 넘으려 할 때 한 번 경계를 타고 짧게 달린다. 정면으로 넘으면 그대로 떨어진다.",
		"max_cos": 0.75},
	"flash_step": {"name": "순보 깔창", "slot": "prop", "when": "첫 정면 충돌 직전", "anime": true, "sfx": "슉", "sfx_color": "#4A5BD8",
		"desc": "정면의 첫 알에 닿기 직전, 그 뒤의 빈자리로 순간이동한다. 진행 방향은 그대로다."},
	"rubber_fist": {"name": "고무 주먹", "slot": "weapon", "when": "발사 순간", "anime": true, "sfx": "쭈우욱", "sfx_color": "#F2A23A",
		"desc": "정면으로 주먹을 뻗어 첫 알을 밀고, 돌아올 때 처음 닿은 알을 내 쪽으로 끌어당긴다.",
		"reach": 300.0, "speed": 1400.0, "power": 380.0, "pull": 360.0},
	"charge_palm": {"name": "모으고 쏘는 손바닥", "slot": "weapon", "when": "충전한 샷의 한 박자 뒤", "anime": true, "sfx": "파아앗", "sfx_color": "#2FA8E0",
		"desc": "조준을 1초 이상 유지하면 충전된다. 쏜 알이 한 박자 뒤 그 자리에서 처음 조준 방향으로 빔을 쏜다.",
		"charge": 1.0, "delay": 0.5, "power": 420.0, "width": 16.0},
	"at_field": {"name": "절대영역 방패", "slot": "aux", "when": "발사 직후", "anime": true, "sfx": "지잉", "sfx_color": "#F28A2E",
		"desc": "발사 직후 알 앞에 육각 장벽이 펼쳐진다. 처음 닿은 알을 밀고 장벽은 깨진다.",
		"power": 400.0},
	"log_sub": {"name": "통나무 대역", "slot": "aux", "when": "첫 충돌", "anime": true, "sfx": "펑", "sfx_color": "#3FA27A",
		"desc": "첫 충돌 때 이 알은 비어 있는 옆자리로 빠지고 원래 자리에 통나무를 남긴다. 부딪힌 알은 통나무에 맞고 튕긴다."},
	"trap_card": {"name": "함정 카드 한 장", "slot": "aux", "when": "멈출 때", "anime": true, "sfx": "착", "sfx_color": "#C04A9A",
		"desc": "멈춘 자리에 카드를 놓는다. 다음 바퀴 시작 전까지 다른 알이 밟으면 들어온 방향의 반대로 튕긴다. 위치는 모두에게 보인다.",
		"radius": 18.0},
	"stopwatch": {"name": "5초짜리 스톱워치", "slot": "aux", "when": "첫 충돌 직후", "anime": true, "sfx": "째깍", "sfx_color": "#7A55C8",
		"desc": "첫 충돌 직후 근처에서 움직이는 알들을 잠깐 얼린다. 풀린 알은 하던 방향으로 다시 움직인다.",
		"radius": 170.0, "time": 0.5},
	"rebound_shoes": {"name": "리바운드 운동화", "slot": "prop", "when": "맞힌 알이 또 부딪힐 때", "anime": true, "sfx": "통", "sfx_color": "#E07B39",
		"desc": "내 알에 맞은 상대가 다른 알과 부딪히면, 내 알이 그 충돌 지점 쪽으로 짧게 뛰어든다.",
		"power": 460.0},
	"alchemy_glove": {"name": "양손이 바쁜 연금 장갑", "slot": "weapon", "when": "첫 충돌", "anime": true, "sfx": "짝", "sfx_color": "#2F7FD8",
		"desc": "첫 충돌 지점 앞의 빈 공간에 짧은 돌벽을 세운다. 벽은 이번 샷이 끝날 때까지 알을 튕겨낸다.",
		"half_len": 50.0, "ahead": 70.0},
	# ── 마법 단품 ─────────────────────────────────────────
	"echo_bell": {"name": "메아리 종", "slot": "weapon", "when": "첫 충돌 반 박자 뒤",
		"desc": "첫 충돌 지점에서 반 박자 뒤 충격파가 퍼진다. 범위에 남은 알을 바깥쪽으로 민다.",
		"delay": 0.3, "radius": 120.0, "power": 300.0},
	"string_doll": {"name": "실매듭 인형", "slot": "weapon", "when": "첫 충돌",
		"desc": "처음 맞힌 상대와 그 근처의 다른 알을 실로 잇는다. 이번 샷에서 둘이 많이 벌어지면 뒤처진 알을 한 번 끌어당긴다.",
		"range": 150.0, "slack": 70.0, "power": 360.0},
	"night_charm": {"name": "밤비늘 부적", "slot": "weapon", "when": "첫 충돌",
		"desc": "처음 맞힌 상대 알에 저주를 남긴다. 그 알이 다음에 발사될 때 출발점 뒤로 그림자가 튀어나와 가까운 알을 민다.",
		"range": 150.0, "power": 380.0},
	"ink_drop": {"name": "잉크 한 방울", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 잉크를 던진다. 첫 알에 닿으면 양옆으로 갈라져 주변의 다른 알을 민다.",
		"speed": 1000.0, "split_speed": 750.0, "split_dist": 170.0, "power": 300.0},
	"mushroom": {"name": "버섯 원탁", "slot": "aux", "when": "첫 충돌",
		"desc": "첫 충돌 지점 양옆의 빈자리에 버섯을 심는다. 다음 바퀴 시작 전까지 버섯을 밟은 알은 튕겨 나가고 그 버섯은 사라진다.",
		"radius": 14.0, "power": 340.0},
	"wind_knot": {"name": "바람 매듭", "slot": "aux", "when": "멈출 때",
		"desc": "멈춘 자리에 방향이 그려진 바람을 남긴다. 다음 샷부터 처음 지나간 알을 그쪽으로 살짝 꺾는다.",
		"radius": 26.0, "turn_deg": 28.0, "rounds": 1},
	"shadow_scale": {"name": "그림자 저울", "slot": "aux", "when": "첫 충돌",
		"desc": "첫 충돌에서 상대에게 가는 충격 일부를, 그 상대와 가장 가까운 다른 알에 나눠 보낸다. 쏜 알은 받지 않는다.",
		"share": 0.45, "range": 160.0},
	"moon_well": {"name": "달빛 우물", "slot": "aux", "when": "첫 충돌",
		"desc": "첫 충돌 자리에 원을 남긴다. 다음 샷부터 처음 들어온 알을 감속시키고, 원을 빠져나가면 진행 방향으로 한 번 민다.",
		"radius": 36.0, "slow": 0.45, "power": 380.0, "rounds": 1},
	"second_step": {"name": "두 번째 발자국", "slot": "prop", "when": "처음 멈출 때",
		"desc": "처음 멈추면 지나온 길을 짧게 되짚는다. 되돌아오는 길에서 처음 닿은 알을 밀고 멈춘다.",
		"speed": 520.0},
	"side_scroll": {"name": "옆구리 주문서", "slot": "prop", "when": "충돌 없이 일정 거리", "side": true,
		"desc": "충돌 없이 일정 거리를 가면 장착할 때 고른 쪽으로 90도 꺾인다. 꺾이는 위치를 조준 중 표시한다.",
		"dist": 180.0},
	"glass_wings": {"name": "유리 날개", "slot": "prop", "when": "판 끝을 비스듬히 넘을 때",
		"desc": "판 끝을 비스듬히 넘으려는 순간 안쪽으로 한 번 반사한다. 거의 정면으로 넘으면 날개가 깨지고 떨어진다.",
		"max_cos": 0.8, "keep": 0.85},
	"anchor": {"name": "약속의 닻", "slot": "prop", "when": "샷이 끝날 때",
		"desc": "샷이 끝났을 때 내 알이 살아 있고 출발점이 비어 있으면 그곳으로 돌아온다."},
}

## 세트: 같은 알에 세 부품을 모두 달면 전용 동작이 열린다.
const SETS := {
	"trex": {"name": "메카 티라노", "parts": ["trex_head", "trex_arm", "trex_leg"],
		"move": "물고 던지기", "short": {"trex_head": "머리", "trex_arm": "팔", "trex_leg": "다리"},
		"throw_power": 420.0},
	"moon": {"name": "달그림자 마도사", "parts": ["moon_staff", "star_cloak", "moon_boots"],
		"move": "궤도 마법", "short": {"moon_staff": "지팡이", "star_cloak": "망토", "moon_boots": "장화"},
		"power": 520.0},
	"clock": {"name": "시계공", "parts": ["hour_hammer", "late_key", "minute_spring"],
		"move": "정각", "move_desc": "바퀴마다 한 번, 내 샷이 끝나면 같은 알로 바로 한 번 더 쏜다 (두 번째 샷은 힘 70%)",
		"short": {"hour_hammer": "망치", "late_key": "열쇠", "minute_spring": "태엽"}},
	"captain": {"name": "선장", "parts": ["parrot_hat", "hook_hand", "peg_leg"],
		"move": "포격 명령", "move_desc": "바퀴마다 한 번, 내 샷이 끝나면 판 바깥에서 대포알이 그 샷 방향으로 판을 가로지르며 길 위의 알을 민다",
		"short": {"parrot_hat": "모자", "hook_hand": "갈고리", "peg_leg": "의족"}},
	"hero": {"name": "최후의 주인공", "parts": ["hero_band", "torn_cape", "awaken_shoes"],
		"move": "라스트 컷", "move_desc": "투지 3칸 + 세트 완성: 판 끝까지 관통 돌진, 부딪힌 알은 옆으로, 판 끝에서 망토로 반드시 멈춘다", "short": {"hero_band": "머리띠", "torn_cape": "망토", "awaken_shoes": "운동화"}},
}

## 오늘의 공방: 매 판 하나의 공방이 열리고, 그 판의 부품은 공용 10종 + 공방 전용 6종.
## 공용 4종: 정면 공격 · 측면 공격 · 밀고 들어가기 · 뒤로 빠지기 (확장 기획 「부품 확장」)
const COMMON_PARTS := ["pea", "magnet", "rocket", "retro"]
const MATCH_EXCLUSIVE := 10   # 한 판에 쓰는 공방 전용 부품 수
const WORKSHOPS := {
	"junk": {"name": "고물 정비소", "tag": "티라노를 조립하고 몸통으로 들이받는 곳", "desc": "티라노를 조립하고, 몸통으로 들이받을 각도와 가장자리에서 살아남을 방법을 고른다.",
		"parts": ["trex_head", "trex_arm", "trex_leg", "sucker", "brake", "mine", "hook", "copier", "carousel", "crab", "shotgun", "claw"], "rep": ["trex_head", "sucker", "mine"], "set": "trex"},
	"magic": {"name": "수상한 마법 상점", "tag": "닿지 않는 알을 밀고 한 발 뒤를 준비하는 곳", "desc": "직접 닿지 않는 알을 밀고, 한 발 뒤에 일어날 일을 준비한다.",
		"parts": ["moon_staff", "star_cloak", "moon_boots", "shadow_scale", "night_charm", "anchor", "echo_bell", "moon_well", "wind_knot", "side_scroll"], "rep": ["moon_staff", "night_charm", "anchor"], "set": "moon"},
	"toon": {"name": "만화 소품 창고", "tag": "판 끝을 달리고 상대 뒤로 넘어가는 곳", "desc": "최후의 주인공을 모으거나, 상대 뒤로 넘어가고 판 끝을 타며 직선 조준으로는 잡기 힘든 알을 노린다.",
		"parts": ["hero_band", "torn_cape", "awaken_shoes", "drift_tire", "flash_step", "log_sub", "trap_card", "rubber_fist", "charge_palm",
			"at_field", "stopwatch", "rebound_shoes", "alchemy_glove", "nose", "flipper", "chute"],
		"rep": ["hero_band", "flash_step", "rubber_fist"], "set": "hero"},
	"lab": {"name": "엉뚱한 발명 연구소", "tag": "알의 크기·무게·개수·주인을 바꾸는 곳",
		"desc": "알끼리 합치고, 쪼개고, 상대 알을 조종한다. 세트 대신 부품 하나하나가 규칙을 바꾼다.",
		"parts": ["merge_bolt", "decoy", "split_capsule", "weight", "shrink_ray", "remote", "sticky", "tilter", "coupling", "repel", "ghost", "inflate", "bumper"],
		"rep": ["merge_bolt", "split_capsule", "remote"], "set": ""},
	"clock": {"name": "태엽 시계탑", "tag": "효과가 다음 차례에 터지는 곳",
		"desc": "지금이 아니라 다음 차례 끝, 다음 바퀴 시작에 터지는 효과로 남의 차례에도 판을 움직인다.",
		"parts": ["hour_hammer", "late_key", "minute_spring", "time_spring", "reserve_bow", "rewind_watch", "slow_arrow", "order_swap",
			"hourglass", "metronome", "alarm_clock", "wind_mouse", "shock_spring", "slow_spring", "replay_spring", "time_capsule", "tick_step"],
		"rep": ["hour_hammer", "time_spring", "alarm_clock"], "set": "clock"},
	"pirate": {"name": "해적 선착장", "tag": "바람이 불고 판이 바뀌는 곳",
		"desc": "바퀴마다 바뀌는 바람을 타고, 구멍·널빤지·밀물로 판 자체를 바꾼다.",
		"parts": ["parrot_hat", "hook_hand", "peg_leg", "hole_cannon", "spyglass", "bolas", "smoke_powder", "flag_signal",
			"rum_barrel", "water_pump", "plank_dock", "treasure_chest", "jump_board", "wind_sail", "lifeboat", "oar", "helm"],
		"rep": ["parrot_hat", "hole_cannon", "wind_sail"], "set": "captain"},
	"all": {"name": "잡동사니 창고", "tag": "모든 부품이 섞여 나오는 곳", "desc": "모든 부품 66종이 섞여 나온다.", "parts": [], "rep": ["pea", "moon_staff", "rubber_fist"], "set": ""},
}
const WORKSHOP_ORDER := ["junk", "magic", "toon", "lab", "clock", "pirate", "all"]


## 이 공방에서 나오는 부품 id 목록.
static func workshop_pool(ws: String) -> Array:
	if ws == "all" or not WORKSHOPS.has(ws):
		return ids()
	var out: Array = COMMON_PARTS.duplicate()
	out.append_array(WORKSHOPS[ws]["parts"])
	return out


## 한 판에 쓸 부품: 공용 4종 + 전용 중 10종. 세트 부품은 항상 넣고, 무기·보조·추진이 각 3종 이상 되게 뽑는다.
static func match_pool(ws: String, rng: RandomNumberGenerator) -> Array:
	if ws == "all" or not WORKSHOPS.has(ws):
		return ids()
	var excl: Array = WORKSHOPS[ws]["parts"]
	if excl.size() <= MATCH_EXCLUSIVE:
		return COMMON_PARTS + excl
	var set_id: String = WORKSHOPS[ws].get("set", "")
	var fixed: Array = []
	var rest: Array = []
	for id in excl:
		if set_id != "" and set_of(id) == set_id:
			fixed.append(id)
		else:
			rest.append(id)
	var best: Array = []
	for attempt in 60:
		var pick: Array = fixed.duplicate()
		var bag: Array = rest.duplicate()
		while pick.size() < MATCH_EXCLUSIVE and not bag.is_empty():
			var k := rng.randi_range(0, bag.size() - 1)
			pick.append(bag[k])
			bag.remove_at(k)
		best = pick
		var cnt := {"weapon": 0, "aux": 0, "prop": 0}
		for id in COMMON_PARTS + pick:
			cnt[slot_of(id)] += 1
		if cnt["weapon"] >= 3 and cnt["aux"] >= 3 and cnt["prop"] >= 3:
			break
	return COMMON_PARTS + best


## 장착할 때 좌우를 고르는 부품. 보조는 Stone.magnet_side, 추진은 Stone.prop_side 에 저장.
const SIDE_PARTS := ["magnet", "shield", "crab", "side_scroll", "water_pump"]

## 탄환을 쏘는 무기(데칼코마니 포신의 조건).
const BULLET_WEAPONS := ["pea", "shotgun"]


static func ids() -> Array:
	return CATALOG.keys()


## 강화 카드는 "up:부품" 으로 쓴다.
static func is_up(id: String) -> bool:
	return id.begins_with("up:")


static func base_of(id: String) -> String:
	return id.substr(3) if id.begins_with("up:") else id


static func get_part(id: String) -> Dictionary:
	return CATALOG.get(base_of(id), {})


static func part_name(id: String) -> String:
	if id == "":
		return "-"
	return CATALOG[base_of(id)]["name"] + (" ★" if is_up(id) else "")


static func slot_of(id: String) -> String:
	return CATALOG[base_of(id)]["slot"]


static func num(id: String, key: String) -> float:
	return float(CATALOG[id][key])


## 이 알에서 부품이 실제로 작동할 수 있는지. 조건이 안 맞으면 이유를 돌려준다.
static func unmet_need(id: String, stone_parts: Dictionary) -> String:
	var need: String = CATALOG.get(id, {}).get("needs", "")
	if need == "bullet" and not BULLET_WEAPONS.has(stone_parts.get("weapon", "")):
		return "탄환 무기(콩알총·산탄총)가 있어야 작동"
	return ""


static func set_of(id: String) -> String:
	if is_up(id):
		return ""
	return CATALOG.get(id, {}).get("set", "")


static func is_anime(id: String) -> bool:
	return CATALOG.get(base_of(id), {}).get("anime", false)


## 이 알에 달린 부품이 속한 세트 중 가장 많이 모인 것. 없으면 "".
static func main_set(stone_parts: Dictionary) -> String:
	var best := ""
	var best_n := 0
	for sid in SETS:
		var n: int = set_progress(stone_parts, sid)["count"]
		if n > best_n:
			best_n = n
			best = sid
	return best


## 이 알에 달린 세트 부품 수. {set, count, missing:[id]}
static func set_progress(stone_parts: Dictionary, set_id := "") -> Dictionary:
	if set_id == "":
		set_id = main_set(stone_parts)
		if set_id == "":
			return {"set": "", "count": 0, "missing": [], "total": 3}
	var have := 0
	var missing: Array = []
	for pid in SETS[set_id]["parts"]:
		if stone_parts.values().has(pid):
			have += 1
		else:
			missing.append(pid)
	return {"set": set_id, "count": have, "missing": missing, "total": SETS[set_id]["parts"].size()}


## set_id 를 비우면 어느 세트든 완성됐는지.
static func set_complete(stone_parts: Dictionary, set_id := "") -> bool:
	if set_id == "":
		for sid in SETS:
			if set_complete(stone_parts, sid):
				return true
		return false
	return set_progress(stone_parts, set_id)["count"] == SETS[set_id]["parts"].size()


## 예: "메카 티라노 2/3 · 다리 필요". set_id 를 비우면 이 알에서 가장 많이 모인 세트.
static func set_label(stone_parts: Dictionary, set_id := "") -> String:
	if set_id == "":
		set_id = main_set(stone_parts)
		if set_id == "":
			return ""
	var pr := set_progress(stone_parts, set_id)
	if pr["count"] == 0:
		return ""
	var st: Dictionary = SETS[set_id]
	if pr["count"] == pr["total"]:
		return "%s 완성 · %s" % [st["name"], st["move"]]
	var need: Array = []
	for m in pr["missing"]:
		need.append(st["short"][m])
	return "%s %d/%d · %s 필요" % [st["name"], pr["count"], pr["total"], "·".join(need)]



# ── 부품 업그레이드 (확장 기획 「부품 업그레이드」) ─────────────
## 강화(★)는 부품마다 한 단계. 공용 4종과 공방 전용 단품만 (세트 부품·연구소 부품 제외).
const UPGRADES := {
	"pea": "정면 두 발 연사", "shotgun": "부채꼴 다섯 발", "claw": "붙잡은 뒤 조준 방향으로 던지기",
	"nose": "정면 충돌 두 번까지 세게", "magnet": "범위 4.5칸, 가까운 두 알", "bumper": "측면 충돌 두 번까지",
	"flipper": "양옆으로 한 번씩", "rocket": "가속 1.5배", "retro": "후퇴 1.5배", "chute": "두 번 급제동",
	"sucker": "맞은 알을 멈추고 내 쪽으로 1칸 당기기", "brake": "멈출 때 주변 1칸의 알을 살짝 밀기",
	"mine": "지뢰 범위 1.5배", "shadow_scale": "60%를 옆 알에", "night_charm": "저주의 그림자가 1.8배로 밀친다",
	"anchor": "돌아온 자리 주변 알을 밀어낸다", "drift_tire": "가장자리를 더 빠르게 멀리 달린다", "flash_step": "착지 뒤 앞으로 한 번 더 밀고 나간다",
	"log_sub": "통나무가 더 세게 튕겨 낸다", "trap_card": "되돌린 알을 1바퀴 동안 느리게", "rubber_fist": "뻗는 거리 1.5배",
	"charge_palm": "빔이 1.4배 세게 민다", "hook": "1.6배 세게 끌어온다", "copier": "포탑이 두 발을 쏜다", "carousel": "던지는 거리 1.5배",
	"crab": "좌우로 한 번씩, 두 번 튄다", "echo_bell": "충격파가 두 번 퍼진다", "moon_well": "원의 지름 1.5배",
	"wind_knot": "바람이 1.6배 더 꺾는다", "side_scroll": "꺾이는 위치를 조준 힘으로 정한다", "at_field": "장벽이 두 번까지 버틴다",
	"stopwatch": "1초 동안 멈춘다", "rebound_shoes": "1.4배 세게 뛰어든다", "alchemy_glove": "돌벽을 두 개 세운다",
}
const UP_TWICE := ["nose", "bumper"]
const UP_NUM := {
	"magnet": {"range": 1.5}, "rocket": {"power": 1.5}, "retro": {"power": 1.5}, "shadow_scale": {"share": 1.5},
	"rubber_fist": {"reach": 1.5}, "charge_palm": {"power": 1.4}, "hook": {"power": 1.6}, "carousel": {"power": 1.0},
	"stopwatch": {"time": 2.0}, "rebound_shoes": {"power": 1.4}, "drift_tire": {"dist": 2.0}, "at_field": {"power": 1.4},
	"wind_knot": {"turn_deg": 1.6}, "night_charm": {"power": 1.8}, "trap_card": {}, "sucker": {}, "brake": {},
}


static func upgradable(part: String) -> bool:
	return UPGRADES.has(part) and set_of(part) == ""
