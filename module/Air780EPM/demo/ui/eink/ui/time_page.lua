--[[
@module  time_page
@summary 时间显示演示模块
@version 1.0
@date    2025.12.25
@author  江访
@usage
本模块为时间显示演示功能模块，主要功能包括：
1、使用os.date接口获取当前时间；
2、显示多种时间格式；
3、支持实时时间更新；

按键功能：
- PWR键：返回主页
- BOOT键：切换时间显示格式

对外接口：
1、time_page.draw()：绘制时间显示页面
2、time_page.handle_key()：处理时间页面按键事件
3、time_page.on_enter()：页面进入时重置状态
4、time_page.on_leave()：页面离开时执行清理操作
]]

local time_page = {}

-- 时间显示状态
local time_state = {
    format_index = 1,       -- 当前显示格式索引
    last_update = 0,        -- 最后更新时间
    update_interval = 5000, -- 更新间隔（5秒）
    display_formats = {     -- 时间显示格式列表
        { name = "Full Format",  format = "%Y/%m/%d %H:%M:%S" },
        { name = "Short Format", format = "%Y-%m-%d %H:%M" },
        { name = "Time Only",    format = "%H:%M:%S" },
        { name = "Date Only",    format = "%Y/%m/%d" },
        { name = "Weekday",      format = "%A %H:%M" },
        { name = "UTC Time",     format = "!%Y-%m-%d %H:%M:%S" }
    }
}

--[[
获取当前时间字符串
@local
@return string 格式化后的时间字符串
]]
local function get_time_string()
    local format_info = time_state.display_formats[time_state.format_index]
    return os.date(format_info.format)
end

--[[
绘制时间显示页面；
绘制时间显示页面的所有UI元素；

@api time_page.draw()
@summary 绘制时间显示页面的所有UI元素
@return nil

@usage
-- 在UI主循环中调用
time_page.draw()
]]
function time_page.draw()
    -- 清除绘图缓冲区
    eink.clear(1, true)

    -- 显示标题
    eink.setFont(eink.font_opposansm22)
    eink.rect(10, 10, 190, 45, 0, 0) -- 标题背景框
    eink.print(30, 35, "Time Display", 0)

    eink.setFont(eink.font_opposansm16)
    -- 显示当前时间
    local time_str = get_time_string()

    -- 时间显示框
    eink.rect(15, 60, 185, 110, 0, 0)

    -- 显示时间
    eink.print(21, 90, time_str, 0)
  
    -- 显示格式信息
    eink.setFont(eink.font_opposansm12)
    local format_info = time_state.display_formats[time_state.format_index]
    eink.print(30, 130, "Format:", 0)
    eink.print(110, 130, format_info.name, 0)

    -- 显示格式索引
    eink.print(90, 145, string.format("%d/%d",
        time_state.format_index,
        #time_state.display_formats), 0)

    -- 绘制分隔线
    eink.line(10, 150, 190, 150, 0)

    -- 显示操作提示
    eink.print(35, 175, "BOOT:Change Format", 0)
    eink.print(35, 190, "PWR: Return to Home", 0)

    -- 刷新屏幕
    eink.show(0, 0, true)

    -- 更新最后更新时间
    time_state.last_update = mcu.ticks()
end

--[[
处理按键事件；
根据按键类型执行相应的操作；

@api time_page.handle_key(key_type, switch_page)
@summary 处理时间页面按键事件
@string key_type 按键类型
@valid_values "boot_up", "pwr_up"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = time_page.handle_key("boot_up", switch_page)
]]
function time_page.handle_key(key_type, switch_page)
    log.info("time_page.handle_key", "key_type:", key_type)

    if key_type == "boot_up" then
        -- BOOT键：切换时间显示格式
        time_state.format_index = time_state.format_index % #time_state.display_formats + 1
        log.info("time_page", "切换到格式:", time_state.format_index)
        return true
    elseif key_type == "pwr_up" then
        -- PWR键：返回首页
        switch_page("home")
        return true
    end
    return false
end

--[[
检查是否需要更新时间；
基于时间间隔判断是否需要刷新显示；

@api time_page.need_update()
@summary 检查是否需要更新时间显示
@return bool 需要更新返回true，否则返回false

@usage
-- 在UI主循环中调用
if time_page.need_update() then
    time_page.draw()
end
]]
function time_page.need_update()
    local current_time = mcu.ticks()
    return (current_time - time_state.last_update) >= time_state.update_interval
end

--[[
页面进入时重置状态；

@api time_page.on_enter()
@summary 页面进入时重置状态
@return nil

@usage
-- 在页面切换时调用
time_page.on_enter()
]]
function time_page.on_enter()
    time_state.format_index = 1
    time_state.last_update = 0
    log.info("time_page", "进入时间显示页面")
end

--[[
页面离开时执行清理操作；

@api time_page.on_leave()
@summary 页面离开时执行清理操作
@return nil

@usage
-- 在页面切换时调用
time_page.on_leave()
]]
function time_page.on_leave()
    log.info("time_page", "离开时间显示页面")
end

return time_page
