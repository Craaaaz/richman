extends Control

# 大富翁連線大廳 (Lobby.gd) - 全程式碼生成版
# 這裡包含了 UI 的建立與網路邏輯

# --- [遊戲設定] ---
const DEFAULT_PORT = 7777
const MAX_CLIENTS = 4

# --- [資源載入] ---
const SiteScript = preload("res://Site.gd")
const PlayerScript = preload("res://Player.gd")
const GameUIScript = preload("res://GameUI.gd")
const DirectionSelectorScript = preload("res://DirectionSelector.gd")
const MapEditorScript = preload("res://MapEditor.gd")
const VenueConfig = preload("res://Venue_configuration.gd") # 用於讀取預設地圖

# --- [UI 外觀設定] ---
const UI_PADDING = 20          # 邊距
const BTN_HEIGHT = 50          # 按鈕高度
const INPUT_WIDTH = 300        # 輸入框寬度
const GAP_SIZE = 60            # 元件之間的垂直間距

# 變數宣告
var peer = ENetMultiplayerPeer.new()
var main_container: VBoxContainer
var ip_input: LineEdit
var status_label: Label
var host_button: Button
var join_button: Button
var start_game_button: Button
var map_editor_button: Button

# 遊戲狀態變數
var site_instance: Site
var game_ui_instance: GameUI
var direction_selector_instance: DirectionSelector
var map_editor_instance: MapEditor
var game_started = false
var connected_peer_ids = []

# 地圖數據變數
var current_map_data: Array = []

# 回合系統變數
var turn_order = []
var current_turn_index = -1
var moving_player_steps_remaining = 0
var moving_player_id = 0

func _ready():
	_setup_ui()
	
	# 連接網路訊號
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _setup_ui():
	# 1. 設定背景/整體佈局
	# set_anchors_and_offsets_preset 會同時設定錨點並將偏移量歸零，確保完全填滿視窗
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# 使用 CenterContainer 來確保內容絕對置中
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)
	
	# 2. 建立垂直容器 (VBoxContainer)
	main_container = VBoxContainer.new()
	main_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_theme_constant_override("separation", GAP_SIZE)
	center_container.add_child(main_container)
	
	# 3. 建立標題
	var title = Label.new()
	title.text = "大富翁多人連線"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = Color(1, 0.8, 0.2) # 金黃色
	main_container.add_child(title)
	
	# 4. 建立 IP 輸入欄
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "請輸入 Host IP (例如 127.0.0.1)"
	ip_input.text = "127.0.0.1"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_input.custom_minimum_size = Vector2(INPUT_WIDTH, BTN_HEIGHT)
	main_container.add_child(ip_input)
	
	# 5. 建立按鈕容器
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)
	main_container.add_child(btn_container)
	
	# 6. 建立按鈕
	host_button = _create_styled_button("建立主機 (Host)")
	host_button.pressed.connect(_on_host_pressed)
	btn_container.add_child(host_button)
	
	join_button = _create_styled_button("加入遊戲 (Join)")
	join_button.pressed.connect(_on_join_pressed)
	btn_container.add_child(join_button)
	
	# 新增：開始遊戲按鈕 (預設隱藏，只有 Host 看得到)
	start_game_button = _create_styled_button("開始遊戲")
	start_game_button.modulate = Color(0.2, 1.0, 0.4) # 綠色
	start_game_button.pressed.connect(_on_start_game_pressed)
	start_game_button.hide()
	btn_container.add_child(start_game_button)
	
	# 新增：地圖編輯按鈕 (預設隱藏，只有 Host 看得到)
	map_editor_button = _create_styled_button("編輯地圖 (MAP)")
	map_editor_button.modulate = Color(1.0, 0.6, 0.2) # 橘色
	map_editor_button.pressed.connect(_on_map_editor_pressed)
	map_editor_button.hide()
	btn_container.add_child(map_editor_button)
	
	# 7. 建立狀態標籤
	status_label = Label.new()
	status_label.text = "準備就緒..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.7, 0.7, 0.7) # 灰色
	main_container.add_child(status_label)

