## 子彈（Task 2.3 / 2.4）
##
## 玩家武器與Boss彈幕共用。方向統一用 Vector2——玩家子彈只有水平分量，
## Boss彈幕（階段五）用任意角度，兩者不需要分叉邏輯。
class_name Bullet
extends Area2D

## Task 2.4：按五行著色，讓玩家一眼看出屬性歸屬。
##
## 顏色一律來自 `data/palette.json`——全遊戲只有那一份色板，
## 字形、子彈、刀氣、傷害數字、UI 都讀它。
##
## 改成宣紙底之後整組色都換過：深底時用的高飽和亮色在紙上會糊掉，
## 現在是能壓在紙上的深色顏料（靛藍／朱砂／銀灰／石綠／藤黃／焦墨）。
static var ELEMENT_COLORS: Dictionary = Palette.elements()

## `weapons.json` 的 `range` 欄位換算成實際飛行距離（像素）。
##
## Task 2.7a 之前這個欄位是死資料——十把武器只有傷害與射速的差別，
## 「暗器(long)」與「藤蔓刺(short)」的射程完全一樣。
const RANGE_DISTANCES := {
	"short": 180.0,
	"medium": 420.0,
	"long": 720.0,
}

@export var speed: float = 500.0

## 存活上限（秒）。沒有這個的話，打空的子彈會一直往畫面外飛且永不釋放，
## 一場戰鬥下來累積成千上萬個節點。
@export var max_lifetime: float = 3.0

## 飛行距離上限（像素）。0 表示不限距離，只受 max_lifetime 約束。
##
## ⚠️ 這是**距離**上限而不是換算成時間的存活上限：兩者在等速直線下等價，
## 但日後若加入減速／追蹤彈，距離才是設計者真正想控制的量。
@export var max_distance: float = 0.0

var damage: int = 0
var element: String = "neutral"
var direction: Vector2 = Vector2.RIGHT

var _age: float = 0.0
var _travelled: float = 0.0
var _trail: BulletTrail
var _vfx: Dictionary = {}
var _spin: float = 0.0


func _ready() -> void:
	# ⚠️ 用 body_entered 而非 area_entered。
	# Character 繼承 CharacterBody2D（PhysicsBody2D），Area2D 的 area_entered
	# 只會對其他 Area2D 觸發，對 PhysicsBody2D 永遠不會觸發——照原計劃寫成
	# area_entered 的話，子彈能生成、能飛，但永遠打不到任何人。
	body_entered.connect(_on_body_entered)


func setup(dmg: int, elem: String, spawn_pos: Vector2, dir: Vector2) -> void:
	damage = dmg
	element = elem
	direction = dir.normalized()
	global_position = spawn_pos
	modulate = ELEMENT_COLORS.get(elem, Color.WHITE)
	_build_visual()


## 依屬性造出筆頭與拖尾。
##
## 遠程原本是一個固定的 9×6 實心菱形，六種屬性只換顏色——近戰卻有多層刀氣、
## 筆鋒與粒子。這裡把同一套思路搬過來：**子彈本身就是一筆運動中的墨**，
## 每個屬性的筆頭長寬、拖尾長度、擺動、自轉都不一樣。造型參數在
## `data/element_vfx.json` 的 projectile 區塊，調整不必動程式碼。
func _build_visual() -> void:
	_vfx = _get_projectile_profile(element)
	var color: Color = ELEMENT_COLORS.get(element, Color.WHITE)
	_spin = float(_vfx.get("spin", 0.0))

	# 筆頭：一枚有鋒的墨點，長寬依屬性而異（金是細長的針，土是粗短的塊）
	var visual := get_node_or_null(^"Visual") as Polygon2D
	if visual != null:
		var length := float(_vfx.get("head_length", 14.0))
		var half := float(_vfx.get("head_width", 7.0)) * 0.5
		visual.polygon = PackedVector2Array([
			Vector2(length * 0.5, 0.0),
			Vector2(-length * 0.35, -half),
			Vector2(-length * 0.5, 0.0),
			Vector2(-length * 0.35, half),
		])
		# 筆頭要朝著飛行方向，否則金的長針會橫著飛
		if not is_zero_approx(_spin):
			visual.rotation = 0.0
		else:
			visual.rotation = direction.angle()

	_trail = BulletTrail.new()
	_trail.setup(
		color,
		float(_vfx.get("trail_width", 11.0)),
		int(_vfx.get("trail_points", 16)),
		float(_vfx.get("wave", 0.0)),
		float(_vfx.get("wave_frequency", 3.0))
	)
	add_child(_trail)

	var amount := int(_vfx.get("particles", 0))
	if amount <= 0:
		return
	var particles := CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = 0.4
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 5.0
	particles.direction = -direction
	particles.spread = 40.0
	particles.initial_velocity_min = float(_vfx.get("particle_speed", 70.0)) * 0.4
	particles.initial_velocity_max = float(_vfx.get("particle_speed", 70.0))
	particles.gravity = Vector2(0.0, 90.0)
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 2.0
	particles.color = color
	particles.z_index = 3
	particles.emitting = true
	add_child(particles)


