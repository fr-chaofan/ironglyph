## 武器管理與子彈（Task 2.2 / 2.3 / 2.4）
extends GutTest

var PlayerScene := preload("res://scenes/player.tscn")
var BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")
const FusionResolverScript := preload("res://scripts/fusion_resolver.gd")

var _player: Node
var _wm: WeaponManager


func before_each() -> void:
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	await wait_physics_frames(2)
	_wm = _player.get_node(^"WeaponManager")


func after_each() -> void:
	for action: StringName in [&"interact", &"eject_component", &"fire"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


# ---- Task 2.2 資料表 ----

func test_載入10把武器() -> void:
	assert_eq(_wm.weapons.size(), 10)


func test_每把武器欄位齊全() -> void:
	var required := [
		"id", "radical", "element", "name", "damage", "fire_rate",
		"attack_type", "projectile", "range",
	]
	for w: Dictionary in _wm.weapons:
		for key: String in required:
			assert_true(w.has(key), "武器 %s 缺欄位 %s" % [w.get("id", "?"), key])


func test_武器id不重複() -> void:
	var seen := {}
	for w: Dictionary in _wm.weapons:
		var id: String = w["id"]
		assert_false(seen.has(id), "武器id重複：%s" % id)
		seen[id] = true


func test_武器屬性都是合法五行或neutral() -> void:
	var valid: Array = ElementSystem.ELEMENTS + ["neutral"]
	for w: Dictionary in _wm.weapons:
		assert_has(valid, w["element"], "武器 %s 的屬性 %s 不合法" % [w["id"], w["element"]])


func test_五行武器各有涵蓋() -> void:
	# 缺任一屬性的武器，玩家就沒辦法剋制對應的敵人
	var covered := {}
	for w: Dictionary in _wm.weapons:
		covered[w["element"]] = true
	for element: String in ElementSystem.ELEMENTS:
		assert_true(covered.has(element), "沒有任何 %s 屬性的武器" % element)


# ---- Task 2.6 active attack executor ----

func test_CORE由GlyphLoadout指定中性基礎攻擊() -> void:
	assert_eq(_wm.get_current_weapon().get("id", ""), "gong")
	assert_eq(_wm.current_index, 5, "弓在catalog中的位置只供debug辨識，不是inventory slot")


func test_可按id選擇catalog中的攻擊profile() -> void:
	assert_true(_wm.set_active_weapon_by_id("shui"))
	assert_eq(_wm.get_current_weapon().get("id", ""), "shui")
	assert_eq(_wm.current_index, 0)


func test_未知攻擊id安全清空() -> void:
	assert_false(_wm.set_active_weapon_by_id("missing"))
	assert_eq(_wm.get_current_weapon(), {})
	assert_eq(_wm.current_index, -1)
	assert_false(_wm.can_fire())


func test_設定active_attack時發出weapon_changed訊號() -> void:
	watch_signals(_wm)
	_wm.set_active_weapon_by_id("shui")
	assert_signal_emitted(_wm, "weapon_changed")


func test_E與Q不再循環永久武器catalog() -> void:
	var original_id: String = _wm.get_current_weapon().get("id", "")
	Input.action_press(&"interact")
	await wait_physics_frames(2)
	Input.action_release(&"interact")
	Input.action_press(&"eject_component")
	await wait_physics_frames(2)
	Input.action_release(&"eject_component")
	await wait_physics_frames(2)
	assert_eq(_wm.get_current_weapon().get("id", ""), original_id,
		"沒有拾取物／已裝備部件時，E/Q不可遍歷十把永久武器")


# ---- Task 2.7a 攻擊型別與射程 ----

func test_attack_type只有兩種合法值() -> void:
	for w: Dictionary in _wm.weapons:
		assert_has(
			["projectile", "melee"], w.get("attack_type", ""),
			"武器 %s 的 attack_type 不合法" % w.get("id", "?")
		)


func test_range值都在合法集合內() -> void:
	# range 從死資料變成真的會影響飛行距離，打錯字會靜默變成不限射程
	var valid := Bullet.RANGE_DISTANCES.keys()
	valid.append("melee")
	for w: Dictionary in _wm.weapons:
		assert_has(valid, w.get("range", ""), "武器 %s 的 range 不合法" % w.get("id", "?"))


func test_近戰刀標記為melee而非投射物() -> void:
	var dao: Dictionary = _wm.get_weapon_by_id("dao")
	assert_eq(dao.get("attack_type", ""), "melee", "「刂・近戰刀」不該是投射物")


func test_近戰武器開火時退回基礎弓而不是丟出一把飛刀() -> void:
	assert_true(_wm.set_active_weapon_by_id("dao"))
	_wm.cooldown = 0.0

	_wm.fire(1.0)
	var bullets := _get_bullets()

	assert_eq(bullets.size(), 1, "J 仍應有遠程手段，不能完全打不出東西")
	var b: Bullet = bullets[-1]
	assert_eq(b.damage, 7, "應退回基礎弓「弓」的 7 傷，而不是近戰刀的 14")
	assert_almost_eq(_wm.cooldown, 0.3, 0.001, "冷卻也應該用弓的 fire_rate")
	b.queue_free()


func test_三種射程換算成不同的飛行距離() -> void:
	# 2.7a 之前「暗器(long)」與「藤蔓刺(short)」的射程完全一樣
	assert_eq(Bullet.RANGE_DISTANCES["short"], 180.0)
	assert_eq(Bullet.RANGE_DISTANCES["medium"], 420.0)
	assert_eq(Bullet.RANGE_DISTANCES["long"], 720.0)

	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	b.set_range("short")
	assert_eq(b.max_distance, 180.0)
	b.set_range("long")
	assert_eq(b.max_distance, 720.0)


func test_未知射程與melee不限距離() -> void:
	# 近戰武器不該走到生成子彈這條路；真的走到了也讓它照舊飛，
	# 不要靜默變成射程 0 的啞彈
	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)

	b.set_range("melee")
	assert_eq(b.max_distance, 0.0)
	b.set_range("no_such_range")
	assert_eq(b.max_distance, 0.0)


