extends Node

func _ready():
	print("=== 測試遊戲設定系統 ===")
	
	# 測試 Global 設定系統
	var global_test = Node.new()
	global_test.set_script(load("res://global.gd"))
	
	# 測試設定載入與保存
	print("1. 測試設定載入...")
	global_test.load_settings()
	print("   載入的設定: ", global_test.game_settings)
	
	# 測試設定修改
	print("2. 測試設定修改...")
	global_test.game_settings["starting_money"] = 10000
	global_test.game_settings["pass_start_bonus"] = 2000
	global_test.save_settings()
	print("   修改後的設定: ", global_test.game_settings)
	
	# 測試設定同步
	print("3. 測試設定同步...")
	var test_settings = {
		"starting_money": 8000,
		"pass_start_bonus": 3000,
		"host_only_settings": true
	}
	global_test.sync_game_settings(test_settings)
	print("   同步後的設定: ", global_test.game_settings)
	
	# 測試玩家資金初始化
	print("4. 測試玩家資金初始化...")
	global_test.add_player(1)
	global_test.add_player(2)
	
	print("   玩家1資金: ", global_test.players[1]["money"])
	print("   玩家2資金: ", global_test.players[2]["money"])
	
	# 驗證資金使用正確的設定值
	assert(global_test.players[1]["money"] == 8000, "玩家1資金應為8000")
	assert(global_test.players[2]["money"] == 8000, "玩家2資金應為8000")
	
	print("=== 測試完成 ===")
	
	# 清理
	global_test.queue_free()