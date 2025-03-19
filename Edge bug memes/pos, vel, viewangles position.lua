-- Настройки интерфейса
local display_group = gui.Groupbox(gui.Reference("Visuals"), "Параметры игрока", 300)
local speed_toggle = gui.Checkbox(display_group, "speed_active", "Скорость игрока", true)
local pos_toggle = gui.Checkbox(display_group, "pos_active", "Позиция игрока", true)
local cam_toggle = gui.Checkbox(display_group, "cam_active", "Углы камеры", true)

local speed_color = gui.ColorPicker(speed_toggle, "clr_speed", 78, 193, 89, 255)
local pos_color = gui.ColorPicker(pos_toggle, "clr_pos", 255, 0, 0, 255)
local cam_color = gui.ColorPicker(cam_toggle, "clr_cam", 0, 128, 255, 255)

local y_offset = gui.Slider(display_group, "y_pos", "Вертикальное смещение", 200, 0, 1080)

-- Функция для получения скорости игрока
local function GetPlayerSpeed()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return Vector3(0,0,0) end
    return player:GetPropVector("m_vecAbsVelocity")
end

-- Функция для получения положения игрока
local function GetPlayerPosition()
    local player = entities.GetLocalPlayer()
    return player and player:IsAlive() and player:GetAbsOrigin() or Vector3(0,0,0)
end

local function GetPlayerViewAngles()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return EulerAngles(0,0,0) end
    return player:GetPropVector("m_angEyeAngles")
end

-- Дополнительный коллбэк для получения углов в режиме реального времени через CreateMove
local current_view_angles = EulerAngles(0, 0, 0)
callbacks.Register("CreateMove", function(cmd)
    if cmd.sendpacket then
        current_view_angles = cmd.viewangles
    end
end)

-- Система рендеринга
callbacks.Register("Draw", function()
    if not (speed_toggle:GetValue() or pos_toggle:GetValue() or cam_toggle:GetValue()) then return end
    
    local base_y = y_offset:GetValue()
    local line_height = 14
    
    if speed_toggle:GetValue() then
        local vel = GetPlayerSpeed()
        draw.Color(speed_color:GetValue())
        draw.Text(10, base_y, string.format("Скорость: X=%.1f, Y=%.1f, Z=%.1f", vel.x, vel.y, vel.z))
        base_y = base_y + line_height
    end
    
    if pos_toggle:GetValue() then
        local pos = GetPlayerPosition()
        draw.Color(pos_color:GetValue())
        draw.Text(10, base_y, string.format("Позиция: X=%.2f, Y=%.2f, Z=%.2f", pos.x, pos.y, pos.z))
        base_y = base_y + line_height
    end
    
    if cam_toggle:GetValue() then
        -- Используем более точные углы из CreateMove, если доступны
        local angles = GetPlayerViewAngles()
        if current_view_angles.x ~= 0 or current_view_angles.y ~= 0 then
            angles = current_view_angles
        end
        draw.Color(cam_color:GetValue())
        draw.Text(10, base_y, string.format("Камера: X=%.2f°, Y=%.2f°", angles.x, angles.y))
    end
end)