func test_子彈飛超過射程就釋放() -> void:
	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	b.speed = 1000.0
	b.set_range("short")  # 180px
	b.setup(5, "neutral", Vector2.ZERO, Vector2.RIGHT)

	b._physics_process(0.1)  # 飛 100px
	assert_false(b.is_queued_for_deletion(), "還沒到 180px 不該消失")

	b._physics_process(0.1)  # 累計 200px
	assert_true(b.is_queued_for_deletion(), "超過射程上限必須消失")


func test_往左飛也會累計射程() -> void:
	# 位移是負的，用 absf 累計；忘了取絕對值的話往左的子彈永遠不會到期
	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	b.speed = 1000.0
	b.set_range("short")
	b.setup(5, "neutral", Vector2.ZERO, Vector2.LEFT)

	b._physics_process(0.1)
	b._physics_process(0.1)
	assert_true(b.is_queued_for_deletion(), "朝左飛的子彈也必須受射程限制")


func test_遠程武器實際生成的子彈帶對射程() -> void:
	assert_true(_wm.set_active_weapon_by_id("jin"))  # 暗器 long
	_wm.cooldown = 0.0
	_wm.fire(1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_eq(b.max_distance, 720.0, "暗器是 long，應為 720px")
	b.queue_free()


# ---- Task 2.3 開火 ----

func test_開火有冷卻() -> void:
	_equip_water()
	assert_true(_wm.can_fire(), "初始應可開火")
	_wm.fire(1.0)
	assert_false(_wm.can_fire(), "剛開火後應在冷卻中")
	assert_almost_eq(_wm.cooldown, 0.4, 0.001, "水波彈 fire_rate 為 0.4")


func test_冷卻中重複開火不會生成第二發() -> void:
	_equip_water()
	var before := _count_bullets()
	_wm.fire(1.0)
	_wm.fire(1.0)
	_wm.fire(1.0)
	assert_eq(_count_bullets() - before, 1, "冷卻中的開火應被擋掉")


func test_開火生成子彈且帶對武器數值() -> void:
	_equip_water()
	_wm.fire(1.0)
	var bullets := _get_bullets()
	assert_gt(bullets.size(), 0, "應生成子彈")
	var b: Bullet = bullets[-1]
	assert_eq(b.damage, 8, "水波彈傷害為 8")
	assert_eq(b.element, "water")
	b.queue_free()


func test_子彈方向跟隨傳入的朝向() -> void:
	_equip_water()
	_wm.fire(-1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_lt(b.direction.x, 0.0, "朝左開火，子彈應往左飛")
	b.queue_free()


func test_子彈生成點在角色前方() -> void:
	_equip_water()
	_wm.fire(1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_gt(b.global_position.x, _player.global_position.x,
		"朝右開火時子彈應生成在角色右側，避免一出生就卡在自己的碰撞體裡")
	b.queue_free()


func test_子彈不掛在Player底下() -> void:
	_equip_water()
	# 掛在 Player 底下的話子彈會跟著角色移動，且角色死亡時會把空中的子彈一起帶走
	_wm.fire(1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_ne(b.get_parent(), _player, "子彈不應掛在 Player 底下")
	b.queue_free()


func test_零落從上方落下() -> void:
	# 「零」的本義就是落雨（零 = 雨 + 令）。這是全場唯一從天而降的攻擊——
	# 打得到直射打不到的東西，也是它與其他八條配方最大的區別。
	var recipe: Dictionary = FusionResolverScript.new().resolve("令", "rain")
	var attack: Dictionary = recipe.get("attack", {})
	assert_eq(attack.get("pattern", ""), "rain")
	assert_true(_wm.set_active_weapon(attack))

	var before := _get_bullets()
	_wm.fire(1.0)
	var spawned: Array = []
	for bullet: Bullet in _get_bullets():
		if not before.has(bullet):
			spawned.append(bullet)

	assert_eq(spawned.size(), 7, "零落應生成7滴")
	for bullet: Bullet in spawned:
		assert_eq(bullet.element, "water")
		assert_gt(bullet.direction.y, 0.9, "每一滴都要往下落")
		assert_lt(
			bullet.global_position.y, _player.global_position.y,
			"生成點必須在玩家上方，否則不是「從天而降」"
		)
		bullet.queue_free()


func test_子彈碰撞層設定正確() -> void:
	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	# layer_4 = player_bullet = 位元值 8
	assert_eq(b.collision_layer, 8, "子彈應在 player_bullet 層")
	assert_eq(b.collision_mask & 4, 4, "應偵測 enemy")
	assert_eq(b.collision_mask & 1, 1, "應偵測 ground，否則會穿牆")
	assert_eq(b.collision_mask & 2, 0, "不應偵測 player，否則會打到自己")


func test_子彈用body_entered而非area_entered() -> void:
	# Character 是 CharacterBody2D（PhysicsBody2D），Area2D 的 area_entered
	# 對 PhysicsBody2D 永遠不會觸發——接錯訊號會導致「子彈能飛但打不到人」
	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	await wait_physics_frames(1)
	assert_true(b.body_entered.is_connected(b._on_body_entered), "應連接 body_entered")


func test_子彈超過存活上限自動釋放() -> void:
	var b: Bullet = BulletScene.instantiate()
	b.max_lifetime = 0.05
	add_child_autofree(b)
	b.setup(5, "neutral", Vector2.ZERO, Vector2.RIGHT)
	await wait_seconds(0.2)
	assert_false(is_instance_valid(b), "打空的子彈必須自動消失，否則會無限累積節點")


func test_子彈按五行著色() -> void:
	# Task 2.4：顏色是玩家辨識屬性的主要線索
	var seen_colors := {}
	for element: String in ElementSystem.ELEMENTS:
		var b: Bullet = BulletScene.instantiate()
		add_child_autofree(b)
		b.setup(5, element, Vector2.ZERO, Vector2.RIGHT)
		assert_ne(b.modulate, Color.WHITE, "%s 屬性子彈應有專屬顏色" % element)
		seen_colors[b.modulate] = element
	assert_eq(seen_colors.size(), 5, "五個屬性的顏色應互不相同")


func test_六種顏色兩兩之間有足夠差異() -> void:
	# 實機驗證時發現金屬(0.8,0.8,0.9)與中性純白在畫面上分辨不出來。
	# 顏色是玩家辨識屬性的主要線索，撞色等於這個線索失效。
	# 這裡量化把關：任兩色的RGB距離必須超過門檻。
	const MIN_DISTANCE := 0.45

	var names: Array = Bullet.ELEMENT_COLORS.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: Color = Bullet.ELEMENT_COLORS[names[i]]
			var b: Color = Bullet.ELEMENT_COLORS[names[j]]
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			assert_gt(
				distance, MIN_DISTANCE,
				"「%s」與「%s」顏色太接近（距離 %.2f），畫面上會分辨不出來" % [names[i], names[j], distance]
			)


func test_中性色不是純白() -> void:
	# 五行傳統配色是「金＝白」，中性色若也用白就必然與金屬撞色。
	# 正解是把中性色移開白色，而不是改動金屬色。
	assert_ne(Bullet.ELEMENT_COLORS["neutral"], Color.WHITE,
		"中性色用純白會與五行的金屬色撞色")


func test_子彈命中Character會扣血() -> void:
	var target: Character = preload("res://scripts/character.gd").new()
	target.max_hp = 100
	target.element = "fire"
	add_child_autofree(target)
	await wait_physics_frames(1)

	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	b.setup(10, "water", Vector2.ZERO, Vector2.RIGHT)
	b._on_body_entered(target)

	assert_eq(target.hp, 85, "水打火 10 傷害 ×1.5 = 15")


func test_子彈命中地形會消失但不報錯() -> void:
	var wall := StaticBody2D.new()
	add_child_autofree(wall)
	var b: Bullet = BulletScene.instantiate()
	add_child_autofree(b)
	b.setup(10, "water", Vector2.ZERO, Vector2.RIGHT)
	b._on_body_entered(wall)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(b), "打到地形應消失，不能穿牆")


# ---- helpers ----

func _get_bullets() -> Array:
	var found: Array = []
	_collect_bullets(get_tree().root, found)
	return found


func _collect_bullets(node: Node, found: Array) -> void:
	if node is Bullet:
		found.append(node)
	for child: Node in node.get_children():
		_collect_bullets(child, found)


func _count_bullets() -> int:
	return _get_bullets().size()


func _equip_water() -> void:
	assert_true(_wm.set_active_weapon_by_id("shui"))
	_wm.cooldown = 0.0
