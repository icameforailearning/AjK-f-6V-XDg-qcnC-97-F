-- Улучшенный скрипт определения краёв с точной остановкой bbox на краю

-- Создаем интерфейс
local ref = gui.Reference("MISC", "da")
local main_group = gui.Groupbox(ref, "Система определения краёв с BBox", 16, 16, 296, 296)

-- Настройки визуализации
local visualize_toggle = gui.Checkbox(main_group, "edge_visual", "Активировать визуализацию", true)
local edge_color = gui.ColorPicker(visualize_toggle, "edge_color", "Цвет края", 255, 0, 0, 255)
local trajectory_color = gui.ColorPicker(main_group, "trajectory_color", "Цвет траектории", 0, 255, 0, 255)
local prediction_distance = gui.Slider(main_group, "pred_dist", "Дальность прогноза", 15, 1, 64, 1)

-- Настройки для обнаружения краёв
local edge_distance = gui.Slider(main_group, "edge_distance", "Дистанция обнаружения краёв", 150, 50, 500)
local edge_precision = gui.Slider(main_group, "edge_precision", "Точность обнаружения", 8, 2, 16)
local edge_size = gui.Slider(main_group, "edge_marker_size", "Размер маркера края", 4, 1, 15)

-- Настройки для блокировки движения
local auto_edge_stop = gui.Checkbox(main_group, "auto_edge_stop", "Автостоп на краю BBox", true)
local stop_distance_threshold = gui.Slider(main_group, "stop_threshold", "Порог активации стопа", 25, 5, 50)
local bbox_margin = gui.Slider(main_group, "bbox_margin", "Запас от края (юниты)", 0, 0, 10)

-- Системные переменные
local trajectory_points = {}
local detected_edges = {}
local should_stop_movement = false
local movement_block_direction = nil
local landing_surface = nil
local gravity = 800
local tick_interval = globals.TickInterval()

-- Функция получения bbox игрока
local function get_bbox_corners(origin)
    local player = entities.GetLocalPlayer()
    if not player then return {} end
    
    local mins, maxs = player:GetMins(), player:GetMaxs()
    
    return {
        Vector3(origin.x + mins.x, origin.y + mins.y, origin.z + mins.z),
        Vector3(origin.x + maxs.x, origin.y + mins.y, origin.z + mins.z),
        Vector3(origin.x + maxs.x, origin.y + maxs.y, origin.z + mins.z),
        Vector3(origin.x + mins.x, origin.y + maxs.y, origin.z + mins.z),
        Vector3(origin.x + mins.x, origin.y + mins.y, origin.z + maxs.z),
        Vector3(origin.x + maxs.x, origin.y + mins.y, origin.z + maxs.z),
        Vector3(origin.x + maxs.x, origin.y + maxs.y, origin.z + maxs.z),
        Vector3(origin.x + mins.x, origin.y + maxs.y, origin.z + maxs.z)
    }
end

-- Улучшенная функция трассировки для bbox
local function trace_hull(start_origin, end_origin)
    local min_fraction = 1.0
    local hit_pos = end_origin
    local hit_normal = Vector3(0, 0, 0)
    local hit = false
    
    for _, start_pos in ipairs(get_bbox_corners(start_origin)) do
        local end_pos = Vector3(
            end_origin.x + (start_pos.x - start_origin.x),
            end_origin.y + (start_pos.y - start_origin.y),
            end_origin.z + (start_pos.z - start_origin.z)
        )
        
        local trace = engine.TraceLine(start_pos, end_pos, 0x1)
        
        if trace.fraction < min_fraction then
            min_fraction = trace.fraction
            hit_pos = Vector3(
                start_pos.x + (end_pos.x - start_pos.x) * trace.fraction,
                start_pos.y + (end_pos.y - start_pos.y) * trace.fraction,
                start_pos.z + (end_pos.z - start_pos.z) * trace.fraction
            )
            hit = true
            
            -- Вычисляем нормаль поверхности
            if trace.fraction < 1.0 then
                local hit_center = Vector3(hit_pos.x, hit_pos.y, hit_pos.z)
                
                -- Трассировка по трем направлениям для определения нормали
                local trace_up = engine.TraceLine(hit_center, Vector3(hit_center.x, hit_center.y, hit_center.z + 5), 0x1)
                local trace_right = engine.TraceLine(hit_center, Vector3(hit_center.x + 5, hit_center.y, hit_center.z), 0x1)
                local trace_forward = engine.TraceLine(hit_center, Vector3(hit_center.x, hit_center.y + 5, hit_center.z), 0x1)
                
                hit_normal = Vector3(0, 0, 0)
                if trace_up.fraction < 1.0 then hit_normal.z = hit_normal.z + 1 end
                if trace_right.fraction < 1.0 then hit_normal.x = hit_normal.x + 1 end
                if trace_forward.fraction < 1.0 then hit_normal.y = hit_normal.y + 1 end
                
                -- Нормализуем вектор
                local norm_length = math.sqrt(hit_normal.x^2 + hit_normal.y^2 + hit_normal.z^2)
                if norm_length > 0 then
                    hit_normal.x = hit_normal.x / norm_length
                    hit_normal.y = hit_normal.y / norm_length
                    hit_normal.z = hit_normal.z / norm_length
                end
            end
        end
    end
    
    return {
        fraction = min_fraction,
        endpos = hit_pos,
        hit = hit,
        normal = hit_normal
    }
