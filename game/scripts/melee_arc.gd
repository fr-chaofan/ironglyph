## 揮擊視覺：五行之呼吸。
##
## 本節點**自己就是最核心的那一筆墨**（`Line2D`），字核的一根真實筆畫；
## 屬性刀氣是掛在它底下的數層 `Line2D`，纏在筆畫周圍。
## 「核心是字、氣在字外」——這是「字界」世界觀在特效上的直接表達。
##
## 每個屬性**造型本身就不一樣**，不是同一條線換顏色：
## 水＝翻卷的浪、火＝上飄的舌、金＝銳利折線、木＝抽枝、土＝碎裂岩塊、中性＝純墨。
## 造型參數全在 `data/element_vfx.json`，調整不需要動程式碼——
## 用 `scenes/vfx_showcase.tscn` 六種並排循環播放來對照著調。
##
## 水墨質感靠三件事，都不需要 shader 或素材：
## - `width_curve` 兩端收細 → 起筆收筆的提按
## - `gradient` 沿線由濃到淡 → 墨色濃淡
## - `gap_ratio` 把外層打斷成數段 → 飛白（乾筆的白絲）
##
## ⚠️ 不是所有字都有筆畫資料。「刂」就**不在** Make Me a Hanzi 資料集裡，
## `HanziData.get_medians()` 會回傳空陣列，此時退回一段幾何弧線——
## 與 `HanziSprite.shatter_and_die()` 缺資料時退回整體淡出是同一個原則。
class_name MeleeArc
extends Line2D

const DATA_PATH := "res://data/element_vfx.json"
## Make Me a Hanzi 的字身框大小；y 軸朝上，與螢幕相反
const _EM_SIZE := 1024.0
## 平揮／下劈掃過的角度（弧度）
const _SWEEP := deg_to_rad(110.0)
## 上挑掃過的角度。比平揮窄，這樣整段弧線才留在斜前上方那一區，
## 不會掃過頭跑到反方向去。
const _SWEEP_UP := deg_to_rad(80.0)
## 上挑弧線的中心方向（斜前上方）
const _UP_ANGLE := deg_to_rad(-50.0)
## 造型取樣點數。太少折線感明顯，太多沒有視覺差別只是浪費。
const _SAMPLES := 24

static var _vfx_data: Dictionary = {}

var _element: String = "neutral"


static func load_vfx_data() -> Dictionary:
	if not _vfx_data.is_empty():
		return _vfx_data
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("MeleeArc: 無法開啟 %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MeleeArc: %s 解析失敗" % DATA_PATH)
		return {}
	_vfx_data = parsed
	return _vfx_data


## 取得某屬性的造型參數，缺項自動補上 defaults。
static func get_vfx_profile(element: String) -> Dictionary:
	var data := load_vfx_data()
	var defaults: Dictionary = data.get("defaults", {})
	var profile: Dictionary = defaults.duplicate(true)
	var override: Variant = data.get(element, {})
	if typeof(override) == TYPE_DICTIONARY:
		for key: String in (override as Dictionary):
			if key.begins_with("_"):
				continue
			profile[key] = (override as Dictionary)[key]
	return profile


## 生成一道揮擊刀氣並自動釋放。
##
## `offset` 是**相對於 `parent` 的局部座標**（判定框中心），`facing` ±1，
## `downward` 為真時整段往下掃。
##
## ⚠️ **位置一定要在 `add_child()` 之後才設，而且設的是 `position` 不是 `global_position`。**
## 節點還沒進場景樹時沒有父變換，`global_position` 的 setter 會退化成 `set_position()`
## ——世界座標被當成局部座標，加進樹後變成「父節點位置 ＋ 世界座標」，偏移量直接翻倍。
static func spawn(
	parent: Node,
	offset: Vector2,
	facing: float,
	glyph: String,
	color: Color,
	duration: float,
	reach: float,
	vertical: int = 0,
	element: String = "neutral"
) -> MeleeArc:
	if parent == null or not is_instance_valid(parent):
		return null

	var profile := get_vfx_profile(element)
	var base_points := _build_points(glyph, reach * float(profile.get("trail_scale", 1.0)))

	var arc := MeleeArc.new()
	arc._element = element
	arc.points = base_points
	arc.z_index = 6
	_style_line(arc, float(profile.get("core_width", 9.0)), color, 1.0)

	parent.add_child(arc)
	arc.position = offset
	arc._build_swath(profile, color, reach)
	arc._spawn_particles(profile, color, facing, vertical)
	arc._animate(facing, duration, vertical)
	return arc


