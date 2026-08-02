## 把一個場景跑起來、等幾幀、截圖存檔（開發用工具，不進遊戲）。
##
## 無畫面環境（WSL）看不到畫面，但 Godot 本身是 Windows 原生程式，
## 可以讓它自己把 viewport 存成 PNG，再回頭看那張圖。
extends SceneTree

var _frames_left: int = 45
var _out_path: String = "res://_shot.png"
var _done: bool = false


func _initialize() -> void:
	var target: String = "res://scenes/vfx_showcase.tscn"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("scene="):
			target = arg.trim_prefix("scene=")
		elif arg.begins_with("out="):
			_out_path = arg.trim_prefix("out=")
		elif arg.begins_with("frames="):
			_frames_left = int(arg.trim_prefix("frames="))

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
	var error := image.save_png(_out_path)
	print("screenshot: saved %s size=%s err=%d" % [_out_path, image.get_size(), error])
	return true
