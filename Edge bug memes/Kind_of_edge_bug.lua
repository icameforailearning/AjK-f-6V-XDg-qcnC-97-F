-- Объединенный скрипт для установки точек, отображения bbox и остановки движения
-- на задних ребрах bbox при приближении к линии

-- Создаем основные элементы интерфейса
local ref = gui.Reference("MISC", "da")
local main_group = gui.Groupbox(ref, "Система позиционирования на краю с BBox", 16, 16, 296, 296)

-- Настройки для точек
local point_enable = gui.Checkbox(main_group, "point_placer_enable", "Включить установку точек", true)
local point_key = gui.Keybox(main_group, "point_placer_key", "Клавиша для установки точки", 0)
local point_color = gui.ColorPicker(point_enable, "point_color", "Цвет точки", 255, 0, 0, 255)
local point_size = gui.Slider(main_group, "point_size", "Размер точки", 4, 1, 15)
local line_thickness = gui.Slider(main_group, "point_line_thickness", "Толщина линии", 2, 1, 5)

-- Добавляем настройку цвета для самой удаленной нижней грани
local farthest_bottom_edge_color = gui.ColorPicker(main_group, "farthest_bottom_edge_color", 
    "Цвет самой удаленной нижней грани", 255, 165, 0, 255)



-- Настройки для траектории и BBox
local visualize_bbox = gui.Checkbox(main_group, "eb_visual", "Активировать визуализацию BBox", true)
local trajectory_color = gui.ColorPicker(visualize_bbox, "eb_trajectory_color", "Цвет траектории", 0, 255, 0, 255)
local bbox_color = gui.ColorPicker(main_group, "bbox_color", "Цвет BBox", 0, 0, 255, 150)
local back_edges_color = gui.ColorPicker(main_group, "back_edges_color", "Цвет задних рёбер", 255, 0, 0, 255)
local prediction_distance = gui.Slider(main_group, "eb_pred_dist", "Дальность прогноза", 15, 1, 64, 1)

-- Настройки для остановки движения
local auto_stop = gui.Checkbox(main_group, "auto_stop", "Автостоп у линии", true)
local stop_distance = gui.Slider(main_group, "stop_distance", "Погрешность остановки (единиц)", 5, 1, 20, 1)
local stop_visualization = gui.Checkbox(main_group, "stop_visual", "Визуализация точки остановки", true)
local stop_color = gui.ColorPicker(stop_visualization, "stop_color", "Цвет индикатора остановки", 255, 255, 0, 255)

-- Массив для хранения точек (максимум 2)
local points = {}

-- Системные переменные для предсказания траектории
local trajectory_points = {}
local gravity = 800
local tick_interval = globals.TickInterval()

-- Переменная для отслеживания состояния остановки
local should_stop_movement = false
local best_stop_position = nil
local closest_back_edge = nil

-- Переменные для обработки нажатий клавиш
local key_pressed = false

-- Вспомогательные функции для работы с векторами
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

-- Замена для normalized
local function VectorNormalize(v)
    local length = VectorLength(v)
    if length > 0 then
        return CreateVector(v.x / length, v.y / length, v.z / length)
    end
    return CreateVector(0, 0, 0)
end

-- Замена для clamp
local function Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

-- Замена для clone
local function VectorCopy(v)
    return CreateVector(v.x, v.y, v.z)
end

-- Функции для конвертации между нашими векторами и Vector3
local function ToVector3(v)
    return Vector3(v.x, v.y, v.z)
end

local function FromVector3(v)
    return CreateVector(v.x, v.y, v.z)
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

