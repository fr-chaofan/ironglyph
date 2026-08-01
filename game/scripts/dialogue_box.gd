## 對話／演出框架的核心 UI 元件（Task 4.0）。
##
## 序章教程NPC、Boss開場白、「賜俸」貪/爭/棄三選一、Phase 2.1「命」接住/放手、
## 終章「主」降臨訓誡全部共用這一個元件，不要各自兜一套 Label 顯示邏輯。
##
## 對外只有四個入口：
## - `play(dialogue_id)`：讀 `data/dialogue/<id>.json` 播一段純敘事對話。
## - `play_lines(lines)`：直接餵資料，不經檔案（測試與程式生成台詞用）。
## - `play_choice(dialogue_id, choices)`：播完台詞後給玩家選項，送出 `choice_made`。
## - `is_active()`：呼叫端（NPC/Boss）判斷是否已在對話中，避免重複觸發。
##
## ⚠️ 本節點必須 `PROCESS_MODE_ALWAYS`。對話期間整棵樹是暫停的（玩家不能動），
## 若本節點跟著暫停，打字機不會跑、推進鍵也收不到，遊戲會直接卡死在對話框。
class_name DialogueBox
extends CanvasLayer

## 整段對話播完（含選擇型對話送出 choice_made 之後）才送出。
signal dialogue_finished
## 每顯示一句送一次，供演出端（如仁的五連頭銜光效）逐句掛特效。
signal line_shown(index: int, line: Dictionary)
## 選擇型對話的結果；呼叫端（BossRen）自行處理增益/減益邏輯。
signal choice_made(choice_id: String)

const DIALOGUE_DIR := "res://data/dialogue"

## 台詞 JSON 所在目錄。測試可指向 fixture 目錄，不必把測試資料混進正式台詞。
@export_dir var dialogue_dir: String = DIALOGUE_DIR

## 打字機速度（字/秒）。設為 0 表示不做逐字顯示，整句直接出現。
@export var chars_per_second: float = 32.0

## 對話期間是否暫停整棵樹。正式流程一律 true；
## 元件測試需要在對話進行中 await 影格時可關掉。
@export var pauses_game: bool = true

## 推進／確認選項用的 action。沿用開火鍵，不新增按鍵。
@export var advance_action: StringName = &"fire"
## 選項左右移動用的 action，同樣沿用既有移動鍵。
@export var prev_choice_action: StringName = &"move_left"
@export var next_choice_action: StringName = &"move_right"

@onready var _panel: Control = get_node_or_null(^"Panel") as Control
@onready var _label: Label = get_node_or_null(^"Panel/Label") as Label
@onready var _speaker_label: Label = get_node_or_null(^"Panel/SpeakerLabel") as Label
@onready var _choice_container: BoxContainer = get_node_or_null(^"Panel/ChoiceContainer") as BoxContainer
@onready var _advance_prompt: Label = get_node_or_null(^"Panel/AdvancePrompt") as Label

var lines: Array = []
var current_index: int = -1
var choices: Array = []
var selected_choice: int = 0

var _playing: bool = false
var _typing: bool = false
var _revealed_chars: float = 0.0
var _was_paused: bool = false
var _pending_choices: Array = []


func _ready() -> void:
	# 暫停期間仍要能跑打字機與收推進鍵，見類別註解。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_clear_choice_buttons()


func _process(delta: float) -> void:
	if not _typing:
		return
	_advance_typing(delta)


## 讀取台詞檔並播放。找不到檔案不會卡住流程：送出 dialogue_finished 讓呼叫端往下走。
func play(dialogue_id: String) -> void:
	var data := _load_dialogue(dialogue_id)
	if data.is_empty():
		push_warning("dialogue not found: " + dialogue_id)
		dialogue_finished.emit()
		return
	play_lines(data.get("lines", []))


