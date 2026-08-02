## 水墨遠山視差背景。
##
## 用公有領域的古代山水手卷當遠景（授權見 `assets/backgrounds/CREDITS.md`）。
## 手卷本來就是「一段一段往右展開」的觀看方式，與橫向捲動的視差背景是同一個道理。
##
## ⚠️ **關鍵是要壓得夠淡。** 畫面上其他所有東西都是程序化生成的筆畫，
## 直接貼一張真跡掃描進去會變成「字是畫的、背景是照片」。往紙色化開之後
## 它讀起來就是宣紙上本來就有的淡墨遠山，而不是一張貼圖。
## ⚠️ 用 `Parallax2D`（Godot 4.3 起）而不是舊的 `ParallaxBackground`。
## 後者是 `CanvasLayer`，預設 `layer = -100`——會被場景裡那張不透明的紙色
## `ColorRect` 整個蓋住，畫面上完全看不到。`Parallax2D` 是 `Node2D`，
## 正常參與樹順序與 z_index，擺在紙底之上、其他一切之下即可。
class_name InkParallax
extends Parallax2D

const SCROLL_PATH := "res://assets/backgrounds/liuyu-landscape-1680.jpg"

## 遠景相對於鏡頭的移動比例。越小顯得越遠。
@export_range(0.0, 1.0, 0.01) var distance_scale: float = 0.18
## 遠山往紙色化開的程度。1.0 = 完全變成紙（看不見）。
@export_range(0.0, 1.0, 0.01) var wash: float = 0.80
## 取手卷的上面多少當遠景。
##
## ⚠️ 手卷最下緣是近景的樹石，筆觸密而深，貼上來會與前景的字打架。
## 但取太少又會鋪不滿畫面——0.78 是「夠鋪滿、又切掉最吵那一段」的折衷。
@export_range(0.2, 1.0, 0.02) var top_fraction: float = 0.78

## 遠景要蓋住幾倍的視口高度。
##
## ⚠️ 要大於 1：鏡頭會跟著玩家上下移動，而遠景的垂直視差比例很小、幾乎不跟著跑。
## 只鋪滿一個視口的話，玩家一跳起來畫面下緣就會露出空白的紙。
@export_range(1.0, 3.0, 0.05) var coverage: float = 2.2

## 垂直微調。正值往下。
@export var vertical_bias: float = 190.0

var _sprite: Sprite2D


func _ready() -> void:
	var texture: Texture2D = load(SCROLL_PATH)
	if texture == null:
		push_warning("InkParallax: 載不到 %s" % SCROLL_PATH)
		return

	# ⚠️ 縮放與位置一律由視口算出來，不要手填數字。
	# 手調的結果就是「在我的解析度上剛好，換一台機器就露白」——
	# 而且每次微調都得重跑一次才知道對不對。
	var cropped_height := texture.get_height() * top_fraction
	var target_height := get_viewport_rect().size.y * coverage
	var fitted_scale := target_height / cropped_height

	scroll_scale = Vector2(distance_scale, distance_scale * 0.5)
	# 水平無限重複，玩家往哪邊走都不會走到畫的盡頭
	repeat_size = Vector2(texture.get_width() * fitted_scale, 0.0)
	repeat_times = 3

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.centered = false
	# 切掉最下緣筆觸最密的近景
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0.0, 0.0, texture.get_width(), cropped_height)
	_sprite.scale = Vector2.ONE * fitted_scale
	# 以視口中心為基準往上鋪，讓遠景橫跨整個可見範圍
	_sprite.position = Vector2(0.0, -target_height * 0.5 + vertical_bias)
	# 往紙色化開：alpha 讓紙透上來，modulate 再把殘餘的墨壓向紙的色溫
	_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0 - wash).lerp(
		Color(Palette.paper().r, Palette.paper().g, Palette.paper().b, 1.0 - wash), 0.35
	)
	add_child(_sprite)
