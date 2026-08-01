## 對話框元件測試（Task 4.0）
##
## ⚠️ 這支測試刻意**全部同步**推進對話，不在對話進行中 await 影格。
## `DialogueBox` 播放時會把整棵樹暫停，GUT 自己的等待也跑在同一棵樹上，
## 在暫停狀態下 await 會直接把整個測試流程卡死。需要驗證打字機時，
## 改成手動呼叫 `_process(delta)` 餵固定 delta，結果也比等真實影格穩定。
extends GutTest

const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")
const FIXTURE_DIR := "res://tests/fixtures/dialogue"
const CHOICES := [
	{"id": "greed", "label": "貪（拾取）"},
	{"id": "fight", "label": "爭（格擋彈反）"},
	{"id": "release", "label": "棄（不碰）"},
]

var _box: DialogueBox
var _label: Label


func before_each() -> void:
	_box = DialogueBoxScene.instantiate() as DialogueBox
	_box.dialogue_dir = FIXTURE_DIR
	# 預設關掉打字機，讓多數測試專注在推進邏輯；打字機測試自己開。
	_box.chars_per_second = 0.0
	add_child_autofree(_box)
	_label = _box.get_node(^"Panel/Label") as Label


func after_each() -> void:
	# 測試中途失敗會讓樹卡在暫停狀態，後面每一支測試都會跟著死，一律強制解除。
	get_tree().paused = false


func test_三句台詞逐句推進到最後結束() -> void:
	watch_signals(_box)
	_box.play("test_dialogue")

	assert_true(_box.is_active(), "play() 之後應處於對話狀態")
	assert_true(_box.visible)
	assert_eq(_box.get_current_line().get("text", ""), "第一句")
	assert_eq((_box.get_node(^"Panel/SpeakerLabel") as Label).text, "甲")

	_box.advance()
	assert_eq(_box.get_current_line().get("text", ""), "第二句")
	assert_eq(_label.text, "第二句")

	_box.advance()
	assert_eq(_box.get_current_line().get("text", ""), "第三句")
	assert_signal_not_emitted(_box, "dialogue_finished", "還沒播完不應送出 finished")

	_box.advance()
	assert_signal_emit_count(_box, "dialogue_finished", 1)
	assert_false(_box.is_active())
	assert_false(_box.visible, "播完必須把對話框收起來")


func test_對話期間暫停整棵樹播完自動恢復() -> void:
	assert_false(get_tree().paused, "前置條件：測試開始時不應處於暫停")

	_box.play("test_dialogue")
	assert_true(get_tree().paused, "對話期間必須暫停，否則玩家可以邊講話邊跑")

	for i in 3:
		_box.advance()

	assert_false(get_tree().paused, "對話結束必須恢復遊戲")


func test_原本就暫停時對話結束不會誤解除暫停() -> void:
	# 階段六的暫停選單裡觸發對話時，對話結束不該把暫停選單一起關掉。
	get_tree().paused = true

	_box.play("test_dialogue")
	for i in 3:
		_box.advance()

	assert_true(get_tree().paused, "播放前就暫停的話，結束後應維持暫停")


func test_找不到台詞檔不暫停也不卡住流程() -> void:
	watch_signals(_box)
	_box.play("no_such_dialogue")

	assert_engine_error("dialogue not found", "缺檔要留下警告，不能安靜跳過")
	assert_signal_emit_count(_box, "dialogue_finished", 1, "缺檔也要送出 finished，呼叫端才能往下走")
	assert_false(_box.is_active())
	assert_false(get_tree().paused, "缺檔不可以把遊戲留在暫停狀態")


func test_台詞檔格式錯誤時視同缺檔() -> void:
	watch_signals(_box)
	_box.play("test_malformed")

	assert_engine_error("dialogue 格式錯誤")
	assert_engine_error("dialogue not found")
	assert_signal_emit_count(_box, "dialogue_finished", 1)
	assert_false(_box.is_active())
	assert_false(get_tree().paused)


func test_空台詞陣列直接結束且不進入暫停() -> void:
	watch_signals(_box)
	_box.play_lines([])

	assert_signal_emit_count(_box, "dialogue_finished", 1)
	assert_false(_box.is_active())
	assert_false(get_tree().paused, "空台詞不該讓畫面閃一下暫停")


