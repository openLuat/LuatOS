--[[
@module  sip_win
@summary SIP 电话应用 UI 主窗口
@version 1.0.0
@date    2026.05.28
@usage
使用 airui 实现 sip.html 的所有页面和功能。
]]

local win_id = nil
local main_container = nil
local keyboard = nil

-- ==================== 屏幕自适应 ====================
local W, H = 480, 320
local project_name = (_G.project_config and _G.project_config.name) or ""
local w_str, h_str = project_name:match("_(%d+)x(%d+)_")
if w_str and h_str then
    W, H = tonumber(w_str), tonumber(h_str)
end
local SCALE = 1.0

local function update_screen_size()
    local phys_w, phys_h = lcd.getSize()
    local rotation = airui.get_rotation()
    if rotation == 0 or rotation == 180 then
        W, H = phys_w, phys_h
    else
        W, H = phys_h, phys_w
    end
    local raw_scale = math.min(W / 480, H / 320)
    SCALE = math.max(raw_scale, 0.75)
end

local function s(v)
    return math.floor(v * SCALE)
end

-- ==================== 颜色常量 ====================
local C = {
    PRIMARY      = 0xFF6200,
    PRIMARY_LIGHT= 0xFF9E26,
    BG           = 0xFFF8F0,
    CARD         = 0xFFFFFF,
    TEXT         = 0x252525,
    TEXT_SECOND  = 0x8A7359,
    TEXT_HINT    = 0xB68A5D,
    SUCCESS      = 0x20B565,
    DANGER       = 0xF04444,
    MISSED       = 0xF04444,
    ANSWERED     = 0x20A764,
    DIALED       = 0xFF7200,
    ORANGE_BG    = 0xFFF4E8,
    BORDER       = 0xFFD1A0,
    CALL_BG_TOP  = 0x164D8F,
    CALL_BG_BOT  = 0x030A18,
    NAV_ACTIVE   = 0xFF6200,
    NAV_INACTIVE = 0x9B6A33,
    TRANSLUCENT  = 0xFFFFFF,
}

-- ==================== 工具函数 ====================
local function now_time()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour, t.min)
end

