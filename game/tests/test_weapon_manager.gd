## 武器管理與子彈（Task 2.2 / 2.3 / 2.4）
extends GutTest

var PlayerScene := preload("res://scenes/player.tscn")
var BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")

var _player: Node
var _wm: WeaponManager


func before_each() -> void:
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	await wait_physics_frames(2)
	_wm = _player.get_node(^"WeaponManager")


func after_each() -> void:
	for action: StringName in [&"weapon_next", &"weapon_prev", &"fire"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


# ---- Task 2.2 資料表 ----

func test_載入10把武器() -> void:
	assert_eq(_wm.weapons.size(), 10)


func test_每把武器欄位齊全() -> void:
	var required := ["id", "radical", "element", "name", "damage", "fire_rate", "projectile", "range"]
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


# ---- Task 2.3 切換 ----

func test_初始武器為第一把() -> void:
	assert_eq(_wm.current_index, 0)
	assert_eq(_wm.get_current_weapon()["id"], "shui")


func test_往後切換() -> void:
	_wm.cycle_weapon(1)
	assert_eq(_wm.current_index, 1)
	assert_eq(_wm.get_current_weapon()["id"], "huo")


func test_往前切換會繞回最後一把() -> void:
	_wm.cycle_weapon(-1)
	assert_eq(_wm.current_index, 9, "從第0把往前應繞到第9把，而非變成 -1")
	assert_eq(_wm.get_current_weapon()["id"], "shi")


func test_切換一整圈回到原點() -> void:
	for i in range(10):
		_wm.cycle_weapon(1)
	assert_eq(_wm.current_index, 0)


func test_切換時發出weapon_changed訊號() -> void:
	watch_signals(_wm)
	_wm.cycle_weapon(1)
	assert_signal_emitted(_wm, "weapon_changed")


func test_武器清單為空時切換不會除以零() -> void:
	_wm.weapons = []
	_wm.cycle_weapon(1)
	assert_eq(_wm.current_index, 0, "空清單時應直接返回，不應取模除以零")
	assert_eq(_wm.get_current_weapon(), {})


func test_Q鍵E鍵觸發切換() -> void:
	Input.action_press(&"weapon_next")
	await wait_physics_frames(2)
	Input.action_release(&"weapon_next")
	await wait_physics_frames(2)
	assert_eq(_wm.current_index, 1, "E 鍵應切到下一把")


# ---- Task 2.3 開火 ----

func test_開火有冷卻() -> void:
	assert_true(_wm.can_fire(), "初始應可開火")
	_wm.fire(1.0)
	assert_false(_wm.can_fire(), "剛開火後應在冷卻中")
	assert_almost_eq(_wm.cooldown, 0.4, 0.001, "水波彈 fire_rate 為 0.4")


func test_冷卻中重複開火不會生成第二發() -> void:
	var before := _count_bullets()
	_wm.fire(1.0)
	_wm.fire(1.0)
	_wm.fire(1.0)
	assert_eq(_count_bullets() - before, 1, "冷卻中的開火應被擋掉")


func test_開火生成子彈且帶對武器數值() -> void:
	_wm.fire(1.0)
	var bullets := _get_bullets()
	assert_gt(bullets.size(), 0, "應生成子彈")
	var b: Bullet = bullets[-1]
	assert_eq(b.damage, 8, "水波彈傷害為 8")
	assert_eq(b.element, "water")
	b.queue_free()


func test_子彈方向跟隨傳入的朝向() -> void:
	_wm.fire(-1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_lt(b.direction.x, 0.0, "朝左開火，子彈應往左飛")
	b.queue_free()


func test_子彈生成點在角色前方() -> void:
	_wm.fire(1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_gt(b.global_position.x, _player.global_position.x,
		"朝右開火時子彈應生成在角色右側，避免一出生就卡在自己的碰撞體裡")
	b.queue_free()


func test_子彈不掛在Player底下() -> void:
	# 掛在 Player 底下的話子彈會跟著角色移動，且角色死亡時會把空中的子彈一起帶走
	_wm.fire(1.0)
	var b: Bullet = _get_bullets()[-1]
	assert_ne(b.get_parent(), _player, "子彈不應掛在 Player 底下")
	b.queue_free()


# ---- Task 2.3 / 2.4 子彈 ----

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