# [輔助函式] 統一建立按鈕樣式
func _create_styled_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, BTN_HEIGHT)
	return btn

# --- 按鈕事件邏輯 ---

func _on_host_pressed():
	status_label.text = "正在建立伺服器..."
	
	# 重置 peer 以防萬一
	if peer:
		peer.close()
	peer = ENetMultiplayerPeer.new()
	
	var error = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if error != OK:
		status_label.text = "建立失敗 (錯誤碼 " + str(error) + ")\n可能連接埠 " + str(DEFAULT_PORT) + " 被佔用"
		status_label.modulate = Color.RED
		return
		
	# 確保 host 實例存在再進行壓縮設定
	if peer.host:
		peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
		
	multiplayer.multiplayer_peer = peer
	status_label.text = "伺服器建立成功！\nIP: " + _get_local_ip()
	status_label.modulate = Color.GREEN
	_disable_buttons()
	
	# Host 才能看到地圖編輯按鈕
	map_editor_button.show()
	
	# Host 加入玩家列表 (Host ID 永遠是 1)
	if not 1 in connected_peer_ids:
		connected_peer_ids.append(1)
	
	# 檢查是否可以直接開始 (例如調試時)
	_check_ready_to_start()

func _on_start_game_pressed():
	# 開始前先廣播地圖數據 (如果有的話)
	if not current_map_data.is_empty():
		rpc("sync_map_data", current_map_data)
	
	rpc("start_game_sequence")
	map_editor_button.hide() # 開始後隱藏

func _on_map_editor_pressed():
	# 初始化地圖數據 (如果還沒有)
	if current_map_data.is_empty():
		var config = VenueConfig.new()
		current_map_data = config.get_map_data()
	
	# 開啟編輯器
	map_editor_instance = MapEditorScript.new()
	map_editor_instance.map_saved.connect(_on_map_saved)
	map_editor_instance.editor_closed.connect(_on_map_editor_closed)
	add_child(map_editor_instance)
	
	# 傳入數據
	map_editor_instance.setup_editor(current_map_data)
	
	# 隱藏大廳 UI
	main_container.hide()

func _on_map_saved(new_data: Array):
	current_map_data = new_data
	print("地圖已更新")
	_on_map_editor_closed()

func _on_map_editor_closed():
	main_container.show()
	map_editor_instance = null

# [RPC] 同步地圖數據
@rpc("call_local", "reliable")
func sync_map_data(data: Array):
	current_map_data = data
	print("接收到同步地圖數據")

func _on_join_pressed():
	var ip = ip_input.text
	if ip == "":
		status_label.text = "IP 不能為空！"
		return
	status_label.text = "連線中: " + ip + "..."
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		status_label.text = "錯誤: " + str(error)
		return
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_disable_buttons()

# --- 網路回調 ---

func _on_player_connected(id): 
	status_label.text += "\n玩家加入 ID: " + str(id)
	if not id in connected_peer_ids:
		connected_peer_ids.append(id)
	
	# 如果是 Host，檢查遊戲開始條件
	if multiplayer.is_server():
		_check_ready_to_start()
	else:
		# Client 端顯示等待訊息
		status_label.text = "等待 Host 開始遊戲... (目前人數: " + str(connected_peer_ids.size()) + ")"

func _on_player_disconnected(id): 
	status_label.text += "\n玩家離開 ID: " + str(id)
	if id in connected_peer_ids:
		connected_peer_ids.erase(id)
	
	# 如果是 Host，檢查人數是否還足夠
	if multiplayer.is_server():
		_check_ready_to_start()

func _on_connected_ok():
	status_label.text = "成功加入遊戲！"
	status_label.modulate = Color.GREEN
	# Client 記錄自己
	var my_id = multiplayer.get_unique_id()
	if not my_id in connected_peer_ids:
		connected_peer_ids.append(my_id)

func _on_connected_fail():
	status_label.text = "連線失敗"
	status_label.modulate = Color.RED
	_reset_ui()
	connected_peer_ids.clear()

