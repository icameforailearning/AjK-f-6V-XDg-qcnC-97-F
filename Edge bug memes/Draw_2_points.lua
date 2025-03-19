-- Скрипт установки точек для Aimware V5

-- Элементы интерфейса
local ui_group = gui.Groupbox(gui.Reference("Visuals"), "Установка точек", 300)
local ui_enable = gui.Checkbox(ui_group, "point_placer_enable", "Включить установку точек", true)
local ui_key = gui.Keybox(ui_group, "point_placer_key", "Клавиша для установки точки", 0)
local ui_color = gui.ColorPicker(ui_enable, "point_color", "Цвет точки", 255, 0, 0, 255)
local ui_size = gui.Slider(ui_group, "point_size", "Размер точки", 4, 1, 15)
local ui_line_thickness = gui.Slider(ui_group, "point_line_thickness", "Толщина линии", 2, 1, 5)

-- Массив для хранения точек (максимум 2)
local points = {}

-- Вспомогательные функции для работы с векторами (без запрещённых функций)
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

-- Получение позиции игрока
local function GetPlayerPosition()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return nil end
    
    local origin = player:GetAbsOrigin()
    return CreateVector(origin.x, origin.y, origin.z)
end

-- Функция трассировки для поиска точки на поверхности
local function TraceGround(start_pos, max_distance)
    max_distance = max_distance or 150
    local down_end = CreateVector(start_pos.x, start_pos.y, start_pos.z - max_distance)
    
    -- Используем Vector3 для функций игрового движка
    local trace_start = Vector3(start_pos.x, start_pos.y, start_pos.z)
    local trace_end = Vector3(down_end.x, down_end.y, down_end.z)
    
    -- Используем MASK_PLAYERSOLID (0x201B) для определения коллизий игрока
    local result = engine.TraceLine(trace_start, trace_end, 0x201B)
    
    -- Обработка различных типов результата трассировки
    local fraction = 1.0
    if type(result) == "userdata" then
        pcall(function() fraction = result.fraction end)
    elseif type(result) == "number" then
        fraction = result
    end
    
    -- Вычисляем точку столкновения
    local hit_pos = {
        x = start_pos.x + (down_end.x - start_pos.x) * fraction,
        y = start_pos.y + (down_end.y - start_pos.y) * fraction,
        z = start_pos.z + (down_end.z - start_pos.z) * fraction
    }
    
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

-- Функция отрисовки точек
local function DrawPoints()
    if #points == 0 then return end
    
    local r, g, b, a = ui_color:GetValue()
    local size = ui_size:GetValue()
    
    for i, point in ipairs(points) do
        local screen_x, screen_y = client.WorldToScreen(Vector3(point.x, point.y, point.z))
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
        local x1, y1 = client.WorldToScreen(Vector3(points[1].x, points[1].y, points[1].z))
        local x2, y2 = client.WorldToScreen(Vector3(points[2].x, points[2].y, points[2].z))
        
        if x1 and y1 and x2 and y2 then
            draw.Color(r, g, b, a)
            draw.Line(x1, y1, x2, y2)
        end
    end
end

-- Переменные для обработки нажатий клавиш
local key_pressed = false

-- Основной коллбэк для отрисовки
callbacks.Register("Draw", function()
    if not ui_enable:GetValue() then return end
    
    -- Обработка нажатия клавиши
    local key = ui_key:GetValue()
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
end)
