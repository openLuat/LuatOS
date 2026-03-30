--[[
@module  call_win
@summary 通话页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为通话功能页面，显示联系人列表并提供拨号功能。
订阅"OPEN_CALL_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local contact_list

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=800, h=480, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=800, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 500, h = 40, align = airui.TEXT_ALIGN_CENTER, text="通话", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=800, h=420, color=0xF3F4F6 })

    contact_list = airui.table({
        parent = content, x=20, y=20, w=760, h=300,
        rows = 5, cols = 1,
        col_width = {740},
        border_color = 0xcccccc
    })
    local contacts = { "张三", "李四", "王五", "赵六", "钱七" }
    for i, name in ipairs(contacts) do
        contact_list:set_cell_text(i-1, 0, name)
    end

    airui.button({
        parent = content, x=340, y=340, w=120, h=50,
        text = "拨号",
        font_size = 20,
        on_click = function()
            log.info("call", "拨号")
        end
    })
end

function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_CALL_WIN", open_handler)