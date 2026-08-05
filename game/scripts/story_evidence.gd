## 必經證物觸發器（Task 4.1a 新增；設計上供水域/火山/森林/礦山等後續關卡的
## 證物鏈共用，不必每關各自兜一份）。
##
## 與 GuideNpc 的差異：證物「必經但不強制停留」——玩家路過就自動播放，
## 不需要按鍵互動，也不像引路者那樣接續第二段對話。只播一次。
class_name StoryEvidence
extends Area2D

## 讀取的台詞檔 id（`data/dialogue/<id>.json`）。
@export var dialogue_id: String = ""
## DialogueBox 的節點路徑，慣例同 guide_npc.gd / cutscene_player.gd。
@export var dialogue_box_path: NodePath = ^"../DialogueBox"

var _has_triggered: bool = false


func _get_dialogue_box() -> DialogueBox:
	return get_node_or_null(dialogue_box_path) as DialogueBox


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _has_triggered or dialogue_id.is_empty():
		return
	if not body.is_in_group(&"player"):
		return
	var dialogue_box := _get_dialogue_box()
	if dialogue_box == null:
		push_warning("StoryEvidence: 找不到 DialogueBox，無法播放對話")
		return
	if dialogue_box.is_active():
		return

	_has_triggered = true
	dialogue_box.play(dialogue_id)


func has_triggered() -> bool:
	return _has_triggered
