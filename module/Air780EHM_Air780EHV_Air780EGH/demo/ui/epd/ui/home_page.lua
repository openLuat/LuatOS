--[[
@module  home_page
@summary epd主页模块，提供应用入口和导航功能
@version 1.0
@date    2026.08.19
@author  江访
@usage
本模块为主页模块，主要功能包括：
1、提供应用入口和导航功能；
2、显示系统标题和操作提示；
3、管理三个功能选项的选中状态；
4、处理主页面的按键事件；

对外接口：
1、home_page.draw()：绘制主页面所有UI元素，包括选中指示
2、home_page.handle_key()：处理主页面按键事件
3、home_page.on_enter()：页面进入时重置选中状态
]]

local home_page = {}

-- 选项区域定义（epd屏幕250x122横屏，两行布局）
-- 选项框高度22px，比标题/底部留出充足间距，避免重叠
local options = {
    {name = "epd_demo",  text = "图形演示", x1 = 20,  y1 = 42, x2 = 120, y2 = 64},
    {name = "info_demo", text = "动态信息", x1 = 130, y1 = 42, x2 = 230, y2 = 64},
    {name = "time_demo", text = "时间显示", x1 = 20,  y1 = 70, x2 = 120, y2 = 92},
}

-- 当前选中项索引
local selected_index = 1

-- 是否首次绘制（首次全刷保证画面干净，之后切换用局部刷新避免闪烁）
local first_draw = true

--[[
刷新屏幕；
首次绘制用全刷(FULL)确保画面干净，之后切换选项用局部刷新(PARTIAL)避免闪烁；

@local
@return nil
]]
local function refresh_screen()
    local mode = first_draw and epd.FULL or epd.PARTIAL
    local ok, rerr = panel:refresh(mode).wait()
    if not ok then
        log.error("home_page", "refresh failed", rerr)
    end
    first_draw = false
end

--[[
绘制主页界面；
绘制主页面所有UI元素，包括选中指示；

@api home_page.draw()
@summary 绘制主页面所有UI元素，包括选中指示
@return nil

@usage
-- 在UI主循环中调用
home_page.draw()
]]
function home_page.draw()
    -- 清空画布为白色
    panel:clear(epd.WHITE)

    -- 设置黑色前景、白色背景
    panel:setColor(epd.BLACK, epd.WHITE)

    -- 显示标题（框 y=4..24 高20px，16号字基线21，文字顶部5底部21，完全在框内）
    panel:rect(10, 2, 240, 24, epd.BLACK, 0)   -- 标题背景框
    panel:drawHzfont(72, 18, "epd演示系统", 16)

    -- 显示操作提示（基线36，12号字顶部约24，贴合标题框底24，不重叠）
    panel:drawHzfont(20, 36, "BOOT:切换 PWR:确认", 12)

    -- 绘制所有选项框
    for i, opt in ipairs(options) do
        if i == selected_index then
            -- 选中状态：实心矩形 + 白色文字（14号字基线y1+17，垂直居中不贴边）
            panel:rect(opt.x1, opt.y1, opt.x2, opt.y2, epd.BLACK, 1)
            panel:setColor(epd.WHITE, epd.BLACK)
            panel:drawHzfont(opt.x1 + 15, opt.y1 + 17, opt.text, 14)
            panel:setColor(epd.BLACK, epd.WHITE)
        else
            -- 未选中状态：空心矩形 + 黑色文字
            panel:rect(opt.x1, opt.y1, opt.x2, opt.y2, epd.BLACK, 0)
            panel:drawHzfont(opt.x1 + 15, opt.y1 + 17, opt.text, 14)
        end
    end

    -- 绘制底部信息（基线112，12号字顶部100，位于选项框92下方，不重叠）
    panel:drawHzfont(30, 112, "epd核心库演示", 12)
    panel:drawHzfont(150, 112, "微雪2.13寸", 12)

    -- 刷新屏幕
    refresh_screen()
end

--[[
处理主页按键事件；
根据按键类型执行相应的操作；
注意：此处只更新选中状态，由UI主循环统一调用draw()重绘，避免重复刷新；

@api home_page.handle_key(key_type, switch_page)
@summary 处理主页按键事件
@string key_type 按键类型
@valid_values "confirm", "next", "prev", "back"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = home_page.handle_key("next", switch_page)
]]
function home_page.handle_key(key_type, switch_page)
    log.info("home_page.handle_key", "key_type:", key_type, "selected_index:", selected_index)

    if key_type == "confirm" or key_type == "pwr_up" or key_type == "pwr_down" then
        -- 确认键：切换到选中的页面
        switch_page(options[selected_index].name)
        return true
    elseif key_type == "next" or key_type == "boot_up" then
        -- 方向键：切换到下一个选项
        selected_index = selected_index % #options + 1
        log.info("home_page", "切换到选项:", selected_index)
        first_draw = false   -- 确保切换用局部刷新，不闪烁
        return true
    elseif key_type == "prev" then
        -- 方向键：切换到上一个选项
        selected_index = (selected_index - 2 + #options) % #options + 1
        first_draw = false
        return true
    end
    return false
end

--[[
页面进入时重置状态；

@api home_page.on_enter()
@summary 页面进入时重置状态
@return nil

@usage
-- 在页面切换时调用
home_page.on_enter()
]]
function home_page.on_enter()
    selected_index = 1
    first_draw = true   -- 进入主页时全刷，确保画面干净
    log.info("home_page", "进入主页")
end

--[[
页面离开时执行清理操作；

@api home_page.on_leave()
@summary 页面离开时执行清理操作
@return nil

@usage
-- 在页面切换时调用
home_page.on_leave()
]]
function home_page.on_leave()
    log.info("home_page", "离开主页")
end

return home_page
