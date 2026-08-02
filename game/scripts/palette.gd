## 全域色板（宣紙底 × 墨色寫字）。
##
## **全遊戲只有這一份顏色來源**：字形、子彈、刀氣、傷害數字、UI 都讀它。
## 想改基調就改 `data/palette.json`，不必四處找硬編碼的顏色——
## 訓練假人漏上色那次就是因為顏色散落在各處。
class_name Palette
extends RefCounted

const DATA_PATH := "res://data/palette.json"

static var _data: Dictionary = {}


static func load_data() -> Dictionary:
	if not _data.is_empty():
		return _data
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Palette: 無法開啟 %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Palette: %s 解析失敗" % DATA_PATH)
		return {}
	_data = parsed
	return _data


static func _color(key: String, fallback: Color) -> Color:
	var raw: Variant = load_data().get(key, null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return fallback
	return Color(float(raw[0]), float(raw[1]), float(raw[2]))


## 宣紙色。背景與筆畫之間的分隔都用它。
static func paper() -> Color:
	return _color("paper", Color(0.93, 0.90, 0.83))


## 紙的陰影／地形色
static func paper_shade() -> Color:
	return _color("paper_shade", Color(0.84, 0.80, 0.71))


## 焦墨。主角與 UI 文字。
static func ink() -> Color:
	return _color("ink", Color(0.04, 0.04, 0.04))


## 五行彩墨。回傳的是拷貝，呼叫端改不到色板本身。
static func elements() -> Dictionary:
	var raw: Variant = load_data().get("elements", {})
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: String in (raw as Dictionary):
		var value: Variant = (raw as Dictionary)[key]
		if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
			out[key] = Color(float(value[0]), float(value[1]), float(value[2]))
	return out


static func element(name: String) -> Color:
	return elements().get(name, ink())


## 兩個顏色的 RGB 距離。
##
## Godot 的 `Color` 沒有 `distance_to()`，而色板的可讀性門檻全都是用距離定義的：
## 任兩個屬性色要拉開 0.45 以上、每個屬性色離紙要 0.8 以上。
static func distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
