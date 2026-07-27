## Player 場景與朝向行為（Task 1.3 / 1.4 / 1.5）
##
## 重點是守住「漢字本體永遠不可水平鏡像翻轉」這條設計規則——
## 這是最容易在後續重構時被人用 scale.x = sign(dir) 一行破壞掉的約束。
extends GutTest

var PlayerScene := preload("res://scenes/player.tscn")

var _player: Node


func before_each() -> void:
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	await wait_physics_frames(2)


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump", &"fire", &"eject_component"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func test_場景節點齊全() -> void:
	assert_not_null(_player.get_node_or_null(^"HanziSprite"), "缺 HanziSprite")
	assert_not_null(_player.get_node_or_null(^"DirectionIndicator"), "缺 DirectionIndicator")
	assert_not_null(_player.get_node_or_null(^"CollisionShape2D"), "缺 CollisionShape2D")
	assert_not_null(_player.get_node_or_null(^"Camera2D"), "缺 Camera2D")


func test_開局顯示聲符字核令() -> void:
	var sprite: HanziSprite = _player.get_node(^"HanziSprite")
	assert_eq(sprite.text, "令")


func test_碰撞層為player且不與自己的子彈碰撞() -> void:
	# layer_2 = player = 位元值 2
	assert_eq(_player.collision_layer, 2, "Player 應在 layer_2 (player)")
	# mask 應含 ground(1) 與 enemy(4)，不含 player_bullet(8)
	assert_eq(_player.collision_mask & 1, 1, "應與 ground 碰撞")
	assert_eq(_player.collision_mask & 4, 4, "應與 enemy 碰撞")
	assert_eq(_player.collision_mask & 8, 0, "不應與自己的 player_bullet 碰撞")


func test_向左移動時只翻轉指示器不翻轉漢字() -> void:
	var sprite: HanziSprite = _player.get_node(^"HanziSprite")
	var indicator: Node2D = _player.get_node(^"DirectionIndicator")

	Input.action_press(&"move_left")
	await wait_physics_frames(3)
	Input.action_release(&"move_left")

	assert_lt(_player.facing_dir, 0.0, "按左鍵後 facing_dir 應為負")
	assert_lt(indicator.scale.x, 0.0, "朝向指示器應翻轉")
	assert_gt(sprite.scale.x, 0.0, "⚠️ 漢字本體不可鏡像翻轉——「令」鏡像後不是「令」")


func test_向右移動時指示器轉回正向() -> void:
	var sprite: HanziSprite = _player.get_node(^"HanziSprite")
	var indicator: Node2D = _player.get_node(^"DirectionIndicator")

	Input.action_press(&"move_left")
	await wait_physics_frames(3)
	Input.action_release(&"move_left")
	Input.action_press(&"move_right")
	await wait_physics_frames(3)
	Input.action_release(&"move_right")

	assert_gt(_player.facing_dir, 0.0)
	assert_gt(indicator.scale.x, 0.0, "指示器應轉回正向")
	assert_gt(sprite.scale.x, 0.0, "漢字本體始終不翻轉")


func test_指示器反覆翻轉不會累積縮放() -> void:
	# 用 scale.x *= -1 實作會在連續翻轉時把數值愈乘愈大/愈小，這裡確認沒有這個問題
	var indicator: Node2D = _player.get_node(^"DirectionIndicator")
	var original_magnitude := absf(indicator.scale.x)

	for i in range(4):
		Input.action_press(&"move_left")
		await wait_physics_frames(2)
		Input.action_release(&"move_left")
		Input.action_press(&"move_right")
		await wait_physics_frames(2)
		Input.action_release(&"move_right")

	assert_almost_eq(absf(indicator.scale.x), original_magnitude, 0.001,
		"反覆翻轉後縮放量值應維持不變")


func test_二段跳可用兩次() -> void:
	# 起始就在空中（before_each 剛實例化，還沒落地）
	assert_eq(_player.max_jumps, 2, "預設應為二段跳")

	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	var after_first: float = _player.velocity.y
	assert_lt(after_first, 0.0, "第一段跳應產生向上速度")

	await wait_physics_frames(6)
	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	assert_lt(_player.velocity.y, 0.0, "第二段跳應再次產生向上速度")


func test_第三次跳躍無效() -> void:
	for i in range(3):
		Input.action_press(&"jump")
		await wait_physics_frames(2)
		Input.action_release(&"jump")
		await wait_physics_frames(3)

	assert_eq(_player._jumps_used, 2, "空中最多只能用掉 max_jumps 次")


func test_空中跳直接覆寫下墜速度() -> void:
	# 下墜途中按二段跳應該立刻往上，而不是被既有下墜速度抵銷
	_player._jumps_used = 1
	_player.velocity.y = 600.0  # 正在快速下墜

	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")

	assert_lt(_player.velocity.y, 0.0, "下墜中按二段跳應立刻轉為向上")


func test_空中跳力道略弱於地面跳() -> void:
	assert_lt(_player.air_jump_multiplier, 1.0, "空中跳應略弱，讓兩段手感有區別")
	assert_gt(_player.air_jump_multiplier, 0.5, "但不該弱到失去意義")


func test_重力讓角色下墜() -> void:
	_player.velocity = Vector2.ZERO
	await wait_physics_frames(5)
	assert_gt(_player.velocity.y, 0.0, "空中應受重力加速下墜")


