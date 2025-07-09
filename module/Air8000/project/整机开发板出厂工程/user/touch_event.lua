-- touch_event.lua
local touch_event = {}

-- 事件类型定义
touch_event.EVENT_CLICK = 1 --单击事件
-- touch_event.EVENT_DOUBLE_CLICK = 2  --双击事件,实际用途不大
touch_event.EVENT_LONG_PRESS = 3 --长按事件
touch_event.EVENT_SWIPE_LEFT = 4 --左滑事件
touch_event.EVENT_SWIPE_RIGHT = 5 --右滑事件
touch_event.EVENT_SWIPE_UP = 6 --上滑事件
touch_event.EVENT_SWIPE_DOWN = 7 --下滑事件

-- 内部状态
local state = "IDLE"--默认闲置状态，按压和
local start_time = 0  -- 按下时间戳
local start_x, start_y = 0, 0 --按下初始坐标
local last_x, last_y = 0, 0  --抬手时坐标
local last_move_time = 0  -- 最后移动时间戳

-- 阈值定义（单位：像素）
local CLICK_MAX_MOVE = 50   --长按允许区域，超过算滑动
local SWIPE_THRESHOLD = 70  -- 滑动距离大于70判断为滑动，可以根据屏幕尺寸设置
local SWIPE_RATIO = 2.0     -- 滑动长的距离是滑动短的距离2倍以上，判定长边为滑动方向，斜向滑动且距离相差不在2倍以上，滑动不生效
local LONG_PRESS_DURATION = 500  -- 超过500（毫秒）为长按

-- 初始化手势识别
function touch_event.init()
    state = "IDLE"
    start_time = 0
    start_x, start_y = 0, 0
    last_x, last_y = 0, 0
    last_move_time = 0
end

-- 计算两点之间的距离
local function distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- 处理触摸事件（只考虑坐标）
function touch_event.process(point)
    local x, y, event = point.x, point.y, point.event
    local result = nil
    local now = point.time or mcu.ticks()  -- 获取当前时间戳
    
    if event == 1 then -- 按下
        if state == "IDLE" then --闲置状态转为按压状态
            state = "PRESSED"
            start_time = now
            start_x, start_y = x, y
            last_x, last_y = x, y
            last_move_time = now
        end
        
    elseif event == 2 then -- 抬起
        if state == "PRESSED" then
            local duration = now - start_time  -- 按下持续时间
            
            -- 计算移动距离
            local dist = distance(start_x, start_y, x, y)
            
            -- 长按检测：时间超过阈值且移动距离在允许范围内
            if duration >= LONG_PRESS_DURATION and dist <= CLICK_MAX_MOVE then
                result = {tag = touch_event.EVENT_LONG_PRESS, x = start_x, y = start_y}
            else
                -- 滑动和点击检测逻辑
                local dx = x - start_x
                local dy = y - start_y
                local adx = math.abs(dx)--返回绝对值
                local ady = math.abs(dy)
                
                -- 检测滑动主方向移动距离
                if adx > ady then--滑动方向为X
                    if adx > SWIPE_THRESHOLD and adx > ady * SWIPE_RATIO then --符合X轴的滑动判定
                        if dx < 0 then
                            result = {tag = touch_event.EVENT_SWIPE_LEFT, x = start_x, y = start_y} --距离减小为左
                        else
                            result = {tag = touch_event.EVENT_SWIPE_RIGHT, x = start_x, y = start_y}--记录增大为右
                        end
                    end
                else
                    if ady > SWIPE_THRESHOLD and ady > adx * SWIPE_RATIO then--符合Y轴的滑动判定
                        if dy < 0 then
                            result = {tag = touch_event.EVENT_SWIPE_UP, x = start_x, y = start_y}
                        else
                            result = {tag = touch_event.EVENT_SWIPE_DOWN, x = start_x, y = start_y}
                        end
                    end
                end
                
                -- 检测点击
                if not result and adx <= CLICK_MAX_MOVE and ady <= CLICK_MAX_MOVE then --符合点击判定
                    result = {tag = touch_event.EVENT_CLICK, x = start_x, y = start_y}
                end
            end
            
            touch_event.init()
        end
        
    elseif event == 3 then -- 移动
        if state == "PRESSED" then
            last_x, last_y = x, y
            last_move_time = now
            
            -- 原有滑动检测逻辑
            local dx = x - start_x
            local dy = y - start_y
            local adx = math.abs(dx)
            local ady = math.abs(dy)
            
            -- 检测滑动主方向移动距离
            if adx > ady then
                if adx > SWIPE_THRESHOLD and adx > ady * SWIPE_RATIO then
                    if dx < 0 then
                        result = {tag = touch_event.EVENT_SWIPE_LEFT, x = start_x, y = start_y}
                    else
                        result = {tag = touch_event.EVENT_SWIPE_RIGHT, x = start_x, y = start_y}
                    end
                end
            else
                if ady > SWIPE_THRESHOLD and ady > adx * SWIPE_RATIO then
                    if dy < 0 then
                        result = {tag = touch_event.EVENT_SWIPE_UP, x = start_x, y = start_y}
                    else
                        result = {tag = touch_event.EVENT_SWIPE_DOWN, x = start_x, y = start_y}
                    end
                end
            end
            
            -- 如果检测到滑动，立即返回结果
            if result then
                touch_event.init()
            end
        end
    end
    
    return result
end

return touch_event