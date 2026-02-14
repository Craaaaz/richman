extends Control

# 全域變數引用
var global: Node

# 骰子系統
var rng = RandomNumberGenerator.new()
var dice_button: Button
var dice_value: int = 0

# 玩家管理系統
var players: Dictionary = {} # 儲存所有玩家 {player_id: player_node}
var current_player_id: int # 當前回合玩家ID
var my_player_id: int = 1 # 本地玩家ID

# 場景載入同步 (解決 race condition)
var peers_ready: Dictionary = {} # 記錄哪些 peer 已經載入場景 {peer_id: true}
var expected_peers: Array = [] # 預期要等待的所有 peer ID
var all_ready: bool = false # 是否所有 peer 都已就緒

# 玩家移動系統
var player_position: Vector2 = Vector2(100, 100) # 本地玩家初始位置
var player_speed: float = 200.0 # 移動速度 (像素/秒)
var target_position: Vector2 = Vector2(100, 100) # 目標位置
var is_moving: bool = false
var move_path: Array[Vector2] = [] # 移動路徑
var current_path_index: int = 0
var sync_timer: float = 0.0 # 同步計時器
var last_sync_position: Vector2 = Vector2(100, 100) # 上次同步的位置
const SYNC_INTERVAL: float = 0.1 # 每0.1秒同步一次位置
const MIN_SYNC_DISTANCE: float = 5.0 # 最小同步距離，避免微小移動造成過多網路流量

# 玩家資訊顯示系統
var player_info_container: VBoxContainer # 玩家資訊容器（左下角）
var player_info_labels: Dictionary = {} # 儲存玩家資訊標籤 {player_id: label_node}

# 棋盤設定 - 口字形棋盤
const BOARD_CELL_SIZE: int = 60 # 每個格子大小 (縮小以適應螢幕)
const BOARD_OUTER_SIZE: int = 8 # 外圍邊長 (格子數，減少以適應螢幕)
const TOTAL_CELLS: int = 28 # 總格子數 (8*4 - 4個角落重複計算)

# 玩家顏色對應 (根據玩家ID)
const PLAYER_COLORS: Array[Color] = [
	Color(1, 0, 0, 1),    # 紅色 (玩家1)
	Color(0, 1, 0, 1),    # 綠色 (玩家2)
	Color(0, 0, 1, 1),    # 藍色 (玩家3)
	Color(1, 1, 0, 1),    # 黃色 (玩家4)
]

# 玩家ID到顏色索引的映射
var player_color_map: Dictionary = {}
var next_color_index: int = 0

# 口字形棋盤位置對照表 (預先計算好的位置)
var board_positions: Array[Vector2] = []
var board_cells: Array[Control] = [] # 儲存棋盤格子節點

func _ready():
	# 取得全域變數節點
	global = get_node("/root/Global")
	
	# 取得骰子按鈕
	dice_button = get_node("DiceButton")
	
	# 初始化隨機數生成器
	rng.randomize()
	
	# 初始化棋盤位置和視覺化
	_init_board_positions()
	_create_board_visualization()
	
	# 連接按鈕信號
	dice_button.pressed.connect(_on_dice_button_pressed)
	
	# 初始化網路訊號 (只處理斷線，連線在場景載入後不會再觸發)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# 建立玩家資訊顯示
	_create_player_info_display()
	
	# 設定本地玩家ID
	my_player_id = multiplayer.get_unique_id()
	print("場景載入完成，我是", global.get_player_name_by_id(my_player_id), "，對等方: ", multiplayer.get_peers())
	
	# 除錯：檢查玩家順序狀態
	print("玩家順序狀態檢查：")
	print("  player_id_to_order: ", global.player_id_to_order)
	print("  player_order_to_id: ", global.player_order_to_id)
	print("  players: ", global.players.keys())
	print("  get_players_in_order(): ", global.get_players_in_order())
	
	# === 場景載入同步機制 ===
	# 不直接初始化玩家，而是通知伺服器「我的場景已載入」
	# 伺服器收集到所有 peer 的就緒通知後，才統一初始化所有玩家
	if multiplayer.is_server():
		# 伺服器：建立預期 peer 列表 (自己 + 所有連線的 client)
		expected_peers = [1] # 伺服器自己的 ID 是 1
		for peer_id in multiplayer.get_peers():
			expected_peers.append(peer_id)
		print("伺服器等待所有 peer 就緒: ", expected_peers)
		# 標記自己已就緒
		_on_client_scene_ready(1)
	else:
		# 客戶端：通知伺服器自己已就緒
		rpc_id(1, "_on_client_scene_ready", my_player_id)