## 直接以資料播放，不經檔案。`lines` 每項為 {"speaker": String, "text": String}。
func play_lines(lines_data: Array) -> void:
	if _playing:
		push_warning("DialogueBox 已在播放中，忽略新的播放請求")
		return

	lines = lines_data.duplicate(true)
	_pending_choices = []
	if lines.is_empty():
		# 空台詞不該讓畫面閃一下暫停再解除，直接視為播完。
		dialogue_finished.emit()
		return

	_playing = true
	current_index = -1
	_set_choices([])
	visible = true
	_set_paused(true)
	_show_next_line()


## 選擇型對話：播完 `dialogue_id` 的台詞後呈現選項，玩家確認後送出 choice_made。
## `choices` 範例：
## [{"id":"greed","label":"貪（拾取）"}, {"id":"fight","label":"爭（格擋彈反）"}, {"id":"release","label":"棄（不碰）"}]
func play_choice(dialogue_id: String, choice_list: Array) -> void:
	if choice_list.is_empty():
		push_warning("play_choice 需要至少一個選項：" + dialogue_id)
		play(dialogue_id)
		return

	var data := _load_dialogue(dialogue_id)
	var dialogue_lines: Array = data.get("lines", []) if not data.is_empty() else []
	play_lines_with_choice(dialogue_lines, choice_list)


## play_choice 的無檔案版本，供程式生成的選項（如 Phase 2.1「命」）使用。
func play_lines_with_choice(lines_data: Array, choice_list: Array) -> void:
	if choice_list.is_empty():
		play_lines(lines_data)
		return

	if lines_data.is_empty():
		# 沒有前導台詞也要能單獨呈現選項，否則呼叫端得自己補一句廢話。
		play_lines([{"speaker": "", "text": ""}])
	else:
		play_lines(lines_data)

	if not _playing:
		return
	_pending_choices = choice_list.duplicate(true)
	# 只有一句台詞時 _show_next_line 已經跑完最後一句，選項要在這裡補上；
	# 打字機還在跑的話交給打字完成的那條路徑處理。
	_maybe_enter_choice_state()


## 推進一句。打字未完成時先補完整句，不吃掉這一次按鍵的推進意圖之外的東西。
func advance() -> void:
	if not _playing:
		return

	# 打字未完成時，這一次按鍵只負責補完整句——不推進、也不確認選項。
	if _typing:
		_complete_typing()
		_maybe_enter_choice_state()
		return

	if not choices.is_empty():
		_confirm_choice()
		return

	if _maybe_enter_choice_state():
		return

	_show_next_line()


## 移動選項游標。delta 為 -1 / +1，會在頭尾繞回。
func move_choice_cursor(delta: int) -> void:
	if choices.is_empty():
		return
	selected_choice = posmod(selected_choice + delta, choices.size())
	_refresh_choice_buttons()


func is_active() -> bool:
	return _playing


func get_current_line() -> Dictionary:
	if current_index < 0 or current_index >= lines.size():
		return {}
	var line: Variant = lines[current_index]
	return (line as Dictionary).duplicate(true) if typeof(line) == TYPE_DICTIONARY else {}