-- Функция трассировки для поиска точки на поверхности
local function TraceGround(start_pos, max_distance)
    max_distance = max_distance or 150
    
    local down_end = CreateVector(start_pos.x, start_pos.y, start_pos.z - max_distance)
    
    -- Используем Vector3 для функций игрового движка
    local trace_start = ToVector3(start_pos)
    local trace_end = ToVector3(down_end)
    
    -- Используем MASK_PLAYERSOLID (0x201B) для определения коллизий игрока
    local result = engine.TraceLine(trace_start, trace_end, 0x201B)
    
    -- Обработка результата трассировки
    local fraction = 1.0
    if type(result) == "userdata" then
        pcall(function() fraction = result.fraction end)
    elseif type(result) == "number" then
        fraction = result
    end
    
    -- Вычисляем точку столкновения
    local hit_pos = CreateVector(
        start_pos.x + (down_end.x - start_pos.x) * fraction,
        start_pos.y + (down_end.y - start_pos.y) * fraction,
        start_pos.z + (down_end.z - start_pos.z) * fraction
    )
    
    return {
        fraction = fraction,
        hit_pos = hit_pos,
        is_hit = fraction < 0.99
    }
end

-- Функция для добавления новой точки
local function AddPoint()
    local player_pos = GetPlayerPosition()
    if not player_pos then return end
    
    -- Находим точку на земле под игроком
    local trace_result = TraceGround(player_pos)
    if not trace_result.is_hit then return end
    
    -- Поднимаем точку немного вверх для лучшей видимости
    local point_pos = trace_result.hit_pos
    point_pos.z = point_pos.z + 1
    
    -- Добавляем точку (максимум 2)
    if #points >= 2 then
        table.remove(points, 1) -- Удаляем первую точку если уже есть 2
    end
    
    table.insert(points, point_pos)
end

-- Функция для вычисления расстояния от точки до линии
local function DistancePointToLine(point, line_start, line_end)
    local line_vec = VectorSubtract(line_end, line_start)
    local point_vec = VectorSubtract(point, line_start)
    
    local line_length = VectorLength(line_vec)
    if line_length < 0.0001 then
        return VectorDistance(point, line_start)
    end
    
    -- Нормализуем вектор линии
    local line_norm = VectorNormalize(line_vec)
    
    -- Проекция точки на линию
    local dot_product = point_vec.x * line_norm.x + point_vec.y * line_norm.y + point_vec.z * line_norm.z
    
    -- Проекция может быть за пределами отрезка, ограничиваем её
    local t = Clamp(dot_product, 0, line_length)
    
    -- Находим ближайшую точку на линии
    local closest_point = VectorAdd(
        line_start,
        VectorMultiply(line_norm, t)
    )
    
    -- Возвращаем расстояние от точки до ближайшей точки на линии
    return VectorDistance(point, closest_point)
end

-- Функция получения bbox игрока
local function GetBBoxCorners(origin, player)
    if not player then player = entities.GetLocalPlayer() end
    if not player then return {} end
    
    local mins, maxs = player:GetMins(), player:GetMaxs()
    
    return {
        CreateVector(origin.x + mins.x, origin.y + mins.y, origin.z + mins.z), -- 1: левый-задний-нижний
        CreateVector(origin.x + maxs.x, origin.y + mins.y, origin.z + mins.z), -- 2: правый-задний-нижний
        CreateVector(origin.x + maxs.x, origin.y + maxs.y, origin.z + mins.z), -- 3: правый-передний-нижний
        CreateVector(origin.x + mins.x, origin.y + maxs.y, origin.z + mins.z), -- 4: левый-передний-нижний
        CreateVector(origin.x + mins.x, origin.y + mins.y, origin.z + maxs.z), -- 5: левый-задний-верхний
        CreateVector(origin.x + maxs.x, origin.y + mins.y, origin.z + maxs.z), -- 6: правый-задний-верхний
        CreateVector(origin.x + maxs.x, origin.y + maxs.y, origin.z + maxs.z), -- 7: правый-передний-верхний
        CreateVector(origin.x + mins.x, origin.y + maxs.y, origin.z + maxs.z)  -- 8: левый-передний-верхний
    }
end




