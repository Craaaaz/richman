extends Control

# 全域變數引用
var global: Node

# 大富翁連線大廳 (Lobby.gd)
# 用於建立連線、加入遊戲與管理連線狀態

# 預設連線設定
const DEFAULT_PORT = 7777
const MAX_CLIENTS = 4
const GAME_SCENE_PATH = "res://gamescene.tscn" # 遊戲場景路徑

# 網路物件
var peer = ENetMultiplayerPeer.new()

# UI 元件
var main_container: VBoxContainer
var ip_input: LineEdit
var status_label: Label
var host_button: Button
var join_button: Button
var start_game_button: Button # 新增：開始遊戲按鈕

func _ready():
	# 取得全域變數節點
	global = get_node("/root/Global")
	
	# 建立簡易 UI
	_setup_ui()
	
	# 連接網路訊號 (Signal)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _setup_ui():
	# 設定根節點填滿螢幕 (從上次修改繼承，確保佈局正常)
	anchor_right = 1
	anchor_bottom = 1
	
	# 使用 CenterContainer 確保內容在螢幕正中央
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)
	
	main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 15)
	center_container.add_child(main_container)
	
	# 標題
	var title = Label.new()
	title.text = "大富翁多人連線大廳"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)
	
	# IP 輸入欄
	var ip_label = Label.new()
	ip_label.text = "主機 IP 位址 (Host 不需輸入):"
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(ip_label)
	
	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1" # 預設本機
	ip_input.placeholder_text = "輸入 Host IP"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER # 文字置中
	ip_input.custom_minimum_size = Vector2(300, 40) # 稍微加寬加高
	main_container.add_child(ip_input)
	
	# 按鈕容器 (水平排列 Host/Join)
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)
	main_container.add_child(btn_container)
	
	# 主持遊戲按鈕
	host_button = Button.new()
	host_button.text = "建立主機 (Host)"
	host_button.pressed.connect(_on_host_pressed)
	btn_container.add_child(host_button)
	
	# 加入遊戲按鈕
	join_button = Button.new()
	join_button.text = "加入遊戲 (Join)"
	join_button.pressed.connect(_on_join_pressed)
	btn_container.add_child(join_button)
	
	# 新增：開始遊戲按鈕 (垂直堆疊在 Host/Join 下方)
	start_game_button = Button.new()
	start_game_button.text = "開始遊戲"
	start_game_button.pressed.connect(_on_start_game_pressed)
	start_game_button.disabled = true # 預設禁用
	start_game_button.custom_minimum_size = Vector2(200, 50)
	main_container.add_child(start_game_button)
	
	# 狀態顯示
	status_label = Label.new()
	status_label.text = "狀態: 等待操作..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.7, 0.7, 0.7)
	main_container.add_child(status_label)

# --- 按鈕事件 ---

func _on_host_pressed():
	status_label.text = "正在建立伺服器..."
	var error = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if error != OK:
		status_label.text = "建立失敗: " + str(error)
		return
		
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	
	# 清除之前的玩家資料
	global.clear_all_players()
	
	# Host 加入自己 (ID 1)
	_on_player_connected(1) 
	
	status_label.text = "伺服器已建立！等待玩家加入...\n(您的 IP: " + _get_local_ip() + ")"
	status_label.modulate = Color.GREEN
	_disable_lobby_buttons()
	_check_game_start_state()
	
func _on_join_pressed():
	var ip = ip_input.text
	if ip == "":
		status_label.text = "請輸入 IP 位址！"
		return
		
	status_label.text = "正在連線至 " + ip + "..."
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		status_label.text = "連線請求失敗: " + str(error)
		return
		
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_disable_lobby_buttons()

func _on_start_game_pressed():
	# 只有 Host (ID=1) 可以開始遊戲
	if multiplayer.is_server() and multiplayer.get_unique_id() == 1:
		# 廣播所有玩家準備好，並切換場景
		rpc("start_game")
	else:
		# 如果 Client 點了，應該不會發生，因為按鈕預設禁用
		status_label.text = "只有主機可以開始遊戲。"
		status_label.modulate = Color.RED


# --- 網路事件回調 ---

func _on_player_connected(id):
	# Server 端觸發
	if multiplayer.is_server():
		# 在 global 中註冊玩家並分配順序
		global.add_player(id)
		
		# 取得玩家中文名稱
		var player_name = global.get_player_name_by_id(id)
		
		# 刷新狀態標籤，顯示總玩家數和中文名稱
		var peer_count = multiplayer.get_peers().size() + 1 # 包含 Host 自己
		status_label.text = player_name + " 已連線 (ID: %d)。總人數: %d/%d" % [id, peer_count, MAX_CLIENTS]
		status_label.modulate = Color.GREEN
		
		# 步驟1：同步新玩家的順序給所有現有客戶端
		rpc("sync_player_order", id, global.player_id_to_order[id])
		
		# 步驟2：同步所有現有玩家的順序給新連接的客戶端
		# 收集所有玩家的順序映射
		var all_player_orders: Dictionary = {}
		for player_id in global.player_id_to_order:
			all_player_orders[player_id] = global.player_id_to_order[player_id]
		
		print("向新玩家 ", id, " 同步所有玩家順序：", all_player_orders)
		rpc_id(id, "sync_all_player_orders", all_player_orders)
		
		_check_game_start_state()
	# Client 端觸發 (如果 Server 廣播有人連線，Client 會收到這個訊號，但通常我們只在 Server 端處理人數變動)
	# 這裡我們主要關注 Server 端的廣播狀態更新

