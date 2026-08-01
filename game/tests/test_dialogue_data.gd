## 台詞資料表檢查（Task 4.0）
##
## 台詞是純資料、由多人／多agent並行編輯，最容易出的兩種錯都不會在執行時報錯：
## 1. JSON 打錯結構 → 對話直接不播，玩家只看到畫面卡一下
## 2. 混進簡體字或字型沒收錄的罕用字 → 安靜地顯示成簡體或豆腐方框（GDD 第0節）
##
## 這裡把 `data/dialogue/` 下所有台詞檔掃一遍，讓上述問題在 CI 就擋下來。
extends GutTest

const DIALOGUE_DIR := "res://data/dialogue"
const FONT_PATH := "res://assets/fonts/NotoSansTC-Bold.otf"

## 只列**簡體專有**的字形（繁體正字另有寫法），共用字不列，避免誤判。
const SIMPLIFIED_CHARS := [
	"们", "个", "这", "么", "见", "说", "语", "万", "与", "义",
	"会", "来", "为", "学", "实", "写", "单", "双", "变", "时",
	"对", "国", "开", "门", "问", "间", "闻", "车", "东", "远",
	"还", "进", "边", "产", "养", "无", "书", "买", "乐",
]

var _font: FontFile
var _files: PackedStringArray


func before_all() -> void:
	_font = load(FONT_PATH)
	_files = _list_dialogue_files()


func test_台詞目錄存在且至少有一個台詞檔() -> void:
	assert_true(DirAccess.dir_exists_absolute(DIALOGUE_DIR), "缺少台詞目錄 %s" % DIALOGUE_DIR)
	assert_gt(_files.size(), 0, "台詞目錄是空的")


func test_每個台詞檔都是合法schema() -> void:
	for file_name: String in _files:
		var data := _load(file_name)
		assert_false(data.is_empty(), "%s 不是合法的 JSON 物件" % file_name)
		if data.is_empty():
			continue

		var dialogue_id := String(data.get("id", ""))
		assert_eq(
			dialogue_id, file_name.get_basename(),
			"%s 的 id 欄位應與檔名一致，否則 play(id) 會找不到檔案" % file_name
		)

		var lines: Variant = data.get("lines", null)
		assert_eq(typeof(lines), TYPE_ARRAY, "%s 缺少 lines 陣列" % file_name)
		if typeof(lines) != TYPE_ARRAY:
			continue
		assert_gt((lines as Array).size(), 0, "%s 的 lines 是空的" % file_name)

		for i in (lines as Array).size():
			var line: Variant = (lines as Array)[i]
			assert_eq(typeof(line), TYPE_DICTIONARY, "%s 第%d句不是物件" % [file_name, i])
			if typeof(line) != TYPE_DICTIONARY:
				continue
			assert_true((line as Dictionary).has("speaker"), "%s 第%d句缺 speaker（旁白用空字串）" % [file_name, i])
			assert_false(
				String((line as Dictionary).get("text", "")).strip_edges().is_empty(),
				"%s 第%d句的 text 是空的" % [file_name, i]
			)


func test_台詞用字全部有字形不會顯示成豆腐() -> void:
	for file_name: String in _files:
		for line: Dictionary in _get_lines(file_name):
			var text := String(line.get("speaker", "")) + String(line.get("text", ""))
			for i in text.length():
				var code := text.unicode_at(i)
				if code < 128:
					continue
				assert_true(
					_font.has_char(code),
					"%s 的「%s」(U+%04X) 不在字型裡，會顯示成豆腐方框" % [file_name, text[i], code]
				)


func test_台詞不可出現簡體字() -> void:
	# GDD 第0節：全專案文字一律繁體。簡體字有字形，不檢查就只會安靜地混進去。
	for file_name: String in _files:
		for line: Dictionary in _get_lines(file_name):
			var text := String(line.get("speaker", "")) + String(line.get("text", ""))
			for simplified: String in SIMPLIFIED_CHARS:
				assert_false(
					text.contains(simplified),
					"%s 含簡體字「%s」，違反 GDD 第0節語言規範：%s" % [file_name, simplified, text]
				)


func test_終Boss與終章台詞已就位() -> void:
	# Task 4.0 的兩份實際台詞；序章台詞由 Task 4.1a 補上。
	assert_has(_files, "boss_ren_intro.json", "缺少終Boss「仁」的開場白")
	assert_has(_files, "ending_zhu_descent.json", "缺少終章「主」降臨訓誡")


func _list_dialogue_files() -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(DIALOGUE_DIR)
	if dir == null:
		return files
	for file_name: String in dir.get_files():
		# 匯出後 .json 可能帶 .remap 後綴，統一去掉再判斷。
		var clean := file_name.trim_suffix(".remap")
		if clean.get_extension() == "json":
			files.append(clean)
	return files


func _load(file_name: String) -> Dictionary:
	var file := FileAccess.open("%s/%s" % [DIALOGUE_DIR, file_name], FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _get_lines(file_name: String) -> Array:
	var lines: Variant = _load(file_name).get("lines", [])
	return lines if typeof(lines) == TYPE_ARRAY else []