func _on_server_disconnected():
	status_label.text = "伺服器已斷線"
	status_label.modulate = Color.RED
	_reset_ui()
	connected_peer_ids.clear()
	# 清除遊戲
	if site_instance:
		site_instance.queue_free()
		site_instance = null
	if game_ui_instance:
		game_ui_instance.queue_free()
		game_ui_instance = null
	game_started = false
	main_container.show()

func _disable_buttons():
	host_button.disabled = true
	join_button.disabled = true
	ip_input.editable = false

func _reset_ui():
	host_button.disabled = false
	join_button.disabled = false
	ip_input.editable = true
	multiplayer.multiplayer_peer = null

func _get_local_ip():
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
	return "未知"

# --- 遊戲流程控制 ---

# 檢查是否滿足開始條件 (Host 專用)
func _check_ready_to_start():
	if game_started: return
	if not multiplayer.is_server(): return
	
	# 顯示開始按鈕，讓 Host 決定何時開始
	# 條件: 房間內有 2 名或以上玩家
	if connected_peer_ids.size() >= 2:
		status_label.text = "等待 Host 開始遊戲... (人數: " + str(connected_peer_ids.size()) + ")"
		start_game_button.show()
		start_game_button.disabled = false
	else:
		status_label.text = "等待玩家加入... (人數: " + str(connected_peer_ids.size()) + ")"
		start_game_button.hide()
		start_game_button.disabled = true

# [RPC] 開始遊戲序列 (所有人執行)
@rpc("call_local", "reliable")
func start_game_sequence():
	game_started = true
	
	# 1. 隱藏大廳 UI
	main_container.hide()
	
	# 2. 生成地圖
	_spawn_map()
	
	# 3. 生成遊戲UI
	_spawn_game_ui()
	
	# 4. 只有 Host 負責計算並分發玩家位置，以及初始化回合順序
	if multiplayer.is_server():
		_calculate_and_spawn_players()
		# 等待一下確保玩家生成完畢，再開始回合
		await get_tree().create_timer(1.0).timeout
		_init_turn_system()

# 生成地圖實例
func _spawn_map():
	if site_instance:
		site_instance.queue_free()
	
	site_instance = SiteScript.new()
	# 注入自定義地圖數據 (若有)
	if not current_map_data.is_empty():
		site_instance.map_data_override = current_map_data
		
	add_child(site_instance)
	site_instance.generate_map()

# 生成遊戲UI實例
func _spawn_game_ui():
	if game_ui_instance:
		game_ui_instance.queue_free()
	
	game_ui_instance = GameUIScript.new()
	add_child(game_ui_instance)
	
	# 連接訊號
	game_ui_instance.roll_dice_requested.connect(_on_ui_roll_dice_requested)

# 計算並分發玩家位置 (Host 邏輯)
func _calculate_and_spawn_players():
	# 等待一下確保大家地圖都生成好了 (雖然 reliable RPC 應該是有序的，但保險起見)
	await get_tree().create_timer(0.5).timeout
	
	var valid_spots = site_instance.get_all_valid_sites()
	valid_spots.shuffle()
	
	var spawn_data = {}
	var index = 0
	
	for pid in connected_peer_ids:
		if index < valid_spots.size():
			spawn_data[pid] = valid_spots[index]
			index += 1
		else:
			print("警告: 地圖格數不足！")
	
	rpc("spawn_players", spawn_data)

# [RPC] 接收出生點並生成玩家
@rpc("call_local", "reliable")
func spawn_players(spawn_data: Dictionary):
	print("生成玩家: ", spawn_data)
	for pid in spawn_data:
		var grid_pos = spawn_data[pid]
		_create_player_instance(pid, grid_pos)

