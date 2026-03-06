-- Hold S key for 2x speed, release to return to 1x
-- 基于用户提供的JavaScript逻辑改写

local original_speed = 1.0

function key_handler(event)
    if event.event == "down" then
        -- 保存当前速度
        original_speed = mp.get_property_number("speed", 1.0)
        -- 设置为2倍速
        mp.set_property_number("speed", 2.0)
        mp.commandv("show-text", "Speed: 2x", 1000)
    elseif event.event == "up" then
        -- 恢复原来的速度
        mp.set_property_number("speed", original_speed)
        mp.commandv("show-text", "Speed: " .. original_speed .. "x", 1000)
    end
end

-- 注册s键，使用complex选项来启用按下/释放事件
mp.add_key_binding("s", "hold_speed", key_handler, {complex = true})