end

-- Функция для предсказания траектории с учетом bbox
local function predict_trajectory()
    trajectory_points = {}
    landing_surface = nil
    
    local player = entities.GetLocalPlayer()
    if not visualize_toggle:GetValue()
        or not player
        or not player:IsAlive()
        or bit.band(player:GetPropInt("m_fFlags"), 1) ~= 0 then
        return
    end
    
    local velocity = player:GetPropVector("m_vecVelocity")
    local current_pos = player:GetAbsOrigin()
    local current_vel = Vector3(velocity.x, velocity.y, velocity.z)
    
    for i = 1, prediction_distance:GetValue() do
        current_vel.z = current_vel.z - (gravity * tick_interval)
        local next_pos = Vector3(
            current_pos.x + (current_vel.x * tick_interval),
            current_pos.y + (current_vel.y * tick_interval),
            current_pos.z + (current_vel.z * tick_interval)
        )
        
        local trace_result = trace_hull(current_pos, next_pos)
        
        table.insert(trajectory_points, {
            pos = Vector3(current_pos.x, current_pos.y, current_pos.z),
            hit = trace_result.hit,
            normal = trace_result.normal
        })
        
        current_pos = trace_result.hit and trace_result.endpos or next_pos
        
        if trace_result.hit then
            landing_surface = {
                pos = trace_result.endpos,
                normal = trace_result.normal
            }
            break
        end
    end
    
    return landing_surface
end

-- Функция поиска земли под точкой
local function FindGround(pos, max_distance)
    max_distance = max_distance or 150
    local down_end = Vector3(pos.x, pos.y, pos.z - max_distance)
    local trace_result = engine.TraceLine(pos, down_end, 0x1)
    
    if trace_result.fraction < 1.0 then
        local hit_pos = Vector3(
            pos.x,
            pos.y,
            pos.z - (trace_result.fraction * max_distance)
        )
        return {
            pos = hit_pos,
            fraction = trace_result.fraction,
            normal = trace_result.normal
        }
    end
    
    return nil
end

