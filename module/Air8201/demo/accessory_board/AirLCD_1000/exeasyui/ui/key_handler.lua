--[[
@module  key_handler
@summary 按键处理模块
@version 1.0
@date    2025.12.3
@author  江访
@usage
本文件为按键处理功能模块，核心业务逻辑为：
1、管理页面可点击区域列表，支持动态区域注册；
2、处理按键事件，实现光标在可点击区域间的切换；
3、提供光标绘制和清除功能，视觉上标记当前焦点；
4、支持模拟点击操作，触发界面元素响应；
5、实现页面切换时的区域列表更新；

本文件的对外接口有8个：
1、key_handler.register_page()：注册页面区域回调函数；
2、key_handler.switch_to_page()：切换到指定页面；
3、key_handler.clear_areas()：清空当前区域列表；
4、key_handler.add_area()：添加可点击区域；
5、key_handler.next_area()：切换到下一个区域；
6、key_handler.simulate_click()：模拟点击当前区域；
7、key_handler.set_visible()：显示/隐藏光标；
8、key_handler.get_current_area()：获取当前区域信息；
]]

local key_handler = {}

-- 模块内部状态
local clickable_areas = {}
local current_area_index = 0
local page_callbacks = {}
local config = {
    cursor_thickness = 2,
    cursor_color = 0xFF0000,
    show_cursor = true,
    last_switch_time = 0
}
local current_drawn_rect = nil


--[[
注册页面区域回调函数；

@api key_handler.register_page(page_name, callback)

@summary 注册页面的可点击区域回调函数

@string
page_name
页面名称标识符，用于后续页面切换时引用；

@function
callback
区域注册回调函数，函数内应调用key_handler.clear_areas()和key_handler.add_area()来定义页面的可点击区域；

@return nil

@usage
key_handler.register_page("home", function()
    key_handler.clear_areas()
    key_handler.add_area(20, 100, 280, 50)  -- 主页按钮1
    key_handler.add_area(20, 170, 280, 50)  -- 主页按钮2
end)
]]
function key_handler.register_page(page_name, callback)
    page_callbacks[page_name] = callback
end

--[[
切换到指定页面并更新区域列表；

@api key_handler.switch_to_page(page_name)

@summary 切换到指定页面

@string
page_name
目标页面名称，必须已通过key_handler.register_page()注册；

@return boolean
切换成功返回true，失败返回false；

@usage
local result = key_handler.switch_to_page("home")
if result then
    log.info("成功切换到主页")
end
]]
function key_handler.switch_to_page(page_name)
    key_handler.clear_cursor()

    if page_callbacks[page_name] then
        page_callbacks[page_name]()
    else
        clickable_areas = {}
    end

    if #clickable_areas > 0 then
        current_area_index = 1
        config.last_switch_time = mcu.ticks()
        key_handler.draw_cursor()
        return true
    else
        current_area_index = 0
        return false
    end
end

-- 清空区域
function key_handler.clear_areas()
    key_handler.clear_cursor()
    clickable_areas = {}
    current_area_index = 0
end

-- 添加区域
function key_handler.add_area(x, y, w, h)
    table.insert(clickable_areas, { x = x, y = y, w = w, h = h })

    if #clickable_areas == 1 and current_area_index == 0 then
        current_area_index = 1
        config.last_switch_time = mcu.ticks()
    end
end

-- 获取当前区域矩形
local function get_current_area_rect()
    if current_area_index < 1 or current_area_index > #clickable_areas then
        return nil
    end

    local area = clickable_areas[current_area_index]
    return {
        x1 = area.x - 3,
        y1 = area.y - 3,
        x2 = area.x + area.w + 3,
        y2 = area.y + area.h + 3
    }
end

-- 获取当前区域中心
local function get_current_area_center()
    if current_area_index < 1 or current_area_index > #clickable_areas then
        return 160, 240
    end

    local area = clickable_areas[current_area_index]
    local center_x = area.x + math.floor(area.w / 2)
    local center_y = area.y + math.floor(area.h / 2)

    return center_x, center_y
