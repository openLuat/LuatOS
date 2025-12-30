--[[
@module  ui_main
@summary 显示主模块
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为显示主模块，核心业务逻辑为：
1、初始化ht1621液晶屏
2、显示时间或日期页面
3、处理按键切换页面
4、定时更新显示内容
5、冒号闪烁控制

本文件对外接口：无
]]

-- 引入驱动模块
local ht1621_drv = require "ht1621_drv"
local key_drv = require "key_drv"

-- 段码屏对象
local seg = nil
-- 当前显示页面：time或date
local current_page = "time"
-- 冒号状态：true为亮，false为灭
local colon_state = true
-- 冒号闪烁定时器ID
local colon_timer = nil
-- 定时更新定时器ID
local update_timer = nil

-- 数字段码表 (0-9)
local digit_map = {
    [0] = 0xEB, -- 0
    [1] = 0x0A, -- 1
    [2] = 0xAD, -- 2
    [3] = 0x8F, -- 3
    [4] = 0x4E, -- 4
    [5] = 0xC7, -- 5
    [6] = 0xE7, -- 6
    [7] = 0x8A, -- 7
    [8] = 0xEF, -- 8
    [9] = 0xCF  -- 9
}

-- 星期数字映射 (1-7)
local week_map = {
    ["Monday"] = 1,
    ["Tuesday"] = 2,
    ["Wednesday"] = 3,
    ["Thursday"] = 4,
    ["Friday"] = 5,
    ["Saturday"] = 6,
    ["Sunday"] = 7
}

--[[
清屏函数
@summary 清除所有显示
]]
local function clear_display()
    if not seg then return end
    for i = 0, 11 do
        ht1621.data(seg, i, 0x00)
    end
end

--[[
显示单个数字到指定位置
@param position number 显示位置 (0,2,4,6,8,10)
@param num number 要显示的数字 (0-9)
@param show_dp boolean 是否显示该位置的小数点
]]
local function show_digit(position, num, show_dp)
    if not seg then return end
    if num < 0 or num > 9 then return end

    local value = digit_map[num]
    if show_dp then
        value = value | 0x10 -- 添加小数点
    end

    ht1621.data(seg, position, value)
end

--[[
显示时间页面
@summary 显示时间和星期
]]
local function show_time()
    if not seg then return end

    -- 清屏
    clear_display()

    -- 获取当前时间
    local now = os.date("*t")
    local hour_str = string.format("%02d", now.hour)
    local min_str = string.format("%02d", now.min)

    -- 获取星期数字 (1-7)
    local week_name = os.date("%A")
    local week_num = week_map[week_name] or 1

    -- 显示时间
    -- 位置1: 小时的十位 (位置0)
    show_digit(0, tonumber(string.sub(hour_str, 1, 1)), false)

    -- 位置2: 小时的个位 (位置2，带冒号)
    show_digit(2, tonumber(string.sub(hour_str, 2, 2)), colon_state)

    -- 位置3: 分钟的十位 (位置4)
    show_digit(4, tonumber(string.sub(min_str, 1, 1)), false)

    -- 位置4: 分钟的个位 (位置6)
    show_digit(6, tonumber(string.sub(min_str, 2, 2)), false)

    -- 位置6: 星期 (位置10，显示1-7)
    show_digit(10, week_num, false)

    -- 设置当前页面
    current_page = "time"

    log.info("ui_main", string.format("显示时间: %s:%s 星期%d", hour_str, min_str, week_num))
end

--[[
显示日期页面
@summary 显示年月日
]]
local function show_date()
    if not seg then return end

    -- 清屏
    clear_display()

    -- 获取当前日期
    local now = os.date("*t")
    local year_str = string.sub(tostring(now.year), 3, 4) -- 最后两位
    local month_str = string.format("%02d", now.month)
    local day_str = string.format("%02d", now.day)

    -- 显示日期
    -- 位置1: 年份的十位 (位置0)
    show_digit(0, tonumber(string.sub(year_str, 1, 1)), false)

    -- 位置2: 年份的个位 (位置2)
    show_digit(2, tonumber(string.sub(year_str, 2, 2)), false)

    -- 位置3: 月份的十位 (位置4)
    show_digit(4, tonumber(string.sub(month_str, 1, 1)), false)

    -- 位置4: 月份的个位 (位置6)
    show_digit(6, tonumber(string.sub(month_str, 2, 2)), false)

    -- 位置5: 日期的十位 (位置8)
    show_digit(8, tonumber(string.sub(day_str, 1, 1)), false)

    -- 位置6: 日期的个位 (位置10)
    show_digit(10, tonumber(string.sub(day_str, 2, 2)), false)

    -- 设置当前页面
    current_page = "date"

    log.info("ui_main", string.format("显示日期: %s-%s-%s", year_str, month_str, day_str))