func get_selected_choice_id() -> String:
	if choices.is_empty():
		return ""
	return String((choices[selected_choice] as Dictionary).get("id", ""))


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return

	if not choices.is_empty():
		if event.is_action_pressed(prev_choice_action):
			move_choice_cursor(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(next_choice_action):
			move_choice_cursor(1)
			get_viewport().set_input_as_handled()
			return

	if not event.is_action_pressed(advance_action):
		return

	advance()
	# 對話期間的推進鍵不可以同時觸發開火——最後一句按下去會在解除暫停的
	# 同一幀打出一發子彈。
	get_viewport().set_input_as_handled()


func _show_next_line() -> void:
	current_index += 1
	if current_index >= lines.size():
		_finish()
		return

	var line := get_current_line()
	if _speaker_label != null:
		_speaker_label.text = String(line.get("speaker", ""))
	if _label != null:
		_label.text = String(line.get("text", ""))

	_start_typing()
	_update_advance_prompt()
	line_shown.emit(current_index, line)
	# 最後一句配上選項時，選項要跟著這句一起出現，不該再多按一次才看到。
	_maybe_enter_choice_state()


func _start_typing() -> void:
	_revealed_chars = 0.0
	if _label == null or chars_per_second <= 0.0:
		_typing = false
		if _label != null:
			_label.visible_characters = -1
		return

	_typing = true
	_label.visible_characters = 0


func _advance_typing(delta: float) -> void:
	if _label == null:
		_typing = false
		return

	_revealed_chars += chars_per_second * delta
	var total := _label.text.length()
	if _revealed_chars >= float(total):
		_complete_typing()
		# 打字自然跑完的那一幀也要能帶出選項，不能只靠玩家按鍵那條路徑。
		_maybe_enter_choice_state()
		return
	_label.visible_characters = int(_revealed_chars)


func _complete_typing() -> void:
	_typing = false
	_revealed_chars = 0.0
	if _label != null:
		_label.visible_characters = -1
	_update_advance_prompt()


func _is_last_line() -> bool:
	return current_index >= lines.size() - 1


## 條件成立才進選項狀態，回傳是否真的進了。
## 打字中不進——選項要等整句顯示完再出現，否則玩家會邊讀邊誤觸確認鍵。
func _maybe_enter_choice_state() -> bool:
	if _typing or _pending_choices.is_empty() or not _is_last_line():
		return false
	_enter_choice_state()
	return true


func _enter_choice_state() -> void:
	_set_choices(_pending_choices)
	_pending_choices = []
	_update_advance_prompt()


func _confirm_choice() -> void:
	var choice_id := get_selected_choice_id()
	_set_choices([])
	choice_made.emit(choice_id)
	_finish()


func _set_choices(choice_list: Array) -> void:
	choices = choice_list.duplicate(true)
	selected_choice = 0
	_refresh_choice_buttons()


func _refresh_choice_buttons() -> void:
	if _choice_container == null:
		return

	_clear_choice_buttons()
	_choice_container.visible = not choices.is_empty()
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var item := Label.new()
		item.text = ("▶ %s" if i == selected_choice else "　%s") % String(choice.get("label", ""))
		item.modulate = Color.WHITE if i == selected_choice else Color(0.62, 0.62, 0.68)
		_choice_container.add_child(item)


func _clear_choice_buttons() -> void:
	if _choice_container == null:
		return
	# 先 remove_child 再 queue_free：queue_free 要到影格結束才生效，
	# 同一幀重建選項時舊 Label 仍會留在 get_children() 裡造成重複顯示。
	for child: Node in _choice_container.get_children():
		_choice_container.remove_child(child)
		child.queue_free()


func _update_advance_prompt() -> void:
	if _advance_prompt == null:
		return
	if not choices.is_empty():
		_advance_prompt.text = "A/D 選擇　　J 確認"
	elif _is_last_line() and _pending_choices.is_empty():
		_advance_prompt.text = "J 結束"
	else:
		_advance_prompt.text = "J 繼續　▼"


func _finish() -> void:
	_typing = false
	_playing = false
	lines = []
	current_index = -1
	_pending_choices = []
	_set_choices([])
	visible = false
	_set_paused(false)
	dialogue_finished.emit()


## 暫停／恢復。恢復時還原成播放前的狀態，而不是無條件解除暫停——
## 從暫停選單觸發對話（階段六）時，對話結束不應該把暫停選單一起解除。
func _set_paused(paused: bool) -> void:
	if not pauses_game:
		return
	var tree := get_tree()
	if tree == null:
		return

	if paused:
		_was_paused = tree.paused
		tree.paused = true
		return
	tree.paused = _was_paused


func _load_dialogue(dialogue_id: String) -> Dictionary:
	var path := "%s/%s.json" % [dialogue_dir.rstrip("/"), dialogue_id]
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("dialogue 格式錯誤（應為 JSON 物件）: " + path)
		return {}

	var data: Dictionary = parsed
	if typeof(data.get("lines", [])) != TYPE_ARRAY:
		push_warning("dialogue 缺少 lines 陣列: " + path)
		return {}
	return data
