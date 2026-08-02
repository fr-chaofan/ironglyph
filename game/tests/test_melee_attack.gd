## 近戰揮擊元件測試（Task 2.7b）
##
## 判定用 `intersect_shape` 的即時形狀查詢，因此**當幀就有結果**——
## 測試不必猜要 await 幾幀，也不必為了等 Area2D 的 monitoring 更新而加保險等待。
## 唯一需要 await 的是讓物理空間先建立起來（before_each 的兩幀）。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")

## COMBAT.md 3.4 節定案的安全揮擊窗口：接觸傷害在 52px，近戰有效命中 52～120px
const SAFE_WINDOW_HIT := 110.0
const SAFE_WINDOW_MISS := 130.0

var _player: Node2D
var _melee: MeleeAttack


func before_each() -> void:
	_release_inputs()
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	_player.global_position = Vector2.ZERO
	_melee = _player.get_node(^"MeleeAttack") as MeleeAttack
	_melee.show_arc = false  # 測試不需要 tween 與額外節點
	# ⚠️ 停掉玩家的物理處理，位置才是確定的。開著的話玩家會因為重力持續下墜，
	# 而距離邊界測試（110px 命中／130px 落空）差幾個像素就會翻盤。
	_player.set_physics_process(false)
	await wait_physics_frames(2)


func after_each() -> void:
	_release_inputs()


# ---- profile 資料 ----

func test_令筆擊profile存在且數值符合設計() -> void:
	var profile := MeleeAttack.get_profile("ling_slash")
	assert_false(profile.is_empty(), "找不到 ling_slash")
	assert_eq(int(profile.get("damage", 0)), 16)
	assert_eq(profile.get("element", ""), "neutral", "令筆擊預設無屬性")
	assert_eq(profile.get("glyph", ""), "令")
	assert_almost_eq(float(profile.get("windup", 0.0)), 0.10, 0.001, "沒有前搖的近戰＝無腦連打")


func test_未知profile不會揮出去() -> void:
	_melee.profile_id = "no_such_profile"
	assert_false(_melee.swing(1.0), "找不到 profile 應該安全失敗")
	assert_engine_error("找不到近戰 profile")
	assert_true(_melee.can_swing())


# ---- 三段式生命週期 ----

func test_揮擊經過前搖判定冷卻三段() -> void:
	assert_true(_melee.swing(1.0))
	assert_eq(_melee.state, MeleeAttack.State.WINDUP, "揮出當下應在前搖")

	_melee._physics_process(0.05)
	assert_eq(_melee.state, MeleeAttack.State.WINDUP, "0.05s 還沒走完 0.10s 前搖")

	_melee._physics_process(0.06)
	assert_eq(_melee.state, MeleeAttack.State.ACTIVE)

	_melee._physics_process(0.13)
	assert_eq(_melee.state, MeleeAttack.State.COOLDOWN)

	_melee._physics_process(0.5)
	assert_eq(_melee.state, MeleeAttack.State.IDLE)


func test_冷卻中不能再揮() -> void:
	assert_true(_melee.swing(1.0))
	assert_false(_melee.swing(1.0), "同一次揮擊還沒結束不該接受新的揮擊")


func test_cancel立刻回到idle() -> void:
	_melee.swing(1.0)
	_melee.cancel()
	assert_eq(_melee.state, MeleeAttack.State.IDLE)
	assert_true(_melee.can_swing())


func test_總冷卻含前搖與判定() -> void:
	# cooldown 是「從揮出到能再揮」的總時長 0.45s，不是判定結束後再等 0.45s
	_melee.swing(1.0)
	var elapsed := 0.0
	for i in 60:
		_melee._physics_process(0.01)
		elapsed += 0.01
		if _melee.can_swing():
			break
	# 狀態轉換發生在影格邊界上，三次轉換各會多吃一幀，因此略長於 0.45s
	assert_between(elapsed, 0.45, 0.49, "整套揮擊應在 0.45s 左右結束")


