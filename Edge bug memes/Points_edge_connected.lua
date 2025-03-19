-- Основные элементы интерфейса
local ref = gui.Reference("MISC", "ENCHANCEMENT")
local main_group = gui.Groupbox(ref, "Система определения краёв с BBox", 16, 16, 296, 296)

-- Настройки для определения краёв
local edge_enable = gui.Checkbox(main_group, "edge_detector_enable", "Включить определение краёв", true)
local edge_color = gui.ColorPicker(edge_enable, "edge_color", "Цвет маркера края", 255, 0, 0, 255)
local edge_size = gui.Slider(main_group, "edge_size", "Размер маркера", 4, 1, 15)
local edge_distance = gui.Slider(main_group, "edge_distance", "Дистанция обнаружения", 150, 50, 500)
local edge_raycount = gui.Slider(main_group, "edge_raycount", "Количество лучей", 24, 8, 48)
local edge_precision = gui.Slider(main_group, "edge_precision", "Точность обнаружения", 8, 2, 16)
local edge_height = gui.Slider(main_group, "edge_height", "Высота проверки прыжка", 72, 32, 128)

-- Настройки для линий и BBox
local line_enable = gui.Checkbox(main_group, "line_enable", "Соединять точки линиями", true)
local line_color = gui.ColorPicker(line_enable, "line_color", "Цвет линий", 0, 255, 0, 255)
local line_thickness = gui.Slider(main_group, "line_thickness", "Толщина линий", 2, 1, 5)
local height_tolerance = gui.Slider(main_group, "height_tolerance", "Допуск по высоте для группировки", 1, 0.1, 10, 0.1)

-- Настройки для BBox и траектории
local visualize_bbox = gui.Checkbox(main_group, "eb_visual", "Активировать визуализацию BBox", true)
local bbox_color = gui.ColorPicker(main_group, "bbox_color", "Цвет BBox", 0, 0, 255, 150)
local back_edges_color = gui.ColorPicker(main_group, "back_edges_color", "Цвет задних рёбер", 255, 0, 0, 255)
local trajectory_color = gui.ColorPicker(visualize_bbox, "eb_trajectory_color", "Цвет траектории", 0, 255, 0, 255)

-- Настройки для предсказания траектории
local prediction_ticks = gui.Slider(main_group, "eb_pred_ticks", "Кол-во тиков предикшона", 15, 1, 64, 1)
local prediction_substeps = gui.Slider(main_group, "eb_pred_substeps", "Промежуточные шаги", 3, 1, 10, 1)

-- Настройки для остановки движения
local auto_stop = gui.Checkbox(main_group, "auto_stop", "Автостоп у линии", true)
local stop_distance = gui.Slider(main_group, "stop_distance", "Погрешность остановки (единиц)", 5, 1, 20, 1)
local stop_visualization = gui.Checkbox(main_group, "stop_visual", "Визуализация точки остановки", true)
local stop_color = gui.ColorPicker(stop_visualization, "stop_color", "Цвет индикатора остановки", 255, 255, 0, 255)
-- Функции для работы с векторами
local function CreateVector(x, y, z)
    return {x = x or 0, y = y or 0, z = z or 0}
end

local function VectorAdd(v1, v2)
    return CreateVector(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z)
end

local function VectorSubtract(v1, v2)
    return CreateVector(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z)
end

local function VectorMultiply(v, scalar)
    return CreateVector(v.x * scalar, v.y * scalar, v.z * scalar)
end

