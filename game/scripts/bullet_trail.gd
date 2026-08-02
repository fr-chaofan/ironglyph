## 子彈拖尾：一筆正在寫出來的墨。
##
## 近戰的刀氣有多層造型、筆鋒與飛白，遠程原本只是一個 9×6 的實心菱形滑過去——
## 這個元件把同一套水墨思路搬到子彈上。
##
## ⚠️ **必須 `top_level = true`。** 拖尾記錄的是子彈走過的**世界座標**；
## 若跟著父節點的變換走，整條軌跡會隨子彈一起平移旋轉，看起來像一根黏在
## 子彈屁股後面的棍子，而不是留在空中的墨跡。
class_name BulletTrail
extends Line2D

## 拖尾最多保留幾個點
var max_points: int = 16
## 橫向擺動的振幅與頻率（水的波、火的抖）
var wave: float = 0.0
var wave_frequency: float = 3.0

var _age: float = 0.0
var _sample_index: int = 0


func setup(color: Color, trail_width: float, points_count: int, wave_amount: float, frequency: float) -> void:
	# 世界座標，不跟著子彈的變換走
	top_level = true
	max_points = maxi(2, points_count)
	wave = wave_amount
	wave_frequency = frequency

	width = maxf(1.0, trail_width)
	default_color = color
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	joint_mode = Line2D.LINE_JOINT_ROUND
	z_index = 4

	# 筆鋒：頭飽滿、尾收細。points[0] 是最舊的一點，所以曲線是「尾→頭」
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.05))
	curve.add_point(Vector2(0.75, 1.0))
	curve.add_point(Vector2(1.0, 0.9))
	width_curve = curve

	# 濃淡：尾端往紙色化開，就像墨在紙上散掉
	var gradient := Gradient.new()
	gradient.set_color(0, color.lerp(Palette.paper(), 0.85))
	gradient.set_color(1, color)
	self.gradient = gradient


## 每個物理影格記錄一次子彈位置。
func push_sample(world_position: Vector2, direction: Vector2, delta: float) -> void:
	_age += delta
	_sample_index += 1

	var point := world_position
	if wave > 0.0:
		# 沿著行進方向的法線擺動，水波與火舌的抖動都靠它
		var normal := Vector2(-direction.y, direction.x)
		point += normal * sin(_age * wave_frequency * TAU) * wave

	add_point(point)
	while get_point_count() > max_points:
		remove_point(0)


## 子彈消失後拖尾自己淡出，不要跟著瞬間不見——墨跡會留在紙上一會兒。
func fade_and_free(duration: float = 0.18) -> void:
	top_level = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)
