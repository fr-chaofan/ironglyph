## 敵人的三段式揮擊（Task 2.7d）
##
## Task 2.7d 之前 `chase_melee` 只是「一團會走路的接觸傷害」——沒有前搖可讀、
## 沒有後搖可懲罰。這裡驗證改造後的節奏對玩家是**可閱讀、可懲罰**的。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")
const ChaseAI := preload("res://scripts/enemy_ai_chase.gd")

var _player: Node2D


func before_each() -> void:
	_player = PlayerScene.instantiate()
	_player.position = Vector2.ZERO
	add_child_autofree(_player)
	_player.set_physics_process(false)
	await wait_physics_frames(2)


# ---- 資料表 ----

func test_每隻近戰敵人都有melee區塊() -> void:
	for data: Dictionary in _load_enemies():
		if String(data.get("ai", "")) != "chase_melee":
			continue
		var melee: Variant = data.get("melee", null)
		assert_eq(
			typeof(melee), TYPE_DICTIONARY,
			"「%s」是 chase_melee 卻沒有 melee 區塊，會退回預設節奏" % data.get("char", "?")
		)
		for key: String in ["windup", "active", "recovery"]:
			assert_true((melee as Dictionary).has(key), "「%s」的 melee 缺 %s" % [data.get("char"), key])


func test_前搖長度隨傷害遞增() -> void:
	# 大傷害要給得起的預兆。針(9傷)必須比劍(18傷)快得多，
	# 否則「讀預兆」這件事對兩者是同一個難度，敵人就沒有性格差異。
	var needle := _find_enemy("針")
	var sword := _find_enemy("劍")
	var dust := _find_enemy("塵")

	assert_lt(
		float(needle.get("melee", {}).get("windup", 0.0)),
		float(sword.get("melee", {}).get("windup", 0.0)),
		"針的預兆必須比劍短"
	)
	assert_lt(
		float(dust.get("melee", {}).get("windup", 0.0)),
		float(needle.get("melee", {}).get("windup", 0.0)),
		"塵是全場最快最弱的，預兆應該最短"
	)


func test_後搖都不短於前搖() -> void:
	# 後搖是玩家的懲罰窗口。比前搖還短的話，讀對預兆也換不到反打機會。
	for data: Dictionary in _load_enemies():
		var melee: Variant = data.get("melee", null)
		if typeof(melee) != TYPE_DICTIONARY:
			continue
		assert_gte(
			float((melee as Dictionary).get("recovery", 0.0)),
			float((melee as Dictionary).get("windup", 0.0)),
			"「%s」的後搖比前搖短，讀對預兆卻沒有反打窗口" % data.get("char", "?")
		)


func test_攻擊距離短於玩家的最遠命中距離() -> void:
	# 玩家的近戰最遠命中 120px。敵人若能從更遠處打到，
	# 「站在安全窗口外緣揮擊」的設計就完全失效。
	var ai := ChaseAI.new()
	assert_lt(ai.attack_range, 120.0, "敵人的攻擊距離必須小於玩家的最遠命中距離")
	ai.free()


# ---- 三段式節奏 ----

func test_進入距離後揮擊並走完三段() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	var melee := enemy.melee_attack

	_tick(enemy, 0.01)
	assert_eq(melee.state, MeleeAttack.State.WINDUP, "進入攻擊距離應開始前搖")

	melee._physics_process(0.5)  # 劍的前搖 0.45s
	assert_eq(melee.state, MeleeAttack.State.ACTIVE)

	melee._physics_process(0.13)
	assert_eq(melee.state, MeleeAttack.State.COOLDOWN, "判定結束進入後搖")

	melee._physics_process(0.6)
	assert_eq(melee.state, MeleeAttack.State.IDLE)


func test_前搖期間不造成傷害() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	var before: int = _player.hp

	_tick(enemy, 0.01)
	enemy.melee_attack._physics_process(0.2)  # 仍在 0.45s 前搖內

	assert_eq(_player.hp, before, "前搖期間不該扣血，否則預兆等於沒有")


func test_判定期間打到玩家() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	var before: int = _player.hp

	_tick(enemy, 0.01)
	enemy.melee_attack._physics_process(0.5)

	assert_lt(_player.hp, before, "判定期間應該打到玩家")


func test_前搖與後搖期間敵人定住不動() -> void:
	# 後搖不動就是玩家的懲罰窗口——揮空還能立刻退開的話，反打就沒有獎勵
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))

	_tick(enemy, 0.01)
	assert_eq(_tick(enemy, 0.01), 0.0, "前搖期間不可移動")

	enemy.melee_attack._physics_process(0.5)
	enemy.melee_attack._physics_process(0.13)
	assert_eq(enemy.melee_attack.state, MeleeAttack.State.COOLDOWN)
	assert_eq(_tick(enemy, 0.01), 0.0, "後搖期間不可移動")


