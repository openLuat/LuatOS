--[[
@module  settings_face_win
@summary 人脸识别子页面（实时预览 / 人脸录入 / 人脸验证 / 清空用户）
@version 2.0
@date    2026.10.23
@author  江访
@usage
订阅: OPEN_FACE_WIN
发布: FACE_STATUS_REQ / FACE_REGISTER_REQ / FACE_VERIFY_REQ / FACE_CLEAR_REQ
      FACE_PREVIEW_START_REQ / FACE_PREVIEW_STOP_REQ
订阅: FACE_STATUS_UPDATE / FACE_STATE_UPDATE / FACE_PREVIEW_STATE /
      FACE_REGISTER_RESULT / FACE_VERIFY_RESULT / FACE_CLEAR_RESULT

本页只负责「摆位置 + 发消息」：预览宿主容器与 airui.camera 组件由 app/face/face_app.lua
创建并挂在 airui.screen 上，页面把预览区的屏幕绝对坐标随 FACE_PREVIEW_START_REQ 下发。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local status_label, hint_label, result_label
local btn_preview, btn_register, btn_verify, btn_clear

local sw, sh = 480, 800
local pad = 12
local busy_kind = nil     -- nil=空闲 / "register" / "verify" / "clear"
local preview_state = 0   -- 0=未预览 1=正在打开 2=预览中
local preview_rect = nil  -- 预览区几何（屏幕绝对坐标，交给业务层建 camera 组件）

local PREVIEW_TEXT = {
    [0] = "开始预览",
    [1] = "连接中...",
    [2] = "停止预览",
}

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

--[[预览按钮文案与可用性
连接中（1）不可点，避免重复下发 START_REQ；人脸操作进行中同样禁用]]
local function sync_preview_btn()
    if not btn_preview then return end
    btn_preview:set_text(PREVIEW_TEXT[preview_state] or PREVIEW_TEXT[0])
    btn_preview:set_disabled(busy_kind ~= nil or preview_state == 1)
end

--[[忙碌态：录入/验证/清空进行中时按钮都禁用
（业务层是单例 UART 会话，并发会互相抢模组回包）]]
local function set_busy(kind)
    busy_kind = kind
    if btn_register then
        btn_register:set_text(kind == "register" and "录入中..." or "录入人脸")
        btn_register:set_disabled(kind ~= nil)
    end
    if btn_verify then
        btn_verify:set_text(kind == "verify" and "验证中..." or "验证人脸")
        btn_verify:set_disabled(kind ~= nil)
    end
    if btn_clear then
        btn_clear:set_text(kind == "clear" and "清空中..." or "清空全部用户")
        btn_clear:set_disabled(kind ~= nil)
    end
    sync_preview_btn()
end

--[[模组状态卡的配色：就绪绿、失败红、初始化/处理中橙、其余灰]]
local function state_color(state)
    if state == 2 then return theme.C.green end
    if state == 4 then return theme.C.rose end
    if state == 1 or state == 3 then return theme.C.amber end
    return theme.C.t2
end

-- ==================== 预览 ====================
local function start_preview()
    if busy_kind or preview_state ~= 0 or not preview_rect then return end

    preview_state = 1
    sync_preview_btn()
    if result_label then
        result_label:set_color(theme.C.t2)
        result_label:set_text("正在连接摄像头...")
    end

    sys.publish("FACE_PREVIEW_START_REQ", {
        x = preview_rect.x, y = preview_rect.y,
        w = preview_rect.w, h = preview_rect.h,
        fit = "contain",
    })
end

local function stop_preview()
    if preview_state == 0 then return end
    -- destroy=false：只停显示，保留最后一帧
    sys.publish("FACE_PREVIEW_STOP_REQ", { destroy = false })
end

--[[关闭预览并销毁组件

预览宿主容器挂在 airui.screen 上，exwin 隐藏/销毁页面 root 时不会带走它，
所以离开本页必须显式要求业务层销毁，否则画面会浮在其他页面上。]]
local function destroy_preview()
    preview_state = 0
    sys.publish("FACE_PREVIEW_STOP_REQ", { destroy = true })
end

-- ==================== 人脸操作 ====================
--[[启动一次识别操作
@param kind "register" / "verify"]]
local function start_face_op(kind)
    if busy_kind then return end

    local action = (kind == "register") and "录入" or "验证"
    set_busy(kind)
    if result_label then
        result_label:set_color(theme.C.t1)
        result_label:set_text("正在" .. action .. "人脸，请正对摄像头...")
    end
    if hint_label then hint_label:set_text("请正对摄像头") end

    -- 预览与人脸识别互斥，业务层收到请求后会先停流并（必要时）硬复位模组
    local topic = (kind == "register") and "FACE_REGISTER_REQ" or "FACE_VERIFY_REQ"
    sys.publish(topic, {})
end

--[[执行清空：删除模组内全部人脸模板]]
local function start_clear()
    if busy_kind then return end

    set_busy("clear")
    if result_label then
        result_label:set_color(theme.C.t1)
        result_label:set_text("正在清空全部用户...")
    end
    if hint_label then hint_label:set_text("清空后需重新录入") end

    sys.publish("FACE_CLEAR_REQ")
end

--[[清空不可恢复，先弹窗二次确认]]
local function confirm_clear()
    if busy_kind then return end

    local box = airui.msgbox({
        w = math.min(math.floor(sw * 0.78), sw - 20),
        h = math.max(math.floor(sh * 0.28), 120),
        style = { text_font_size = theme.fs("body") },
        title = "确认清空",
        text = "将删除模组内全部已录入人脸，且无法恢复。是否继续？",
        buttons = { "确定", "取消" },
        on_action = function(self, btn_label)
            if btn_label == "确定" then start_clear() end
            self:hide()
        end,
    })
    box:show()
end

-- ==================== 界面 ====================
local function build_ui()
    update_screen_size()
    local ctx = theme.page({
        title = "人脸识别",
        sub = "实时预览 · 录入 · 验证 · 清空",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    pad = ctx.pad

    --[[页面 base 的左上角在屏幕 (ax, ay)；预览区要交给业务层在 airui.screen 上建组件，
    所以预览矩形必须换算成屏幕绝对坐标（窄屏 area 为 nil → 0）。]]
    local area = theme.content_area()
    local ax = (area and area.x) or 0
    local ay = (area and area.y) or 0

    local body_fs = theme.fs("body")
    local cap_fs = theme.fs("caption")
    local micro_fs = theme.fs("micro")

    --[[宽屏：左预览（1:2 竖版，与旋转 90° 后的 480x960 等比）+ 右控制列
    窄屏：预览在上、控制列在下]]
    local wide = ctx.w >= theme.dp(640)
    local pv_x, pv_y, pv_w, pv_h
    local ctl_x, ctl_y, ctl_w, ctl_h

    if wide then
        pv_h = ctx.h
        pv_w = math.min(math.floor(pv_h / 2), math.floor(ctx.w * 0.45))
        pv_x, pv_y = ctx.x, ctx.y
        ctl_x = ctx.x + pv_w + pad
        ctl_y = ctx.y
        ctl_w = ctx.w - pv_w - pad
        ctl_h = ctx.h
    else
        pv_h = math.min(math.floor(ctx.h * 0.45), theme.dp(320))
        pv_w = math.min(math.floor(pv_h / 2), ctx.w)
        pv_x = ctx.x + math.floor((ctx.w - pv_w) / 2)
        pv_y = ctx.y
        ctl_x = ctx.x
        ctl_y = ctx.y + pv_h + pad
        ctl_w = ctx.w
        ctl_h = ctx.h - pv_h - pad
    end

    preview_rect = { x = ax + pv_x, y = ay + pv_y, w = pv_w, h = pv_h }

    -- ===== 预览区（背板 + 提示；摄像头画面由业务层覆盖在其上）=====
    local pv_card = theme.card(main_container, {
        x = pv_x, y = pv_y, w = pv_w, h = pv_h,
    })
    theme.label(pv_card, {
        x = pad, y = math.floor(pv_h / 2) - theme.dp(24),
        w = pv_w - 2 * pad, h = theme.dp(48),
        text = "预览区\n点击「开始预览」",
        px_size = cap_fs, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ===== 模组状态卡 =====
    local status_h = theme.dp(104)
    local status_card = theme.card(main_container, {
        x = ctl_x, y = ctl_y, w = ctl_w, h = status_h,
    })

    theme.section(status_card, {
        x = pad, y = theme.dp(10), w = ctl_w - 2 * pad,
        text = "模组状态", px_size = micro_fs, color = theme.C.t3,
    })

    local status_y = theme.dp(10) + theme.dp(20)
    status_label = theme.label(status_card, {
        x = pad, y = status_y, w = ctl_w - 2 * pad, h = body_fs + theme.dp(8),
        text = "正在获取状态...", px_size = body_fs, color = theme.C.t2,
    })

    hint_label = theme.label(status_card, {
        x = pad, y = status_y + body_fs + theme.dp(10), w = ctl_w - 2 * pad,
        h = cap_fs + theme.dp(8),
        text = "请正对摄像头", px_size = cap_fs, color = theme.C.t3,
    })

    -- ===== 预览开关 =====
    local prev_h = theme.dp(52)
    local prev_y = ctl_y + status_h + pad

    btn_preview = theme.ghost_button(main_container, {
        x = ctl_x, y = prev_y, w = ctl_w, h = prev_h,
        text = PREVIEW_TEXT[0], size = theme.FS.label,
        on_click = function()
            if preview_state == 0 then
                start_preview()
            elseif preview_state == 2 then
                stop_preview()
            end
        end,
    })

    -- ===== 录入 / 验证按钮 =====
    local btn_h = theme.dp(56)
    local btn_y = prev_y + prev_h + pad
    local btn_w = math.floor((ctl_w - pad) / 2)

    btn_register = theme.button(main_container, {
        x = ctl_x, y = btn_y, w = btn_w, h = btn_h,
        text = "录入人脸", size = theme.FS.label,
        bg = theme.C.primary, fg = theme.C.on_primary, pressed = theme.C.primary_deep,
        on_click = function() start_face_op("register") end,
    })

    btn_verify = theme.button(main_container, {
        x = ctl_x + btn_w + pad, y = btn_y, w = ctl_w - btn_w - pad, h = btn_h,
        text = "验证人脸", size = theme.FS.label,
        bg = theme.C.green, fg = theme.C.white, pressed = theme.C.green_deep,
        on_click = function() start_face_op("verify") end,
    })

    -- ===== 清空全部按钮（危险操作，确认后再执行） =====
    local clear_h = theme.dp(46)
    local clear_y = btn_y + btn_h + pad

    btn_clear = theme.button(main_container, {
        x = ctl_x, y = clear_y, w = ctl_w, h = clear_h,
        text = "清空全部用户", size = theme.FS.label,
        bg = theme.C.rose, fg = theme.C.white, pressed = theme.C.rose_deep,
        on_click = confirm_clear,
    })

    -- ===== 结果卡 =====
    local res_y = clear_y + clear_h + pad
    local res_h = ctl_y + ctl_h - res_y
    if res_h < theme.dp(96) then res_h = theme.dp(96) end

    local res_card = theme.card(main_container, {
        x = ctl_x, y = res_y, w = ctl_w, h = res_h, scrollable = true,
    })

    theme.section(res_card, {
        x = pad, y = theme.dp(10), w = ctl_w - 2 * pad,
        text = "操作结果", px_size = micro_fs, color = theme.C.t3,
    })

    local res_text_y = theme.dp(10) + theme.dp(20)
    result_label = theme.label(res_card, {
        x = pad, y = res_text_y, w = ctl_w - 2 * pad,
        h = res_h - res_text_y - pad,
        text = "尚未进行录入或验证", px_size = body_fs, color = theme.C.t1,
    })

    set_busy(busy_kind)
end

-- ==================== 消息回调 ====================
local function on_status_update(data)
    if not data or not status_label then return end

    status_label:set_text(data.text or "未知状态")
    status_label:set_color(state_color(data.state))

    if data.message and hint_label then
        hint_label:set_text(data.message)
    end

    --[[模组不可用时释放按钮，避免界面一直卡在「录入中/验证中」
    BUSY(3) 期间 ready 可能仍是 false（操作中会现场重新探测模组），不能在这里解锁]]
    if not data.ready and busy_kind and data.state ~= 3 then
        set_busy(nil)
    end
end

local function on_state_update(data)
    if data and data.message and hint_label then
        hint_label:set_text(data.message)
    end
end

--[[预览状态：0=未预览 1=正在打开 2=预览中
业务层在同一主题上复用 text 字段说明原因（掉线、未检测到摄像头、固件不支持…）]]
local function on_preview_state(data)
    if not data then return end

    preview_state = data.state or 0
    sync_preview_btn()

    local text = data.text
    -- 人脸操作进行中时不覆盖结果卡（业务层停流时的提示会让位给「正在录入…」）
    if preview_state == 0 and not busy_kind and text and result_label
        and text ~= "预览已停止" and text ~= "预览已关闭" and text ~= "预览未开启" then
        result_label:set_color(theme.C.t2)
        result_label:set_text(text)
    end
end

local function on_register_result(data)
    set_busy(nil)
    if not result_label then return end

    if data and data.success then
        result_label:set_color(theme.C.green)
        result_label:set_text("录入成功\n姓名：" .. tostring(data.name or "--") ..
            "    编号：" .. tostring(data.user_id or "--"))
    else
        result_label:set_color(theme.C.rose)
        result_label:set_text("录入失败\n" .. tostring((data and data.error) or "未知错误"))
    end
end

local function on_verify_result(data)
    set_busy(nil)
    if not result_label then return end

    if data and data.success then
        result_label:set_color(theme.C.green)
        result_label:set_text("验证成功\n姓名：" .. tostring(data.name or "--") ..
            "    编号：" .. tostring(data.user_id or "--"))
    else
        result_label:set_color(theme.C.rose)
        result_label:set_text("验证失败\n" .. tostring((data and data.error) or "未知错误"))
    end
end

local function on_clear_result(data)
    set_busy(nil)
    if not result_label then return end

    if data and data.success then
        result_label:set_color(theme.C.green)
        result_label:set_text("已清空全部人脸数据\n可重新录入新用户")
        if hint_label then hint_label:set_text("请正对摄像头") end
    else
        result_label:set_color(theme.C.rose)
        result_label:set_text("清空失败\n" .. tostring((data and data.error) or "未知错误"))
    end
end

-- ==================== 窗口生命周期 ====================
local function on_create()
    busy_kind = nil
    preview_state = 0
    build_ui()

    sys.subscribe("FACE_STATUS_UPDATE", on_status_update)
    sys.subscribe("FACE_STATE_UPDATE", on_state_update)
    sys.subscribe("FACE_PREVIEW_STATE", on_preview_state)
    sys.subscribe("FACE_REGISTER_RESULT", on_register_result)
    sys.subscribe("FACE_VERIFY_RESULT", on_verify_result)
    sys.subscribe("FACE_CLEAR_RESULT", on_clear_result)

    sys.publish("FACE_STATUS_REQ")
end

local function on_destroy()
    sys.unsubscribe("FACE_STATUS_UPDATE", on_status_update)
    sys.unsubscribe("FACE_STATE_UPDATE", on_state_update)
    sys.unsubscribe("FACE_PREVIEW_STATE", on_preview_state)
    sys.unsubscribe("FACE_REGISTER_RESULT", on_register_result)
    sys.unsubscribe("FACE_VERIFY_RESULT", on_verify_result)
    sys.unsubscribe("FACE_CLEAR_RESULT", on_clear_result)

    destroy_preview()

    busy_kind = nil
    preview_rect = nil

    if main_container then main_container:destroy(); main_container = nil end

    status_label = nil
    hint_label = nil
    result_label = nil
    btn_preview = nil
    btn_register = nil
    btn_verify = nil
    btn_clear = nil
end

local function on_get_focus()
    sys.publish("FACE_STATUS_REQ")
end

local function on_lose_focus()
    -- 预览组件挂在 airui.screen 上，不随页面隐藏，离开本页必须销毁
    destroy_preview()
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FACE_WIN", open_handler)
