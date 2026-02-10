extends Control

# 大富翁連線大廳 (Lobby.gd) - 全程式碼生成版
# 這裡包含了 UI 的建立與網路邏輯

# --- [遊戲設定] ---
const DEFAULT_PORT = 7777
const MAX_CLIENTS = 4

# --- [UI 外觀設定] ---
# 您可以在這裡快速調整一些基礎數值，或到底下的 _setup_ui() 進行細部調整
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
	# PRESET_FULL_RECT 讓這個 Control 填滿整個視窗
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# [修改] 使用 CenterContainer 來確保內容絕對置中
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)
	
	# 2. 建立垂直容器 (VBoxContainer) 來自動排列元件
	main_container = VBoxContainer.new()
	# 設定容器內的元件對齊方式
	main_container.alignment = BoxContainer.ALIGNMENT_CENTER
	# 設定元件之間的間距
	main_container.add_theme_constant_override("separation", GAP_SIZE)
	# 將 VBoxContainer 加入到 CenterContainer 中，而不是直接加入根節點
	center_container.add_child(main_container)
	
	# 3. 建立標題 (Label)
	var title = Label.new()
	title.text = "大富翁多人連線"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# [修改技巧] 調整字體大小 (預設約 16px)
	title.add_theme_font_size_override("font_size", 32)
	# [修改技巧] 調整顏色
	title.modulate = Color(1, 0.8, 0.2) # 金黃色
	main_container.add_child(title)
	
	# 4. 建立 IP 輸入欄 (LineEdit)
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "請輸入 Host IP (例如 127.0.0.1)"
	ip_input.text = "127.0.0.1"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# [修改技巧] 設定固定大小
	ip_input.custom_minimum_size = Vector2(INPUT_WIDTH, BTN_HEIGHT)
	main_container.add_child(ip_input)
	
	# 5. 建立按鈕容器 (HBoxContainer) - 讓兩個按鈕並排
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20) # 按鈕左右間距
	main_container.add_child(btn_container)
	
	# 6. 建立按鈕 (Button)
	host_button = _create_styled_button("建立主機 (Host)")
	host_button.pressed.connect(_on_host_pressed)
	btn_container.add_child(host_button)
	
	join_button = _create_styled_button("加入遊戲 (Join)")
	join_button.pressed.connect(_on_join_pressed)
	btn_container.add_child(join_button)
	
	# 7. 建立狀態標籤 (Label)
	status_label = Label.new()
	status_label.text = "準備就緒..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.7, 0.7, 0.7) # 灰色
	main_container.add_child(status_label)

# [輔助函式] 統一建立按鈕樣式，方便一次修改所有按鈕
func _create_styled_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	# 設定最小寬度與高度
	btn.custom_minimum_size = Vector2(140, BTN_HEIGHT)
	# 如果想要滑鼠移上去變色，通常需要設定 Theme，但在純代碼中用 modulate 最快
	# btn.modulate = Color.WHITE 
	return btn

# --- 按鈕事件邏輯 (維持不變) ---

func _on_host_pressed():
	status_label.text = "正在建立伺服器..."
	var error = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if error != OK:
		status_label.text = "建立失敗: " + str(error)
		return
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	status_label.text = "伺服器建立成功！\nIP: " + _get_local_ip()
	status_label.modulate = Color.GREEN
	_disable_buttons()

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

func _on_player_connected(id): status_label.text += "\n玩家加入 ID: " + str(id)
func _on_player_disconnected(id): status_label.text += "\n玩家離開 ID: " + str(id)
func _on_connected_ok():
	status_label.text = "成功加入遊戲！"
	status_label.modulate = Color.GREEN
func _on_connected_fail():
	status_label.text = "連線失敗"
	status_label.modulate = Color.RED
	_reset_ui()
func _on_server_disconnected():
	status_label.text = "伺服器已斷線"
	status_label.modulate = Color.RED
	_reset_ui()

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
