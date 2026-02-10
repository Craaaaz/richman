extends Control
class_name MapEditor

signal map_saved(new_map_data: Array)
signal editor_closed

# 固定目標編輯大小
const TARGET_ROWS = 20
const TARGET_COLS = 20

var map_data: Array = []
var grid_container: GridContainer
var row_count: int = TARGET_ROWS
var col_count: int = TARGET_COLS

# UI 元件
var bg_panel: Panel
var save_button: Button
var cancel_button: Button

func _ready():
	# 全螢幕背景
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	bg_panel = Panel.new()
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 設定深色背景
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	bg_panel.add_theme_stylebox_override("panel", style)
	add_child(bg_panel)
	
	# 使用 VBoxContainer 作為最上層的垂直佈局
	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 加入一些內邊距，避免貼邊
	root_vbox.add_theme_constant_override("margin_top", 20)
	root_vbox.add_theme_constant_override("margin_bottom", 20)
	add_child(root_vbox)
	
	# 1. 標題區域
	var title = Label.new()
	title.text = "地圖編輯器 (點擊切換路徑)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	root_vbox.add_child(title)
	
	# 2. 中間滾動區域 (使用 Size Flags 讓它佔據剩餘空間)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 讓內容置中
	var scroll_center = CenterContainer.new()
	scroll_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_center)
	root_vbox.add_child(scroll)
	
	var main_vbox = VBoxContainer.new()
	scroll_center.add_child(main_vbox)
	
	# 網格容器
	grid_container = GridContainer.new()
	main_vbox.add_child(grid_container)
	
	# 3. 底部按鈕區域
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 30)
	# 確保它在最底部顯示，且不會被壓縮
	btn_hbox.custom_minimum_size = Vector2(0, 60)
	root_vbox.add_child(btn_hbox)
	
	save_button = Button.new()
	save_button.text = "儲存變更"
	save_button.custom_minimum_size = Vector2(120, 40)
	save_button.modulate = Color.GREEN
	save_button.pressed.connect(_on_save_pressed)
	btn_hbox.add_child(save_button)
	
	cancel_button = Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(120, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	btn_hbox.add_child(cancel_button)

# 初始化編輯器數據
func setup_editor(initial_data: Array):
	# 初始化一個全 0 的 20x20 矩陣
	map_data = []
	for r in range(TARGET_ROWS):
		var row = []
		for c in range(TARGET_COLS):
			row.append(0)
		map_data.append(row)
	
	# 如果有傳入舊數據，將其複製到新矩陣的中心或左上角
	# 這裡我們嘗試保留原樣 (左上角對齊)
	if not initial_data.is_empty():
		var old_rows = initial_data.size()
		var old_cols = initial_data[0].size()
		
		for r in range(min(old_rows, TARGET_ROWS)):
			for c in range(min(old_cols, TARGET_COLS)):
				map_data[r][c] = initial_data[r][c]
		
	row_count = TARGET_ROWS
	col_count = TARGET_COLS
	
	_refresh_grid()

# 重新整理網格顯示
func _refresh_grid():
	# 清除舊按鈕
	for child in grid_container.get_children():
		child.queue_free()
	
	# 設定 GridContainer 的列數
	grid_container.columns = col_count
	
	# 產生按鈕
	for r in range(row_count):
		for c in range(col_count):
			var val = map_data[r][c]
			var btn = Button.new()
			# 按鈕小一點以免 20x20 太大
			btn.custom_minimum_size = Vector2(30, 30) 
			btn.toggle_mode = true
			btn.button_pressed = (val == 1)
			
			# 設定按鈕樣式 (使用 StyleBoxFlat 確保純色)
			btn.add_theme_stylebox_override("normal", _get_button_style(val))
			btn.add_theme_stylebox_override("hover", _get_button_style(val))
			btn.add_theme_stylebox_override("pressed", _get_button_style(val))
			btn.add_theme_stylebox_override("focus", _get_empty_style()) # 移除焦點框干擾
			
			# 設定 toggle 狀態
			btn.toggle_mode = true
			btn.button_pressed = (val > 0)
			
			# 連接訊號
			btn.toggled.connect(_on_cell_toggled.bind(r, c, btn))
			
			grid_container.add_child(btn)

# 取得對應顏色的樣式
func _get_button_style(val: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	if val > 0:
		style.bg_color = Color.WHITE # 有東西 = 純白
	else:
		style.bg_color = Color.BLACK # 沒東西 = 純黑
	return style

func _get_empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

# 當格子被點擊
func _on_cell_toggled(pressed: bool, row: int, col: int, btn: Button):
	# 更新數據 (注意：這裡簡單編輯器只會設回 1，會覆蓋掉特殊的 2,3,4 類型)
	var new_val = 1 if pressed else 0
	map_data[row][col] = new_val
	
	# 更新視覺
	btn.add_theme_stylebox_override("normal", _get_button_style(new_val))
	btn.add_theme_stylebox_override("hover", _get_button_style(new_val))
	btn.add_theme_stylebox_override("pressed", _get_button_style(new_val))

func _on_save_pressed():
	map_saved.emit(map_data)
	queue_free()

func _on_cancel_pressed():
	editor_closed.emit()
	queue_free()
