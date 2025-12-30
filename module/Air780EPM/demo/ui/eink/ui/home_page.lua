--[[
@module  home_page
@summary eink主页模块，提供应用入口和导航功能
@version 1.0
@date    2025.12.25
@author  江访  
@usage
本模块为主页模块，主要功能包括：
1、提供应用入口和导航功能；
2、显示系统标题和操作提示；
3、管理两个功能选项的选中状态；
4、处理主页面的按键事件；

对外接口：
1、home_page.draw()：绘制主页面所有UI元素，包括选中指示
2、home_page.handle_key()：处理主页面按键事件
3、home_page.on_enter()：页面进入时重置选中状态
]] 

local home_page = {}

-- 选项区域定义（eink屏幕200x200，需合理布局）
local options = {
    {name = "eink_demo", text = "eink Demo", x1 = 20, y1 = 80, x2 = 90, y2 = 130, color = 0},
    {name = "time_demo", text = "Time Demo", x1 = 110, y1 = 80, x2 = 180, y2 = 130, color = 0}
}

-- 当前选中项索引
local selected_index = 1


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
    -- 清除绘图缓冲区
    eink.clear(1, true)
    eink.setFont(eink.font_opposansm20)
    -- 显示标题
    eink.rect(10, 10, 190, 45, 0, 0)     -- 标题背景框
    eink.print(50, 35, "eink Demo", 0)

    eink.setFont(eink.font_opposansm12)
    -- 显示操作提示
    eink.print(22, 65, "BOOT:Select PWR:Confirm", 0)

    -- 绘制分隔线
    eink.line(10, 70, 190, 70, 0)

    -- 绘制所有选项框
    for i, opt in ipairs(options) do
        -- 绘制选项框
        if i == selected_index then
            -- 选中状态：实心矩形
            eink.rect(opt.x1, opt.y1, opt.x2, opt.y2, 0, 1)
            eink.print(opt.x1 + 3, opt.y1 + 25, opt.text, 1)  -- 白色文字
        else
            -- 未选中状态：空心矩形
            eink.rect(opt.x1, opt.y1, opt.x2, opt.y2, 0, 0)
            eink.print(opt.x1 + 3, opt.y1 + 25, opt.text, 0)  -- 黑色文字
        end
    end

    -- 绘制底部信息
    eink.print(50, 155, "eink Core Library", 0)
    eink.print(55, 175, "Waveshare 1.54", 0)

    -- 刷新屏幕
    eink.show(0, 0, true)
end

--[[
处理主页按键事件；
根据按键类型执行相应的操作；

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
    
    if key_type == "confirm" or key_type == "pwr_up" then
        -- 确认键：切换到选中的页面
        local opt = options[selected_index]
        switch_page(opt.name)
        return true
    elseif key_type == "boot_up" then
        -- BOOT键：切换选项
        selected_index = selected_index % #options + 1
        return true
    elseif key_type == "back" then
        -- 返回键：当前主页不需要返回功能
        return false
    end
    return false
end

--[[
页面进入时重置选中状态；
重置选中状态为第一个选项；

@api home_page.on_enter()
@summary 重置选中状态
@return nil

@usage
-- 在页面切换时调用
home_page.on_enter()
]] 
function home_page.on_enter()
    selected_index = 1  -- 默认选中第一个
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