-- ИСПРАВЛЕННАЯ функция для определения задних рёбер BBox относительно движения
local function GetBackEdges(bbox_corners, movement_dir)
    -- Собираем только нижние рёбра BBox (плоскость Z-)
    local lower_edges = {
        {bbox_corners[1], bbox_corners[2]}, -- Заднее нижнее ребро (Y-)
        {bbox_corners[2], bbox_corners[3]}, -- Правое нижнее ребро (X+)
        {bbox_corners[3], bbox_corners[4]}, -- Переднее нижнее ребро (Y+)
        {bbox_corners[4], bbox_corners[1]}  -- Левое нижнее ребро (X-)
    }

    -- Если установлены 2 точки линии
    if #points >= 2 then
        local line_start = points[1]
        local line_end = points[2]
        local line_vector = VectorNormalize(VectorSubtract(line_end, line_start))

        -- Анализ рёбер нижней плоскости
        local candidate_edges = {}
        
        for _, edge in ipairs(lower_edges) do
            local edge_vector = VectorNormalize(VectorSubtract(edge[2], edge[1]))
            local dot_product = math.abs(edge_vector.x * line_vector.x + edge_vector.y * line_vector.y)
            
            local edge_center = VectorMultiply(VectorAdd(edge[1], edge[2]), 0.5)
            local distance = DistancePointToLine(edge_center, line_start, line_end)
            
            table.insert(candidate_edges, {
                edge = edge,
                parallel_score = dot_product,
                distance = distance
            })
        end

        -- Фильтрация и выбор оптимального ребра
        if #candidate_edges > 0 then
            table.sort(candidate_edges, function(a, b)
                if math.abs(a.parallel_score - b.parallel_score) > 0.1 then
                    return a.parallel_score > b.parallel_score  -- Сначала по параллельности
                else
                    return a.distance > b.distance  -- Затем по расстоянию
                end
            end)
            return {candidate_edges[1].edge}
        end
    end

    -- Резервный алгоритм выбора по направлению движения
    local back_edges = {}
    local movement_angle = math.atan2(movement_dir.y, movement_dir.x)
    
    for _, edge in ipairs(lower_edges) do
        local edge_vector = VectorNormalize(VectorSubtract(edge[2], edge[1]))
        local edge_angle = math.atan2(edge_vector.y, edge_vector.x)
        local angle_diff = math.abs(math.atan2(
            math.sin(movement_angle - edge_angle), 
            math.cos(movement_angle - edge_angle)
        ))
        
        -- Выбираем перпендикулярные движению рёбра (допуск ±45 градусов)
        if angle_diff > math.rad(45) and angle_diff < math.rad(135) then
            table.insert(back_edges, edge)
        end
    end

    return back_edges
end
-- Функция для трассировки отдельного луча
local function TraceRay(start_pos, end_pos)
    -- Используем Vector3 для функций игрового движка
    local trace_start = ToVector3(start_pos)
    local trace_end = ToVector3(end_pos)
    
    local trace = engine.TraceLine(trace_start, trace_end, 0x1)
    
    return {
        fraction = trace.fraction,
        endpos = FromVector3(trace.endpos),
        hit = trace.fraction < 1.0
    }
end

-- Собственная функция для трассировки bbox (вместо tracehull)
local function TraceBox(start_origin, end_origin, player)
    local corners = GetBBoxCorners(start_origin, player)
    
    local min_fraction = 1.0
    local hit_pos = VectorCopy(end_origin)
    local hit = false
    
    for i = 1, #corners do
        local start_pos = corners[i]
        
        -- Вычисляем вектор смещения для этого угла
        local offset = VectorSubtract(start_pos, start_origin)
        
        -- Вычисляем соответствующий конечный угол
        local end_pos = VectorAdd(end_origin, offset)
        
        local trace = TraceRay(start_pos, end_pos)
        
        if trace.fraction < min_fraction then
            min_fraction = trace.fraction
            
            -- Интерполируем позицию столкновения для центра bbox
            hit_pos = VectorAdd(
                start_origin,
                VectorMultiply(
                    VectorSubtract(end_origin, start_origin),
                    trace.fraction
                )
            )
            hit = true
        end
    end
    
    return {
        fraction = min_fraction,
        endpos = hit_pos,
        hit = hit
    }
