## 字形可讀性與打擊感（視覺第一輪）
##
## 這裡驗證的都是**資訊傳達**而不是好不好看：敵人身上看不看得出屬性、
## 主角能不能一眼與敵人區分、命中停頓會不會把遊戲卡在慢動作。
## 好不好看只有在有畫面的機器上才判斷得了。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const EnvironmentScene := preload("res://scenes/world_environment.tscn")
const DummyScene := preload("res://scenes/training_dummy.tscn")


func after_each() -> void:
	# 停頓沒還原的話，後面每一支測試都會在慢動作裡跑
	Engine.time_scale = 1.0
	GameFeel.enabled = true


# ---- 屬性著色 ----

func test_敵人字形依五行著色() -> void:
	# 在此之前敵人一律是白的：子彈有顏色、傷害數字有剋/抗，
	# 唯獨敵人本體沒有屬性線索，玩家只能靠背字表
	for element: String in ["water", "fire", "metal", "wood", "earth"]:
		var enemy: Enemy = EnemyScene.instantiate()
		add_child_autofree(enemy)
		enemy.setup({
			"char": "河", "element": element, "ai": "patrol_ranged",
			"hp": 30, "damage": 0, "speed": 0,
		})

		var color := enemy.hanzi_sprite.get_theme_color(&"font_color")
		var expected: Color = Bullet.ELEMENT_COLORS[element]
		assert_almost_eq(
			color.r / HanziSprite.ELEMENT_GLOW_BOOST, expected.r, 0.01,
			"%s 屬敵人的字形顏色不對" % element
		)
		assert_almost_eq(color.g / HanziSprite.ELEMENT_GLOW_BOOST, expected.g, 0.01)
		assert_almost_eq(color.b / HanziSprite.ELEMENT_GLOW_BOOST, expected.b, 0.01)


func test_每個屬性都與紙色拉得夠開() -> void:
	# ⚠️ 紙上的可讀性門檻是「離紙多遠」，不是「離別的屬性多遠」。
	# 第一版色板只要求兩兩距離，金（銀灰）離紙只有 0.58——實機上淡到幾乎看不見。
	var paper := Palette.paper()
	for element: String in Bullet.ELEMENT_COLORS:
		var color: Color = Bullet.ELEMENT_COLORS[element]
		assert_gt(
			Palette.distance(color, paper), 0.8,
			"%s 離紙只有 %.2f，會糊進紙裡" % [element, Palette.distance(color, paper)]
		)


func test_屬性著色不再調亮() -> void:
	# 深底時把顏色調亮是為了讓 glow 撿到它；在紙上調亮只會讓墨色變淡、糊進紙裡
	assert_almost_eq(HanziSprite.ELEMENT_GLOW_BOOST, 1.0, 0.001)


func test_主角走同一套色表() -> void:
	# ⚠️ 深底時期這裡踩過：主角用純白，而五行「金＝白」，於是與金屬性敵人撞色。
	# 走同一套色表就不會再犯。
	var player: Node2D = PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)

	var sprite := player.get_node(^"HanziSprite") as HanziSprite
	var color := sprite.get_theme_color(&"font_color")
	var expected: Color = Bullet.ELEMENT_COLORS["neutral"]

	assert_almost_eq(color.r / HanziSprite.ELEMENT_GLOW_BOOST, expected.r, 0.01)
	assert_almost_eq(color.g / HanziSprite.ELEMENT_GLOW_BOOST, expected.g, 0.01)
	assert_almost_eq(color.b / HanziSprite.ELEMENT_GLOW_BOOST, expected.b, 0.01)


func test_主角顏色與每一種五行色都拉得開() -> void:
	# 既有的 test_六種顏色兩兩之間有足夠差異 只管子彈的六個色，
	# 沒有把「主角字形」納入檢查——這次的撞色就是從這個縫隙漏出去的。
	# 門檻沿用同一個 0.45。
	var player: Node2D = PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)

	var sprite := player.get_node(^"HanziSprite") as HanziSprite
	var player_color := sprite.get_theme_color(&"font_color") / HanziSprite.ELEMENT_GLOW_BOOST

	for element: String in ["water", "fire", "metal", "wood", "earth"]:
		var enemy_color: Color = Bullet.ELEMENT_COLORS[element]
		var distance := Vector3(
			player_color.r - enemy_color.r,
			player_color.g - enemy_color.g,
			player_color.b - enemy_color.b
		).length()
		assert_gt(
			distance, 0.45,
			"主角與 %s 屬敵人的顏色距離只有 %.2f，畫面上會分不出來" % [element, distance]
		)


func test_訓練假人也要依屬性著色() -> void:
	# 假人 extends Character 而不是 Enemy，拿不到 Enemy._apply_data() 的著色。
	# 漏掉的話，同樣是火屬性，生成的「焰」是橙紅、假人「焰」卻是白的——
	# 比全部都白還糟，玩家會以為顏色代表別的意思。
	var dummy: Node2D = DummyScene.instantiate()
	dummy.element = "fire"
	dummy.display_char = "焰"
	add_child_autofree(dummy)
	await wait_physics_frames(1)

	var sprite := dummy.get_node(^"HanziSprite") as HanziSprite
	var color := sprite.get_theme_color(&"font_color")
	var expected: Color = Bullet.ELEMENT_COLORS["fire"]

	assert_almost_eq(color.r / HanziSprite.ELEMENT_GLOW_BOOST, expected.r, 0.01)
	assert_almost_eq(color.g / HanziSprite.ELEMENT_GLOW_BOOST, expected.g, 0.01)
	assert_almost_eq(color.b / HanziSprite.ELEMENT_GLOW_BOOST, expected.b, 0.01)


