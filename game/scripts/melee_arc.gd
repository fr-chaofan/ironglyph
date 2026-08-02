## 揮擊視覺（Task 2.7b）。
##
## 甩出字核的一根真實筆畫當作揮擊軌跡——複用 Task 3.4 筆畫崩解的
## 「medians → Line2D」技術，不需要任何美術素材。
##
## ⚠️ 不是所有字都有筆畫資料。「刂」（Task 2.7c 的刀刃筆擊）就**不在**
## Make Me a Hanzi 資料集裡，`HanziData.get_medians()` 會回傳空陣列。
## 沒有筆畫資料時退回一段幾何弧線，而不是讓揮擊變成看不見的攻擊——
## 與 `HanziSprite.shatter_and_die()` 在缺資料時退回整體淡出是同一個原則。
class_name MeleeArc
extends Line2D

## Make Me a Hanzi 的字身框大小；y 軸朝上，與螢幕相反
const _EM_SIZE := 1024.0
## 揮擊掃過的角度（弧度）
const _SWEEP := deg_to_rad(110.0)


## 生成一道揮擊弧線並自動釋放。
##
## `offset` 是**相對於 `parent` 的局部座標**（判定框中心），`facing` ±1，
## `downward` 為真時整段往下掃。
##
## ⚠️ **位置一定要在 `add_child()` 之後才設，而且設的是 `position` 不是 `global_position`。**
## 節點還沒進場景樹時沒有父變換，Godot 的 `global_position` setter 會退化成 `set_position()`
## ——那個世界座標會被當成局部座標，加進場景樹後變成「父節點位置 + 世界座標」，偏移量直接翻倍。
## 2.7b 就是這樣讓揮擊弧線跑到腳下 120px 的位置，而且玩家走得越遠偏得越多。
static func spawn(
	parent: Node,
	offset: Vector2,
	facing: float,
	glyph: String,
	color: Color,
	duration: float,
	reach: float,
	downward: bool = false
) -> MeleeArc:
	if parent == null or not is_instance_valid(parent):
		return null

	var arc := MeleeArc.new()
	arc.width = maxf(3.0, reach * 0.14)
	arc.default_color = color
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	arc.joint_mode = Line2D.LINE_JOINT_ROUND
	arc.z_index = 6
	arc.points = _build_points(glyph, reach)

	parent.add_child(arc)
	arc.position = offset
	arc._animate(facing, duration, downward)
	return arc


## 取字形裡**最長的一筆**當揮擊軌跡：筆畫數越多的字，最長的一筆通常就是
## 那一撇或一捺，甩出去最像揮擊；短點畫甩出來看不出方向。
static func _build_points(glyph: String, reach: float) -> PackedVector2Array:
	var medians: Array = HanziData.get_medians(glyph)
	var longest: Array = []
	var longest_length := 0.0

	for stroke: Array in medians:
		if stroke.size() < 2:
			continue
		var length := 0.0
		for i in range(1, stroke.size()):
			length += Vector2(float(stroke[i][0]), float(stroke[i][1])).distance_to(
				Vector2(float(stroke[i - 1][0]), float(stroke[i - 1][1]))
			)
		if length > longest_length:
			longest_length = length
			longest = stroke

	if longest.is_empty():
		return _fallback_arc(reach)

	# 以筆畫自身的外框正規化到 [-0.5, 0.5]，再放大到 reach——
	# 不同字的筆畫長度差很多，不正規化的話「令」與「劍」的揮擊會差好幾倍大小
	var min_point := Vector2.INF
	var max_point := -Vector2.INF
	for point: Array in longest:
		var p := Vector2(float(point[0]), float(point[1]))
		min_point = min_point.min(p)
		max_point = max_point.max(p)

	var extent := maxf(max_point.x - min_point.x, max_point.y - min_point.y)
	if extent <= 0.0:
		return _fallback_arc(reach)

	var center := (min_point + max_point) * 0.5
	var scale_factor := reach * 1.5 / extent
	var points := PackedVector2Array()
	for point: Array in longest:
		points.append(Vector2(
			(float(point[0]) - center.x) * scale_factor,
			# y 取負號：字身框 y 朝上，螢幕 y 朝下
			-(float(point[1]) - center.y) * scale_factor
		))
	return points


## 沒有筆畫資料時的退路：一段圓弧
static func _fallback_arc(reach: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := reach * 0.75
	for i in 9:
		var angle := lerpf(-_SWEEP * 0.5, _SWEEP * 0.5, float(i) / 8.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _animate(facing: float, duration: float, downward: bool) -> void:
	var base_angle := PI * 0.5 if downward else 0.0
	# 往左揮時鏡像的是**軌跡**不是字形本身，不違反「漢字不可水平鏡像」的鐵律——
	# 這裡畫的是一道揮擊光跡，不是要讓玩家讀出是哪個字
	scale.x = facing if not downward else 1.0

	# ⚠️ **鏡像的同時，掃描方向也必須跟著反過來。**
	# 螢幕 y 軸朝下，所以角度由負掃到正 = 由上往下劈。形狀被 scale.x = -1 鏡像後，
	# 同一組角度序列會變成由下往上「撩」——看起來就不是劈了。
	# 只翻形狀不翻掃描方向，是鏡像動畫最容易漏掉的一半。
	var sweep_dir := 1.0 if downward else signf(facing)
	if is_zero_approx(sweep_dir):
		sweep_dir = 1.0

	rotation = base_angle - _SWEEP * 0.5 * sweep_dir
	modulate.a = 0.0

	var visible_time := maxf(duration, 0.05)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation", base_angle + _SWEEP * 0.5 * sweep_dir, visible_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, visible_time * 0.25)
	tween.chain().tween_property(self, "modulate:a", 0.0, visible_time * 0.75)
	tween.chain().tween_callback(queue_free)