# 建立單個玩家實例
func _create_player_instance(pid: int, grid_pos: Vector2i):
	var player = PlayerScript.new()
	player.player_id = pid
	player.grid_pos = grid_pos
	player.name = "Player_" + str(pid)
	
	# 設定顏色
	if pid == 1:
		player.set_color(Color.RED) # Host
	elif pid == multiplayer.get_unique_id():
		player.set_color(Color.CYAN) # 自己
		# 初始化 UI 顯示
		if game_ui_instance:
			game_ui_instance.update_money_display(player.money)
	else:
		player.set_color(Color.GREEN) # 其他人
	
	if site_instance:
		site_instance.add_child(player)
		var world_pos = site_instance.get_world_position(grid_pos)
		player.move_to_world_pos(world_pos, 0.0)

# --- [步驟 4 & 5: 回合與骰子系統] ---

# 初始化回合系統 (Host 執行)
func _init_turn_system():
	# 這裡可以實作排序邏輯 (目前依據連接順序)
	# connected_peer_ids 已經包含了所有玩家 ID
	# 複製一份順序並廣播給所有人 (確保順序一致)
	rpc("sync_turn_order", connected_peer_ids)

# [RPC] 同步回合順序
@rpc("call_local", "reliable")
func sync_turn_order(new_order):
	turn_order = new_order
	print("回合順序已同步: ", turn_order)
	
	# 如果我是 Host，開始第一個回合
	if multiplayer.is_server():
		start_new_turn(0)

# 開始新回合 (Host 呼叫)
func start_new_turn(index: int):
	current_turn_index = index
	# 循環處理
	if current_turn_index >= turn_order.size():
		current_turn_index = 0
		
	var current_player_id = turn_order[current_turn_index]
	rpc("update_turn_state", current_player_id)

# [RPC] 更新回合狀態 (所有人接收)
@rpc("call_local", "reliable")
func update_turn_state(player_id: int):
	print("現在輪到玩家: ", player_id)
	
	var is_my_turn = (player_id == multiplayer.get_unique_id())
	
	if game_ui_instance:
		if is_my_turn:
			game_ui_instance.update_turn_info("輪到你了！請擲骰子")
			game_ui_instance.set_dice_enabled(true)
		else:
			game_ui_instance.update_turn_info("等待玩家 " + str(player_id) + " 擲骰子...")
			game_ui_instance.set_dice_enabled(false)

# 當玩家按下 UI 的骰子按鈕
func _on_ui_roll_dice_requested():
	# 向伺服器請求擲骰
	rpc_id(1, "request_roll_dice")

# [RPC] 請求擲骰 (Server 執行)
@rpc("any_peer", "call_local", "reliable")
func request_roll_dice():
	var sender_id = multiplayer.get_remote_sender_id()
	
	# 驗證是否輪到該玩家
	var current_player_id = turn_order[current_turn_index]
	if sender_id != current_player_id:
		print("非當前回合玩家嘗試擲骰！忽略。")
		return
	
	# 生成隨機數字 (1-6)
	var roll_result = randi_range(1, 6)
	print("玩家 ", sender_id, " 擲出了: ", roll_result)
	
	# 廣播結果
	rpc("broadcast_dice_result", sender_id, roll_result)

	# [RPC] 廣播擲骰結果 (所有人接收)
@rpc("call_local", "reliable")
func broadcast_dice_result(player_id: int, number: int):
	if game_ui_instance:
		game_ui_instance.show_dice_result(number)
		game_ui_instance.update_turn_info("玩家 " + str(player_id) + " 擲出了 " + str(number))
	
	# 開始移動邏輯 (Host 主導)
	if multiplayer.is_server():
		# 等待動畫一下
		await get_tree().create_timer(1.0).timeout
		_start_movement_sequence(player_id, number)

# --- [步驟 6: 移動邏輯] ---

# 開始移動序列 (Host 執行)
func _start_movement_sequence(player_id: int, steps: int):
	moving_player_id = player_id
	moving_player_steps_remaining = steps
	
	print("開始移動: 玩家 ", player_id, " 步數: ", steps)
	
	# 開始第一步處理
	_process_next_movement_step()

