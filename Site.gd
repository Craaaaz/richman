extends Control
class_name Site

# 載入地圖配置腳本
const VenueConfig = preload("res://Venue_configuration.gd")
# 載入地圖塊樣式資源
const SITE_BOX_STYLE = preload("res://site_box.tres")

# 地圖塊的大小 (像素)
@export var block_size: Vector2 = Vector2(100, 100)
# 地圖塊之間的間距 (像素)
@export var block_spacing: Vector2 = Vector2(10, 10)
# 地圖起始位置偏移
@export var start_offset: Vector2 = Vector2(50, 50)

# 儲存地圖數據 (方便後續查詢)
# 格式: { Vector2i(grid_x, grid_y): Node(block_instance) }
var grid_instances = {}

# 儲存有效的路徑座標列表
var valid_coordinates: Array[Vector2i] = []

# 外部注入的地圖數據 (若為空則讀取預設配置)
var map_data_override: Array = []

func _ready():
	# 測試用：如果不是由主場景呼叫，可在此測試生成
	# generate_map()
	pass

# 生成地圖的主要函數
func generate_map():
	print("開始生成地圖...")
	
	# 清除舊地圖 (如果有)
	for child in get_children():
		child.queue_free()
	grid_instances.clear()
	valid_coordinates.clear()
	
	var matrix
	
	# 決定使用哪份地圖數據
	if not map_data_override.is_empty():
		print("使用自定義地圖數據")
		matrix = map_data_override
	else:
		print("使用預設地圖配置")
		var config = VenueConfig.new()
		matrix = config.get_map_data()
	
	# 掃描矩陣
	for row_index in range(matrix.size()):
		var row_data = matrix[row_index]
		for col_index in range(row_data.size()):
			var cell_value = row_data[col_index]
			
			# 如果大於 0，則生成地圖塊
			if cell_value > 0:
				_create_block(row_index, col_index, cell_value)

	print("地圖生成完畢，共生成 ", valid_coordinates.size(), " 個地塊")
	
	# 生成完畢後，執行自動適配螢幕
	_fit_map_to_screen()

# 自動縮放並置中地圖
func _fit_map_to_screen():
	if valid_coordinates.is_empty(): return
	
	# 1. 計算地圖的邊界 (以局部座標)
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for grid_pos in valid_coordinates:
		var panel = grid_instances[grid_pos]
		# 取得每個 Panel 的矩形 (相對於 Site 的原點 0,0)
		var rect = Rect2(panel.position, panel.size)
		if rect.position.x < min_x: min_x = rect.position.x
		if rect.position.y < min_y: min_y = rect.position.y
		if rect.end.x > max_x: max_x = rect.end.x
		if rect.end.y > max_y: max_y = rect.end.y
	
	var map_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	
	# 2. 取得螢幕大小 (viewport)
	var viewport_rect = get_viewport_rect()
	# 預留邊距 (padding)
	var padding = 50.0
	var available_size = viewport_rect.size - Vector2(padding * 2, padding * 2)
	
	# 3. 計算縮放比例 (Uniform Scale)
	# 比較 寬度比 和 高度比，取較小者以確保完整放入
	var scale_x = available_size.x / map_rect.size.x
	var scale_y = available_size.y / map_rect.size.y
	var final_scale = min(scale_x, scale_y)
	
	# 如果地圖本身就很小，不要放大超過 1.0 (避免糊掉)，除非你希望它總是填滿
	# 這裡我們允許放大，因為是幾何圖形
	# final_scale = min(final_scale, 1.0) 
	
	scale = Vector2(final_scale, final_scale)
	print("地圖縮放比例: ", final_scale)
	
	# 4. 計算置中位置
	# 讓 Site 的中心點對齊螢幕中心
	# 但 Site 的 pivot 預設是左上角 (0,0)
	
	# 計算縮放後的地圖中心點 (在 Site 座標系下)
	var map_center_local = map_rect.get_center()
	# 螢幕中心
	var screen_center = viewport_rect.size / 2
	
	# 算式推導:
	# 目標: (map_center_local * scale) + position = screen_center
	# position = screen_center - (map_center_local * scale)
	
	position = screen_center - (map_center_local * scale)
	print("地圖置中位置: ", position)

# 建立單個地圖塊
func _create_block(row: int, col: int, type: int = 1):
	var panel = Panel.new()
	
	# 設定樣式
	panel.add_theme_stylebox_override("panel", SITE_BOX_STYLE)
	
	# 設定大小
	panel.custom_minimum_size = block_size
	panel.size = block_size
	
	# 根據類型設定顏色與標籤
	var color = Color.WHITE
	var label_text = ""
	
	match type:
		1: # Road
			color = Color.WHITE
		2: # Start
			color = Color(1, 0.9, 0.2) # Yellow
			label_text = "起點"
		3: # Property
			color = Color(0.3, 0.6, 1.0) # Blue
			label_text = "地產"
		4: # Shop
			color = Color(1.0, 0.4, 0.7) # Pink
			label_text = "商店"
		_:
			color = Color.GRAY
	
	panel.modulate = color
	
	# 如果有文字，加入 Label
	if label_text != "":
		var lbl = Label.new()
		lbl.text = label_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 反轉顏色以保持對比 (因為底色有變)
		lbl.add_theme_color_override("font_color", Color.BLACK)
		lbl.add_theme_color_override("font_outline_color", Color.WHITE)
		lbl.add_theme_constant_override("outline_size", 2)
		panel.add_child(lbl)
	
	# 儲存類型數據到 metadata (方便後續查詢)
	panel.set_meta("tile_type", type)
	
	# 計算位置 (Col 對應 X, Row 對應 Y)
	var pos_x = start_offset.x + col * (block_size.x + block_spacing.x)
	var pos_y = start_offset.y + row * (block_size.y + block_spacing.y)
	panel.position = Vector2(pos_x, pos_y)
	
	# 加入場景
	add_child(panel)
	
	# 記錄數據
	var grid_pos = Vector2i(col, row)
	grid_instances[grid_pos] = panel
	valid_coordinates.append(grid_pos)
	
	# 可以在這裡為每個地塊命名，方便除錯
	panel.name = "Site_%d_%d" % [col, row]

# 獲取地圖塊類型
func get_tile_type(grid_pos: Vector2i) -> int:
	if grid_instances.has(grid_pos):
		var panel = grid_instances[grid_pos]
		if panel.has_meta("tile_type"):
			return panel.get_meta("tile_type")
	return 0

# 獲取世界座標位置 (根據網格座標)
func get_world_position(grid_pos: Vector2i) -> Vector2:
	if grid_instances.has(grid_pos):
		# 回傳該地塊的中心點
		var panel = grid_instances[grid_pos]
		return panel.position + panel.size / 2
	return Vector2.ZERO

# 檢查某個網格座標是否是有效的地圖塊
func is_valid_site(grid_pos: Vector2i) -> bool:
	return grid_instances.has(grid_pos)

# 獲取所有有效空位的列表 (用於隨機出生點)
func get_all_valid_sites() -> Array[Vector2i]:
	return valid_coordinates

# --- 路徑查詢功能 ---

# 取得指定格子的所有相鄰有效格子 (上、下、左、右)
func get_valid_neighbors(current_pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	for dir in directions:
		var neighbor_pos = current_pos + dir
		if is_valid_site(neighbor_pos):
			neighbors.append(neighbor_pos)
			
	return neighbors

# 判斷兩個格子是否相鄰
func is_neighbor(pos_a: Vector2i, pos_b: Vector2i) -> bool:
	return pos_a.distance_squared_to(pos_b) == 1
