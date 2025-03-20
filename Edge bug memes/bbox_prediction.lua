-- EdgeBug Trajectory Visualizer для Aimware с учётом BBox и автоматическими дополнительными путями

local ref = gui.Reference("MISC", "da")

local trajectory_group = gui.Groupbox(ref, "Визуализация траектории", 16, 16, 296, 296)

-- Настройки визуализации

local visualize_trajectory = gui.Checkbox(trajectory_group, "eb_visual", "Активировать визуализацию", true)

local trajectory_color = gui.ColorPicker(trajectory_group, "eb_trajectory_color", "Цвет основной траектории", 0, 255, 0, 255)

local prediction_distance = gui.Slider(trajectory_group, "eb_pred_dist", "Дальность прогноза", 15, 1, 64, 1)

-- Системные переменные

local main_trajectory = {}

local gravity = 800

local tick_interval = globals.TickInterval()

-- Для определения направления стрейфа

local prev_velocity = Vector3(0, 0, 0)

local strafe_direction = 0 -- -1 = влево, 0 = нет стрейфа, 1 = вправо

local function get_bbox_corners(origin)
    local player = entities.GetLocalPlayer()
    if not player then return {} end
    
    local mins, maxs = player:GetMins(), player:GetMaxs()
    
    return {
        origin + Vector3(mins.x, mins.y, mins.z),
        origin + Vector3(maxs.x, mins.y, mins.z),
        origin + Vector3(maxs.x, maxs.y, mins.z),
        origin + Vector3(mins.x, maxs.y, mins.z),
        origin + Vector3(mins.x, mins.y, maxs.z),
        origin + Vector3(maxs.x, mins.y, maxs.z),
        origin + Vector3(maxs.x, maxs.y, maxs.z),
        origin + Vector3(mins.x, maxs.y, maxs.z)
    }
end

local function trace_hull(start_origin, end_origin)
    local min_fraction = 1.0
    local hit_pos = end_origin
    local hit = false
    
    for _, start_pos in ipairs(get_bbox_corners(start_origin)) do
        local end_pos = end_origin + (start_pos - start_origin)
        local trace = engine.TraceLine(start_pos, end_pos, 0x1)
        
        if trace.fraction < min_fraction then
            min_fraction = trace.fraction
            hit_pos = end_origin + (trace.endpos - start_pos)
            hit = true
        end
    end
    
    return {
        fraction = min_fraction,
        endpos = hit_pos,
        hit = hit
    }
end

-- Исправленная функция для определения направления стрейфа
local function update_strafe_direction(player)
    local velocity = player:GetPropVector("m_vecVelocity")
    local eye_angles = player:GetPropVector("m_angEyeAngles")
    
    -- Проверяем, движется ли игрок значительно
    local vel_length = math.sqrt(velocity.x^2 + velocity.y^2)
    if vel_length < 5 then
        strafe_direction = 0
        return
    end
    
    -- Определяем поворот, сравнивая текущее направление скорости с предыдущим
    local current_dir = math.atan2(velocity.y, velocity.x)
    local prev_dir = math.atan2(prev_velocity.y, prev_velocity.x)
    local diff = current_dir - prev_dir
    
    -- Нормализуем разницу в пределах [-π, π]
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    
    -- Определение направления стрейфа (оставляем как есть)
    if math.abs(diff) > 0.02 then -- Небольшой порог для избежания дрожания
        if diff > 0 then
            strafe_direction = 1 -- Стрейф вправо
        else
            strafe_direction = -1 -- Стрейф влево
        end
    end
    
    -- Обновляем предыдущую скорость
    prev_velocity = Vector3(velocity.x, velocity.y, velocity.z)
end

