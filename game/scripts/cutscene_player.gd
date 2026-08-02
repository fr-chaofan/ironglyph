## 無互動過場的步驟播放器（Task 4.0）。
##
## 跟 DialogueBox 是**組合**關係而非繼承：過場本身可以插入對話，
## 但對話不需要過場。終章「主」降臨、Boss 開場光效等演出都用同一組步驟資料描述。
##
## 步驟格式（Array of Dictionary）：
## - {"type": "dialogue", "id": "boss_ren_intro"} — 播一段台詞，等玩家按完
## - {"type": "lines", "lines": [...]}            — 直接餵台詞資料，不經檔案
## - {"type": "wait", "seconds": 1.5}             — 純停頓（暫停中仍會計時）
## - {"type": "signal", "name": "zhu_descent"}    — 送出 cue，交給關卡/Boss 掛特效
##
## 具體視覺演出（白光、筆畫崩解反向播放、鏡頭震動）屬於 Task 4.4 / 5.4 的範圍，
## 這裡只負責時序與 cue，不寫死任何特效實作。
class_name CutscenePlayer
extends Node

signal cutscene_finished
signal step_started(index: int, step: Dictionary)
## 演出 cue。關卡端接這個 signal 決定要播什麼特效，過場本身不認得特效。
signal cue(cue_name: String)

@export var dialogue_box_path: NodePath = ^"../DialogueBox"

## 終章「主」降臨的台詞 id，實際演出見 Task 4.4 / 5.4。
const ENDING_ZHU_DIALOGUE_ID := "ending_zhu_descent"

var _playing: bool = false


func is_playing() -> bool:
	return _playing


## 依序執行 steps。重複呼叫會被忽略，避免兩段過場疊在一起搶 DialogueBox。
func play_steps(steps: Array) -> void:
	if _playing:
		push_warning("CutscenePlayer 已在播放中，忽略新的過場請求")
		return

	_playing = true
	for i in steps.size():
		var step: Variant = steps[i]
		if typeof(step) != TYPE_DICTIONARY:
			continue
		step_started.emit(i, (step as Dictionary).duplicate(true))
		await _run_step(step as Dictionary)
		if not is_inside_tree():
			# 過場途中場景被換掉（例如玩家死亡重載）就安靜收工，不要繼續動已失效的節點。
			_playing = false
			return

	_playing = false
	cutscene_finished.emit()


## 終章「主」降臨。台詞走 DialogueBox，光效由關卡端接 cue 掛上。
func play_ending_zhu_descent() -> void:
	await play_steps([
		{"type": "signal", "name": "zhu_descent_light"},
		{"type": "wait", "seconds": 1.0},
		{"type": "dialogue", "id": ENDING_ZHU_DIALOGUE_ID},
		{"type": "signal", "name": "zhu_descent_end"},
	])


func _run_step(step: Dictionary) -> void:
	match String(step.get("type", "")):
		"dialogue":
			await _play_dialogue_id(String(step.get("id", "")))
		"lines":
			await _play_dialogue_lines(step.get("lines", []))
		"wait":
			await _wait(float(step.get("seconds", 0.0)))
		"signal":
			cue.emit(String(step.get("name", "")))
		_:
			push_warning("未知的過場步驟型別: " + String(step.get("type", "")))


func _play_dialogue_id(dialogue_id: String) -> void:
	var box := _get_dialogue_box()
	if box == null or dialogue_id.is_empty():
		return
	box.play(dialogue_id)
	await _await_dialogue(box)


func _play_dialogue_lines(lines: Variant) -> void:
	var box := _get_dialogue_box()
	if box == null or typeof(lines) != TYPE_ARRAY:
		return
	box.play_lines(lines as Array)
	await _await_dialogue(box)


## 對話可能同步結束（空台詞、找不到檔案），此時 dialogue_finished 已經送完了，
## 再 await 就會永遠等下去。必須先問 is_active() 才決定要不要等。
func _await_dialogue(box: DialogueBox) -> void:
	if not box.is_active():
		return
	await box.dialogue_finished


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	# create_timer 預設 process_always=true，對話暫停整棵樹時仍會走完。
	await get_tree().create_timer(seconds).timeout


func _get_dialogue_box() -> DialogueBox:
	var box := get_node_or_null(dialogue_box_path) as DialogueBox
	if box == null:
		push_warning("CutscenePlayer 找不到 DialogueBox: " + String(dialogue_box_path))
	return box