end

-- 清除光标
function key_handler.clear_cursor()
    if current_drawn_rect then
        lcd.setColor(0xFFFFFF, 0xFFFFFF)
        local r = current_drawn_rect
        for i = 1, config.cursor_thickness do
            local offset = i - 1
            lcd.drawRectangle(
                r.x1 + offset,
                r.y1 + offset,
                r.x2 - offset,
                r.y2 - offset
            )
        end
        current_drawn_rect = nil
    end
end

-- 绘制光标
function key_handler.draw_cursor()
    if not config.show_cursor then
        return
    end
    if current_area_index < 1 or current_area_index > #clickable_areas then
        return
    end

    key_handler.clear_cursor()

    local rect = get_current_area_rect()
    if not rect then return end

    current_drawn_rect = rect
    lcd.setColor(0xFFFFFF, config.cursor_color)

    local thickness = config.cursor_thickness
    for i = 1, thickness do
        local offset = i - 1
        lcd.drawRectangle(
            rect.x1 + offset,
            rect.y1 + offset,
            rect.x2 - offset,
            rect.y2 - offset
        )
    end

    config.last_switch_time = mcu.ticks()
end

--[[
切换到下一个可点击区域；

@api key_handler.next_area()

@summary 在可点击区域间循环切换焦点

@return boolean
切换成功返回true，失败返回false；

@usage
local result = key_handler.next_area()
if result then
    log.info("已切换到下一个区域")
end
]]
function key_handler.next_area()
    if #clickable_areas == 0 then
        return false
    end

    local old_index = current_area_index
    current_area_index = current_area_index + 1
    if current_area_index > #clickable_areas then
        current_area_index = 1
    end

    key_handler.draw_cursor()
    return true
end

--[[
模拟点击当前选中区域；

@api key_handler.simulate_click()

@summary 模拟点击当前焦点区域

@return number, number
返回点击的坐标X, Y；如果当前没有选中区域，返回0, 0；

@usage
local x, y = key_handler.simulate_click()
log.info("点击坐标:", x, ",", y)
]]
function key_handler.simulate_click()
    if #clickable_areas == 0 or current_area_index == 0 then
        return 0, 0
    end

    local center_x, center_y = get_current_area_center()
    -- exeasyui必须先按下再单击
    sys.publish("BASE_TOUCH_EVENT", "TOUCH_DOWN", center_x, center_y)
    sys.publish("BASE_TOUCH_EVENT", "SINGLE_TAP", center_x, center_y)

    return center_x, center_y
end

--[[
显示或隐藏光标；

@api key_handler.set_visible(visible)

@summary 设置光标可见性

@boolean
visible
true表示显示光标，false表示隐藏光标；

@return nil

@usage
key_handler.set_visible(true)   -- 显示光标
key_handler.set_visible(false)  -- 隐藏光标
]]
function key_handler.set_visible(visible)
    config.show_cursor = visible

    if not visible then
        key_handler.clear_cursor()
    else
        key_handler.draw_cursor()
    end
end

--[[
获取当前选中区域信息；

@api key_handler.get_current_area()

@summary 获取当前焦点区域的详细信息

@return table or nil
区域信息表，包含以下字段：
- index: number 当前区域索引
- total: number 总区域数
- x: number 区域X坐标
- y: number 区域Y坐标
- w: number 区域宽度
- h: number 区域高度
- center_x: number 中心点X坐标
- center_y: number 中心点Y坐标
如果没有选中区域，返回nil；

@usage
local area = key_handler.get_current_area()
if area then
    log.info("当前区域:", area.index, "/", area.total)
end
]]
function key_handler.get_current_area()
    if current_area_index < 1 or current_area_index > #clickable_areas then
        return nil
    end

    local area = clickable_areas[current_area_index]
    local center_x, center_y = get_current_area_center()

    return {
        index = current_area_index,
        total = #clickable_areas,
        x = area.x,
        y = area.y,
        w = area.w,
        h = area.h,
        center_x = center_x,
        center_y = center_y
    }
end

return key_handler