--[[
@module  time_page
@summary 时间显示演示模块
@version 1.0
@date    2026.08.19
@author  江访
@usage
本模块为时间显示演示功能模块，主要功能包括：
1、使用os.date接口获取当前时间；
2、显示多种时间格式；
3、自动切换时间格式（局部刷新，不闪烁）；

按键功能：
- PWR键：返回主页

对外接口：
1、time_page.draw()：绘制时间显示页面
2、time_page.handle_key()：处理时间页面按键事件
3、time_page.need_update()：检查是否需要更新时间
4、time_page.auto_update()：自动切换格式并局部刷新
5、time_page.on_enter()：页面进入时重置状态
6、time_page.on_leave()：页面离开时执行清理操作
]]

local time_page = {}

-- 时间显示状态
local time_state = {
    format_index = 1,       -- 当前显示格式索引
    last_update = 0,        -- 最后更新时间
    update_interval = 5000, -- 自动切换格式间隔（5秒）
    display_formats = {     -- 时间显示格式列表
        {name = "完整格式", format = "%Y年%m月%d日 %H:%M:%S"},
        {name = "简洁格式", format = "%Y-%m-%d %H:%M"},
        {name = "时间格式", format = "%H:%M:%S"},
        {name = "日期格式", format = "%Y/%m/%d"},
        {name = "星期格式", format = "%A %H:%M"},
        {name = "UTC时间", format = "!%H:%M:%S UTC"}
    }
}

-- 是否首次绘制（首次全刷保证画面干净，之后局部刷新避免闪烁）
local first_draw = true

--[[
获取当前时间字符串
@local
@return string 格式化后的时间字符串
]]
local function get_time_string()
    local format_info = time_state.display_formats[time_state.format_index]
    return os.date(format_info.format)
end

-- 时间显示框布局（250x122横屏）
local TIME_X1, TIME_Y1, TIME_X2, TIME_Y2 = 20, 38, 230, 66

--[[
刷新屏幕；
首次绘制用全刷(FULL)，之后局部刷新(PARTIAL)避免闪烁；

@local
@return nil
]]
local function refresh_screen()
    local mode = first_draw and epd.FULL or epd.PARTIAL
    local ok, rerr = panel:refresh(mode).wait()
    if not ok then
        log.error("time_page", "refresh failed", rerr)
    end
    first_draw = false
end

--[[
绘制时间显示页面；
绘制时间显示页面的所有UI元素（250x122横屏）；

@api time_page.draw()
@summary 绘制时间显示页面的所有UI元素
@return nil

@usage
-- 在UI主循环中调用
time_page.draw()
]]
function time_page.draw()
    -- 清空画布为白色
    panel:clear(epd.WHITE)
    panel:setColor(epd.BLACK, epd.WHITE)

    -- 显示标题（框 y=4..24 高20，16号字基线21顶部5底部21，完全在框内）
    panel:rect(10, 4, 240, 24, epd.BLACK, 0)   -- 标题背景框
    panel:drawHzfont(105, 20, "时间显示", 16)

    -- 时间显示框（加宽 y 高度，给16号字下降部留空间，框 y=32..64）
    panel:rect(10, 32, 240, 64, epd.BLACK, 0)

    -- 显示当前时间（14号字，居中，避免长字符串超框）
    local time_str = get_time_string()
    local tw = panel:getHzfontWidth(time_str, 14)
    local tx = math.floor((250 - tw) / 2)
    if tx < 14 then tx = 14 end
    if tx + tw > 236 then
        -- 超框时左对齐并缩小到12号
        tx = 14
        tw = panel:getHzfontWidth(time_str, 12)
        panel:drawHzfont(tx, 58, time_str, 12)
    else
        panel:drawHzfont(tx, 58, time_str, 14)
    end

    -- 显示格式名称（基线84）
    panel:drawHzfont(20, 84, "时间格式:", 12)
    local format_info = time_state.display_formats[time_state.format_index]
    panel:drawHzfont(100, 84, format_info.name, 12)

    -- 显示格式索引（基线102）
    panel:drawHzfont(20, 102, string.format("%d/%d",
        time_state.format_index,
        #time_state.display_formats), 12)

    -- 显示操作提示（基线102，只保留返回提示）
    panel:drawHzfont(150, 102, "PWR键:返回", 12)

    -- 刷新屏幕
    refresh_screen()

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

    if key_type == "pwr_up" then
        -- PWR键：返回首页
        switch_page("home")
        return true
    end
    return false
end

--[[
检查是否需要更新；
基于时间间隔判断是否需要刷新显示；

@api time_page.need_update()
@summary 检查是否需要更新时间显示
@return bool 需要更新返回true，否则返回false

@usage
-- 在UI主循环中调用
if time_page.need_update() then
    time_page.auto_update()
end
]]
function time_page.need_update()
    local current_time = mcu.ticks()
    return (current_time - time_state.last_update) >= time_state.update_interval
end

--[[
自动更新；
自动切换到下一种时间格式，并局部刷新显示；
配合need_update()在UI主循环中周期调用，实现时间格式自动轮播；

@api time_page.auto_update()
@summary 自动切换时间格式并局部刷新
@return nil

@usage
-- 在UI主循环超时分支中调用
if time_page.need_update() then
    time_page.auto_update()
end
]]
function time_page.auto_update()
    -- 自动切换到下一种格式
    time_state.format_index = time_state.format_index % #time_state.display_formats + 1
    log.info("time_page", "自动切换格式:", time_state.format_index)
    time_page.draw()
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
    first_draw = true   -- 进入页面时全刷，确保画面干净
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