func _init_board_positions():
	# 清除現有位置
	board_positions.clear()
	
	# 計算棋盤中心點
	var viewport_size = get_viewport_rect().size
	var center_x = int(viewport_size.x / 2)
	var center_y = int(viewport_size.y / 2)
	
	# 計算棋盤左上角（格子以左上角為基準排列，確保整數對齊）
	var board_pixel_size = BOARD_OUTER_SIZE * BOARD_CELL_SIZE
	var origin_x = center_x - int(board_pixel_size / 2)
	var origin_y = center_y - int(board_pixel_size / 2)
	
	# 確保在畫面內
	var margin = 20
	if origin_x < margin:
		origin_x = margin
	if origin_y < margin:
		origin_y = margin
	if origin_x + board_pixel_size > int(viewport_size.x) - margin:
		origin_x = int(viewport_size.x) - margin - board_pixel_size
	if origin_y + board_pixel_size > int(viewport_size.y) - margin:
		origin_y = int(viewport_size.y) - margin - board_pixel_size
	
	# 格子中心偏移量
	var half_cell = int(BOARD_CELL_SIZE / 2)
	
	# 上邊 (從左到右)
	for i in range(BOARD_OUTER_SIZE):
		var x = origin_x + i * BOARD_CELL_SIZE + half_cell
		var y = origin_y + half_cell
		board_positions.append(Vector2(x, y))
	
	# 右邊 (從上到下，跳過右上角)
	for i in range(1, BOARD_OUTER_SIZE):
		var x = origin_x + (BOARD_OUTER_SIZE - 1) * BOARD_CELL_SIZE + half_cell
		var y = origin_y + i * BOARD_CELL_SIZE + half_cell
		board_positions.append(Vector2(x, y))
	
	# 下邊 (從右到左，跳過右下角)
	for i in range(BOARD_OUTER_SIZE - 2, -1, -1):
		var x = origin_x + i * BOARD_CELL_SIZE + half_cell
		var y = origin_y + (BOARD_OUTER_SIZE - 1) * BOARD_CELL_SIZE + half_cell
		board_positions.append(Vector2(x, y))
	
	# 左邊 (從下到上，跳過左下角和左上角)
	for i in range(BOARD_OUTER_SIZE - 2, 0, -1):
		var x = origin_x + half_cell
		var y = origin_y + i * BOARD_CELL_SIZE + half_cell
		board_positions.append(Vector2(x, y))
	
	# 驗證總格子數
	var expected_cells = BOARD_OUTER_SIZE * 4 - 4
	if board_positions.size() != expected_cells:
		print("警告：棋盤格子數不正確！預期: ", expected_cells, "，實際: ", board_positions.size())
	
	print("棋盤初始化完成，總格子數: ", board_positions.size())
	print("棋盤範圍: X[", origin_x, ", ", origin_x + board_pixel_size, "], Y[", origin_y, ", ", origin_y + board_pixel_size, "]")
	print("畫面範圍: X[0, ", viewport_size.x, "], Y[0, ", viewport_size.y, "]")

