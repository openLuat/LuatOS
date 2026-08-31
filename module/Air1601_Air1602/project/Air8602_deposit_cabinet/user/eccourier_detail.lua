--[[
@module  eccourier_detail
@summary 寄存柜管理员功能页面
@version 1.7 (使用消息订阅方式调用串口，回调改为命名函数)
@date    2026.10.16
@author  王城钧
@usage
订阅 "OPEN_EXPRESS_COURIER_DETAIL_WIN" 消息打开管理员功能页面。
支持查看所有箱子状态、按编号开箱。
]]

local win_id = nil
local main_container
local screen_w, screen_h = 1024, 600
local margin = 15
local title_h = math.floor(60 * _G.density_scale)
local density = _G.density_scale or 1
local keyboard = nil
local box_number_textarea = nil
local current_result_modal = nil

-- 键盘提交回调：提交后自动隐藏键盘
local function keyboard_commit_cb(self)
    self:hide()
end

-- 返回按钮回调：关闭当前窗口
local function on_back_click()
    exwin.close(win_id)
end

-- 查看所有箱子状态按钮回调
local function on_view_boxstatus_click()
    sys.publish("OPEN_EXPRESS_BOXSTATUS_WIN")
end

-- 显示错误提示弹窗（2秒后自动关闭）
local function show_toast(text)
    local toast_modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.5
    })

    local toast_content = airui.container({
        parent = toast_modal,
        x = math.floor((screen_w - math.floor(250 * density)) / 2),
        y = math.floor((screen_h - math.floor(100 * density)) / 2),
        w = math.floor(250 * density),
        h = math.floor(100 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density)
    })

    airui.label({
        parent = toast_content,
        x = 0, y = math.floor(30 * density),
        w = math.floor(250 * density),
        h = math.floor(40 * density),
        text = text,
        font_size = math.floor(16 * density),
        color = 0xD32F2F,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 定时销毁提示弹窗（2秒后自动关闭）
    local function destroy_toast_modal()
        toast_modal:destroy()
    end
    sys.timerStart(destroy_toast_modal, 2000)
end

-- 开箱按钮回调：校验箱子编号并发布开柜请求
local function on_open_box_click()
    local box_number = box_number_textarea:get_text()
    if not box_number or box_number == "" then
        show_toast("请输入箱子编号")
        return
    end

    local box_num = tonumber(box_number)
    if not box_num or box_num < 1 or box_num > 30 then
        show_toast("箱子编号必须在1-30之间")
        return
    end

    -- 通过消息发布开柜请求
    log.info("eccourier_detail", "发布开柜请求", box_num)
    sys.publish("OPEN_BOX", box_num)
end

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    title_h = math.floor(60 * _G.density_scale)
    density = _G.density_scale or 1
end

local function show_result_dialog(box_number, success, error_msg)
    -- 销毁之前的弹窗
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end

    local density_local = _G.density_scale or 1

    -- 开箱结果弹窗
    local result_modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.6
    })

    local result_content = airui.container({
        parent = result_modal,
        x = math.floor((screen_w - math.floor(300 * density_local)) / 2),
        y = math.floor((screen_h - math.floor(200 * density_local)) / 2),
        w = math.floor(300 * density_local),
        h = math.floor(200 * density_local),
        color = 0xFFFFFF,
        radius = math.floor(10 * density_local)
    })

    if success then
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(40 * density_local),
            w = math.floor(300 * density_local),
            h = math.floor(30 * density_local),
            text = "柜门已打开",
            font_size = math.floor(20 * density_local),
            color = 0x28A745,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600
        })

        airui.label({
            parent = result_content,
            x = 0, y = math.floor(80 * density_local),
            w = math.floor(300 * density_local),
            h = math.floor(40 * density_local),
            text = "第" .. box_number .. "号箱门已打开",
            font_size = math.floor(14 * density_local),
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(40 * density_local),
            w = math.floor(300 * density_local),
            h = math.floor(30 * density_local),
            text = "开柜失败",
            font_size = math.floor(20 * density_local),
            color = 0xD32F2F,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600
        })

        local error_text = error_msg or "未知错误"
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(80 * density_local),
            w = math.floor(300 * density_local),
            h = math.floor(40 * density_local),
            text = error_text,
            font_size = math.floor(14 * density_local),
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 确定按钮回调：销毁弹窗并清空输入框
    local function on_result_confirm_click()
        result_modal:destroy()
        current_result_modal = nil
        if box_number_textarea then
            box_number_textarea:set_text("")
        end
    end

    airui.button({
        parent = result_content,
        x = math.floor(75 * density_local),
        y = math.floor(130 * density_local),
        w = math.floor(150 * density_local),
        h = math.floor(45 * density_local),
        text = "确定",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density_local),
            font_size = math.floor(16 * density_local),
            font_weight = 600
        },
        on_click = on_result_confirm_click
    })

    current_result_modal = result_modal
