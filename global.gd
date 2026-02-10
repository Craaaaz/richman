extends Node

# 用來儲存所有玩家資訊的字典
# 格式範例: { 1: {"name": "主機", "score": 1000}, 28374: {"name": "玩家2", "score": 1000} }
var players = {}

# 本機玩家的 ID (由 Multiplayer API 提供)
var my_id = 0

# 遊戲設定（例如：起始資金）
var starting_money = 1500

func add_player(id, name):
	players[id] = {
		"name": name,
		"money": starting_money,
		"position": 0 # 玩家目前在哪個格子（索引）
	}
	print("玩家已加入資訊庫：", name)

func remove_player(id):
	players.erase(id)
