## 近戰揮擊元件（Task 2.7b）。
##
## 三段式生命週期：**前搖 windup → 判定 active → 冷卻 cooldown**。
## 玩家與敵人共用同一份程式碼（敵人側 Task 2.7d 接上），只有 mask 與 profile 不同——
## 戰鬥規則對雙方對稱，日後調手感只需要改一處，階段五的 Boss 也能直接複用。
##
## ⚠️ **判定用即時形狀查詢（`intersect_shape`），而不是常駐 Area2D + 開關 CollisionShape2D。**
## `docs/COMBAT.md` 6.1 節原本規劃成 Area2D，實作時改掉，三個理由：
##
## 1. 開關碰撞形狀必須走 `set_deferred()`（物理查詢 flush 期間不可同步改碰撞狀態，
##    `Enemy.die()` 已經踩過這個坑），代表判定框「真正生效」比程式碼寫的晚一幀，
##    0.12s 的判定窗實際只有 0.10s，且時長會隨影格率漂移。
## 2. Area2D 的 `get_overlapping_bodies()` 要等物理步進後才更新，判定第一幀必然是空的。
## 3. 即時查詢**當幀就有結果**，測試不必猜要 await 幾幀，也不需要為近戰新增碰撞層。
class_name MeleeAttack
extends Node2D

signal swing_started(profile: Dictionary, downward: bool)
signal hit_landed(target: Node, damage: int)
signal bullet_blocked(bullet: Node)
signal charge_interrupted(target: Node)
## 下劈命中任何東西時送出，由角色自己決定怎麼彈（見 player.gd 的順序說明）
signal pogo_bounced(bounce_velocity: float)
## 上挑命中時送出。與下劈對稱：下劈抬自己、上挑抬敵人。
signal target_launched(target: Node, launch_velocity: float)
signal swing_finished

const DATA_PATH := "res://data/melee.json"
## 留在被近戰打到的目標身上，供 ComponentDropper 判斷掉落物要不要吸附
const MELEE_HIT_META := &"_ironglyph_melee_hit"
## 單次查詢最多回傳幾個碰撞體。一次揮擊同時掃到十幾個目標已經是極端情況。
const MAX_HITS := 16

enum State {
	IDLE,
	WINDUP,
	ACTIVE,
	COOLDOWN,
}

## 揮擊的垂直方向。W/S 是一對修飾鍵：S+K 下劈、W+K 上挑。
enum Vertical {
	UP = -1,
	NONE = 0,
	DOWN = 1,
}

## 預設使用的 profile id。Task 2.7c 起由 GlyphLoadout 依裝備狀態傳入。
@export var profile_id: String = "ling_slash"

## 判定要打傷的層。玩家＝enemy(4)；敵人＝player(2)。
@export_flags_2d_physics var target_mask: int = 4

## 可以被揮掉的投射物層（消彈）。
## ⚠️ **絕不可包含 player_bullet(8)**，否則玩家會揮掉自己剛打出去的子彈。
## 敵人側設為 0——敵人不消玩家子彈，否則遠程武器完全失效。
@export_flags_2d_physics var block_mask: int = 16

## 是否生成揮擊軌跡。元件測試關掉可以省下每次揮擊的 tween 與節點。
@export var show_arc: bool = true

## 命中時是否打斷目標的蓄力。**只有玩家可以**——敵人也能打斷的話，
## 玩家的每一次遠程攻擊都會被貼身敵人打斷，遊戲會變成互相鎖死。
@export var can_interrupt: bool = true

## 命中時是否在目標身上留下「被近戰打到」的記號，供掉落物判斷要不要吸附。
@export var marks_melee_hits: bool = true

var state: int = State.IDLE
var facing: float = 1.0
## 目前這一擊的垂直方向（Vertical.UP / NONE / DOWN）
var vertical: int = Vertical.NONE

## 資料表靜態快取：每個敵人都重讀一次 JSON 是 Task 3.3 修過的問題
static var _data: Dictionary = {}

var _profile: Dictionary = {}
var _timings: Dictionary = {}
var _timer: float = 0.0
var _hit_this_swing: Dictionary = {}
var _bounced_this_swing: bool = false
var _launched_this_swing: bool = false
var _query_shape: RectangleShape2D = RectangleShape2D.new()


static func load_data() -> Dictionary:
	if not _data.is_empty():
		return _data

	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("MeleeAttack: 無法開啟 %s" % DATA_PATH)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MeleeAttack: %s 解析失敗，應為物件" % DATA_PATH)
		return {}

	_data = parsed
	return _data


## 取得一份 profile 拷貝；找不到回傳空字典。
static func get_profile(id: String) -> Dictionary:
	var profiles: Variant = load_data().get("profiles", {})
	if typeof(profiles) != TYPE_DICTIONARY:
		return {}
	var profile: Variant = (profiles as Dictionary).get(id, {})
	return (profile as Dictionary).duplicate(true) if typeof(profile) == TYPE_DICTIONARY else {}


static func get_pogo_settings() -> Dictionary:
	var pogo: Variant = load_data().get("pogo", {})
	return (pogo as Dictionary).duplicate(true) if typeof(pogo) == TYPE_DICTIONARY else {}