end

-- Функция для предсказания траектории игрока
local function PredictTrajectory()
    trajectory_points = {}
    
    local player = entities.GetLocalPlayer()
    if not visualize_bbox:GetValue() or
       not player or
       not player:IsAlive() or
       bit.band(player:GetPropInt("m_fFlags"), 1) ~= 0 then -- Проверка на землю
        return
    end
    
    local velocity = player:GetPropVector("m_vecVelocity")
    local current_pos = FromVector3(player:GetAbsOrigin())
    local current_vel = CreateVector(velocity.x, velocity.y, velocity.z)
    local movement_dir = VectorNormalize(CreateVector(velocity.x, velocity.y, 0))
    
    for i = 1, prediction_distance:GetValue() do
        -- Применяем гравитацию
        current_vel.z = current_vel.z - (gravity * tick_interval)
        
        -- Вычисляем следующую позицию
        local next_pos = VectorAdd(
            current_pos,
            CreateVector(
                current_vel.x * tick_interval,
                current_vel.y * tick_interval,
                current_vel.z * tick_interval
            )
        )
        
        -- Проверяем коллизии
        local trace_result = TraceBox(current_pos, next_pos, player)
        
        -- Получаем BBox для текущей позиции
        local bbox = GetBBoxCorners(current_pos, player)
        
        -- Определяем задние рёбра
        local back_edges = GetBackEdges(bbox, movement_dir)
        
        -- Сохраняем текущую позицию
        table.insert(trajectory_points, {
            pos = VectorCopy(current_pos),
            hit = trace_result.hit,
            bbox = bbox,
            back_edges = back_edges
        })
        
        -- Обновляем текущую позицию
        current_pos = trace_result.hit and trace_result.endpos or next_pos
        
        -- Если столкнулись, прекращаем симуляцию
        if trace_result.hit then break end
    end
    
    return trajectory_points
end


-- Функция для проверки расстояния от задних рёбер bbox до линии
local function CheckBackEdgesDistance(back_edges, line_start, line_end)
    if #back_edges == 0 then return 999999 end
    
    local min_distance = 999999
    local closest_edge = nil
    
    for _, edge in ipairs(back_edges) do
        local corner1 = edge[1]
        local corner2 = edge[2]
        
        -- Проверяем расстояние от обоих концов ребра до линии
        local dist1 = DistancePointToLine(corner1, line_start, line_end)
        local dist2 = DistancePointToLine(corner2, line_start, line_end)
        
        -- Также проверяем несколько точек вдоль ребра для более точного результата
        local edge_points = 5
        for j = 1, edge_points do
            local t = j / (edge_points + 1)
            local point = VectorAdd(
                VectorMultiply(corner1, 1 - t),
                VectorMultiply(corner2, t)
            )
            local dist = DistancePointToLine(point, line_start, line_end)
            
            if dist < min_distance then
                min_distance = dist
                closest_edge = {corner1, corner2}
            end
        end
    end
    
    return min_distance, closest_edge
end

-- Функция для остановки движения игрока через client.Command
local function StopMovement()
    if not should_stop_movement then return end
    
    -- Останавливаем движение путем отмены всех клавиш движения
    client.Command("-back")
    client.Command("-forward")
    client.Command("-right")
    client.Command("-left")
end

