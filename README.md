# 개조 알까기

알을 튕겨 상대를 판 밖으로 밀어내고, 바퀴가 지날 때마다 부품을 골라 내 알에 장착하는 2~8인 턴제 대전. Godot 4.7 (2D, GL Compatibility)로 만들고 웹으로 내보낸다.

- 같은 기기에서 번갈아 조준하는 로컬 대전. 자리마다 사람/CPU를 고를 수 있다.
- 부품 20종 (무기 7 · 보조 9 · 추진 4), 알 하나에 무기·보조·추진 슬롯 하나씩.
- 2인 정사각형 판(알 3개, 12바퀴), 3~4인 원형(알 2개, 8바퀴), 5~8인 넓은 원형(알 2개, 6바퀴, 개조가 1바퀴부터, 조준 8초 기본).

## 실행

### Godot 설치 (Windows)

```bash
winget install --id GodotEngine.GodotEngine -e
```

또는 https://godotengine.org/download/windows 에서 **Godot 4.7 (Standard)** zip을 받아 압축을 풀면 바로 실행된다. 설치 후 Godot을 열고 **가져오기(Import)** → 이 폴더의 `project.godot` 선택 → **F5**로 실행.

웹으로 내보내려면 export templates가 필요하다. 에디터에서 **편집기 → 내보내기 템플릿 관리 → 다운로드 및 설치**를 한 번 해 두면 된다.

### 웹 빌드

```bash
godot --headless --path . --export-release "Web" docs/index.html
python -m http.server 3700 --directory docs
```

`http://localhost:3700`. 스레드를 쓰지 않는 웹 빌드라 GitHub Pages처럼 특별한 헤더가 없는 정적 호스팅에서 그대로 돈다. 저장소 설정의 Pages를 `main` 브랜치 `/docs` 폴더로 두면 된다.

## 구조

판정·물리·연출을 나눴다. `scripts/sim/` 은 화면 없이 돌아가며, 같은 입력이면 항상 같은 결과가 나온다 (온라인 대전 때 모두가 같은 충돌을 보게 하기 위한 바탕).

| 파일 | 내용 |
|---|---|
| `scripts/sim/parts_data.gd` | 부품 20종의 슬롯, 발동 시점, 설명, 충격량·사거리 같은 수치 |
| `scripts/sim/parts.gd` | 부품 효과: 발사·첫 충돌·측면 충돌·정지 사건에 반응. 조준선 미리보기 |
| `scripts/sim/world.gd` | 고정 간격(1/120초) 원형 알 물리, 탄환, 거울·지뢰·방울·포탑, 탈락 판정. 복제해서 미리 돌려볼 수 있다 |
| `scripts/sim/match.gd` | 차례, 바퀴, 시작 자리 넘기기, 개조 일정, 장착, 승패(최후 1인 / 바퀴 제한 시 남은 알 수 / 무승부) |
| `scripts/sim/bot.gd` | CPU: 후보 샷을 세계 복제본에서 돌려 보고 고른 뒤 사람처럼 약간 빗나가게 쏜다 |
| `scripts/game.gd` | 입력(당겨서 쏘기), 그리기, HUD, 개조 카드, 결과 화면 |
| `scripts/stone_art.gd` | 알과 부품 실루엣 |

## 테스트와 수치 검증

```bash
GODOT=godot tests/run.sh                                         # 판정·물리·부품 25개
godot --headless --path . -s res://tests/smoke_game.gd -- 4      # 화면 코드로 CPU끼리 한 판
godot --headless --path . -s res://tools/simulate.gd -- 4 30     # 경기 길이·탈락률·부품 작동 횟수
```

현재 시험값에서 CPU끼리 둔 결과 (봇은 실제보다 정확하므로 사람끼리면 더 길어진다):

| 인원 | 평균 바퀴 | 탈락이 나온 샷 | 바퀴 제한으로 끝난 판 |
|---|---|---|---|
| 2인 | 6.4 / 12 | 37% | 6% |
| 4인 | 5.6 / 8 | 39% | 13% |
| 6인 | 6.0 / 6 | 36% | 85% |

5~8인은 6바퀴 제한에 대부분 걸린다. 기획서의 시험값 그대로이며, 다인전 바퀴 수는 플레이 테스트 후 조정할 값이다.

## 개발용 실행 인자

```bash
godot --path . -- --auto 4            # 설정 화면 없이 4인전 시작 (빨강만 사람)
godot --path . -- --auto 6 --draft    # 개조 화면부터
godot --path . -- --auto 4 --allcpu --shots <폴더>   # CPU끼리 3배속, 1.5초마다 화면 저장
```

## 아직 없는 것

- 친구 초대형 온라인 대전 (기획서 제작 순서 5단계)
- 온라인용 동시 선택·공개 (로컬은 시작 순서대로 고른다)
- 효과음

폰트: IBM Plex Sans KR (SIL Open Font License, `fonts/OFL.txt`). 비주얼은 디자인 시안 「개조 알까기 디자인 시안」(펠트 테이블, 금속 퍽, 퍽 지름 = 1칸)을 따른다.