static func get_uppercut_settings() -> Dictionary:
	var upper: Variant = load_data().get("uppercut", {})
	return (upper as Dictionary).duplicate(true) if typeof(upper) == TYPE_DICTIONARY else {}


func can_swing() -> bool:
	return state == State.IDLE


func is_swinging() -> bool:
	return state == State.WINDUP or state == State.ACTIVE


func get_active_profile() -> Dictionary:
	return _profile.duplicate(true)


## 揮擊。`direction` 是水平朝向（±1），`down` 為真時判定框改到腳下（下劈）。
## 回傳是否真的開始揮擊——冷卻中會回傳 false。
func swing(direction: float, profile: Dictionary = {}, vertical_dir: int = Vertical.NONE) -> bool:
	if not can_swing():
		return false

	var resolved := profile if not profile.is_empty() else get_profile(profile_id)
	if resolved.is_empty():
		push_warning("MeleeAttack: 找不到近戰 profile「%s」" % profile_id)
		return false

	_profile = resolved
	vertical = vertical_dir
	facing = signf(direction) if not is_zero_approx(direction) else 1.0
	_timings = _resolve_timings()
	_hit_this_swing.clear()
	_bounced_this_swing = false
	_launched_this_swing = false

	state = State.WINDUP
	_timer = float(_timings.get("windup", 0.0))
	swing_started.emit(_profile.duplicate(true), vertical)

	# 前搖為 0 的 profile 要當幀就進入判定，不能白白吃掉一幀
	if _timer <= 0.0:
		_enter_active()
	return true


## 中斷目前揮擊並回到 IDLE（角色死亡、被擊飛等情境）。
func cancel() -> void:
	state = State.IDLE
	_timer = 0.0
	_hit_this_swing.clear()


func _physics_process(delta: float) -> void:
	match state:
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_enter_active()
		State.ACTIVE:
			# 先判定再扣時間：判定窗的第一幀與最後一幀都要真的掃一次
			_resolve_hits()
			_timer -= delta
			if _timer <= 0.0:
				_enter_cooldown()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				state = State.IDLE
				swing_finished.emit()


func _enter_active() -> void:
	state = State.ACTIVE
	_timer = float(_timings.get("active", 0.1))
	_spawn_arc()
	_resolve_hits()


## 揮擊軌跡掛在自己底下：跟著角色移動，角色死亡時一起消失，
## 不會像子彈那樣留在關卡裡。
func _spawn_arc() -> void:
	if not show_arc:
		return
	var element := get_element()
	var color: Color = Bullet.ELEMENT_COLORS.get(element, Color.WHITE)
	# 傳局部偏移而不是世界座標：弧線掛在本節點底下，本節點就在角色中心
	MeleeArc.spawn(
		self,
		get_hitbox_offset(),
		facing,
		String(_profile.get("glyph", "")),
		color,
		float(_timings.get("active", 0.12)) * 1.6,
		float(_timings.get("reach", 58.0)),
		vertical,
		element
	)


func _enter_cooldown() -> void:
	state = State.COOLDOWN
	# cooldown 是「從揮出到能再揮」的總時長，扣掉已經走過的前搖與判定
	var total := float(_timings.get("cooldown", 0.4))
	var elapsed := float(_timings.get("windup", 0.0)) + float(_timings.get("active", 0.1))
	_timer = maxf(0.0, total - elapsed)
	if _timer <= 0.0:
		state = State.IDLE
		swing_finished.emit()


## 是否為下劈。保留給既有呼叫端與視覺判讀。
func is_downward() -> bool:
	return vertical == Vertical.DOWN


func is_upward() -> bool:
	return vertical == Vertical.UP


## 上下揮擊時各段時長與判定框改用 pogo / uppercut 區塊的設定。
func _resolve_timings() -> Dictionary:
	var timings := {
		"windup": float(_profile.get("windup", 0.1)),
		"active": float(_profile.get("active", 0.12)),
		"cooldown": float(_profile.get("cooldown", 0.45)),
		"reach": float(_profile.get("reach", 58.0)),
		"hitbox": _profile.get("hitbox", [72, 56]),
		"damage_scale": 1.0,
		"bounce": 0.0,
	}
	if vertical == Vertical.UP:
		var upper := get_uppercut_settings()
		timings["windup"] = float(upper.get("windup", timings["windup"]))
		timings["active"] = float(upper.get("active", timings["active"]))
		timings["cooldown"] = float(upper.get("cooldown", timings["cooldown"]))
		timings["offset_forward"] = float(upper.get("offset_forward", 42.0))
		timings["offset_up"] = float(upper.get("offset_up", 46.0))
		timings["hitbox"] = upper.get("hitbox", [66, 70])
		timings["damage_scale"] = float(upper.get("damage_scale", 0.9))
		timings["launch"] = float(upper.get("launch", -320.0))
		return timings

	if vertical != Vertical.DOWN:
		return timings

	var pogo := get_pogo_settings()
	timings["windup"] = float(pogo.get("windup", timings["windup"]))
	timings["active"] = float(pogo.get("active", timings["active"]))
	timings["cooldown"] = float(pogo.get("cooldown", timings["cooldown"]))
	timings["reach"] = float(pogo.get("offset", 52.0))
	timings["hitbox"] = pogo.get("hitbox", [56, 72])
	timings["damage_scale"] = float(pogo.get("damage_scale", 0.8))
	timings["bounce"] = float(pogo.get("bounce", -340.0))
	return timings