func test_WeaponManager已接上() -> void:
	# 階段一時此節點還不存在、`_try_fire()` 靜默略過；Task 2.3 接上後應能取到
	assert_not_null(_player.weapon_manager, "Task 2.3 後應有 WeaponManager")
	assert_true(_player.weapon_manager.has_method(&"fire"))


func test_按開火鍵不會崩潰() -> void:
	Input.action_press(&"fire")
	await wait_physics_frames(3)
	Input.action_release(&"fire")
	assert_true(is_instance_valid(_player), "開火不應造成崩潰")


func test_受擊時漢字閃紅() -> void:
	var sprite: HanziSprite = _player.get_node(^"HanziSprite")
	_player.take_damage(10, "fire")
	await wait_physics_frames(2)
	assert_ne(sprite.modulate, Color.WHITE, "受擊後應處於閃紅過程中")


func test_致死後進入terminal狀態且只發出一次died() -> void:
	var collision_shape := _player.get_node(^"CollisionShape2D") as CollisionShape2D
	var hanzi_sprite := _player.get_node(^"HanziSprite") as HanziSprite
	_player.velocity = Vector2(180.0, -240.0)
	watch_signals(_player)

	_player.take_damage(_player.max_hp, "neutral")

	assert_true(is_instance_valid(_player), "Player 本體應暫留給筆畫崩解與關卡 controller")
	assert_true(_player.is_dead, "致死後必須進入明確的 terminal dead state")
	assert_eq(_player.velocity, Vector2.ZERO, "死亡當下必須停止移動")
	assert_false(_player.is_physics_processing(), "死亡後不可再處理移動／跳躍／開火")
	assert_eq(
		_player.process_mode,
		Node.PROCESS_MODE_DISABLED,
		"死亡 signal 與 shatter 啟動後必須停用整個 Player subtree"
	)
	assert_false(_player.is_in_group(&"player"), "敵人 AI 不可繼續鎖定死亡 Player")
	assert_false(
		_player.direction_indicator.visible,
		"死亡當幀必須隱藏方向指示器，不可留下會被誤認為角色的空殼"
	)
	assert_signal_emit_count(_player, "died", 1, "首次致死必須恰好發出一次 died")
	assert_true(hanzi_sprite.is_queued_for_deletion(), "terminal state 仍必須啟動筆畫崩解死亡特效")

	# die() 可能在物理 query flush 期間被呼叫，碰撞停用刻意 deferred。
	await wait_process_frames(2)
	assert_true(is_instance_valid(_player), "收尾期間 Player 本體仍應有效")
	assert_true(collision_shape.disabled, "死亡 Player 的 CollisionShape 必須停用")
	assert_eq(_player.collision_layer, 0, "死亡 Player 不可再被其他碰撞 mask 命中")
	assert_eq(_player.collision_mask, 0, "死亡 Player 不可再主動碰撞地形或敵人")

	_player.die()
	_player.take_damage(9999, "fire")
	assert_signal_emit_count(_player, "died", 1, "重複死亡呼叫不可再次發出 died")


func test_死亡後無論直接呼叫或按住fire都不能生成子彈() -> void:
	var before := _count_bullets()
	_player.take_damage(_player.max_hp, "neutral")

	# 直接呼叫守住未來 controller／debug code；按鍵路徑守住 physics 已停用。
	_player.weapon_manager.cooldown = 0.0
	_player._try_fire()
	Input.action_press(&"fire")
	await wait_physics_frames(2)
	Input.action_release(&"fire")

	assert_eq(_count_bullets(), before, "terminal dead state 不可再生成任何子彈")


func test_死亡後GlyphLoadout不再接收Q彈出部件() -> void:
	var loadout := _player.get_node(^"GlyphLoadout")
	loadout.equip_component_id("water")
	watch_signals(loadout)

	_player.take_damage(_player.max_hp, "neutral")
	Input.action_press(&"eject_component")
	await wait_process_frames(2)
	Input.action_release(&"eject_component")

	assert_false(loadout.can_process(), "死亡後 GlyphLoadout 不可繼續處理 gameplay input")
	assert_signal_emit_count(loadout, "component_ejected", 0, "死亡後按 Q 不可彈出部件")
	assert_eq(
		(loadout.get_snapshot().get("component", {}) as Dictionary).get("id", ""),
		"water",
		"死亡收尾期間裝備狀態應保持不變"
	)


func test_camera有平滑跟隨() -> void:
	var cam: CameraBounds = _player.get_node(^"Camera2D")
	assert_true(cam.position_smoothing_enabled, "鏡頭應啟用平滑跟隨")
	assert_false(cam.has_bounds, "未設定關卡邊界前 has_bounds 應為 false")


func test_set_level_bounds套用限制() -> void:
	var cam: CameraBounds = _player.get_node(^"Camera2D")
	cam.set_level_bounds(Rect2(-500, -300, 1000, 600))
	assert_eq(cam.limit_left, -500)
	assert_eq(cam.limit_top, -300)
	assert_eq(cam.limit_right, 500)
	assert_eq(cam.limit_bottom, 300)
	assert_true(cam.has_bounds)


func _count_bullets() -> int:
	return _count_bullets_below(get_tree().root)


func _count_bullets_below(node: Node) -> int:
	var count := 1 if node is Bullet else 0
	for child: Node in node.get_children():
		count += _count_bullets_below(child)
	return count
