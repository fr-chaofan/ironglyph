## 形聲合體字的特殊技能
##
## 九條配方原本只有數值與彈道形狀的差異。每個技能都是從**字的本義**長出來的：
## 零＝落雨、泠＝清越穿透、鈴＝聲響、苓＝藥、柃＝叢生、坽＝堤岸、
## 炩＝明亮灼燒、砱＝石縫、刢＝刃利。
##
## 技能全部寫在 `data/fusion_recipes.json` 的 `ability` 區塊，由 `Bullet` 統一結算——
## 不必為每個字開一支腳本。
extends GutTest

const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const FusionResolverScript := preload("res://scripts/fusion_resolver.gd")

var _host: Node2D
var _resolver


func before_each() -> void:
	_host = Node2D.new()
	add_child_autofree(_host)
	_resolver = FusionResolverScript.new()


func _ability(component_id: String) -> Dictionary:
	var attack: Dictionary = _resolver.resolve("令", component_id).get("attack", {})
	var raw: Variant = attack.get("ability", {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _spawn_enemy(offset: Vector2, element: String = "water", hp: int = 300) -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	enemy.position = offset
	enemy.set_physics_process(false)
	_host.add_child(enemy)
	enemy.setup({
		"char": "河", "element": element, "ai": "patrol_ranged",
		"hp": hp, "damage": 0, "speed": 0,
	})
	await wait_physics_frames(1)
	return enemy


func _fire(component_id: String, at: Vector2, shooter: Node = null) -> Bullet:
	var attack: Dictionary = _resolver.resolve("令", component_id).get("attack", {})
	var bullet: Bullet = BulletScene.instantiate()
	bullet.speed = 0.0
	# ⚠️ 關掉碰撞層。子彈與敵人重疊時真實碰撞會先觸發並把子彈釋放掉，
	# 測試再手動呼叫 _on_body_entered 就會打到已釋放的實例。
	# 這些測試要精確控制「命中了誰、命中幾次」，一律手動驅動。
	bullet.collision_layer = 0
	bullet.collision_mask = 0
	bullet.position = at
	bullet.ability = (attack.get("ability", {}) as Dictionary).duplicate(true)
	bullet.shooter = shooter
	_host.add_child(bullet)
	bullet.setup(int(attack.get("damage", 5)), String(attack.get("element", "neutral")), at, Vector2.RIGHT)
	await wait_physics_frames(1)
	return bullet


# ---- 每條配方都要有識別度 ----

func test_九條配方各有其技能或彈道() -> void:
	# 九個都只有數值差異的話，玩家分不出換部件到底換到了什麼
	var seen := {}
	for recipe: Dictionary in _resolver.get_all_recipes() if _resolver.has_method("get_all_recipes") else []:
		pass
	for component_id: String in ["rain", "water", "metal", "grass", "wood", "earth", "fire", "stone", "blade"]:
		var attack: Dictionary = _resolver.resolve("令", component_id).get("attack", {})
		assert_false(attack.is_empty(), "%s 應該有配方" % component_id)
		var signature := "%s|%s" % [
			String(attack.get("pattern", "single")),
			str((attack.get("ability", {}) as Dictionary).keys()),
		]
		if signature == "single|[]":
			assert_true(false, "%s 既沒有特殊彈道也沒有技能" % component_id)
		seen[component_id] = signature


# ---- 逐一驗證 ----

func test_泠穿透多個敵人() -> void:
	assert_eq(int(_ability("water").get("pierce", 0)), 2, "清泠：水聲清越，穿得過去")

	var first: Enemy = await _spawn_enemy(Vector2(0, 0))
	var bullet: Bullet = await _fire("water", Vector2.ZERO)
	var before: int = first.hp

	bullet._on_body_entered(first)
	assert_lt(first.hp, before)
	assert_false(bullet.is_queued_for_deletion(), "還有穿透次數就不該消失")


func test_泠用完穿透次數後消失() -> void:
	var bullet: Bullet = await _fire("water", Vector2.ZERO)
	for i in 3:
		var enemy: Enemy = await _spawn_enemy(Vector2(float(i) * 40.0, 0))
		bullet._on_body_entered(enemy)
	assert_true(bullet.is_queued_for_deletion(), "穿透次數用完必須消失，否則會穿到底")


func test_苓命中回血() -> void:
	# 玩家在此之前完全沒有回復手段——這是茯苓帶進來的新維度
	assert_gt(int(_ability("grass").get("heal", 0)), 0)

	var player: Node2D = preload("res://scenes/player.tscn").instantiate()
	_host.add_child(player)
	await wait_physics_frames(1)
	player.hp = 50

	var enemy: Enemy = await _spawn_enemy(Vector2(200, 0))
	var bullet: Bullet = await _fire("grass", Vector2(200, 0), player)
	bullet._on_body_entered(enemy)

	assert_gt(player.hp, 50, "茯苓散命中應該回血")


func test_苓不會回超過上限() -> void:
	var player: Node2D = preload("res://scenes/player.tscn").instantiate()
	_host.add_child(player)
	await wait_physics_frames(1)

	var enemy: Enemy = await _spawn_enemy(Vector2(200, 0))
	var bullet: Bullet = await _fire("grass", Vector2(200, 0), player)
	bullet._on_body_entered(enemy)

	assert_eq(player.hp, player.max_hp, "滿血時回血不可以溢出")


func test_鈴能隔空打斷蓄力() -> void:
	# 近戰能打斷是「為什麼要靠近錘／灶」的唯一理由，
	# 鈴聲震盪是那條規則的**唯一例外**——這種唯一最容易被記住
	assert_true(bool(_ability("metal").get("interrupt", false)))

	var enemy: Enemy = EnemyScene.instantiate()
	enemy.position = Vector2(200, 0)
	enemy.set_physics_process(false)
	_host.add_child(enemy)
	enemy.setup({
		"char": "灶", "element": "fire", "ai": "stationary_aoe",
		"hp": 300, "damage": 0, "speed": 0,
	})
	await wait_physics_frames(1)
	# 定點AOE 要偵測到玩家才會起手；測試場上沒有玩家，直接把蓄力狀態設起來
	var ai := enemy.get_node(^"AI")
	ai.set("_initialised", true)
	ai.set("_telegraph_left", 0.5)
	assert_true(enemy.is_charging(), "前置條件：敵人應該正在蓄力")

	var bullet: Bullet = await _fire("metal", Vector2(200, 0))
	bullet._on_body_entered(enemy)

	assert_false(enemy.is_charging(), "鈴聲應該隔空打斷蓄力")


func test_一般遠程仍然打不斷蓄力() -> void:
	# 若每種遠程都能打斷，靠近的理由就沒了
	assert_false(bool(_ability("water").get("interrupt", false)))
	assert_false(bool(_ability("earth").get("interrupt", false)))


func test_砱無視五行劣勢() -> void:
	assert_true(bool(_ability("stone").get("ignore_disadvantage", false)))

	# 土屬打木屬本來是劣勢（木剋土）
	var enemy: Enemy = await _spawn_enemy(Vector2(0, 0), "wood", 999)
	var bullet: Bullet = await _fire("stone", Vector2.ZERO)
	var damage: int = bullet.damage
	bullet._on_body_entered(enemy)

	assert_eq(999 - enemy.hp, damage, "劣勢倍率應該被抬到 1.0，扣滿原傷害")


func test_砱仍然吃得到優勢倍率() -> void:
	# 只抬下限，不是把倍率鎖死成 1.0
	var enemy: Enemy = await _spawn_enemy(Vector2(0, 0), "water", 999)
	var bullet: Bullet = await _fire("stone", Vector2.ZERO)
	bullet._on_body_entered(enemy)

	assert_gt(999 - enemy.hp, bullet.damage, "土剋水，優勢仍然要吃到")


func test_炩留下灼燒且不疊加() -> void:
	var burn: Dictionary = _ability("fire").get("burn", {})
	assert_gt(int(burn.get("ticks", 0)), 0)

	var enemy: Enemy = await _spawn_enemy(Vector2(0, 0), "wood", 999)
	var bullet: Bullet = await _fire("fire", Vector2.ZERO)
	bullet._on_body_entered(enemy)

	var effects := 0
	for child: Node in enemy.get_children():
		if child is BurnEffect:
			effects += 1
	assert_eq(effects, 1, "應該附上灼燒")

	# 再打一次不可以疊加——連射的火屬武器會讓傷害完全失控
	var second: Bullet = await _fire("fire", Vector2.ZERO)
	second._on_body_entered(enemy)
	effects = 0
	for child: Node in enemy.get_children():
		if child is BurnEffect:
			effects += 1
	assert_eq(effects, 1, "同一目標只能有一層灼燒")


func test_灼燒會按節拍扣血並自行結束() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(0, 0), "wood", 999)
	var burn := BurnEffect.apply(enemy, {"damage": 5, "ticks": 2, "interval": 0.1}, "fire")
	assert_not_null(burn)

	burn._process(0.15)
	assert_eq(999 - enemy.hp, 5, "第一跳應該扣血")

	burn._process(0.15)
	assert_true(burn.is_queued_for_deletion(), "跳完必須自己收掉，不可以永久燒下去")


func test_柃命中後彈向下一個敵人() -> void:
	assert_eq(int(_ability("wood").get("chain", 0)), 1)

	var first: Enemy = await _spawn_enemy(Vector2(0, 0))
	await _spawn_enemy(Vector2(120, 0))

	var before := _count_bullets()
	var bullet: Bullet = await _fire("wood", Vector2.ZERO)
	bullet._on_body_entered(first)
	await wait_physics_frames(1)

	assert_gt(_count_bullets(), before, "應該彈出一發新的")


func test_柃不會彈回剛打到的目標() -> void:
	# 不排除的話子彈會在同一個目標身上來回彈到次數用完
	var only: Enemy = await _spawn_enemy(Vector2(0, 0))
	var before := _count_bullets()
	var bullet: Bullet = await _fire("wood", Vector2.ZERO)
	bullet._on_body_entered(only)
	await wait_physics_frames(1)

	assert_eq(_count_bullets(), before, "場上只有一個敵人時不該彈出新的")


func test_坽立起墨牆擋敵方子彈() -> void:
	var wall_config: Dictionary = _ability("earth").get("wall", {})
	assert_gt(float(wall_config.get("duration", 0.0)), 0.0)

	var wall := InkWall.spawn(_host, Vector2.ZERO, wall_config, Color.WHITE)
	assert_not_null(wall, "坽壘應該立起一道牆")
	if wall == null:
		return

	assert_eq(wall.collision_layer, 0, "牆本身不可以參與碰撞，否則玩家會被自己的牆卡住")

	var sensor: Area2D = null
	for child: Node in wall.get_children():
		if child is Area2D:
			sensor = child as Area2D
			break
	assert_not_null(sensor)
	if sensor != null:
		assert_eq(sensor.collision_mask, 16, "只擋 enemy_bullet；擋自己的子彈等於把自己封死")


func test_刢兼具穿透且是唯一升級近戰的配方() -> void:
	assert_gt(int(_ability("blade").get("pierce", 0)), 0, "刢是刃利，該穿得過去")

	var with_melee: Array = []
	for component_id: String in ["rain", "water", "metal", "grass", "wood", "earth", "fire", "stone", "blade"]:
		var recipe: Dictionary = _resolver.resolve("令", component_id)
		if not String(recipe.get("melee_profile_id", "")).is_empty():
			with_melee.append(component_id)
	assert_eq(with_melee, ["blade"], "只有刢同時升級 K")


func _count_bullets() -> int:
	var count := 0
	for child: Node in _host.get_children():
		if child is Bullet:
			count += 1
	for child: Node in get_tree().root.get_children():
		if child is Bullet:
			count += 1
	return count