func _create_board_visualization():
	# 清除現有棋盤格子
	for cell in board_cells:
		if cell and is_instance_valid(cell):
			cell.queue_free()
	board_cells.clear()
	
	# 取得棋盤容器
	var board_container = get_node("BoardContainer")
	if not board_container:
		print("錯誤：找不到 BoardContainer 節點")
		return
	
	# 建立棋盤格子
	var half = Vector2(BOARD_CELL_SIZE / 2, BOARD_CELL_SIZE / 2)
	for i in range(board_positions.size()):
		var cell_position = board_positions[i]
		var top_left = cell_position - half
		
		# 建立格子節點（擴大 2 像素以容納內部邊框）
		var cell = Control.new()
		cell.name = "Cell_" + str(i)
		cell.layout_mode = 0
		cell.position = top_left - Vector2(1, 1)  # 因格子擴大，位置微調
		cell.size = Vector2(BOARD_CELL_SIZE + 2, BOARD_CELL_SIZE + 2)
		
		# 用單一 Panel + StyleBoxFlat 繪製格子（邊框向內繪製）
		var panel = Panel.new()
		panel.position = Vector2(1, 1)  # 邊框向內繪製
		panel.size = Vector2(BOARD_CELL_SIZE, BOARD_CELL_SIZE)
		var style = StyleBoxFlat.new()
		
		# 判斷是否為角落格子（索引 0, 7, 14, 21）
		var is_corner = i in [0, 7, 14, 21]
		
		if is_corner:
			# 角落格子：白底黑邊
			style.bg_color = Color(1, 1, 1, 1)         # 白色填充
			style.border_color = Color(0, 0, 0, 1)      # 黑色邊框
			#panel.z_index = 1  # 確保角落格子繪製在最上層
		else:
			# 非角落格子：黑底白邊
			style.bg_color = Color(0, 0, 0, 1)         # 黑色填充
			style.border_color = Color(1, 1, 1, 1)      # 白色邊框
		
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.anti_aliasing = false
		style.corner_radius_top_left = 0
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		panel.add_theme_stylebox_override("panel", style)
		
		# 建立格子編號標籤
		var label = Label.new()
		label.text = str(i)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# 根據背景調整文字顏色
		if is_corner:
			label.modulate = Color(0, 0, 0, 1) # 白底用黑字
		else:
			label.modulate = Color(1, 1, 1, 1) # 黑底用白字
		
		# 組裝節點
		cell.add_child(panel)
		cell.add_child(label)
		board_container.add_child(cell)
		
		# 儲存格子節點
		board_cells.append(cell)
	
	print("棋盤視覺化建立完成，總格子數: ", board_cells.size())

func _create_player_info_display():
	# 如果容器已存在，先清除
	if player_info_container and is_instance_valid(player_info_container):
		player_info_container.queue_free()
	
	# 建立玩家資訊容器
	player_info_container = VBoxContainer.new()
	player_info_container.name = "PlayerInfoContainer"
	player_info_container.layout_mode = 0
	
	# 設定錨點到左下角
	player_info_container.anchor_left = 0.0
	player_info_container.anchor_top = 1.0
	player_info_container.anchor_right = 0.0
	player_info_container.anchor_bottom = 1.0
	
	# 設定位置偏移（左下角，留邊距）
	player_info_container.offset_left = 20
	player_info_container.offset_top = -300  # 從底部往上 300 像素
	player_info_container.offset_right = 250  # 寬度 230 像素
	player_info_container.offset_bottom = -20  # 從底部往上 20 像素
	
	# 設定容器樣式（白色透明背景）
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.8)  # 白色，80% 透明度
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)  # 灰色邊框
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	player_info_container.add_theme_stylebox_override("panel", style)
	
	# 設定容器間距
	player_info_container.add_theme_constant_override("separation", 8)
	
	# 標題
	var title_label = Label.new()
	title_label.text = "玩家資訊"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	player_info_container.add_child(title_label)
	
	# 分隔線
	var separator = HSeparator.new()
	player_info_container.add_child(separator)
	
	# 將容器添加到場景
	add_child(player_info_container)
	
	# 初始化玩家資訊標籤
	_update_player_info_display()
	
	print("玩家資訊顯示容器建立完成")

