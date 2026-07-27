## 敵人生成器（Task 3.3）
##
## 放在關卡場景裡，設定 enemy_char 即可生成對應敵人。
## 資料表由靜態快取共用——20個生成器不需要各自把 enemies.json 讀一遍。
class_name EnemySpawner
extends Node2D

signal enemy_spawned(enemy: Enemy)
signal enemy_defeated(enemy: Enemy)

const DATA_PATH := "res://data/enemies.json"
const ENEMY_SCENE := preload("res://scenes/enemy_base.tscn")

## 要生成哪個敵字，必須存在於 enemies.json
@export var enemy_char: String = "河"
## 是否在 _ready 時自動生成。關卡若要做波次控制可關掉，改由外部呼叫 spawn()
@export var spawn_on_ready: bool = true
## 敵人被打倒後多久重生。設 0 或負數代表不重生
@export var respawn_delay: float = 0.0

static var _data_table: Dictionary = {}
static var _data_loaded: bool = false

var current_enemy: Enemy = null


func _ready() -> void:
	load_data_table()
	if spawn_on_ready:
		spawn()


## 讀取並快取 enemies.json。重複呼叫不會重讀。
static func load_data_table() -> void:
	if _data_loaded:
		return

	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("EnemySpawner: 無法開啟 %s（錯誤碼 %d）" % [DATA_PATH, FileAccess.get_open_error()])
		return

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()

	if typeof(parsed) != TYPE_ARRAY:
		push_error("EnemySpawner: %s 解析失敗，應為陣列" % DATA_PATH)
		return

	for entry: Dictionary in parsed:
		_data_table[entry.get("char", "")] = entry
	_data_loaded = true


static func get_enemy_data(character: String) -> Dictionary:
	load_data_table()
	return _data_table.get(character, {})


static func get_all_enemy_data() -> Array:
	load_data_table()
	return _data_table.values()


func spawn() -> Enemy:
	var data := get_enemy_data(enemy_char)
	if data.is_empty():
		push_error("EnemySpawner: enemies.json 裡沒有「%s」" % enemy_char)
		return null

	var enemy: Enemy = ENEMY_SCENE.instantiate()
	add_child(enemy)
	enemy.setup(data)
	enemy.defeated.connect(_on_enemy_defeated)

	current_enemy = enemy
	enemy_spawned.emit(enemy)
	return enemy


func _on_enemy_defeated(enemy: Enemy) -> void:
	enemy_defeated.emit(enemy)
	current_enemy = null
	if respawn_delay > 0.0:
		await get_tree().create_timer(respawn_delay).timeout
		if is_instance_valid(self):
			spawn()
