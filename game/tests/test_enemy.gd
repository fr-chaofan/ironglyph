## 敵人資料表、生成、AI 與死亡（Task 3.1 / 3.2 / 3.3 / 3.4）
extends GutTest

const EnemyScene := preload("res://scenes/enemy_base.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const FusionResolverScript := preload("res://scripts/fusion_resolver.gd")
const EXPECTED_DROP_COMPONENTS := {
	"河": "water",
	"海": "water",
	"湖": "water",
	"雨": "rain",
	"焰": "fire",
	"炎": "fire",
	"灶": "fire",
	"焚": "fire",
	"鋼": "metal",
	"針": "metal",
	"劍": "blade",
	"錘": "metal",
	"樹": "wood",
	"藤": "grass",
	"森": "wood",
	"林": "wood",
	"巖": "mountain",
	"石": "stone",
	"山": "mountain",
	"塵": "earth",
}


func _spawn_enemy(character: String) -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.setup(EnemySpawner.get_enemy_data(character))
	return enemy


# ---- Task 3.1 資料表 ----

func test_共20種敵人() -> void:
	assert_eq(EnemySpawner.get_all_enemy_data().size(), 20)


func test_每個屬性各4種() -> void:
	var by_element := {}
	for data: Dictionary in EnemySpawner.get_all_enemy_data():
		var element: String = data["element"]
		by_element[element] = by_element.get(element, 0) + 1

	assert_eq(by_element.size(), 5, "應涵蓋五個屬性")
	for element: String in ElementSystem.ELEMENTS:
		assert_eq(by_element.get(element, 0), 4, "%s 屬應有4種敵人" % element)


func test_每筆欄位齊全且數值合理() -> void:
	for data: Dictionary in EnemySpawner.get_all_enemy_data():
		for key: String in ["char", "element", "ai", "hp", "damage", "speed", "drop_component_id"]:
			assert_true(data.has(key), "敵人 %s 缺欄位 %s" % [data.get("char", "?"), key])
		assert_gt(int(data["hp"]), 0, "%s 的 hp 應為正" % data["char"])
		assert_gt(int(data["damage"]), 0, "%s 的 damage 應為正" % data["char"])
		assert_gte(float(data["speed"]), 0.0, "%s 的 speed 不應為負" % data["char"])


func test_每種敵人都掉落合法且指定的部件() -> void:
	var resolver := FusionResolverScript.new()
	var all_enemy_data: Array = EnemySpawner.get_all_enemy_data()
	assert_eq(all_enemy_data.size(), EXPECTED_DROP_COMPONENTS.size())

	for data: Dictionary in all_enemy_data:
		var character := String(data.get("char", ""))
		var component_id := String(data.get("drop_component_id", ""))
		assert_eq(
			component_id,
			EXPECTED_DROP_COMPONENTS.get(character, ""),
			"敵字「%s」的掉落部件不符合策展表" % character
		)
		assert_false(
			resolver.get_component(component_id).is_empty(),
			"敵字「%s」引用不存在的 component_id「%s」" % [character, component_id]
		)


func test_敵字都有筆畫資料() -> void:
	# 沒有筆畫資料的字，死亡時就跑不出筆畫崩解特效（會退回單純淡出）
	for data: Dictionary in EnemySpawner.get_all_enemy_data():
		assert_true(
			HanziData.has_character(data["char"]),
			"「%s」在 hanzi_decomposition.json 裡沒有資料，死亡特效會退化" % data["char"]
		)


func test_ai型別都是已實作的三種() -> void:
	const IMPLEMENTED := ["patrol_ranged", "chase_melee", "stationary_aoe"]
	for data: Dictionary in EnemySpawner.get_all_enemy_data():
		assert_has(IMPLEMENTED, data["ai"], "敵人 %s 的 ai「%s」沒有對應實作" % [data["char"], data["ai"]])


func test_定點型敵人速度為零() -> void:
	for data: Dictionary in EnemySpawner.get_all_enemy_data():
		if data["ai"] == "stationary_aoe":
			assert_eq(float(data["speed"]), 0.0, "%s 是定點型，速度應為0" % data["char"])


# ---- Task 3.2 敵人本體 ----

func test_setup灌入資料() -> void:
	var enemy := _spawn_enemy("河")
	assert_eq(enemy.hanzi_sprite.text, "河")
	assert_eq(enemy.element, "water")
	assert_eq(enemy.max_hp, 30)
	assert_eq(enemy.hp, 30)
	assert_eq(enemy.ai_type, "patrol_ranged")


func test_碰撞層為enemy() -> void:
	var enemy := _spawn_enemy("河")
	assert_eq(enemy.collision_layer, 4, "敵人應在 enemy 層")
	assert_eq(enemy.collision_mask & 1, 1, "應與 ground 碰撞")


func test_受五行相剋影響() -> void:
	var enemy := _spawn_enemy("焰")  # 火屬，hp 35
	enemy.take_damage(10, "water")   # 水剋火 ×1.5
	assert_eq(enemy.hp, 20, "35 - (10×1.5) = 20")


func test_三種AI都能掛上() -> void:
	for pair: Array in [["河", "patrol_ranged"], ["海", "chase_melee"], ["雨", "stationary_aoe"]]:
		var enemy := _spawn_enemy(pair[0])
		var ai := enemy.get_node_or_null(^"AI")
		assert_not_null(ai, "%s 應掛上 AI 節點" % pair[0])
		assert_true(ai.has_method(&"decide_velocity"), "AI 應實作 decide_velocity")


func test_未知ai型別退回巡邏而非崩潰() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.setup({"char": "河", "element": "water", "ai": "teleport_ninja", "hp": 10, "damage": 1, "speed": 10})

	# 應該留下警告讓人知道資料有問題，但不能崩潰
	assert_engine_error("teleport_ninja", "未知 ai_type 應發出警告")
	assert_not_null(enemy.get_node_or_null(^"AI"), "未知型別也該有可運作的 AI")
	assert_eq(enemy.ai_type, "teleport_ninja", "保留原始值以便除錯")


# ---- Task 3.2 AI 行為 ----

func test_定點型敵人不移動() -> void:
	var enemy := _spawn_enemy("雨")  # stationary_aoe
	var start_x := enemy.global_position.x
	await wait_physics_frames(10)
	assert_almost_eq(enemy.global_position.x, start_x, 0.5, "定點型不應水平移動")


func test_追擊型朝玩家移動() -> void:
	var player := PlayerScene.instantiate()
	add_child_autofree(player)
	player.global_position = Vector2(400, 0)

	var enemy := _spawn_enemy("海")  # chase_melee
	enemy.global_position = Vector2(0, 0)
	await wait_physics_frames(4)

	assert_gt(enemy.velocity.x, 0.0, "玩家在右邊，追擊型應往右移動")


func test_追擊型在沒有玩家時原地待命() -> void:
	var enemy := _spawn_enemy("海")
	await wait_physics_frames(4)
	assert_almost_eq(enemy.velocity.x, 0.0, 0.1, "場上沒有玩家時不應亂跑")


func test_巡邏型會左右來回() -> void:
	var enemy := _spawn_enemy("河")  # patrol_ranged, speed 80
	var ai := enemy.get_node(^"AI")
	ai.patrol_range = 40.0
	enemy.global_position = Vector2.ZERO
	await wait_physics_frames(4)

	var first_direction: float = signf(enemy.velocity.x)
	assert_ne(first_direction, 0.0, "巡邏型應該在移動")

	# 走超過巡邏範圍後應折返
	enemy.global_position.x = first_direction * 100.0
	await wait_physics_frames(3)
	assert_eq(signf(enemy.velocity.x), -first_direction, "超出巡邏範圍應折返")


func test_敵人子彈用enemy_bullet層() -> void:
	# 沿用玩家子彈的層會導致敵人互相誤傷、且打不到玩家
	var enemy := _spawn_enemy("河")
	var bullet := EnemyAIShared.spawn_enemy_bullet(enemy, Vector2.RIGHT, 8, "water")
	assert_eq(bullet.collision_layer, 16, "應在 enemy_bullet 層(16)")
	assert_eq(bullet.collision_mask & 2, 2, "應打得到 player")
	assert_eq(bullet.collision_mask & 4, 0, "不應打到其他敵人")
	bullet.queue_free()


func test_敵人子彈比玩家子彈慢() -> void:
	# 玩家要閃得掉才有操作空間
	var enemy := _spawn_enemy("河")
	var bullet := EnemyAIShared.spawn_enemy_bullet(enemy, Vector2.RIGHT, 8, "water")
	var player_bullet: Bullet = preload("res://scenes/projectiles/bullet_base.tscn").instantiate()
	add_child_autofree(player_bullet)
	assert_lt(bullet.speed, player_bullet.speed)
	bullet.queue_free()


# ---- Task 3.3 生成器 ----

func test_spawner生成正確敵人() -> void:
	var spawner := EnemySpawner.new()
	spawner.enemy_char = "劍"
	add_child_autofree(spawner)
	await wait_physics_frames(2)

	assert_not_null(spawner.current_enemy, "應生成敵人")
	assert_eq(spawner.current_enemy.element, "metal")
	assert_eq(spawner.current_enemy.max_hp, 40)


func test_spawner遇到未知敵字不崩潰() -> void:
	var spawner := EnemySpawner.new()
	spawner.enemy_char = "沒有這個字"
	spawner.spawn_on_ready = false
	add_child_autofree(spawner)

	assert_null(spawner.spawn(), "未知敵字應回傳 null")
	assert_push_error("沒有這個字", "應明確報錯指出是哪個敵字找不到")


# ---- Task 3.4 死亡特效 ----

func test_死亡時發出defeated訊號() -> void:
	var enemy := _spawn_enemy("塵")  # hp 20
	watch_signals(enemy)
	enemy.take_damage(999, "neutral")
	assert_signal_emitted(enemy, "defeated")


func test_筆畫崩解產生對應筆數的碎片() -> void:
	var enemy := _spawn_enemy("山")  # 山 共3筆
	var expected := HanziData.get_medians("山").size()
	assert_eq(expected, 3, "「山」應有3筆")

	var before := _count_fragments()
	enemy.take_damage(999, "neutral")
	await wait_physics_frames(2)

	assert_eq(_count_fragments() - before, expected, "碎片數應等於筆畫數")


func test_碎片會自行清除不殘留() -> void:
	var enemy := _spawn_enemy("山")
	enemy.hanzi_sprite.shatter_duration = 0.1

	var before := _count_fragments()
	enemy.take_damage(999, "neutral")
	await wait_physics_frames(2)
	assert_gt(_count_fragments(), before, "應先產生碎片")

	await wait_seconds(0.5)
	assert_eq(_count_fragments(), before, "碎片動畫結束後應全部釋放，不可累積")


func test_沒有筆畫資料時退回淡出而非報錯() -> void:
	var sprite := HanziSprite.new()
	sprite.character_text = "𰻞"  # 資料集不可能有的字
	add_child_autofree(sprite)
	await wait_physics_frames(1)
	sprite.shatter_and_die()
	await wait_physics_frames(2)
	pass_test("無筆畫資料時未報錯")


func test_死亡後敵人節點被釋放() -> void:
	var enemy := _spawn_enemy("塵")
	enemy.take_damage(999, "neutral")
	await wait_physics_frames(3)
	assert_false(is_instance_valid(enemy), "敵人本體應被釋放")


# ---- helpers ----

## 筆畫碎片是 Line2D，掃整棵場景樹數出來
## ⚠️ 用 group 而不是「是不是 Line2D」來認碎片。
## 場上的 Line2D 不只崩解碎片一種——字形的筆畫渲染、揮擊刀氣的每一層都是，
## 按型別數會把它們全部數進來，敵人死亡時筆畫被釋放還會讓數量變成負的。
func _count_fragments() -> int:
	return get_tree().get_nodes_in_group(&"stroke_fragment").size()



