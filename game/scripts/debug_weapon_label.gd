## 臨時debug顯示：目前的兩個攻擊動詞（Task 2.3 Verify 用，Task 2.7b 擴充）
##
## 正式HUD在階段六 Task 6.1 實作，屆時這支腳本與 test_room.tscn 一起刪除。
##
## ⚠️ **必須同時顯示 J 與 K。** Task 2.7a 起「刂・近戰刀」按 J 會退回基礎弓，
## 只顯示 `WeaponManager.active_weapon` 的話，標籤會寫著「近戰刀 傷害14」
## 但玩家實際打出去的是 7 傷的弓箭——讀數與實際行為對不上，
## 手動驗證時會把這種落差誤判成傷害計算的 bug。
extends Label

## 指向 Player 底下的 WeaponManager
@export var weapon_manager_path: NodePath
## 指向 Player 底下的 MeleeAttack（沒有 GlyphLoadout 時的退路）
@export var melee_attack_path: NodePath
## 指向 Player 底下的 GlyphLoadout。Task 2.7c 起它才是 J/K 分派的真相源。
@export var glyph_loadout_path: NodePath

var _weapon_manager: Node
var _melee_attack: MeleeAttack
var _glyph_loadout: Node


func _ready() -> void:
	_weapon_manager = get_node_or_null(weapon_manager_path)
	_melee_attack = get_node_or_null(melee_attack_path) as MeleeAttack
	_glyph_loadout = get_node_or_null(glyph_loadout_path)

	if _weapon_manager == null:
		text = "（找不到 WeaponManager）"
		return

	_weapon_manager.weapon_changed.connect(_on_weapon_changed)
	if _glyph_loadout != null and _glyph_loadout.has_signal(&"loadout_changed"):
		_glyph_loadout.connect(&"loadout_changed", _on_loadout_changed)
	_refresh()


func _on_loadout_changed(_snapshot: Dictionary) -> void:
	_refresh()


func _on_weapon_changed(_weapon: Dictionary, _index: int) -> void:
	_refresh()


func _refresh() -> void:
	text = "%s\n%s" % [_ranged_text(), _melee_text()]


func _ranged_text() -> String:
	var weapon: Dictionary = _weapon_manager.get_current_weapon()
	if weapon.is_empty():
		return "J 遠程：（無）"

	# 近戰型武器按 J 會退回基礎弓，標籤要跟著顯示真正打出去的東西
	if String(weapon.get("attack_type", "projectile")) == "melee":
		var fallback: Dictionary = _weapon_manager.get_weapon_by_id(
			WeaponManager.CORE_RANGED_WEAPON_ID
		)
		if not fallback.is_empty():
			return "J 遠程：%s（手持%s，退回基礎攻擊）" % [
				_describe(fallback), weapon.get("radical", ""),
			]

	return "J 遠程：%s" % _describe(weapon)


func _melee_text() -> String:
	# Task 2.7c 起近戰 profile 由裝備狀態分派（手持「刂」是刀刃筆擊），
	# 讀 MeleeAttack 的預設 profile_id 只會永遠顯示令筆擊
	var profile: Dictionary = {}
	if _glyph_loadout != null and _glyph_loadout.has_method(&"get_melee_profile"):
		profile = _glyph_loadout.call(&"get_melee_profile")
	elif _melee_attack != null:
		profile = MeleeAttack.get_profile(_melee_attack.profile_id)

	if profile.is_empty():
		return "K 近戰：（無 profile）"
	return "K 近戰：%s" % _describe(profile)


func _describe(attack: Dictionary) -> String:
	return "%s%s　%s屬　傷害%d" % [
		attack.get("radical", attack.get("glyph", "")),
		attack.get("name", ""),
		attack.get("element", "neutral"),
		int(attack.get("damage", 0)),
	]