-- Функция для проверки необходимости остановки
local function CheckShouldStop()
    should_stop_movement = false
    best_stop_position = nil
    closest_back_edge = nil
    
    -- Проверяем, есть ли две точки и предсказанная траектория
    if #points < 2 or #trajectory_points == 0 then return end
    
    local line_start = points[1]
    local line_end = points[2]
    
    -- Порог расстояния для остановки
    local threshold = stop_distance:GetValue()
    
    -- Перебираем все точки траектории
    for i, traj_point in ipairs(trajectory_points) do
        -- Проверяем расстояние от задних рёбер до линии
        local distance, edge = CheckBackEdgesDistance(traj_point.back_edges, line_start, line_end)
        
        -- Если расстояние меньше порога, устанавливаем флаг остановки
        if distance <= threshold then
            should_stop_movement = true
            best_stop_position = VectorCopy(traj_point.pos)
            closest_back_edge = edge
            break
        end
    end
end

-- Функция отрисовки точек и линии
local function DrawPoints()
    if #points == 0 or not point_enable:GetValue() then return end
    
    local r, g, b, a = point_color:GetValue()
    local size = point_size:GetValue()
    
    for i, point in ipairs(points) do
        local screen_x, screen_y = client.WorldToScreen(ToVector3(point))
        
        if screen_x and screen_y then
            -- Рисуем основную точку
            draw.Color(r, g, b, a)
            draw.FilledCircle(screen_x, screen_y, size)
            
            -- Рисуем контур для лучшей видимости
            draw.Color(0, 0, 0, a)
            draw.OutlinedCircle(screen_x, screen_y, size + 1)
            
            -- Рисуем номер точки
            draw.Color(255, 255, 255, 255)
            draw.Text(screen_x + size + 2, screen_y - 5, tostring(i))
        end
    end
    
    -- Рисуем линию между точками, если их две
    if #points == 2 then
        local x1, y1 = client.WorldToScreen(ToVector3(points[1]))
        local x2, y2 = client.WorldToScreen(ToVector3(points[2]))
        
        if x1 and y1 and x2 and y2 then
            local thickness = line_thickness:GetValue()
            draw.Color(r, g, b, a)
            for i = 0, thickness - 1 do
                draw.Line(x1, y1 + i, x2, y2 + i)
            end
        end
    end
end

-- Функция рисования линии между двумя точками в 3D мире
local function DrawLine3D(point1, point2, r, g, b, a)
    local x1, y1 = client.WorldToScreen(ToVector3(point1))
    local x2, y2 = client.WorldToScreen(ToVector3(point2))
    
    if x1 and y1 and x2 and y2 then
        draw.Color(r, g, b, a)
        draw.Line(x1, y1, x2, y2)
    end
end

-- Функция отрисовки BBox
local function DrawBBox(corners, r, g, b, a, back_edges)
    -- Рисуем нижний прямоугольник
    DrawLine3D(corners[1], corners[2], r, g, b, a)
    DrawLine3D(corners[2], corners[3], r, g, b, a)
    DrawLine3D(corners[3], corners[4], r, g, b, a)
    DrawLine3D(corners[4], corners[1], r, g, b, a)
    
    -- Рисуем верхний прямоугольник
    DrawLine3D(corners[5], corners[6], r, g, b, a)
    DrawLine3D(corners[6], corners[7], r, g, b, a)
    DrawLine3D(corners[7], corners[8], r, g, b, a)
    DrawLine3D(corners[8], corners[5], r, g, b, a)
    
    -- Рисуем вертикальные ребра
    DrawLine3D(corners[1], corners[5], r, g, b, a)
    DrawLine3D(corners[2], corners[6], r, g, b, a)
    DrawLine3D(corners[3], corners[7], r, g, b, a)
    DrawLine3D(corners[4], corners[8], r, g, b, a)
    
    -- Если переданы задние рёбра, рисуем их выделенным цветом
    if back_edges then
        local br, bg, bb, ba = back_edges_color:GetValue()
        
        for _, edge in ipairs(back_edges) do
            DrawLine3D(edge[1], edge[2], br, bg, bb, ba)
            
            -- Рисуем маленькие кружки на концах рёбер для лучшей видимости
            local x1, y1 = client.WorldToScreen(ToVector3(edge[1]))
            local x2, y2 = client.WorldToScreen(ToVector3(edge[2]))
            
            if x1 and y1 then
                draw.Color(br, bg, bb, ba)
                draw.FilledCircle(x1, y1, 3)
            end
            
            if x2 and y2 then
                draw.Color(br, bg, bb, ba)
                draw.FilledCircle(x2, y2, 3)
            end
        end
    end
