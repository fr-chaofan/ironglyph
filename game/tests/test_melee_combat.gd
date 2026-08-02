## 近戰與裝備狀態的整合（Task 2.7c）
##
## 涵蓋三件 2.7b 之後才成立的事：
## 1. GlyphLoadout 依裝備狀態分派 J/K 兩個動詞
## 2. 近戰打斷 stationary_aoe 的蓄力（遠程不行）
## 3. 近戰擊殺的掉落物會飛向玩家
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const PickupScene := preload("res://scenes/component_pickup.tscn")

var _player: Node2D
var _melee: MeleeAttack
var _loadout
var _weapon_manager: WeaponManager


func before_each() -> void:
	_player = PlayerScene.instantiate()
	_player.position = Vector2.ZERO
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_melee = _player.get_node(^"MeleeAttack") as MeleeAttack
	_melee.show_arc = false
	_loadout = _player.get_node(^"GlyphLoadout")
	_weapon_manager = _player.get_node(^"WeaponManager") as WeaponManager
	await wait_physics_frames(2)


# ---- J/K 分派（COMBAT.md 3.2 的表逐列驗證）----

func test_CORE時J是基礎弓K是令筆擊() -> void:
	assert_eq(_loadout.get_ranged_profile().get("id", ""), "gong")

	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "ling_slash")
	assert_eq(melee.get("element", ""), "neutral")
	assert_eq(melee.get("glyph", ""), "令")


func test_FUSED時K染上融合字的屬性() -> void:
	_loadout.equip_component_id("rain")

	assert_eq(_loadout.get_ranged_profile().get("id", ""), "reset_burst")

	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "ling_slash", "合體不改變近戰招式本身")
	assert_eq(
		melee.get("element", ""), "water",
		"合體除了換遠程武器，也該讓近戰吃到相剋——這是 FUSED 的第二層價值"
	)


func test_HELD投射類部件不影響K() -> void:
	_loadout.equip_component_id("fire")

	assert_eq(_loadout.get_ranged_profile().get("id", ""), "huo", "J 換成火球")
	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "ling_slash")
	assert_eq(melee.get("element", ""), "neutral", "投射類部件不該染到近戰")


func test_HELD近戰類刂強化K並讓J退回基礎弓() -> void:
	_loadout.equip_component_id("blade")

	var ranged: Dictionary = _loadout.get_ranged_profile()
	assert_eq(ranged.get("id", ""), "gong", "手持「刂」仍要有遠程手段，不能完全打不到遠處")
	assert_eq(_weapon_manager.get_current_weapon().get("id", ""), "gong")

	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "dao_slash", "「刂」強化的是 K")
	assert_eq(melee.get("element", ""), "metal", "刀刃筆擊吃金屬性（金剋木）")
	assert_eq(int(melee.get("damage", 0)), 24)


func test_彈出刂之後K回到令筆擊() -> void:
	_loadout.equip_component_id("blade")
	assert_eq(_loadout.get_melee_profile().get("id", ""), "dao_slash")

	_loadout.eject_component()

	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "ling_slash", "還回去之後只剩自己的筆擊")
	assert_eq(melee.get("element", ""), "neutral")


func test_snapshot帶著melee_weapon() -> void:
	_loadout.equip_component_id("blade")
	var snapshot: Dictionary = _loadout.get_snapshot()
	assert_eq((snapshot.get("melee_weapon", {}) as Dictionary).get("id", ""), "dao_slash")


func test_玩家實際揮出的是分派後的profile() -> void:
	_loadout.equip_component_id("blade")
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0), "wood")
	enemy.max_hp = 999
	enemy.hp = 999

	_player._try_melee()
	_melee._physics_process(0.12)

	# 刀刃筆擊 24 傷 × 金剋木 1.5 = 36
	assert_eq(enemy.hp, 999 - 36, "手持「刂」揮擊應該打出金屬性的刀刃筆擊")


# ---- 打斷蓄力 ----

func test_近戰打斷蓄力並復原字形縮放() -> void:
	var enemy: Enemy = await _spawn_charging_enemy(Vector2(80, 0))
	assert_true(enemy.is_charging(), "前置條件：敵人應該正在蓄力")

	watch_signals(_melee)
	_player._try_melee()
	_melee._physics_process(0.12)

	assert_false(enemy.is_charging(), "近戰應打斷蓄力")
	assert_signal_emit_count(_melee, "charge_interrupted", 1)
	assert_eq(
		enemy.hanzi_sprite.scale, Vector2.ONE,
		"打斷必須 kill 掉蓄力 tween 並復原縮放，否則敵人永遠停在放大狀態"
	)


