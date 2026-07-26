## HanziData 單例的煙霧測試（Task 1.2）
##
## 驗證資料檔確實被載入、getter回傳正確型別、缺字時安全回傳空值。
extends GutTest


func test_singleton_已載入資料() -> void:
	assert_not_null(HanziData, "HanziData autoload 應該存在")
	assert_gt(HanziData.data.size(), 0, "應載入至少一個字")


func test_收錄字數為23() -> void:
	# 字表共23字，全部在Make Me a Hanzi中找到（見 tools/build_hanzi_data.py）
	assert_eq(HanziData.data.size(), 23, "應收錄23字")


func test_焚已取代查無的燄() -> void:
	# 「燄」是「焰」的異體字，資料集未收錄，改用同屬火的「焚」
	assert_false(HanziData.has_character("燄"), "「燄」應已從字表移除")
	assert_true(HanziData.has_character("焚"), "「焚」應已納入字表")
	# 「焚」拆解出的「林」本身也是木屬性敵字，部首武器機制可跨屬性互動
	assert_eq(HanziData.get_decomposition("焚"), "⿱林火")
	assert_true(HanziData.has_character("林"), "「焚」拆解出的「林」應同樣有資料")


func test_get_strokes_回傳非空陣列() -> void:
	var strokes: Array = HanziData.get_strokes("淼")
	assert_gt(strokes.size(), 0, "「淼」應有筆畫資料")
	assert_typeof(strokes[0], TYPE_STRING, "每一筆畫應為SVG path字串")


func test_get_decomposition_回傳IDS字串() -> void:
	# 實際值來自資料集，不是人工編造
	assert_eq(HanziData.get_decomposition("河"), "⿰氵可")
	assert_eq(HanziData.get_decomposition("淼"), "⿱水⿰水水")


func test_decomposition_不含自我循環() -> void:
	# 防止資料出現「X 拆解為含 X 自身」這種無法終止的定義
	for ch: String in HanziData.get_all_characters():
		var decomp: String = HanziData.get_decomposition(ch)
		assert_false(decomp.contains(ch), "「%s」的拆解式不應包含自己：%s" % [ch, decomp])


func test_get_radical() -> void:
	assert_eq(HanziData.get_radical("河"), "氵")
	assert_eq(HanziData.get_radical("巖"), "山")


func test_medians_筆數與strokes一致() -> void:
	for ch: String in HanziData.get_all_characters():
		assert_eq(
			HanziData.get_medians(ch).size(),
			HanziData.get_strokes(ch).size(),
			"「%s」的medians筆數應與strokes一致" % ch
		)


func test_缺字安全回傳空值() -> void:
	# 「燄」是已從字表移除的字；「𰻞」是資料集不可能有的字
	for ch: String in ["燄", "𰻞"]:
		assert_false(HanziData.has_character(ch), "「%s」不應被收錄" % ch)
		assert_eq(HanziData.get_strokes(ch), [], "缺字的strokes應為空陣列")
		assert_eq(HanziData.get_medians(ch), [], "缺字的medians應為空陣列")
		assert_eq(HanziData.get_decomposition(ch), "", "缺字的decomposition應為空字串")
		assert_eq(HanziData.get_radical(ch), "", "缺字的radical應為空字串")