# ---- 命中判定 ----

func test_前搖期間不判定() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0))
	var before: int = enemy.hp

	_melee.swing(1.0)
	_melee._physics_process(0.05)  # 仍在前搖

	assert_eq(enemy.hp, before, "前搖期間不該造成傷害，否則玩家的預兆等於沒有")


func test_判定期間命中前方敵人() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0))
	var before: int = enemy.hp

	_swing_through(1.0)

	assert_lt(enemy.hp, before, "正前方 80px 的敵人應該被打到")


func test_背後的敵人打不到() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(-80, 0))
	var before: int = enemy.hp

	_swing_through(1.0)  # 朝右揮

	assert_eq(enemy.hp, before, "判定框只在面向側")


func test_安全窗口內緣110px必須命中() -> void:
	# COMBAT.md 3.4：接觸傷害在 52px、最遠命中 120px。把窗口寫死進測試，
	# 否則日後調手感會悄悄破壞「站在窗口外緣揮擊不吃接觸傷害」的設計意圖。
	var enemy: Enemy = await _spawn_enemy(Vector2(SAFE_WINDOW_HIT, 0))
	var before: int = enemy.hp
	_swing_through(1.0)
	assert_lt(enemy.hp, before, "中心距 %dpx 必須命中" % SAFE_WINDOW_HIT)


func test_超過安全窗口130px必須落空() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(SAFE_WINDOW_MISS, 0))
	var before: int = enemy.hp
	_swing_through(1.0)
	assert_eq(enemy.hp, before, "中心距 %dpx 必須落空" % SAFE_WINDOW_MISS)


func test_同一次揮擊只結算一次() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0))
	enemy.max_hp = 999
	enemy.hp = 999

	watch_signals(_melee)
	_swing_through(1.0)

	assert_signal_emit_count(
		_melee, "hit_landed", 1,
		"判定窗橫跨多個物理影格，不去重的話貼身揮一次會打出七、八下"
	)
	assert_eq(enemy.hp, 999 - 16, "只該扣一次令筆擊的 16 傷")


func test_一次揮擊可以同時打到多個敵人() -> void:
	var a: Enemy = await _spawn_enemy(Vector2(70, 0))
	var b: Enemy = await _spawn_enemy(Vector2(100, 0))
	a.max_hp = 999
	a.hp = 999
	b.max_hp = 999
	b.hp = 999

	_swing_through(1.0)

	assert_lt(a.hp, 999)
	assert_lt(b.hp, 999)


func test_傷害走基類因此吃五行相剋() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0))
	enemy.element = "wood"
	enemy.max_hp = 999
	enemy.hp = 999

	_melee.swing(1.0, {
		"id": "test_metal", "name": "測試", "element": "metal",
		"damage": 10, "cooldown": 0.4, "windup": 0.0, "active": 0.1,
		"reach": 58, "hitbox": [72, 56],
	})
	_melee._physics_process(0.01)

	# 金剋木 ×1.5：自己算傷害的話這裡會是 10
	assert_eq(enemy.hp, 999 - 15, "近戰必須走 Character.take_damage() 才吃得到相剋倍率")


# ---- 消彈 ----

func test_揮擊可以打掉敵方子彈() -> void:
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))

	watch_signals(_melee)
	_swing_through(1.0)

	assert_signal_emit_count(_melee, "bullet_blocked", 1)
	assert_true(bullet.is_queued_for_deletion(), "敵方子彈應被揮掉")


func test_不會揮掉自己的子彈() -> void:
	# player_bullet 層若被列進 block_mask，玩家會揮掉自己剛打出去的子彈
	var bullet: Bullet = BulletScene.instantiate()
	bullet.speed = 0.0
	bullet.position = Vector2(80, 0)
	add_child_autofree(bullet)
	bullet.setup(5, "neutral", Vector2(80, 0), Vector2.RIGHT)
	await wait_physics_frames(1)

	_swing_through(1.0)

	assert_false(bullet.is_queued_for_deletion(), "玩家的子彈在 player_bullet 層，不可被自己揮掉")


