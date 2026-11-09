extends RefCounted
## 맵 테마 (디자인 사양 「맵 테마 색 표」). 경기장과 HUD가 모두 이 값을 읽는다.
## 새 맵은 THEMES 에 한 항목, ORDER 에 이름 하나만 늘리면 된다.

## "auto": 공방 따라가기 — 그날 공방의 경기장 (디자인 「오늘의 공방 프로토타입」).
const ORDER := ["auto", "play", "workshop", "neon"]
const WS_THEME := {"junk": "ws_junk", "magic": "ws_magic", "toon": "ws_toon"}

const THEMES := {
	"play": {
		"name": "밝은 놀이판",
		"bg": Color("E9D5AE"), "grain": Color(120 / 255.0, 80 / 255.0, 30 / 255.0, 0.10), "bg_center": Color("E9D5AE"),
		"rail_hi": Color("D9A46A"), "rail": Color("B77F45"), "rail_lo": Color("7E5228"), "rail_glow": Color(0, 0, 0, 0),
		"felt_c": Color("57C98A"), "felt_e": Color("2F9461"), "grid": false,
		"danger": Color("FF6B57"), "danger_line": Color(1, 1, 1, 0.75),
		"outline": Color("1A1D21"), "shadow": Color(40 / 255.0, 25 / 255.0, 10 / 255.0, 0.32),
		"spark": Color("FFE08A"), "light": 0.16,
		"panel": Color(1.0, 251 / 255.0, 242 / 255.0, 0.86), "text": Color("1B1E22"), "sub": Color("5A5F66"),
		"line": Color(90 / 255.0, 60 / 255.0, 20 / 255.0, 0.18), "accent_bg": Color(183 / 255.0, 127 / 255.0, 69 / 255.0, 0.18),
		"gauge": Color("E0533D"), "gold": Color("A8641F"), "dark": false,
		"accent": Color("B77F45"), "accent_ink": Color.WHITE,
	},
	"workshop": {
		"name": "장난감 공방",
		"bg": Color("5B3E28"), "grain": Color(0, 0, 0, 0.16), "bg_center": Color("5B3E28"),
		"rail_hi": Color("E8C98A"), "rail": Color("C9A15A"), "rail_lo": Color("8C6A2E"), "rail_glow": Color(0, 0, 0, 0),
		"felt_c": Color("3C8C77"), "felt_e": Color("2A6656"), "grid": true,
		"danger": Color("FFB347"), "danger_line": Color(1.0, 230 / 255.0, 180 / 255.0, 0.85),
		"outline": Color("16130F"), "shadow": Color(0, 0, 0, 0.38),
		"spark": Color("FFD27A"), "light": 0.10,
		"panel": Color(245 / 255.0, 236 / 255.0, 214 / 255.0, 0.92), "text": Color("2A1E12"), "sub": Color("6B5A45"),
		"line": Color(60 / 255.0, 40 / 255.0, 20 / 255.0, 0.25), "accent_bg": Color(201 / 255.0, 161 / 255.0, 90 / 255.0, 0.30),
		"gauge": Color("C9A15A"), "gold": Color("8C5A1E"), "dark": false,
		"accent": Color("C9A15A"), "accent_ink": Color("2A1E12"),
	},
	"neon": {
		"name": "선명한 다크",
		"bg": Color("0E1430"), "grain": Color(0, 0, 0, 0), "bg_center": Color("151D45"),
		"rail_hi": Color("5CE1E6"), "rail": Color("1F2A5C"), "rail_lo": Color("0A1030"), "rail_glow": Color("5CE1E6"),
		"felt_c": Color("22B3A0"), "felt_e": Color("11756C"), "grid": false,
		"danger": Color("FF4FA3"), "danger_line": Color(1.0, 140 / 255.0, 200 / 255.0, 0.9),
		"outline": Color("070A18"), "shadow": Color(0, 0, 0, 0.5),
		"spark": Color("9DF6FF"), "light": 0.12,
		"panel": Color(20 / 255.0, 28 / 255.0, 66 / 255.0, 0.78), "text": Color("F3F6FF"), "sub": Color("AAB4D6"),
		"line": Color(92 / 255.0, 225 / 255.0, 230 / 255.0, 0.25), "accent_bg": Color(92 / 255.0, 225 / 255.0, 230 / 255.0, 0.16),
		"gauge": Color("5CE1E6"), "gold": Color("FFD27A"), "dark": true,
		"accent": Color("5CE1E6"), "accent_ink": Color("0E1430"),
	},
	# ── 공방 경기장 ──
	"ws_junk": {
		"name": "고물 정비소", "deco": "junk", "panel_style": "junk",
		"bg": Color("33383D"), "grain": Color(0, 0, 0, 0), "bg_center": Color("33383D"), "bg2": Color("2A2E33"),
		"rail_hi": Color("5A6068"), "rail": Color("2B2F34"), "rail_lo": Color("16191C"), "rail_glow": Color(0, 0, 0, 0),
		"felt_c": Color("4F8F78"), "felt_e": Color("2E5E50"), "grid": false,
		"danger": Color("FFC23D"), "danger_line": Color(1.0, 214 / 255.0, 110 / 255.0, 0.9),
		"outline": Color("15181B"), "shadow": Color(0, 0, 0, 0.42), "spark": Color("FFD27A"), "light": 0.12,
		"panel": Color(26 / 255.0, 29 / 255.0, 32 / 255.0, 0.84), "text": Color("F1F2EE"), "sub": Color("B4BAB3"),
		"line": Color(1.0, 194 / 255.0, 61 / 255.0, 0.25), "accent_bg": Color(1.0, 194 / 255.0, 61 / 255.0, 0.16),
		"gauge": Color("FFC23D"), "gold": Color("FFC23D"), "dark": true, "accent": Color("FFC23D"), "accent_ink": Color("1A1A1A"),
	},
	"ws_magic": {
		"name": "수상한 마법 상점", "deco": "magic", "panel_style": "magic",
		"bg": Color("17153A"), "grain": Color(0, 0, 0, 0), "bg_center": Color("2A2463"), "bg2": Color("2A2463"),
		"rail_hi": Color("8A74C8"), "rail": Color("3A2A55"), "rail_lo": Color("1C1433"), "rail_glow": Color(0, 0, 0, 0),
		"felt_c": Color("6A50B8"), "felt_e": Color("36256E"), "grid": false,
		"danger": Color("7FE0FF"), "danger_line": Color(190 / 255.0, 240 / 255.0, 1.0, 0.9),
		"outline": Color("0D0A20"), "shadow": Color(0, 0, 0, 0.5), "spark": Color("C9D5FF"), "light": 0.12,
		"panel": Color(24 / 255.0, 20 / 255.0, 58 / 255.0, 0.82), "text": Color("F1EEFF"), "sub": Color("B7B0DE"),
		"line": Color(183 / 255.0, 200 / 255.0, 1.0, 0.25), "accent_bg": Color(183 / 255.0, 200 / 255.0, 1.0, 0.14),
		"gauge": Color("B7C8FF"), "gold": Color("B7C8FF"), "dark": true, "accent": Color("B7C8FF"), "accent_ink": Color("17153A"),
	},
	"ws_toon": {
		"name": "만화 소품 창고", "deco": "manga", "panel_style": "manga",
		"bg": Color("F3EEE2"), "grain": Color(0, 0, 0, 0), "bg_center": Color("F3EEE2"), "bg2": Color("E4DCC8"),
		"rail_hi": Color("3A3A3A"), "rail": Color("151515"), "rail_lo": Color("000000"), "rail_glow": Color(0, 0, 0, 0),
		"felt_c": Color("FFFDF6"), "felt_e": Color("EDE6D4"), "grid": false,
		"danger": Color("E04E3A"), "danger_line": Color(20 / 255.0, 20 / 255.0, 20 / 255.0, 0.85),
		"outline": Color("111111"), "shadow": Color(0, 0, 0, 0.22), "spark": Color("111111"), "light": 0.0,
		"panel": Color(1.0, 253 / 255.0, 246 / 255.0, 0.94), "text": Color("141414"), "sub": Color("55524B"),
		"line": Color(0, 0, 0, 0.85), "accent_bg": Color(224 / 255.0, 78 / 255.0, 58 / 255.0, 0.14),
		"gauge": Color("E04E3A"), "gold": Color("E04E3A"), "dark": false, "accent": Color("E04E3A"), "accent_ink": Color.WHITE,
	},
}

const AUTO_NAME := "공방 따라가기"


## map: 고른 맵("auto" 포함), ws: 그날 공방 → 실제로 그릴 테마 id
static func resolve(map: String, ws: String) -> String:
	if map == "auto":
		return WS_THEME.get(ws, "play")
	return map if THEMES.has(map) else "play"


static func get_theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES["play"])