-- Улучшенная функция определения краёв на поверхности
local function DetectEdges(surface_pos, surface_normal)
    if not surface_pos then return {} end
    
    local detected_edges = {}
    local num_rays = 24 -- Количество лучей для точного определения
    local angle_step = 360 / num_rays
    local max_dist = edge_distance:GetValue()
    local precision = edge_precision:GetValue()
    
    -- Определяем плоскость поверхности
    local surface_up = Vector3(0, 0, 1)
    if math.sqrt(surface_normal.x^2 + surface_normal.y^2 + surface_normal.z^2) < 0.1 then
        surface_normal = surface_up -- По умолчанию горизонтальная поверхность
    end
    
    -- Для каждого направления ищем край поверхности
    for i = 1, num_rays do
        local current_angle = i * angle_step
        local rad = math.rad(current_angle)
        local ray_dir = Vector3(math.cos(rad), math.sin(rad), 0)
        
        -- Пошаговый поиск края
        local edge_found = false
        local edge_pos = nil
        
        for step = 1, precision do
            local check_dist = (step / precision) * max_dist
            local check_pos = Vector3(
                surface_pos.x + (ray_dir.x * check_dist),
                surface_pos.y + (ray_dir.y * check_dist),
                surface_pos.z + (ray_dir.z * check_dist)
            )
            
            -- Проверяем, есть ли под точкой земля
            local ground_result = FindGround(check_pos, 20)
            
            if not ground_result then
                -- Если земли нет - нашли край
                if step > 1 then
                    -- Вычисляем предыдущую позицию
                    local prev_dist = ((step - 1) / precision) * max_dist
                    local prev_pos = Vector3(
                        surface_pos.x + (ray_dir.x * prev_dist),
                        surface_pos.y + (ray_dir.y * prev_dist),
                        surface_pos.z + (ray_dir.z * prev_dist)
                    )
                    
                    -- Уточняем положение края бинарным поиском
                    local min_dist = prev_dist
                    local max_dist_binary = check_dist
                    
                    for refinement = 1, 5 do -- 5 итераций уточнения
                        local mid_dist = (min_dist + max_dist_binary) / 2
                        local mid_pos = Vector3(
                            surface_pos.x + (ray_dir.x * mid_dist),
                            surface_pos.y + (ray_dir.y * mid_dist),
                            surface_pos.z + (ray_dir.z * mid_dist)
                        )
                        
                        local mid_ground = FindGround(mid_pos, 20)
                        
                        if mid_ground then
                            min_dist = mid_dist
                        else
                            max_dist_binary = mid_dist
                        end
                    end
                    
                    -- Используем min_dist как наиболее точную оценку края
                    edge_pos = Vector3(
                        surface_pos.x + (ray_dir.x * min_dist),
                        surface_pos.y + (ray_dir.y * min_dist),
                        surface_pos.z + (ray_dir.z * min_dist)
                    )
                    edge_found = true
                    break
                end
            end
        end
        
        if edge_found and edge_pos then
            table.insert(detected_edges, {
                pos = edge_pos,
                dir = ray_dir,
                angle = current_angle
            })
        end
    end
    
    return detected_edges
end

-- Функция для расчета расстояния между точкой и краем
local function DistanceToEdge(player_pos, edge_pos, edge_dir)
    -- Вектор от края к игроку
    local to_player = Vector3(
        player_pos.x - edge_pos.x,
        player_pos.y - edge_pos.y,
        player_pos.z - edge_pos.z
    )
    
    -- Проекция вектора на направление края (перпендикулярное к вектору к краю)
    local edge_perp = Vector3(-edge_dir.y, edge_dir.x, 0)
    local projected = to_player.x * edge_perp.x + to_player.y * edge_perp.y
    
    -- Вычисляем перпендикулярную составляющую (расстояние до края)
    return math.abs(projected)
end

-- Функция расчета оптимального положения bbox относительно края
local function CalculateOptimalBBoxPosition(player_pos, player_vel, edge_pos, edge_dir)
    local player = entities.GetLocalPlayer()
    if not player then return nil end
    
    -- Получаем размеры BBox
    local mins, maxs = player:GetMins(), player:GetMaxs()
    local bbox_width = maxs.x - mins.x
    local bbox_length = maxs.y - mins.y
    
    -- Определяем направление движения в плоскости
    local vel_xy = Vector3(player_vel.x, player_vel.y, 0)
    local vel_length = math.sqrt(vel_xy.x^2 + vel_xy.y^2)
    
    -- Если скорость слишком низкая, не можем определить направление
    if vel_length < 5 then return nil end
    
    -- Нормализуем вектор скорости
    local vel_dir = Vector3(vel_xy.x / vel_length, vel_xy.y / vel_length, 0)
    
    -- Определяем, какой стороной BBox должен быть на краю
    -- Вычисляем проекции на оси X и Y
    local projection_x = math.abs(vel_dir.x)
    local projection_y = math.abs(vel_dir.y)
    
    -- Определяем смещение в зависимости от направления движения
    local offset
    if projection_x > projection_y then
        -- Движение преимущественно по оси X
        offset = vel_dir.x > 0 and maxs.x or mins.x
    else
        -- Движение преимущественно по оси Y
        offset = vel_dir.y > 0 and maxs.y or mins.y
    end
    
    -- Вычисляем направление от края к центру поверхности (против вектора dir)
    local to_center = Vector3(-edge_dir.x, -edge_dir.y, 0)
    
    -- Если движемся к краю, используем противоположное смещение
    local dot_product = vel_dir.x * to_center.x + vel_dir.y * to_center.y
    if dot_product < 0 then
        offset = -offset
    end
    
    -- Добавляем запас от края
    local margin = bbox_margin:GetValue()
    offset = offset + (margin * math.sign(offset))
    
    return offset