end

--[[
设置冒号状态
@param state boolean 冒号状态，true为亮，false为灭
]]
local function set_colon_state(state)
    colon_state = state
    -- 如果当前显示的是时间页面，更新冒号显示
    if current_page == "time" then
        local now = os.date("*t")
        local hour_str = string.format("%02d", now.hour)
        show_digit(2, tonumber(string.sub(hour_str, 2, 2)), colon_state)
    end
end

--[[
冒号闪烁处理函数
@summary 每秒钟切换冒号的亮灭状态
]]
local function colon_blink_callback()
    local current_state = colon_state
    set_colon_state(not current_state)
end

--[[
启动冒号闪烁
@summary 创建冒号闪烁定时器
]]
local function start_colon_blink()
    if colon_timer then
        sys.timerStop(colon_timer)
    end
    colon_timer = sys.timerLoopStart(colon_blink_callback, 1000) -- 每1秒执行一次
end

--[[
停止冒号闪烁
@summary 停止冒号闪烁定时器
]]
local function stop_colon_blink()
    if colon_timer then
        sys.timerStop(colon_timer)
        colon_timer = nil
    end
end

--[[
定时更新显示内容
@summary 每30秒检查并更新显示内容
]]
local function periodic_update_callback()
    if current_page == "time" then
        show_time()
    else
        show_date()
    end
    log.info("ui_main", "定时更新显示内容")
end

--[[
启动定时更新
@summary 创建定时更新定时器
]]
local function start_periodic_update()
    if update_timer then
        sys.timerStop(update_timer)
    end
    update_timer = sys.timerLoopStart(periodic_update_callback, 30000) -- 每30秒执行一次
end

--[[
停止定时更新
@summary 停止定时更新定时器
]]
local function stop_periodic_update()
    if update_timer then
        sys.timerStop(update_timer)
        update_timer = nil
    end
end

--[[
切换显示页面
@summary 在时间和日期页面之间切换
]]
local function toggle_page()
    if current_page == "time" then
        show_date()
        -- 停止冒号闪烁
        stop_colon_blink()
    else
        show_time()
        -- 启动冒号闪烁
        start_colon_blink()
    end
end

--[[
按键事件处理回调
@param key_event string 按键事件类型
]]
local function key_event_callback(key_event)
    if key_event == "boot_down" then
        -- 切换显示页面
        toggle_page()
        log.info("ui_main", "按键切换页面")
    end
end

--[[
按键事件处理函数
@summary 处理按键事件，切换显示页面
]]
local function handle_key_event()
    sys.subscribe("KEY_EVENT", key_event_callback)
end


--[[
开机显示函数
@summary 显示全8图案和所有特殊符号，持续1秒
]]
local function show_boot_screen()
    if not seg then return end

    -- 显示全8图案和所有特殊符号，不同ht1621地址可能不同，此接口可用于测试
    ht1621.data(seg, 0, 0xEF | 0x10)  -- 显示第一个8和电池图标
    ht1621.data(seg, 2, 0xEF | 0x10)  -- 显示第二个8和冒号
    ht1621.data(seg, 4, 0xEF | 0x10)  -- 显示第三个8和温度圆圈
    ht1621.data(seg, 6, 0xEF | 0x10)  -- 显示第四个8和右下小数点
    ht1621.data(seg, 8, 0xEF | 0x10)  -- 显示第五个8和右下小数点
    ht1621.data(seg, 10, 0xEF | 0x10) -- 显示第六个8和右下小数点

    log.info("ui_main", "显示开机画面")
end

--[[
主函数
@summary 初始化所有组件并启动主逻辑
]]
local function main()
    -- 初始化HT1621驱动，获取seg对象
    seg = ht1621_drv.init()
    if not seg then
        log.error("ui_main", "HT1621驱动初始化失败")
        return
    end

    -- 显示开机画面
    show_boot_screen()
    sys.wait(1000)

    -- 注册按键事件处理
    handle_key_event()

    -- 初始显示时间页面
    show_time()

    -- 启动冒号闪烁
    start_colon_blink()

    -- 启动定时更新
    start_periodic_update()

    -- 启动内存监控（可选，调试时开启）
    -- sys.timerLoopStart(monitor_memory, 3000)

    log.info("ui_main", "显示主模块初始化完成")
end

-- 运行主函数
sys.taskInit(main)
