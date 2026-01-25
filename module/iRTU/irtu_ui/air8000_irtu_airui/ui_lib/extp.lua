-- extp.lua - 触摸系统模块
--[[
@module  extp
@summary 触摸系统拓展库
@version 1.0.9
@date    2025.11.13
@author  江访
@usage
核心业务逻辑为：
1、初始化触摸设备，支持多种触摸芯片
2、处理原始触摸数据并解析为各种手势事件
3、通过统一消息接口发布触摸事件
4、提供消息发布控制功能
5、提供滑动和长按阈值配置功能

支持的触摸事件类型包括：
1、RAW_DATA - 原始触摸数据
2、TOUCH_DOWN - 按下事件
3、MOVE_X - 水平移动
4、MOVE_Y - 垂直移动
5、SWIPE_LEFT - 向左滑动
6、SWIPE_RIGHT - 向右滑动
7、SWIPE_UP - 向上滑动
8、SWIPE_DOWN - 向下滑动
9、SINGLE_TAP - 单击
10、LONG_PRESS - 长按

触摸判断逻辑：
1、按下至抬手只能触发事件5-10中的一个事件
2、移动像素超过滑动判定阈值，
   如果触发的是水平移动MOVE_X，抬手只会返回SWIPE_LEFT和SWIPE_RIGHT事件，
   如果触发的是垂直移动MOVE_Y，抬手只会返回SWIPE_UP和SWIPE_DOWN事件，
3、按下至抬手像素移动超过滑动判定阈值，
   如果时间小于500ms判定为单击，按下至抬手的时间大于500ms判定为长按

本文件的对外接口有5个：
1、extp.init(param)                      -- 触摸设备初始化函数
2、extp.set_publish_enabled(msg_type, enabled) -- 设置消息发布状态
3、extp.get_publish_enable(msg_type)          -- 获取消息发布状态
4、extp.set_swipe_threshold(threshold)         -- 设置滑动判定阈值
5、extp.set_long_press_threshold(threshold)     -- 设置长按判定阈值

所有触摸事件均通过sys.publish("BASE_TOUCH_EVENT", event_type, ...)发布
]]

local extp = {}

-- 触摸状态变量
local state = "IDLE"             -- 当前状态：IDLE(空闲), DOWN(按下), MOVE(移动)
local touch_down_x = 0           -- 按下时的X坐标
local touch_down_y = 0           -- 按下时的Y坐标
local touch_down_time = 0        -- 按下时的时间戳
local swipe_threshold = 45       -- 滑动判定阈值（像素）
local long_press_threshold = 500 -- 长按判定阈值（毫秒）
local swipe_direction = nil      -- 滑动方向（用于MOVE状态）

-- 消息发布控制表，默认全部打开
local publish_control = {
    RAW_DATA = false,   -- 原始触摸数据
    TOUCH_DOWN = false,  -- 按下事件
    MOVE_X = false,     -- 水平移动
    MOVE_Y = false,     -- 垂直移动
    SWIPE_LEFT = true,  -- 向左滑动
    SWIPE_RIGHT = true, -- 向右滑动
    SWIPE_UP = true,    -- 向上滑动
    SWIPE_DOWN = true,  -- 向下滑动
    SINGLE_TAP = true,  -- 单击
    LONG_PRESS = true   -- 长按
}

-- 定义支持的触摸芯片配置
local tp_configs = {
    cst820 = { i2c_speed = i2c.FAST, tp_model = "cst820" },
    gt9157 = { i2c_speed = i2c.FAST, tp_model = "gt9157" },
    cst9220 = { i2c_speed = i2c.SLOW, tp_model = "cst9220" },
    jd9261t = { i2c_speed = i2c.FAST, tp_model = "jd9261t" },
    gt911 = { i2c_speed = i2c.SLOW, tp_model = "gt911" },
    AirLCD_1010 = { i2c_speed = i2c.SLOW, tp_model = "gt911" },
    Air780EHM_LCD_4 = { i2c_speed = i2c.SLOW, tp_model = "gt911" },
    AirLCD_1020 = { i2c_speed = i2c.SLOW, tp_model = "gt911" }
}

