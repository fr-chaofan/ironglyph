## 過場步驟播放器測試（Task 4.0）
##
## 這支測試把 DialogueBox 的 `pauses_game` 關掉。`play_steps()` 本身是 coroutine，
## 驗證它必須 await 影格／signal；若對話同時把整棵樹暫停，GUT 的等待也會跟著停住。
## 「對話期間確實會暫停」由 test_dialogue_box.gd 以同步方式單獨驗證。
extends GutTest

const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")
const CutscenePlayerScript := preload("res://scripts/cutscene_player.gd")
const FIXTURE_DIR := "res://tests/fixtures/dialogue"

var _root: Node
var _box: DialogueBox
var _cutscene: CutscenePlayer


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)

	_box = DialogueBoxScene.instantiate() as DialogueBox
	_box.name = "DialogueBox"
	_box.dialogue_dir = FIXTURE_DIR
	_box.chars_per_second = 0.0
	_box.pauses_game = false
	_root.add_child(_box)

	_cutscene = CutscenePlayerScript.new() as CutscenePlayer
	_cutscene.name = "CutscenePlayer"
	_cutscene.dialogue_box_path = ^"../DialogueBox"
	_root.add_child(_cutscene)


func after_each() -> void:
	get_tree().paused = false


func test_依序執行步驟並在最後送出cutscene_finished() -> void:
	watch_signals(_cutscene)

	await _cutscene.play_steps([
		{"type": "signal", "name": "light_on"},
		{"type": "wait", "seconds": 0.05},
		{"type": "signal", "name": "light_off"},
	])

	assert_signal_emit_count(_cutscene, "cue", 2)
	assert_signal_emit_count(_cutscene, "step_started", 3)
	assert_signal_emit_count(_cutscene, "cutscene_finished", 1)
	assert_false(_cutscene.is_playing())


func test_對話步驟播完才繼續下一步() -> void:
	watch_signals(_cutscene)

	# 不 await：讓過場跑到「等對話結束」那一步就停住，才能檢查它確實在等。
	_cutscene.play_steps([
		{"type": "dialogue", "id": "test_dialogue"},
		{"type": "signal", "name": "after_dialogue"},
	])
	await wait_process_frames(1)

	assert_true(_box.is_active(), "過場應該停在對話這一步")
	assert_signal_not_emitted(_cutscene, "cue", "對話還沒播完不該執行下一步")

	_advance_until_finished()
	await wait_for_signal(_cutscene.cutscene_finished, 1.0)

	assert_signal_emitted_with_parameters(_cutscene, "cue", ["after_dialogue"])
	assert_false(_cutscene.is_playing())


func test_台詞找不到時過場不會卡在等待對話() -> void:
	# 缺檔的話 DialogueBox 會同步送出 dialogue_finished，
	# 過場若無條件 await 那個 signal 就會永遠等下去。
	watch_signals(_cutscene)

	await _cutscene.play_steps([
		{"type": "dialogue", "id": "no_such_dialogue"},
		{"type": "signal", "name": "reached_end"},
	])

	assert_engine_error("dialogue not found")
	assert_signal_emitted_with_parameters(_cutscene, "cue", ["reached_end"])
	assert_signal_emit_count(_cutscene, "cutscene_finished", 1)


func test_可直接餵台詞資料不經檔案() -> void:
	_cutscene.play_steps([
		{"type": "lines", "lines": [{"speaker": "主", "text": "一句"}]},
	])
	await wait_process_frames(1)

	assert_true(_box.is_active())
	_advance_until_finished()
	await wait_for_signal(_cutscene.cutscene_finished, 1.0)
	assert_false(_cutscene.is_playing())


func test_播放中不接受第二段過場() -> void:
	_cutscene.play_steps([{"type": "dialogue", "id": "test_dialogue"}])
	await wait_process_frames(1)
	assert_true(_cutscene.is_playing())

	_cutscene.play_steps([{"type": "signal", "name": "should_not_run"}])
	watch_signals(_cutscene)
	await wait_process_frames(1)

	assert_engine_error("CutscenePlayer 已在播放中")
	assert_signal_not_emitted(_cutscene, "cue", "前一段過場還沒結束不該插播")

	_advance_until_finished()
	await wait_for_signal(_cutscene.cutscene_finished, 1.0)


func test_未知步驟型別會跳過而不是中斷過場() -> void:
	watch_signals(_cutscene)

	await _cutscene.play_steps([
		{"type": "no_such_step"},
		"這不是字典",
		{"type": "signal", "name": "still_running"},
	])

	assert_engine_error("未知的過場步驟型別")
	assert_signal_emitted_with_parameters(_cutscene, "cue", ["still_running"])
	assert_signal_emit_count(_cutscene, "cutscene_finished", 1)


func test_找不到DialogueBox時過場仍會走完() -> void:
	_cutscene.dialogue_box_path = ^"../NoSuchNode"
	watch_signals(_cutscene)

	await _cutscene.play_steps([
		{"type": "dialogue", "id": "test_dialogue"},
		{"type": "signal", "name": "reached_end"},
	])

	assert_engine_error("找不到 DialogueBox")
	assert_signal_emitted_with_parameters(_cutscene, "cue", ["reached_end"])
	assert_signal_emit_count(_cutscene, "cutscene_finished", 1)


func test_主降臨過場的cue順序與台詞() -> void:
	# 光效實作屬於 Task 4.4 / 5.4，這裡只確認時序與 cue 名稱穩定。
	_box.dialogue_dir = "res://data/dialogue"
	var cues: Array = []
	_cutscene.cue.connect(func(cue_name: String) -> void: cues.append(cue_name))

	_cutscene.play_ending_zhu_descent()
	await wait_process_frames(1)

	assert_eq(cues, ["zhu_descent_light"], "降光的 cue 應在停頓之前就送出")
	assert_false(_box.is_active(), "停頓期間不該已經開始講話")

	await wait_seconds(1.2)
	assert_true(_box.is_active(), "停頓結束後應開始播「主」的訓誡")
	assert_eq(_box.lines.size(), 5, "ending_zhu_descent.json 應有五句")

	_advance_until_finished()
	await wait_for_signal(_cutscene.cutscene_finished, 1.0)

	assert_eq(cues, ["zhu_descent_light", "zhu_descent_end"], "cue 順序：先降光，台詞播完再收尾")


func _advance_until_finished() -> void:
	var guard := 0
	while _box.is_active() and guard < 32:
		_box.advance()
		guard += 1
