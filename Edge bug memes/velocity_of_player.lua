-- Настройки для отображения скорости
local speed_group = gui.Groupbox(gui.Reference("Visuals"), "Speed Display Settings")
local speed_enable = gui.Checkbox(speed_group, "speed_enable", "Enable Speed Display", true)
local speed_color = gui.ColorPicker(speed_group, "speed_color", "Speed Color", 78, 193, 89, 255)
local font_size = gui.Slider(speed_group, "font_size", "Font Size", 24, 12, 48)
local position_y = gui.Slider(speed_group, "position_y", "Vertical Position", 200, 0, 1080)

-- Функция для получения скорости игрока
local function GetPlayerSpeed()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return 0, 0, 0 end
    
    -- Получаем вектор скорости
    local velocity = player:GetPropVector("m_vecAbsVelocity")
    
    -- Возвращаем компоненты скорости
    return velocity.x, velocity.y, velocity.z
end

-- Функция для отрисовки скорости на экране
callbacks.Register("Draw", function()
    if not speed_enable:GetValue() then return end
    
    -- Получаем компоненты скорости
    local speed_x, speed_y, speed_z = GetPlayerSpeed()
    
    -- Форматируем текст для отображения
    local speed_text = string.format("Speed: X: %.1f Y: %.1f Z: %.1f", speed_x, speed_y, speed_z)
    
    -- Получаем размеры экрана и текста
    local screen_w, screen_h = draw.GetScreenSize()
    local text_w, text_h = draw.GetTextSize(speed_text)
    
    -- Получаем цвет для отображения
    local r, g, b, a = speed_color:GetValue()
    
    -- Устанавливаем цвет и отрисовываем текст
    draw.Color(r, g, b, a)
    draw.Text((screen_w - text_w) / 2, screen_h - position_y:GetValue(), speed_text)
end)