-- 特殊型号的默认配置
local special_tp_configs = {
    Air780EHM_LCD_4 = {
        i2c_id = 1,
        pin_rst = 1,
        pin_int = 22
    },
    AirLCD_1010 = {
        i2c_id = 0,
        pin_rst = 20,
        pin_int = gpio.WAKEUP0
    },
    AirLCD_1020 = {
        i2c_id = i2c.createSoft(0, 1),
        pin_rst = 28,
        pin_int = 7
    }
}

-- 设置消息发布状态
-- @param msg_type 消息类型 ("RAW_DATA", "TOUCH_DOWN", "MOVE_X", "MOVE_Y", "SWIPE_LEFT", "SWIPE_RIGHT", "SWIPE_UP", "SWIPE_DOWN", "SINGLE_TAP", "LONG_PRESS", 或 "ALL")
-- @param enabled 是否启用 (true/false)
-- @return boolean 操作是否成功
function extp.set_publish_enabled(msg_type, enabled)
    if msg_type == "ALL" then
        for k, _ in pairs(publish_control) do
            publish_control[k] = enabled
        end
        log.info("extp", "所有消息发布", enabled and "启用" or "禁用")
        return true
    elseif publish_control[msg_type] ~= nil then
        publish_control[msg_type] = enabled
        log.info("extp", msg_type, "消息发布", enabled and "启用" or "禁用")
        return true
    else
        log.error("extp", "未知的消息类型:", msg_type)
        return false
    end
end

-- 获取消息发布状态
-- @param msg_type 消息类型 ("ALL", "RAW_DATA", "TOUCH_DOWN", "MOVE_X", "MOVE_Y", "SWIPE_LEFT", "SWIPE_RIGHT", "SWIPE_UP", "SWIPE_DOWN", "SINGLE_TAP", "LONG_PRESS")
-- @return boolean|table 发布状态 (true/false) 或所有状态表（当msg_type为"ALL"时）
function extp.get_publish_enable(msg_type)
    if msg_type == "ALL" then
        -- 返回完整的发布控制表
        return publish_control
    elseif publish_control[msg_type] ~= nil then
        return publish_control[msg_type]
    else
        log.error("extp", "未知的消息类型:", msg_type)
        return nil
    end
end

-- 设置滑动判定阈值
-- @param threshold number 滑动判定阈值（像素）
-- @return boolean 操作是否成功
function extp.set_swipe_threshold(threshold)
    if type(threshold) == "number" and threshold > 0 then
        swipe_threshold = threshold
        log.info("extp", "滑动判定阈值设置为:", threshold)
        return true
    else
        log.error("extp", "无效的滑动阈值:", threshold)
        return false
    end
end

-- 设置长按判定阈值
-- @param threshold number 长按判定阈值（毫秒）
-- @return boolean 操作是否成功
function extp.set_long_press_threshold(threshold)
    if type(threshold) == "number" and threshold > 0 then
        long_press_threshold = threshold
        log.info("extp", "长按判定阈值设置为:", threshold)
        return true
    else
        log.error("extp", "无效的长按阈值:", threshold)
        return false
    end
end

