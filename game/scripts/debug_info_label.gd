## 執行期環境資訊（僅供 test_room.tscn 手動驗證用）
##
## 把「渲染器是不是 Forward+」從「在編輯器UI裡找一個下拉選單」變成「按F5讀一行字」。
## 編輯器裡的下拉選單顯示的是**設定值**，這裡顯示的是**實際跑起來用的**，兩者可能不同
## ——驅動有問題時 Godot 會靜默退回軟體渲染。
extends Label


func _ready() -> void:
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	var adapter := RenderingServer.get_video_adapter_name()
	var api := RenderingServer.get_video_adapter_api_version()

	var lines := [
		"渲染器：%s" % method,
		"顯示卡：%s" % adapter,
		"圖形API：%s" % api,
	]
	text = "\n".join(lines)

	# Forward+ 走 Vulkan。退回 Compatibility 代表驅動有問題，畫面會很卡。
	if method == "forward_plus":
		add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		text += "\n⚠️ 非 Forward+，請檢查顯示卡驅動"


func _process(_delta: float) -> void:
	# FPS 掉到個位數通常就是退回軟體渲染了
	var base: String = text.split("\nFPS")[0]
	text = "%s\nFPS：%d" % [base, Engine.get_frames_per_second()]