# ---- 下劈 ----

func test_下劈判定在腳下而不是前方() -> void:
	var below: Enemy = await _spawn_enemy(Vector2(0, 80))
	var front: Enemy = await _spawn_enemy(Vector2(80, 0))
	var below_before: int = below.hp
	var front_before: int = front.hp

	_swing_through(1.0, true)

	assert_lt(below.hp, below_before, "下劈應打到腳下的敵人")
	assert_eq(front.hp, front_before, "下劈不該打到正前方")


func test_下劈命中送出彈起且只送一次() -> void:
	await _spawn_enemy(Vector2(-20, 80))
	await _spawn_enemy(Vector2(20, 80))

	watch_signals(_melee)
	_swing_through(1.0, true)

	assert_signal_emit_count(
		_melee, "pogo_bounced", 1,
		"一刀掃到兩隻敵人不該疊加成兩倍彈速"
	)


func test_下劈落空不彈起() -> void:
	watch_signals(_melee)
	_swing_through(1.0, true)
	assert_signal_not_emitted(_melee, "pogo_bounced", "沒踩到東西就該正常落下")


func test_下劈踩敵方子彈也能彈起() -> void:
	await _spawn_enemy_bullet(Vector2(0, 80))

	watch_signals(_melee)
	_swing_through(1.0, true)

	assert_signal_emit_count(_melee, "pogo_bounced", 1)


func test_下劈傷害打八折() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(0, 80))
	enemy.max_hp = 999
	enemy.hp = 999

	_swing_through(1.0, true)

	assert_eq(enemy.hp, 999 - 13, "16 × 0.8 = 12.8，四捨五入為 13")


func test_下劈彈起速度小於一般跳躍() -> void:
	# 彈起若比跳躍還高，所有平台段都會變成下劈
	var pogo := MeleeAttack.get_pogo_settings()
	var bounce := absf(float(pogo.get("bounce", 0.0)))
	var jump := absf(float(_player.jump_velocity))

	assert_lt(bounce, jump, "下劈彈起 %.0f 必須小於跳躍 %.0f" % [bounce, jump])


# ---- 揮擊視覺 ----

func test_揮擊弧線出現在身前() -> void:
	# ⚠️ 玩家刻意不放在原點：位置翻倍的 bug 在 (0,0) 附近幾乎看不出來，
	# 離原點越遠偏得越多。2.7b 就是這樣讓弧線跑到腳下 120px。
	_player.global_position = Vector2(400, -200)
	_melee.show_arc = true
	await wait_physics_frames(1)

	_swing_through(1.0)

	var arc := _find_arc()
	assert_not_null(arc, "判定開始時應生成揮擊弧線")
	assert_gt(arc.points.size(), 1, "弧線要有筆畫點")
	var expected: Vector2 = _player.global_position + Vector2(58.0, 0.0)
	assert_almost_eq(arc.global_position.x, expected.x, 1.0, "弧線應在身前 58px")
	assert_almost_eq(arc.global_position.y, expected.y, 1.0, "弧線不該掉到腳下")


func test_朝左揮擊時弧線在左側() -> void:
	_player.global_position = Vector2(400, -200)
	_melee.show_arc = true
	await wait_physics_frames(1)

	_swing_through(-1.0)

	var arc := _find_arc()
	assert_not_null(arc)
	assert_almost_eq(arc.global_position.x, _player.global_position.x - 58.0, 1.0)


func test_下劈弧線在腳下() -> void:
	_player.global_position = Vector2(400, -200)
	_melee.show_arc = true
	await wait_physics_frames(1)

	_swing_through(1.0, true)

	var arc := _find_arc()
	assert_not_null(arc)
	assert_almost_eq(arc.global_position.x, _player.global_position.x, 1.0, "下劈弧線應在正下方")
	assert_almost_eq(arc.global_position.y, _player.global_position.y + 52.0, 1.0)