local function VectorLength(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function VectorDistance(v1, v2)
    local dx, dy, dz = v1.x - v2.x, v1.y - v2.y, v1.z - v2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function VectorNormalize(v)
    local length = VectorLength(v)
    if length > 0 then
        return CreateVector(v.x / length, v.y / length, v.z / length)
    end
    return CreateVector(0, 0, 0)
end

local function VectorCopy(v)
    return CreateVector(v.x, v.y, v.z)
end

local function Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

-- Функции для конвертации между нашими векторами и Vector3
local function ToVector3(v)
    return Vector3(v.x, v.y, v.z)
end

local function FromVector3(v)
    return CreateVector(v.x, v.y, v.z)
end

-- Функция для получения направления по углу
local function AngleToDirection(angle_deg)
    local rad = math.rad(angle_deg)
    return CreateVector(math.cos(rad), math.sin(rad), 0)
end


-- Получение позиции игрока
local function GetPlayerPosition()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return nil end
    
    local origin = player:GetAbsOrigin()
    return FromVector3(origin)
end

-- Функция для получения направления движения игрока
local function GetPlayerDirection()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then
        return CreateVector(0, 1, 0) -- Направление по умолчанию
    end
    
    local velocity = player:GetPropVector("m_vecVelocity")
    local vel = CreateVector(velocity.x, velocity.y, 0) -- Игнорируем вертикальную составляющую
    
    if VectorLength(vel) < 0.1 then
        -- Если игрок почти неподвижен, используем направление взгляда
        local angles = player:GetPropVector("m_angEyeAngles")
        local rad = math.rad(angles.y)
        return CreateVector(math.cos(rad), math.sin(rad), 0)
    end
    
    return VectorNormalize(vel)
end

-- Улучшенная функция трассировки для CS2
local function TraceCollision(start_pos, end_pos)
    -- Используем Vector3 для функций игрового движка
    local trace_start = ToVector3(start_pos)
    local trace_end = ToVector3(end_pos)
    
    -- Используем MASK_PLAYERSOLID (0x201B) для определения коллизий игрока
    local result = engine.TraceLine(trace_start, trace_end, 0x201B)
    
    -- Обработка различных типов результата трассировки
    local fraction = 1.0
    if type(result) == "userdata" then
        -- Проверяем, есть ли свойство fraction в объекте result
        pcall(function() fraction = result.fraction end)
    elseif type(result) == "number" then
        fraction = result
    end
    
    -- Вычисляем точку столкновения
    local hit_pos = {
        x = start_pos.x + (end_pos.x - start_pos.x) * fraction,
        y = start_pos.y + (end_pos.y - start_pos.y) * fraction,
        z = start_pos.z + (end_pos.z - start_pos.z) * fraction
    }
    
    return {
        fraction = fraction,
        hit_pos = hit_pos,
        is_hit = fraction < 0.99
    }
end

-- Улучшенная функция поиска земли под игроком
local function FindGround(pos, max_distance)
    max_distance = max_distance or 150
    
    local down_end = CreateVector(pos.x, pos.y, pos.z - max_distance)
    local trace_result = TraceCollision(pos, down_end)
    
    if trace_result.is_hit then
        return trace_result.hit_pos
    end
    
    return nil
end

-- Функция проверки безопасности прыжка с края
local function IsJumpSafe(edge_pos, direction, height)
    -- Проверка горизонтального пространства
    local horizontal_end = VectorAdd(edge_pos, VectorMultiply(direction, height))
    local horizontal_trace = TraceCollision(edge_pos, horizontal_end)
    if horizontal_trace.is_hit then
        return false -- Есть препятствие на горизонтальном пути
    end
    
    -- Проверка вертикального пространства
    local vertical_end = VectorAdd(edge_pos, CreateVector(0, 0, height))
    local vertical_trace = TraceCollision(edge_pos, vertical_end)
    if vertical_trace.is_hit then
        return false -- Есть препятствие на вертикальном пути
    end
    
    -- Проверка диагонального пространства (45 градусов)
    local diagonal_dir = CreateVector(
        direction.x * 0.7071, 
        direction.y * 0.7071, 
        0.7071
    )
    local diagonal_end = VectorAdd(edge_pos, VectorMultiply(diagonal_dir, height * 1.414))
    local diagonal_trace = TraceCollision(edge_pos, diagonal_end)
    if diagonal_trace.is_hit then
        return false -- Есть препятствие на диагональном пути
    end
    
    return true -- Прыжок безопасен
end

-- Основная функция определения краёв
local function DetectEdges()
    local player_pos = GetPlayerPosition()
    if not player_pos then return {} end
    
    -- Находим поверхность под игроком
    local standing_pos = CreateVector(player_pos.x, player_pos.y, player_pos.z + 5)
    local ground_pos = FindGround(standing_pos)
    if not ground_pos then return {} end
    
    local max_distance = edge_distance:GetValue()
    local num_rays = edge_raycount:GetValue()
    local ray_precision = edge_precision:GetValue()
    local angle_step = 360 / num_rays
    local jump_height = edge_height:GetValue()
    local safe_edges = {}
    
    -- Сканируем во всех направлениях
    for i = 1, num_rays do
        local current_angle = i * angle_step
        local direction = AngleToDirection(current_angle)
        
        -- Двухэтапный поиск края
        local found_edge = false
        local edge_pos = nil
        
        -- 1. Грубый поиск
        local coarse_step_size = max_distance / 10
        for coarse_step = 1, 10 do
            local coarse_dist = coarse_step * coarse_step_size
            local check_pos = VectorAdd(ground_pos, VectorMultiply(direction, coarse_dist))
            
            -- Проверка, есть ли под этой точкой земля
            local floor_check = FindGround(check_pos, 15) -- Небольшая глубина проверки
            
            if not floor_check then
                -- Нашли потенциальный край, переходим к точному поиску
                local previous_pos = VectorAdd(ground_pos, VectorMultiply(direction, (coarse_step - 1) * coarse_step_size))
                
                -- 2. Точный поиск
                local fine_step_size = coarse_step_size / ray_precision
                for fine_step = 1, ray_precision do
                    local fine_dist = (coarse_step - 1) * coarse_step_size + fine_step * fine_step_size
                    local fine_check_pos = VectorAdd(ground_pos, VectorMultiply(direction, fine_dist))
                    
                    -- Проверка земли с высокой точностью
                    local fine_floor_check = FindGround(fine_check_pos, 15)
                    
                    if not fine_floor_check then
                        -- Нашли точный край
                        edge_pos = VectorAdd(ground_pos, VectorMultiply(direction, fine_dist - fine_step_size))
                        found_edge = true
                        break
                    end
                end
                
                if found_edge then break end
            end
        end
        
        -- Если нашли край, проверяем, безопасен ли он для прыжка
        if edge_pos and found_edge then
            -- Проверяем, нет ли препятствий при прыжке с этого края
            if IsJumpSafe(edge_pos, direction, jump_height) then
                -- Поднимаем точку немного вверх для лучшей видимости на поверхности
                edge_pos.z = edge_pos.z + 1
                
                table.insert(safe_edges, {
                    pos = edge_pos,
                    dir = direction,
                    height = edge_pos.z  -- Добавляем высоту для группировки точек
                })
            end
        end
    end
    
    return safe_edges
end

-- Функция для группировки точек по высоте
local function GroupEdgesByHeight(edges, tolerance)
    local groups = {}
    
    for _, edge in ipairs(edges) do
        -- Ищем группу с подходящей высотой
        local found_group = false
        for group_height, group in pairs(groups) do
            if math.abs(edge.pos.z - group_height) <= tolerance then
                table.insert(group, edge)
                found_group = true
                break
            end
        end
        
        -- Если не нашли подходящую группу, создаем новую
        if not found_group then
            groups[edge.pos.z] = {edge}
        end
    end
    
    return groups
end

-- Функция для создания линий между точками в одной группе
local function CreateLinesForGroup(group)
    local lines = {}
    
    -- Если менее 3 точек, не создаем замкнутую фигуру
    if #group < 3 then return lines end
    
    -- Сортируем точки по часовой стрелке относительно центра группы
    local center = CreateVector(0, 0, 0)
    for _, edge in ipairs(group) do
        center = VectorAdd(center, edge.pos)
    end
    
    center = VectorMultiply(center, 1 / #group)
    
    -- Сортируем точки по углу относительно центра
    table.sort(group, function(a, b)
        local angle_a = math.atan2(a.pos.y - center.y, a.pos.x - center.x)
        local angle_b = math.atan2(b.pos.y - center.y, b.pos.x - center.x)
        return angle_a < angle_b
    end)
    
    -- Создаем линии между соседними точками
    for i = 1, #group do
        local j = i % #group + 1  -- Следующая точка (или первая, если это последняя)
        table.insert(lines, {
            start = group[i].pos,
            finish = group[j].pos
        })
    end
    
    return lines
end

-- Функция для отрисовки точек и линий
local function DrawEdgesAndLines(edges, lines)
    -- Отрисовываем точки
    local r, g, b, a = edge_color:GetValue()
    local size = edge_size:GetValue()
    
    for _, edge in ipairs(edges) do
        local screen_x, screen_y = client.WorldToScreen(ToVector3(edge.pos))
        
        if screen_x and screen_y then
            -- Рисуем основной маркер
            draw.Color(r, g, b, a)
            draw.FilledCircle(screen_x, screen_y, size)
            
            -- Рисуем контур для лучшей видимости
            draw.Color(0, 0, 0, a)
            draw.OutlinedCircle(screen_x, screen_y, size + 1)
        end
    end
    
    -- Отрисовываем линии
    if line_enable:GetValue() then
        local lr, lg, lb, la = line_color:GetValue()
        local thickness = line_thickness:GetValue()
        
        draw.Color(lr, lg, lb, la)
        for _, line in ipairs(lines) do
            local start_x, start_y = client.WorldToScreen(ToVector3(line.start))
            local end_x, end_y = client.WorldToScreen(ToVector3(line.finish))
            
            if start_x and start_y and end_x and end_y then
                draw.Line(start_x, start_y, end_x, end_y)
                
                -- Если толщина больше 1, рисуем дополнительные линии для имитации толщины
                if thickness > 1 then
                    for i = 1, thickness - 1 do
                        local offset = i / 2
                        if i % 2 == 0 then
                            draw.Line(start_x + offset, start_y + offset, end_x + offset, end_y + offset)
                        else
                            draw.Line(start_x - offset, start_y - offset, end_x - offset, end_y - offset)
                        end
                    end
                end
            end
        end
    end
end

-- Системные переменные для предсказания траектории
local trajectory_points = {}
local gravity = 800
local tick_interval = globals.TickInterval()

-- Переменные для отслеживания состояния остановки
local should_stop_movement = false
local best_stop_position = nil
local closest_back_edge = nil

-- Функция для создания BBox на основе точек
local function CreateBBoxFromPoints(points)
    -- Находим минимальные и максимальные координаты
    local min_x, min_y, min_z = math.huge, math.huge, math.huge
    local max_x, max_y, max_z = -math.huge, -math.huge, -math.huge
    
    for _, point in ipairs(points) do
        min_x = math.min(min_x, point.pos.x)
        min_y = math.min(min_y, point.pos.y)
        min_z = math.min(min_z, point.pos.z)
        
        max_x = math.max(max_x, point.pos.x)
        max_y = math.max(max_y, point.pos.y)
        max_z = math.max(max_z, point.pos.z + 50) -- Добавляем высоту для BBox
    end
    
    -- Создаем BBox
    return {
        min = CreateVector(min_x, min_y, min_z),
        max = CreateVector(max_x, max_y, max_z)
    }
end

-- Функция для отрисовки BBox
local function DrawBBox(bbox)
    local r, g, b, a = bbox_color:GetValue()
    draw.Color(r, g, b, a)
    
    -- Получаем экранные координаты для вершин BBox
    local corners = {
        {bbox.min.x, bbox.min.y, bbox.min.z},
        {bbox.max.x, bbox.min.y, bbox.min.z},
        {bbox.min.x, bbox.max.y, bbox.min.z},
        {bbox.max.x, bbox.max.y, bbox.min.z},
        {bbox.min.x, bbox.min.y, bbox.max.z},
        {bbox.max.x, bbox.min.y, bbox.max.z},
        {bbox.min.x, bbox.max.y, bbox.max.z},
        {bbox.max.x, bbox.max.y, bbox.max.z}
    }
    
    local screen_corners = {}
    for i, corner in ipairs(corners) do
        local x, y = client.WorldToScreen(Vector3(corner[1], corner[2], corner[3]))
        if x and y then
            screen_corners[i] = {x = x, y = y}
        else
            screen_corners[i] = nil
        end
    end
    
    -- Рисуем линии между углами BBox
    -- Нижняя грань
    if screen_corners[1] and screen_corners[2] then draw.Line(screen_corners[1].x, screen_corners[1].y, screen_corners[2].x, screen_corners[2].y) end
    if screen_corners[1] and screen_corners[3] then draw.Line(screen_corners[1].x, screen_corners[1].y, screen_corners[3].x, screen_corners[3].y) end
    if screen_corners[3] and screen_corners[4] then draw.Line(screen_corners[3].x, screen_corners[3].y, screen_corners[4].x, screen_corners[4].y) end
    if screen_corners[2] and screen_corners[4] then draw.Line(screen_corners[2].x, screen_corners[2].y, screen_corners[4].x, screen_corners[4].y) end
    
    -- Верхняя грань
    if screen_corners[5] and screen_corners[6] then draw.Line(screen_corners[5].x, screen_corners[5].y, screen_corners[6].x, screen_corners[6].y) end
    if screen_corners[5] and screen_corners[7] then draw.Line(screen_corners[5].x, screen_corners[5].y, screen_corners[7].x, screen_corners[7].y) end
    if screen_corners[7] and screen_corners[8] then draw.Line(screen_corners[7].x, screen_corners[7].y, screen_corners[8].x, screen_corners[8].y) end
    if screen_corners[6] and screen_corners[8] then draw.Line(screen_corners[6].x, screen_corners[6].y, screen_corners[8].x, screen_corners[8].y) end
    
    -- Боковые грани
    if screen_corners[1] and screen_corners[5] then draw.Line(screen_corners[1].x, screen_corners[1].y, screen_corners[5].x, screen_corners[5].y) end
    if screen_corners[2] and screen_corners[6] then draw.Line(screen_corners[2].x, screen_corners[2].y, screen_corners[6].x, screen_corners[6].y) end
    if screen_corners[3] and screen_corners[7] then draw.Line(screen_corners[3].x, screen_corners[3].y, screen_corners[7].x, screen_corners[7].y) end
    if screen_corners[4] and screen_corners[8] then draw.Line(screen_corners[4].x, screen_corners[4].y, screen_corners[8].x, screen_corners[8].y) end
    
    -- Отрисовка задних рёбер с другим цветом для видимости
    local br, bg, bb, ba = back_edges_color:GetValue()
    draw.Color(br, bg, bb, ba)
    
    -- Определяем, какие рёбра являются задними относительно игрока
    local player_pos = GetPlayerPosition()
    if not player_pos then return nil end
    
    local center = CreateVector(
        (bbox.min.x + bbox.max.x) / 2,
        (bbox.min.y + bbox.max.y) / 2,
        (bbox.min.z + bbox.max.z) / 2
    )
    
    local to_player = VectorSubtract(player_pos, center)
    to_player = VectorNormalize(to_player)
    
    -- Проверяем каждое ребро
    local edges = {
        {1, 2}, {1, 3}, {3, 4}, {2, 4},  -- Нижняя грань
        {5, 6}, {5, 7}, {7, 8}, {6, 8},  -- Верхняя грань
        {1, 5}, {2, 6}, {3, 7}, {4, 8}   -- Боковые рёбра
    }
    
    -- Находим самое близкое заднее ребро
    local min_dist = math.huge
    closest_back_edge = nil
    
    for _, edge in ipairs(edges) do
        if screen_corners[edge[1]] and screen_corners[edge[2]] then
            local p1 = CreateVector(corners[edge[1]][1], corners[edge[1]][2], corners[edge[1]][3])
            local p2 = CreateVector(corners[edge[2]][1], corners[edge[2]][2], corners[edge[2]][3])
            
            local edge_center = VectorMultiply(VectorAdd(p1, p2), 0.5)
            local to_edge = VectorSubtract(edge_center, center)
            to_edge = VectorNormalize(to_edge)
            
            -- Если скалярное произведение < 0, то ребро находится сзади относительно игрока
            local dot_product = to_edge.x * to_player.x + to_edge.y * to_player.y + to_edge.z * to_player.z
            
            if dot_product < 0 then
                draw.Line(screen_corners[edge[1]].x, screen_corners[edge[1]].y, 
                          screen_corners[edge[2]].x, screen_corners[edge[2]].y)
                
                -- Проверяем, является ли это ребро ближайшим к игроку
                local dist = VectorDistance(player_pos, edge_center)
                if dist < min_dist then
                    min_dist = dist
                    closest_back_edge = {
                        p1 = p1,
                        p2 = p2
                    }
                end
            end
        end
    end
    
    return closest_back_edge
end

-- Функция для прогнозирования траектории движения игрока
local function PredictTrajectory()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then
        trajectory_points = {}
        return
    end
    
    local pos = GetPlayerPosition()
    if not pos then
        trajectory_points = {}
        return
    end
    
    local velocity = player:GetPropVector("m_vecVelocity")
    local vel = CreateVector(velocity.x, velocity.y, velocity.z)
    
    if VectorLength(vel) < 5 then
        trajectory_points = {}
        return
    end
    
    local num_ticks = prediction_ticks:GetValue()
    local num_substeps = prediction_substeps:GetValue()
    local substep_time = tick_interval / num_substeps
    
    trajectory_points = {pos}
    
    local current_pos = VectorCopy(pos)
    local current_vel = VectorCopy(vel)
    
    for tick = 1, num_ticks do
        for substep = 1, num_substeps do
            -- Применяем гравитацию (только к Z-компоненте)
            current_vel.z = current_vel.z - gravity * substep_time
            
            -- Обновляем позицию
            current_pos = VectorAdd(current_pos, VectorMultiply(current_vel, substep_time))
            
            -- Проверяем столкновение с миром
            local trace_result = TraceCollision(trajectory_points[#trajectory_points], current_pos)
            
            if trace_result.is_hit then
                -- Добавляем точку столкновения
                table.insert(trajectory_points, trace_result.hit_pos)
                -- Прекращаем прогнозирование
                return
            end
        end
        
        -- Добавляем позицию в конце тика
        table.insert(trajectory_points, VectorCopy(current_pos))
    end
end

-- Функция для отрисовки траектории движения
local function DrawTrajectory()
    if #trajectory_points < 2 then return end
    
    local r, g, b, a = trajectory_color:GetValue()
    draw.Color(r, g, b, a)
    
    for i = 1, #trajectory_points - 1 do
        local start_x, start_y = client.WorldToScreen(ToVector3(trajectory_points[i]))
        local end_x, end_y = client.WorldToScreen(ToVector3(trajectory_points[i + 1]))
        
        if start_x and start_y and end_x and end_y then
            draw.Line(start_x, start_y, end_x, end_y)
        end
    end
end

-- Функция для получения ближайшей точки на линии от данной точки
local function ClosestPointOnLine(line_start, line_end, point)
    local line_dir = VectorSubtract(line_end, line_start)
    local line_length = VectorLength(line_dir)
    
    if line_length < 0.001 then
        return VectorCopy(line_start)
    end
    
    local line_dir_norm = VectorNormalize(line_dir)
    local point_to_start = VectorSubtract(point, line_start)
    local dot = point_to_start.x * line_dir_norm.x + point_to_start.y * line_dir_norm.y + point_to_start.z * line_dir_norm.z
    
    dot = Clamp(dot, 0, line_length)
    
    return VectorAdd(line_start, VectorMultiply(line_dir_norm, dot))
end

-- Функция для определения точки остановки
local function DetermineStopPosition()
    if not closest_back_edge then return nil end
    
    local player_pos = GetPlayerPosition()
    if not player_pos then return nil end
    
    -- Находим ближайшую точку на линии от игрока
    local closest_point = ClosestPointOnLine(closest_back_edge.p1, closest_back_edge.p2, player_pos)
    
    -- Определяем направление от точки к игроку
    local to_player = VectorSubtract(player_pos, closest_point)
    local dist = VectorLength(to_player)
    
    -- Если расстояние меньше заданного, возвращаем точку остановки
    local stop_dist = stop_distance:GetValue()
    if dist < stop_dist then
        should_stop_movement = true
        return closest_point
    end
    
    should_stop_movement = false
    return nil
end

-- Функция для отрисовки точки остановки
local function DrawStopPoint(stop_pos)
    if not stop_pos then return end
    
    local r, g, b, a = stop_color:GetValue()
    draw.Color(r, g, b, a)
    
    local screen_x, screen_y = client.WorldToScreen(ToVector3(stop_pos))
    if screen_x and screen_y then
        draw.FilledCircle(screen_x, screen_y, 8)
        draw.Color(0, 0, 0, a)
        draw.OutlinedCircle(screen_x, screen_y, 8)
    end
end

-- Кэширование результатов для улучшения производительности
local cached_edges = {}
local all_lines = {}
local edge_groups = {}
local last_cache_time = 0
local CACHE_DURATION = 0.1 -- 100мс

-- Основной коллбэк для отрисовки
callbacks.Register("Draw", function()
    if not edge_enable:GetValue() then return end
    
    -- Обновляем кэш периодически для экономии ресурсов
    local current_time = globals.RealTime()
    if current_time - last_cache_time > CACHE_DURATION then
        cached_edges = DetectEdges()
        
        -- Группируем точки по высоте
        edge_groups = GroupEdgesByHeight(cached_edges, height_tolerance:GetValue())
        
        -- Создаем линии для каждой группы
        all_lines = {}
        for _, group in pairs(edge_groups) do
            if #group >= 3 and line_enable:GetValue() then -- Минимум 3 точки для создания замкнутой фигуры
                local group_lines = CreateLinesForGroup(group)
                for _, line in ipairs(group_lines) do
                    table.insert(all_lines, line)
                end
            end
        end
        
        last_cache_time = current_time
    end
    
    -- Отрисовываем точки и линии
    DrawEdgesAndLines(cached_edges, all_lines)
    
    -- Если включена визуализация BBox
    if visualize_bbox:GetValue() then
        -- Создаем BBox на основе точек и отрисовываем его
        for _, group in pairs(edge_groups) do
            if #group >= 4 then
                local bbox = CreateBBoxFromPoints(group)
                closest_back_edge = DrawBBox(bbox)
            end
        end
        
        -- Обрабатываем предсказание траектории
        PredictTrajectory()
        DrawTrajectory()
    end
    
    -- Определяем и отрисовываем точку остановки, если включено
    if auto_stop:GetValue() and closest_back_edge then
        best_stop_position = DetermineStopPosition()
        
        if stop_visualization:GetValue() and best_stop_position then
            DrawStopPoint(best_stop_position)
        end
    end
end)

-- Коллбэк для управления движением
callbacks.Register("CreateMove", function(cmd)
    if auto_stop:GetValue() and should_stop_movement and best_stop_position then
        -- Останавливаем движение игрока
        cmd.forwardmove = 0
        cmd.sidemove = 0
    end
end)