end

-- Функция отрисовки траектории
local function DrawTrajectory()
    if not visualize_bbox:GetValue() or #trajectory_points == 0 then return end
    
    local r, g, b, a = trajectory_color:GetValue()
    local br, bg, bb, ba = bbox_color:GetValue()
    
    -- Рисуем траекторию
    for i = 1, #trajectory_points - 1 do
        local p1 = trajectory_points[i].pos
        local p2 = trajectory_points[i + 1].pos
        
        local x1, y1 = client.WorldToScreen(ToVector3(p1))
        local x2, y2 = client.WorldToScreen(ToVector3(p2))
        
        if x1 and y1 and x2 and y2 then
            draw.Color(r, g, b, a)
            draw.Line(x1, y1, x2, y2)
            
            if trajectory_points[i + 1].hit then
                draw.FilledRect(x2 - 3, y2 - 3, x2 + 3, y2 + 3)
            end
        end
        
        -- Рисуем BBox для каждой точки траектории
        if i % 3 == 0 or i == #trajectory_points then  -- Рисуем BBox через каждые три точки для оптимизации
            DrawBBox(trajectory_points[i].bbox, br, bg, bb, ba, trajectory_points[i].back_edges)
        end
    end
    
    -- Отображаем индикаторы точки остановки
    if should_stop_movement and stop_visualization:GetValue() and closest_back_edge then
        local sr, sg, sb, sa = stop_color:GetValue()
        draw.Color(sr, sg, sb, sa)
        
        -- Подсвечиваем ближайшее к линии ребро
        for i = 1, 2 do
            local corner = closest_back_edge[i]
            local x, y = client.WorldToScreen(ToVector3(corner))
            if x and y then
                draw.FilledCircle(x, y, 4)
            end
        end
        
        -- Рисуем линию между углами ребра
        local x1, y1 = client.WorldToScreen(ToVector3(closest_back_edge[1]))
        local x2, y2 = client.WorldToScreen(ToVector3(closest_back_edge[2]))
        
        if x1 and y1 and x2 and y2 then
            draw.Color(sr, sg, sb, sa)
            draw.Line(x1, y1, x2, y2)
        end
    end
    
    -- Рисуем BBox в последней точке прогноза (более ярко)
    if #trajectory_points > 0 then
        local last_point = trajectory_points[#trajectory_points]
        DrawBBox(last_point.bbox, br, bg, bb, ba * 1.5, last_point.back_edges)
    end
end

-- Основные коллбэки
callbacks.Register("Draw", function()
    -- Обработка нажатия клавиши для добавления точек
    if point_enable:GetValue() then
        local key = point_key:GetValue()
        if key ~= 0 then
            local key_state = input.IsButtonDown(key)
            
            -- Добавляем точку при нажатии (но не при удержании)
            if key_state and not key_pressed then
                AddPoint()
                key_pressed = true
            elseif not key_state then
                key_pressed = false
            end
        end
        
        -- Отрисовка точек
        DrawPoints()
    end
    
    -- Отрисовка траектории и BBox
    DrawTrajectory()
end)

-- Коллбэк для предсказания траектории и проверки остановки
callbacks.Register("CreateMove", function()
    -- Предсказываем траекторию
    PredictTrajectory()
    
    -- Проверяем необходимость остановки
    if auto_stop:GetValue() then
        CheckShouldStop()
    else
        should_stop_movement = false
    end
end)

-- Коллбэк для остановки движения
callbacks.Register("CreateMove", function()
    -- Если нужно остановить движение, делаем это
    if auto_stop:GetValue() and should_stop_movement then
        StopMovement()
    end
end)