func test_場上每一種可攻擊目標都會著色() -> void:
	# 掃過所有 extends Character 的場景，確保沒有第三種「忘了上色」的角色。
	# 這次就是靠人工發現假人漏掉的——測試要能自己抓到才行。
	const SCENES := {
		"res://scenes/enemy_base.tscn": "enemy",
		"res://scenes/training_dummy.tscn": "dummy",
	}
	for path: String in SCENES:
		var scene := load(path) as PackedScene
		assert_not_null(scene, "載入失敗：%s" % path)
		var instance: Node2D = scene.instantiate()
		instance.element = "wood"
		add_child_autofree(instance)
		if instance.has_method(&"setup"):
			instance.call(&"setup", {
				"char": "樹", "element": "wood", "ai": "stationary_aoe",
				"hp": 30, "damage": 0, "speed": 0,
			})
		await wait_physics_frames(1)

		var sprite := instance.get_node(^"HanziSprite") as HanziSprite
		var color := sprite.get_theme_color(&"font_color")
		assert_almost_eq(
			color.g / HanziSprite.ELEMENT_GLOW_BOOST,
			float(Bullet.ELEMENT_COLORS["wood"].g), 0.01,
			"%s 沒有依屬性著色" % path
		)


func test_未知屬性退回白色而不是透明() -> void:
	var sprite := HanziSprite.new()
	add_child_autofree(sprite)
	sprite.set_element_color("no_such_element")

	var color := sprite.get_theme_color(&"font_color")
	assert_gt(color.a, 0.9, "查不到屬性時不可以變成看不見的字")


func test_主角是焦墨() -> void:
	# 主角是 neutral，紙上的 neutral 就是焦墨——全場最黑最實的一筆，
	# 一眼與彩墨畫的敵人分開
	var player: Node2D = PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)

	var color := (player.get_node(^"HanziSprite") as HanziSprite).get_theme_color(&"font_color")
	assert_lt(color.r + color.g + color.b, 0.5, "主角應該是最深的墨色")


func test_宣紙底不開glow() -> void:
	# ⚠️ 發光是為了讓亮色在深背景上跳出來。在紙上它只會把畫面糊成一片霧，
	# 而且 bloom 會把筆畫之間那道細分隔抹平——「字看著糊」的元凶之一就是它。
	var env_node: WorldEnvironment = EnvironmentScene.instantiate()
	add_child_autofree(env_node)

	assert_not_null(env_node.environment)
	assert_false(env_node.environment.glow_enabled, "宣紙底不該開 glow")


# ---- 打擊感 ----

func test_命中停頓結束後時間一定還原() -> void:
	# Engine.time_scale 是全域的，任何沒還原的路徑都會讓整個遊戲卡在慢動作
	var node := Node.new()
	add_child_autofree(node)

	await GameFeel.hit_stop(node, 0.02)

	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "停頓結束必須把時間還原")


func test_停頓期間確實放慢() -> void:
	var node := Node.new()
	add_child_autofree(node)

	GameFeel.hit_stop(node, 0.05)
	await wait_frames(1)

	assert_lt(Engine.time_scale, 1.0, "停頓期間應該處於慢動作")
	await wait_seconds(0.2)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001)


func test_停頓不會疊加() -> void:
	# 多個敵人同幀被打到時，不該疊成一次長停頓
	var node := Node.new()
	add_child_autofree(node)

	GameFeel.hit_stop(node, 0.05)
	GameFeel.hit_stop(node, 0.05)
	GameFeel.hit_stop(node, 0.05)
	await wait_seconds(0.25)

	assert_almost_eq(Engine.time_scale, 1.0, 0.001)


func test_關閉開關後不影響時間() -> void:
	var node := Node.new()
	add_child_autofree(node)

	GameFeel.enabled = false
	await GameFeel.hit_stop(node, 0.05)

	assert_almost_eq(Engine.time_scale, 1.0, 0.001)


func test_鏡頭震動會偏移並自動歸零() -> void:
	var player: Node2D = PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)

	var camera := player.get_node(^"Camera2D") as CameraBounds
	camera.shake(10.0, 0.1)
	camera._process(0.016)

	assert_ne(camera.offset, Vector2.ZERO, "震動期間鏡頭應該偏移")

	camera._process(0.2)
	assert_eq(camera.offset, Vector2.ZERO, "震動結束必須把 offset 歸零，否則鏡頭永遠歪著")


func test_連續震動取較強的而不是累加() -> void:
	# 累加的話一秒內打三下會震到畫面完全看不清
	var player: Node2D = PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)

	var camera := player.get_node(^"Camera2D") as CameraBounds
	camera.shake(4.0, 0.1)
	camera.shake(4.0, 0.1)
	camera.shake(4.0, 0.1)
	camera._process(0.016)

	assert_lt(camera.offset.length(), 4.0 * 2.0, "三次震動不該疊成三倍強度")
