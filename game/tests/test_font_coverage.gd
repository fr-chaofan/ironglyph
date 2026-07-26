## 字型字形涵蓋檢查
##
## 專案用的是 Noto Sans TC 的**繁中子集版**（5.6MB，非17MB全CJK版）。
## 子集版少了一些罕用字符——例如金部的偏旁形「釒」(U+91D2)就不在裡面。
## 缺字形時 Godot 不會報錯，只會畫出一個空的豆腐方框，很容易到了實機才發現。
##
## 這裡把所有會被顯示出來的字都掃一遍，讓缺字形在CI就擋下來。
extends GutTest

const FONT_PATH := "res://assets/fonts/NotoSansTC-Bold.otf"

var _font: FontFile


func before_all() -> void:
	_font = load(FONT_PATH)


func test_字型檔載入成功() -> void:
	assert_not_null(_font, "應能載入 %s" % FONT_PATH)


func test_全部敵字與主角字都有字形() -> void:
	for ch: String in HanziData.get_all_characters():
		assert_true(_font.has_char(ch.unicode_at(0)), "字型缺「%s」的字形，會顯示成豆腐方框" % ch)


func test_全部武器部首都有字形() -> void:
	# 「釒」(U+91D2) 曾因為子集版字型沒有收錄而顯示成豆腐，改用「金」(U+91D1)
	var wm: WeaponManager = WeaponManager.new()
	add_child_autofree(wm)
	wm.load_weapons()

	for w: Dictionary in wm.weapons:
		var radical: String = w.get("radical", "")
		assert_false(radical.is_empty(), "武器 %s 沒有部首" % w.get("id", "?"))
		for i in radical.length():
			assert_true(
				_font.has_char(radical.unicode_at(i)),
				"武器 %s 的部首「%s」在字型裡沒有字形" % [w.get("id", "?"), radical]
			)


func test_部首不可為簡體字() -> void:
	# GDD 第0節：全專案文字一律繁體。「钅」(U+9485) 是「釒」的簡體形，
	# 它剛好在字型裡有字形，所以不會顯示成豆腐——只會安靜地變成簡體。
	const SIMPLIFIED_RADICALS := ["钅", "讠", "饣", "纟", "贝", "车", "门", "马"]
	var wm: WeaponManager = WeaponManager.new()
	add_child_autofree(wm)
	wm.load_weapons()

	for w: Dictionary in wm.weapons:
		assert_does_not_have(
			SIMPLIFIED_RADICALS, w.get("radical", ""),
			"武器 %s 的部首是簡體字，違反 GDD 第0節語言規範" % w.get("id", "?")
		)
