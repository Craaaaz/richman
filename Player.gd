extends Control
class_name Player

# 玩家屬性
var player_id: int = 0
var player_name: String = "Player"
var money: int = 15000 # 初始資金
var grid_pos: Vector2i = Vector2i.ZERO # 當前在地圖網格上的位置
var previous_grid_pos: Vector2i = Vector2i(-999, -999) # 上一個位置 (用於判斷移動方向，初始值設為無效)
var color: Color = Color.WHITE

# 外觀設定
var radius: float = 35.0 # 半徑 (直徑70，小於地圖格100)

func _ready():
	# 設定節點基本大小，確保置中時有參考依據
	custom_minimum_size = Vector2(radius * 2, radius * 2)
	size = custom_minimum_size

func _draw():
	# 繪製實心圓
	# draw_circle(圓心座標, 半徑, 顏色)
	# 因為這是 Control 節點，(size / 2) 就是中心點
	draw_circle(size / 2, radius, color)
	
	# 繪製邊框 (黑色)
	draw_arc(size / 2, radius, 0, TAU, 32, Color.BLACK, 2.0)

# 設定玩家顏色並重繪
func set_color(new_color: Color):
	color = new_color
	queue_redraw()

# 移動到指定的世界座標 (由 Site.gd 計算出來的中心點)
# duration: 移動動畫時間 (秒)
func move_to_world_pos(target_pos: Vector2, duration: float = 0.5):
	# 由於 target_pos 是地塊中心，而 Control 的 position 是左上角
	# 我們需要扣除自身大小的一半來置中
	var centered_pos = target_pos - (size / 2)
	
	# 使用 Tween 進行平滑移動
	var tween = create_tween()
	tween.tween_property(self, "position", centered_pos, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
