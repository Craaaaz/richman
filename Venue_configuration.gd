extends Node
class_name VenueConfiguration

# 地圖矩陣配置
# 0: 空白 (無地塊)
# 1: 普通地圖塊 (可移動路徑)
# 2: 起點 (Start)
# 3: 地產 (Property) - 玩家可購買
# 4: 商店 (Shop) - 暫未實作
var map_matrix: Array[Array] = [
	[3, 1, 3, 1, 3, 0, 3, 1, 3],
	[1, 0, 0, 0, 1, 1, 1, 0, 1],
	[3, 0, 0, 0, 0, 0, 0, 0, 3],
	[1, 0, 0, 0, 0, 0, 0, 0, 1],
	[3, 0, 0, 0, 0, 0, 0, 0, 3],
	[2, 1, 3, 1, 3, 1, 3, 1, 1]
]

# 獲取地圖數據
func get_map_data() -> Array[Array]:
	return map_matrix

# 獲取地圖尺寸 (行數, 列數)
func get_map_size() -> Vector2i:
	if map_matrix.is_empty():
		return Vector2i.ZERO
	return Vector2i(map_matrix[0].size(), map_matrix.size())
