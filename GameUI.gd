extends Control
class_name GameUI

signal roll_dice_requested

var turn_label: Label
var dice_button: Button
var result_label: Label
var money_label: Label

func _ready():
	# 全螢幕佈局
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # 讓點擊穿透到下面的地圖(如果有的話)
	
	# 建立左下角的資金顯示容器
	var money_container = PanelContainer.new()
	money_container.layout_mode = 1
	money_container.anchors_preset = Control.PRESET_BOTTOM_LEFT
	money_container.offset_left = 20
	money_container.offset_bottom = -20
	money_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(money_container)
	
	money_label = Label.new()
	money_label.text = "資金: $15,000"
	money_label.add_theme_font_size_override("font_size", 24)
	money_label.add_theme_color_override("font_color", Color.GOLD)
	money_container.add_child(money_label)
	
	# 建立右下角的容器
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_END
	# 設定錨點在右下
	container.layout_mode = 1 # Anchors Layout
	container.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	container.offset_left = -200 # 寬度
	container.offset_top = -200 # 高度
	container.offset_right = -20 # 右邊距
	container.offset_bottom = -20 # 下邊距
	container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	add_child(container)
	
	# 1. 回合資訊
	turn_label = Label.new()
	turn_label.text = "等待遊戲開始..."
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_label.add_theme_font_size_override("font_size", 24)
	turn_label.add_theme_color_override("font_outline_color", Color.BLACK)
	turn_label.add_theme_constant_override("outline_size", 4)
	container.add_child(turn_label)
	
	# 2. 骰子結果顯示
	result_label = Label.new()
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 64)
	result_label.add_theme_color_override("font_color", Color.YELLOW)
	result_label.add_theme_color_override("font_outline_color", Color.BLACK)
	result_label.add_theme_constant_override("outline_size", 8)
	container.add_child(result_label)
	
	# 3. 骰子按鈕
	dice_button = Button.new()
	dice_button.text = "擲骰子 (Roll)"
	dice_button.custom_minimum_size = Vector2(0, 60)
	dice_button.pressed.connect(_on_dice_pressed)
	dice_button.disabled = true # 預設停用
	container.add_child(dice_button)

func _on_dice_pressed():
	roll_dice_requested.emit()
	dice_button.disabled = true # 按下後暫時鎖定

# 更新回合顯示文字
func update_turn_info(text: String):
	turn_label.text = text

# 設定骰子按鈕是否可用
func set_dice_enabled(enabled: bool):
	dice_button.disabled = !enabled
	if enabled:
		dice_button.text = "點擊擲骰子！"
		dice_button.modulate = Color.WHITE
	else:
		dice_button.text = "等待其他玩家..."
		dice_button.modulate = Color(0.7, 0.7, 0.7, 0.5)

# 顯示骰子結果動畫效果 (簡單版)
func show_dice_result(number: int):
	result_label.text = str(number)
	# 簡單的彈跳動畫
	var tween = create_tween()
	result_label.scale = Vector2(0.5, 0.5)
	tween.tween_property(result_label, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(result_label, "scale", Vector2(1.0, 1.0), 0.1)

# 更新資金顯示
func update_money_display(amount: int):
	money_label.text = "資金: $" + str(amount)
	
	# 簡單閃爍效果
	var tween = create_tween()
	money_label.modulate = Color.RED
	tween.tween_property(money_label, "modulate", Color.WHITE, 0.3)