# 處理下一步驟 (Host 執行)
func _process_next_movement_step():
	# 檢查步數是否歸零
	if moving_player_steps_remaining <= 0:
		print("移動結束，回合結束")
		
		# 觸發地塊事件
		var final_player_node = site_instance.get_node_or_null("Player_" + str(moving_player_id))
		if final_player_node:
			_handle_tile_event(moving_player_id, final_player_node.grid_pos)
			
			# 等待一下讓玩家看清楚訊息
			await get_tree().create_timer(1.5).timeout
		
		_next_turn()
		return
		
	# 取得玩家目前實例
	var player_node = site_instance.get_node_or_null("Player_" + str(moving_player_id))
	if not player_node:
		print("找不到玩家節點！跳過回合")
		_next_turn()
		return
		
	var current_pos = player_node.grid_pos
	var previous_pos = player_node.previous_grid_pos
	
	# 查詢有效鄰居
	var neighbors = site_instance.get_valid_neighbors(current_pos)
	var possible_moves: Array[Vector2i] = []
	
	# 過濾掉「來時的路」(除非是死路，或者剛開始且沒地方去)
	for neighbor in neighbors:
		if neighbor != previous_pos:
			possible_moves.append(neighbor)
	
	# [判斷情況]
	
	# 情況 A: 沒有路可走 (死路)
	if possible_moves.size() == 0:
		if neighbors.size() > 0:
			# 如果真的死路，只好往回走
			possible_moves.append(previous_pos)
		else:
			# 完全孤島 (不應發生)
			print("玩家卡住了！")
			_next_turn()
			return
	
	# 情況 B: 只有一條路 (直線或轉角) -> 自動移動
	if possible_moves.size() == 1:
		var target = possible_moves[0]
		_execute_move(moving_player_id, target)
		
	# 情況 C: 有多條路 (叉路 或 起點) -> 請求玩家選擇
	else:
		print("遇到叉路: ", current_pos, " 選項: ", possible_moves)
		_ask_player_direction(moving_player_id, current_pos, possible_moves)

# 執行移動 (Host 執行 -> RPC)
func _execute_move(player_id: int, target_grid_pos: Vector2i):
	# 扣除步數
	moving_player_steps_remaining -= 1
	
	# 廣播移動指令
	rpc("animate_player_move", player_id, target_grid_pos)

# [RPC] 執行動畫移動 (所有人接收)
@rpc("call_local", "reliable")
func animate_player_move(player_id: int, target_grid_pos: Vector2i):
	if not site_instance: return
	
	var player_node = site_instance.get_node_or_null("Player_" + str(player_id))
	if player_node:
		# 更新前一個位置
		player_node.previous_grid_pos = player_node.grid_pos
		# 更新當前位置
		player_node.grid_pos = target_grid_pos
		
		# 計算世界座標並移動
		var world_pos = site_instance.get_world_position(target_grid_pos)
		player_node.move_to_world_pos(world_pos, 0.4) # 0.4秒移動時間

	# Host 等待移動結束後，繼續下一步
	if multiplayer.is_server():
		await get_tree().create_timer(0.5).timeout
		_process_next_movement_step()

# 請求玩家選擇方向 (Host 執行)
func _ask_player_direction(player_id: int, current_pos: Vector2i, options: Array[Vector2i]):
	# 計算相對方向，轉換成 Vector2i.UP/DOWN 等，傳給 Client
	var directions: Array[Vector2i] = []
	for opt in options:
		directions.append(opt - current_pos)
		
	print("等待玩家選擇方向: ", directions)
	rpc_id(player_id, "show_direction_selector", directions)