-- 触摸回调函数
-- 参数: tp_device-触摸设备对象, tp_data-触摸数据
local function tp_callback(tp_device, tp_data)
    -- 发布原始数据
    if publish_control.RAW_DATA then
        sys.publish("BASE_TOUCH_EVENT", "RAW_DATA", tp_device, tp_data)
    end

    if type(tp_data[1]) ~= "table" then return end

    local event_type = tp_data[1].event
    local x = tp_data[1].x
    local y = tp_data[1].y
    -- 获取高精度时间戳
    local ms_h, ms_l = mcu.ticks2(1)
    -- 使用系统时间戳或触摸数据中的时间戳
    local timestamp = ms_l or tp_data[1].timestamp
    if not event_type then return end

    if event_type == 2 then -- 抬手事件
        if state == "DOWN" or state == "MOVE" then
            local moveX = x - touch_down_x
            local moveY = y - touch_down_y

            if moveX < -swipe_threshold then
                if publish_control.SWIPE_LEFT then
                    sys.publish("BASE_TOUCH_EVENT", "SWIPE_LEFT", moveX, 0)
                end
            elseif moveX > swipe_threshold then
                if publish_control.SWIPE_RIGHT then
                    sys.publish("BASE_TOUCH_EVENT", "SWIPE_RIGHT", moveX, 0)
                end
            elseif moveY < -swipe_threshold then
                if publish_control.SWIPE_UP then
                    sys.publish("BASE_TOUCH_EVENT", "SWIPE_UP", 0, moveY)
                end
            elseif moveY > swipe_threshold then
                if publish_control.SWIPE_DOWN then
                    sys.publish("BASE_TOUCH_EVENT", "SWIPE_DOWN", 0, moveY)
                end
            else
                -- 计算按下时间
                local press_time = timestamp - touch_down_time

                -- 判断是单击还是长按
                if press_time < long_press_threshold then
                    if publish_control.SINGLE_TAP then
                        sys.publish("BASE_TOUCH_EVENT", "SINGLE_TAP", touch_down_x, touch_down_y)
                    end
                else
                    if publish_control.LONG_PRESS then
                        sys.publish("BASE_TOUCH_EVENT", "LONG_PRESS", touch_down_x, touch_down_y)
                    end
                end
            end
            state = "IDLE"
        end
    elseif event_type == 1 or event_type == 3 then -- 按下或移动事件
        if state == "IDLE" and event_type == 1 then
            -- 从空闲状态接收到按下事件
            state = "DOWN"
            touch_down_x = x
            touch_down_y = y
            touch_down_time = timestamp
            swipe_direction = nil

            -- 发布按下事件
            if publish_control.TOUCH_DOWN then
                sys.publish("BASE_TOUCH_EVENT", "TOUCH_DOWN", x, y)
            end
        elseif state == "DOWN" and event_type == 3 then
            -- 在按下状态下接收到移动事件
            if math.abs(x - touch_down_x) >= swipe_threshold or math.abs(y - touch_down_y) >= swipe_threshold then
                state = "MOVE"
                -- 确定滑动方向
                if math.abs(x - touch_down_x) > math.abs(y - touch_down_y) then
                    -- 水平滑动
                    if x - touch_down_x < 0 then
                        swipe_direction = "LEFT"
                    else
                        swipe_direction = "RIGHT"
                    end
                else
                    -- 垂直滑动
                    if y - touch_down_y < 0 then
                        swipe_direction = "UP"
                    else
                        swipe_direction = "DOWN"
                    end
                end
            end
        elseif state == "MOVE" and event_type == 3 then
            -- 在移动状态下接收到移动事件
            -- 根据滑动方向发布相应的移动事件
            if swipe_direction == "LEFT" or swipe_direction == "RIGHT" then
                -- 水平滑动，发布MOVE_X事件
                if publish_control.MOVE_X then
                    sys.publish("BASE_TOUCH_EVENT", "MOVE_X", x - touch_down_x, 0)
                end
            else
                -- 垂直滑动，发布MOVE_Y事件
                if publish_control.MOVE_Y then
                    sys.publish("BASE_TOUCH_EVENT", "MOVE_Y", 0, y - touch_down_y)
                end
            end
        end
    end
end

