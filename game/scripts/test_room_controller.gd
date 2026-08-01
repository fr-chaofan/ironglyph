## 手動驗證場景的生命週期控制。
##
## TestRoom 不是正式關卡，也沒有 Phase 4 的 checkpoint / LevelManager。
## 玩家死亡後等待筆畫崩解完成，再完整重載場景，避免留下仍可操作的空殼，
## 同時確保 ComponentDropper、HUD 等只綁定初始 Player 的測試用節點取得新引用。
extends Node2D

@export_range(0.0, 5.0, 0.05) var death_reload_delay: float = 0.8
@export var player_path: NodePath = ^"Player"
@export var dialogue_box_path: NodePath = ^"DialogueBox"
@export var cutscene_player_path: NodePath = ^"CutscenePlayer"
@export var hint_label_path: NodePath = ^"HUD/Hint"
## 選擇結果在 HUD 停留幾秒後還原提示文字。
@export_range(0.5, 10.0, 0.5) var choice_readout_duration: float = 3.0

## Task 4.0 的手動驗證用台詞；正式觸發點在序章NPC（Task 4.1a）與Boss戰（Task 5.4）。
const DEMO_DIALOGUE_ID := "boss_ren_intro"
const DEMO_CHOICES := [
	{"id": "greed", "label": "貪（拾取）"},
	{"id": "fight", "label": "爭（格擋彈反）"},
	{"id": "release", "label": "棄（不碰）"},
]

var _reload_pending: bool = false
var _hint_label: Label
var _hint_default_text: String = ""


func _ready() -> void:
	_connect_dialogue_readout()

	var player := get_node_or_null(player_path)
	if player == null or not player.has_signal(&"died"):
		push_warning("TestRoomController: 找不到可監聽死亡事件的 Player")
		return

	var callback := Callable(self, "_on_player_died")
	if not player.is_connected(&"died", callback):
		player.connect(&"died", callback)


## 選擇型對話的結果印回 HUD。「賜俸」三選一實際上要影響戰鬥數值（Task 5.4），
## 在那之前先讓選擇結果在畫面上看得見，才有辦法用眼睛驗證資料流是通的。
func _connect_dialogue_readout() -> void:
	var box := get_node_or_null(dialogue_box_path) as DialogueBox
	_hint_label = get_node_or_null(hint_label_path) as Label
	if box == null or _hint_label == null:
		return

	_hint_default_text = _hint_label.text
	var callback := Callable(self, "_on_choice_made")
	if not box.is_connected(&"choice_made", callback):
		box.connect(&"choice_made", callback)


func _on_choice_made(choice_id: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = "選擇結果：%s" % choice_id

	await get_tree().create_timer(choice_readout_duration).timeout
	if _hint_label != null and is_instance_valid(_hint_label):
		_hint_label.text = _hint_default_text


## Task 4.0 的手動驗證入口。
##
## 這裡刻意用原始 keycode 而不是 Input Action：T/Y/U 只是測試場景的除錯捷徑，
## 不是正式玩法按鍵，不值得為它們往 `project.godot` 的 `[input]` 增加三個 action
## （多人協作時那一小節最容易互相覆蓋，見 COLLABORATION.md 第6節）。
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	var box := get_node_or_null(dialogue_box_path) as DialogueBox
	if box == null or box.is_active():
		return

	match key_event.keycode:
		KEY_T:
			box.play(DEMO_DIALOGUE_ID)
		KEY_Y:
			box.play_choice(DEMO_DIALOGUE_ID, DEMO_CHOICES)
		KEY_U:
			var cutscene := get_node_or_null(cutscene_player_path) as CutscenePlayer
			if cutscene != null and not cutscene.is_playing():
				cutscene.play_ending_zhu_descent()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_player_died() -> void:
	if _reload_pending:
		return
	_reload_pending = true

	await get_tree().create_timer(death_reload_delay).timeout
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()
