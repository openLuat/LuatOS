--[[
@module  db_test_win
@summary 数据库CRUD测试窗口 320x480（exwin 架构）
@version 1.0.1
@date    2026.05.11
@author  合宙
]]


local W, H = 320, 480

local COLOR_BG = 0xF5F5F5
local COLOR_CARD = 0xFFFFFF
local COLOR_PRIMARY = 0x007AFF
local COLOR_DANGER = 0xE63946
local COLOR_ACCENT = 0xFF9800
local COLOR_TEXT = 0x333333
local COLOR_HINT = 0x999999

local wid = nil
local main_container = nil

-- 信息显示 label 引用
local lb_user = nil    -- 用户名
local lb_devid = nil   -- 设备ID

-- 数据展示 label 引用
local lb_op = nil      -- 当前操作
local lb_params = nil  -- 操作参数
local lb_status = nil  -- 响应状态
local lb_data = nil    -- 返回数据

----------------------------------------------------------------------
-- 登录状态检查
----------------------------------------------------------------------
local function check_login()
    local info = exapp.iot_get_account_info()
    return info and not info.is_guest
end

local function get_nickname()
    local info = exapp.iot_get_account_info()
    return info and info.nickname or "测试用户"
end

local function get_account()
    local info = exapp.iot_get_account_info()
    return info and info.account or "guest_000000"
end

-- 获取设备ID（按芯片型号）
local function get_device_id()
    local model = rtos.bsp()
    if model:find("Air1601") or model:find("Air1602") then
        return tostring(mcu.unique_id())
    elseif model:find("Air8101") or model:find("Air6205") or model:find("Air8000") then
        return tostring(wlan.getMac())
    elseif model:find("Air780E") then
        return tostring(mobile.imei())
    else
        return "PC"
    end
end

-- 刷新信息显示
local function refresh_info()
    if lb_user then
        lb_user:set_text("用户: " .. get_nickname() .. " (" .. get_account() .. ")")
    end
    if lb_devid then
        lb_devid:set_text("设备ID: " .. get_device_id())
    end
end

-- 刷新数据展示面板
local function show_data(op, params, status, data)
    if lb_op then
        lb_op:set_text("操作: " .. (op or "--"))
    end
    if lb_params then
        lb_params:set_text("参数: " .. (params or "--"))
    end
    if lb_status then
        lb_status:set_text("状态: " .. (status or "等待中"))
        lb_status:set_color(status == "成功" and COLOR_PRIMARY or COLOR_DANGER)
    end
    if lb_data and data then
        lb_data:set_text(data)
    end
end

----------------------------------------------------------------------
-- DB 操作（日志输出结果）
----------------------------------------------------------------------
local function do_add()
    if not check_login() then
        log.warn("db", "请先登录IOT账号")
        return
    end
    exapp.add_record({
        cls = 99,
        uni_key = "test_" .. os.time(),
        i1 = math.random(1, 100),
        s1 = get_nickname(),
        d1 = os.time()
    })
    log.info("db", "add_record 已调用 -> 查看日志中的 [db] 标签")
    show_data("add_record", "cls=99, i1=" .. math.random(1,100) .. ", s1=" .. get_nickname(), "已发送", "等待服务器响应...")
end

local function do_list()
    if not check_login() then
        log.warn("db", "请先登录IOT账号")
        return
    end
    exapp.list_record({cls = 99, sort = "i1", desc = true, size = 5})
    log.info("db", "list_record 已调用 -> 查看日志中的 [db] 标签")
    show_data("list_record", "cls=99, sort=i1, desc=true, size=5", "已发送", "查看日志 [db] 标签")
end

local function do_delete()
    if not check_login() then
        log.warn("db", "请先登录IOT账号")
        return
    end
    local uk = "test_" .. os.time()
    exapp.add_record({cls = 99, uni_key = uk, i1 = 1, s1 = "待删除"})
    exapp.delete_record({cls = 99, uni_key = uk})
    log.info("db", "delete_record 已调用 -> 查看日志中的 [db] 标签")
    show_data("delete_record", "cls=99, uni_key=" .. uk, "已发送", "add后立即delete")
end

local function do_flow()
    if not check_login() then
        log.warn("db", "请先登录IOT账号")
        return
    end
    local nick = get_nickname()
    local uk = "flow_" .. os.time()
    exapp.add_record({cls = 99, uni_key = uk, i1 = 50, s1 = nick})
    exapp.list_record({cls = 99, size = 3})
    exapp.delete_record({cls = 99, uni_key = uk})
    log.info("db", "完整流程已调用：add -> list -> delete")
    show_data("完整流程", "add->list->delete", "已发送", "uni_key=" .. uk)
end

