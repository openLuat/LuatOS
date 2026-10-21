--[[
@module  settings_face_win
@summary 人脸识别子页面（人脸录入 / 人脸验证）
@version 1.2
@date    2026.10.21
@author  江访
@usage
订阅: OPEN_FACE_WIN
发布: FACE_STATUS_REQ / FACE_REGISTER_REQ / FACE_VERIFY_REQ / FACE_CLEAR_REQ
订阅: FACE_STATUS_UPDATE / FACE_STATE_UPDATE /
      FACE_REGISTER_RESULT / FACE_VERIFY_RESULT / FACE_CLEAR_RESULT
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local status_label, hint_label, result_label
local btn_register, btn_verify, btn_clear

local sw, sh = 480, 800
local pad = 12
local busy_kind = nil   -- nil=空闲 / "register" / "verify" / "clear"

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

--[[忙碌态：录入/验证/清空进行中时三个按钮都禁用
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
end

--[[模组状态卡的配色：就绪绿、失败红、初始化/处理中橙、其余灰]]
local function state_color(state)
    if state == 2 then return theme.C.green end
    if state == 4 then return theme.C.rose end
    if state == 1 or state == 3 then return theme.C.amber end
    return theme.C.t2
end

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

    -- reset=true：传感器可能停在摄像头模式，识别前先复位回人脸模式
    sys.publish(kind == "register" and "FACE_REGISTER_REQ" or "FACE_VERIFY_REQ", { reset = true })
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

local function build_ui()
    update_screen_size()
    local ctx = theme.page({
        title = "人脸识别",
        sub = "人脸录入与验证",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    pad = ctx.pad

    local body_fs = theme.fs("body")
    local cap_fs = theme.fs("caption")
    local micro_fs = theme.fs("micro")

    -- ===== 模组状态卡 =====
    local status_h = theme.dp(112)
    local status_card = theme.card(main_container, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = status_h,
    })

    theme.section(status_card, {
        x = pad, y = theme.dp(10), w = ctx.w - 2 * pad,
        text = "模组状态", px_size = micro_fs, color = theme.C.t3,
    })

    local status_y = theme.dp(10) + theme.dp(20)
    status_label = theme.label(status_card, {
        x = pad, y = status_y, w = ctx.w - 2 * pad, h = body_fs + theme.dp(8),
        text = "正在获取状态...", px_size = body_fs, color = theme.C.t2,
    })

    hint_label = theme.label(status_card, {
        x = pad, y = status_y + body_fs + theme.dp(10), w = ctx.w - 2 * pad,
        h = cap_fs + theme.dp(8),
        text = "请正对摄像头", px_size = cap_fs, color = theme.C.t3,
    })

    -- ===== 录入 / 验证按钮 =====
    local btn_h = theme.dp(56)
    local btn_y = ctx.y + status_h + pad
    local btn_w = math.floor((ctx.w - pad) / 2)

    btn_register = theme.button(main_container, {
        x = ctx.x, y = btn_y, w = btn_w, h = btn_h,
        text = "录入人脸", size = theme.FS.label,
        bg = theme.C.primary, fg = theme.C.on_primary, pressed = theme.C.primary_deep,
        on_click = function() sys.taskInit(start_face_op, "register") end,
    })

    btn_verify = theme.button(main_container, {
        x = ctx.x + btn_w + pad, y = btn_y, w = ctx.w - btn_w - pad, h = btn_h,
        text = "验证人脸", size = theme.FS.label,
        bg = theme.C.green, fg = theme.C.white, pressed = theme.C.green_deep,
        on_click = function() sys.taskInit(start_face_op, "verify") end,
    })

    -- ===== 清空全部按钮（危险操作，确认后再执行） =====
    local clear_h = theme.dp(48)
    local clear_y = btn_y + btn_h + pad

    btn_clear = theme.button(main_container, {
        x = ctx.x, y = clear_y, w = ctx.w, h = clear_h,
        text = "清空全部用户", size = theme.FS.label,
        bg = theme.C.rose, fg = theme.C.white, pressed = theme.C.rose_deep,
        on_click = confirm_clear,
    })

    -- ===== 结果卡 =====
    local res_y = clear_y + clear_h + pad
    local res_h = ctx.y + ctx.h - res_y
    if res_h < theme.dp(96) then res_h = theme.dp(96) end

    local res_card = theme.card(main_container, {
        x = ctx.x, y = res_y, w = ctx.w, h = res_h, scrollable = true,
    })

    theme.section(res_card, {
        x = pad, y = theme.dp(10), w = ctx.w - 2 * pad,
        text = "识别结果", px_size = micro_fs, color = theme.C.t3,
    })

    local res_text_y = theme.dp(10) + theme.dp(20)
    result_label = theme.label(res_card, {
        x = pad, y = res_text_y, w = ctx.w - 2 * pad,
        h = res_h - res_text_y - pad,
        text = "尚未进行录入或验证", px_size = body_fs, color = theme.C.t1,
    })
end

-- ==================== 消息回调 ====================
local function on_status_update(data)
    if not data or not status_label then return end

    status_label:set_text(data.text or "未知状态")
    status_label:set_color(state_color(data.state))

    if data.message and hint_label then
        hint_label:set_text(data.message)
    end

    -- 模组不可用时释放按钮，避免界面一直卡在「录入中/验证中」
    if not data.ready and busy_kind then
        set_busy(nil)
    end
end

local function on_state_update(data)
    if data and data.message and hint_label then
        hint_label:set_text(data.message)
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
    build_ui()
    busy_kind = nil

    sys.subscribe("FACE_STATUS_UPDATE", on_status_update)
    sys.subscribe("FACE_STATE_UPDATE", on_state_update)
    sys.subscribe("FACE_REGISTER_RESULT", on_register_result)
    sys.subscribe("FACE_VERIFY_RESULT", on_verify_result)
    sys.subscribe("FACE_CLEAR_RESULT", on_clear_result)

    sys.publish("FACE_STATUS_REQ")
end

local function on_destroy()
    sys.unsubscribe("FACE_STATUS_UPDATE", on_status_update)
    sys.unsubscribe("FACE_STATE_UPDATE", on_state_update)
    sys.unsubscribe("FACE_REGISTER_RESULT", on_register_result)
    sys.unsubscribe("FACE_VERIFY_RESULT", on_verify_result)
    sys.unsubscribe("FACE_CLEAR_RESULT", on_clear_result)

    busy_kind = nil

    if main_container then main_container:destroy(); main_container = nil end

    status_label = nil
    hint_label = nil
    result_label = nil
    btn_register = nil
    btn_verify = nil
    btn_clear = nil
end

local function on_get_focus()
    sys.publish("FACE_STATUS_REQ")
end

local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FACE_WIN", open_handler)