## 屬性刀氣：數層造型過的曲線纏在核心筆畫外。
## 由內而外越寬越淡，構成「一片氣」而不是「一根線」。
func _build_swath(profile: Dictionary, color: Color, reach: float) -> void:
	var layers := maxi(0, int(profile.get("layers", 3)))
	if layers <= 0 or points.size() < 2:
		return

	var swath := float(profile.get("swath_width", 30.0))
	for i in layers:
		# t: 0 = 貼著核心筆畫，1 = 最外層
		var t := float(i + 1) / float(layers)
		var layer := Line2D.new()
		layer.points = _modulate_shape(points, profile, t, swath, i)
		layer.z_index = -1 - i  # 外層壓在核心筆畫底下，墨線始終在最上面
		_style_line(
			layer,
			lerpf(float(profile.get("core_width", 9.0)), swath, t),
			color,
			lerpf(0.55, 0.12, t)
		)
		add_child(layer)

	for branch: Line2D in _build_branches(profile, color, reach):
		add_child(branch)


## 把基準曲線依屬性造型調變。這裡是「水看起來像水、火看起來像火」的所在。
func _modulate_shape(
	base: PackedVector2Array,
	profile: Dictionary,
	t: float,
	swath: float,
	layer_index: int
) -> PackedVector2Array:
	var amplitude := float(profile.get("amplitude", 0.0))
	var frequency := float(profile.get("frequency", 2.0))
	var jitter := float(profile.get("jitter", 0.0))
	var drift := float(profile.get("drift", 0.0))
	var spike := float(profile.get("spike", 0.0))
	var gap_ratio := clampf(float(profile.get("gap_ratio", 0.0)), 0.0, 0.9)

	var resampled := _resample(base, _SAMPLES)
	var out := PackedVector2Array()
	var count := resampled.size()
	# 每層錯開相位，層與層之間才不會整齊得像列印出來的
	var phase := float(layer_index) * 0.8

	for i in count:
		var u := float(i) / float(maxi(1, count - 1))
		var point := resampled[i]
		var normal := _normal_at(resampled, i)

		var push := swath * t * 0.5
		if amplitude > 0.0:
			push += sin(u * frequency * TAU + phase) * amplitude * t
		if spike > 0.0:
			# 折線：只有少數幾個尖角，其餘平直——刃光與雷的銳利感來自「稀疏」
			push += (1.0 if int(u * 5.0 + phase) % 2 == 0 else -1.0) * spike * t * 0.5
		if jitter > 0.0:
			push += _deterministic_noise(i, layer_index) * jitter * t

		var moved := point + normal * push
		if drift != 0.0:
			# 火焰越到尾端飄得越高
			moved.y += drift * t * u

		out.append(moved)

	if gap_ratio > 0.0:
		out = _apply_gaps(out, gap_ratio, layer_index)
	return out


## 飛白／斷口：把線打斷成數段。乾筆掃過紙面就是這種斷續的白絲。
## Line2D 沒有「多段」概念，這裡改成抽掉中間一段點，讓線看起來裂開。
func _apply_gaps(source: PackedVector2Array, gap_ratio: float, seed_index: int) -> PackedVector2Array:
	var count := source.size()
	if count < 6:
		return source

	var gap_length := maxi(1, int(float(count) * gap_ratio * 0.5))
	var start := 1 + (seed_index * 3 + 2) % maxi(1, count - gap_length - 2)
	var out := PackedVector2Array()
	for i in count:
		if i >= start and i < start + gap_length:
			continue
		out.append(source[i])
	return out


## 木屬性的抽枝：從主線上長出幾根短枝。
func _build_branches(profile: Dictionary, color: Color, reach: float) -> Array[Line2D]:
	var branches: Array[Line2D] = []
	var count := int(profile.get("branches", 0))
	if count <= 0 or points.size() < 3:
		return branches

	var length := float(profile.get("branch_length", 0.35)) * reach
	var resampled := _resample(points, _SAMPLES)
	for i in count:
		var at := int(lerpf(2.0, float(resampled.size() - 2), float(i + 1) / float(count + 1)))
		var root := resampled[at]
		var normal := _normal_at(resampled, at)
		var side := 1.0 if i % 2 == 0 else -1.0
		var tip := root + normal * length * side + Vector2(0.0, -length * 0.25)

		var branch := Line2D.new()
		branch.points = PackedVector2Array([root, root.lerp(tip, 0.55), tip])
		branch.z_index = -1
		_style_line(branch, float(profile.get("core_width", 9.0)) * 0.5, color, 0.45)
		branches.append(branch)
	return branches


## 統一的水墨筆觸樣式：提按（兩端收細）＋ 濃淡（沿線變透明）。
static func _style_line(line: Line2D, width: float, color: Color, alpha: float) -> void:
	line.width = maxf(1.5, width)
	line.default_color = Color(color.r, color.g, color.b, alpha)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND

	# 提按：起筆與收筆收細，中段最飽滿
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.05))
	line.width_curve = curve

	# 濃淡：墨在紙上由濃到淡
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, alpha))
	gradient.set_color(1, Color(color.r, color.g, color.b, alpha * 0.15))
	line.gradient = gradient