end

-- Определение необходимости блокировки движения
local function ShouldStopMovement()
    if not auto_edge_stop:GetValue() or #detected_edges == 0 then
        should_stop_movement = false
        movement_block_direction = nil
        return
    end
    
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then
        should_stop_movement = false
        movement_block_direction = nil
        return
    end
    
    -- Получаем текущую позицию и скорость игрока
    local player_pos = player:GetAbsOrigin()
    local velocity = player:GetPropVector("m_vecVelocity")
    local vel_length_2d = math.sqrt(velocity.x^2 + velocity.y^2)
    
    -- Если скорость слишком низкая, не блокируем движение
    if vel_length_2d < 5 then
        should_stop_movement = false
        movement_block_direction = nil
        return
    end
    
    -- Нормализуем вектор скорости
    local vel_dir = Vector3(velocity.x / vel_length_2d, velocity.y / vel_length_2d, 0)
    
    -- Находим ближайший край в направлении движения
    local closest_edge = nil
    local min_distance = 9999
    
    for _, edge in ipairs(detected_edges) do
        -- Вектор от игрока к краю
        local to_edge = Vector3(
            edge.pos.x - player_pos.x,
            edge.pos.y - player_pos.y,
            0
        )
        
        -- Нормализуем вектор
        local to_edge_length = math.sqrt(to_edge.x^2 + to_edge.y^2)
        if to_edge_length == 0 then goto continue end
        
        to_edge.x = to_edge.x / to_edge_length
        to_edge.y = to_edge.y / to_edge_length
        
        -- Проверяем, движется ли игрок к краю
        local dot_product = vel_dir.x * to_edge.x + vel_dir.y * to_edge.y
        
        -- Если игрок движется в направлении края
        if dot_product > 0.7 then -- Допуск на отклонение от прямого направления
            local dist = DistanceToEdge(player_pos, edge.pos, edge.dir)
            
            if dist < min_distance then
                min_distance = dist
                closest_edge = edge
            end
        end
        
        ::continue::
    end
    
    -- Если нашли край и достаточно близко к нему
    if closest_edge and min_distance < stop_distance_threshold:GetValue() then
        -- Определяем оптимальное смещение BBox
        local optimal_offset = CalculateOptimalBBoxPosition(
            player_pos, velocity, closest_edge.pos, closest_edge.dir
        )
        
        if optimal_offset then
            -- Вычисляем направление перпендикулярное к краю
            local edge_perp = Vector3(-closest_edge.dir.y, closest_edge.dir.x, 0)
            
            -- Определяем в каком направлении от края находится игрок
            local to_player = Vector3(
                player_pos.x - closest_edge.pos.x,
                player_pos.y - closest_edge.pos.y,
                0
            )
            
            local side_dot = to_player.x * edge_perp.x + to_player.y * edge_perp.y
            
            -- Если игрок на нужной стороне от края
            if math.sign(side_dot) == math.sign(optimal_offset) then
                -- Определяем направление блокировки движения
                movement_block_direction = Vector3(
                    closest_edge.dir.y,
                    -closest_edge.dir.x,
                    0
                )
                
                if side_dot < 0 then
                    movement_block_direction.x = -movement_block_direction.x
                    movement_block_direction.y = -movement_block_direction.y
                end
                
                should_stop_movement = true
                return
            end
        end
    end
    
    should_stop_movement = false
    movement_block_direction = nil
end

-- Вспомогательная функция для определения знака числа
function math.sign(x)
    return x > 0 and 1 or (x < 0 and -1 or 0)
