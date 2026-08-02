## 武器管理器（Task 2.3）
##
## 掛在 Player 底下。weapons.json 是攻擊 profile catalog；
## Task 2.6 起由 GlyphLoadout 指定唯一的 active_weapon，不再讓玩家 Q/E 輪換整個 catalog。
class_name WeaponManager
extends Node

signal weapon_changed(weapon: Dictionary, index: int)

const DATA_PATH := "res://data/weapons.json"
## 沒有遠程可用時退回的基礎攻擊（見 _resolve_ranged_weapon）
const CORE_RANGED_WEAPON_ID := "gong"
const BULLET_SCENE := preload("res://scenes/projectiles/bullet_base.tscn")

## 子彈生成點相對於角色中心的偏移，避免一出生就卡在自己的碰撞體裡
@export var muzzle_offset: Vector2 = Vector2(36, 0)

var weapons: Array = []
## 僅保留給舊 debug UI／測試辨識 catalog 位置；它不再代表玩家持有十格 inventory。
var current_index: int = -1
var active_weapon: Dictionary = {}
var cooldown: float = 0.0


func _ready() -> void:
	load_weapons()


func load_weapons() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("WeaponManager: 無法開啟 %s（錯誤碼 %d）" % [DATA_PATH, FileAccess.get_open_error()])
		return

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()

	if typeof(parsed) != TYPE_ARRAY:
		push_error("WeaponManager: %s 解析失敗，應為陣列" % DATA_PATH)
		return

	weapons = parsed.duplicate(true)

	# CORE 必須有能力打倒第一隻敵人取得部件；現有中性「弓」作為基礎攻擊。
	if active_weapon.is_empty():
		set_active_weapon_by_id("gong")
	else:
		current_index = _find_weapon_index(String(active_weapon.get("id", "")))
		weapon_changed.emit(get_current_weapon(), current_index)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)


## 舊的程式化 debug API 保留相容性，但 gameplay input 不再呼叫它。
func cycle_weapon(step: int) -> void:
	if weapons.is_empty():
		return  # 沒有武器時取模會除以零
	var start_index := current_index if current_index >= 0 else 0
	var next_index := posmod(start_index + step, weapons.size())
	set_active_weapon(weapons[next_index])


func get_current_weapon() -> Dictionary:
	return active_weapon.duplicate(true)


func get_weapon_by_id(weapon_id: String) -> Dictionary:
	var index := _find_weapon_index(weapon_id)
	if index < 0:
		return {}
	return (weapons[index] as Dictionary).duplicate(true)


func set_active_weapon(weapon: Dictionary) -> bool:
	active_weapon = weapon.duplicate(true)
	current_index = _find_weapon_index(String(active_weapon.get("id", "")))
	weapon_changed.emit(get_current_weapon(), current_index)
	return not active_weapon.is_empty()


func set_active_weapon_by_id(weapon_id: String) -> bool:
	var weapon := get_weapon_by_id(weapon_id)
	if weapon.is_empty():
		set_active_weapon({})
		return false
	return set_active_weapon(weapon)


func can_fire() -> bool:
	return cooldown <= 0.0 and not active_weapon.is_empty()


## direction 由呼叫方傳入（Player 的 facing_dir），不從節點 scale 推導——
## 漢字本體不翻轉，scale 讀不出朝向。
func fire(direction: float = 1.0) -> void:
	if not can_fire():
		return

	var weapon: Dictionary = _resolve_ranged_weapon()
	if weapon.is_empty():
		return
	cooldown = float(weapon.get("fire_rate", 0.5))

	var dir := Vector2(signf(direction) if not is_zero_approx(direction) else 1.0, 0.0)
	# 本身是 Node（沒有 global_position），生成點取自父節點的角色
	var origin: Node2D = get_parent() as Node2D
	var center: Vector2 = Vector2.ZERO if origin == null else origin.global_position

	if String(weapon.get("pattern", "single")) == "radial":
		var projectile_count := clampi(int(weapon.get("projectile_count", 1)), 1, 64)
		for index in projectile_count:
			var radial_dir := Vector2.RIGHT.rotated(TAU * float(index) / float(projectile_count))
			_spawn_bullet(weapon, center, radial_dir)
		return

	var spawn_pos := center + Vector2(muzzle_offset.x * dir.x, muzzle_offset.y)
	_spawn_bullet(weapon, spawn_pos, dir)


## J（遠程）永遠不會把近戰武器當投射物丟出去。
##
## `weapons.json` 的「刂・近戰刀」標著 `attack_type: melee`，Task 2.7a 之前它會生成一把
## **飛出去的刀**。現在改為退回 CORE 基礎弓——這正是 `docs/COMBAT.md` 3.2 節定案的
## 「HELD・近戰類 → J 退回基礎弓」行為。
##
## ⚠️ Task 2.7c 會把這個決策移到 `GlyphLoadout.get_ranged_profile()`，
## 由裝備狀態的唯一真相源統一分派 J/K；此處是在近戰系統上線前的過渡實作。
func _resolve_ranged_weapon() -> Dictionary:
	var weapon: Dictionary = get_current_weapon()
	if String(weapon.get("attack_type", "projectile")) != "melee":
		return weapon

	var fallback := get_weapon_by_id(CORE_RANGED_WEAPON_ID)
	if fallback.is_empty():
		push_warning("WeaponManager: 近戰武器無法退回基礎弓「%s」" % CORE_RANGED_WEAPON_ID)
	return fallback


func _spawn_bullet(weapon: Dictionary, spawn_pos: Vector2, direction: Vector2) -> Bullet:
	var bullet: Bullet = BULLET_SCENE.instantiate()

	# 掛在關卡根節點而非 Player 底下——掛在 Player 底下的話，子彈會跟著角色移動，
	# 且角色死亡 queue_free 時會把空中的子彈一起帶走。
	_get_projectile_parent().add_child(bullet)
	bullet.set_range(String(weapon.get("range", "")))
	bullet.setup(
		int(weapon.get("damage", 0)),
		String(weapon.get("element", "neutral")),
		spawn_pos,
		direction
	)
	return bullet


func _get_projectile_parent() -> Node:
	# current_scene 在單元測試環境可能是 null，退回場景樹根節點
	var scene := get_tree().current_scene
	return scene if scene != null else get_tree().root


func _find_weapon_index(weapon_id: String) -> int:
	var normalized_id := weapon_id.strip_edges()
	if normalized_id.is_empty():
		return -1
	for index in weapons.size():
		var weapon: Dictionary = weapons[index]
		if String(weapon.get("id", "")).strip_edges() == normalized_id:
			return index
	return -1