-- 初始化触摸功能
-- @param param table 初始化参数表，包含以下字段：
--   tp_model: string 触摸芯片型号 ("gt911"、"cst820"、"gt9157"、"jd9261t"、"AirLCD_1010", "AirLCD_1020", "Air780EHM_LCD_4")
--   i2c_id: number I2C总线ID
--   pin_rst: number 复位引脚
--   pin_int: number 中断引脚
-- @return boolean 初始化是否成功
function extp.init(param)
    if type(param) ~= "table" then
        log.error("extp", "参数必须为表")
        return false
    end

    -- 检查必要参数
    if not param.tp_model then
        log.error("extp", "缺少必要参数: tp_model")
        return false
    end

    local tp_model = param.tp_model

    -- 检查是否支持该型号
    local config = tp_configs[tp_model]
    if not config then
        log.error("extp", "不支持的触摸型号:", tp_model)
        return false
    end

    -- 特殊型号参数处理
    local final_param = {}
    final_param.tp_model = tp_model

    -- 处理特殊型号的默认配置
    if special_tp_configs[tp_model] then
        local default_config = special_tp_configs[tp_model]

        if tp_model == "Air780EHM_LCD_4" then
            -- Air780EHM_LCD_4: 强制使用默认配置，忽略传入的其他参数
            final_param.i2c_id = default_config.i2c_id
            final_param.pin_rst = default_config.pin_rst
            final_param.pin_int = default_config.pin_int
            log.info("extp", "Air780EHM_LCD_4使用固定配置")
        else
            -- AirLCD_1010 和 AirLCD_1020: 使用传入参数，如果未传入则使用默认配置
            final_param.i2c_id = param.i2c_id or default_config.i2c_id
            final_param.pin_rst = param.pin_rst or default_config.pin_rst
            final_param.pin_int = param.pin_int or default_config.pin_int

            -- 记录使用的配置来源
            if param.i2c_id then
                log.info("extp", tp_model, "使用传入的i2c_id")
            else
                log.info("extp", tp_model, "使用默认i2c_id")
            end

            if param.pin_rst then
                log.info("extp", tp_model, "使用传入的pin_rst")
            else
                log.info("extp", tp_model, "使用默认pin_rst")
            end

            if param.pin_int then
                log.info("extp", tp_model, "使用传入的pin_int")
            else
                log.info("extp", tp_model, "使用默认pin_int")
            end
        end
    else
        -- 其他型号：直接使用传入参数
        final_param.i2c_id = param.i2c_id
        final_param.pin_rst = param.pin_rst
        final_param.pin_int = param.pin_int
    end

    local tp_i2c_id, tp_pin_rst, tp_pin_int = final_param.i2c_id, final_param.pin_rst or 255, final_param.pin_int

    -- 统一初始化流程
    if type(tp_i2c_id) ~= "userdata" and config.i2c_speed ~= nil then
        log.info("tp", tp_i2c_id, "tp speed", config.i2c_speed)
        i2c.setup(tp_i2c_id, config.i2c_speed)
    end
    local tp_device = tp.init(config.tp_model, { port = tp_i2c_id, pin_rst = tp_pin_rst, pin_int = tp_pin_int },
        tp_callback)
    log.info("tp_model", config.tp_model, "port", tp_i2c_id, "pin_rst", tp_pin_rst, "pin_int", tp_pin_int)
    if tp_device ~= nil then
        return tp_device
    end

    -- 若第一套配置失败，尝试默认 rst 参数重试
    local tp_device_retry = tp.init(config.tp_model, { port = tp_i2c_id, pin_rst = 255, pin_int = tp_pin_int }, tp_callback)
    if tp_device_retry ~= nil then
        return tp_device_retry
    end

    -- 若硬件触摸初始化失败，尝试PC触摸回退
    log.warn("extp", "触摸初始化失败，尝试PC触摸回退")
    local ok_pc, dev_pc = pcall(tp.init, "pc", { port = 0 }, tp_callback)
    if ok_pc and dev_pc then
        log.info("extp", "PC触摸回退成功")
        return dev_pc
    end
    log.error("extp", "PC触摸回退失败")
    return false
end

return extp
