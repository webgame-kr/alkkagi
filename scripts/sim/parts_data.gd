extends RefCounted
## 부품 데이터. 슬롯, 발동 시점, 설명, 충격량 같은 수치를 한곳에서 관리한다.
## 효과를 실행하는 코드는 parts.gd 에 있다.

const SLOT_LABEL := {"weapon": "무기", "aux": "보조", "prop": "추진"}
const SLOTS := ["weapon", "aux", "prop"]

## power: 상대 알에 주는 속도 변화(px/s). range: 작동 거리(px).
const CATALOG := {
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
	"hero_band": {"name": "주인공 머리띠", "slot": "weapon", "when": "마지막 알의 약한 샷", "set": "hero",
		"desc": "내 마지막 알을 힘 50% 이하로 쏘면, 몸통보다 먼저 정면으로 짧은 충격파를 보낸다.",
		"max_power": 0.5, "range": 160.0, "power": 330.0},
	"torn_cape": {"name": "찢어진 망토", "slot": "aux", "when": "상대가 처음 떨어질 때", "set": "hero",
		"desc": "내 샷에서 처음으로 상대 알이 떨어지면, 아직 판 위에 있는 발사 알을 즉시 멈춘다."},
	"awaken_shoes": {"name": "각성 운동화", "slot": "prop", "when": "마지막 알의 첫 충돌 직후", "set": "hero",
		"desc": "내 마지막 알을 쏘면 첫 충돌 직후 조준 방향으로 한 번 더 달려든다.",
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
	"hero": {"name": "최후의 주인공", "parts": ["hero_band", "torn_cape", "awaken_shoes"],
		"move": "라스트 컷", "short": {"hero_band": "머리띠", "torn_cape": "망토", "awaken_shoes": "운동화"}},
}

## 장착할 때 좌우를 고르는 부품. 보조는 Stone.magnet_side, 추진은 Stone.prop_side 에 저장.
const SIDE_PARTS := ["magnet", "shield", "crab", "side_scroll"]

## 탄환을 쏘는 무기(데칼코마니 포신의 조건).
const BULLET_WEAPONS := ["pea", "shotgun"]


static func ids() -> Array:
	return CATALOG.keys()


static func get_part(id: String) -> Dictionary:
	return CATALOG.get(id, {})


static func part_name(id: String) -> String:
	if id == "":
		return "-"
	return CATALOG[id]["name"]


static func slot_of(id: String) -> String:
	return CATALOG[id]["slot"]


static func num(id: String, key: String) -> float:
	return float(CATALOG[id][key])


## 이 알에서 부품이 실제로 작동할 수 있는지. 조건이 안 맞으면 이유를 돌려준다.
static func unmet_need(id: String, stone_parts: Dictionary) -> String:
	var need: String = CATALOG.get(id, {}).get("needs", "")
	if need == "bullet" and not BULLET_WEAPONS.has(stone_parts.get("weapon", "")):
		return "탄환 무기(콩알총·산탄총)가 있어야 작동"
	return ""


static func set_of(id: String) -> String:
	return CATALOG.get(id, {}).get("set", "")


static func is_anime(id: String) -> bool:
	return CATALOG.get(id, {}).get("anime", false)


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
static func set_progress(stone_parts: Dictionary, set_id := "trex") -> Dictionary:
	var have := 0
	var missing: Array = []
	for pid in SETS[set_id]["parts"]:
		if stone_parts.values().has(pid):
			have += 1
		else:
			missing.append(pid)
	return {"set": set_id, "count": have, "missing": missing, "total": SETS[set_id]["parts"].size()}


static func set_complete(stone_parts: Dictionary, set_id := "trex") -> bool:
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