-- Функция для расчета траектории с учетом смещения
local function calculate_trajectory(start_pos, start_velocity, offset_direction, offset_amount)
    local trajectory = {}
    local current_pos = Vector3(start_pos.x, start_pos.y, start_pos.z)
    local current_vel = Vector3(start_velocity.x, start_velocity.y, start_velocity.z)
    
    -- Применяем смещение к скорости, если необходимо
    if offset_direction ~= 0 and offset_amount ~= 0 then
        -- Создаем нормализованный перпендикулярный вектор к скорости
        local vel_length = math.sqrt(current_vel.x^2 + current_vel.y^2)
        if vel_length > 0 then
            local perpendicular
            
            -- ИСПРАВЛЕНО: Поменяли местами расчет перпендикулярного вектора
            if offset_direction < 0 then -- Влево
                perpendicular = Vector3(current_vel.y / vel_length, -current_vel.x / vel_length, 0)
            else -- Вправо
                perpendicular = Vector3(-current_vel.y / vel_length, current_vel.x / vel_length, 0)
            end
            
            -- Применяем смещение к скорости
            current_vel.x = current_vel.x + perpendicular.x * offset_amount
            current_vel.y = current_vel.y + perpendicular.y * offset_amount
        end
    end
    
    for i = 1, prediction_distance:GetValue() do
        -- Применяем гравитацию
        current_vel.z = current_vel.z - (gravity * tick_interval)
        
        local next_pos = Vector3(
            current_pos.x + (current_vel.x * tick_interval),
            current_pos.y + (current_vel.y * tick_interval),
            current_pos.z + (current_vel.z * tick_interval)
        )
        
        local trace_result = trace_hull(current_pos, next_pos)
        
        table.insert(trajectory, {
            pos = Vector3(current_pos.x, current_pos.y, current_pos.z),
            hit = trace_result.hit
        })
        
        current_pos = trace_result.hit and trace_result.endpos or next_pos
        
        if trace_result.hit then break end
    end
    
    return trajectory
end

local function predict_trajectories()
    main_trajectory = {}
    
    local player = entities.GetLocalPlayer()
    
    if not visualize_trajectory:GetValue()
        or not player
        or not player:IsAlive()
        or bit.band(player:GetPropInt("m_fFlags"), 1) ~= 0 then -- Пропускаем, если на земле
        return
    end
    
    -- Обновляем направление стрейфа
    update_strafe_direction(player)
    
    local velocity = player:GetPropVector("m_vecVelocity")
    local current_pos = player:GetAbsOrigin()
    
    -- Рассчитываем основную траекторию
    main_trajectory = calculate_trajectory(current_pos, velocity, 0, 0)
end

local function draw_bbox(pos, r, g, b, a)
    local corners = get_bbox_corners(pos)
    
    draw.Color(r, g, b, a)
    for _, corner in ipairs(corners) do
        local x, y = client.WorldToScreen(corner)
        if x and y then
            draw.FilledCircle(x, y, 2)
        end
    end
end

local function draw_trajectory(trajectory, r, g, b, a)
    if #trajectory == 0 then return end
    
    draw.Color(r, g, b, a)
    
    -- Рисуем линии траектории
    for i = 1, #trajectory - 1 do
        local p1 = trajectory[i].pos
        local p2 = trajectory[i + 1].pos
        
        local x1, y1 = client.WorldToScreen(p1)
        local x2, y2 = client.WorldToScreen(p2)
        
        if x1 and y1 and x2 and y2 then
            draw.Line(x1, y1, x2, y2)
            
            if trajectory[i + 1].hit then
                draw.FilledRect(x2 - 3, y2 - 3, x2 + 3, y2 + 3)
            end
        end
    end
    
    -- Рисуем BBox в последней точке
    local last_pos = trajectory[#trajectory].pos
    draw_bbox(last_pos, r, g, b, a)
end

callbacks.Register("Draw", function()
    if not visualize_trajectory:GetValue() then return end
    
    -- Получаем цвета
    local r, g, b, a = trajectory_color:GetValue()
    
    -- Сначала просчитываем траектории
    predict_trajectories()
    
    -- Затем отрисовываем основную траекторию
    draw_trajectory(main_trajectory, r, g, b, a)
end)
