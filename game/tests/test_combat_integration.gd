## 端到端戰鬥流程（開火 → 子彈飛行 → 命中 → 五行結算 → 扣血）
##
## 前面的測試都是單元層級：WeaponManager 會生成子彈、Bullet 命中會呼叫 take_damage、
## ElementSystem 會算倍率。但**整條鏈實際串起來會不會通**是另一回事——
## 碰撞層對不上、子彈生成點在目標背後、mask 少勾一位，任何一個都會讓單元測試全過
## 但實際打不到人。這支測試用真的物理碰撞把整條鏈跑一遍。
extends GutTest

var TestRoomScene := preload("res://scenes/test_room.tscn")

var _room: Node
var _player: Node
var _wm: WeaponManager
var _loadout: Node


func before_each() -> void:
	_room = TestRoomScene.instantiate()
	add_child_autofree(_room)
	await wait_physics_frames(3)
	_player = _room.get_node(^"Player")
	_wm = _player.get_node(^"WeaponManager")
	_loadout = _player.get_node(^"GlyphLoadout")


func after_each() -> void:
	for action: StringName in [&"fire", &"move_left", &"move_right", &"interact", &"eject_component"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func test_測試場景載入完整() -> void:
	assert_not_null(_player, "缺 Player")
	assert_not_null(_room.get_node_or_null(^"Dummies/DummyFire"), "缺火屬假人")
	assert_not_null(_room.get_node_or_null(^"Dummies/DummyWood"), "缺木屬假人")
	assert_not_null(_room.get_node_or_null(^"Dummies/DummyWater"), "缺水屬假人")


func test_假人碰撞層讓子彈打得到() -> void:
	var dummy: Character = _room.get_node(^"Dummies/DummyFire")
	# 假人在 enemy 層(4)，子彈 mask 含 enemy
	assert_eq(dummy.collision_layer, 4, "假人應在 enemy 層")
	var bullet: Bullet = preload("res://scenes/projectiles/bullet_base.tscn").instantiate()
	add_child_autofree(bullet)
	assert_ne(bullet.collision_mask & dummy.collision_layer, 0,
		"子彈的 mask 必須涵蓋假人所在的層，否則永遠偵測不到")


func test_火球打火屬假人走中性倍率() -> void:
	var dummy: Character = _room.get_node(^"Dummies/DummyFire")
	var before: int = dummy.hp

	# 火與「令」拼不出字（資料集查無「炩」），因此進入 HELD 並使用既有火球。
	# ⚠️ 別拿「氵」當 HELD 範例——它會融合成「泠」。
	_loadout.equip_component_id("fire")
	assert_eq(_wm.get_current_weapon()["id"], "huo")

	# 把玩家挪到假人左邊一點，朝右開火
	_player.global_position = dummy.global_position + Vector2(-90, 0)
	await wait_physics_frames(2)
	_wm.fire(1.0)

	# 等子彈飛完這段距離（speed 500，約 90px → 0.18s）
	await wait_seconds(0.5)

	var dealt: int = before - dummy.hp
	assert_eq(dealt, 12, "同屬性走中性倍率：傷害12 × 1.0。實際扣了 %d" % dealt)


func test_火球打水屬假人走劣勢倍率() -> void:
	# 水剋火，所以火球打水屬是劣勢
	var dummy: Character = _room.get_node(^"Dummies/DummyWater")
	var before: int = dummy.hp

	_loadout.equip_component_id("fire")
	_player.global_position = dummy.global_position + Vector2(-90, 0)
	await wait_physics_frames(2)
	_wm.fire(1.0)
	await wait_seconds(0.5)

	assert_eq(before - dummy.hp, 7, "劣勢倍率：傷害12 × 0.6 = 7.2，取整為 7")


func test_子彈從角色前方生成不會立刻打到自己() -> void:
	var before: int = _player.hp
	_wm.fire(1.0)
	await wait_seconds(0.3)
	assert_eq(_player.hp, before, "玩家不該被自己的子彈打到")


func test_零的環形彈幕不會打到玩家自己() -> void:
	_loadout.equip_component_id("rain")
	assert_eq(_player.get_node(^"HanziSprite").text, "零")
	assert_eq(_wm.get_current_weapon().get("id", ""), "reset_burst")

	var before: int = _player.hp
	_wm.fire(1.0)
	await wait_seconds(0.3)
	assert_eq(_player.hp, before, "玩家不該被自身中心生成的歸零彈幕打到")


func test_假人死亡後會重生() -> void:
	var dummy = _room.get_node(^"Dummies/DummyWood")
	dummy.respawn_delay = 0.1
	dummy.take_damage(9999, "metal")
	assert_eq(dummy.hp, 0, "應被打倒")

	await wait_seconds(0.4)
	assert_eq(dummy.hp, dummy.max_hp, "假人應原地重生，方便反覆測試")
	assert_true(is_instance_valid(dummy), "假人不應被 queue_free")
