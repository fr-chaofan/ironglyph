## 血量顯示
##
## 在此之前畫面上完全看不到自己的血——HUD 有武器與環境資訊，唯獨沒有血量。
## 玩家只能靠受擊閃紅猜還剩多少，實機測試時根本無從判斷該不該撤退。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const TestRoomScene := preload("res://scenes/test_room.tscn")
const HpBarScript := preload("res://scripts/hp_bar.gd")

var _player: Node2D
var _bar: HpBar


func before_each() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "Player"
	add_child_autofree(_player)

	_bar = HpBarScript.new() as HpBar
	_bar.target_path = ^"../Player"
	_player.get_parent().add_child(_bar)
	await wait_physics_frames(1)


func _label_text() -> String:
	for child: Node in _bar.get_children():
		if child is Label:
			return (child as Label).text
	return ""


func test_顯示目前與上限血量() -> void:
	assert_true(_label_text().contains(str(_player.max_hp)), "應顯示血量上限")
	assert_true(_label_text().contains("血"), "應該看得出這是血量")


func test_受傷後跟著更新() -> void:
	var before := _label_text()
	_player.take_damage(30, "neutral")
	await wait_physics_frames(1)

	assert_ne(_label_text(), before, "受傷後顯示要跟著變")
	assert_true(_label_text().contains(str(_player.hp)))


func test_低血量進入危險狀態() -> void:
	# 玩家要看得出「快死了」，不是等血條見底才發現
	_player.hp = int(_player.max_hp * 0.2)
	_player.hp_changed.emit(_player.hp, _player.max_hp)
	await wait_physics_frames(1)

	assert_lt(_bar._ratio, HpBarScript.DANGER_RATIO)
	assert_not_null(_bar._danger_tween, "危險時應該脈動")


func test_血量回滿會解除危險脈動() -> void:
	# ⚠️ 每次血量變動都重建 tween 的話會越疊越快；這裡驗證舊的有被 kill
	_player.hp = 10
	_player.hp_changed.emit(_player.hp, _player.max_hp)
	await wait_physics_frames(1)
	var danger := _bar._danger_tween

	_player.hp = _player.max_hp
	_player.hp_changed.emit(_player.hp, _player.max_hp)
	await wait_physics_frames(1)

	assert_false(danger.is_valid(), "回滿血後舊的脈動 tween 必須被 kill")
	assert_almost_eq(_bar.modulate.a, 1.0, 0.01)


func test_找不到角色時不會崩潰() -> void:
	var orphan := HpBarScript.new() as HpBar
	orphan.target_path = ^"../NoSuchNode"
	add_child_autofree(orphan)
	await wait_physics_frames(1)
	pass_test("缺目標時安全降級")


# ---- 練習場的血量覆寫 ----

func test_練習場玩家有500血() -> void:
	var room: Node2D = TestRoomScene.instantiate()
	add_child_autofree(room)
	await wait_physics_frames(2)

	var player := room.get_node(^"Player") as Character
	assert_eq(player.max_hp, 500, "練習場刻意把血量拉高，方便長時間測試")
	assert_eq(player.hp, 500, "開場應該是滿血")


func test_正式玩家場景維持預設血量() -> void:
	# ⚠️ 練習場的 500 是**場景實例覆寫**，不可以汙染 player.tscn 的預設值——
	# 那是正式遊戲的平衡數值，屬於 Task 8.1 的範圍。
	var player: Node2D = PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)

	assert_eq(player.max_hp, 100, "player.tscn 的預設血量不可以被練習場帶歪")
