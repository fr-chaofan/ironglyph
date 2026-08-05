## 序章「字界殘頁」關卡骨架驗證（Task 4.1a）。
##
## 這裡不驗證完整關卡體驗（教程手感留給人工試玩），只驗證：
## 1. 場景載入不炸、必要節點齊全
## 2. GuideNPC → 兩段對話接續播放
## 3. TutorialTrigger 偵測到對應按鍵後標記完成、提示淡出
## 4. FirstComponentDrop 一開始就帶著 rain 部件可直接被拾取
## 5. StoryEvidence 只播一次
## 6. LevelExit 呼叫 LevelManager.next_level()
extends GutTest

const PrologueScene := preload("res://scenes/levels/level_00_prologue.tscn")
const FIXTURE_DIALOGUE_DIR := "res://data/dialogue"

var _room: Node2D
var _player: Node2D
var _dialogue_box: DialogueBox


func before_each() -> void:
	_release_inputs()
	_room = PrologueScene.instantiate()
	add_child_autofree(_room)
	await wait_physics_frames(2)

	_player = _room.get_node(^"Player") as Node2D
	_dialogue_box = _room.get_node(^"DialogueBox") as DialogueBox
	_dialogue_box.pauses_game = false
	_dialogue_box.chars_per_second = 0.0


func after_each() -> void:
	get_tree().paused = false
	_release_inputs()


func test_場景必要節點齊全() -> void:
	assert_not_null(_room.get_node_or_null(^"PlayerSpawn"))
	assert_not_null(_room.get_node_or_null(^"Player"))
	assert_not_null(_room.get_node_or_null(^"GuideNPC"))
	assert_not_null(_room.get_node_or_null(^"TutorialTriggers"))
	assert_not_null(_room.get_node_or_null(^"FirstComponentDrop"))
	assert_not_null(_room.get_node_or_null(^"OldWorkshopEvidence"))
	assert_not_null(_room.get_node_or_null(^"LevelExit"))
	assert_not_null(_room.get_node_or_null(^"DialogueBox"))


func test_TutorialTriggers底下有五個對應教學動線的節點() -> void:
	var triggers := _room.get_node(^"TutorialTriggers")
	assert_eq(triggers.get_child_count(), 4, "移動+跳躍合併成一個觸發區，加上開火/E/Q共4個節點")


# ---- GuideNPC ----

func test_進入GuideNPC範圍播放甦醒對話並接續教程對話() -> void:
	watch_signals(_dialogue_box)
	var guide := _room.get_node(^"GuideNPC")

	guide.call(&"_on_body_entered", _player)
	assert_true(_dialogue_box.is_active())
	assert_eq(_dialogue_box.get_current_line().get("speaker", ""), "")

	# prologue_awakening 共8句：play() 已顯示第0句，還需8次推進才會播完並觸發
	# dialogue_finished → one-shot 接上的 _play_follow_up 會在同一次呼叫內接著播第二段。
	for i in 8:
		_dialogue_box.advance()
	assert_true(_dialogue_box.is_active(), "第一段播完應緊接播第二段，不應整段結束")
	assert_eq(_dialogue_box.get_current_line().get("speaker", ""), "引路者", "第二段開頭應已經在播")

	# prologue_guide_tutorial 共5句，同樣需要5次推進才會播完。
	for i in 5:
		_dialogue_box.advance()
	assert_false(_dialogue_box.is_active(), "兩段都播完後才算整段結束")


func test_GuideNPC只觸發一次() -> void:
	var guide := _room.get_node(^"GuideNPC")
	guide.call(&"_on_body_entered", _player)
	assert_true(_dialogue_box.is_active())

	# 播完全部對話：8句(awakening) + 5句(guide_tutorial) = 13次推進
	for i in 13:
		_dialogue_box.advance()
	assert_false(_dialogue_box.is_active())

	guide.call(&"_on_body_entered", _player)
	assert_false(_dialogue_box.is_active(), "已觸發過的引路者不應再次播放對話")


# ---- TutorialTrigger ----

func test_移動跳躍教學按下對應鍵後標記完成() -> void:
	var trigger := _room.get_node(^"TutorialTriggers/MoveJumpTutorial")
	trigger.call(&"_on_body_entered", _player)
	assert_false(trigger.call(&"is_completed"))

	Input.action_press(&"jump")
	await wait_process_frames(1)
	Input.action_release(&"jump")

	assert_true(trigger.call(&"is_completed"), "按下 jump 後應標記完成")


func test_教學提示只在玩家進入範圍後顯示() -> void:
	var trigger := _room.get_node(^"TutorialTriggers/FireTutorial")
	var hint := trigger.get_node(^"Hint") as Label
	assert_false(hint.visible)

	trigger.call(&"_on_body_entered", _player)
	assert_true(hint.visible)

	trigger.call(&"_on_body_exited", _player)
	assert_false(hint.visible, "未完成时離開範圍應隱藏提示")


func test_force_complete可直接標記完成供測試使用() -> void:
	var trigger := _room.get_node(^"TutorialTriggers/PickupTutorial")
	trigger.call(&"force_complete")
	assert_true(trigger.call(&"is_completed"))


# ---- FirstComponentDrop ----

func test_FirstComponentDrop一開始就帶著rain部件() -> void:
	var pickup := _room.get_node(^"FirstComponentDrop")
	var component: Dictionary = pickup.get("component")
	assert_eq(component.get("id", ""), "rain", "序章的固定部件應該是 rain，呼應水域關的第一個配方")


func test_FirstComponentDrop設了lifetime為0永不消失() -> void:
	var pickup := _room.get_node(^"FirstComponentDrop")
	assert_eq(pickup.lifetime, 0.0, "教學用部件不該無預警消失，否則玩家可能錯過E/Q練習")


# ---- OldWorkshopEvidence ----

func test_進入OldWorkshopEvidence範圍播放證物對話() -> void:
	var evidence := _room.get_node(^"OldWorkshopEvidence")
	evidence.call(&"_on_body_entered", _player)
	assert_true(_dialogue_box.is_active())
	assert_true(evidence.call(&"has_triggered"))


func test_OldWorkshopEvidence只播一次() -> void:
	var evidence := _room.get_node(^"OldWorkshopEvidence")
	evidence.call(&"_on_body_entered", _player)
	for i in 6:
		_dialogue_box.advance()
	assert_false(_dialogue_box.is_active())

	evidence.call(&"_on_body_entered", _player)
	assert_false(_dialogue_box.is_active(), "已播過的證物不該再次觸發")


# ---- LevelExit ----

func test_進入LevelExit呼叫LevelManager的next_level() -> void:
	var level_manager := get_node_or_null(^"/root/LevelManager")
	assert_not_null(level_manager, "本測試依賴 LevelManager autoload 已註冊")
	if level_manager == null:
		return

	var before_index: int = level_manager.current_level_index
	var exit_node := _room.get_node(^"LevelExit")
	exit_node.call(&"_on_body_entered", _player)

	assert_eq(
		level_manager.current_level_index, before_index + 1,
		"進入 LevelExit 應該讓 LevelManager 前進到下一關索引"
	)
	# 水域關場景檔尚未建立（Task 4.1），LevelManager 內部會 push_error 但不崩潰。
	assert_push_error("場景檔案不存在")

	# 測試後把索引還原，避免影響其他共用同一 LevelManager autoload 的測試。
	level_manager.current_level_index = before_index


func _release_inputs() -> void:
	for action: StringName in [
		&"move_left",
		&"move_right",
		&"jump",
		&"fire",
		&"interact",
		&"eject_component",
	]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
