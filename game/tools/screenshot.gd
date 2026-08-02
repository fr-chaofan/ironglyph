## 把一個場景跑起來、等幾幀、截圖存檔（開發用工具，不進遊戲）。
##
## 無畫面環境（WSL）看不到畫面，但 Godot 本身是 Windows 原生程式，
## 可以讓它自己把 viewport 存成 PNG，再回頭看那張圖。
extends SceneTree

var _frames_left: int = 45
var _out_path: String = "res://_shot.png"
var _done: bool = false
var _region := Rect2i()
var _zoom: int = 1


func _initialize() -> void:
	var target: String = "res://scenes/vfx_showcase.tscn"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("scene="):
			target = arg.trim_prefix("scene=")
		elif arg.begins_with("out="):
			_out_path = arg.trim_prefix("out=")
		elif arg.begins_with("frames="):
			_frames_left = int(arg.trim_prefix("frames="))
		elif arg.begins_with("region="):
			# region=x,y,w,h — 裁一塊出來，方便看細節
			var parts := arg.trim_prefix("region=").split(",")
			if parts.size() == 4:
				_region = Rect2i(
					int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
				)
		elif arg.begins_with("zoom="):
			_zoom = int(arg.trim_prefix("zoom="))

	print("screenshot: loading ", target)
	var packed := load(target) as PackedScene
	if packed == null:
		printerr("載不到場景：", target)
		quit(1)
		return
	root.add_child(packed.instantiate())
	print("screenshot: scene added")


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames_left -= 1
	if _frames_left > 0:
		return false

	_done = true
	var image := root.get_texture().get_image()
	if image == null:
		printerr("拿不到 viewport 影像")
		return true

	if _region.size.x > 0 and _region.size.y > 0:
		image = image.get_region(_region)
	if _zoom > 1:
		# 最近鄰放大，看得清像素邊界
		image.resize(
			image.get_width() * _zoom, image.get_height() * _zoom, Image.INTERPOLATE_NEAREST
		)
	var error := image.save_png(_out_path)
	print("screenshot: saved %s size=%s err=%d" % [_out_path, image.get_size(), error])
	return true
