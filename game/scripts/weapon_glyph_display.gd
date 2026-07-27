## 玩家目前武器的場景內字形顯示（Task 2.5）。
##
## 掛在 Player 底下，透過改變自身的位置跟隨朝向。字形本身永遠維持正向，
## 不用負的 scale.x 鏡像，避免偏旁或完整漢字變成無法辨識的反字。
class_name WeaponGlyphDisplay
extends Node2D

## WeaponManager 相對於本節點的位置。
@export var weapon_manager_path: NodePath = ^"../WeaponManager"

## 面向右側時的顯示偏移；面向左側時只反轉 x。
@export var side_offset: Vector2 = Vector2(56.0, -8.0)

## 切換武器時的淡入／彈出時長。
@export_range(0.0, 1.0, 0.01) var switch_duration: float = 0.12

@onready var _glyph: Label = get_node_or_null(^"Glyph") as Label

var _weapon_manager: WeaponManager
var _switch_tween: Tween
var _owner_dead: bool = false


func _ready() -> void:
	var parent_node := get_parent()
	set_facing(_get_facing_from(parent_node))
	_connect_owner_death(parent_node)

	# 先清空，避免場景裡的 placeholder 在資料尚未載入時閃一下。
	set_weapon({})

	_weapon_manager = get_node_or_null(weapon_manager_path) as WeaponManager
	if _weapon_manager == null:
		return

	if not _weapon_manager.weapon_changed.is_connected(_on_weapon_changed):
		_weapon_manager.weapon_changed.connect(_on_weapon_changed)

	# WeaponManager 可能早於本節點完成 _ready() 並已送出初始 signal；
	# 主動同步一次，不能只依賴 weapon_changed。
	set_weapon(_weapon_manager.get_current_weapon())


## 更新目前武器。display_glyph 是未來組字系統的顯示結果；
## 尚未提供時回退到現有武器資料的 radical。
func set_weapon(weapon: Dictionary) -> void:
	if _glyph == null or _owner_dead or weapon.is_empty():
		_clear_display()
		return

	var glyph_text := String(weapon.get("display_glyph", "")).strip_edges()
	if glyph_text.is_empty():
		glyph_text = String(weapon.get("radical", "")).strip_edges()
	if glyph_text.is_empty():
		_clear_display()
		return

	var element := String(weapon.get("element", "neutral"))
	var element_color: Color = Bullet.ELEMENT_COLORS.get(element, Color.WHITE)

	_kill_switch_tween()
	show()
	_glyph.text = glyph_text

	if switch_duration <= 0.0:
		scale = Vector2.ONE
		_glyph.modulate = element_color
		return

	# 每次切換都從相同狀態開始。快速連按時舊 tween 會先被取消，
	# 因此不會累積縮放或把透明度卡在中間值。
	scale = Vector2.ONE * 0.82
	_glyph.modulate = Color(
		element_color.r,
		element_color.g,
		element_color.b,
		0.35
	)
	_switch_tween = create_tween()
	_switch_tween.set_parallel(true)
	_switch_tween.set_trans(Tween.TRANS_BACK)
	_switch_tween.set_ease(Tween.EASE_OUT)
	_switch_tween.tween_property(self, "scale", Vector2.ONE, switch_duration)
	_switch_tween.tween_property(_glyph, "modulate", element_color, switch_duration)


## 移到玩家面向的一側。只改位置，不以負 scale 鏡像字形。
func set_facing(direction: float) -> void:
	var facing := signf(direction)
	if is_zero_approx(facing):
		facing = 1.0

	position = Vector2(absf(side_offset.x) * facing, side_offset.y)
	scale = Vector2(absf(scale.x), absf(scale.y))


func _on_weapon_changed(weapon: Dictionary, _index: int) -> void:
	set_weapon(weapon)


func _on_owner_died() -> void:
	_owner_dead = true
	_clear_display()


func _clear_display() -> void:
	_kill_switch_tween()
	scale = Vector2.ONE
	if _glyph != null:
		_glyph.text = ""
		_glyph.modulate = Color.WHITE
	hide()


func _kill_switch_tween() -> void:
	if _switch_tween != null and _switch_tween.is_valid():
		_switch_tween.kill()
	_switch_tween = null
	scale = Vector2(absf(scale.x), absf(scale.y))


func _connect_owner_death(parent_node: Node) -> void:
	if parent_node == null or not parent_node.has_signal(&"died"):
		return

	var callback := Callable(self, "_on_owner_died")
	if not parent_node.is_connected(&"died", callback):
		parent_node.connect(&"died", callback)


func _get_facing_from(parent_node: Node) -> float:
	if parent_node == null:
		return 1.0

	# Object.get() 對不存在的 property 會報錯；先查 property list，
	# 讓此元件被單獨測試或暫時掛到其他 Node 底下時也能安全退回向右。
	for property in parent_node.get_property_list():
		if property.get("name", &"") != &"facing_dir":
			continue
		var value: Variant = parent_node.get(&"facing_dir")
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			return float(value)
		break
	return 1.0
