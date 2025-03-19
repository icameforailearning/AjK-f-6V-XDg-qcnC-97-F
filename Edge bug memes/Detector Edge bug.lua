-- Edge Bug Detector with Sound Selection для Aimware

local edgebug_group = gui.Groupbox(gui.Reference("Tab", "Tab"), "EdgeBug Detector Settings")


local edgebug_color = gui.ColorPicker(edgebug_group, "edgebug_clr", "Text Color", 255, 165, 0, 255)
local edgebug_pos_y = gui.Slider(edgebug_group, "edgebug_pos_y", "Vertical Position", 300, 0, 1080)
local detection_threshold = gui.Slider(edgebug_group, "edgebug_thresh", "Detection Threshold", 50, 1, 300)

-- Состояния обнаружения
local last_z_speed = 0
local edgebug_detected = false
local detection_time = 0

-- Таблица соответствия звуков
local sound_files = {
    ["beep07"] = "sounds/edgebugsounds/beep07.wav",
    ["bell1"] = "sounds/edgebugsounds/bell1.wav",
    ["blip1"] = "sounds/edgebugsounds/blip1.wav",
    ["hit"] = "sounds/edgebugsounds/hit.wav"
}


local edgebug_enable = gui.Checkbox(edgebug_group, "edgebug_enable", "Enable EdgeBug Detection", true)
local volume_ctrl = gui.Slider(edgebug_group, "edge_bug.volume", "Volume of EdgeBug Sound", 0.5, 0, 1, 0.01)
local edgebug_sound = gui.Combobox(edgebug_group, "edgebug_sound", "EdgeBug Sound", 
    "Off", "beep07", "bell1", "blip1", "hit")

local function update_sound()
    local current_volume = volume_ctrl:GetValue()
    
    if current_volume ~= last_volume then
        client.Command("snd_toolvolume " .. string.format("%.2f", current_volume), true)
        last_volume = current_volume
    end
end





local function GetPlayerVelocity()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return Vector3(0,0,0) end
    return player:GetPropVector("m_vecAbsVelocity")
end



local function IsInAir()
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then return false end
    local flags = player:GetPropInt("m_fFlags")
    return bit.band(flags, 1) == 0
end

callbacks.Register("CreateMove", function(cmd)
    if not edgebug_enable:GetValue() then return end
    update_sound()
    local velocity = GetPlayerVelocity()
    local current_z = velocity.z
    local move_type = local_player:GetPropInt("m_MoveType")
    
    if move_type == 2313 and move_type == 8 then -- MOVETYPE_LADDER
        edgebug_detected = false
        return
    end

    -- Алгоритм детектирования EdgeBug
    if IsInAir() then
        if last_z_speed < -detection_threshold:GetValue() then
            if current_z > last_z_speed * 0.5 and current_z < -5 then
                edgebug_detected = true
                detection_time = globals.RealTime()
                
                -- Воспроизведение звука
                local selected_sound = edgebug_sound:GetString()
                if selected_sound ~= "Off" and sound_files[selected_sound] then
                    client.Command("play " .. sound_files[selected_sound], true)
                end
                
                client.ChatSay("I am Franzj!")
                print("echo [EDGEBUG] Detected at Z-speed: " .. current_z, true)
            end
        end
    else
        edgebug_detected = false
    end
    
    last_z_speed = current_z
end)

callbacks.Register("Draw", function()
    if not edgebug_enable:GetValue() then return end
    
    local screen_w, screen_h = draw.GetScreenSize()
    local r, g, b, a = edgebug_color:GetValue()
    
    if edgebug_detected and (globals.RealTime() - detection_time < 2) then
        draw.Color(r, g, b, a)
        local text = "EDGE BUG DETECTED!"
        local text_w = draw.GetTextSize(text)
        draw.Text(screen_w/2 - text_w/2, edgebug_pos_y:GetValue(), text)
    end
end)

-- Инструкция для пользователя

print("[EDGEBUG] Configure sounds in Visuals > Overlay > EdgeBug Detector Settings")
