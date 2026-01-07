--[[
@module  time_page
@summary 时间显示演示模块
@version 1.0
@date    2026.01.06
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
    format_index = 1,     -- 当前显示格式索引
    last_update = 0,      -- 最后更新时间
    update_interval = 5000, -- 更新间隔（5秒）
    display_formats = {   -- 时间显示格式列表
        {name = "完整格式", format = "%Y年%m月%d日 %H:%M:%S"},
        {name = "简洁格式", format = "%Y-%m-%d %H:%M"},
        {name = "时间格式", format = "%H:%M:%S"},
        {name = "日期格式", format = "%Y/%m/%d"},
        {name = "星期格式", format = "%A %H:%M"},
        {name = "UTC时间", format = "!%Y-%m-%d %H:%M:%S"}
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
    eink.setFont(eink.font_opposansm12_chinese)
    eink.rect(10, 10, 190, 45, 0, 0)     -- 标题背景框
    eink.print(70, 30, "时间显示", 0)

    -- 显示当前时间
    local time_str = get_time_string()

    -- 时间显示框
    eink.rect(20, 60, 180, 110, 0, 0)
    
    -- 统一使用12号中文字体显示时间
    eink.setFont(eink.font_opposansm12_chinese)
    
    -- 根据字符串长度微调显示位置
    if #time_str > 20 then
        -- 长字符串向左偏移
        eink.print(25, 85, time_str, 0)
    else
        -- 短字符串居中显示
        eink.print(30, 85, time_str, 0)
    end

    -- 显示格式信息
    local format_info = time_state.display_formats[time_state.format_index]
    eink.print(30, 130, "当前时间格式:", 0)

    eink.print(130, 130, format_info.name, 0)
            -- 显示格式索引
    eink.print(80, 145, string.format("%d/%d",
        time_state.format_index,
        #time_state.display_formats), 0)

    -- 绘制分隔线
    eink.line(10, 150, 190, 150, 0)

    -- 显示操作提示
    eink.print(55, 175, "GPIO8:切换格式", 0)
    eink.print(55, 190, "GPIO9:返回主页", 0)


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
@valid_values "switch_down", "confirm_down"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = time_page.handle_key("switch_down", switch_page)
]]
function time_page.handle_key(key_type, switch_page)
    log.info("time_page.handle_key", "key_type:", key_type)

    if key_type == "switch_down" then
        -- BOOT键：切换时间显示格式
        time_state.format_index = time_state.format_index % #time_state.display_formats + 1
        log.info("time_page", "切换到格式:", time_state.format_index)
        return true
    elseif key_type == "confirm_down" then
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