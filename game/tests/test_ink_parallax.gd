## 水墨遠山視差背景
##
## 這裡最重要的一條是**授權**：遊戲要上 Steam 販售，素材授權出錯是會被下架的。
## 測試守著「每個背景素材都必須在 CREDITS.md 裡列明出處與授權」，
## 讓日後有人隨手丟一張圖進來時會被擋下。
extends GutTest

const BACKGROUND_DIR := "res://assets/backgrounds"
const CREDITS_PATH := "res://assets/backgrounds/CREDITS.md"


func test_每個背景素材都在CREDITS裡列明授權() -> void:
	var file := FileAccess.open(CREDITS_PATH, FileAccess.READ)
	assert_not_null(file, "缺少 CREDITS.md——背景素材必須有授權出處")
	if file == null:
		return
	var credits := file.get_as_text()

	var dir := DirAccess.open(BACKGROUND_DIR)
	assert_not_null(dir)
	if dir == null:
		return

	var found := 0
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap").trim_suffix(".import")
		if clean.get_extension().to_lower() not in ["jpg", "jpeg", "png", "webp"]:
			continue
		found += 1
		assert_true(
			credits.contains(clean),
			"「%s」沒有在 CREDITS.md 裡列明出處與授權——不可以隨手丟圖進來" % clean
		)
	assert_gt(found, 0, "背景目錄是空的")


func test_CREDITS標明是公有領域可商用() -> void:
	var file := FileAccess.open(CREDITS_PATH, FileAccess.READ)
	if file == null:
		return
	var credits := file.get_as_text()
	assert_true(
		credits.contains("CC0") or credits.contains("Public Domain"),
		"授權必須明確標示；『看起來很老應該沒問題』不是授權"
	)


func test_遠景素材載得起來() -> void:
	var texture: Texture2D = load(InkParallax.SCROLL_PATH)
	assert_not_null(texture, "載不到遠景手卷")
	if texture == null:
		return
	assert_gt(
		float(texture.get_width()) / float(texture.get_height()), 1.5,
		"側向卷軸需要橫向構圖；立軸與扇面的比例不合用"
	)


func test_遠景壓得夠淡() -> void:
	# 畫面上其他所有東西都是程序化生成的筆畫。真跡掃描不壓淡就會變成
	# 「字是畫的、背景是照片」，而且會與前景的字搶視線。
	var parallax := InkParallax.new()
	add_child_autofree(parallax)
	await wait_physics_frames(1)

	assert_gt(parallax.wash, 0.6, "遠景要壓得夠淡才像宣紙上本來就有的淡墨")
	assert_lt(parallax.distance_scale, 0.4, "遠景跟鏡頭跑太快就不像遠景")


func test_只取手卷上半段() -> void:
	# 手卷下半是近景的樹石，筆觸密而深，整張貼上去會與前景的字打架
	var parallax := InkParallax.new()
	add_child_autofree(parallax)
	await wait_physics_frames(1)

	assert_lt(parallax.top_fraction, 1.0, "應該只取上半的遠山")

	var sprite: Sprite2D = null
	for child: Node in parallax.get_children():
		if child is Sprite2D:
			sprite = child as Sprite2D
			break
	assert_not_null(sprite)
	if sprite != null:
		assert_true(sprite.region_enabled, "沒開 region 就是整張貼上去")


func test_遠景要超額覆蓋視口() -> void:
	# ⚠️ 縮放與位置一律由視口算出來，不要手填數字。
	# 手調的結果就是「在我的解析度上剛好，換一台機器就露白」。
	# 而且鏡頭會跟著玩家上下移動，遠景的垂直視差比例很小、幾乎不跟著跑——
	# 只鋪滿一個視口的話，玩家一跳起來畫面下緣就會露出空白的紙。
	var parallax := InkParallax.new()
	add_child_autofree(parallax)
	await wait_physics_frames(1)

	assert_gt(parallax.coverage, 1.0, "遠景必須鋪得比視口大，否則鏡頭一動就露白")

	var sprite: Sprite2D = null
	for child: Node in parallax.get_children():
		if child is Sprite2D:
			sprite = child as Sprite2D
			break
	assert_not_null(sprite)
	if sprite == null:
		return

	var painted_height := sprite.region_rect.size.y * sprite.scale.y
	assert_gt(
		painted_height, parallax.get_viewport_rect().size.y,
		"遠景畫出來的高度要大於視口高度"
	)


func test_用Parallax2D而不是舊的ParallaxBackground() -> void:
	# ⚠️ ParallaxBackground 是 CanvasLayer，預設 layer = -100，
	# 會被場景裡那張不透明的紙色 ColorRect 整個蓋住，畫面上完全看不到。
	var parallax := InkParallax.new()
	add_child_autofree(parallax)

	# 型別檢查在編譯期就能定案，所以直接比對基底類別名稱
	assert_true(parallax is Parallax2D)
	assert_eq(
		parallax.get_class(), "Parallax2D",
		"必須是 Node2D 系的 Parallax2D；CanvasLayer 版的 ParallaxBackground 會被紙底蓋住"
	)
