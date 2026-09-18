--[[
@module  ecrecv
@summary 寄存柜取件窗口模块
@version 8.8 (添加串口开柜功能，回调改为命名函数)
@date    2026.10.16
@author  王城钧
@usage
订阅 "OPEN_EXPRESS_RECEIVE_WIN" 消息打开取件窗口，输入取件码后自动开柜。
订阅 "BOX_OPEN_RESULT" 消息处理开柜结果弹窗。
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local keyboard = nil
local pickup_code_textarea = nil
local current_result_modal = nil

-- 键盘提交回调：提交后自动隐藏键盘
local function keyboard_commit_cb(self)
    self:hide()
end

-- 返回按钮回调：关闭取件窗口
local function on_back_click()
    exwin.close(win_id)
end

-- 创建柜门已打开的弹窗
local function create_door_open_dialog()
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.6
    })

    local modal_content = airui.container({
        parent = modal,
        x = math.floor((screen_w - 300) / 2),
        y = math.floor((screen_h - 200) / 2),
        w = 300,
        h = 200,
        color = 0xFFFFFF,
        radius = 10,
    })

    airui.label({
        parent = modal_content,
        x = 0, y = 30,
        w = 300,
        h = 30,
        text = "柜门已打开",
        font_size = 20,
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600
    })

    airui.label({
        parent = modal_content,
        x = 20,
        y = 70,
        w = 260,
        h = 40,
        text = "请及时取走您的物品",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 确定按钮回调：销毁弹窗并关闭取件窗口
    local function on_confirm_click()
        modal:destroy()
        exwin.close(win_id)
    end

    airui.button({
        parent = modal_content,
        x = 75,
        y = 130,
        w = 150,
        h = 45,
        text = "确定",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = 22,
            font_size = 16,
            font_weight = 600,
        },
        on_click = on_confirm_click
    })

    return modal
end

-- 显示错误弹窗
local function show_error_dialog(message)
    local density = _G.density_scale or 1
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.5
    })

    local modal_content = airui.container({
        parent = modal,
        x = math.floor((screen_w - math.floor(250 * density)) / 2),
        y = math.floor((screen_h - math.floor(100 * density)) / 2),
        w = math.floor(250 * density),
        h = math.floor(100 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density)
    })

    airui.label({
        parent = modal_content,
        x = 0, y = math.floor(30 * density),
        w = math.floor(250 * density),
        h = math.floor(40 * density),
        text = message,
        font_size = math.floor(16 * density),
        color = 0xD32F2F,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 定时销毁弹窗（2秒后自动关闭）
    local function destroy_error_modal()
        modal:destroy()
    end
    sys.timerStart(destroy_error_modal, 2000)
end

-- 显示结果弹窗
local function show_result_dialog(box_number, success, error_msg)
    -- 销毁之前的弹窗
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end

    local density = _G.density_scale or 1

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
        x = math.floor((screen_w - math.floor(300 * density)) / 2),
        y = math.floor((screen_h - math.floor(200 * density)) / 2),
        w = math.floor(300 * density),
        h = math.floor(200 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density)
    })

    if success then
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(40 * density),
            w = math.floor(300 * density),
            h = math.floor(30 * density),
            text = "柜门已打开",
            font_size = math.floor(20 * density),
            color = 0x28A745,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600
        })

        airui.label({
            parent = result_content,
            x = 0, y = math.floor(80 * density),
            w = math.floor(300 * density),
            h = math.floor(40 * density),
            text = "第" .. box_number .. "号箱门已打开",
            font_size = math.floor(14 * density),
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(40 * density),
            w = math.floor(300 * density),
            h = math.floor(30 * density),
            text = "取件失败",
            font_size = math.floor(20 * density),
            color = 0xD32F2F,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600
        })

        local error_text = error_msg or "未知错误"
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(80 * density),
            w = math.floor(300 * density),
            h = math.floor(40 * density),
            text = error_text,
            font_size = math.floor(14 * density),
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 确定按钮回调：销毁弹窗并清空输入框
    local function on_result_confirm_click()
        result_modal:destroy()
        current_result_modal = nil
        if pickup_code_textarea then
            pickup_code_textarea:set_text("")
        end
    end

    airui.button({
        parent = result_content,
        x = math.floor(75 * density),
        y = math.floor(130 * density),
        w = math.floor(150 * density),
        h = math.floor(45 * density),
        text = "确定",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
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
    log.info("ecrecv", "开柜结果", json.encode(data))
    show_result_dialog(data.box_num, data.success, data.error)

    -- 如果取件成功，删除对应的取件码记录
    if data.success then
        -- 需要根据箱子号找到对应的取件码
        -- 遍历取件码表，找到匹配的箱子号
        local aircloud = require "aircloud"
        for code, box_num in pairs(aircloud.pickup_code_map or {}) do
            if box_num == data.box_num then
                aircloud.delete_pickup_code(code)
                log.info("ecrecv", "已删除取件码记录: " .. code)
                break
            end
        end
    end
end

-- 取件按钮回调：校验取件码并发布开柜请求
local function on_pickup_click()
    local pickup_code = pickup_code_textarea:get_text()

    -- 验证取件码格式
    if not pickup_code or pickup_code == "" then
        show_error_dialog("请输入取件码")
        return
    end

    -- 验证取件码长度为6位
    if #pickup_code ~= 6 then
        show_error_dialog("取件码必须为6位")
        return
    end

    -- 根据取件码获取对应的柜子号
    local aircloud = require "aircloud"
    log.debug("ecrecv", "输入的取件码: " .. pickup_code .. ", 类型: " .. type(pickup_code))
    log.debug("ecrecv", "内存中存储的取件码: " .. json.encode(aircloud.pickup_code_map))

    local box_num = aircloud.get_box_num_by_pickup_code(pickup_code)

    if box_num then
        -- 通过消息发布开柜请求
        log.info("ecrecv", "发布开柜请求", box_num)
        sys.publish("OPEN_BOX", box_num)
    else
        log.warn("ecrecv", "未找到取件码对应的柜子号: " .. pickup_code)
        local stored_value = fskv.get("pickup_code_" .. pickup_code)
        log.debug("ecrecv", "fskv 中查找: pickup_code_" .. pickup_code .. " = " .. (stored_value or "nil"))
        show_error_dialog("无效的取件码")
    end
end

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

local function create_ui()
    update_screen_size()
    local density = _G.density_scale or 1

    -- 主容器 - 深蓝背景（与首页 ecabinet 一致）
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x08193A
    })

    -- 键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = keyboard_commit_cb,
    })

    -- 标题栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
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
            bg_color = 0xFFFFFF,
            pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = on_back_click
    })

    -- 标题
    airui.label({
        parent = header,
        x = 0, y = math.floor((header_h - 28 * density) / 2),
        w = screen_w, h = math.floor(28 * density),
        text = "取件",
        color = 0xFFFFFF,
        font_size = math.floor(24 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域背景
    local content_bg = airui.container({
        parent = main_container,
        x = math.floor(20 * density),
        y = header_h + math.floor(20 * density),
        w = screen_w - math.floor(40 * density),
        h = screen_h - header_h - math.floor(100 * density),
        color = 0x0E3B5C,
        radius = math.floor(12 * density),
    })

    -- 取件码标题
    airui.label({
        parent = main_container,
        text = "取件码",
        x = math.floor(40 * density),
        y = header_h + math.floor(40 * density),
        w = screen_w - math.floor(80 * density),
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x6FB5F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    -- 取件码输入框
    pickup_code_textarea = airui.textarea({
        parent = main_container,
        x = math.floor(40 * density),
        y = header_h + math.floor(70 * density),
        w = screen_w - math.floor(80 * density),
        h = math.floor(50 * density),
        placeholder = "请输入6位取件码",
        style = {
            bg_color = 0xF5F7FA,
            border_color = 0xE0E0E0,
            border_width = 1,
            radius = math.floor(8 * density),
            font_size = math.floor(16 * density),
            text_color = 0x333333,
        },
        keyboard = keyboard,
    })

    -- 二维码标题
    airui.label({
        parent = main_container,
        text = "扫描二维码",
        x = math.floor(40 * density),
        y = header_h + math.floor(140 * density),
        w = screen_w - math.floor(80 * density),
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x6FB5F5,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 二维码 - 直接添加到main_container
    airui.qrcode({
        parent = main_container,
        x = math.floor((screen_w - math.floor(150 * density)) / 2),
        y = header_h + math.floor(170 * density),
        size = math.floor(150 * density),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 二维码下方文字
    airui.label({
        parent = main_container,
        text = "关注公众号获取更多服务",
        x = 0,
        y = header_h + math.floor(330 * density),
        w = screen_w,
        h = math.floor(20 * density),
        font_size = math.floor(13 * density),
        color = 0x9EB3CC,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 400,
    })

    -- 确定按钮
    airui.button({
        parent = main_container,
        x = math.floor(20 * density),
        y = screen_h - math.floor(60 * density),
        w = math.floor((screen_w - math.floor(60 * density)) / 2),
        h = math.floor(50 * density),
        text = "取件",
        style = {
            bg_color = 0x4A90E2,
            pressed_bg_color = 0x3A80D2,
            text_color = 0xFFFFFF,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = on_pickup_click
    })

    -- 返回按钮
    airui.button({
        parent = main_container,
        x = math.floor((screen_w - math.floor(60 * density)) / 2) + math.floor(40 * density),
        y = screen_h - math.floor(60 * density),
        w = math.floor((screen_w - math.floor(60 * density)) / 2),
        h = math.floor(50 * density),
        text = "返回",
        style = {
            bg_color = 0xF0F0F0,
            pressed_bg_color = 0xE0E0E0,
            text_color = 0x666666,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = on_back_click
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
sys.subscribe("OPEN_EXPRESS_RECEIVE_WIN", open_handler)