func _on_player_disconnected(id):
	# Server 端觸發
	if multiplayer.is_server():
		# 取得玩家中文名稱
		var player_name = global.get_player_name_by_id(id)
		
		# 從 global 中移除玩家
		global.remove_player(id)
		
		var peer_count = multiplayer.get_peers().size() + 1
		status_label.text += "\n" + player_name + " 離開 (ID: " + str(id) + ")。總人數: %d/%d" % [peer_count, MAX_CLIENTS]
		_check_game_start_state()

func _on_connected_ok():
	# Client 端成功連上 Server 後觸發
	status_label.text = "連線成功！已加入遊戲。"
	status_label.modulate = Color.GREEN

func _on_connected_fail():
	# Client 端連線失敗觸發
	status_label.text = "連線失敗，請檢查 IP 或防火牆。"
	status_label.modulate = Color.RED
	_reset_ui()

func _on_server_disconnected():
	# Server 關閉或斷線
	status_label.text = "與伺服器斷開連線。"
	status_label.modulate = Color.RED
	_reset_ui()
	
# --- 玩家順序同步 RPC ---

@rpc("any_peer", "call_local")
func sync_player_order(player_id: int, order: int):
	# 同步單一玩家順序資訊到所有客戶端
	print("同步玩家順序：ID ", player_id, " -> 順序 ", order)
	
	# 更新 global 中的玩家順序映射
	global.player_id_to_order[player_id] = order
	global.player_order_to_id[order] = player_id
	
	# 更新玩家資訊中的名稱
	if not global.players.has(player_id):
		global.players[player_id] = {}
	
	global.players[player_id]["name"] = global.get_player_chinese_name(order)
	global.players[player_id]["order"] = order
	
	print("玩家順序已同步：", global.get_player_name_by_id(player_id), " (ID: ", player_id, ", 順序: ", order, ")")

@rpc("any_peer", "call_local")
func sync_all_player_orders(player_orders: Dictionary):
	# 批量同步所有玩家順序資訊到指定客戶端
	# player_orders 格式: {player_id: order, ...}
	print("批量同步所有玩家順序：", player_orders)
	
	# 清除現有玩家順序映射
	global.player_id_to_order.clear()
	global.player_order_to_id.clear()
	global.players.clear()
	
	# 更新所有玩家順序映射
	for player_id in player_orders:
		var order = player_orders[player_id]
		global.player_id_to_order[player_id] = order
		global.player_order_to_id[order] = player_id
		
		# 更新玩家資訊
		global.players[player_id] = {
			"name": global.get_player_chinese_name(order),
			"order": order,
			"money": global.starting_money,
			"position": 0
		}
	
	# 更新計數器：找出最大的順序值加1
	var max_order = 0
	for order in player_orders.values():
		if order > max_order:
			max_order = order
	global.player_order_counter = max_order + 1
	
	print("所有玩家順序批量同步完成，共 ", player_orders.size(), " 名玩家")
	for player_id in player_orders:
		print("  - ", global.get_player_name_by_id(player_id), " (ID: ", player_id, ", 順序: ", player_orders[player_id], ")")

# --- 遊戲開始邏輯 (RPC) ---

@rpc("any_peer", "call_local")
func start_game():
	# 此 RPC 在所有成功連線的客戶端上執行
	if multiplayer.is_server():
		# Host 切換場景
		print("Host: Starting game, changing scene.")
		get_tree().change_scene_to_file(GAME_SCENE_PATH)
	else:
		# Client 切換場景
		print("Client: Starting game, changing scene.")
		get_tree().change_scene_to_file(GAME_SCENE_PATH)
	
# --- 輔助功能 ---

func _disable_lobby_buttons():
	host_button.disabled = true
	join_button.disabled = true
	ip_input.editable = false

func _enable_lobby_buttons():
	host_button.disabled = false
	join_button.disabled = false
	ip_input.editable = true
	start_game_button.disabled = true # 確保開始按鈕在重置時禁用

func _reset_ui():
	_enable_lobby_buttons()
	multiplayer.multiplayer_peer = null # 清除 peer
	status_label.text = "狀態: 等待操作..."
	status_label.modulate = Color(0.7, 0.7, 0.7)
	
func _check_game_start_state():
	# 只有 Host 才能啟用開始按鈕
	if multiplayer.is_server() and multiplayer.get_unique_id() == 1:
		# 獲取總玩家數 (Peer Count + Host 自己)
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			var current_players = multiplayer.get_peers().size() + 1
			
			if current_players >= 2 and current_players <= MAX_CLIENTS:
				start_game_button.disabled = false
				status_label.text = "準備就緒！總人數: %d/%d。按 '開始遊戲'。" % [current_players, MAX_CLIENTS]
			else:
				start_game_button.disabled = true
				status_label.text = "等待玩家加入... (目前人數: %d/%d)" % [current_players, MAX_CLIENTS]
		else:
			start_game_button.disabled = true # 應在 Host 建立後保證 multiplayer_peer 存在
	else:
		# Client 端無法控制開始按鈕，保持禁用
		start_game_button.disabled = true

func _get_local_ip():
	# 嘗試取得本機 IP 以顯示給 Host 看
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
	return "無法取得區域網路 IP"

func _input(event):
	# 判斷是否按下 F11 鍵
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