func test_打字機逐字顯示且推進鍵先補完整句() -> void:
	_box.chars_per_second = 10.0
	_box.play_lines([
		{"speaker": "仁", "text": "跪下，見證朕的完整。"},
		{"speaker": "令", "text": "第二句"},
	])

	assert_eq(_label.visible_characters, 0, "剛開始應該一個字都還沒顯示")

	_box._process(0.3)
	assert_eq(_label.visible_characters, 3, "0.3秒 × 10字/秒 應顯示3個字")

	_box.advance()
	assert_eq(_label.visible_characters, -1, "打字未完成時第一次推進應先補完整句")
	assert_eq(_box.current_index, 0, "補完整句不可以同時跳到下一句")

	_box.advance()
	assert_eq(_box.current_index, 1, "整句顯示完後再推進才換句")


func test_打字機跑完整句後自動停止() -> void:
	_box.chars_per_second = 10.0
	_box.play_lines([{"speaker": "", "text": "四個字元"}])

	_box._process(1.0)
	assert_eq(_label.visible_characters, -1, "字數跑完應整句顯示")

	# 再跑一次不應該出錯或把 visible_characters 弄回部分顯示
	_box._process(1.0)
	assert_eq(_label.visible_characters, -1)


func test_每顯示一句送出line_shown() -> void:
	watch_signals(_box)
	_box.play("test_dialogue")

	assert_signal_emitted_with_parameters(
		_box, "line_shown", [0, {"speaker": "甲", "text": "第一句"}]
	)
	_box.advance()
	assert_signal_emit_count(_box, "line_shown", 2)


func test_播放中再次呼叫play不會打斷目前對話() -> void:
	_box.play("test_dialogue")
	_box.advance()

	_box.play("test_choice")

	assert_engine_error("已在播放中")
	assert_eq(_box.get_current_line().get("text", ""), "第二句", "應維持在原本那段對話")
	assert_eq(_box.lines.size(), 3)


func test_選擇型對話播完台詞才出現選項並送出choice_made() -> void:
	watch_signals(_box)
	_box.play_choice("test_choice", CHOICES)

	assert_true(_box.choices.is_empty(), "台詞還沒播完不該先跳出選項")
	_box.advance()

	assert_eq(_box.choices.size(), 3, "最後一句之後應進入選項狀態")
	assert_true(_box.is_active(), "選項還沒選之前對話不算結束")
	assert_signal_not_emitted(_box, "dialogue_finished")
	assert_eq(_box.get_selected_choice_id(), "greed", "預設停在第一個選項")

	_box.move_choice_cursor(1)
	assert_eq(_box.get_selected_choice_id(), "fight")

	_box.advance()
	assert_signal_emitted_with_parameters(_box, "choice_made", ["fight"])
	assert_signal_emit_count(_box, "dialogue_finished", 1, "選完才算整段結束")
	assert_false(get_tree().paused)


func test_選項游標在頭尾繞回() -> void:
	_box.play_lines_with_choice([{"speaker": "", "text": "要接住嗎？"}], CHOICES)

	_box.move_choice_cursor(-1)
	assert_eq(_box.get_selected_choice_id(), "release", "從第一項往前應繞到最後一項")

	_box.move_choice_cursor(1)
	assert_eq(_box.get_selected_choice_id(), "greed", "從最後一項往後應繞回第一項")


func test_沒有前導台詞也能單獨呈現選項() -> void:
	_box.play_lines_with_choice([], CHOICES)

	assert_true(_box.is_active())
	assert_eq(_box.choices.size(), 3)


func test_選項按鈕不會重複堆積() -> void:
	var container := _box.get_node(^"Panel/ChoiceContainer") as BoxContainer
	_box.play_lines_with_choice([{"speaker": "", "text": "要接住嗎？"}], CHOICES)

	assert_eq(container.get_child_count(), 3)
	assert_true(container.visible)

	_box.move_choice_cursor(1)
	_box.move_choice_cursor(1)
	assert_eq(container.get_child_count(), 3, "重畫游標不可以把舊的選項 Label 留在容器裡")

	_box.advance()
	assert_eq(container.get_child_count(), 0, "選完必須清空選項")
	assert_false(container.visible)


func test_對外的台詞資料是深拷貝() -> void:
	var source: Array = [{"speaker": "令", "text": "原句"}]
	_box.play_lines(source)

	var line := _box.get_current_line()
	line["text"] = "被外部改掉"

	assert_eq(_box.get_current_line().get("text", ""), "原句", "get_current_line 應回傳拷貝")
	assert_eq(String((source[0] as Dictionary).get("text", "")), "原句", "play_lines 不該持有呼叫端的原始字典")


func test_未播放時推進不會有任何作用() -> void:
	watch_signals(_box)

	_box.advance()
	_box.move_choice_cursor(1)

	assert_signal_not_emitted(_box, "dialogue_finished")
	assert_false(_box.visible)