# [RPC] 顯示方向選擇器 (Client 執行)
@rpc("call_local", "reliable")
func show_direction_selector(available_directions: Array[Vector2i]):
	# 如果不是操作該玩家的客戶端，不該收到此訊息(rpc_id已過濾，但雙保險)
	if multiplayer.get_unique_id() != moving_player_id and moving_player_id != 1: 
		# 注意: call_local 會讓 server 也執行，如果 server 不是該玩家，需要過濾嗎？
		# 其實 rpc_id 已經指定了。如果是 local host，那就會執行。
		pass
		
	# 實例化選擇器 (如果沒有)
	if not direction_selector_instance:
		direction_selector_instance = DirectionSelectorScript.new()
		direction_selector_instance.direction_selected.connect(_on_direction_selected)
		add_child(direction_selector_instance)
	
	# 設定位置 (跟隨玩家)
	var player_node = site_instance.get_node_or_null("Player_" + str(moving_player_id))
	if player_node:
		# [修正] 使用全域座標 (Global Position) 確保 UI 對齊
		# 因為 Player 在 Site (可能有縮放/位移) 裡面，而 Selector 在 Lobby (全螢幕 UI) 裡面
		# 我們需要將 Player 的中心點轉換為螢幕座標
		
		var player_center_global = player_node.global_position + (player_node.size / 2)
		var selector_size = direction_selector_instance.size
		
		# 設定 Selector 的中心點對齊 Player 的中心點
		direction_selector_instance.global_position = player_center_global - (selector_size / 2)
		
		# 確保它在最上層
		direction_selector_instance.z_index = 100
		direction_selector_instance.move_to_front()
	
	direction_selector_instance.show_options(available_directions)
	direction_selector_instance.show()
	
	# 更新 UI 提示
	if game_ui_instance:
		game_ui_instance.update_turn_info("請選擇移動方向！")

# 當玩家選擇了方向 (Client -> Server)
func _on_direction_selected(direction: Vector2i):
	# 隱藏選擇器
	direction_selector_instance.hide()
	
	# 回傳給 Server
	rpc_id(1, "receive_direction_choice", direction)

# [RPC] 接收玩家選擇 (Server 執行)
@rpc("any_peer", "call_local", "reliable")
func receive_direction_choice(direction: Vector2i):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != moving_player_id: return
	
	print("收到玩家選擇: ", direction)
	
	# 驗證並計算目標
	var player_node = site_instance.get_node_or_null("Player_" + str(moving_player_id))
	if player_node:
		var target_pos = player_node.grid_pos + direction
		# 這裡可以加強驗證 target_pos 是否在 valid neighbors 裡
		
		# 繼續移動
		_execute_move(moving_player_id, target_pos)

# 處理地塊事件 (Host 執行)
func _handle_tile_event(player_id: int, grid_pos: Vector2i):
	if not site_instance: return
	
	var type = site_instance.get_tile_type(grid_pos)
	print("玩家 ", player_id, " 停在類型: ", type)
	
	var money_change = 0
	var msg = ""
	
	match type:
		2: # Start
			msg = "回到起點！獎勵 $2000"
			money_change = 2000
		3: # Property
			msg = "購買地產！花費 $1000"
			money_change = -1000
		4: # Shop
			msg = "進入商店！(尚未開放)"
			money_change = 0
		_:
			# 普通路徑或無效
			pass
	
	if money_change != 0 or msg != "":
		rpc("update_player_money", player_id, money_change, msg)

# [RPC] 更新玩家資金與訊息
@rpc("call_local", "reliable")
func update_player_money(player_id: int, amount: int, message: String):
	if not site_instance: return
	
	var player_node = site_instance.get_node_or_null("Player_" + str(player_id))
	if player_node:
		player_node.money += amount
		print("玩家 ", player_id, " 資金變動: ", amount, " 目前: ", player_node.money)
		
		# 如果是自己，更新 UI
		if player_id == multiplayer.get_unique_id():
			if game_ui_instance:
				game_ui_instance.update_money_display(player_node.money)
				if message != "":
					game_ui_instance.update_turn_info(message)
		
		# 如果不是自己，也可以顯示一些浮動文字 (未來擴充)
		# 這裡暫時只讓 GameUI 顯示當前玩家的訊息 (如果是輪到別人的回合，UI 本來就顯示等待中)
		# 但為了讓所有人知道發生什麼事，我們可以強制更新所有人的 Turn Info
		if game_ui_instance:
			game_ui_instance.update_turn_info("玩家 " + str(player_id) + ": " + message)

# 切換到下一位 (Server 內部呼叫)
func _next_turn():
	start_new_turn(current_turn_index + 1)
