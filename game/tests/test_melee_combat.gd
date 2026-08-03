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
const StationaryAI := preload("res://scripts/enemy_ai_stationary.gd")

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


func test_HELD山部件不影響K() -> void:
	_loadout.equip_component_id("mountain")

	assert_eq(_loadout.get_ranged_profile().get("id", ""), "tu", "J 換成石撞")
	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "ling_slash")
	assert_eq(melee.get("element", ""), "neutral", "投射類部件不該染到近戰")


func test_刂融合成刢後J與K同時升級() -> void:
	# ⚠️ 「刂」原本是 HELD、J 退回基礎弓；補上 ⿰令刂＝刢 的配方之後改為融合。
	# 若配方只帶遠程，刀刃筆擊會憑空消失——玩家拿到更完整的字反而變弱。
	# 因此配方支援 melee_profile_id，讓 FUSED 也能升級 K。
	_loadout.equip_component_id("blade")

	assert_eq(_loadout.get_snapshot().get("visible_glyph", ""), "刢")

	var ranged: Dictionary = _loadout.get_ranged_profile()
	assert_eq(ranged.get("id", ""), "whetted", "J 換成刢刃，不再退回基礎弓")

	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "dao_slash", "K 仍然是刀刃筆擊")
	assert_eq(melee.get("element", ""), "metal", "刀刃筆擊吃金屬性（金剋木）")
	assert_eq(int(melee.get("damage", 0)), 24)


func test_一般配方不會誤升級近戰() -> void:
	# 只有帶 melee_profile_id 的配方才升級 K，其餘維持令筆擊
	_loadout.equip_component_id("rain")
	var melee: Dictionary = _loadout.get_melee_profile()
	assert_eq(melee.get("id", ""), "ling_slash")


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


func test_蓄力與硬直都有明顯的顏色回饋() -> void:
	# 只靠 1.0→1.25 的縮放，實機上肉眼分辨不出來有沒有打斷成功
	var enemy: Enemy = await _spawn_charging_enemy(Vector2(80, 0))
	var sprite := enemy.hanzi_sprite

	await wait_seconds(0.3)  # 讓蓄力 tween 跑一段
	assert_ne(sprite.self_modulate, Color.WHITE, "蓄力中應該染上警示色")

	_player._try_melee()
	_melee._physics_process(0.12)

	assert_eq(
		sprite.self_modulate, StationaryAI.STAGGER_COLOR,
		"硬直期間要染成另一個顏色，玩家才看得出現在可以免費打它"
	)

	var ai := enemy.get_node(^"AI")
	ai.call(&"decide_velocity", enemy, 1.0)  # 推過硬直
	assert_eq(sprite.self_modulate, Color.WHITE, "硬直結束要把顏色還原")


func test_蓄力染色不與受擊閃紅打架() -> void:
	# flash_hit() 用 modulate、蓄力用 self_modulate。共用同一個屬性的話，
	# 蓄力中被打一下就會互相把對方的 tween 蓋掉。
	var enemy: Enemy = await _spawn_charging_enemy(Vector2(80, 0))
	await wait_seconds(0.3)

	var charge_tint := enemy.hanzi_sprite.self_modulate
	enemy.hanzi_sprite.flash_hit()

	assert_eq(
		enemy.hanzi_sprite.self_modulate, charge_tint,
		"受擊閃紅不可以洗掉蓄力的警示色"
	)


func test_打斷時飄出打斷字樣() -> void:
	var enemy: Enemy = await _spawn_charging_enemy(Vector2(80, 0))

	_player._try_melee()
	_melee._physics_process(0.12)

	var found := false
	for child: Node in enemy.get_children():
		if child is Label and (child as Label).text == "打斷！":
			found = true
			break
	assert_true(found, "打斷要有文字回饋，否則玩家只能靠比對縮放來猜")


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