func test_距離太遠時朝玩家接近() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(300, 0))
	# 敵人在玩家右側，應該往左（負方向）走
	assert_lt(_tick(enemy, 0.01), 0.0, "超出攻擊距離應該接近玩家")


func test_高度差太大不揮擊() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 200))
	_tick(enemy, 0.01)
	assert_eq(
		enemy.melee_attack.state, MeleeAttack.State.IDLE,
		"判定框只有 56 高，垂直差太大時揮了也打不到"
	)


# ---- 接觸傷害 ----

func test_近戰敵人不再造成接觸傷害() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	assert_true(enemy.has_own_melee())

	var before: int = _player.hp
	enemy._check_touch_damage()

	assert_eq(_player.hp, before, "有可讀揮擊之後，接觸傷害只會變成蹭血的噪音")


func test_遠程與定點敵人保留接觸傷害() -> void:
	# 貼臉貼太久還是要有代價，否則玩家可以站在遠程敵人身上安全輸出
	var ranged: Enemy = await _spawn_melee_enemy("河", Vector2(80, 0))
	assert_false(ranged.has_own_melee(), "patrol_ranged 不該有自己的揮擊")


# ---- 敵我不對稱 ----

func test_敵人的揮擊不消玩家子彈() -> void:
	# 敵人也能消彈的話，玩家的遠程武器會完全失效
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	assert_eq(enemy.melee_attack.block_mask, 0)

	# ⚠️ 子彈不能放在敵人身上——它的 mask 含 enemy 層，會自然命中敵人而消失，
	# 測到的就不是「敵人有沒有揮掉它」。放在敵人揮擊範圍內、但不碰到敵人身體的位置。
	var bullet_position: Vector2 = enemy.global_position + Vector2(-40.0, 0.0)
	var bullet: Bullet = BulletScene.instantiate()
	bullet.speed = 0.0
	bullet.position = bullet_position
	add_child_autofree(bullet)
	bullet.setup(5, "neutral", bullet_position, Vector2.RIGHT)
	await wait_physics_frames(1)
	assert_false(bullet.is_queued_for_deletion(), "前置條件：子彈不該一生成就被打掉")

	_tick(enemy, 0.01)
	enemy.melee_attack._physics_process(0.5)

	assert_false(bullet.is_queued_for_deletion(), "敵人不可以揮掉玩家的子彈")


func test_敵人的揮擊不能打斷() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	assert_false(
		enemy.melee_attack.can_interrupt,
		"敵人也能打斷的話，玩家的每次攻擊都會被貼身敵人打斷，變成互相鎖死"
	)


# ---- 視覺預兆 ----

func test_前搖時字形傾斜且不鏡像() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))

	_tick(enemy, 0.01)
	await wait_seconds(0.3)  # 讓傾斜 tween 跑一段

	assert_ne(enemy.hanzi_sprite.rotation, 0.0, "前搖應該讓字形往攻擊方向傾斜")
	assert_gt(
		enemy.hanzi_sprite.scale.x, 0.0,
		"傾斜要用 rotation，不可用負的 scale.x——漢字鏡像後會變成無法辨識的反字"
	)
	assert_ne(enemy.hanzi_sprite.self_modulate, Color.WHITE, "前搖應該染色")


func test_死亡時取消揮擊() -> void:
	var enemy: Enemy = await _spawn_melee_enemy("劍", Vector2(80, 0))
	_tick(enemy, 0.01)
	assert_true(enemy.melee_attack.is_swinging())

	enemy.die()
	assert_eq(
		enemy.melee_attack.state, MeleeAttack.State.IDLE,
		"死亡當幀的揮擊必須立刻失效，否則屍體還會再打出一下"
	)


# ---- helpers ----

## 推進一次 AI 決策，回傳它決定的水平速度
func _tick(enemy: Enemy, delta: float) -> float:
	var ai := enemy.get_node(^"AI")
	return ai.call(&"decide_velocity", enemy, delta)


func _spawn_melee_enemy(enemy_char: String, offset: Vector2) -> Enemy:
	var data := _find_enemy(enemy_char)
	var enemy: Enemy = EnemyScene.instantiate()
	# 位置要在 add_child 之前設好，否則與玩家重疊會被去穿透推開
	enemy.position = _player.global_position + offset
	enemy.set_physics_process(false)
	add_child_autofree(enemy)
	enemy.setup(data)
	enemy.melee_attack.show_arc = false
	await wait_physics_frames(1)
	return enemy


func _load_enemies() -> Array:
	var file := FileAccess.open("res://data/enemies.json", FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _find_enemy(enemy_char: String) -> Dictionary:
	for data: Dictionary in _load_enemies():
		if String(data.get("char", "")) == enemy_char:
			return data.duplicate(true)
	return {}
