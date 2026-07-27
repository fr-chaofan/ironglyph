## 臨時debug顯示：目前武器名稱與屬性（Task 2.3 Verify 用）
##
## 正式HUD在階段六 Task 6.1 實作，屆時這支腳本與 test_room.tscn 一起刪除。
extends Label

## 指向 Player 底下的 WeaponManager
@export var weapon_manager_path: NodePath


func _ready() -> void:
	var wm := get_node_or_null(weapon_manager_path)
	if wm == null:
		text = "（找不到 WeaponManager）"
		return

	wm.weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(wm.get_current_weapon(), wm.current_index)


func _on_weapon_changed(weapon: Dictionary, _index: int) -> void:
	if weapon.is_empty():
		text = "（無武器）"
		return
	text = "%s %s　%s屬　傷害%d" % [
		weapon.get("radical", ""),
		weapon.get("name", ""),
		weapon.get("element", ""),
		int(weapon.get("damage", 0)),
	]