func _update_player_info_display():
	# 清除現有標籤
	for player_id in player_info_labels:
		var label = player_info_labels[player_id]
		if label and is_instance_valid(label):
			label.queue_free()
	player_info_labels.clear()
	
	# 取得所有玩家（按順序）
	var player_ids = global.get_players_in_order()
	
	if player_ids.size() == 0:
		print("沒有玩家可顯示")
		return
	
	# 為每個玩家建立資訊標籤
	for player_id in player_ids:
		# 建立水平容器
		var player_row = HBoxContainer.new()
		player_row.add_theme_constant_override("separation", 10)
		
		# 玩家顏色標記
		var color_marker = ColorRect.new()
		color_marker.custom_minimum_size = Vector2(20, 20)
		
		# 設定玩家顏色
		var color_index = player_color_map.get(player_id, 0)
		if color_index < PLAYER_COLORS.size():
			color_marker.color = PLAYER_COLORS[color_index]
		
		# 玩家名稱和資金
		var player_info_label = Label.new()
		player_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		player_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		player_info_label.add_theme_font_size_override("font_size", 14)
		player_info_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
		
		# 取得玩家資訊
		var player_name = global.get_player_name_by_id(player_id)
		var player_money = 1500  # 預設起始資金（未來從 global.players 取得）
		if global.players.has(player_id):
			player_money = global.players[player_id].get("money", 1500)
		
		# 設定標籤文字
		player_info_label.text = "%s: $%d" % [player_name, player_money]
		
		# 如果是當前回合玩家，加粗顯示
		if player_id == current_player_id:
			player_info_label.add_theme_font_size_override("font_size", 16)
			player_info_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.8, 1))
		
		# 組裝元件
		player_row.add_child(color_marker)
		player_row.add_child(player_info_label)
		
		# 添加到主容器
		player_info_container.add_child(player_row)
		
		# 儲存標籤參考（儲存 player_row 以便更新）
		player_info_labels[player_id] = player_row
	
	print("玩家資訊顯示已更新，共 %d 名玩家" % player_ids.size())

func _initialize_players():
	# === 此函數現在只由伺服器在所有 peer 就緒後調用 ===
	# 伺服器負責：分配顏色、建立玩家、同步給所有客戶端
	
	print("=== 所有玩家已就緒，開始初始化 ===")
	print("伺服器玩家順序狀態檢查：")
	print("  player_id_to_order: ", global.player_id_to_order)
	print("  player_order_to_id: ", global.player_order_to_id)
	print("  players: ", global.players.keys())
	
	# 清除現有玩家節點
	for player_id in players:
		var player_node = players[player_id]
		if player_node and is_instance_valid(player_node):
			player_node.queue_free()
	players.clear()
	
	# 重置顏色映射
	player_color_map.clear()
	next_color_index = 0
	
	# 收集所有玩家ID並按加入順序排序
	var all_player_ids: Array = global.get_players_in_order()
	
	print("所有玩家（按順序）: ", all_player_ids)
	if all_player_ids.size() == 0:
		print("警告：玩家列表為空！嘗試使用所有連線的玩家...")
		# 備用方案：使用所有連線的玩家
		all_player_ids = [1]  # 伺服器自己
		for peer_id in multiplayer.get_peers():
			all_player_ids.append(peer_id)
		all_player_ids.sort()
		print("備用玩家列表: ", all_player_ids)
	
	for player_id in all_player_ids:
		print("  - ", global.get_player_name_by_id(player_id), " (ID: ", player_id, ")")
	
	var start_pos = board_positions[0] if board_positions.size() > 0 else Vector2(100, 100)
	
	# 第一步：為所有玩家分配顏色並廣播
	for player_id in all_player_ids:
		player_color_map[player_id] = next_color_index % PLAYER_COLORS.size()
		next_color_index += 1
		rpc("sync_player_color", player_id, player_color_map[player_id])
	
	# 第二步：建立所有玩家並廣播 (call_local 會在伺服器本地也執行)
	for player_id in all_player_ids:
		rpc("sync_player", player_id, start_pos)
	
	# 第三步：設定第一個玩家的回合
	current_player_id = all_player_ids[0]
	rpc("sync_player_turn", current_player_id)
	
	print("=== 初始化完成，第一回合: ", global.get_player_name_by_id(current_player_id), " ===")