## 屬性粒子點綴：水花／火星／塵屑。用 CPUParticles2D 而不是 GPU 版本——
## 全部參數都能在程式碼裡設定，不必額外準備 ParticleProcessMaterial 資源。
func _spawn_particles(profile: Dictionary, color: Color, facing: float, vertical: int) -> void:
	var amount := int(profile.get("particles", 0))
	if amount <= 0:
		return

	var particles := CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = 0.45
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 26.0
	particles.direction = Vector2(0.0, float(vertical)) if vertical != 0 else Vector2(facing, -0.25)
	particles.spread = float(profile.get("particle_spread", 60.0))
	particles.initial_velocity_min = float(profile.get("particle_speed", 130.0)) * 0.5
	particles.initial_velocity_max = float(profile.get("particle_speed", 130.0))
	particles.gravity = Vector2(0.0, 220.0)
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.6
	particles.color = color
	particles.z_index = 5
	particles.emitting = true
	add_child(particles)


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

	# 以筆畫自身的外框正規化到 reach，不同字的筆畫長度差很多，
	# 不正規化的話「令」與「劍」的揮擊會差好幾倍大小
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
	var result := PackedVector2Array()
	for point: Array in longest:
		result.append(Vector2(
			(float(point[0]) - center.x) * scale_factor,
			# y 取負號：字身框 y 朝上，螢幕 y 朝下
			-(float(point[1]) - center.y) * scale_factor
		))
	return result


## 沒有筆畫資料時的退路：一段圓弧
static func _fallback_arc(reach: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := reach * 0.75
	for i in 9:
		var angle := lerpf(-_SWEEP * 0.5, _SWEEP * 0.5, float(i) / 8.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


## 把任意點數的折線重新取樣成固定點數，造型調變才有穩定的解析度。
static func _resample(source: PackedVector2Array, count: int) -> PackedVector2Array:
	if source.size() < 2 or count < 2:
		return source

	var lengths := PackedFloat32Array()
	var total := 0.0
	lengths.append(0.0)
	for i in range(1, source.size()):
		total += source[i].distance_to(source[i - 1])
		lengths.append(total)
	if total <= 0.0:
		return source

	var out := PackedVector2Array()
	var cursor := 1
	for i in count:
		var target := total * float(i) / float(count - 1)
		while cursor < lengths.size() - 1 and lengths[cursor] < target:
			cursor += 1
		var span := lengths[cursor] - lengths[cursor - 1]
		var ratio := 0.0 if span <= 0.0 else (target - lengths[cursor - 1]) / span
		out.append(source[cursor - 1].lerp(source[cursor], ratio))
	return out


## 曲線在某點的法線方向（往哪一側推開）
static func _normal_at(points_array: PackedVector2Array, index: int) -> Vector2:
	var count := points_array.size()
	if count < 2:
		return Vector2.UP
	var previous := points_array[maxi(0, index - 1)]
	var next := points_array[mini(count - 1, index + 1)]
	var tangent := next - previous
	if tangent.length() < 0.001:
		return Vector2.UP
	return Vector2(-tangent.y, tangent.x).normalized()


## 確定性雜訊。用 randf() 的話同一次揮擊每幀重算會抖動，
## 而且測試無法斷言形狀。
static func _deterministic_noise(index: int, salt: int) -> float:
	var value := sin(float(index) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0


func _animate(facing: float, duration: float, vertical: int) -> void:
	var sign_facing := signf(facing)
	if is_zero_approx(sign_facing):
		sign_facing = 1.0

	# 往左揮時鏡像的是**軌跡**不是字形本身，不違反「漢字不可水平鏡像」的鐵律——
	# 這裡畫的是一道揮擊光跡，不是要讓玩家讀出是哪個字。
	# ⚠️ 下劈是左右橫掃、與朝向無關，所以不鏡像；平揮與上挑都要跟著朝向。
	scale.x = 1.0 if vertical == 1 else sign_facing

	# 三種揮法的弧線中心與掃描寬度
	var base_angle := 0.0
	var sweep := _SWEEP
	if vertical == 1:
		base_angle = PI * 0.5
	elif vertical == -1:
		# 斜前上方。鏡像會把角度一起翻掉，所以基準角要跟著朝向變號
		base_angle = _UP_ANGLE * sign_facing
		sweep = _SWEEP_UP

	# ⚠️ **鏡像的同時，掃描方向也必須跟著反過來。**
	# 螢幕 y 軸朝下，所以角度由負掃到正 = 由上往下劈。形狀被 scale.x = -1 鏡像後，
	# 同一組角度序列會變成由下往上「撩」——看起來就不是劈了。
	# 只翻形狀不翻掃描方向，是鏡像動畫最容易漏掉的一半。
	# 平揮由上往下劈、上挑由下往上撩、下劈左右橫掃
	var sweep_dir := sign_facing
	if vertical == 1:
		sweep_dir = 1.0
	elif vertical == -1:
		sweep_dir = -sign_facing

	rotation = base_angle - sweep * 0.5 * sweep_dir
	modulate.a = 0.0

	var visible_time := maxf(duration, 0.05)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation", base_angle + sweep * 0.5 * sweep_dir, visible_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, visible_time * 0.25)
	tween.chain().tween_property(self, "modulate:a", 0.0, visible_time * 0.75)
	tween.chain().tween_callback(queue_free)
