## 玩家目前武器的場景內字形顯示（Task 2.5）。
##
## 掛在 Player 底下，透過改變自身的位置跟隨朝向。字形本身永遠維持正向，
## 不用負的 scale.x 鏡像，避免偏旁或完整漢字變成無法辨識的反字。
class_name WeaponGlyphDisplay
extends Node2D

## WeaponManager 相對於本節點的位置。
@export var weapon_manager_path: NodePath = ^"../WeaponManager"
## Task 2.6 的單槽裝備狀態；存在時優先於 legacy WeaponManager signal。
@export var glyph_loadout_path: NodePath = ^"../GlyphLoadout"

## 面向右側時的顯示偏移；面向左側時只反轉 x。
@export var side_offset: Vector2 = Vector2(56.0, -8.0)

## 切換武器時的淡入／彈出時長。
@export_range(0.0, 1.0, 0.01) var switch_duration: float = 0.12

@onready var _glyph: Label = get_node_or_null(^"Glyph") as Label

var _weapon_manager: WeaponManager
var _glyph_loadout: Node
var _switch_tween: Tween
var _owner_dead: bool = false


func _ready() -> void:
	# 手持的部件與拾取物用同一套視覺處理，玩家才不必學兩次
	if _glyph != null:
		ComponentGlyph.wrap(_glyph, _glyph.get_theme_font_size(&"font_size"))

	var parent_node := get_parent()
	set_facing(_get_facing_from(parent_node))
	_connect_owner_death(parent_node)

	# 先清空，避免場景裡的 placeholder 在資料尚未載入時閃一下。
	set_weapon({})

	_glyph_loadout = get_node_or_null(glyph_loadout_path)
	if (
		_glyph_loadout != null
		and _glyph_loadout.has_signal(&"loadout_changed")
		and _glyph_loadout.has_method(&"get_snapshot")
	):
		var callback := Callable(self, "_on_loadout_changed")
		if not _glyph_loadout.is_connected(&"loadout_changed", callback):
			_glyph_loadout.connect(&"loadout_changed", callback)
		# 不依賴節點 ready 順序：Loadout 若尚未 ready，預設 snapshot 也是安全的 CORE。
		set_loadout_snapshot(_glyph_loadout.call(&"get_snapshot"))
		return
	_glyph_loadout = null

	# 沒有 GlyphLoadout 的舊場景／元件測試才回退到 Task 2.5 行為。
	_weapon_manager = get_node_or_null(weapon_manager_path) as WeaponManager
	if _weapon_manager == null:
		return

	if not _weapon_manager.weapon_changed.is_connected(_on_weapon_changed):
		_weapon_manager.weapon_changed.connect(_on_weapon_changed)

	# WeaponManager 可能早於本節點完成 _ready() 並已送出初始 signal；
	# 主動同步一次，不能只依賴 weapon_changed。
	set_weapon(_weapon_manager.get_current_weapon())


## 更新外置武器顯示。Task 2.6 的融合完整字顯示在主 HanziSprite，
## 此處的 display_glyph 僅表示 HELD 部件。
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
	# 淡墨：與拾取物同一套處理，玩家不必學兩次
	var element_color: Color = ComponentGlyph.wash(
		Bullet.ELEMENT_COLORS.get(element, Color.WHITE)
	)

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


func _on_loadout_changed(snapshot: Dictionary) -> void:
	set_loadout_snapshot(snapshot)


func set_loadout_snapshot(snapshot: Dictionary) -> void:
	if String(snapshot.get("mode", "core")) != "held":
		set_weapon({})
		return

	var value: Variant = snapshot.get("external_weapon", {})
	if typeof(value) != TYPE_DICTIONARY:
		set_weapon({})
		return
	var external_weapon: Dictionary = value
	set_weapon(external_weapon.duplicate(true))


func _on_owner_died() -> void:
	_owner_dead = true
	_clear_display()


## 玩家復活時呼叫，讓字形能重新顯示。
##
## `_owner_dead` 一旦設起來就沒有東西會清掉它，玩家從存檔點復活後武器字形會
## 永遠隱藏。階段四 Task 4.1 的存檔點是第一個會觸發復活的地方，在那之前這是
## 摸不到的潛在問題，但屆時沒有這個方法就會變成真的bug。
func revive() -> void:
	_owner_dead = false
	if _glyph_loadout != null and is_instance_valid(_glyph_loadout):
		set_loadout_snapshot(_glyph_loadout.call(&"get_snapshot"))
		return
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		set_weapon(_weapon_manager.get_current_weapon())


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