func test_遠程打不斷蓄力() -> void:
	# 「只有近戰能打斷」是靠近錘／灶的唯一理由；遠程也能打斷的話就沒人需要靠近了
	var enemy: Enemy = await _spawn_charging_enemy(Vector2(80, 0))

	enemy.take_damage(5, "neutral")

	assert_true(enemy.is_charging(), "遠程傷害不該打斷蓄力")


func test_沒在蓄力時打斷不做任何事() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0), "water")
	assert_false(enemy.interrupt_charge(), "沒有蓄力可打斷時應回傳 false")


func test_非定點AOE的敵人不會因為打斷而報錯() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0), "water")  # patrol_ranged
	assert_false(enemy.interrupt_charge())


func test_敵人的近戰不能打斷() -> void:
	# 敵人也能打斷的話，玩家的每一次攻擊都會被貼身敵人打斷，變成互相鎖死
	var enemy_melee := MeleeAttack.new()
	enemy_melee.can_interrupt = false
	assert_false(enemy_melee.can_interrupt)
	enemy_melee.free()


# ---- 掉落物吸附 ----

func test_近戰命中會在目標身上留下記號() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0), "water")
	enemy.max_hp = 999
	enemy.hp = 999

	_player._try_melee()
	_melee._physics_process(0.12)

	assert_true(
		enemy.has_meta(MeleeAttack.MELEE_HIT_META),
		"記號要在 take_damage 之前留——掉落物是在 die() 裡同步生成的"
	)


func test_遠程命中不留記號() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(80, 0), "water")
	enemy.take_damage(5, "neutral")
	assert_false(enemy.has_meta(MeleeAttack.MELEE_HIT_META))


func test_掉落物被吸引時會朝玩家移動() -> void:
	var pickup: ComponentPickup = PickupScene.instantiate()
	pickup.position = Vector2(400, 0)
	add_child_autofree(pickup)
	pickup.setup({"id": "water", "display_glyph": "氵", "element": "water"})
	await wait_physics_frames(1)

	var before := pickup.global_position.distance_to(_player.global_position)
	pickup.attract_to(_player)
	assert_true(pickup.is_attracting())

	pickup._process(0.1)
	pickup._process(0.1)

	var after := pickup.global_position.distance_to(_player.global_position)
	assert_lt(after, before, "被吸引的掉落物應該朝玩家靠近")


func test_吸附不會自動裝備() -> void:
	# 「借」是玩家的主動選擇；自動裝備會把 Task 2.6 的分寸感洗掉
	var pickup: ComponentPickup = PickupScene.instantiate()
	pickup.position = Vector2(60, 0)
	add_child_autofree(pickup)
	pickup.setup({"id": "fire", "display_glyph": "火", "element": "fire"})
	await wait_physics_frames(1)

	pickup.attract_to(_player)
	for i in 20:
		pickup._process(0.05)

	assert_eq(_loadout.get_snapshot().get("mode", ""), "core", "沒按 E 就不該裝備上去")


func test_吸附到夠近就停下() -> void:
	var pickup: ComponentPickup = PickupScene.instantiate()
	pickup.position = Vector2(200, 0)
	add_child_autofree(pickup)
	pickup.setup({"id": "water", "display_glyph": "氵", "element": "water"})
	await wait_physics_frames(1)

	pickup.attract_to(_player)
	for i in 40:
		pickup._process(0.05)

	assert_false(pickup.is_attracting(), "靠得夠近就該停下，不要在玩家身上抖動")
	assert_lt(
		pickup.global_position.distance_to(_player.global_position),
		pickup.attract_stop_distance + 1.0
	)


# ---- helpers ----

func _spawn_enemy(offset: Vector2, element: String, ai: String = "patrol_ranged") -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	# ⚠️ 位置必須在 add_child 之前設好，否則敵人會有一瞬間與玩家重疊，
	# 物理去穿透會把玩家推開一個身寬，之後的距離斷言全部失準
	enemy.position = _player.global_position + offset
	enemy.set_physics_process(false)
	add_child_autofree(enemy)
	enemy.setup({
		"char": "河", "element": element, "ai": ai,
		"hp": 300, "damage": 0, "speed": 0,
	})
	await wait_physics_frames(1)
	return enemy


## 生成一隻正在蓄力的定點AOE敵人
func _spawn_charging_enemy(offset: Vector2) -> Enemy:
	var enemy: Enemy = await _spawn_enemy(offset, "fire", "stationary_aoe")
	var ai := enemy.get_node(^"AI")
	# 直接把冷卻清零並推進一次，讓它進入蓄力階段
	ai.set("_initialised", true)
	ai.set("_cooldown", 0.0)
	ai.call(&"decide_velocity", enemy, 0.01)
	return enemy
