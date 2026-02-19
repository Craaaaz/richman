extends Node

# 用來儲存所有玩家資訊的字典
# 格式範例: { 1: {"name": "玩家一", "order": 1, "money": 1000}, 28374: {"name": "玩家二", "order": 2, "money": 1000} }
var players = {}

# 玩家順序追蹤
var player_order_counter: int = 1
var player_id_to_order: Dictionary = {}  # 玩家ID到順序的映射
var player_order_to_id: Dictionary = {}  # 順序到玩家ID的映射

# 本機玩家的 ID (由 Multiplayer API 提供)
var my_id = 0

# 遊戲設定（例如：起始資金）
var starting_money = 5000

# 遊戲設定字典（可配置）
var game_settings = {
	"starting_money": 5000,
	"pass_start_bonus": 5000,
	"host_only_settings": true
}

# 設定檔案路徑
const SETTINGS_FILE_PATH = "user://game_settings.cfg"

# 中文玩家名稱對照表
const PLAYER_CHINESE_NAMES: Array[String] = [
	"玩家一",
	"玩家二", 
	"玩家三",
	"玩家四"
]

# 根據玩家順序取得中文名稱
func get_player_chinese_name(order: int) -> String:
	if order >= 1 and order <= PLAYER_CHINESE_NAMES.size():
		return PLAYER_CHINESE_NAMES[order - 1]
	return "玩家" + str(order)

# 根據玩家ID取得中文名稱
func get_player_name_by_id(player_id: int) -> String:
	if player_id_to_order.has(player_id):
		var order = player_id_to_order[player_id]
		return get_player_chinese_name(order)
	return "玩家" + str(player_id)

# 根據玩家順序取得玩家ID
func get_player_id_by_order(order: int) -> int:
	if player_order_to_id.has(order):
		return player_order_to_id[order]
	return -1

# --- 設定檔案管理 ---

# 儲存設定到檔案
func save_settings():
	var config = ConfigFile.new()
	config.set_value("game", "starting_money", game_settings["starting_money"])
	config.set_value("game", "pass_start_bonus", game_settings["pass_start_bonus"])
	var error = config.save(SETTINGS_FILE_PATH)
	if error == OK:
		print("遊戲設定已儲存: ", game_settings)
	else:
		print("儲存設定失敗: ", error)

# 從檔案載入設定
func load_settings():
	var config = ConfigFile.new()
	var error = config.load(SETTINGS_FILE_PATH)
	if error == OK:
		game_settings["starting_money"] = config.get_value("game", "starting_money", 5000)
		game_settings["pass_start_bonus"] = config.get_value("game", "pass_start_bonus", 5000)
		print("遊戲設定已載入: ", game_settings)
	else:
		print("載入設定失敗，使用預設值: ", game_settings)

# 同步遊戲設定 RPC
@rpc("any_peer", "call_local")
func sync_game_settings(settings_dict: Dictionary):
	game_settings = settings_dict.duplicate()
	print("遊戲設定已同步: ", game_settings)
	
	# 更新 starting_money 變數以保持向後兼容
	starting_money = game_settings["starting_money"]
	
	# 更新所有現有玩家的資金至新的起始金額
	var new_starting_money = game_settings["starting_money"]
	for player_id in players:
		# 確保玩家字典有 money 鍵
		if not players[player_id].has("money"):
			players[player_id]["money"] = new_starting_money
			print("為玩家", get_player_name_by_id(player_id), "新增資金鍵: $", new_starting_money)
		else:
			players[player_id]["money"] = new_starting_money
			print("已更新玩家", get_player_name_by_id(player_id), "資金至 $", new_starting_money)
		
		# 通知遊戲場景更新介面即可，不需要在此發送 sync_player_money RPC
		# 因為 sync_game_settings 本身就是一個同步所有人的 RPC
		pass
	
	# 通知遊戲場景更新UI（如果遊戲場景存在）
	_notify_game_scene_settings_changed()

# 添加玩家並分配順序
func add_player(id: int):
	if player_id_to_order.has(id):
		print("玩家已存在：", id)
		return
	
	# 分配順序
	var order = player_order_counter
	player_order_counter += 1
	
	# 更新映射
	player_id_to_order[id] = order
	player_order_to_id[order] = id
	
	# 取得中文名稱
	var chinese_name = get_player_chinese_name(order)
	
	# 儲存玩家資訊
	players[id] = {
		"name": chinese_name,
		"order": order,
		"money": game_settings["starting_money"],
		"position": 0 # 玩家目前在哪個格子（索引）
	}
	
	print("玩家已加入資訊庫：", chinese_name, " (ID: ", id, ", 順序: ", order, ")")

# 移除玩家並重整順序
func remove_player(id: int):
	if not player_id_to_order.has(id):
		return
	
	# 取得被移除玩家的順序
	var removed_order = player_id_to_order[id]
	
	# 移除映射
	player_id_to_order.erase(id)
	player_order_to_id.erase(removed_order)
	players.erase(id)
	
	print("玩家已移除：ID ", id, " (順序: ", removed_order, ")")
	
	# 重整順序：將所有順序大於被移除玩家的順序減1
	var orders_to_update: Array[int] = []
	for order in player_order_to_id.keys():
		if order > removed_order:
			orders_to_update.append(order)
	
	# 排序以便從大到小處理
	orders_to_update.sort()
	
	for order in orders_to_update:
		var player_id = player_order_to_id[order]
		var new_order = order - 1
		
		# 更新映射
		player_id_to_order[player_id] = new_order
		player_order_to_id[new_order] = player_id
		player_order_to_id.erase(order)
		
		# 更新玩家資訊中的名稱
		if players.has(player_id):
			players[player_id]["name"] = get_player_chinese_name(new_order)
			players[player_id]["order"] = new_order
		
		print("玩家順序更新：ID ", player_id, " 從順序 ", order, " 改為 ", new_order)
	
	# 更新計數器
	player_order_counter -= 1

# 取得所有玩家的順序列表（按順序排序）
func get_players_in_order() -> Array[int]:
	var result: Array[int] = []
	
	# 找出最大的順序值
	var max_order = 0
	for order in player_order_to_id:
		if order > max_order:
			max_order = order
	
	# 從1到最大順序遍歷
	for order in range(1, max_order + 1):
		if player_order_to_id.has(order):
			result.append(player_order_to_id[order])
	
	return result

# 取得玩家總數
func get_player_count() -> int:
	return players.size()

# 清除所有玩家資料（用於重新開始遊戲）
func clear_all_players():
	players.clear()
	player_id_to_order.clear()
	player_order_to_id.clear()
	player_order_counter = 1
	print("所有玩家資料已清除")

# 通知遊戲場景設定已變更
func _notify_game_scene_settings_changed():
	get_tree().call_group("game_scene", "on_game_settings_changed")
	print("已通知遊戲場景更新設定")