# === 場景就緒同步 RPC ===

@rpc("any_peer", "reliable")
func _on_client_scene_ready(peer_id: int):
	# 此 RPC 只在伺服器端處理
	if not multiplayer.is_server():
		return
	
	print("收到", global.get_player_name_by_id(peer_id), "場景就緒通知")
	peers_ready[peer_id] = true
	
	# 檢查是否所有 peer 都已就緒
	var all_peers_ready = true
	for expected_id in expected_peers:
		if not peers_ready.has(expected_id):
			all_peers_ready = false
			print("  仍在等待", global.get_player_name_by_id(expected_id))
			break
	
	if all_peers_ready and not all_ready:
		all_ready = true
		print("所有 peer 已就緒: ", expected_peers)
		_initialize_players()

func _create_player(player_id: int, position: Vector2):
	# 如果玩家已存在，先移除
	if players.has(player_id):
		var old_player = players[player_id]
		if old_player and is_instance_valid(old_player):
			old_player.queue_free()
	
	var color_index = player_color_map.get(player_id, 0)
	print(global.get_player_name_by_id(player_id), "顏色索引: ", color_index, " 顏色: ", PLAYER_COLORS[color_index])
	
	# 建立新玩家節點
	var player_node = Control.new()
	player_node.name = "Player_" + str(player_id)
	player_node.layout_mode = 0
	
	# 根據顏色索引添加小偏移，讓同一格子的玩家不會完全重疊
	var offset = _get_player_offset(color_index)
	
	player_node.position = position - Vector2(15, 15) + offset # 讓玩家在格子中央 (格子60x60，玩家30x30)
	player_node.size = Vector2(30, 30)
	
	# 建立玩家顏色方塊
	var color_rect = ColorRect.new()
	color_rect.layout_mode = 0
	color_rect.anchor_right = 1.0
	color_rect.anchor_bottom = 1.0
	color_rect.size_flags_horizontal = 3
	color_rect.size_flags_vertical = 3
	
	# 設定玩家顏色
	color_rect.color = PLAYER_COLORS[color_index]
	
	# 建立玩家名稱標籤（使用中文名稱而非玩家ID）
	var label = Label.new()
	label.text = global.get_player_name_by_id(player_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# 組裝節點
	player_node.add_child(color_rect)
	player_node.add_child(label)
	add_child(player_node)
	
	# 儲存玩家
	players[player_id] = player_node
	
	print("建立", global.get_player_name_by_id(player_id), "位置: ", position, " for client ", multiplayer.get_unique_id())

func _process(delta: float):
	if is_moving and move_path.size() > 0:
		_move_player(delta)
		# 在移動過程中定期同步位置
		if is_moving:
			sync_timer += delta
			if sync_timer >= SYNC_INTERVAL:
				sync_timer = 0.0
				# 檢查位置是否有顯著變化
				if player_position.distance_to(last_sync_position) >= MIN_SYNC_DISTANCE:
					# 廣播當前位置給所有玩家
					rpc("sync_player_position", my_player_id, player_position)
					last_sync_position = player_position

func _on_dice_button_pressed():
	print("按鈕按下，我是", global.get_player_name_by_id(my_player_id), "，當前回合：", global.get_player_name_by_id(current_player_id))
	# 如果不是當前回合玩家，不能擲骰子
	if my_player_id != current_player_id:
		print("不是你的回合，請等待", global.get_player_name_by_id(current_player_id), "行動")
		return
	
	# 如果玩家正在移動，不允許擲骰子
	if is_moving:
		print("玩家正在移動中，請稍候...")
		return
	
	# 擲骰子 (1-6)
	dice_value = rng.randi_range(1, 6)
	print(global.get_player_name_by_id(my_player_id), "擲骰子: ", dice_value)
	_update_button_text()
	
	# 廣播骰子結果
	rpc("sync_dice_result", my_player_id, dice_value)
	
	# 根據骰子點數計算移動路徑
	_calculate_move_path()
	
	# 開始移動
	if move_path.size() > 0:
		is_moving = true
		current_path_index = 0
		target_position = move_path[0]
		sync_timer = 0.0
		last_sync_position = player_position
		print("開始移動，目標位置[", current_path_index, "]: ", target_position)

func _calculate_move_path():
	move_path.clear()
	
	# 找到玩家當前所在的棋盤格子索引
	var current_cell_index = _find_current_cell_index()
	if current_cell_index == -1:
		print("錯誤：找不到玩家當前位置對應的棋盤格子")
		return
	
	print("玩家當前格子索引: ", current_cell_index, "，骰子點數: ", dice_value, "，棋盤總格子數: ", board_positions.size())
	
	# 確保玩家位置對齊到最近的棋盤格子
	# 這可以避免累積誤差
	player_position = board_positions[current_cell_index]
	print("對齊玩家位置到格子 ", current_cell_index, ": ", player_position)
	
	# 根據骰子點數計算移動路徑
	# 重要：從下一個格子開始，逐步移動到每個中間格子
	for i in range(1, dice_value + 1):
		var next_cell_index = (current_cell_index + i) % board_positions.size()
		var next_position = board_positions[next_cell_index]
		move_path.append(next_position)
		print("  步驟 ", i, ": 從格子 ", current_cell_index, " 移動到格子 ", next_cell_index, " (位置: ", next_position, ")")
	
	print("移動路徑 (", move_path.size(), "步): ", move_path)

func _find_current_cell_index() -> int:
	# 找到離玩家位置最近的棋盤格子
	var min_distance = INF
	var closest_index = -1
	
	for i in range(board_positions.size()):
		var distance = player_position.distance_to(board_positions[i])
		if distance < min_distance:
			min_distance = distance
			closest_index = i
	
	# 除錯資訊
	if closest_index != -1:
		print("找到最近格子: 索引 ", closest_index, "，距離 ", min_distance, "，玩家位置 ", player_position, "，格子位置 ", board_positions[closest_index])
	else:
		print("錯誤：找不到最近格子，玩家位置 ", player_position)
	
	return closest_index

func _move_player(delta: float):
	# 計算移動方向
	var direction = target_position - player_position
	
	# 如果已經到達目標位置
	if direction.length() < 1.0:
		player_position = target_position
		current_path_index += 1
		
		# 更新視覺位置到當前路徑點（停在這格）
		_update_my_player_visual()
		
		# 廣播到達路徑點的位置
		rpc("sync_player_position", my_player_id, player_position)
		
		# 如果還有下一個目標位置
		if current_path_index < move_path.size():
			target_position = move_path[current_path_index]
			# 這幀到此為止，下一幀再開始朝新目標移動
			return
		else:
			# 移動完成
			is_moving = false
			move_path.clear()
			current_path_index = 0
			
			# 確保玩家位置對齊到最近的棋盤格子
			var final_cell_index = _find_current_cell_index()
			if final_cell_index != -1:
				player_position = board_positions[final_cell_index]
			
			_update_my_player_visual()
			
			# 廣播最終位置更新
			rpc("sync_player_position", my_player_id, player_position)
			
			# 切換到下一個玩家回合
			_next_player_turn()
			return
	
	# 移動玩家（限制每幀最多移動到目標位置，不會超過）
	var move_distance = player_speed * delta
	if direction.length() > move_distance:
		player_position += direction.normalized() * move_distance
	else:
		player_position = target_position
	
	_update_my_player_visual()

func _get_player_offset(color_index: int) -> Vector2:
	match color_index:
		1: return Vector2(5, 0)
		2: return Vector2(0, 5)
		3: return Vector2(5, 5)
		_: return Vector2.ZERO

func _update_my_player_visual():
	if players.has(my_player_id):
		var color_index = player_color_map.get(my_player_id, 0)
		var offset = _get_player_offset(color_index)
		players[my_player_id].position = player_position - Vector2(15, 15) + offset

func _next_player_turn():
	# 取得所有玩家ID（按順序）
	var player_ids = global.get_players_in_order()
	
	print("=== 回合切換除錯資訊 ===")
	print("當前玩家ID: ", current_player_id, " (", global.get_player_name_by_id(current_player_id), ")")
	print("玩家列表: ", player_ids)
	for player_id in player_ids:
		print("  - ", global.get_player_name_by_id(player_id), " (ID: ", player_id, ")")
	
	if player_ids.size() == 0:
		print("錯誤：沒有玩家在遊戲中")
		return
	
	# 檢查當前玩家是否在玩家列表中
	var current_index = player_ids.find(current_player_id)
	if current_index == -1:
		print("警告：當前玩家 ", current_player_id, " 不在玩家列表中，使用第一個玩家")
		current_index = 0
		current_player_id = player_ids[0]
	
	# 計算下一個玩家
	var next_index = (current_index + 1) % player_ids.size()
	current_player_id = player_ids[next_index]
	
	# 廣播回合切換
	rpc("sync_player_turn", current_player_id)
	
	print("切換回合，現在是", global.get_player_name_by_id(current_player_id), "的回合")
	print("=== 回合切換完成 ===")

func _update_button_text():
	# 更新按鈕文字顯示骰子點數
	dice_button.text = "骰子\n" + str(dice_value)
	
	# 如果不是當前回合玩家，顯示提示（使用中文名稱）
	if my_player_id != current_player_id:
		dice_button.text += "\n等待" + global.get_player_name_by_id(current_player_id)

# --- 網路同步功能 ---

@rpc("any_peer", "call_local")
func sync_dice_result(player_id: int, value: int):
	print(global.get_player_name_by_id(player_id), " 擲出骰子: ", value)
	
	# 更新骰子顯示
	if player_id == my_player_id:
		dice_value = value
		_update_button_text()

@rpc("any_peer", "call_local")
func sync_player_position(player_id: int, position: Vector2):
	print("同步", global.get_player_name_by_id(player_id), "位置: ", position)
	
	# 更新玩家位置（包含偏移）
	if players.has(player_id):
		var color_index = player_color_map.get(player_id, 0)
		var offset = _get_player_offset(color_index)
		players[player_id].position = position - Vector2(15, 15) + offset
	
	# 如果是本地玩家，更新本地變數
	if player_id == my_player_id:
		player_position = position
		last_sync_position = position

@rpc("any_peer", "call_local")
func sync_player(player_id: int, position: Vector2):
	print("sync_player received by client ", multiplayer.get_unique_id(), " for ", global.get_player_name_by_id(player_id), " at ", position)
	
	# 建立或更新玩家
	if not players.has(player_id):
		_create_player(player_id, position)
	else:
		var color_index = player_color_map.get(player_id, 0)
		var offset = _get_player_offset(color_index)
		players[player_id].position = position - Vector2(15, 15) + offset
	
	# 如果是本地玩家，更新本地位置變數
	if player_id == my_player_id:
		player_position = position
		last_sync_position = position
	
	# 更新玩家資訊顯示
	_update_player_info_display()

@rpc("any_peer", "call_local")
func sync_player_turn(player_id: int):
	print("=== 同步回合切換 ===")
	print("收到回合切換通知：玩家ID ", player_id, " (", global.get_player_name_by_id(player_id), ")")
	print("本地玩家順序狀態：")
	print("  player_id_to_order: ", global.player_id_to_order)
	print("  get_players_in_order(): ", global.get_players_in_order())
	
	# 檢查玩家是否存在
	if not global.player_id_to_order.has(player_id):
		print("警告：玩家ID ", player_id, " 不存在於本地玩家順序映射中！")
		# 嘗試使用第一個玩家
		var player_ids = global.get_players_in_order()
		if player_ids.size() > 0:
			player_id = player_ids[0]
			print("使用第一個玩家替代：", global.get_player_name_by_id(player_id))
		else:
			print("錯誤：沒有可用的玩家！")
			return
	
	current_player_id = player_id
	_update_button_text()
	
	# 更新玩家資訊顯示（高亮當前回合玩家）
	_update_player_info_display()
	
	print("回合已切換到", global.get_player_name_by_id(current_player_id))
	print("=== 回合同步完成 ===")

@rpc("any_peer", "call_local")
func sync_player_color(player_id: int, color_index: int):
	print("同步", global.get_player_name_by_id(player_id), "顏色索引: ", color_index)
	player_color_map[player_id] = color_index
	
	# 如果玩家已存在，更新其顏色
	if players.has(player_id):
		var player_node = players[player_id]
		var color_rect = player_node.get_child(0) as ColorRect
		if color_rect:
			color_rect.color = PLAYER_COLORS[color_index]
	
	# 更新玩家資訊顯示（顏色標記）
	_update_player_info_display()

func _on_player_disconnected(player_id: int):
	print(global.get_player_name_by_id(player_id), "斷線")
	
	# 移除玩家
	if players.has(player_id):
		var player_node = players[player_id]
		if player_node and is_instance_valid(player_node):
			player_node.queue_free()
		players.erase(player_id)
	
	# 移除顏色映射
	if player_color_map.has(player_id):
		player_color_map.erase(player_id)
	
	# 更新玩家資訊顯示
	_update_player_info_display()
	
	# 如果斷線的玩家是當前回合玩家，切換到下一個玩家
	if player_id == current_player_id:
		_next_player_turn()

# --- 資金同步功能（未來擴展用） ---

@rpc("any_peer", "call_local")
func sync_player_money(player_id: int, money: int):
	print("同步", global.get_player_name_by_id(player_id), "資金: $", money)
	
	# 更新全域玩家資金資訊
	if global.players.has(player_id):
		global.players[player_id]["money"] = money
	else:
		# 如果玩家不存在，建立基本資訊
		global.players[player_id] = {
			"name": global.get_player_name_by_id(player_id),
			"money": money
		}
	
	# 更新玩家資訊顯示
	_update_player_info_display()

# 更新玩家資金（伺服器端呼叫）
func update_player_money(player_id: int, money_change: int):
	if not multiplayer.is_server():
		return
	
	# 計算新資金
	var current_money = 1500
	if global.players.has(player_id):
		current_money = global.players[player_id].get("money", 1500)
	
	var new_money = current_money + money_change
	if new_money < 0:
		new_money = 0
	
	# 更新全域資料
	if global.players.has(player_id):
		global.players[player_id]["money"] = new_money
	else:
		global.players[player_id] = {
			"name": global.get_player_name_by_id(player_id),
			"money": new_money
		}
	
	# 廣播給所有客戶端
	rpc("sync_player_money", player_id, new_money)
	
	print("玩家", global.get_player_name_by_id(player_id), "資金更新: $", current_money, " -> $", new_money)
