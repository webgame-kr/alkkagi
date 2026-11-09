extends RefCounted
## 맵 테마 (디자인 사양 「맵 테마 색 표」). 경기장과 HUD가 모두 이 값을 읽는다.
## 새 맵은 THEMES 에 한 항목, ORDER 에 이름 하나만 늘리면 된다.

const ORDER := ["play", "workshop", "neon"]

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
	},
}


static func get_theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES["play"])
