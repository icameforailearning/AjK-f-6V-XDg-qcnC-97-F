-- Настройки для траектории и BBox
local visualize_bbox = gui.Checkbox(main_group, "eb_visual", "Активировать визуализацию BBox", true)
local trajectory_color = gui.ColorPicker(visualize_bbox, "eb_trajectory_color", "Цвет траектории", 0, 255, 0, 255)
local bbox_color = gui.ColorPicker(main_group, "bbox_color", "Цвет BBox", 0, 0, 255, 150)
local back_edges_color = gui.ColorPicker(main_group, "back_edges_color", "Цвет задних рёбер", 255, 0, 0, 255)
-- Добавляем новые элементы управления
local prediction_ticks = gui.Slider(main_group, "eb_pred_ticks", "Количество тиков прогноза", 15, 1, 64, 1)
local visualize_prediction_bbox = gui.Checkbox(main_group, "eb_visual_prediction_bbox", "Отображать BBox предикшена", true)
-- Оставляем слайдер дистанции для совместимости
local prediction_distance = gui.Slider(main_group, "eb_pred_dist", "Дальность прогноза", 15, 1, 64, 1)
