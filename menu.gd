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
var settings_button: Button # 新增：設置按鈕

# 設置彈出視窗相關
var settings_popup: PopupPanel
var settings_starting_money_spin: SpinBox
var settings_pass_bonus_spin: SpinBox
var settings_popup_container: PanelContainer

func _ready():
	# 取得全域變數節點
	global = get_node("/root/Global")
	
	# 載入遊戲設定
	global.load_settings()
	
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
	
	# 新增：設置按鈕 (在開始遊戲下方)
	settings_button = Button.new()
	settings_button.text = "設置"
	settings_button.pressed.connect(_on_settings_pressed)
	settings_button.disabled = true # 預設禁用
	settings_button.custom_minimum_size = Vector2(150, 40)
	settings_button.add_theme_color_override("font_color", Color(0.3, 0.3, 0.6, 1))  # 藍紫色
	main_container.add_child(settings_button)
	
	# 狀態顯示
	status_label = Label.new()
	status_label.text = "狀態: 等待操作..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.7, 0.7, 0.7)
	main_container.add_child(status_label)
	
	# 建立設置彈出視窗
	_create_settings_popup()

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

func _on_settings_pressed():
	# 只有 Host (ID=1) 可以開啟設置
	if multiplayer.is_server() and multiplayer.get_unique_id() == 1:
		# 更新彈出視窗中的數值（從當前設定載入）
		settings_starting_money_spin.value = global.game_settings["starting_money"]
		settings_pass_bonus_spin.value = global.game_settings["pass_start_bonus"]
		settings_popup.popup_centered()
		# 添加淡入和縮放效果
		settings_popup_container.modulate = Color(1, 1, 1, 0)
		settings_popup_container.scale = Vector2(0.9, 0.9)
		var tween = create_tween()
		tween.tween_property(settings_popup_container, "modulate", Color(1, 1, 1, 1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(settings_popup_container, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		# 設置初始焦點到第一個輸入框
		await get_tree().process_frame
		settings_starting_money_spin.grab_focus()
		print("開啟設置彈出視窗，當前設定：", global.game_settings)
	else:
		status_label.text = "只有主機可以修改設置。"
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
			"money": global.game_settings["starting_money"],
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
	settings_button.disabled = true # 確保設置按鈕在重置時禁用

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
				settings_button.disabled = false  # 啟用設置按鈕
				status_label.text = "準備就緒！總人數: %d/%d。按 '開始遊戲'。" % [current_players, MAX_CLIENTS]
			else:
				start_game_button.disabled = true
				settings_button.disabled = false  # 主機建立後即可設置
				status_label.text = "等待玩家加入... (目前人數: %d/%d)" % [current_players, MAX_CLIENTS]
		else:
			start_game_button.disabled = true # 應在 Host 建立後保證 multiplayer_peer 存在
			settings_button.disabled = true
	else:
		# Client 端無法控制開始按鈕，保持禁用
		start_game_button.disabled = true
		settings_button.disabled = true

func _get_local_ip():
	# 嘗試取得本機 IP 以顯示給 Host 看
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
	return "無法取得區域網路 IP"

func _create_settings_popup():
	# 建立設置彈出視窗
	settings_popup = PopupPanel.new()
	settings_popup.name = "SettingsPopup"
	settings_popup.size = Vector2(650, 450)
	
	# 主容器
	settings_popup_container = PanelContainer.new()
	settings_popup_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_popup_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_popup_container.custom_minimum_size = Vector2(650, 450)
	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.96, 0.96, 0.98, 1)  # 更淺的藍灰色背景
	popup_style.border_color = Color(0.2, 0.2, 0.4, 1)  # 更深的藍色邊框
	popup_style.border_width_left = 4
	popup_style.border_width_top = 4
	popup_style.border_width_right = 4
	popup_style.border_width_bottom = 4
	popup_style.corner_radius_top_left = 10
	popup_style.corner_radius_top_right = 10
	popup_style.corner_radius_bottom_left = 10
	popup_style.corner_radius_bottom_right = 10
	popup_style.shadow_color = Color(0, 0, 0, 0.25)
	popup_style.shadow_size = 12
	popup_style.shadow_offset = Vector2(0, 4)
	settings_popup_container.add_theme_stylebox_override("panel", popup_style)
	
	# 垂直容器
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 40
	vbox.offset_top = 40
	vbox.offset_right = -40
	vbox.offset_bottom = -40
	
	# 標題
	var title_label = Label.new()
	title_label.text = "遊戲設置"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.6, 1))  # 深藍色標題
	title_label.add_theme_constant_override("margin_top", 10)
	title_label.add_theme_constant_override("margin_bottom", 15)
	vbox.add_child(title_label)
	
	# 分隔線
	var title_separator = HSeparator.new()
	title_separator.add_theme_constant_override("separation", 15)
	title_separator.add_theme_constant_override("margin_bottom", 10)
	vbox.add_child(title_separator)
	
	# 初始資金設定
	var starting_money_container = HBoxContainer.new()
	starting_money_container.add_theme_constant_override("separation", 20)
	starting_money_container.add_theme_constant_override("margin_top", 25)
	starting_money_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var starting_money_label = Label.new()
	starting_money_label.text = "初始資金:"
	starting_money_label.custom_minimum_size = Vector2(140, 40)
	starting_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	starting_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	starting_money_label.add_theme_font_size_override("font_size", 16)
	starting_money_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.5, 1))
	starting_money_container.add_child(starting_money_label)
	
	settings_starting_money_spin = SpinBox.new()
	settings_starting_money_spin.min_value = 1000
	settings_starting_money_spin.max_value = 99999
	settings_starting_money_spin.step = 100
	settings_starting_money_spin.value = global.game_settings["starting_money"]
	settings_starting_money_spin.custom_minimum_size = Vector2(200, 40)
	settings_starting_money_spin.value_changed.connect(_validate_settings_values)
	settings_starting_money_spin.add_theme_font_size_override("font_size", 15)
	settings_starting_money_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# SpinBox 樣式
	var spinbox_style = StyleBoxFlat.new()
	spinbox_style.bg_color = Color(1, 1, 1, 1)
	spinbox_style.border_color = Color(0.4, 0.4, 0.6, 1)
	spinbox_style.border_width_left = 2
	spinbox_style.border_width_top = 2
	spinbox_style.border_width_right = 2
	spinbox_style.border_width_bottom = 2
	spinbox_style.corner_radius_top_left = 4
	spinbox_style.corner_radius_top_right = 4
	spinbox_style.corner_radius_bottom_left = 4
	spinbox_style.corner_radius_bottom_right = 4
	settings_starting_money_spin.add_theme_stylebox_override("normal", spinbox_style)
	
	# SpinBox 焦點樣式
	var spinbox_focus_style = spinbox_style.duplicate()
	spinbox_focus_style.border_color = Color(0.2, 0.2, 0.8, 1)  # 藍色邊框
	spinbox_focus_style.border_width_left = 3
	spinbox_focus_style.border_width_top = 3
	spinbox_focus_style.border_width_right = 3
	spinbox_focus_style.border_width_bottom = 3
	settings_starting_money_spin.add_theme_stylebox_override("focus", spinbox_focus_style)
	starting_money_container.add_child(settings_starting_money_spin)
	
	vbox.add_child(starting_money_container)
	
	# 起點獎勵設定
	var pass_bonus_container = HBoxContainer.new()
	pass_bonus_container.add_theme_constant_override("separation", 20)
	pass_bonus_container.add_theme_constant_override("margin_top", 20)
	pass_bonus_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var pass_bonus_label = Label.new()
	pass_bonus_label.text = "起點獎勵:"
	pass_bonus_label.custom_minimum_size = Vector2(140, 40)
	pass_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pass_bonus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pass_bonus_label.add_theme_font_size_override("font_size", 16)
	pass_bonus_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.5, 1))
	pass_bonus_container.add_child(pass_bonus_label)
	
	settings_pass_bonus_spin = SpinBox.new()
	settings_pass_bonus_spin.min_value = 0
	settings_pass_bonus_spin.max_value = 50000
	settings_pass_bonus_spin.step = 100
	settings_pass_bonus_spin.value = global.game_settings["pass_start_bonus"]
	settings_pass_bonus_spin.custom_minimum_size = Vector2(200, 40)
	settings_pass_bonus_spin.value_changed.connect(_validate_settings_values)
	settings_pass_bonus_spin.add_theme_font_size_override("font_size", 15)
	settings_pass_bonus_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# 使用相同的 SpinBox 樣式
	settings_pass_bonus_spin.add_theme_stylebox_override("normal", spinbox_style)
	settings_pass_bonus_spin.add_theme_stylebox_override("focus", spinbox_focus_style)
	pass_bonus_container.add_child(settings_pass_bonus_spin)
	
	vbox.add_child(pass_bonus_container)
	
	# 說明文字
	var note_label = Label.new()
	note_label.text = "只有主機可修改設定，設定會自動同步給所有玩家"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.add_theme_font_size_override("font_size", 13)
	note_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.5, 1))
	note_label.add_theme_constant_override("margin_top", 20)
	vbox.add_child(note_label)
	
	# 按鈕容器
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	button_container.add_theme_constant_override("margin_top", 30)
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_theme_constant_override("margin_left", 20)
	button_container.add_theme_constant_override("margin_right", 20)
	
	var confirm_button = Button.new()
	confirm_button.text = "確定"
	confirm_button.custom_minimum_size = Vector2(100, 45)
	confirm_button.add_theme_font_size_override("font_size", 16)
	
	# 確定按鈕樣式
	var confirm_style = StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.9, 1.0, 0.9, 1)  # 淺綠色背景
	confirm_style.border_color = Color(0, 0.5, 0, 1)  # 綠色邊框
	confirm_style.border_width_left = 2
	confirm_style.border_width_top = 2
	confirm_style.border_width_right = 2
	confirm_style.border_width_bottom = 2
	confirm_style.corner_radius_top_left = 5
	confirm_style.corner_radius_top_right = 5
	confirm_style.corner_radius_bottom_left = 5
	confirm_style.corner_radius_bottom_right = 5
	confirm_button.add_theme_stylebox_override("normal", confirm_style)
	
	# 懸停效果
	var confirm_hover_style = confirm_style.duplicate()
	confirm_hover_style.bg_color = Color(0.8, 1.0, 0.8, 1)  # 更亮的綠色
	confirm_button.add_theme_stylebox_override("hover", confirm_hover_style)
	
	# 按下效果
	var confirm_pressed_style = confirm_style.duplicate()
	confirm_pressed_style.bg_color = Color(0.7, 0.9, 0.7, 1)  # 稍暗的綠色
	confirm_button.add_theme_stylebox_override("pressed", confirm_pressed_style)
	
	# 禁用狀態
	var confirm_disabled_style = confirm_style.duplicate()
	confirm_disabled_style.bg_color = Color(0.8, 0.8, 0.8, 1)  # 灰色
	confirm_disabled_style.border_color = Color(0.5, 0.5, 0.5, 1)
	confirm_button.add_theme_stylebox_override("disabled", confirm_disabled_style)
	
	# 焦點效果
	var confirm_focus_style = confirm_style.duplicate()
	confirm_focus_style.border_color = Color(0, 0.8, 0, 1)  # 亮綠色邊框
	confirm_focus_style.border_width_left = 3
	confirm_focus_style.border_width_top = 3
	confirm_focus_style.border_width_right = 3
	confirm_focus_style.border_width_bottom = 3
	confirm_button.add_theme_stylebox_override("focus", confirm_focus_style)
	
	confirm_button.add_theme_color_override("font_color", Color(0, 0.4, 0, 1))  # 深綠色文字
	confirm_button.pressed.connect(_on_settings_confirm)
	button_container.add_child(confirm_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(100, 45)
	cancel_button.add_theme_font_size_override("font_size", 16)
	
	# 取消按鈕樣式
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(1.0, 0.9, 0.9, 1)  # 淺紅色背景
	cancel_style.border_color = Color(0.5, 0, 0, 1)  # 紅色邊框
	cancel_style.border_width_left = 2
	cancel_style.border_width_top = 2
	cancel_style.border_width_right = 2
	cancel_style.border_width_bottom = 2
	cancel_style.corner_radius_top_left = 5
	cancel_style.corner_radius_top_right = 5
	cancel_style.corner_radius_bottom_left = 5
	cancel_style.corner_radius_bottom_right = 5
	cancel_button.add_theme_stylebox_override("normal", cancel_style)
	
	# 懸停效果
	var cancel_hover_style = cancel_style.duplicate()
	cancel_hover_style.bg_color = Color(1.0, 0.8, 0.8, 1)  # 更亮的紅色
	cancel_button.add_theme_stylebox_override("hover", cancel_hover_style)
	
	# 按下效果
	var cancel_pressed_style = cancel_style.duplicate()
	cancel_pressed_style.bg_color = Color(0.9, 0.7, 0.7, 1)  # 稍暗的紅色
	cancel_button.add_theme_stylebox_override("pressed", cancel_pressed_style)
	
	# 禁用狀態
	var cancel_disabled_style = cancel_style.duplicate()
	cancel_disabled_style.bg_color = Color(0.8, 0.8, 0.8, 1)  # 灰色
	cancel_disabled_style.border_color = Color(0.5, 0.5, 0.5, 1)
	cancel_button.add_theme_stylebox_override("disabled", cancel_disabled_style)
	
	# 焦點效果
	var cancel_focus_style = cancel_style.duplicate()
	cancel_focus_style.border_color = Color(0.8, 0, 0, 1)  # 亮紅色邊框
	cancel_focus_style.border_width_left = 3
	cancel_focus_style.border_width_top = 3
	cancel_focus_style.border_width_right = 3
	cancel_focus_style.border_width_bottom = 3
	cancel_button.add_theme_stylebox_override("focus", cancel_focus_style)
	
	cancel_button.add_theme_color_override("font_color", Color(0.4, 0, 0, 1))  # 深紅色文字
	cancel_button.pressed.connect(_on_settings_cancel)
	button_container.add_child(cancel_button)
	
	# 重置按鈕
	var reset_button = Button.new()
	reset_button.text = "重置"
	reset_button.custom_minimum_size = Vector2(100, 45)
	reset_button.add_theme_font_size_override("font_size", 16)
	reset_button.add_theme_color_override("font_color", Color(0.5, 0.3, 0, 1))  # 橙色文字
	# 重置按鈕樣式
	var reset_style = StyleBoxFlat.new()
	reset_style.bg_color = Color(1.0, 0.95, 0.8, 1)  # 淺橙色背景
	reset_style.border_color = Color(0.6, 0.4, 0, 1)  # 橙色邊框
	reset_style.border_width_left = 2
	reset_style.border_width_top = 2
	reset_style.border_width_right = 2
	reset_style.border_width_bottom = 2
	reset_style.corner_radius_top_left = 5
	reset_style.corner_radius_top_right = 5
	reset_style.corner_radius_bottom_left = 5
	reset_style.corner_radius_bottom_right = 5
	reset_button.add_theme_stylebox_override("normal", reset_style)
	
	# 懸停效果
	var reset_hover_style = reset_style.duplicate()
	reset_hover_style.bg_color = Color(1.0, 0.9, 0.7, 1)  # 更亮的橙色
	reset_button.add_theme_stylebox_override("hover", reset_hover_style)
	
	# 按下效果
	var reset_pressed_style = reset_style.duplicate()
	reset_pressed_style.bg_color = Color(0.9, 0.85, 0.7, 1)  # 稍暗的橙色
	reset_button.add_theme_stylebox_override("pressed", reset_pressed_style)
	
	reset_button.pressed.connect(_on_settings_reset)
	button_container.add_child(reset_button)
	
	vbox.add_child(button_container)
	
	# 組裝
	settings_popup_container.add_child(vbox)
	settings_popup.add_child(settings_popup_container)
	
	add_child(settings_popup)

func _on_settings_confirm():
	# 更新設定
	var new_starting_money = int(settings_starting_money_spin.value)
	var new_pass_bonus = int(settings_pass_bonus_spin.value)
	
	global.game_settings["starting_money"] = new_starting_money
	global.game_settings["pass_start_bonus"] = new_pass_bonus
	
	# 儲存到檔案
	global.save_settings()
	
	# 同步給所有客戶端（並套用到本機）
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		global.rpc("sync_game_settings", global.game_settings)
	else:
		global.sync_game_settings(global.game_settings)
	
	# 淡出和縮小效果後關閉彈出視窗
	var tween = create_tween()
	tween.tween_property(settings_popup_container, "modulate", Color(1, 1, 1, 0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(settings_popup_container, "scale", Vector2(0.9, 0.9), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(settings_popup.hide)
	tween.tween_callback(func(): 
		settings_popup_container.modulate = Color(1, 1, 1, 1)
		settings_popup_container.scale = Vector2(1, 1)
	)
	
	status_label.text = "設定已更新並同步給所有玩家\n起始資金: $%d, 起點獎勵: $%d" % [new_starting_money, new_pass_bonus]
	status_label.modulate = Color.GREEN

func _validate_settings_values(value: float):
	# 驗證設定值
	if settings_starting_money_spin.value < 1000:
		settings_starting_money_spin.value = 1000
	if settings_pass_bonus_spin.value < 0:
		settings_pass_bonus_spin.value = 0

func _on_settings_reset():
	# 重置為預設值
	settings_starting_money_spin.value = 5000
	settings_pass_bonus_spin.value = 5000
	status_label.text = "已重置為預設值"
	status_label.modulate = Color(0.8, 0.5, 0, 1)

func _on_settings_cancel():
	# 淡出和縮小效果後關閉彈出視窗，不儲存變更
	var tween = create_tween()
	tween.tween_property(settings_popup_container, "modulate", Color(1, 1, 1, 0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(settings_popup_container, "scale", Vector2(0.9, 0.9), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(settings_popup.hide)
	tween.tween_callback(func():
		settings_popup_container.modulate = Color(1, 1, 1, 1)
		settings_popup_container.scale = Vector2(1, 1)
	)
	status_label.text = "設定變更已取消"
	status_label.modulate = Color(0.8, 0, 0, 1)

func _input(event):
	# 判斷是否按下 F11 鍵
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	# ESC 鍵關閉設置彈出視窗
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if settings_popup and settings_popup.visible:
			_on_settings_cancel()
	
	# Enter 鍵確認設置
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if settings_popup and settings_popup.visible:
			_on_settings_confirm()
	
	# Tab 鍵在輸入框間導航
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if settings_popup and settings_popup.visible:
			if event.shift_pressed:
				# Shift+Tab 反向導航
				if settings_starting_money_spin.has_focus():
					settings_pass_bonus_spin.grab_focus()
				elif settings_pass_bonus_spin.has_focus():
					settings_starting_money_spin.grab_focus()
			else:
				# Tab 正向導航
				if settings_starting_money_spin.has_focus():
					settings_pass_bonus_spin.grab_focus()
				elif settings_pass_bonus_spin.has_focus():
					settings_starting_money_spin.grab_focus()
	
	# Alt+S 快速聚焦到初始資金輸入框
	if event is InputEventKey and event.pressed and event.keycode == KEY_S and event.alt_pressed:
		if settings_popup and settings_popup.visible:
			settings_starting_money_spin.grab_focus()
	
	# Alt+B 快速聚焦到起點獎勵輸入框
	if event is InputEventKey and event.pressed and event.keycode == KEY_B and event.alt_pressed:
		if settings_popup and settings_popup.visible:
			settings_pass_bonus_spin.grab_focus()
	
	# PageUp/PageDown 快速調整數值
	if event is InputEventKey and event.pressed:
		if settings_popup and settings_popup.visible:
			if settings_starting_money_spin.has_focus():
				if event.keycode == KEY_PAGEUP:
					settings_starting_money_spin.value += 1000
				elif event.keycode == KEY_PAGEDOWN:
					settings_starting_money_spin.value = max(1000, settings_starting_money_spin.value - 1000)
			elif settings_pass_bonus_spin.has_focus():
				if event.keycode == KEY_PAGEUP:
					settings_pass_bonus_spin.value += 1000
				elif event.keycode == KEY_PAGEDOWN:
					settings_pass_bonus_spin.value = max(0, settings_pass_bonus_spin.value - 1000)
				elif event.keycode == KEY_HOME:
					settings_pass_bonus_spin.value = 0
				elif event.keycode == KEY_END:
					settings_pass_bonus_spin.value = 50000
			# Home/End 快速設置
			if settings_starting_money_spin.has_focus():
				if event.keycode == KEY_HOME:
					settings_starting_money_spin.value = 1000
				elif event.keycode == KEY_END:
					settings_starting_money_spin.value = 99999
			
			# 箭頭鍵調整（帶 Ctrl 加速）
			var adjust_amount = 100
			if event.ctrl_pressed:
				adjust_amount = 1000
			
			if settings_starting_money_spin.has_focus():
				if event.keycode == KEY_UP:
					settings_starting_money_spin.value += adjust_amount
				elif event.keycode == KEY_DOWN:
					settings_starting_money_spin.value = max(1000, settings_starting_money_spin.value - adjust_amount)
			elif settings_pass_bonus_spin.has_focus():
				if event.keycode == KEY_UP:
					settings_pass_bonus_spin.value += adjust_amount
				elif event.keycode == KEY_DOWN:
					settings_pass_bonus_spin.value = max(0, settings_pass_bonus_spin.value - adjust_amount)
	
	# Alt+R 快速重置
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and event.alt_pressed:
		if settings_popup and settings_popup.visible:
			_on_settings_reset()