end

-- Функция блокировки движения на краю
local function BlockMovementAtEdge(cmd)
    if not should_stop_movement or not movement_block_direction then return end
    
    -- Получаем текущие углы обзора
    local view_angles = cmd:GetViewAngles()
    
    -- Вычисляем векторы направления в координатах игрока
    local rad_yaw = math.rad(view_angles.y)
    local forward = Vector3(math.cos(rad_yaw), math.sin(rad_yaw), 0)
    local right = Vector3(math.cos(rad_yaw + 90), math.sin(rad_yaw + 90), 0)
    
    -- Проекции на направления движения
    local forward_dot = forward.x * movement_block_direction.x + forward.y * movement_block_direction.y
    local right_dot = right.x * movement_block_direction.x + right.y * movement_block_direction.y
    
    -- Блокируем движение по направлению к краю
    if forward_dot > 0 and cmd:GetForwardMove() > 0 then
        cmd:SetForwardMove(0)
    elseif forward_dot < 0 and cmd:GetForwardMove() < 0 then
        cmd:SetForwardMove(0)
    end
    
    if right_dot > 0 and cmd:GetSideMove() > 0 then
        cmd:SetSideMove(0)
    elseif right_dot < 0 and cmd:GetSideMove() < 0 then
        cmd:SetSideMove(0)
    end
end

-- Функция визуализации
local function DrawVisualization()
    if not visualize_toggle:GetValue() then return end
    
    -- Отображаем траекторию
    if #trajectory_points > 0 then
        local r, g, b, a = trajectory_color:GetValue()
        draw.Color(r, g, b, a)
        
        for i = 1, #trajectory_points - 1 do
            local p1 = trajectory_points[i].pos
            local p2 = trajectory_points[i + 1].pos
            
            local x1, y1 = client.WorldToScreen(p1)
            local x2, y2 = client.WorldToScreen(p2)
            
            if x1 and y1 and x2 and y2 then
                draw.Line(x1, y1, x2, y2)
                
                if trajectory_points[i + 1].hit then
                    draw.FilledRect(x2 - 3, y2 - 3, x2 + 3, y2 + 3)
                end
            end
        end
        
        -- Отображаем bbox в последней точке
        if #trajectory_points > 0 then
            local last_pos = trajectory_points[#trajectory_points].pos
            
            for _, corner in ipairs(get_bbox_corners(last_pos)) do
                local x, y = client.WorldToScreen(corner)
                if x and y then
                    draw.FilledCircle(x, y, 2)
                end
            end
        end
    end
    
    -- Отображаем найденные края
    if #detected_edges > 0 then
        local r, g, b, a = edge_color:GetValue()
        draw.Color(r, g, b, a)
        
        local size = edge_size:GetValue()
        
        for _, edge in ipairs(detected_edges) do
            local x, y = client.WorldToScreen(edge.pos)
            
            if x and y then
                draw.FilledCircle(x, y, size)
                
                -- Отображаем направление края
                local dir_end = Vector3(
                    edge.pos.x + edge.dir.x * 20,
                    edge.pos.y + edge.dir.y * 20,
                    edge.pos.z
                )
                
                local dir_x, dir_y = client.WorldToScreen(dir_end)
                
                if dir_x and dir_y then
                    draw.Line(x, y, dir_x, dir_y)
                end
            end
        end
    end
    
    -- Отображаем состояние блокировки движения
    if should_stop_movement then
        draw.Color(255, 0, 0, 255)
        draw.Text(10, 10, "Движение блокировано на краю")
    end
end

-- Основной цикл обновления
callbacks.Register("CreateMove", function(cmd)
    -- Предсказываем траекторию
    local surface = predict_trajectory()
    
    -- Если нашли поверхность приземления, ищем на ней края
    if surface then
        detected_edges = DetectEdges(surface.pos, surface.normal)
        
        -- Определяем, нужно ли блокировать движение
        ShouldStopMovement()
        
        -- Применяем блокировку движения, если нужно
        BlockMovementAtEdge(cmd)
    else
        should_stop_movement = false
        movement_block_direction = nil
    end
end)

-- Цикл отрисовки
callbacks.Register("Draw", DrawVisualization)
