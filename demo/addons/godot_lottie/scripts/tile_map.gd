@tool

extends TileMap

enum Tile { OBSTACLE, START_POINT, END_POINT }

@onready var game_map: TileMap = $"."  # Reference to the current TileMap

const CELL_SIZE = Vector2i(64, 32)
const BASE_LINE_WIDTH = 3.0
const DRAW_COLOR = Color.WHITE * Color(1, 1, 1, 0.5)

# Object for 2D grid pathfinding
var _astar = AStarGrid2D.new()

var _start_point = Vector2i()
var _end_point = Vector2i()
var _path = PackedVector2Array()

# List of tiles with ID 2 and ID 3 that should be treated specially
var _ignored_tiles = []

# Path local para exibição (suavizado/arredondado)
var _display_path = PackedVector2Array()

# Cache para otimização de pesos
var _weight_cache := {}  # Guarda pesos calculados


# --- INÍCIO BLOCO GRID F3 (para futura remoção) ---
var _show_grid_lines := true

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_show_grid_lines = !_show_grid_lines
		queue_redraw()

func _draw():
	if _path.is_empty() and not _show_grid_lines:
		return

	# Desenha o caminho (suavizado se disponível)
	var draw_points: PackedVector2Array = _display_path if not _display_path.is_empty() else PackedVector2Array()
	if draw_points.is_empty() and not _path.is_empty():
		for c in _path:
			draw_points.append(map_to_local(c))

	if not draw_points.is_empty():
		var last_point = draw_points[0]
		for index in range(1, draw_points.size()):
			var current_point = draw_points[index]
			draw_line(last_point, current_point, DRAW_COLOR, BASE_LINE_WIDTH, true)
			draw_circle(current_point, BASE_LINE_WIDTH * 1.0, DRAW_COLOR)
			last_point = current_point

	# Draw grid lines if enabled
	if _show_grid_lines:
		# Use get_used_rect to cover toda a área da grid, não só as células usadas
		var rect = get_used_rect()
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				var cell = Vector2i(x, y)
				var center = map_to_local(cell)
				var half_w = CELL_SIZE.x / 2.0
				var half_h = CELL_SIZE.y / 2.0
				var p0 = center + Vector2(0, -half_h)
				var p1 = center + Vector2(half_w, 0)
				var p2 = center + Vector2(0, half_h)
				var p3 = center + Vector2(-half_w, 0)
				var grid_color = Color(0.2, 0.5, 1.0, 0.5) # azul semi-transparente
				draw_line(p0, p1, grid_color, 0.5, true)
				draw_line(p1, p2, grid_color, 0.5, true)
				draw_line(p2, p3, grid_color, 0.5, true)
				draw_line(p3, p0, grid_color, 0.5, true)
# --- FIM BLOCO GRID F3 ---

func _ready():
	# Configure AStarGrid2D
	_astar.region = game_map.get_used_rect()  # Define the grid region based on the TileMap
	_astar.cell_size = CELL_SIZE
	_astar.cell_shape = AStarGrid2D.CELL_SHAPE_ISOMETRIC_RIGHT #Configure the isometric layout
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES

	# Update AStarGrid2D
	_astar.update()

	# Define solid (non-walkable) cells based on the TileMap
	for i in range(_astar.region.position.x, _astar.region.end.x):
		for j in range(_astar.region.position.y, _astar.region.end.y):
			var pos = Vector2i(i, j)
			var tile_id = get_cell_source_id(0, pos)
			# Adiciona tiles com ID 2, 3 e 4 à lista especial
			if tile_id == 2 or tile_id == 3 or tile_id == 4:
				_ignored_tiles.append(pos)
			# Mark as solid if not walkable and not ID 2 or ID 3
			elif tile_id != 1:
				_astar.set_point_solid(pos)

func round_local_position(local_position):
	return map_to_local(local_to_map(local_position))

func is_point_walkable(local_position):
	var map_position = local_to_map(local_position)
	if _astar.is_in_boundsv(map_position):
		return not _astar.is_point_solid(map_position)
	return false

