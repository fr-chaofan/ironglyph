## 漢字資料單例（autoload 名稱：HanziData）
##
## 資料來源為 Make Me a Hanzi，由 tools/build_hanzi_data.py 擷取合併後產生
## res://data/hanzi_decomposition.json。供 Task 3.4 筆畫崩解特效、部首武器拆解等使用。
##
## ⚠️ 資料集查無的字（目前為「燄」）已在建置階段跳過，不在此檔案內。
## 所有 getter 對查不到的字一律回傳空值，呼叫端需自行處理，不要假設一定有資料。
extends Node

const DATA_PATH := "res://data/hanzi_decomposition.json"

var data: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("HanziData: 無法開啟 %s（錯誤碼 %d）" % [DATA_PATH, FileAccess.get_open_error()])
		return

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("HanziData: %s 解析失敗，不是有效的JSON物件" % DATA_PATH)
		return

	data = parsed


## 是否收錄此字。呼叫端在用其他getter前應先檢查，或自行處理空回傳值。
func has_character(character: String) -> bool:
	return data.has(character)


## 筆畫SVG path字串陣列；查無此字回傳空陣列
func get_strokes(character: String) -> Array:
	if data.has(character):
		return data[character].get("strokes", [])
	return []


## 筆畫中軸點（每筆一組座標陣列），可用於崩解方向/書寫動畫；查無此字回傳空陣列
func get_medians(character: String) -> Array:
	if data.has(character):
		return data[character].get("medians", [])
	return []


## IDS拆解字串，如「河」→「⿰氵可」；查無此字回傳空字串
func get_decomposition(character: String) -> String:
	if data.has(character):
		return data[character].get("decomposition", "")
	return ""


## 部首，如「河」→「氵」；查無此字回傳空字串
func get_radical(character: String) -> String:
	if data.has(character):
		return data[character].get("radical", "")
	return ""


## 目前收錄的所有字，供除錯/覆蓋率檢查用
func get_all_characters() -> Array:
	return data.keys()
