-- Player State Monitor for Aimware -- Отслеживает: в воздухе, на земле, в воде, на игроке, на лестнице

local last_state = {} -- Хранит предыдущее состояние

callbacks.Register("CreateMove", function(cmd)
    local local_player = entities.GetLocalPlayer()

    -- Проверка валидности игрока
    if not local_player or local_player:GetHealth() <= 0 then return end

    -- Получаем состояние
    local flags = local_player:GetPropInt("m_fFlags")
    local move_type = local_player:GetPropInt("m_MoveType")

    local state = {
        in_air = not (bit.band(flags, 1) ~= 0) and move_type ~= 9,  -- FL_ONGROUND = 1
        on_ground = bit.band(flags, 1) ~= 0,
        in_water = false,  -- Изначально предполагаем, что игрок не в воде
        on_ladder = move_type == 9,  -- MOVETYPE_LADDER
        on_player = false
    }

    -- Проверяем уровень воды через другие свойства или методы
    if flags and bit.band(flags, 256) ~= 0 then  -- FL_INWATER (обычно это битовая маска для проверки нахождения в воде)
        state.in_water = true
    end

    -- Проверка нахождения на другом игроке
    local ground_entity = local_player:GetPropEntity("m_hGroundEntity")
    if ground_entity and ground_entity:IsPlayer() then
        state.on_player = ground_entity:IsAlive()
    end

    -- Вывод при изменении состояния
    if state.in_air ~= last_state.in_air 
        or state.on_ground ~= last_state.on_ground
        or state.in_water ~= last_state.in_water
        or state.on_ladder ~= last_state.on_ladder
        or state.on_player ~= last_state.on_player then
        
        local output = string.format(
            "[State] In Air: %s | Ground: %s | Water: %s | Ladder: %s | On Player: %s | MoveType: %d",
            state.in_air and "✓" or "✗",
            state.on_ground and "✓" or "✗",
            state.in_water and "✓" or "✗",
            state.on_ladder and "✓" or "✗",
            state.on_player and "✓" or "✗",
            move_type
        )
        
        print(255, 165, 0, "[State Monitor] ")  -- Оранжевый заголовок
        print(output)
        
        last_state = state  -- Обновляем кэш
    end
end)

-- Инициализация 
client.ColorLog(0, 255, 0, "Player State Monitor loaded!\n")
