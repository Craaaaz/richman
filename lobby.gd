extends Control

# 大富翁連線大廳 (Lobby.gd)
# 用於建立連線、加入遊戲與管理連線狀態

# 預設連線設定
const DEFAULT_PORT = 7777
const MAX_CLIENTS = 4

# 網路物件
var peer = ENetMultiplayerPeer.new()

# UI 元件 (會在 _ready 動態建立，方便您直接掛載測試)
var main_container: VBoxContainer
var ip_input: LineEdit
var status_label: Label
var host_button: Button
var join_button: Button

func _ready():
	# 建立簡易 UI
	_setup_ui()
	
	# 連接網路訊號 (Signal)
	# 當有玩家連線進來 (Server 端觸發)
	multiplayer.peer_connected.connect(_on_player_connected)
	# 當有玩家斷線 (Server 端觸發)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	# 當成功連上 Server (Client 端觸發)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	# 當連線失敗 (Client 端觸發)
	multiplayer.connection_failed.connect(_on_connected_fail)
	# 當與 Server 斷開 (Client 端觸發)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _setup_ui():
	# 設定根節點填滿螢幕
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
	ip_input.text = "127.0.0.1" 
	ip_input.placeholder_text = "輸入 Host IP"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER # 文字置中
	ip_input.custom_minimum_size = Vector2(300, 40) # 稍微加寬加高
	main_container.add_child(ip_input)
	
	# 按鈕容器
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
	
	status_label.text = "伺服器已建立！等待玩家加入...\n(您的 IP: " + _get_local_ip() + ")"
	status_label.modulate = Color.GREEN
	_disable_buttons()
	
	# 這裡可以載入遊戲主場景，或者等待所有玩家到齊
	# change_scene_to_game()

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
	_disable_buttons()

# --- 網路事件回調 ---

func _on_player_connected(id):
	# 這是 Server 端會收到的訊號 (或是其他 Client 收到有人加入)
	status_label.text += "\n玩家已連線 (ID: " + str(id) + ")"

func _on_player_disconnected(id):
	status_label.text += "\n玩家離開 (ID: " + str(id) + ")"

func _on_connected_ok():
	# 這是 Client 端成功連上 Server 後觸發
	status_label.text = "連線成功！已加入遊戲。"
	status_label.modulate = Color.GREEN

func _on_connected_fail():
	# 這是 Client 端連線失敗觸發
	status_label.text = "連線失敗，請檢查 IP 或防火牆。"
	status_label.modulate = Color.RED
	_reset_ui()

func _on_server_disconnected():
	# Server 關閉或斷線
	status_label.text = "與伺服器斷開連線。"
	status_label.modulate = Color.RED
	_reset_ui()

# --- 輔助功能 ---

func _disable_buttons():
	host_button.disabled = true
	join_button.disabled = true
	ip_input.editable = false

func _reset_ui():
	host_button.disabled = false
	join_button.disabled = false
	ip_input.editable = true
	multiplayer.multiplayer_peer = null # 清除 peer

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