local function format_time(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

-- ==================== PC 模拟器检测 ====================
local function is_pc_simulator()
    local ok, bsp = pcall(rtos.bsp)
    return ok and bsp == "PC"
end

local toast_dialog = nil
local toast_timer = nil

local function toast(text)
    log.info("sip_win", "toast:", text)
    if not main_container then return end
    -- 销毁旧的
    if toast_dialog and toast_dialog.destroy then
        toast_dialog:destroy()
        toast_dialog = nil
    end
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end

    local tw = s(280)
    local th = s(40)
    local tx = (W - tw) / 2
    local ty = H - s(140)

    toast_dialog = airui.container({
        parent = main_container,
        x = tx, y = ty,
        w = tw, h = th,
        color = 0x252525,
        radius = s(20),
    })

    airui.label({
        parent = toast_dialog,
        x = 0, y = 0,
        w = tw, h = th,
        text = text,
        font_size = s(13),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    toast_timer = sys.timerStart(function()
        if toast_dialog and toast_dialog.destroy then
            toast_dialog:destroy()
            toast_dialog = nil
        end
    end, 1500)
end

-- ==================== 页面管理 ====================
local pages = {}
local current_page = ""
local prev_page = ""
local last_app_tab = "contacts"
local app_header = nil
local app_content = nil
local app_nav = nil
local tab_views = {}
local app_subview = "tab"
local app_chat_view = nil

-- 自动登录状态
local is_auto_login = false
local current_login_mode = "manual"
local progress_bar = nil
local progress_label = nil
local progress_timer = nil
local login_in_progress = false
local login_timeout_timer = nil

-- 前向声明：show_page 在 show_login_timeout_popup 之后定义
local show_page

local function show_login_timeout_popup()
    if progress_timer then sys.timerStop(progress_timer); progress_timer = nil end
    if login_timeout_timer then sys.timerStop(login_timeout_timer); login_timeout_timer = nil end

    local content_text = current_login_mode == "auto"
        and "账号不存在，请联系厂家处理！"
        or "请确认账号存在并正确填写账号信息！"

    -- 动态创建弹窗，保证在最顶层
    local mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x000000,
        opacity = 128,
    })
    local card_w, card_h = s(280), s(180)
    local card = airui.container({
        parent = mask,
        x = (W - card_w) / 2, y = (H - card_h) / 2,
        w = card_w, h = card_h,
        color = 0xFFFFFF,
        radius = s(12),
    })
    airui.label({
        parent = card,
        x = 0, y = s(10),
        w = card_w, h = s(24),
        text = "提示",
        font_size = s(16),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = card,
        x = s(16), y = s(38),
        w = card_w - s(32), h = s(80),
        text = content_text,
        font_size = s(12),
        color = C.TEXT,
    })
    local ok_btn = airui.container({
        parent = card,
        x = (card_w - s(100)) / 2, y = card_h - s(42),
        w = s(100), h = s(32),
        color = C.PRIMARY,
        radius = s(6),
        on_click = function()
            if current_login_mode == "auto" then
                show_page("welcome")
            else
                show_page("login")
            end
            sys.timerStart(function()
                mask:destroy()
            end, 100)
        end
    })
    airui.label({
        parent = ok_btn,
        x = 0, y = 0,
        w = s(100), h = s(32),
        text = "确定",
        font_size = s(14),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

local switch_tab
local show_app_tab
local show_app_subview
local open_chat

local function set_hidden_safe(widget, hidden)
    if not widget or (widget.is_destroyed and widget:is_destroyed()) then return end
    if widget.set_hidden then
        widget:set_hidden(hidden)
    elseif hidden and widget.hide then
        widget:hide()
    elseif (not hidden) and widget.open then
        widget:open()
    end
end

local function open_safe(widget)
    if not widget or (widget.is_destroyed and widget:is_destroyed()) then return end
    if widget.open then
        widget:open()
    else
        set_hidden_safe(widget, false)
    end
end

local function log_widget_state(tag, widget, hidden_expected)
    local destroyed = widget and widget.is_destroyed and widget:is_destroyed() or false
    log.info("sip_win", tag, "destroyed=", destroyed, "hidden_expected=", hidden_expected)
end

function show_page(name)
    log.info("sip_win", "show_page:", name)
    -- if name == "incoming" then
    --     log.error("sip_win", "===== show_page(incoming) 调用栈 =====")
    --     log.error("sip_win", debug.traceback())
    -- end
    for k, container in pairs(pages) do
        if k == name then
            open_safe(container)
            log_widget_state("page_show:" .. k, container, false)
        else
            set_hidden_safe(container, true)
            log_widget_state("page_hide:" .. k, container, true)
        end
    end

    -- 顶层切页后，额外同步 app 内部子视图状态
    if name ~= "app" then
        set_hidden_safe(app_content, true)
        if tab_views then
            for _, view in pairs(tab_views) do
                set_hidden_safe(view, true)
            end
        end
        set_hidden_safe(app_nav, true)
        set_hidden_safe(app_header, true)
        set_hidden_safe(app_chat_view, true)
        set_hidden_safe(app_fab, true)
        set_hidden_safe(app_dialpad, true)
    else
        if show_app_subview then
            show_app_subview(app_subview)
        else
            set_hidden_safe(app_content, false)
            set_hidden_safe(app_nav, false)
            set_hidden_safe(app_header, false)
        end
    end
    
    prev_page = current_page
    current_page = name
end

local function back_page()
    if prev_page and prev_page ~= "" and pages[prev_page] then
        show_page(prev_page)
    else
        show_page("welcome")
    end
end

-- ==================== 全局数据引用 ====================
local sip_config = require "sip_config"
local sip_data = require "sip_data"
local sip_service = require "sip_service"

--[[
关闭 SIP 应用，返回系统主界面
]]
local function close_app()
    sys.taskInit(function()
        sip_service.hangup()
        sip_service.logout()
        sip_data.set_user(nil)
        current_login_mode = "manual"
        if win_id then
            exwin.close(win_id)
        end
    end)
end

--[[
仅关闭窗口返回系统桌面，保持 SIP 后台在线
]]
local function back_to_home()
    if win_id then
        exwin.close(win_id)
    end
end

-- ==================== 状态变量 ====================
local account = sip_config.get_account()
local contacts = sip_data.get_contacts()
local records = sip_data.get_records()
local chats = sip_data.get_chats()

local call_seconds = 0
local call_timer_obj = nil
local dial_number_value = ""
local current_chat_num = ""
local current_call_num = ""
local current_call_name = ""
local call_was_answered = false  -- 标记通话是否被接通
local call_recorded = false        -- 标记通话记录是否已保存
local call_is_incoming = false     -- 标记是否为来电（true=来电, false=去电）

-- 来电界面相关
local incoming_num_label = nil
local incoming_name_label = nil
local incoming_state_label = nil
local incoming_timer_label = nil
local incoming_answer_btn = nil
local incoming_reject_btn = nil
local incoming_timer_obj = nil  -- 来电超时定时器

-- UI 引用缓存（用于动态更新）
local ui_refs = {}

-- ==================== 键盘 ====================
local function create_keyboard()
    keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = s(50),
        w = W,
        h = s(150)
    })
end

-- ==================== CallScreen 页面 ====================
local call_num_label = nil
local call_name_label = nil
local call_timer_label = nil
local call_status_label = nil
local call_hangup_btn = nil
local call_sim_hint = nil  -- PC 模拟器无音频提示

local function create_call_screen()
    local page = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x030A18,
    })

    -- 顶部标题栏（深色）
    local header_h = s(50)
    airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = header_h,
        color = 0x082145,
    })
    airui.label({
        parent = page,
        x = 0, y = s(8),
        w = W, h = s(34),
        text = "拨号界面",
        font_size = s(18),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- PC 模拟器无音频提示条
    call_sim_hint = airui.label({
        parent = page,
        x = 0, y = header_h,
        w = W, h = s(24),
        text = "",
        font_size = s(11),
        color = 0xFFCC00,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 脉冲圆圈
    local pulse_size = s(70)
    airui.container({
        parent = page,
        x = (W - pulse_size) / 2, y = s(100),
        w = pulse_size, h = pulse_size,
        color = 0x1E1E2E,
        radius = pulse_size / 2,
        border_color = 0x3A3A5C,
        border_width = 1,
    })
    airui.image({
        parent = page,
        x = (W - pulse_size) / 2, y = s(100),
        w = pulse_size, h = pulse_size,
        src = "/luadb/landline.png",
        fit = "contain",
    })

    -- 被叫号码
    call_num_label = airui.label({
        parent = page,
        x = s(20), y = s(175),
        w = W - s(40), h = s(28),
        text = "",
        font_size = s(22),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 显示名
    call_name_label = airui.label({
        parent = page,
        x = s(20), y = s(205),
        w = W - s(40), h = s(18),
        text = "",
        font_size = s(13),
        color = 0xBFBFBF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 状态 / 计时器
    call_status_label = airui.label({
        parent = page,
        x = s(20), y = s(230),
        w = W - s(40), h = s(24),
        text = "正在呼叫...",
        font_size = s(18),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 挂断按钮（底部居中）
    local btn_size = s(55)
    call_hangup_btn = airui.container({
        parent = page,
        x = (W - btn_size) / 2, y = H - s(70),
        w = btn_size, h = btn_size,
        -- color = 0xE62727,
        radius = btn_size / 2,
        on_click = function()
            sip_service.hangup()
        end,
    })
    airui.image({
        parent = call_hangup_btn,
        x = 0, y = 0,
        w = btn_size, h = btn_size,
        src = "/luadb/hangup.png",
        fit = "contain",
    })

    page:hide()
    pages.call = page
end

local function show_call_screen(num, name)
    if not pages.call then return end
    current_call_num = num or ""
    current_call_name = name or ""
    call_was_answered = false
    call_recorded = false
    call_is_incoming = false
    if call_num_label then call_num_label:set_text(current_call_num) end
    if call_name_label then call_name_label:set_text(current_call_name) end
    if call_status_label then call_status_label:set_text("正在呼叫...") end
    show_page("call")
end

local function hide_call_screen()
    if not pages.call then return end
    if call_timer_obj then
        sys.timerStop(call_timer_obj)
        call_timer_obj = nil
    end
    call_seconds = 0
    if prev_page and pages[prev_page] then
        show_page(prev_page)
    else
        show_app_tab("contacts")
    end
end

-- ==================== Incoming Screen 页面 ====================
local function create_incoming_screen()
    local page = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x030A18,
    })

    -- 顶部标题栏
    local header_h = s(50)
    airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = header_h,
        color = 0x082145,
    })
    airui.label({
        parent = page,
        x = 0, y = s(8),
        w = W, h = s(34),
        text = "来电",
        font_size = s(18),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 脉冲圆圈
    local pulse_size = s(70)
    airui.container({
        parent = page,
        x = (W - pulse_size) / 2, y = s(60),
        w = pulse_size, h = pulse_size,
        color = 0x1E1E2E,
        radius = pulse_size / 2,
        border_color = 0x3A3A5C,
        border_width = 1,
    })
    airui.image({
        parent = page,
        x = (W - pulse_size) / 2, y = s(60),
        w = pulse_size, h = pulse_size,
        src = "/luadb/landline.png",
        fit = "contain",
    })

    -- 来电号码
    incoming_num_label = airui.label({
        parent = page,
        x = s(20), y = s(140),
        w = W - s(40), h = s(28),
        text = "",
        font_size = s(26),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 来电名称
    incoming_name_label = airui.label({
        parent = page,
        x = s(20), y = s(170),
        w = W - s(40), h = s(18),
        text = "",
        font_size = s(15),
        color = 0xBFBFBF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 来电状态
    incoming_state_label = airui.label({
        parent = page,
        x = s(20), y = s(192),
        w = W - s(40), h = s(18),
        text = "收到来电",
        font_size = s(14),
        color = 0xBFBFBF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 通话计时器（初始为空，接听后显示）
    incoming_timer_label = airui.label({
        parent = page,
        x = s(20), y = s(214),
        w = W - s(40), h = s(20),
        text = "",
        font_size = s(18),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 底部按钮区域
    local btn_size = s(55)
    local btn_y = H - s(70)
    local gap = s(60)
    local start_x = (W - btn_size * 2 - gap) / 2

    -- 接听按钮（绿色）
    incoming_answer_btn = airui.container({
        parent = page,
        x = start_x, y = btn_y,
        w = btn_size, h = btn_size,
        -- color = 0x20B565,
        radius = btn_size / 2,
        on_click = function()
            if incoming_timer_obj then
                sys.timerStop(incoming_timer_obj)
                incoming_timer_obj = nil
            end
            local ok = sip_service.accept()
            if ok then
                -- 接听成功，停留在 incoming 页面，更新为通话中状态
                -- 计时器由 SIP_EVT_CONNECTED 统一启动，避免与 SIP 事件冲突
                if incoming_state_label then incoming_state_label:set_text("通话中") end
                if incoming_timer_label then incoming_timer_label:set_text("00:00") end
                set_hidden_safe(incoming_answer_btn, true)
            else
                toast("接听失败")
                hide_incoming_screen()
            end
        end,
    })
    airui.image({
        parent = incoming_answer_btn,
        x = 0, y = 0,
        w = btn_size, h = btn_size,
        src = "/luadb/listen.png",
        fit = "contain",
    })
    airui.label({
        parent = page,
        x = start_x, y = H - s(22),
        w = btn_size, h = s(14),
        text = "接听",
        font_size = s(13),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 挂断按钮（红色）
    incoming_reject_btn = airui.container({
        parent = page,
        x = start_x + btn_size + gap, y = btn_y,
        w = btn_size, h = btn_size,
        -- color = 0xE62727,
        radius = btn_size / 2,
        on_click = function()
            sip_service.hangup()
        end,
    })
    airui.image({
        parent = incoming_reject_btn,
        x = 0, y = 0,
        w = btn_size, h = btn_size,
        src = "/luadb/hangup.png",
        fit = "contain",
    })
    airui.label({
        parent = page,
        x = start_x + btn_size + gap, y = H - s(22),
        w = btn_size, h = s(14),
        text = "挂断",
        font_size = s(13),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    page:hide()
    pages.incoming = page
end

local function show_incoming_screen(num, name)
    if not pages.incoming then return end
    current_call_num = num or ""
    current_call_name = name or ""
    call_was_answered = false
    call_recorded = false
    call_is_incoming = true
    if incoming_num_label then incoming_num_label:set_text(current_call_num) end
    if incoming_name_label then incoming_name_label:set_text(current_call_name) end
    if incoming_state_label then incoming_state_label:set_text("收到来电") end
    if incoming_timer_label then incoming_timer_label:set_text("") end
    set_hidden_safe(incoming_answer_btn, false)
    show_page("incoming")
    -- 30秒超时自动挂断
    if incoming_timer_obj then
        sys.timerStop(incoming_timer_obj)
    end
    incoming_timer_obj = sys.timerStart(function()
        incoming_timer_obj = nil
        log.info("sip_win", "incoming call timeout, auto reject")
        sip_service.hangup()
    end, 30000)
end

local function hide_incoming_screen()
    if not pages.incoming then return end
    if incoming_timer_obj then
        sys.timerStop(incoming_timer_obj)
        incoming_timer_obj = nil
    end
    if prev_page and pages[prev_page] then
        show_page(prev_page)
    else
        show_app_tab("contacts")
    end
end

-- ==================== 创建 Welcome 页面 ====================
local function create_page_welcome()
    local page = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0xFF7A00,
    })

    -- 上半橙色 下半白色
    airui.container({ parent = page, x = 0, y = 0, w = W, h = math.floor(H * 0.5), color = 0xFF7A00 })
    airui.container({ parent = page, x = 0, y = math.floor(H * 0.5), w = W, h = math.floor(H * 0.5), color = 0xFFFFFF })

    local card_w = s(320)
    local card_h = s(360)
    local card_x = (W - card_w) / 2
    local card_y = math.max(s(10), (H - card_h) / 2 - s(10))

    local card = airui.container({
        parent = page,
        x = card_x, y = card_y,
        w = card_w, h = card_h,
        color = 0xFFFFFF,
        radius = s(24),
    })

    -- Logo
    local logo_size = s(62)
    local logo = airui.container({
        parent = card,
        x = (card_w - logo_size) / 2, y = s(25),
        w = logo_size, h = logo_size,
        color = 0xFF6500,
        radius = s(20),
    })
    airui.label({
        parent = logo,
        x = 0, y = 0,
        w = logo_size, h = logo_size,
        text = "S",
        font_size = s(31),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = card,
        x = 0, y = s(100),
        w = card_w, h = s(30),
        text = "欢迎使用 SIP",
        font_size = s(22),
        color = 0x252525,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = card,
        x = 0, y = s(135),
        w = card_w, h = s(22),
        text = "嵌入式物联网语音与消息终端",
        font_size = s(12),
        color = 0x86511A,
        align = airui.TEXT_ALIGN_CENTER
    })

    local btn_h = s(42)
    local btn_w = s(272)
    local btn_x = (card_w - btn_w) / 2

    -- 主按钮：自动登录
    local primary_btn = airui.container({
        parent = card,
        x = btn_x, y = s(170),
        w = btn_w, h = btn_h,
        color = 0xFF5E00,
        radius = s(14),
        on_click = function()
            -- 检查网络就绪
            local adapter = socket and socket.dft and socket.dft() or nil
            local adapter_ready = (socket and socket.adapter and adapter ~= nil) and not not socket.adapter(adapter) or false
            if not adapter_ready then
                toast("请先连接网络")
                return
            end

            is_auto_login = true
            current_login_mode = "auto"
            login_in_progress = true
            local acc = sip_config.get_auto_account()
            local sip_cfg = {
                sip_server_addr = acc.sip_server_addr,
                sip_server_port = acc.sip_server_port,
                sip_domain = acc.sip_domain,
                sip_username = acc.sip_username,
                sip_password = acc.sip_password,
                sip_transport = string.lower(acc.sip_transport or "UDP"),
                adapter = acc.adapter,
            }
            log.info("sip_win", "auto_login", "user=", acc.sip_username, "server=", acc.sip_server_addr)
            sip_data.set_user(acc.sip_username)
            -- 初始化进度条
            if progress_bar then progress_bar:set_value(0, false) end
            if progress_label then progress_label:set_text("0%") end
            show_page("progress")
            -- 启动进度条定时器（最多到80，登录成功才跳到100）
            if progress_timer then sys.timerStop(progress_timer) end
            if login_timeout_timer then sys.timerStop(login_timeout_timer) end
            local progress_value = 0
            progress_timer = sys.timerLoopStart(function()
                progress_value = progress_value + 20
                if progress_value > 80 then progress_value = 80 end
                if progress_bar then progress_bar:set_value(progress_value, true) end
                if progress_label then progress_label:set_text(tostring(progress_value) .. "%") end
            end, 1000)
            -- 5秒超时检查
            login_timeout_timer = sys.timerStart(function()
                login_in_progress = false
                show_login_timeout_popup()
            end, 5000)
            sys.taskInit(function()
                sip_service.logout()
                local ok = sip_service.login(sip_cfg)
                if not ok then
                    log.warn("sip_win", "auto_login init failed")
                end
            end)
        end
    })
    airui.label({
        parent = primary_btn,
        x = 0, y = 0,
        w = btn_w, h = btn_h,
        text = "自动登录",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 次要按钮：手动登录
    local secondary_btn = airui.container({
        parent = card,
        x = btn_x, y = s(225),
        w = btn_w, h = btn_h,
        color = 0xFFF6EB,
        radius = s(14),
        border_color = 0xFFD4A3,
        border_width = 1,
        on_click = function()
            current_login_mode = "manual"
            show_page("login")
        end
    })
    airui.label({
        parent = secondary_btn,
        x = 0, y = 0,
        w = btn_w, h = btn_h,
        text = "手动登录",
        font_size = s(16),
        color = 0xF06000,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 返回主界面按钮
    local back_btn = airui.container({
        parent = card,
        x = btn_x, y = s(280),
        w = btn_w, h = btn_h,
        color = 0xFFF6EB,
        radius = s(14),
        border_color = 0xFFD4A3,
        border_width = 1,
        on_click = function()
            close_app()
        end
    })
    airui.label({
        parent = back_btn,
        x = 0, y = 0,
        w = btn_w, h = btn_h,
        text = "返回主界面",
        font_size = s(16),
        color = 0xF06000,
        align = airui.TEXT_ALIGN_CENTER
    })

    pages.welcome = page
end

-- ==================== 创建 Progress 页面 ====================
local function create_page_progress()
    local page = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = C.BG,
    })

    local bar_w = s(300)
    local bar_h = s(16)
    local bar_x = (W - bar_w) / 2
    local bar_y = (H - bar_h) / 2 - s(20)

    -- 标题
    airui.label({
        parent = page,
        x = 0, y = bar_y - s(50),
        w = W, h = s(30),
        text = "正在登录...",
        font_size = s(18),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 进度条
    progress_bar = airui.bar({
        parent = page,
        x = bar_x, y = bar_y,
        w = bar_w, h = bar_h,
        value = 0,
        min = 0,
        max = 100,
        radius = s(8),
        bg_color = 0xE0E0E0,
        indicator_color = C.PRIMARY,
    })

    -- 进度百分比
    progress_label = airui.label({
        parent = page,
        x = bar_x, y = bar_y + bar_h + s(10),
        w = bar_w, h = s(20),
        text = "0%",
        font_size = s(14),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })

    page:hide()
    pages.progress = page
end

-- ==================== 创建 Login 页面 ====================
local login_inputs = {}

local function create_page_login()
    local page = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = C.BG,
        scrollable = true,
    })

    -- 顶部返回按钮 + 标题
    local header_h = s(50)
    local header = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = header_h,
        color = 0xFF6500,
    })

    local back_btn = airui.container({
        parent = header,
        x = s(5), y = s(5),
        w = s(60), h = s(40),
        color = 0xFF6500,
        on_click = function()
            show_page("welcome")
        end
    })
    airui.label({
        parent = back_btn,
        x = 0, y = 0,
        w = s(60), h = s(40),
        text = "< 返回",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = header,
        x = s(80), y = s(8),
        w = W - s(160), h = s(34),
        text = "SIP 账户登录",
        font_size = s(18),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 登录卡片
    local card_w = math.min(s(432), W - s(40))
    local card_x = (W - card_w) / 2
    local card_y = header_h + s(20)

    local card = airui.container({
        parent = page,
        x = card_x, y = card_y,
        w = card_w, h = H - card_y - s(20),
        color = C.CARD,
        radius = s(20),
    })

    local field_h = s(34)
    local gap = s(10)
    local y = s(15)

    local function add_field(label_text, id, placeholder, opts)
        opts = opts or {}
        airui.label({
            parent = card,
            x = s(15), y = y,
            w = card_w - s(30), h = s(18),
            text = label_text,
            font_size = s(12),
            color = 0x7A4E21,
        })
        y = y + s(20)

        local inp = airui.textarea({
            parent = card,
            x = s(15), y = y,
            w = card_w - s(30), h = field_h,
            text = tostring(opts.value or ""),
            placeholder = placeholder or "",
            font_size = s(14),
            max_len = opts.max_len or 128,
            keyboard = keyboard,
            radius = s(11),
            bg_color = 0xFFFFFF,
            border_color = C.BORDER,
            border_width = 1,
        })
        login_inputs[id] = inp
        y = y + field_h + gap
        return inp
    end

    add_field("用户名 *", "username", "请输入用户名", { value = account.sip_username })
    add_field("密码 *", "password", "请输入密码", { value = account.sip_password })
    add_field("服务器地址 *", "server_address", "请输入服务器地址", { value = account.sip_server_address })
    add_field("域名 *", "domain", "请输入域名", { value = account.sip_domain or account.sip_server_address })
    add_field("端口号 *", "port", "请输入端口号", { value = account.sip_server_port or "5060" })
    add_field("登录名（选填）", "login_name", "可留空", { value = account.login_name })

    -- 传输协议下拉选择（用两个按钮模拟）
    airui.label({
        parent = card,
        x = s(15), y = y,
        w = card_w - s(30), h = s(18),
        text = "传输协议",
        font_size = s(12),
        color = 0x7A4E21,
    })
    y = y + s(20)

    local transport_val = account.sip_transport or "UDP"
    local transport_label = nil
    local udp_btn, tcp_btn

    udp_btn = airui.container({
        parent = card,
        x = s(15), y = y,
        w = (card_w - s(40)) / 2, h = field_h,
        color = transport_val == "UDP" and C.PRIMARY or C.CARD,
        radius = s(11),
        border_color = C.BORDER,
        border_width = 1,
        on_click = function()
            transport_val = "UDP"
            log.info("sip_win", "transport_click", transport_val, "udp_btn=", udp_btn ~= nil, "tcp_btn=", tcp_btn ~= nil)
            udp_btn:set_color(C.PRIMARY)
            tcp_btn:set_color(C.CARD)
        end
    })
    airui.label({
        parent = udp_btn,
        x = 0, y = 0,
        w = (card_w - s(40)) / 2, h = field_h,
        text = "UDP",
        font_size = s(14),
        color = transport_val == "UDP" and 0xFFFFFF or C.TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    tcp_btn = airui.container({
        parent = card,
        x = s(25) + (card_w - s(40)) / 2, y = y,
        w = (card_w - s(40)) / 2, h = field_h,
        color = transport_val == "TCP" and C.PRIMARY or C.CARD,
        radius = s(11),
        border_color = C.BORDER,
        border_width = 1,
        on_click = function()
            transport_val = "TCP"
            log.info("sip_win", "transport_click", transport_val, "udp_btn=", udp_btn ~= nil, "tcp_btn=", tcp_btn ~= nil)
            tcp_btn:set_color(C.PRIMARY)
            udp_btn:set_color(C.CARD)
        end
    })
    airui.label({
        parent = tcp_btn,
        x = 0, y = 0,
        w = (card_w - s(40)) / 2, h = field_h,
        text = "TCP",
        font_size = s(14),
        color = transport_val == "TCP" and 0xFFFFFF or C.TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    y = y + field_h + s(20)

    -- 登录按钮
    local login_btn = airui.container({
        parent = card,
        x = s(15), y = y,
        w = card_w - s(30), h = s(42),
        color = C.PRIMARY,
        radius = s(14),
        on_click = function()
            local un = login_inputs.username:get_text() or ""
            local pw = login_inputs.password:get_text() or ""
            local sa = login_inputs.server_address:get_text() or ""
            local dm = login_inputs.domain:get_text() or ""
            local pt = login_inputs.port:get_text() or "5060"
            local ln = login_inputs.login_name:get_text() or ""
            local adapter = socket and socket.dft and socket.dft() or nil
            local adapter_ready = (socket and socket.adapter and adapter ~= nil) and not not socket.adapter(adapter) or false
            local local_ip = (socket and socket.localIP and adapter_ready and adapter ~= nil) and socket.localIP(adapter) or nil

            log.info("sip_win", "login_submit", "username=", un ~= "" and un or "<empty>", "server=", sa ~= "" and sa or "<empty>", "domain=", dm ~= "" and dm or "<empty>", "port=", pt ~= "" and pt or "<empty>", "transport=", transport_val)

            if un == "" or pw == "" or sa == "" or dm == "" or pt == "" then
                toast("请填写必填项")
                return
            end

            -- 网络状态检查（调试用日志已清理）

            if not adapter_ready then
                toast("请先连接网络")
                return
            end

            account.sip_username = un
            account.sip_password = pw
            account.sip_server_address = sa
            account.sip_domain = dm
            account.sip_server_port = tonumber(pt) or 5060
            account.sip_transport = transport_val
            account.adapter = adapter
            account.display_name = (ln ~= "" and ln) or un

            sip_config.save_account(account)
            sip_data.set_user(un)

            -- 启动 SIP 服务
            local sip_cfg = {
                sip_server_addr = sa,
                sip_server_port = tonumber(pt) or 5060,
                sip_server_address = sa,
                sip_domain = dm,
                sip_username = un,
                sip_password = pw,
                sip_transport = string.lower(transport_val),
                adapter = adapter,
            }

            is_auto_login = false
            current_login_mode = "manual"
            login_in_progress = true
            -- 进入进度条页面
            if progress_bar then progress_bar:set_value(0, false) end
            if progress_label then progress_label:set_text("0%") end
            show_page("progress")
            -- 启动进度条定时器（最多到80，登录成功才跳到100）
            if progress_timer then sys.timerStop(progress_timer) end
            if login_timeout_timer then sys.timerStop(login_timeout_timer) end
            local progress_value = 0
            progress_timer = sys.timerLoopStart(function()
                progress_value = progress_value + 20
                if progress_value > 80 then progress_value = 80 end
                if progress_bar then progress_bar:set_value(progress_value, true) end
                if progress_label then progress_label:set_text(tostring(progress_value) .. "%") end
            end, 1000)
            -- 5秒超时检查
            login_timeout_timer = sys.timerStart(function()
                login_in_progress = false
                show_login_timeout_popup()
            end, 5000)

            sys.taskInit(function()
                -- 如果 SIP 已在运行，先注销清除旧状态
                sip_service.logout()

                local ok = sip_service.login(sip_cfg)
                if not ok then
                    log.warn("sip_win", "manual_login init failed")
                end
                -- 注册成功/失败的页面跳转由 SIP_EVT_REGISTER_OK / SIP_EVT_REGISTER_FAILED 处理
            end)
        end
    })
    airui.label({
        parent = login_btn,
        x = 0, y = 0,
        w = card_w - s(30), h = s(42),
        text = "登录",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    pages.login = page
end

-- ==================== App 页面框架 ====================
app_header = nil
local app_title_label = nil
app_content = nil
app_nav = nil
local app_page = nil
local app_fab = nil
local app_dialpad = nil
local fab_visible = false
local dialpad_visible = false
local new_chat_form = nil
local new_chat_num_input = nil
local new_chat_content_input = nil
local chat_input_area = nil
local is_new_chat_form_visible = false
local is_history_mode = false
local history_btn = nil
local app_tab_contacts = nil
local app_tab_records = nil
local app_tab_chats = nil
local app_tab_profile = nil
local nav_items = {}
tab_views = {}

-- 联系人添加对话框
local contact_dialog_mask = nil
local contact_dialog_input = nil
local contact_dialog_number_label = nil
local contact_dialog_keyboard = nil
local pending_add_number = ""

-- 联系人删除确认对话框
local delete_dialog_mask = nil
local delete_dialog_name_label = nil
local pending_delete_num = ""

-- 联系人状态弹窗
local offline_dialog_mask = nil
local offline_dialog_content = nil
local abnormal_dialog_mask = nil


local function create_page_app()
    local page = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = C.BG,
    })
    app_page = page

    local header_h = s(48)
    local nav_h = s(58)
    local content_h = H - header_h - nav_h

    -- 顶部栏
    app_header = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = header_h,
        color = C.PRIMARY,
    })

    -- 返回按钮（回到欢迎页）
    local back_to_welcome_btn = airui.container({
        parent = app_header,
        x = s(8), y = s(8),
        w = s(55), h = s(32),
        color = 0xFFFFFF,
        radius = s(16),
        on_click = function()
            show_page("welcome")
        end
    })
    airui.label({
        parent = back_to_welcome_btn,
        x = 0, y = (s(32) - s(16)) / 2,
        w = s(55), h = s(32),
        text = "返回",
        font_size = s(14),
        color = C.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    app_title_label = airui.label({
        parent = app_header,
        x = s(48), y = s(8),
        w = W - s(160), h = s(32),
        text = "",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 退出按钮（仅返回系统桌面，不关闭 SIP）
    local exit_btn = airui.container({
        parent = app_header,
        x = W - s(65), y = s(8),
        w = s(55), h = s(32),
        color = 0xFFFFFF,
        radius = s(16),
        on_click = function()
            back_to_home()
        end
    })
    airui.label({
        parent = exit_btn,
        -- x = 0, y = 0,
        x = 0, y = (s(32) - s(14)) / 2,
        w = s(55), h = s(32),
        text = "退出",
        font_size = s(14),
        color = C.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区
    app_content = airui.container({
        parent = page,
        x = 0, y = header_h,
        w = W, h = content_h,
        color = C.BG,
    })

    -- 底部导航
    app_nav = airui.container({
        parent = page,
        x = 0, y = H - nav_h,
        w = W, h = nav_h,
        color = 0xFFFFFF,
        border_top_color = 0xFFE0BA,
        border_top_width = 1,
    })

    local nav_tabs = {
        { key = "contacts", label = "联系人", icon = "/luadb/contact.png" },
        { key = "records",  label = "通话记录", icon = "/luadb/history.png" },
        { key = "chats",    label = "聊天", icon = "/luadb/message.png" },
        { key = "profile",  label = "我的", icon = "/luadb/me.png" },
    }

    local nav_w = W / #nav_tabs
    for i, tab in ipairs(nav_tabs) do
        local nx = (i - 1) * nav_w
        local item_container = airui.container({
            parent = app_nav,
            x = nx, y = 0,
            w = nav_w, h = nav_h,
            color = 0xFFFFFF,
            on_click = function()
                log.info("sip_win", "nav_click:", tab.key)
                show_app_tab(tab.key)
            end
        })

        -- 图标
        local icon_img = airui.image({
            parent = item_container,
            x = (nav_w - s(24)) / 2, y = s(6),
            w = s(24), h = s(24),
            src = tab.icon,
            zoom = 256
        })

        -- 标签
        local label_color = (tab.key == "contacts") and C.NAV_ACTIVE or C.NAV_INACTIVE
        local nav_label = airui.label({
            parent = item_container,
            x = 0, y = s(30),
            w = nav_w, h = s(20),
            text = tab.label,
            font_size = s(10),
            color = label_color,
            align = airui.TEXT_ALIGN_CENTER
        })

        nav_items[tab.key] = { container = item_container, label = nav_label, icon = icon_img }
    end

    -- FAB 按钮
    app_fab = airui.container({
        parent = page,
        x = W - s(72), y = H - nav_h - s(72),
        w = s(52), h = s(52),
        color = C.PRIMARY,
        radius = s(26),
        on_click = function()
            if last_app_tab == "chats" then
                -- 聊天页：显示新建消息表单
                show_app_subview("chat")
                is_new_chat_form_visible = true
                if new_chat_form then
                    new_chat_form:open()
                    if chat_messages_container then chat_messages_container:hide() end
                    if chat_input_area then chat_input_area:hide() end
                    if chat_header_title then chat_header_title:set_text("新建信息") end
                end
                log.info("sip_win", "new_chat_form_show")
            else
                -- 联系人页：切换拨号盘
                dialpad_visible = not dialpad_visible
                set_hidden_safe(app_dialpad, not dialpad_visible)
                set_hidden_safe(app_nav, dialpad_visible)
                log.info("sip_win", "dialpad_toggle:", dialpad_visible)
            end
        end
    })
    airui.label({
        parent = app_fab,
        -- x = 0, y = 0,
        x = 0, y = (s(52) - s(30)) / 2,
        w = s(52), h = s(52),
        text = "+",
        font_size = s(30),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    fab_visible = false

    -- 拨号盘面板
    app_dialpad = airui.container({
        parent = page,
        x = s(20), y = H - s(310),
        w = W - s(40), h = s(300),
        color = 0xFFFFFF,
        radius = s(20),
    })
    app_dialpad:hide()
    dialpad_visible = false

    -- 号码显示
    local dial_display = airui.label({
        parent = app_dialpad,
        x = s(10), y = s(8),
        w = W - s(60), h = s(30),
        text = "请输入号码",
        font_size = s(18),
        color = C.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    ui_refs.dial_display = dial_display

    -- 返回按钮
    local dialpad_back_btn = airui.container({
        parent = app_dialpad,
        x = W - s(40) - s(34), y = s(6),
        w = s(28), h = s(28),
        color = 0xEEEEEE,
        radius = s(14),
        on_click = function()
            dialpad_visible = false
            set_hidden_safe(app_dialpad, true)
            set_hidden_safe(app_nav, false)
            switch_tab("contacts")
        end
    })
    airui.label({
        parent = dialpad_back_btn,
        x = 0, y = 0,
        w = s(28), h = s(28),
        text = "×",
        font_size = s(16),
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 数字键盘
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
    local key_w = (W - s(40) - s(30)) / 3
    local key_h = s(36)
    for i, k in ipairs(keys) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local kx = s(10) + col * (key_w + s(5))
        local ky = s(45) + row * (key_h + s(6))
        local key_btn = airui.container({
            parent = app_dialpad,
            x = kx, y = ky,
            w = key_w, h = key_h,
            color = C.ORANGE_BG,
            radius = s(10),
            on_click = function()
                dial_number_value = dial_number_value .. k
                if dial_display then
                    dial_display:set_text(dial_number_value)
                end
            end
        })
        airui.label({
            parent = key_btn,
            x = 0, y = 0,
            w = key_w, h = key_h,
            text = k,
            font_size = s(18),
            color = C.TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 功能键行
    local func_y = s(45) + 4 * (key_h + s(6))
    local func_w = (W - s(40) - s(20)) / 3

    local clear_btn = airui.container({
        parent = app_dialpad,
        x = s(10), y = func_y,
        w = func_w, h = key_h,
        color = C.ORANGE_BG,
        radius = s(10),
        on_click = function()
            dial_number_value = ""
            if dial_display then
                dial_display:set_text("请输入号码")
            end
        end
    })
    airui.label({ parent = clear_btn, x = 0, y = 0, w = func_w, h = key_h, text = "清空", font_size = s(14), color = C.TEXT, align = airui.TEXT_ALIGN_CENTER })

    local back_btn2 = airui.container({
        parent = app_dialpad,
        x = s(15) + func_w, y = func_y,
        w = func_w, h = key_h,
        color = C.ORANGE_BG,
        radius = s(10),
        on_click = function()
            dial_number_value = string.sub(dial_number_value, 1, -2)
            if dial_display then
                dial_display:set_text(dial_number_value ~= "" and dial_number_value or "请输入号码")
            end
        end
    })
    airui.label({ parent = back_btn2, x = 0, y = 0, w = func_w, h = key_h, text = "删除", font_size = s(14), color = C.TEXT, align = airui.TEXT_ALIGN_CENTER })

    local dial_btn = airui.container({
        parent = app_dialpad,
        x = s(20) + func_w * 2, y = func_y,
        w = func_w, h = key_h,
        color = C.SUCCESS,
        radius = s(10),
        on_click = function()
            if dial_number_value ~= "" then
                if not is_pc_simulator() and sip_service.get_status() ~= "STATE_READY" then
                    toast("正在注册中，请稍候后再拨号")
                    return
                end
                local contact_name = sip_data.get_contact_name(dial_number_value) or dial_number_value
                show_call_screen(dial_number_value, contact_name)
                local ok = sip_service.dial(tostring(dial_number_value))
                if not ok then
                    toast("拨号失败，请检查网络或账号状态")
                    sys.timerStart(function()
                        hide_call_screen()
                    end, 2000)
                end
            end
        end
    })
    airui.label({ parent = dial_btn, x = 0, y = 0, w = func_w, h = key_h, text = "拨号", font_size = s(14), color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })

    -- 添加联系人按钮
    local add_contact_btn = airui.container({
        parent = app_dialpad,
        x = s(10), y = func_y + key_h + s(6),
        w = W - s(60), h = s(32),
        color = 0xFFF2E3,
        radius = s(10),
        border_color = C.BORDER,
        border_width = 1,
        on_click = function()
            if dial_number_value == "" then
                toast("请先输入号码")
                return
            end
            pending_add_number = dial_number_value
            if contact_dialog_mask then
                contact_dialog_mask:set_hidden(false)
                if contact_dialog_number_label then contact_dialog_number_label:set_text(pending_add_number) end
                if contact_dialog_input then contact_dialog_input:set_text("") end
            end
        end
    })
    airui.label({ parent = add_contact_btn, x = 0, y = 0, w = W - s(60), h = s(32), text = "添加联系人", font_size = s(13), color = C.PRIMARY, align = airui.TEXT_ALIGN_CENTER })

    -- ==================== 添加联系人对话框 ====================
    contact_dialog_mask = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x000000,
        opacity = 128,
        on_click = function()
            -- 点击遮罩关闭
            contact_dialog_mask:set_hidden(true)
        end
    })
    contact_dialog_mask:set_hidden(true)

    local dialog_card_w, dialog_card_h = s(280), s(180)
    local dialog_card_x = (W - dialog_card_w) / 2
    local dialog_card_y = (H - dialog_card_h) / 2
    local dialog_card = airui.container({
        parent = contact_dialog_mask,
        x = dialog_card_x, y = dialog_card_y,
        w = dialog_card_w, h = dialog_card_h,
        color = 0xFFFFFF,
        radius = s(12),
        shadow = true,
        -- 阻止点击穿透
        on_click = function() end
    })

    airui.label({
        parent = dialog_card,
        x = 0, y = s(12),
        w = dialog_card_w, h = s(24),
        text = "添加联系人",
        font_size = s(16),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    contact_dialog_number_label = airui.label({
        parent = dialog_card,
        x = s(16), y = s(44),
        w = dialog_card_w - s(32), h = s(20),
        text = "",
        font_size = s(13),
        color = C.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_LEFT
    })

    contact_dialog_keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        w = W,
        h = s(150),
        bg_color = C.CARD
    })

    contact_dialog_input = airui.textarea({
        parent = dialog_card,
        x = s(16), y = s(72),
        w = dialog_card_w - s(32), h = s(36),
        font_size = s(14),
        placeholder = "请输入备注名",
        keyboard = contact_dialog_keyboard
    })

    local btn_h = s(32)
    local btn_w = (dialog_card_w - s(48)) / 2
    local btn_y = dialog_card_h - btn_h - s(14)

    -- 取消按钮
    local dialog_cancel = airui.container({
        parent = dialog_card,
        x = s(16), y = btn_y,
        w = btn_w, h = btn_h,
        color = 0xF5F5F5,
        radius = s(6),
        border_color = C.BORDER,
        border_width = 1,
        on_click = function()
            contact_dialog_mask:set_hidden(true)
        end
    })
    airui.label({
        parent = dialog_cancel,
        x = 0, y = 0,
        w = btn_w, h = btn_h,
        text = "取消",
        font_size = s(14),
        color = C.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 确定按钮
    local dialog_confirm = airui.container({
        parent = dialog_card,
        x = s(16) + btn_w + s(16), y = btn_y,
        w = btn_w, h = btn_h,
        color = C.PRIMARY,
        radius = s(6),
        on_click = function()
            local name = (contact_dialog_input and contact_dialog_input:get_text()) or ""
            if name == "" then
                name = "联系人 " .. pending_add_number
            end
            sip_data.add_contact(pending_add_number, name)
            contacts = sip_data.get_contacts()
            toast("已添加联系人")
            contact_dialog_mask:set_hidden(true)
            dial_number_value = ""
            if dial_display then
                dial_display:set_text("请输入号码")
            end
            -- 添加成功后返回联系人界面
            show_app_tab("contacts")
        end
    })
    airui.label({
        parent = dialog_confirm,
        x = 0, y = 0,
        w = btn_w, h = btn_h,
        text = "确定",
        font_size = s(14),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- ==================== 删除联系人确认对话框 ====================
    delete_dialog_mask = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x000000,
        opacity = 128,
        on_click = function()
            delete_dialog_mask:set_hidden(true)
        end
    })
    delete_dialog_mask:set_hidden(true)

    local del_card_w, del_card_h = s(260), s(140)
    local del_card_x = (W - del_card_w) / 2
    local del_card_y = (H - del_card_h) / 2
    local del_card = airui.container({
        parent = delete_dialog_mask,
        x = del_card_x, y = del_card_y,
        w = del_card_w, h = del_card_h,
        color = 0xFFFFFF,
        radius = s(12),
        on_click = function() end
    })

    airui.label({
        parent = del_card,
        x = 0, y = s(12),
        w = del_card_w, h = s(24),
        text = "确认删除",
        font_size = s(16),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    delete_dialog_name_label = airui.label({
        parent = del_card,
        x = s(16), y = s(44),
        w = del_card_w - s(32), h = s(20),
        text = "",
        font_size = s(13),
        color = C.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_CENTER
    })

    local del_btn_h = s(32)
    local del_btn_w = (del_card_w - s(48)) / 2
    local del_btn_y = del_card_h - del_btn_h - s(14)

    -- 否按钮
    local del_dialog_no = airui.container({
        parent = del_card,
        x = s(16), y = del_btn_y,
        w = del_btn_w, h = del_btn_h,
        color = 0xF5F5F5,
        radius = s(6),
        border_color = C.BORDER,
        border_width = 1,
        on_click = function()
            delete_dialog_mask:set_hidden(true)
        end
    })
    airui.label({
        parent = del_dialog_no,
        x = 0, y = 0,
        w = del_btn_w, h = del_btn_h,
        text = "否",
        font_size = s(14),
        color = C.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 是按钮
    local del_dialog_yes = airui.container({
        parent = del_card,
        x = s(16) + del_btn_w + s(16), y = del_btn_y,
        w = del_btn_w, h = del_btn_h,
        color = C.DANGER,
        radius = s(6),
        on_click = function()
            if pending_delete_num ~= "" then
                sip_data.remove_contact(pending_delete_num)
                contacts = sip_data.get_contacts()
                toast("已删除联系人")
                show_app_tab("contacts")
            end
            delete_dialog_mask:set_hidden(true)
        end
    })
    airui.label({
        parent = del_dialog_yes,
        x = 0, y = 0,
        w = del_btn_w, h = del_btn_h,
        text = "是",
        font_size = s(14),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- ==================== 离线状态提示弹窗 ====================
    offline_dialog_mask = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x000000,
        opacity = 128,
        on_click = function()
            offline_dialog_mask:set_hidden(true)
        end
    })
    offline_dialog_mask:set_hidden(true)

    local off_card_w, off_card_h = s(280), s(200)
    local off_card_x = (W - off_card_w) / 2
    local off_card_y = (H - off_card_h) / 2
    local off_card = airui.container({
        parent = offline_dialog_mask,
        x = off_card_x, y = off_card_y,
        w = off_card_w, h = off_card_h,
        color = 0xFFFFFF,
        radius = s(12),
        on_click = function() end
    })

    airui.label({
        parent = off_card,
        x = 0, y = s(10),
        w = off_card_w, h = s(24),
        text = "提示",
        font_size = s(16),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    offline_dialog_content = airui.label({
        parent = off_card,
        x = s(16), y = s(38),
        w = off_card_w - s(32) - s(85), h = s(110),
        text = " ",
        font_size = s(11),
        color = C.TEXT,
    })

    airui.image({
        parent = off_card,
        x = off_card_w - s(90), y = s(48),
        w = s(80), h = s(80),
        src = "/luadb/sip_call.png",
        fit = "contain",
    })

    local off_ok_btn = airui.container({
        parent = off_card,
        x = (off_card_w - s(100)) / 2, y = off_card_h - s(42),
        w = s(100), h = s(32),
        color = C.PRIMARY,
        radius = s(6),
        on_click = function()
            offline_dialog_mask:set_hidden(true)
        end
    })
    airui.label({
        parent = off_ok_btn,
        x = 0, y = 0,
        w = s(100), h = s(32),
        text = "确定",
        font_size = s(14),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- ==================== 状态异常提示弹窗 ====================
    abnormal_dialog_mask = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x000000,
        opacity = 128,
        on_click = function()
            abnormal_dialog_mask:set_hidden(true)
        end
    })
    abnormal_dialog_mask:set_hidden(true)

    local abn_card_w, abn_card_h = s(260), s(140)
    local abn_card_x = (W - abn_card_w) / 2
    local abn_card_y = (H - abn_card_h) / 2
    local abn_card = airui.container({
        parent = abnormal_dialog_mask,
        x = abn_card_x, y = abn_card_y,
        w = abn_card_w, h = abn_card_h,
        color = 0xFFFFFF,
        radius = s(12),
        on_click = function() end
    })

    airui.label({
        parent = abn_card,
        x = 0, y = s(24),
        w = abn_card_w, h = s(24),
        text = "联系人状态异常",
        font_size = s(14),
        color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    local abn_ok_btn = airui.container({
        parent = abn_card,
        x = (abn_card_w - s(100)) / 2, y = abn_card_h - s(42),
        w = s(100), h = s(32),
        color = C.PRIMARY,
        radius = s(6),
        on_click = function()
            abnormal_dialog_mask:set_hidden(true)
        end
    })
    airui.label({
        parent = abn_ok_btn,
        x = 0, y = 0,
        w = s(100), h = s(32),
        text = "确定",
        font_size = s(14),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    pages.app = page
end

-- ==================== App 子页面：联系人 ====================
local contacts_rows = {}

local function refresh_contacts()
    if not tab_views.contacts then return end
    -- 清除旧行
    for _, row in ipairs(contacts_rows) do
        if row and row.destroy then row:destroy() end
    end
    contacts_rows = {}

    contacts = sip_data.get_contacts()
    local row_h = s(56)
    local gap = s(8)
    local start_y = s(10)

    for i, c in ipairs(contacts) do
        local y = start_y + (i - 1) * (row_h + gap)
        local row = airui.container({
            parent = tab_views.contacts,
            x = s(10), y = y,
            w = W - s(20), h = row_h,
            color = C.CARD,
            radius = s(14),
            on_click = function()
                -- local status = c.online_status or 1
                local status = c.online_status or 0
                if status == 0 then
                    if current_login_mode == "auto" then
                        local auto_account = sip_config.get_auto_account()
                        local linphone_num = tostring(tonumber(auto_account.sip_username) + 1)
                        local linphone_pw = auto_account.sip_password or ""
                        local content = "请下载LinPhone安卓手机客户端并登录账号：\n账号：" .. linphone_num .. "\n密码：" .. linphone_pw .. "\n服务器地址：180.152.6.34:8910\n传输协议：UDP"
                        if offline_dialog_content then offline_dialog_content:set_text(content) end
                    else
                        local content = "此账号当前为离线状态，可以下载LinPhone安卓手机客户端\n并登录此账号进行测试"
                        if offline_dialog_content then offline_dialog_content:set_text(content) end
                    end
                    if offline_dialog_mask then offline_dialog_mask:set_hidden(false) end
                elseif status == 2 then
                    if abnormal_dialog_mask then abnormal_dialog_mask:set_hidden(false) end
                else
                    if not is_pc_simulator() and sip_service.get_status() ~= "STATE_READY" then
                        toast("正在注册中，请稍候后再拨号")
                        return
                    end
                    show_call_screen(c.num, c.name)
                    local ok = sip_service.dial(tostring(c.num))
                    if not ok then
                        toast("拨号失败")
                        hide_call_screen()
                    end
                end
            end,
        })

        -- 头像
        local avatar = airui.container({
            parent = row,
            x = s(10), y = s(10),
            w = s(36), h = s(36),
            color = C.PRIMARY,
            radius = s(18),
        })
        local first_char = string.sub(c.name or c.num, 1, 1)
        airui.label({
            parent = avatar,
            x = 0, y = 0,
            w = s(36), h = s(36),
            text = first_char,
            font_size = s(16),
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 名称
        airui.label({
            parent = row,
            x = s(55), y = s(8),
            w = W - s(155), h = s(20),
            text = c.name or c.num,
            font_size = s(14),
            color = C.TEXT,
        })

        -- 在线状态圆点
        local status_colors = {
            [0] = C.DANGER,
            [1] = C.SUCCESS,
            [2] = C.DIALED,
        }
        local dot_color = status_colors[c.online_status or 0] or C.TEXT_HINT
        airui.container({
            parent = row,
            -- x = s(55), y = s(28) + (s(18) - s(10)) / 2,
            x = s(55), y = s(28) + (s(18) - s(10)) / 3,
            w = s(10), h = s(10),
            color = dot_color,
            radius = s(5),
        })

        -- 号码
        airui.label({
            parent = row,
            x = s(68), y = s(28),
            w = W - s(168), h = s(18),
            text = c.num,
            font_size = s(11),
            color = C.TEXT_SECOND,
        })

        -- 删除按钮
        local del_btn_w = s(36)
        local del_btn_h = s(26)
        local del_btn = airui.container({
            parent = row,
            x = W - s(20) - del_btn_w - s(8), y = (row_h - del_btn_h) / 2,
            w = del_btn_w, h = del_btn_h,
            color = 0xFFEEEE,
            radius = s(4),
            border_color = 0xF04444,
            border_width = 1,
            on_click = function()
                pending_delete_num = c.num
                if delete_dialog_name_label then
                    delete_dialog_name_label:set_text("确定要删除 " .. (c.name or c.num) .. " 吗？")
                end
                if delete_dialog_mask then
                    delete_dialog_mask:set_hidden(false)
                end
            end
        })
        airui.label({
            parent = del_btn,
            x = 0, y = 0,
            w = del_btn_w, h = del_btn_h,
            text = "删除",
            font_size = s(10),
            color = C.DANGER,
            align = airui.TEXT_ALIGN_CENTER
        })

        table.insert(contacts_rows, row)
    end
end

-- ==================== App 子页面：通话记录 ====================
local records_rows = {}

local function refresh_records()
    if not tab_views.records then return end
    for _, row in ipairs(records_rows) do
        if row and row.destroy then row:destroy() end
    end
    records_rows = {}

    records = sip_data.get_records()
    local row_h = s(56)
    local gap = s(8)
    local start_y = s(10)
    local current_day = ""
    local y = start_y

    for i, r in ipairs(records) do
        if r.day ~= current_day then
            current_day = r.day
            local day_label = airui.label({
                parent = tab_views.records,
                x = s(15), y = y,
                w = W - s(30), h = s(20),
                text = current_day,
                font_size = s(11),
                color = 0xB56B1B,
            })
            table.insert(records_rows, day_label)
            y = y + s(24)
        end

        local row = airui.container({
            parent = tab_views.records,
            x = s(10), y = y,
            w = W - s(20), h = row_h,
            color = C.CARD,
            radius = s(14),
            on_click = function()
                if not is_pc_simulator() and sip_service.get_status() ~= "STATE_READY" then
                    toast("正在注册中，请稍候后再拨号")
                    return
                end
                local call_num = (r.num or "")
                if call_num == "" then
                    toast("号码为空，无法拨号")
                    return
                end
                local display_name = ((r.name or "") ~= "") and r.name or call_num
                show_call_screen(call_num, display_name)
                local ok = sip_service.dial(call_num)
                if not ok then
                    toast("拨号失败")
                    hide_call_screen()
                end
            end,
        })

        -- 通话类型图标颜色
        local type_colors = { missed = C.MISSED, answered = C.ANSWERED, dialed = C.DIALED }
        local type_labels = { missed = "未接", answered = "已接", dialed = "已拨" }
        local type_color = type_colors[r.type] or C.TEXT

        local type_icon = airui.container({
            parent = row,
            x = s(10), y = s(14),
            w = s(28), h = s(28),
            color = type_color,
            radius = s(14),
        })
        airui.label({
            parent = type_icon,
            x = 0, y = 0,
            w = s(28), h = s(28),
            text = type_labels[r.type] or "?",
            font_size = s(10),
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER
        })

        local display_name = ((r.name or "") ~= "") and r.name or (r.num or "")
        if display_name == "" then
            display_name = "未知号码"
        end
        airui.label({
            parent = row,
            x = s(48), y = s(8),
            w = W - s(140), h = s(20),
            text = display_name,
            font_size = s(14),
            color = C.TEXT,
        })

        local sub_text = ((r.name or "") ~= "") and ((r.num or "") .. " · " .. (type_labels[r.type] or "")) or (type_labels[r.type] or "")
        airui.label({
            parent = row,
            x = s(48), y = s(28),
            w = W - s(140), h = s(18),
            text = sub_text,
            font_size = s(11),
            color = C.TEXT_SECOND,
        })

        airui.label({
            parent = row,
            x = W - s(70), y = s(18),
            w = s(55), h = s(20),
            text = r.time,
            font_size = s(10),
            color = C.TEXT_HINT,
            align = airui.TEXT_ALIGN_RIGHT
        })

        table.insert(records_rows, row)
        y = y + row_h + gap
    end
end

-- ==================== App 子页面：聊天 ====================
local chats_rows = {}

local function refresh_chats()
    if not tab_views.chats then return end
    for _, row in ipairs(chats_rows) do
        if row and row.destroy then row:destroy() end
    end
    chats_rows = {}

    chats = sip_data.get_chats()
    local row_h = s(56)
    local gap = s(8)
    local start_y = s(10)
    local current_day = ""
    local y = start_y

    for i, c in ipairs(chats) do
        if c.day ~= current_day then
            current_day = c.day
            local day_label = airui.label({
                parent = tab_views.chats,
                x = s(15), y = y,
                w = W - s(30), h = s(20),
                text = current_day,
                font_size = s(11),
                color = 0xB56B1B,
            })
            table.insert(chats_rows, day_label)
            y = y + s(24)
        end

        local row = airui.container({
            parent = tab_views.chats,
            x = s(10), y = y,
            w = W - s(20), h = row_h,
            color = C.CARD,
            radius = s(14),
        })

        -- 头像
        local avatar = airui.container({
            parent = row,
            x = s(10), y = s(10),
            w = s(36), h = s(36),
            color = C.PRIMARY,
            radius = s(18),
        })
        local avatar_text = string.sub(c.num, -2)
        airui.label({
            parent = avatar,
            x = 0, y = 0,
            w = s(36), h = s(36),
            text = avatar_text,
            font_size = s(14),
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER
        })

        local contact_name = sip_data.get_contact_name(c.num)
        local display_name = contact_name and (contact_name .. "（" .. c.num .. "）") or c.num

        airui.label({
            parent = row,
            x = s(55), y = s(8),
            w = W - s(140), h = s(20),
            text = display_name,
            font_size = s(14),
            color = C.TEXT,
        })

        airui.label({
            parent = row,
            x = s(55), y = s(28),
            w = W - s(140), h = s(18),
            text = c.latest or "",
            font_size = s(11),
            color = C.TEXT_SECOND,
        })

        airui.label({
            parent = row,
            x = W - s(70), y = s(18),
            w = s(55), h = s(20),
            text = c.time or "",
            font_size = s(10),
            color = C.TEXT_HINT,
            align = airui.TEXT_ALIGN_RIGHT
        })

        row:set_on_click(function()
            open_chat(c.num)
        end)

        table.insert(chats_rows, row)
        y = y + row_h + gap
    end
end

-- ==================== 新建聊天对话框联系人列表 ====================
-- ==================== App 子页面：我的 ====================
local profile_inputs = {}

local function refresh_profile()
    if not tab_views.profile then return end
    if current_login_mode == "auto" then
        account = sip_config.get_auto_account()
    else
        account = sip_config.get_account()
    end
    if profile_inputs.p_username then profile_inputs.p_username:set_text(tostring(account.sip_username or "")) end
    if profile_inputs.p_password then profile_inputs.p_password:set_text(tostring(account.sip_password or "")) end
    if profile_inputs.p_server_address then profile_inputs.p_server_address:set_text(tostring(account.sip_server_address or "")) end
    if profile_inputs.p_domain then profile_inputs.p_domain:set_text(tostring(account.sip_domain or "")) end
    if profile_inputs.p_server_port then profile_inputs.p_server_port:set_text(tostring(account.sip_server_port or 5060)) end
    if profile_inputs.p_display then profile_inputs.p_display:set_text(tostring(account.display_name or "")) end
end

local function update_app_header_title()
    if not app_title_label then return end
    local account
    if current_login_mode == "auto" then
        account = sip_config.get_auto_account()
    else
        account = sip_config.get_account()
    end
    local username = account and account.sip_username or ""
    app_title_label:set_text(username ~= "" and username or "未登录")
end

show_app_subview = function(view_name)
    app_subview = view_name or "tab"
    log.info("sip_win", "show_app_subview:", app_subview)

    local is_chat = (app_subview == "chat")

    set_hidden_safe(app_header, is_chat)
    set_hidden_safe(app_content, is_chat)
    set_hidden_safe(app_nav, is_chat)
    set_hidden_safe(app_chat_view, not is_chat)
    set_hidden_safe(app_fab, is_chat or (not fab_visible))
    if is_chat then
        dialpad_visible = false
    end
    set_hidden_safe(app_dialpad, is_chat or (not dialpad_visible))
    -- 从通话/来电页面返回时，恢复当前 tab 视图
    if not is_chat and switch_tab then
        switch_tab(last_app_tab, true)
    end
    log_widget_state("subview_header", app_header, is_chat)
    log_widget_state("subview_content", app_content, is_chat)
    log_widget_state("subview_nav", app_nav, is_chat)
    log_widget_state("subview_chat", app_chat_view, not is_chat)
end

switch_tab = function(tab_name, keep_dialpad)
    log.info("sip_win", "switch_tab:", tab_name, "keep_dialpad:", keep_dialpad)
    last_app_tab = tab_name
    -- 更新导航高亮
    for name, item in pairs(nav_items) do
        if item and item.label then
            item.label:set_color(name == tab_name and C.NAV_ACTIVE or C.NAV_INACTIVE)
        end
        if item and item.icon then
            -- 图标颜色通过重新设置图片或遮罩实现，这里简化用标签颜色
        end
    end
    -- 切换内容区：先全部隐藏，再只显示当前 tab。
    for name, view in pairs(tab_views) do
        set_hidden_safe(view, name ~= tab_name)
        log_widget_state("tab_view:" .. name, view, name ~= tab_name)
    end
    -- 更新标题为当前登录用户名
    update_app_header_title()
    -- FAB 控制：联系人页显示拨号盘按钮，聊天页显示新建聊天按钮
    fab_visible = (tab_name == "contacts" or tab_name == "chats")
    set_hidden_safe(app_fab, not fab_visible)
    -- 隐藏拨号盘（除非保留）
    if not keep_dialpad then
        dialpad_visible = false
        set_hidden_safe(app_dialpad, true)
        set_hidden_safe(app_nav, false)
    end
    -- 刷新对应页面
    if tab_name == "contacts" then refresh_contacts() end
    if tab_name == "records" then refresh_records() end
    if tab_name == "chats" then refresh_chats() end
    if tab_name == "profile" then refresh_profile() end
end

show_app_tab = function(tab_name)
    log.info("sip_win", "show_app_tab:", tab_name)
    show_page("app")
    show_app_subview("tab")
    switch_tab(tab_name)
end

local function create_tab_views()
    local content_h = H - s(48) - s(58)

    -- 联系人（可滚动）
    tab_views.contacts = airui.container({
        parent = app_content,
        x = 0, y = 0,
        w = W, h = content_h,
        color = C.BG,
        scrollable = true,
    })

    -- 通话记录（可滚动）
    tab_views.records = airui.container({
        parent = app_content,
        x = 0, y = 0,
        w = W, h = content_h,
        color = C.BG,
        scrollable = true,
    })
    tab_views.records:hide()

    -- 聊天（可滚动）
    tab_views.chats = airui.container({
        parent = app_content,
        x = 0, y = 0,
        w = W, h = content_h,
        color = C.BG,
        scrollable = true,
    })
    tab_views.chats:hide()

    -- 我的（可滚动）
    tab_views.profile = airui.container({
        parent = app_content,
        x = 0, y = 0,
        w = W, h = content_h,
        color = C.BG,
        scrollable = true,
    })
    tab_views.profile:hide()

    -- 初始化"我的"页面内容
    local card_w = W - s(20)
    local card_x = s(10)
    local field_h = s(34)
    local y = s(15)

    local function add_profile_field(label_text, id, value, opts)
        opts = opts or {}
        airui.label({
            parent = tab_views.profile,
            x = card_x + s(10), y = y,
            w = card_w - s(20), h = s(18),
            text = label_text,
            font_size = s(12),
            color = 0x7A4E21,
        })
        y = y + s(20)

        local inp = airui.textarea({
            parent = tab_views.profile,
            x = card_x + s(10), y = y,
            w = card_w - s(20), h = field_h,
            text = tostring(value or ""),
            placeholder = opts.placeholder or "",
            font_size = s(14),
            max_len = opts.max_len or 128,
            keyboard = keyboard,
            radius = s(11),
            bg_color = 0xFFFFFF,
            border_color = C.BORDER,
            border_width = 1,
        })
        profile_inputs[id] = inp
        y = y + field_h + s(10)
    end

    if current_login_mode == "auto" then
        account = sip_config.get_auto_account()
    else
        account = sip_config.get_account()
    end
    add_profile_field("用户名", "p_username", account.sip_username)
    add_profile_field("密码", "p_password", account.sip_password)
    add_profile_field("服务器地址 *", "p_server_address", account.sip_server_address)
    add_profile_field("域名", "p_domain", account.sip_domain)
    add_profile_field("服务器端口", "p_server_port", account.sip_server_port or 5060)
    add_profile_field("显示名", "p_display", account.display_name)

    y = y + s(10)

    -- 保存按钮
    local save_btn = airui.container({
        parent = tab_views.profile,
        x = card_x + s(10), y = y,
        w = card_w - s(20), h = s(42),
        color = C.PRIMARY,
        radius = s(14),
        on_click = function()
            local changed_core = false
            local new_un = profile_inputs.p_username and profile_inputs.p_username:get_text() or account.sip_username
            local new_pw = profile_inputs.p_password and profile_inputs.p_password:get_text() or account.sip_password
            local new_sa = profile_inputs.p_server_address and profile_inputs.p_server_address:get_text()
            local new_dm = profile_inputs.p_domain and profile_inputs.p_domain:get_text()
            local new_sp = profile_inputs.p_server_port and tonumber(profile_inputs.p_server_port:get_text()) or 5060
            local new_dp = profile_inputs.p_display and profile_inputs.p_display:get_text()

            if new_un ~= account.sip_username or new_pw ~= account.sip_password or new_sa ~= account.sip_server_address or new_dm ~= account.sip_domain or new_sp ~= account.sip_server_port or new_dp ~= account.display_name then
                changed_core = true
            end

            account.sip_username = new_un
            account.sip_password = new_pw
            account.sip_server_address = new_sa
            account.sip_domain = new_dm
            account.sip_server_port = new_sp
            account.display_name = new_dp
            sip_config.save_account(account)

            if changed_core then
                sip_service.logout()
                sip_config.set_logged_in(false)
                show_page("login")
                toast("账户信息已变更，请重新登录")
            else
                toast("已保存")
            end
        end
    })
    airui.label({
        parent = save_btn,
        x = 0, y = 0,
        w = card_w - s(20), h = s(42),
        text = "保存",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    y = y + s(52)

    -- 退出登录按钮
    local logout_btn = airui.container({
        parent = tab_views.profile,
        x = card_x + s(10), y = y,
        w = card_w - s(20), h = s(42),
        color = 0xFFF0EB,
        radius = s(14),
        border_color = 0xFFC8A0,
        border_width = 1,
        on_click = function()
            sys.taskInit(function()
                sip_service.hangup()
                sip_service.logout()
                sip_data.set_user(nil)
                sip_config.set_logged_in(false)
                sip_config.clear_account()
                show_page("welcome")
                toast("已退出登录")
            end)
        end
    })
    airui.label({
        parent = logout_btn,
        x = 0, y = 0,
        w = card_w - s(20), h = s(42),
        text = "退出登录",
        font_size = s(16),
        color = 0xD95C00,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- ==================== ChatDetail 页面 ====================
local chat_messages_container = nil
local chat_input_text = nil
local chat_header_title = nil

open_chat = function(num)
    log.info("sip_win", "open_chat:", num, "history_mode:", is_history_mode)
    current_chat_num = num
    show_page("app")
    show_app_subview("chat")

    -- 隐藏新建消息表单
    is_new_chat_form_visible = false
    if new_chat_form then new_chat_form:hide() end

    local contact_name = sip_data.get_contact_name(num)
    local display_name = contact_name and (contact_name .. "（" .. num .. "）") or num
    if chat_header_title then
        chat_header_title:set_text(display_name)
    end

    -- 控制输入区显示/隐藏
    if is_history_mode then
        if chat_input_area then chat_input_area:hide() end
        if history_btn then history_btn:set_hidden(true) end
    else
        if chat_input_area then chat_input_area:open() end
        if history_btn then history_btn:set_hidden(false) end
    end

    -- 刷新消息列表
    if chat_messages_container then
        chat_messages_container:destroy()
    end

    local messages = sip_data.get_messages(num)
    local msg_h = s(50)
    local msg_height = s(16) + msg_h + s(10)

    if is_history_mode then
        -- 历史模式：倒序显示全部消息，隐藏输入框，扩展容器高度
        local container_h = H - s(48)
        chat_messages_container = airui.container({
            parent = app_chat_view,
            x = 0, y = s(48),
            w = W, h = container_h,
            color = 0xFFF8F0,
            scrollable = true,
        })

        local y = s(10)
        for i = #messages, 1, -1 do
            local m = messages[i]
            local is_out = (m.dir == "out")
            local bubble_w = math.min(s(280), W - s(80))
            local bubble_x = is_out and (W - bubble_w - s(15)) or s(15)

            -- 时间
            airui.label({
                parent = chat_messages_container,
                x = bubble_x, y = y,
                w = bubble_w, h = s(16),
                text = m.time or "",
                font_size = s(10),
                color = 0x9C8B7D,
                align = is_out and airui.TEXT_ALIGN_RIGHT or airui.TEXT_ALIGN_LEFT
            })
            y = y + s(16)

            -- 气泡
            local bubble = airui.container({
                parent = chat_messages_container,
                x = bubble_x, y = y,
                w = bubble_w, h = msg_h,
                color = is_out and C.PRIMARY or C.CARD,
                radius = s(12),
            })
            airui.label({
                parent = bubble,
                x = s(8), y = s(6),
                w = bubble_w - s(16), h = msg_h - s(12),
                text = m.text or "",
                font_size = s(13),
                color = is_out and 0xFFFFFF or C.TEXT,
            })
            y = y + msg_h + s(10)
        end

        -- 滚动到顶部，显示最新消息
        if chat_messages_container.scroll_to_y and #messages > 0 then
            chat_messages_container:scroll_to_y(0, false)
        end
    else
        -- 正常模式：正序显示，显示输入框
        local container_h = H - s(48) - s(50)
        chat_messages_container = airui.container({
            parent = app_chat_view,
            x = 0, y = s(48),
            w = W, h = container_h,
            color = 0xFFF8F0,
            scrollable = true,
        })

        local has_scroll = chat_messages_container.scroll_to_y ~= nil
        local start_idx = 1
        local y = s(10)

        if not has_scroll then
            -- 旧固件：限制显示最近N条，确保最新消息可见
            local max_display = math.max(1, math.floor(container_h / msg_height))
            start_idx = math.max(1, #messages - max_display + 1)
            local display_count = #messages - start_idx + 1
            local total_display_h = display_count * msg_height
            if total_display_h < container_h then
                y = s(10) + (container_h - total_display_h)
            end
        end

        for i = start_idx, #messages do
            local m = messages[i]
            local is_out = (m.dir == "out")
            local bubble_w = math.min(s(280), W - s(80))
            local bubble_x = is_out and (W - bubble_w - s(15)) or s(15)

            -- 时间
            airui.label({
                parent = chat_messages_container,
                x = bubble_x, y = y,
                w = bubble_w, h = s(16),
                text = m.time or "",
                font_size = s(10),
                color = 0x9C8B7D,
                align = is_out and airui.TEXT_ALIGN_RIGHT or airui.TEXT_ALIGN_LEFT
            })
            y = y + s(16)

            -- 气泡
            local bubble = airui.container({
                parent = chat_messages_container,
                x = bubble_x, y = y,
                w = bubble_w, h = msg_h,
                color = is_out and C.PRIMARY or C.CARD,
                radius = s(12),
            })
            airui.label({
                parent = bubble,
                x = s(8), y = s(6),
                w = bubble_w - s(16), h = msg_h - s(12),
                text = m.text or "",
                font_size = s(13),
                color = is_out and 0xFFFFFF or C.TEXT,
            })
            y = y + msg_h + s(10)
        end

        -- 新固件：滚动到底部显示最新消息
        if has_scroll and #messages > 0 then
            chat_messages_container:scroll_to_y(999999, false)
        end
    end

end

local function create_page_chat()
    local page = airui.container({
        parent = app_page,
        x = 0, y = 0,
        w = W, h = H,
        color = C.BG,
    })
    page:hide()
    app_chat_view = page

    -- 顶部栏
    local header = airui.container({
        parent = page,
        x = 0, y = 0,
        w = W, h = s(48),
        color = C.PRIMARY,
    })

    local back_btn = airui.container({
        parent = header,
        x = s(5), y = s(5),
        w = s(60), h = s(38),
        color = C.PRIMARY,
        on_click = function()
            log.info("sip_win", "chat_back_click")
            if is_history_mode then
                -- 从历史记录返回正常聊天界面
                is_history_mode = false
                if current_chat_num then
                    open_chat(current_chat_num)
                end
                return
            end
            if is_new_chat_form_visible then
                -- 从新建消息表单返回
                is_new_chat_form_visible = false
                new_chat_form:hide()
                if chat_messages_container then chat_messages_container:open() end
                if chat_input_area then chat_input_area:open() end
                if chat_header_title then chat_header_title:set_text("聊天记录") end
            else
                show_app_tab("chats")
            end
        end
    })
    airui.label({
        parent = back_btn,
        x = 0, y = 0,
        w = s(60), h = s(38),
        text = "< 返回",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    chat_header_title = airui.label({
        parent = header,
        x = s(70), y = s(8),
        w = W - s(140), h = s(32),
        text = "聊天记录",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 历史记录按钮
    history_btn = airui.container({
        parent = header,
        x = W - s(70), y = s(5),
        w = s(70), h = s(38),
        color = C.PRIMARY,
        on_click = function()
            is_history_mode = not is_history_mode
            if current_chat_num then
                open_chat(current_chat_num)
            end
        end
    })
    airui.label({
        parent = history_btn,
        x = 0, y = 0,
        w = s(70), h = s(38),
        text = "历史记录",
        font_size = s(16),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 输入区
    local input_h = s(50)
    local input_area = airui.container({
        parent = page,
        x = 0, y = H - input_h,
        w = W, h = input_h,
        color = C.CARD,
        border_top_color = 0xFFE0BA,
        border_top_width = 1,
    })

    chat_input_area = input_area
    chat_input_text = airui.textarea({
        parent = input_area,
        x = s(8), y = s(8),
        w = W - s(80), h = s(34),
        text = "",
        placeholder = "输入消息",
        font_size = s(14),
        max_len = 512,
        keyboard = keyboard,
        radius = s(10),
        bg_color = 0xFFFFFF,
        border_color = C.BORDER,
        border_width = 1,
    })

    local send_btn = airui.container({
        parent = input_area,
        x = W - s(68), y = s(8),
        w = s(60), h = s(34),
        color = C.PRIMARY,
        radius = s(10),
        on_click = function()
            local text = chat_input_text and chat_input_text:get_text() or ""
            text = string.gsub(text, "^%s*(.-)%s*$", "%1")
            if text == "" then return end

            local tm = now_time()
            sip_data.add_message(current_chat_num, "out", tm, text)

            -- 通过 SIP 发送消息
            sip_service.send_message(current_chat_num, text)

            if chat_input_text then
                chat_input_text:set_text("")
            end

            is_history_mode = false
            open_chat(current_chat_num)
            refresh_chats()
        end
    })
    airui.label({
        parent = send_btn,
        x = 0, y = 0,
        w = s(60), h = s(34),
        text = "发送",
        font_size = s(13),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- ==================== 新建消息表单 ====================
    new_chat_form = airui.container({
        parent = page,
        x = 0, y = s(48),
        w = W, h = H - s(48),
        color = C.BG,
        scrollable = true,
    })
    new_chat_form:hide()

    local form_y = s(10)

    -- 对方号码
    airui.label({
        parent = new_chat_form,
        x = s(15), y = form_y,
        w = W - s(30), h = s(18),
        text = "对方号码",
        font_size = s(12),
        color = C.TEXT,
    })
    form_y = form_y + s(20)

    new_chat_num_input = airui.textarea({
        parent = new_chat_form,
        x = s(15), y = form_y,
        w = W - s(30), h = s(36),
        text = "",
        placeholder = "输入对方号码",
        font_size = s(14),
        max_len = 64,
        keyboard = keyboard,
        radius = s(10),
        bg_color = 0xFFFFFF,
        border_color = C.BORDER,
        border_width = 1,
    })
    form_y = form_y + s(42)

    -- 确定按钮
    local confirm_btn = airui.container({
        parent = new_chat_form,
        x = s(15), y = form_y,
        w = s(80), h = s(32),
        color = C.PRIMARY,
        radius = s(6),
        on_click = function()
            local num = new_chat_num_input and new_chat_num_input:get_text() or ""
            num = string.gsub(num, "^%s*(.-)%s*$", "%1")
            if num == "" then
                toast("请输入对方号码")
                return
            end
            toast("请输入消息内容")
        end
    })
    airui.label({
        parent = confirm_btn,
        x = 0, y = 0,
        w = s(80), h = s(32),
        text = "确定",
        font_size = s(13),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    form_y = form_y + s(42)

    -- 消息内容
    airui.label({
        parent = new_chat_form,
        x = s(15), y = form_y,
        w = W - s(30), h = s(18),
        text = "消息内容",
        font_size = s(12),
        color = C.TEXT,
    })
    form_y = form_y + s(20)

    new_chat_content_input = airui.textarea({
        parent = new_chat_form,
        x = s(15), y = form_y,
        w = W - s(30), h = s(50),
        text = "",
        placeholder = "输入消息内容",
        font_size = s(14),
        max_len = 512,
        keyboard = keyboard,
        radius = s(10),
        bg_color = 0xFFFFFF,
        border_color = C.BORDER,
        border_width = 1,
    })
    form_y = form_y + s(56)

    -- 发送按钮
    local new_send_btn = airui.container({
        parent = new_chat_form,
        x = W - s(85), y = form_y,
        w = s(70), h = s(32),
        color = C.PRIMARY,
        radius = s(6),
        on_click = function()
            local num = new_chat_num_input and new_chat_num_input:get_text() or ""
            num = string.gsub(num, "^%s*(.-)%s*$", "%1")
            if num == "" then
                toast("请输入对方号码")
                return
            end
            local text = new_chat_content_input and new_chat_content_input:get_text() or ""
            text = string.gsub(text, "^%s*(.-)%s*$", "%1")
            if text == "" then
                toast("请输入消息内容")
                return
            end
            local tm = now_time()
            sip_data.add_message(num, "out", tm, text)
            sip_service.send_message(num, text)
            if new_chat_num_input then new_chat_num_input:set_text("") end
            if new_chat_content_input then new_chat_content_input:set_text("") end
            if new_chat_form then new_chat_form:hide() end
            open_chat(num)
            refresh_chats()
        end
    })
    airui.label({
        parent = new_send_btn,
        x = 0, y = 0,
        w = s(70), h = s(32),
        text = "发送",
        font_size = s(13),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

end

-- ==================== SIP 事件订阅 ====================
sys.subscribe("SIP_EVT_REGISTER_OK", function(data)
    log.info("sip_win", "注册成功")
    sip_config.set_logged_in(true)
    login_in_progress = false
    if login_timeout_timer then
        sys.timerStop(login_timeout_timer)
        login_timeout_timer = nil
    end
    if progress_timer then
        sys.timerStop(progress_timer)
        progress_timer = nil
    end
    if progress_bar then progress_bar:set_value(100, true) end
    if progress_label then progress_label:set_text("100%") end
    if is_auto_login then
        -- 自动登录流程：停顿500ms后切页
        sys.timerStart(function()
            local auto_account = sip_config.get_auto_account()
            local contact_num = tostring(tonumber(auto_account.sip_username) + 1)
            sip_data.add_contact(contact_num, "SIP通话测试")
            contacts = sip_data.get_contacts()
            refresh_contacts()
            show_app_tab("contacts")
            is_auto_login = false
        end, 500)
    else
        toast("登录成功")
        -- 从登录页自动进入app
        sys.timerStart(function()
            show_app_tab("contacts")
        end, 500)
    end
end)

sys.subscribe("SIP_EVT_REGISTER_FAILED", function(data)
    log.error("sip_win", "注册失败")
    sip_config.set_logged_in(false)
    login_in_progress = false
end)

sys.subscribe("SIP_EVT_INCOMING", function(from_num)
    log.info("sip_win", "来电:", from_num)
    local name = sip_data.get_contact_name(from_num) or from_num
    show_incoming_screen(from_num, name)
end)

sys.subscribe("SIP_EVT_CONNECTED", function()
    log.info("sip_win", "通话已建立")
    call_was_answered = true
    call_seconds = 0

    if current_page == "incoming" then
        if incoming_state_label then incoming_state_label:set_text("通话中") end
        if incoming_timer_label then incoming_timer_label:set_text("00:00") end
        set_hidden_safe(incoming_answer_btn, true)
    else
        if call_status_label then call_status_label:set_text("00:00") end
    end

    if call_timer_obj then
        sys.timerStop(call_timer_obj)
    end
    call_timer_obj = sys.timerLoopStart(function()
        call_seconds = call_seconds + 1
        local tm = format_time(call_seconds)
        if current_page == "incoming" and incoming_timer_label then
            incoming_timer_label:set_text(tm)
        elseif call_status_label then
            call_status_label:set_text(tm)
        end
    end, 1000)

    -- PC 模拟器无音频提示
    if is_pc_simulator() and not voip then
        if call_sim_hint then
            call_sim_hint:set_text("当前为模拟器环境，无音频输出，真机上可正常通话")
        end
    elseif call_sim_hint then
        call_sim_hint:set_text("")
    end
end)

sys.subscribe("SIP_EVT_ENDED", function(reason)
    log.info("sip_win", "通话结束:", reason or "")
    if call_timer_obj then
        sys.timerStop(call_timer_obj)
        call_timer_obj = nil
    end

    -- 保存通话记录（仅一次）
    if not call_recorded then
        call_recorded = true
        local rtype
        if call_was_answered then
            rtype = "answered"
        elseif call_is_incoming then
            rtype = "missed"
        else
            rtype = "dialed"
        end
        if current_call_num and current_call_num ~= "" then
            sip_data.add_record("今天", rtype, current_call_num, now_time())
            refresh_records()
        end
    end

    -- 关闭拨号界面或来电弹窗
    if current_page == "incoming" then
        hide_incoming_screen()
    else
        hide_call_screen()
    end
end)

sys.subscribe("SIP_EVT_MESSAGE_RX", function(from_num, body)
    log.info("sip_win", "收到消息:", from_num, body)
    if body and string.sub(body, 1, 5) == "<?xml" then
        log.info("sip_win", "忽略 IMDN 回执")
        return
    end
    local tm = now_time()
    sip_data.add_message(from_num, "in", tm, body or "")
    refresh_chats()
    if current_page == "app" and app_subview == "chat" and current_chat_num == from_num then
        is_history_mode = false
        open_chat(from_num)
    end
    toast("新消息: " .. (body or ""))
end)

sys.subscribe("SIP_EVT_ERROR", function(action, payload)
    log.error("sip_win", "SIP 错误:", action)
    toast("SIP 错误: " .. tostring(action))
end)

-- ==================== 窗口生命周期 ====================
local function on_create()
    log.info("sip_win", "窗口创建")
    update_screen_size()
    -- 每次打开都进入欢迎界面，由用户手动登录
    -- 避免模块重载后 SIP 状态混乱导致的"正在注册中"问题
    create_keyboard()

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = W, h = H,
        color = C.BG,
    })

    -- 创建所有页面
    create_page_welcome()
    create_page_login()
    create_page_app()
    create_page_chat()
    create_call_screen()
    create_incoming_screen()
    create_page_progress()
    create_tab_views()

    -- 每次打开都进入欢迎界面，由用户手动登录
    show_page("welcome")

    -- 刷新数据
    refresh_contacts()
    refresh_records()
    refresh_chats()
end

local function on_destroy()
    log.info("sip_win", "窗口销毁")
    if call_timer_obj then
        sys.timerStop(call_timer_obj)
        call_timer_obj = nil
    end
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if progress_timer then
        sys.timerStop(progress_timer)
        progress_timer = nil
    end
    if keyboard then
        keyboard:destroy()
        keyboard = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    pages = {}
    ui_refs = {}
    toast_dialog = nil
end

local function on_get_focus()
    log.info("sip_win", "窗口获得焦点")
end

local function on_lose_focus()
    log.info("sip_win", "窗口失去焦点")
end

-- ==================== 打开窗口 ====================
local function open_handler()
    log.info("sip_win", "打开窗口")
    if win_id then
        exwin.toFront(win_id)
    else
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end

sys.subscribe("OPEN_SIP_WIN", open_handler)
log.info("sip_win", "已订阅 OPEN_SIP_WIN")