## 判定框中心相對於本節點的位置。向前揮是水平偏移，下劈是往下。
func get_hitbox_offset() -> Vector2:
	var reach := float(_timings.get("reach", 58.0))
	match vertical:
		Vertical.DOWN:
			return Vector2(0.0, reach)
		Vertical.UP:
			# ⚠️ 斜**前**上方，不是正頭頂。敵人幾乎不會站在玩家正上方，
			# 判定放頭頂的話揮出去總是空的，看起來像沒打中。
			return Vector2(
				float(_timings.get("offset_forward", 42.0)) * facing,
				-float(_timings.get("offset_up", 46.0))
			)
		_:
			return Vector2(reach * facing, 0.0)


func get_hitbox_size() -> Vector2:
	var raw: Variant = _timings.get("hitbox", [72, 56])
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2(72.0, 56.0)


func get_damage() -> int:
	return int(round(float(_profile.get("damage", 0)) * float(_timings.get("damage_scale", 1.0))))


func get_element() -> String:
	return String(_profile.get("element", "neutral"))


func _resolve_hits() -> void:
	var world := get_world_2d()
	if world == null:
		return

	_query_shape.size = get_hitbox_size()

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _query_shape
	params.transform = Transform2D(0.0, global_position + get_hitbox_offset())
	params.collision_mask = target_mask | block_mask
	params.collide_with_bodies = true
	# 子彈是 Area2D。只查 bodies 的話永遠消不到彈——與 Task 2.3
	# 「Area2D 的 area_entered 對 PhysicsBody2D 不觸發」是同一個坑的反面。
	params.collide_with_areas = true

	var body := get_parent() as CollisionObject2D
	if body != null:
		params.exclude = [body.get_rid()]

	for result: Dictionary in world.direct_space_state.intersect_shape(params, MAX_HITS):
		_apply_hit(result.get("collider"))


func _apply_hit(collider: Variant) -> void:
	var node := collider as Node
	if node == null or not is_instance_valid(node):
		return

	# 同一次揮擊對同一個目標只結算一次。判定窗橫跨多個物理影格，
	# 不去重的話貼身揮一次會打出七、八下。
	var key := node.get_instance_id()
	if _hit_this_swing.has(key):
		return

	var layer := 0
	var collision_object := node as CollisionObject2D
	if collision_object != null:
		layer = collision_object.collision_layer

	if node is Bullet and (layer & block_mask) != 0:
		_hit_this_swing[key] = true
		bullet_blocked.emit(node)
		_try_pogo()
		node.queue_free()
		return

	if node is Character and (layer & target_mask) != 0:
		_hit_this_swing[key] = true
		var damage := get_damage()
		# ⚠️ 記號要在 take_damage **之前**留。這一下可能直接打死目標，
		# 而掉落物是在 die() 裡同步生成的——死後才標記就來不及了。
		if marks_melee_hits:
			node.set_meta(MELEE_HIT_META, true)
		# 傷害一律走基類：相剋倍率、hp 夾值、hp_changed/died 訊號與死亡去重都在那裡
		(node as Character).take_damage(damage, get_element())
		hit_landed.emit(node, damage)
		_try_interrupt(node)
		_try_pogo()
		_try_launch(node)


## 打斷目標的蓄力。只有近戰打得斷，遠程不行——這是靠近定點AOE敵人的唯一理由。
func _try_interrupt(node: Node) -> void:
	if not can_interrupt:
		return
	# 這一下可能已經把目標打死了；對正在銷毀的節點不必再打斷
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if not node.has_method(&"interrupt_charge"):
		return
	if node.call(&"interrupt_charge"):
		charge_interrupted.emit(node)


## 上挑命中才把敵人擊飛。與下劈對稱：**下劈抬自己、上挑抬敵人**。
##
## 一次揮擊可以挑起多個敵人（不像彈起只該有一次），但同一個目標只挑一次——
## 去重已經由 _hit_this_swing 保證。
func _try_launch(node: Node) -> void:
	if vertical != Vertical.UP:
		return
	var launch := float(_timings.get("launch", 0.0))
	if is_zero_approx(launch):
		return
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return

	var body := node as CharacterBody2D
	if body != null:
		body.velocity.y = launch
	_launched_this_swing = true
	target_launched.emit(node, launch)


## 下劈命中才彈起，且一次揮擊只彈一次——一刀掃到三隻敵人不該疊加成三倍彈速。
func _try_pogo() -> void:
	if vertical != Vertical.DOWN or _bounced_this_swing:
		return
	var bounce := float(_timings.get("bounce", 0.0))
	if is_zero_approx(bounce):
		return
	_bounced_this_swing = true
	pogo_bounced.emit(bounce)
