## 遠程子彈的屬性造型（視覺第四輪）
##
## 近戰有多層刀氣、筆鋒、飛白與粒子，遠程原本只是一個 9×6 的實心菱形、
## 六種屬性只換顏色。這裡驗證的是**造型有沒有真的分化**，
## 以及拖尾與命中特效的節點歸屬正不正確。
extends GutTest

const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")

var _host: Node2D


func before_each() -> void:
	_host = Node2D.new()
	add_child_autofree(_host)


func _spawn(element: String) -> Bullet:
	var bullet: Bullet = BulletScene.instantiate()
	bullet.collision_layer = 0
	bullet.collision_mask = 0
	bullet.speed = 0.0
	_host.add_child(bullet)
	bullet.setup(5, element, Vector2.ZERO, Vector2.RIGHT)
	return bullet


func _trail_of(bullet: Bullet) -> BulletTrail:
	for child: Node in bullet.get_children():
		if child is BulletTrail:
			return child as BulletTrail
	return null


# ---- 資料 ----

func test_每個屬性都有子彈造型參數() -> void:
	var data := MeleeArc.load_vfx_data()
	assert_true(data.has("projectile_defaults"), "缺 defaults 的話漏寫一個欄位就會拿到 0")
	for element: String in Bullet.ELEMENT_COLORS:
		assert_true((data.get("projectile", {}) as Dictionary).has(element), "缺少 %s 的子彈造型" % element)


func test_六種子彈造型互不相同() -> void:
	# 需求是「遠程還是很簡陋」——換顏色不算造型分化
	var shapes := {}
	for element: String in Bullet.ELEMENT_COLORS:
		var bullet := _spawn(element)
		var visual := bullet.get_node(^"Visual") as Polygon2D
		var trail := _trail_of(bullet)
		shapes[element] = "%s|%.1f|%d" % [visual.polygon, trail.width, trail.max_points]

	var keys: Array = shapes.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			assert_ne(
				shapes[keys[i]], shapes[keys[j]],
				"%s 與 %s 的子彈造型一模一樣" % [keys[i], keys[j]]
			)


func test_金是最細最長的針() -> void:
	var metal := _spawn("metal")
	var earth := _spawn("earth")

	assert_lt(_trail_of(metal).width, _trail_of(earth).width, "金要比土細")
	assert_gt(
		_trail_of(metal).max_points, _trail_of(earth).max_points,
		"金的殘影要最長，速度感來自拖得久"
	)


func test_土會翻滾而其他不會() -> void:
	var earth := _spawn("earth")
	var water := _spawn("water")
	var earth_before: float = (earth.get_node(^"Visual") as Polygon2D).rotation

	earth._physics_process(0.1)
	water._physics_process(0.1)

	assert_ne((earth.get_node(^"Visual") as Polygon2D).rotation, earth_before, "土屬石塊應該翻滾")
	assert_eq(
		(water.get_node(^"Visual") as Polygon2D).rotation, water.direction.angle(),
		"不翻滾的子彈筆頭要朝著飛行方向"
	)


# ---- 拖尾 ----

func test_拖尾用世界座標() -> void:
	# ⚠️ 不設 top_level 的話整條軌跡會跟著子彈平移，
	# 看起來像黏在屁股後面的棍子，而不是留在空中的墨跡
	var bullet := _spawn("water")
	assert_true(_trail_of(bullet).top_level, "拖尾必須是 top_level")


func test_拖尾有筆鋒與濃淡() -> void:
	var trail := _trail_of(_spawn("water"))
	assert_not_null(trail.width_curve, "沒有筆鋒就是一根等寬的棍子")
	assert_lt(trail.width_curve.sample(0.0), trail.width_curve.sample(0.75), "尾端要收細")
	assert_not_null(trail.gradient)


func test_拖尾長度受上限約束() -> void:
	var bullet := _spawn("metal")
	var trail := _trail_of(bullet)
	for i in trail.max_points * 3:
		trail.push_sample(Vector2(float(i) * 10.0, 0.0), Vector2.RIGHT, 0.016)

	assert_eq(trail.get_point_count(), trail.max_points, "拖尾不可以無限累積點")


# ---- 命中 ----

func test_命中會炸墨點且拖尾脫離後淡出() -> void:
	var bullet := _spawn("water")
	var trail := _trail_of(bullet)

	bullet._burst()

	assert_ne(trail.get_parent(), bullet, "拖尾要脫離子彈，否則會跟著一起被釋放")
	assert_true(is_instance_valid(trail), "拖尾應該留在場上淡出")

	var found := false
	for child: Node in bullet._get_effect_parent().get_children():
		if child is CPUParticles2D:
			found = true
			break
	assert_true(found, "命中應該炸開墨點")


func test_中性子彈不帶粒子只有一筆墨() -> void:
	var bullet := _spawn("neutral")
	var particles := 0
	for child: Node in bullet.get_children():
		if child is CPUParticles2D:
			particles += 1
	assert_eq(particles, 0, "純墨箭不該有屬性粒子")
	assert_not_null(_trail_of(bullet), "但仍然要有拖尾")