end

--[[
开柜结果回调处理
]]
local function on_box_open_result(data)
    log.info("eccourier_detail", "开柜结果", json.encode(data))
    show_result_dialog(data.box_num, data.success, data.error)
end

local function create_ui()
    update_screen_size()

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA
    })

    -- 数字键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = keyboard_commit_cb,
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
        radius = 0,
        shadow = {
            offset_x = 0,
            offset_y = math.floor(3 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.12,
        }
    })

    -- 返回按钮
    airui.button({
        parent = header,
        x = math.floor(15 * density),
        y = math.floor((header_h - 35 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(35 * density),
        text = "返回",
        style = {
            bg_color = 0xFFFFFF, pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2, radius = math.floor(7 * density),
            font_size = math.floor(15 * density), font_weight = 500,
            border_width = 0,
        },
        on_click = on_back_click
    })

    -- 标题
    airui.label({
        parent = header,
        x = 0, y = math.floor((header_h - 28 * density) / 2),
        w = screen_w, h = math.floor(28 * density),
        text = "管理中心",
        color = 0xFFFFFF,
        font_size = math.floor(24 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域（不滚动）
    local content = airui.container({
        parent = main_container,
        x = 0, y = header_h,
        w = screen_w, h = screen_h - header_h,
        color = 0xF8F9FA,
        scroll = false
    })

    -- 查看所有箱子状态按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(30 * density),
        w = screen_w - 2 * margin,
        h = math.floor(50 * density),
        text = "查看所有箱子状态",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600,
        },
        on_click = on_view_boxstatus_click
    })

    -- 箱子编号标签
    airui.label({
        parent = content,
        x = margin, y = math.floor(100 * density),
        w = screen_w - 2 * margin, h = math.floor(25 * density),
        text = "箱子编号",
        color = 0x4A90E2,
        font_size = math.floor(14 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 箱子编号输入框（使用数字键盘）
    box_number_textarea = airui.textarea({
        parent = content,
        x = margin, y = math.floor(130 * density),
        w = screen_w - 2 * margin, h = math.floor(50 * density),
        placeholder = "请输入箱子编号",
        style = {
            bg_color = 0xFFFFFF,
            border_color = 0xDDDDDD,
            border_width = 1,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            text_color = 0x000000,
        },
        keyboard = keyboard,
    })

    -- 开箱按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(200 * density),
        w = screen_w - 2 * margin,
        h = math.floor(50 * density),
        text = "开箱",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600,
        },
        on_click = on_open_box_click
    })

    -- 二维码
    airui.qrcode({
        parent = content,
        x = math.floor((screen_w - math.floor(150 * density)) / 2),
        y = math.floor(280 * density),
        size = math.floor(150 * density),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 二维码说明
    airui.label({
        parent = content,
        x = math.floor((screen_w - math.floor(180 * density)) / 2),
        y = math.floor(450 * density),
        w = math.floor(180 * density),
        h = math.floor(20 * density),
        text = "公众号二维码",
        color = 0x666666,
        font_size = math.floor(12 * density),
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

-- 订阅开柜结果消息
sys.subscribe("BOX_OPEN_RESULT", on_box_open_result)

-- 订阅打开窗口消息
sys.subscribe("OPEN_EXPRESS_COURIER_DETAIL_WIN", open_handler)
