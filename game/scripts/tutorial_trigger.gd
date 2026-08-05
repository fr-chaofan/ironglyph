## 序章「字界殘頁」教程動線的單一教學點（Task 4.1a）。
##
## 依 `docs/LEVEL-DESIGN.md` 2.0 節排列 5 個：移動/跳躍/開火/E拾取/Q彈出，
## 各自對應 `docs/PROTAGONIST-令.md` 第1節「可是我會」的自我認知橋段——
## 令不掩飾殘缺，教程本身也不用花俏演出，只用最直接的文字提示。
##
## 行為：玩家進入範圍就顯示提示；偵測到對應按鍵操作後判定「已學會」，
## 提示淡出並永久停用（不會因為玩家走出又走進而重複顯示）。
class_name TutorialTrigger
extends Area2D

## 顯示給玩家的教學文字，例如「A / D 移動」。
@export var hint_text: String = ""
## 判定「已完成」所需偵測的任一按鍵（陣列中只要有一個被按下就算完成）。
## 移動教學同時看 move_left 與 move_right，其餘教學點通常只放一個 action。
@export var watch_actions: Array[StringName] = []
## 提示淡出的秒數。
@export_range(0.05, 2.0, 0.05) var fade_duration: float = 0.35

@onready var _hint: Label = get_node_or_null(^"Hint") as Label

var _player_in_range: bool = false
var _completed: bool = false


func _ready() -> void:
	if _hint != null:
		_hint.text = hint_text
		_hint.visible = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if _completed or not body.is_in_group(&"player"):
		return
	_player_in_range = true
	if _hint != null:
		_hint.visible = true


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_in_range = false
	if not _completed and _hint != null:
		_hint.visible = false


func _process(_delta: float) -> void:
	if _completed or not _player_in_range:
		return
	for action: StringName in watch_actions:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			_mark_completed()
			return


func _mark_completed() -> void:
	_completed = true
	monitoring = false
	if _hint == null:
		return
	var tween := create_tween()
	tween.tween_property(_hint, ^"modulate:a", 0.0, fade_duration)
	tween.tween_callback(func() -> void: _hint.visible = false)


## 供測試直接呼叫，不必真的模擬鍵盤輸入時序。
func force_complete() -> void:
	_mark_completed()


func is_completed() -> bool:
	return _completed