static func _get_projectile_profile(element_name: String) -> Dictionary:
	var data := MeleeArc.load_vfx_data()
	var profile: Dictionary = (data.get("projectile_defaults", {}) as Dictionary).duplicate(true)
	var table: Variant = data.get("projectile", {})
	if typeof(table) != TYPE_DICTIONARY:
		return profile
	var override: Variant = (table as Dictionary).get(element_name, {})
	if typeof(override) == TYPE_DICTIONARY:
		for key: String in (override as Dictionary):
			if not key.begins_with("_"):
				profile[key] = (override as Dictionary)[key]
	return profile


## 依 `weapons.json` 的 `range` 值設定飛行距離上限。
## 未知或 "melee" 一律回到不限距離——近戰武器不該走到生成子彈這條路，
## 真的走到了也讓它照舊飛，不要靜默變成射程 0 的啞彈。
func set_range(range_name: String) -> void:
	max_distance = float(RANGE_DISTANCES.get(range_name, 0.0))


func _physics_process(delta: float) -> void:
	var step := speed * delta
	position += direction * step

	if _trail != null and is_instance_valid(_trail):
		_trail.push_sample(global_position, direction, delta)
	if not is_zero_approx(_spin):
		# 土屬的石塊翻滾
		var visual := get_node_or_null(^"Visual") as Polygon2D
		if visual != null:
			visual.rotation += _spin * delta

	_travelled += absf(step)
	if max_distance > 0.0 and _travelled >= max_distance:
		queue_free()
		return

	_age += delta
	if _age >= max_lifetime:
		# 飛到期的子彈不算命中，只讓拖尾化開，不炸墨點
		if _trail != null and is_instance_valid(_trail):
			var trail_parent := _get_effect_parent()
			remove_child(_trail)
			trail_parent.add_child(_trail)
			_trail.fade_and_free()
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Character:
		(body as Character).take_damage(damage, element)
	# 打到地形（沒有 take_damage 的 StaticBody2D）也要消失，不能穿牆
	_burst()
	queue_free()


## 命中時炸開幾點墨。原本子彈是直接 queue_free，打中什麼都沒有回饋。
##
## ⚠️ 墨點與拖尾都不能掛在自己底下——本節點下一刻就要被釋放。
## 拖尾改成脫離後自己淡出，墨跡會在紙上留一會兒才化開。
func _burst() -> void:
	if _trail != null and is_instance_valid(_trail):
		var trail_parent := _get_effect_parent()
		remove_child(_trail)
		trail_parent.add_child(_trail)
		_trail.fade_and_free()

	var bits := int(_vfx.get("impact_bits", 0))
	if bits <= 0:
		return

	var burst := CPUParticles2D.new()
	burst.amount = bits
	burst.lifetime = 0.45
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 4.0
	burst.direction = -direction
	burst.spread = float(_vfx.get("impact_spread", 90.0))
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 150.0
	burst.gravity = Vector2(0.0, 260.0)
	burst.scale_amount_min = 1.0
	burst.scale_amount_max = 2.6
	burst.color = ELEMENT_COLORS.get(element, Color.WHITE)
	burst.z_index = 5
	burst.emitting = true

	var parent := _get_effect_parent()
	parent.add_child(burst)
	burst.global_position = global_position
	# one_shot 的粒子放完要自己收掉，否則場上會累積空節點
	burst.get_tree().create_timer(burst.lifetime * 2.0).timeout.connect(burst.queue_free)


func _get_effect_parent() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else get_tree().root
