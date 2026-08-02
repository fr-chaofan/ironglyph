## 敵人掉落的可拾取部件（Task 2.6）。
##
## 進入範圍只顯示預覽；玩家按 E（interact）才交換單一部件槽。
## 若玩家原本有部件，這個節點就地改成舊部件，避免銷毀再生成造成重複掉落。
class_name ComponentPickup
extends Area2D

@export_range(0.0, 1.0, 0.01) var exchange_lock_duration: float = 0.2

## 近戰擊殺時掉落物飛向玩家的最高速度（像素/秒）與加速度（Task 2.7c）。
## 飛過去之後**仍然要按 E 才會裝備**——「借」是玩家的主動選擇，
## 自動裝備會把 Task 2.6 整套「借與還」的分寸感洗掉。
@export var attract_speed: float = 460.0
@export var attract_acceleration: float = 1400.0
## 靠得夠近就停下，不要在玩家身上抖動
@export var attract_stop_distance: float = 20.0

## 同一幀有多個拾取物與玩家重疊時，只允許場景樹中先收到 input 的一個完成交換。
static var _interaction_claim_frame: int = -1

@onready var _glyph: Label = get_node_or_null(^"Glyph") as Label
@onready var _hint: Label = get_node_or_null(^"Hint") as Label

var component: Dictionary = {}
var _nearby_player: Node2D
var _nearby_loadout: Node
var _exchange_lock_left: float = 0.0
var _attract_target: Node2D
var _attract_speed_current: float = 0.0


func _ready() -> void:
	add_to_group(&"component_pickup")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_refresh_visuals()


func _process(delta: float) -> void:
	_exchange_lock_left = maxf(0.0, _exchange_lock_left - delta)
	_update_attraction(delta)
	if _nearby_loadout == null or not is_instance_valid(_nearby_loadout):
		return
	if _exchange_lock_left > 0.0 or not InputMap.has_action(&"interact"):
		return
	if Input.is_action_just_pressed(&"interact"):
		var process_frame := Engine.get_process_frames()
		if _interaction_claim_frame == process_frame:
			return
		_interaction_claim_frame = process_frame
		try_collect()


func setup(component_data: Dictionary) -> void:
	component = component_data.duplicate(true)
	if is_node_ready():
		_refresh_visuals()


## 讓掉落物飛向目標（Task 2.7c）。近戰擊殺的獎勵：不必走過去撿。
##
## 只是移動，**不會自動裝備**——按 E 交換仍然是玩家的主動選擇。
func attract_to(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_attract_target = target
	_attract_speed_current = 0.0


func is_attracting() -> bool:
	return _attract_target != null and is_instance_valid(_attract_target)


func _update_attraction(delta: float) -> void:
	if not is_attracting():
		return

	var offset: Vector2 = _attract_target.global_position - global_position
	if offset.length() <= attract_stop_distance:
		_attract_target = null
		return

	_attract_speed_current = minf(
		attract_speed, _attract_speed_current + attract_acceleration * delta
	)
	global_position += offset.normalized() * _attract_speed_current * delta


## 讓新彈出的部件短暫不可被拾取，避免玩家仍在碰撞範圍內時立刻吸回去。
func arm_exchange_lock(duration: float = -1.0) -> void:
	var lock_duration := exchange_lock_duration if duration < 0.0 else duration
	_exchange_lock_left = maxf(0.0, lock_duration)


## 回傳是否成功把目前部件交給玩家。
func try_collect() -> bool:
	if component.is_empty() or _exchange_lock_left > 0.0:
		return false
	if _nearby_loadout == null or not is_instance_valid(_nearby_loadout):
		return false

	var incoming_id := String(component.get("id", "")).strip_edges()
	if incoming_id.is_empty():
		return false

	var old_component: Dictionary = _nearby_loadout.call(&"equip_component_id", incoming_id)
	var equipped: Dictionary = _nearby_loadout.get_snapshot().get("component", {})
	if String(equipped.get("id", "")) != incoming_id:
		return false

	if old_component.is_empty():
		queue_free()
		return true

	# 單槽交換：同一個世界拾取物改成舊部件，不額外生成第二個節點。
	component = old_component.duplicate(true)
	_exchange_lock_left = exchange_lock_duration
	_refresh_visuals()
	return true


func _on_body_entered(body: Node2D) -> void:
	var loadout: Node = _find_loadout(body)
	if loadout == null:
		return
	_nearby_player = body
	_nearby_loadout = loadout
	_refresh_visuals()


func _on_body_exited(body: Node2D) -> void:
	if body != _nearby_player:
		return
	_nearby_player = null
	_nearby_loadout = null
	_refresh_visuals()


func _find_loadout(body: Node) -> Node:
	if body == null:
		return null
	var candidate := body.get_node_or_null(^"GlyphLoadout")
	if candidate == null:
		return null
	if (
		not candidate.has_method(&"equip_component_id")
		or not candidate.has_method(&"preview_component_id")
		or not candidate.has_method(&"get_snapshot")
	):
		return null
	return candidate


func _refresh_visuals() -> void:
	var display_glyph := String(component.get("display_glyph", "")).strip_edges()
	if _glyph != null:
		_glyph.text = display_glyph
		var element := String(component.get("element", "neutral"))
		_glyph.modulate = Bullet.ELEMENT_COLORS.get(element, Color.WHITE)

	if _hint == null:
		return
	_hint.visible = _nearby_loadout != null and is_instance_valid(_nearby_loadout)
	if not _hint.visible:
		return

	var component_id := String(component.get("id", "")).strip_edges()
	var preview: Dictionary = _nearby_loadout.call(&"preview_component_id", component_id)
	if preview.is_empty():
		_hint.text = "E：無法吸收"
		return

	var core := String(preview.get("core_glyph", "令"))
	if String(preview.get("mode", "held")) == "fused":
		_hint.text = "E：%s + %s → %s" % [
			display_glyph,
			core,
			String(preview.get("visible_glyph", core)),
		]
	else:
		_hint.text = "E：%s + %s → 手持" % [display_glyph, core]
