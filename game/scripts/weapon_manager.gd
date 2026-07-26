## 武器管理器（Task 2.3）
##
## 掛在 Player 底下。讀 weapons.json，Q/E 切換，開火時生成子彈。
class_name WeaponManager
extends Node

signal weapon_changed(weapon: Dictionary, index: int)

const DATA_PATH := "res://data/weapons.json"
const BULLET_SCENE := preload("res://scenes/projectiles/bullet_base.tscn")

## 子彈生成點相對於角色中心的偏移，避免一出生就卡在自己的碰撞體裡
@export var muzzle_offset: Vector2 = Vector2(36, 0)

var weapons: Array = []
var current_index: int = 0
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

	weapons = parsed
	if not weapons.is_empty():
		weapon_changed.emit(get_current_weapon(), current_index)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)

	if Input.is_action_just_pressed(&"weapon_next"):
		cycle_weapon(1)
	if Input.is_action_just_pressed(&"weapon_prev"):
		cycle_weapon(-1)


## 循環切換武器。step 為正往後、為負往前。
func cycle_weapon(step: int) -> void:
	if weapons.is_empty():
		return  # 沒有武器時取模會除以零
	current_index = posmod(current_index + step, weapons.size())
	weapon_changed.emit(get_current_weapon(), current_index)


func get_current_weapon() -> Dictionary:
	if weapons.is_empty():
		return {}
	return weapons[current_index]


func can_fire() -> bool:
	return cooldown <= 0.0 and not weapons.is_empty()


## direction 由呼叫方傳入（Player 的 facing_dir），不從節點 scale 推導——
## 漢字本體不翻轉，scale 讀不出朝向。
func fire(direction: float = 1.0) -> void:
	if not can_fire():
		return

	var weapon: Dictionary = get_current_weapon()
	cooldown = float(weapon.get("fire_rate", 0.5))

	var dir := Vector2(signf(direction) if not is_zero_approx(direction) else 1.0, 0.0)
	# 本身是 Node（沒有 global_position），生成點取自父節點的角色
	var origin: Node2D = get_parent() as Node2D
	var spawn_pos: Vector2 = Vector2.ZERO if origin == null else origin.global_position
	spawn_pos += Vector2(muzzle_offset.x * dir.x, muzzle_offset.y)

	var bullet: Bullet = BULLET_SCENE.instantiate()
	bullet.setup(int(weapon.get("damage", 0)), String(weapon.get("element", "neutral")), spawn_pos, dir)

	# 掛在關卡根節點而非 Player 底下——掛在 Player 底下的話，子彈會跟著角色移動，
	# 且角色死亡 queue_free 時會把空中的子彈一起帶走。
	_get_projectile_parent().add_child(bullet)


func _get_projectile_parent() -> Node:
	# current_scene 在單元測試環境可能是 null，退回場景樹根節點
	var scene := get_tree().current_scene
	return scene if scene != null else get_tree().root