----------------------------------------------------------------------
-- UI 构建
----------------------------------------------------------------------
local function build_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = W, h = H,
        color = COLOR_BG
    })

    -- 标题
    airui.label({
        parent = main_container, x = 0, y = 16, w = W, h = 36,
        text = "数据库 CRUD 测试",
        font_size = 22,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 信息显示区
    local info_y = 56
    local info_h = 18
    local info_gap = 4

    lb_user = airui.label({
        parent = main_container, x = 16, y = info_y, w = W - 32, h = info_h,
        text = "用户: --",
        font_size = 13,
        color = COLOR_TEXT
    })
    info_y = info_y + info_h + info_gap

    lb_devid = airui.label({
        parent = main_container, x = 16, y = info_y, w = W - 32, h = info_h,
        text = "设备ID: --",
        font_size = 13,
        color = COLOR_TEXT
    })

    -- 按钮参数
    local bx = 20
    local bw = W - 40
    local bh = 40
    local bg = 8
    local by = info_y + info_h + 10

    airui.button({
        parent = main_container, x = bx, y = by, w = bw, h = bh,
        text = "添加数据 (add_record)",
        font_size = 16,
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = 0x0056B3, text_color = 0xFFFFFF, radius = 8 },
        on_click = do_add
    })
    by = by + bh + bg

    airui.button({
        parent = main_container, x = bx, y = by, w = bw, h = bh,
        text = "查询数据 (list_record)",
        font_size = 16,
        style = { bg_color = COLOR_ACCENT, pressed_bg_color = 0xCC7A00, text_color = 0xFFFFFF, radius = 8 },
        on_click = do_list
    })
    by = by + bh + bg

    airui.button({
        parent = main_container, x = bx, y = by, w = bw, h = bh,
        text = "删除数据 (delete_record)",
        font_size = 16,
        style = { bg_color = COLOR_DANGER, pressed_bg_color = 0xCC2D3A, text_color = 0xFFFFFF, radius = 8 },
        on_click = do_delete
    })
    by = by + bh + bg + 16

    airui.button({
        parent = main_container, x = bx, y = by, w = bw, h = bh + 8,
        text = "完整流程测试\n(add -> list -> delete)",
        font_size = 15,
        style = { bg_color = COLOR_TEXT, pressed_bg_color = 0x222222, text_color = 0xFFFFFF, radius = 8 },
        on_click = do_flow
    })
    by = by + bh + 8 + bg + 8

    -- 数据展示面板
    local panel = airui.container({
        parent = main_container, x = bx, y = by, w = bw, h = 72,
        color = COLOR_CARD, radius = 10, border_width = 1, border_color = 0xE0E0E0
    })
    local py = 8
    local ph = 18
    local pg = 3

    lb_op = airui.label({
        parent = panel, x = 10, y = py, w = bw - 20, h = ph,
        text = "操作: --",
        font_size = 13, color = COLOR_TEXT
    })
    py = py + ph + pg

    lb_params = airui.label({
        parent = panel, x = 10, y = py, w = bw - 20, h = ph,
        text = "参数: --",
        font_size = 13, color = COLOR_TEXT
    })
    py = py + ph + pg

    lb_status = airui.label({
        parent = panel, x = 10, y = py, w = bw - 20, h = ph,
        text = "状态: 等待操作",
        font_size = 13, color = COLOR_HINT
    })
    py = py + ph + pg

    lb_data = airui.label({
        parent = panel, x = 10, y = py, w = bw - 20, h = ph,
        text = "点击上方按钮开始测试",
        font_size = 12, color = COLOR_HINT
    })

    -- 关闭按钮（紧跟数据面板）
    by = by + 72 + bg
    local close_y = by
    airui.button({
        parent = main_container, x = bx, y = close_y, w = bw, h = bh,
        text = "关  闭",
        font_size = 16,
        style = { bg_color = 0xE0E0E0, pressed_bg_color = 0xCCCCCC, text_color = COLOR_TEXT, radius = 8 },
        on_click = function()
            exwin.close(wid)
        end
    })
end

----------------------------------------------------------------------
-- 窗口生命周期
----------------------------------------------------------------------
-- DB 结果回调
local function on_db_result(endpoint, success, info)
    local op_name = endpoint
    if success then
        show_data(op_name, "--", "成功", tostring(info or ""))
    else
        show_data(op_name, "--", "失败", tostring(info or ""))
    end
end

local function on_create()
    build_ui()
    refresh_info()
    show_data("--", "--", "等待操作", "点击上方按钮开始测试")
    sys.subscribe("DB_RESULT", on_db_result)
end

local function on_destroy()
    sys.unsubscribe("DB_RESULT", on_db_result)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function on_get_focus()
    -- 重新获取焦点时不刷新，保持状态
end

local function on_lose_focus()
    -- 失去焦点时不做处理
end

local function db_test_win()
    wid = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_DB_TEST_WIN", db_test_win)