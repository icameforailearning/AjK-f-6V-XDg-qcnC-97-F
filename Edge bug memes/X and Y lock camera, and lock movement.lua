-- Скрипт управления движением и чувствительностью камеры для Aimware

-- Создаем необходимые элементы пользовательского интерфейса
local SCRIPT_TAB = gui.Tab(gui.Reference("Misc"), "movement_control", "Управление движением")
local SCRIPT_GROUPBOX = gui.Groupbox(SCRIPT_TAB, "Настройки управления движением", 15, 15, 200, 0)

-- Чекбокс для включения/отключения скрипта
local ENABLE_SCRIPT = gui.Checkbox(SCRIPT_GROUPBOX, "enable_movement_control", "Включить управление движением", false)

-- Чекбокс для блокировки движения
local STOP_MOVEMENT = gui.Checkbox(SCRIPT_GROUPBOX, "stop_movement", "Блокировать движение", false)

-- Слайдер для контроля чувствительности камеры (m_yaw)
local CAMERA_SENSITIVITY = gui.Slider(SCRIPT_GROUPBOX, "camera_sensitivity", "Чувствительность камеры", 0, 0, 1, 0.01)

-- Переменные для хранения оригинального значения m_yaw
local original_m_yaw = 0
local has_original_m_yaw = false

-- Функция для ограничения значения в диапазоне (вместо clamp)
local function limit_value(value, min_val, max_val)
    if value < min_val then
        return min_val
    elseif value > max_val then
        return max_val
    else
        return value
    end
end

-- Функция для получения текущего значения m_yaw
local function get_m_yaw()
    return client.GetConVar("m_yaw")
end

-- Функция для установки значения m_yaw
local function set_m_yaw(value)
    client.SetConVar("m_yaw", value, true)
end

-- Функция для блокировки движения игрока
local function block_movement(cmd)
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
end

-- Функция для управления чувствительностью камеры
local function control_camera_sensitivity()
    -- Сохраняем оригинальное значение m_yaw при первом запуске
    if not has_original_m_yaw then
        original_m_yaw = get_m_yaw()
        has_original_m_yaw = true
    end

    -- Получаем значение слайдера
    local sensitivity_factor = CAMERA_SENSITIVITY:GetValue()

    -- Рассчитываем новое значение m_yaw
    -- 0 = оригинальное значение, 1 = полная блокировка (m_yaw = 0)
    local new_m_yaw = original_m_yaw * (1 - sensitivity_factor)

    -- Ограничиваем значение для безопасности
    new_m_yaw = limit_value(new_m_yaw, 0, original_m_yaw)

    -- Устанавливаем новое значение
    set_m_yaw(new_m_yaw)
end

-- Функция для восстановления оригинального значения m_yaw
local function restore_m_yaw()
    if has_original_m_yaw then
        set_m_yaw(original_m_yaw)
    end
end

-- Основная функция, вызываемая на каждое движение
local function on_create_move(cmd)
    -- Проверяем, включен ли скрипт
    if not ENABLE_SCRIPT:GetValue() then
        -- Восстанавливаем оригинальное значение m_yaw если скрипт выключен
        restore_m_yaw()
        has_original_m_yaw = false
        return
    end

    -- Управляем чувствительностью камеры
    control_camera_sensitivity()

    -- Проверяем, нужно ли блокировать движение
    local should_block = STOP_MOVEMENT:GetValue()

    -- Если установлена кнопка, проверяем нажата ли она
    local key = MOVEMENT_BLOCK_KEY:GetValue()
    if key ~= 0 then
        should_block = input.IsButtonDown(key)
    end

    -- Если нужно блокировать движение, выполняем блокировку
    if should_block then
        block_movement(cmd)
    end
end

-- Функция, вызываемая при выгрузке скрипта
local function on_unload()
    -- Восстанавливаем оригинальное значение m_yaw
    restore_m_yaw()
end

-- Регистрируем функции обратного вызова
callbacks.Register("CreateMove", on_create_move)
callbacks.Register("Unload", on_unload)
