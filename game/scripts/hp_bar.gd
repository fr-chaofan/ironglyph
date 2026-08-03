## 血量顯示（墨條 ＋ 數字）。
##
## 在此之前畫面上**完全看不到自己的血**——HUD 有武器與環境資訊，唯獨沒有血量。
## 玩家只能靠受擊閃紅猜自己還剩多少，實機測試時根本無從判斷該不該撤退。
##
## 正式 HUD 在階段六 Task 6.1 實作，屆時樣式會併進去統一管理；
## 這支腳本的職責很窄：綁一個 Character，把 hp_changed 畫出來。
class_name HpBar
extends Control

## 低於這個比例就進入危險狀態（變色並脈動）
const DANGER_RATIO := 0.3

@export var target_path: NodePath
@export var bar_size: Vector2 = Vector2(260.0, 18.0)

var _target: Character
var _ratio: float = 1.0
var _danger_tween: Tween
var _label: Label


func _ready() -> void:
	custom_minimum_size = bar_size + Vector2(0.0, 24.0)

	_label = Label.new()
	_label.add_theme_font_override(&"font", load("res://assets/fonts/LXGWWenKaiTC-Regular.ttf"))
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_color", Palette.ink())
	_label.add_theme_color_override(&"font_outline_color", Palette.paper())
	_label.add_theme_constant_override(&"outline_size", 4)
	_label.position = Vector2(0.0, bar_size.y + 2.0)
	_label.size = Vector2(bar_size.x, 22.0)
	add_child(_label)

	_target = get_node_or_null(target_path) as Character
	if _target == null:
		_label.text = "（找不到角色）"
		return

	_target.hp_changed.connect(_on_hp_changed)
	_on_hp_changed(_target.hp, _target.max_hp)


func _on_hp_changed(current: int, maximum: int) -> void:
	_ratio = 0.0 if maximum <= 0 else clampf(float(current) / float(maximum), 0.0, 1.0)
	_label.text = "血　%d / %d" % [current, maximum]
	queue_redraw()

	# 危險時脈動。⚠️ 每次血量變動都重建 tween 的話會越疊越快，先 kill 再建。
	if _danger_tween != null and _danger_tween.is_valid():
		_danger_tween.kill()
	modulate.a = 1.0
	if _ratio > 0.0 and _ratio <= DANGER_RATIO:
		_danger_tween = create_tween().set_loops()
		_danger_tween.tween_property(self, "modulate:a", 0.45, 0.35)
		_danger_tween.tween_property(self, "modulate:a", 1.0, 0.35)


## 墨條：外框是墨線，填色由血量比例決定。
func _draw() -> void:
	var ink := Palette.ink()
	var rect := Rect2(Vector2.ZERO, bar_size)

	# 底：紙色，讓空的部分看起來是留白而不是黑洞
	draw_rect(rect, Palette.paper(), true)

	if _ratio > 0.0:
		var fill_color := Palette.element("fire") if _ratio <= DANGER_RATIO else ink
		draw_rect(Rect2(Vector2.ZERO, Vector2(bar_size.x * _ratio, bar_size.y)), fill_color, true)

	draw_rect(rect, ink, false, 2.0)