func clear_path():
	if not _path.is_empty():
		_path.clear()
	if not _display_path.is_empty():
		_display_path.clear()
	queue_redraw()

func find_path(local_start_point, local_end_point, mp_limit: int = -1):
	clear_path()
	_start_point = local_to_map(local_start_point)
	_end_point = local_to_map(local_end_point)

	# Aplica pesos táticos: adjacências a sólidos (evita grudar em obstáculos)
	_update_weights()

	# OTIMIZADO: bloqueia apenas tiles especiais que NÃO são destino
	var blocked_specials := []
	for pos in _ignored_tiles:
		if pos != _end_point:
			_astar.set_point_solid(pos, true)
			blocked_specials.append(pos)  # Guarda quais bloqueamos

	# Checa se o destino é um portal (ID 3 ou 4)
	var tile_id = get_cell_source_id(0, _end_point)
	if tile_id == 3:
		# Portal ID 3: entradas cima/baixo
		var front_point = _end_point + Vector2i(0, -1)  # cima
		var back_point = _end_point + Vector2i(0, 1)    # baixo

		# Verifica acessibilidade considerando bounds e se está sólido
		var front_accessible = _astar.is_in_boundsv(front_point) and not _astar.is_point_solid(front_point)
		var back_accessible = _astar.is_in_boundsv(back_point) and not _astar.is_point_solid(back_point)

		var selected_point
		# Prioriza entrada aberta: se uma está fechada, usa a outra automaticamente
		if front_accessible and not back_accessible:
			selected_point = front_point
		elif back_accessible and not front_accessible:
			selected_point = back_point
		elif front_accessible and back_accessible:
			# Ambas abertas: escolhe a mais próxima do ponto de partida
			var dist_front = front_point.distance_to(_start_point)
			var dist_back = back_point.distance_to(_start_point)
			selected_point = front_point if dist_front <= dist_back else back_point
		else:
			# Nenhuma acessível
			return []

		_path = _astar.get_id_path(_start_point, selected_point)
		if _path.is_empty():
			return []
		_path.append(_end_point)

	elif tile_id == 4:
		# Portal ID 4: entradas esquerda/direita
		var left_point = _end_point + Vector2i(-1, 0)   # esquerda
		var right_point = _end_point + Vector2i(1, 0)   # direita

		# Verifica acessibilidade considerando bounds e se está sólido
		var left_accessible = _astar.is_in_boundsv(left_point) and not _astar.is_point_solid(left_point)
		var right_accessible = _astar.is_in_boundsv(right_point) and not _astar.is_point_solid(right_point)

		var selected_point
		# Prioriza entrada aberta: se uma está fechada, usa a outra automaticamente
		if left_accessible and not right_accessible:
			selected_point = left_point
		elif right_accessible and not left_accessible:
			selected_point = right_point
		elif left_accessible and right_accessible:
			# Ambas abertas: escolhe a mais próxima do ponto de partida
			var dist_left = left_point.distance_to(_start_point)
			var dist_right = right_point.distance_to(_start_point)
			selected_point = left_point if dist_left <= dist_right else right_point
		else:
			# Nenhuma acessível
			return []

		_path = _astar.get_id_path(_start_point, selected_point)
		if _path.is_empty():
			return []
		_path.append(_end_point)

	else:
		# Caminho normal para outros tiles
		_path = _astar.get_id_path(_start_point, _end_point)

	# OTIMIZADO: Restaura APENAS tiles que bloqueamos (não todos)
	for pos in blocked_specials:
		_astar.set_point_solid(pos, false)

	# Limita o caminho por MP (se informado)
	if mp_limit > 0 and _path.size() > mp_limit + 1:
		var limited := PackedVector2Array()
		for i in range(0, mp_limit + 1):
			limited.append(_path[i])
		_path = limited

	if not _path.is_empty():
		queue_redraw()

	# OTIMIZADO: Converte path e suaviza em um único loop
	var path_positions := []
	path_positions.resize(_path.size())
	for i in _path.size():
		path_positions[i] = map_to_local(_path[i])
	
	# Suaviza apenas cantos (mantém trechos retos perfeitamente retos)
	_display_path.clear()
	var display_result := []
	
	if path_positions.size() >= 3:
		# Arredonda cantos com Bézier
		var rounded := _round_path_corners(path_positions, 16.0, 6)
		_display_path.resize(rounded.size())
		display_result.resize(rounded.size())
		for i in rounded.size():
			_display_path[i] = rounded[i]
			display_result[i] = rounded[i]
	else:
		# Path curto, sem suavização
		_display_path = PackedVector2Array(path_positions)
		display_result = path_positions.duplicate()
	
	# Retorna Array normal para compatibilidade com character.gd
	return display_result

