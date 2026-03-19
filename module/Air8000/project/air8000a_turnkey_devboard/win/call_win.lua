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
local contact_list -- 用于显示联系人

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、联系人列表和拨号按钮
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="通话", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 联系人列表（简单展示，实际应读取联系人数据库）
    contact_list = airui.table({
        parent = content, x=10, y=10, w=460, h=200,
        rows = 5, cols = 1,
        col_width = {440},
        border_color = 0xcccccc
    })
    -- 模拟填充联系人
    local contacts = { "张三", "李四", "王五", "赵六", "钱七" }
    for i, name in ipairs(contacts) do
        contact_list:set_cell_text(i-1, 0, name)
    end

    -- 拨号按钮
    airui.button({
        parent = content, x=190, y=220, w=100, h=40,
        text = "拨号",
        on_click = function()
            -- TODO: 获取选中联系人并拨号
            log.info("call", "拨号")
        end
    })
end

--[[
窗口创建回调

@function call_win_on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并初始化联系人列表（TODO）
]]
function on_create()
    
    create_ui()
    -- TODO: 初始化联系人列表，订阅通话状态等
end

--[[
窗口销毁回调

@function call_win_on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，释放资源
]]
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 取消订阅
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 刷新联系人
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 暂停可能的活动
end

-- 订阅打开通话页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_CALL_WIN", open_handler)