func test_沒有筆畫資料的字退回幾何弧線() -> void:
	# 「刂」不在 Make Me a Hanzi 資料集裡（Task 2.7c 的刀刃筆擊會用到）。
	# 沒有退路的話揮擊會變成一個看不見的攻擊。
	assert_true(HanziData.get_medians("刂").is_empty(), "前置條件：「刂」應該查不到筆畫")

	var arc := MeleeArc.spawn(_player, Vector2.ZERO, 1.0, "刂", Color.WHITE, 0.1, 58.0)
	assert_not_null(arc)
	assert_gt(arc.points.size(), 1, "查不到筆畫時必須退回幾何弧線")


# ---- Player 整合 ----

func test_Player按K揮擊並在死亡時中斷() -> void:
	assert_true(InputMap.has_action(&"melee"), "缺少 melee action")
	assert_true(InputMap.has_action(&"move_down"), "缺少 move_down action")

	assert_true(_player._try_melee(), "按 K 應該揮得出去")
	assert_true(_melee.is_swinging())

	_player.die()
	assert_eq(_melee.state, MeleeAttack.State.IDLE, "死亡當幀的揮擊必須立刻失效")
	assert_false(_player._try_melee(), "死亡後不可再揮")


func test_下劈彈起會重置跳躍次數() -> void:
	_player._jumps_used = 2
	_player.velocity.y = 500.0

	_player._on_pogo_bounced(-340.0)

	assert_eq(_player.velocity.y, -340.0)
	assert_eq(_player._jumps_used, 0, "踩著敵人應重新取得二段跳")


func test_melee與move_down綁在K與S() -> void:
	# [input] 是手寫的，事件字串打錯會變成「action 存在但沒綁任何按鍵」
	assert_eq(_physical_keycode(&"melee"), KEY_K)
	assert_eq(_physical_keycode(&"move_down"), KEY_S)


# ---- helpers ----

## 走完前搖進入判定並掃一次。回傳後元件停在 ACTIVE。
func _swing_through(direction: float, down: bool = false) -> void:
	_melee.swing(direction, {}, down)
	# 前搖 0.10s（下劈 0.06s）；多推一點確保跨過去
	_melee._physics_process(0.12)


## ⚠️ **位置必須在 add_child 之前設好。**
## 先 add_child 再移動的話，敵人會有一瞬間出現在原點、與玩家完全重疊，
## 物理去穿透會把玩家往旁邊推開整整一個身寬（52px）——
## 之後所有距離斷言都是從錯誤的座標量出來的。
func _spawn_enemy(offset: Vector2) -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	enemy.position = _player.global_position + offset
	# 敵人有重力，測試要的是靜態站位，直接停掉物理處理
	enemy.set_physics_process(false)
	add_child_autofree(enemy)
	enemy.setup({
		"char": "河", "element": "water", "ai": "patrol_ranged",
		"hp": 300, "damage": 0, "speed": 0,
	})
	# 新加入的碰撞體要等一次物理步進才進得了物理空間，形狀查詢才掃得到
	await wait_physics_frames(1)
	return enemy


func _spawn_enemy_bullet(offset: Vector2) -> Bullet:
	var bullet: Bullet = BulletScene.instantiate()
	bullet.collision_layer = EnemyAIShared.ENEMY_BULLET_LAYER
	bullet.collision_mask = EnemyAIShared.ENEMY_BULLET_MASK
	bullet.speed = 0.0
	bullet.position = _player.global_position + offset
	add_child_autofree(bullet)
	bullet.setup(5, "fire", _player.global_position + offset, Vector2.RIGHT)
	await wait_physics_frames(1)
	return bullet


func _find_arc() -> MeleeArc:
	for child: Node in _melee.get_children():
		if child is MeleeArc:
			return child as MeleeArc
	return null


func _physical_keycode(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null:
			return key_event.physical_keycode
	return KEY_NONE


func _release_inputs() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump", &"fire", &"melee", &"move_down"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)
