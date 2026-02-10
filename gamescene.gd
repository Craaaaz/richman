extends Control

# 骰子系統
var rng = RandomNumberGenerator.new()
var dice_button: Button
var dice_value: int = 0

func _ready():
	# 取得骰子按鈕
	dice_button = get_node("DiceButton")
	# 初始化隨機數生成器
	rng.randomize()
	# 連接按鈕信號
	dice_button.pressed.connect(_on_dice_button_pressed)
	# 初始化按鈕文字
	_update_button_text()

func _on_dice_button_pressed():
	# 擲骰子 (1-6)
	dice_value = rng.randi_range(1, 6)
	print("擲骰子: ", dice_value)
	_update_button_text()

func _update_button_text():
	# 更新按鈕文字顯示骰子點數
	dice_button.text = "骰子\n" + str(dice_value)