# Aplica pesos táticos: adjacências a sólidos (evita grudar em obstáculos)
# OTIMIZADO: usa cache para evitar recalcular pesos desnecessariamente
func _update_weights() -> void:
	# Se já calculamos antes, reutiliza cache
	if not _weight_cache.is_empty():
		# Aplica cache
		for pos in _weight_cache:
			_astar.set_point_weight_scale(pos, _weight_cache[pos])
		return
	
	# Cache vazio, calcula pesos pela primeira vez
	var cells_to_modify := {}
	
	# Adjacent to solid tiles (evitar grudar em obstáculos)
	for x in range(_astar.region.position.x, _astar.region.end.x):
		for y in range(_astar.region.position.y, _astar.region.end.y):
			var solid := Vector2i(x, y)
			if _astar.is_point_solid(solid):
				# Aplica peso 2.0 nas 4 direções cardeais adjacentes
				var adjacents := [
					Vector2i(1, 0), Vector2i(-1, 0), 
					Vector2i(0, 1), Vector2i(0, -1)
				]
				for d in adjacents:
					var n: Vector2i = solid + d
					if _astar.is_in_boundsv(n) and not _astar.is_point_solid(n):
						cells_to_modify[n] = 2.0
	
	# Aplica pesos e salva no cache
	for pos in cells_to_modify:
		_astar.set_point_weight_scale(pos, cells_to_modify[pos])
		_weight_cache[pos] = cells_to_modify[pos]
# Arredonda cantos usando Bézier quadrática; mantém retas intactas
func _round_path_corners(points: Array, radius: float, segments_per_corner: int) -> Array:
	if points.size() <= 2:
		return points
	
	var result: Array = []
	result.append(points[0])
	
	for i in range(1, points.size() - 1):
		var prev: Vector2 = points[i - 1]
		var curr: Vector2 = points[i]
		var next: Vector2 = points[i + 1]
		
		var v_in: Vector2 = curr - prev
		var v_out: Vector2 = next - curr
		var len_in: float = max(0.0001, v_in.length())
		var len_out: float = max(0.0001, v_out.length())
		var dir_in: Vector2 = v_in / len_in
		var dir_out: Vector2 = v_out / len_out
		
		# se quase reto, não arredonda
		var dot: float = dir_in.dot(dir_out)
		if dot > 0.997: # ~4.5 graus
			result.append(curr)
			continue
		
		# limita o raio ao comprimento disponível de cada segmento
		var r: float = min(radius, len_in * 0.45, len_out * 0.45)
		var p1: Vector2 = curr - dir_in * r
		var p2: Vector2 = curr + dir_out * r
		
		# adiciona ponto final do segmento reto antes do canto
		result.append(p1)
		
		# cria arco suave (Bézier quadrática) com controle no vértice original
		for s in range(1, segments_per_corner + 1):
			var t: float = float(s) / float(segments_per_corner)
			var one: float = 1.0 - t
			var q: Vector2 = one * one * p1 + 2.0 * one * t * curr + t * t * p2
			result.append(q)
	
	# adiciona o último ponto
	result.append(points[points.size() - 1])
	return result
