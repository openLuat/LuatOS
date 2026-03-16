-- 通话页面

local win_id = nil
local main_container, content
local contact_list -- 用于显示联系人

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn = airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5, text = "返回",
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="通话", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

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

function call_win_on_create()
    
    create_ui()
    -- TODO: 初始化联系人列表，订阅通话状态等
end

function call_win_on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 取消订阅
end

function call_win_on_get_focus()
    -- 刷新联系人
end

function call_win_on_lose_focus()
    -- 暂停可能的活动
end

local function open_handler()
    win_id = exwin.open({
        on_create = call_win_on_create,
        on_destroy = call_win_on_destroy,
        on_get_focus = call_win_on_get_focus,
        on_lose_focus = call_win_on_lose_focus,
    })
end
sys.subscribe("OPEN_CALL_WIN", open_handler)