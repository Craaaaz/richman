extends Control
class_name DirectionSelector

signal direction_selected(direction: Vector2i)

var btn_up: Button
var btn_down: Button
var btn_left: Button
var btn_right: Button

func _ready():
	# 設定為全螢幕，這樣可以攔截點擊 (或者設為比較小的區域跟隨玩家)
	# 這裡我們設為跟隨玩家的小區域 (150x150)
	custom_minimum_size = Vector2(200, 200)
	size = Vector2(200, 200)
	
	# 中心點偏移 (讓 (0,0) 在中心)
	# 我們不直接改 pivot，而是把按鈕位置相對中心配置
	
	btn_up = _create_arrow_button("Up", Vector2i.UP, Vector2(75, 10))
	btn_down = _create_arrow_button("Down", Vector2i.DOWN, Vector2(75, 150))
	btn_left = _create_arrow_button("Left", Vector2i.LEFT, Vector2(5, 75))
	btn_right = _create_arrow_button("Right", Vector2i.RIGHT, Vector2(145, 75))

func _create_arrow_button(text: String, dir: Vector2i, pos: Vector2) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(50, 40)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(func(): _on_btn_pressed(dir))
	add_child(btn)
	return btn

func _on_btn_pressed(dir: Vector2i):
	direction_selected.emit(dir)

# 根據可行的方向顯示/隱藏按鈕
func show_options(available_directions: Array[Vector2i]):
	btn_up.visible = Vector2i.UP in available_directions
	btn_down.visible = Vector2i.DOWN in available_directions
	btn_left.visible = Vector2i.LEFT in available_directions
	btn_right.visible = Vector2i.RIGHT in available_directions
