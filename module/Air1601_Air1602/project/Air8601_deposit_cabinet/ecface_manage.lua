--[[
@module  ecface_manage
@summary 管理员人脸管理界面
@version 1.0
@date    2026.08.14
@usage
管理员通过"管理中心 → 人脸管理"进入本页面，支持：
- 录入人脸（输入用户名称后刷脸注册）
- 查看已注册用户列表（含绑定柜号）
- 删除已注册用户（同步删除人脸↔柜号绑定）
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local keyboard = nil
local name_textarea = nil
local list_container = nil   -- 用户列表容器（动态重建）
local current_result_modal = nil
local current_users = {}     -- 当前列表数据缓存

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

-- 显示结果弹窗
local function show_result_dialog(success, title_text, content_text)
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end

    local density = _G.density_scale or 1

    local result_modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.6
    })

    local result_content = airui.container({
        parent = result_modal,
        x = math.floor((screen_w - math.floor(340 * density)) / 2),
        y = math.floor((screen_h - math.floor(220 * density)) / 2),
        w = math.floor(340 * density),
        h = math.floor(220 * density),
        color = 0x0F2547,
        radius = math.floor(10 * density)
    })

    airui.label({
        parent = result_content,
        x = 0, y = math.floor(30 * density),
        w = math.floor(340 * density),
        h = math.floor(30 * density),
        text = title_text or "",
        font_size = math.floor(20 * density),
        color = success and 0x28A745 or 0xD32F2F,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600
    })

    airui.label({
        parent = result_content,
        x = math.floor(20 * density),
        y = math.floor(70 * density),
        w = math.floor(300 * density),
        h = math.floor(80 * density),
        text = content_text or "",
        font_size = math.floor(14 * density),
        color = 0xB8C6D9,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.button({
        parent = result_content,
        x = math.floor(95 * density),
        y = math.floor(160 * density),
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
        on_click = function()
            result_modal:destroy()
            current_result_modal = nil
        end
    })

    current_result_modal = result_modal
end

-- 重建用户列表（销毁旧容器后重新创建）
local function rebuild_list(users)
    -- 防御：窗口未打开时不渲染（防止消息串扰时把列表画到其他窗口）
    if not main_container then
        log.warn("ecface_manage", "窗口未打开，跳过列表刷新")
        return
    end
    -- 销毁旧列表容器
    if list_container then
        list_container:destroy()
        list_container = nil
    end

    local density = _G.density_scale or 1
    local list_y = math.floor(210 * density)
    local list_h = screen_h - list_y - math.floor(20 * density)

    list_container = airui.container({
        parent = main_container,
        x = math.floor(15 * density),
        y = list_y,
        w = screen_w - math.floor(30 * density),
        h = list_h,
        color = 0x0F2547,
        radius = math.floor(8 * density),
        scroll = true,
    })

    if not users or #users == 0 then
        airui.label({
            parent = list_container,
            text = "暂无已注册用户",
            x = 0, y = math.floor(20 * density),
            w = screen_w - math.floor(30 * density),
            h = math.floor(30 * density),
            font_size = math.floor(14 * density),
            color = 0x999999,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    -- 表头
    airui.label({
        parent = list_container,
        text = "用户ID",
        x = math.floor(10 * density), y = math.floor(10 * density),
        w = math.floor(100 * density), h = math.floor(25 * density),
        font_size = math.floor(13 * density),
        color = 0x3FA9F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })
    airui.label({
        parent = list_container,
        text = "名称",
        x = math.floor(120 * density), y = math.floor(10 * density),
        w = math.floor(160 * density), h = math.floor(25 * density),
        font_size = math.floor(13 * density),
        color = 0x3FA9F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })
    airui.label({
        parent = list_container,
        text = "绑定柜号",
        x = math.floor(290 * density), y = math.floor(10 * density),
        w = math.floor(100 * density), h = math.floor(25 * density),
        font_size = math.floor(13 * density),
        color = 0x3FA9F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    -- 用户行
    local row_h = math.floor(40 * density)
    for i, user in ipairs(users) do
        local row_y = math.floor(40 * density) + (i - 1) * row_h

        -- 行背景（隔行变色）
        airui.container({
            parent = list_container,
            x = math.floor(5 * density),
            y = row_y,
            w = screen_w - math.floor(40 * density),
            h = row_h - math.floor(4 * density),
            color = (i % 2 == 0) and 0x0A2240 or 0x0F2547,
            radius = math.floor(4 * density),
        })

        airui.label({
            parent = list_container,
            text = tostring(user.user_id or ""),
            x = math.floor(10 * density), y = row_y + math.floor(5 * density),
            w = math.floor(100 * density), h = math.floor(25 * density),
            font_size = math.floor(13 * density),
            color = 0xEAF2FF,
            align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = list_container,
            text = user.name or "",
            x = math.floor(120 * density), y = row_y + math.floor(5 * density),
            w = math.floor(160 * density), h = math.floor(25 * density),
            font_size = math.floor(13 * density),
            color = 0xEAF2FF,
            align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = list_container,
            text = user.box_num and ("第" .. user.box_num .. "号") or "未绑定",
            x = math.floor(290 * density), y = row_y + math.floor(5 * density),
            w = math.floor(100 * density), h = math.floor(25 * density),
            font_size = math.floor(13 * density),
            color = user.box_num and 0x28A745 or 0x999999,
            align = airui.TEXT_ALIGN_LEFT,
        })

        -- 删除按钮
        airui.button({
            parent = list_container,
            x = screen_w - math.floor(120 * density),
            y = row_y + math.floor(4 * density),
            w = math.floor(80 * density),
            h = math.floor(32 * density),
            text = "删除",
            style = {
                bg_color = 0xE74C3C,
                pressed_bg_color = 0xC0392B,
                text_color = 0xFFFFFF,
                radius = math.floor(4 * density),
                font_size = math.floor(12 * density),
                font_weight = 500,
            },
            on_click = (function(uid)
                return function()
                    log.info("ecface_manage", "删除用户", uid)
                    sys.publish("FACE_DELETE_REQ", {user_id = uid})
                end
            end)(user.user_id)
        })
    end
end

-- 创建界面
local function create_ui()
    update_screen_size()
    local density = _G.density_scale or 1

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x0A1E3A
    })

    -- 键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 顶部导航栏
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
            bg_color = 0x0F2547,
            pressed_bg_color = 0x1F3A60,
            text_color = 0xFFFFFF,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })

    -- 标题
    airui.label({
        parent = header,
        text = "人脸管理",
        x = 0, y = math.floor((header_h - 28 * density) / 2),
        w = screen_w, h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 名称输入框（录入用户名称）
    airui.label({
        parent = main_container,
        text = "用户名称",
        x = math.floor(20 * density),
        y = math.floor(80 * density),
        w = math.floor(100 * density),
        h = math.floor(25 * density),
        font_size = math.floor(14 * density),
        color = 0x3FA9F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    name_textarea = airui.textarea({
        parent = main_container,
        x = math.floor(120 * density),
        y = math.floor(75 * density),
        w = math.floor(380 * density),
        h = math.floor(40 * density),
        placeholder = "请输入用户名称（如：张三）",
        style = {
            bg_color = 0x0A2240,
            border_color = 0x1F3A60,
            border_width = 1,
            radius = math.floor(5 * density),
            font_size = math.floor(15 * density),
            text_color = 0xFFFFFF,
        },
        keyboard = keyboard,
    })

    -- 录入人脸按钮
    airui.button({
        parent = main_container,
        x = math.floor(520 * density),
        y = math.floor(75 * density),
        w = math.floor(200 * density),
        h = math.floor(40 * density),
        text = "录入人脸",
        style = {
            bg_color = 0x28A745,
            pressed_bg_color = 0x218838,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = function()
            local name = name_textarea:get_text()
            if not name or name == "" then
                show_result_dialog(false, "提示", "请输入用户名称")
                return
            end
            log.info("ecface_manage", "发布人脸注册请求，name=" .. name)
            -- 管理员录入普通用户
            sys.publish("FACE_REGISTER_REQ", {name = name, admin = false})
        end
    })

    -- 刷新列表按钮
    airui.button({
        parent = main_container,
        x = math.floor(20 * density),
        y = math.floor(135 * density),
        w = math.floor(200 * density),
        h = math.floor(40 * density),
        text = "刷新列表",
        style = {
            bg_color = 0x4A90E2,
            pressed_bg_color = 0x3A80D2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = function()
            log.info("ecface_manage", "发布人脸列表请求")
            sys.publish("FACE_LIST_REQ")
        end
    })

    -- 列表标题
    airui.label({
        parent = main_container,
        text = "已注册用户列表",
        x = math.floor(20 * density),
        y = math.floor(185 * density),
        w = math.floor(200 * density),
        h = math.floor(25 * density),
        font_size = math.floor(14 * density),
        color = 0x3FA9F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })
end

-- 处理注册结果
local function on_register_result(data)
    -- ⚠️ 仅当人脸管理窗口为活动窗口时才处理！
    -- 否则刷脸存件/取件等场景触发人脸注册时，本模块会误弹窗/误刷新列表，干扰其他界面。
    if not exwin.is_active(win_id) then return end
    if data.success then
        show_result_dialog(true, "录入成功", "用户ID: " .. tostring(data.user_id) .. "\n名称: " .. tostring(data.name))
        -- 注册成功后刷新列表
        sys.publish("FACE_LIST_REQ")
    else
        show_result_dialog(false, "录入失败", data.error or "请重试")
    end
end

-- 处理列表结果
local function on_list_result(data)
    if not exwin.is_active(win_id) then return end
    if data.success then
        current_users = data.users or {}
        rebuild_list(current_users)
    else
        show_result_dialog(false, "查询失败", data.error or "未知错误")
    end
end

-- 处理删除结果
local function on_delete_result(data)
    if not exwin.is_active(win_id) then return end
    if data.success then
        show_result_dialog(true, "删除成功", "用户 " .. tostring(data.user_id) .. " 已删除")
        -- 删除成功后刷新列表
        sys.publish("FACE_LIST_REQ")
    else
        show_result_dialog(false, "删除失败", data.error or "未知错误")
    end
end

-- 窗口生命周期
local function on_create()
    -- pcall 保护：create_ui 异常时避免窗口异常关闭
    local ok, err = pcall(create_ui)
    if not ok then
        log.error("ecface_manage", "创建界面失败:", err)
        return
    end
    -- ⚠️ 禁止在此重新操作 GPIO38（背光）！
    -- GPIO38 同时是 I2C1 的 SDA（触摸屏 GT911 所在总线），重新 gpio.setup(38) 会把
    -- SDA 从 I2C 复用功能切回普通 GPIO 输出，导致触摸屏 i2c_failed 无应答/传输超时、无法触摸。
    -- 背光已在 hardware.init_screen 中上电时设置，之后由 I2C 上拉维持，无需重复设置。
    -- 打开窗口后自动刷新列表
    sys.publish("FACE_LIST_REQ")
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
    list_container = nil
    current_users = {}
    win_id = nil
end

local function open_handler()
    -- 防止重复打开（与其他窗口模块保持一致）
    if exwin.is_active(win_id) then
        log.warn("ecface_manage", "人脸管理窗口已打开，忽略重复请求")
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

-- 订阅消息
sys.subscribe("OPEN_FACE_MANAGE_WIN", open_handler)
sys.subscribe("FACE_REGISTER_RESULT", on_register_result)
sys.subscribe("FACE_LIST_RESULT", on_list_result)
sys.subscribe("FACE_DELETE_RESULT", on_delete_result)

log.info("ecface_manage", "人脸管理界面模块加载完成")
