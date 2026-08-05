## 序章「字界殘頁」的引路者NPC（Task 4.1a）。
##
## 玩家甦醒後第一個遇到的角色：觸發 `prologue_awakening`（令發現自己殘缺卩），
## 對話播完後接著送出 `prologue_guide_tutorial`（帶出移動/跳躍/開火/E/Q教學動線）。
## 只觸發一次——引路者只需要說一次開場白，重複進出範圍不應該打斷教學或再播一次。
class_name GuideNpc
extends Area2D

## 玩家進入觸發範圍時要播的第一段對話。
@export var dialogue_id: String = "prologue_awakening"
## 第一段播完後緊接著播的第二段（教程引導）。留空字串表示只播一段、不串接。
@export var follow_up_dialogue_id: String = "prologue_guide_tutorial"
## DialogueBox 的節點路徑，與 cutscene_player.gd 的既有慣例一致——用明確路徑，
## 不依賴 get_tree().current_scene（測試環境未必有設定 current_scene）。
@export var dialogue_box_path: NodePath = ^"../DialogueBox"

var _has_triggered: bool = false


func _get_dialogue_box() -> DialogueBox:
	return get_node_or_null(dialogue_box_path) as DialogueBox


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _has_triggered:
		return
	if not body.is_in_group(&"player"):
		return
	var dialogue_box := _get_dialogue_box()
	if dialogue_box == null:
		push_warning("GuideNpc: 找不到 DialogueBox，無法播放對話")
		return
	if dialogue_box.is_active():
		# 玩家理論上不該同時觸發兩段對話，但保守起見不要打斷正在播的內容。
		return

	_has_triggered = true

	if not follow_up_dialogue_id.is_empty():
		# 兩段對話要接續播放：先接 one-shot signal，等第一段播完再播第二段，
		# 避免兩段對話疊在一起搶 DialogueBox（DialogueBox.play 對重複呼叫只會警告並忽略）。
		dialogue_box.dialogue_finished.connect(_play_follow_up, CONNECT_ONE_SHOT)

	dialogue_box.play(dialogue_id)


func _play_follow_up() -> void:
	var dialogue_box := _get_dialogue_box()
	if dialogue_box == null:
		return
	dialogue_box.play(follow_up_dialogue_id)
