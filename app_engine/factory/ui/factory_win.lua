--[[
@module  factory_win
@summary 应用工厂-语音生成APP窗口（录音→生成→安装）
@version 4.0
@date    2026.08.13
@author  江访

消息协议:
订阅: OPEN_APP_FACTORY_WIN   → 创建应用工厂窗口
订阅: FACTORY_REC_READY      → 音频初始化结果
订阅: FACTORY_REC_STATE      → 状态变更 idle/recording
订阅: FACTORY_REC_STATUS     → 提示文本
订阅: FACTORY_REC_DURATION   → 录音计时
订阅: FACTORY_REC_DONE       → 录音完成（含文件/时长）
订阅: FACTORY_MAKE_STATUS    → 应用生成任务进度（status: 1运行中/2成功/3失败，含history/link）
订阅: FACTORY_MAKE_ERROR     → 生成失败
发布: FACTORY_REC_SETUP      → 初始化音频（进入时）
发布: FACTORY_REC_START      → 开始录音
发布: FACTORY_REC_STOP       → 停止录音
发布: FACTORY_MAKE_SEND      → 发送录音生成应用
发布: FACTORY_MAKE_INSTALL   → 安装已生成的APP（携带链接）
发布: FACTORY_REC_RESET      → 清理下电（退出时）

设计要点:
- 进入窗口 on_create 时初始化音频驱动（进APP开关，不常开）
- 退出窗口 on_destroy 时停止+下电
- 中间为消息区（airui.table 单列，新消息自动滚到底部）
- 底部为录音/停止 + 生成按钮，录音时显示计时
- 生成任务运行中每 interval 秒轮询，消息区显示进度 history
- 生成成功后在消息区显示安装链接，弹确认框后调用 exapp.install_remote_app 安装
]]

local window_id = nil
local main_container = nil

local screen_w, screen_h = 480, 800
local margin = 12

-- 消息区组件
local msg_table = nil
local msg_rows = 0          -- 已插入的消息行数
local last_row_h = 44       -- 消息行高

-- 底部控件
local timer_label = nil
local rec_btn = nil
local send_btn = nil

local current_state = "idle"     -- idle/recording
local generating = false         -- 是否正在生成应用（轮询中）
local has_record = false         -- 是否有可发送的录音
local make_link = nil            -- 生成成功的安装链接
local history_shown = 0         -- 已显示的 history 条数（避免重复追加进度）

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946
local COLOR_GREEN          = 0x34C759

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.025)
end

-- ==================== 按钮状态管理 ====================

local function set_btn_style(btn, bg, fg)
    if not btn then return end
    btn:set_style({ bg_color = bg, text_color = fg })
end

local function update_controls()
    if not rec_btn or not send_btn then return end
    if generating then
        rec_btn:set_disabled(true)
        send_btn:set_disabled(true)
        send_btn:set_text("生成中...")
        return
    end
    -- 生成成功有链接时，右侧按钮变为「安装」
    if make_link then
        rec_btn:set_disabled(false)
        rec_btn:set_text("开始录音")
        set_btn_style(rec_btn, COLOR_PRIMARY, COLOR_WHITE)
        send_btn:set_disabled(false)
        send_btn:set_text("安装")
        set_btn_style(send_btn, COLOR_GREEN, COLOR_WHITE)
        return
    end
    rec_btn:set_disabled(false)
    if current_state == "recording" then
        -- 录音中：按钮可点击停止，最长 30 秒自动停止
        rec_btn:set_text("停止录音")
        rec_btn:set_disabled(false)
        set_btn_style(rec_btn, COLOR_DANGER, COLOR_WHITE)
        send_btn:set_disabled(true)
    else
        rec_btn:set_text("开始录音")
        set_btn_style(rec_btn, COLOR_PRIMARY, COLOR_WHITE)
        if has_record then
            send_btn:set_disabled(false)
            send_btn:set_text("生成")
            set_btn_style(send_btn, COLOR_GREEN, COLOR_WHITE)
        else
            send_btn:set_disabled(true)
            send_btn:set_text("生成")
            set_btn_style(send_btn, COLOR_DIVIDER, COLOR_TEXT_SECONDARY)
        end
    end
end

-- ==================== 消息区 ====================

-- 估算消息行高：按字符数/列宽计算换行行数，让长文本可见（进度/提示可能较长）
local function calc_msg_height(text)
    local density = _G.density_scale or 1.0
    local font_size = math.floor(22 * density)
    local usable_w = screen_w - math.floor(2 * margin)
    -- 中文字符宽度≈字号，按最坏情况（全中文）估算
    local chars_per_line = math.max(1, math.floor(usable_w / font_size))
    local lines = math.max(1, math.ceil(#text / chars_per_line))
    local h = lines * math.floor(font_size * 1.4) + math.floor(12 * density)
    -- 行高下限为默认行高，上限防止单条消息过高
    return math.max(last_row_h, math.min(h, math.floor(140 * density)))
end

-- 追加一条消息到聊天区（自动滚到底部）
local function append_msg(text, is_status)
    if not msg_table then return end
    local row
    if msg_rows == 0 then
        -- 首条消息直接使用初始行（表格最小 1 行，避免尾部空行）
        row = 0
        msg_table:set_cell_text(0, 0, text)
    else
        row = msg_rows
        msg_table:insert("row", row, { text })
    end
    local rh = calc_msg_height(text)
    msg_table:set_row_height(row, rh)
    msg_table:set_cell_style("row", row, {
        cell_text_color = is_status and COLOR_TEXT_SECONDARY or COLOR_TEXT,
        cell_bg_color = is_status and COLOR_BG or COLOR_WHITE,
    })
    msg_rows = row + 1
    -- 滚动到底部显示最新消息
    msg_table:scroll_to_row(row, false)
end

-- ==================== 事件回调 ====================

local function on_ready(ok, msg)
    if ok then
        append_msg("音频就绪", true)
    else
        append_msg(msg or "音频初始化失败", true)
    end
end

local function on_state(data)
    if not data or not data.state then return end
    current_state = data.state
    update_controls()
end

local function on_status(msg)
    if msg and msg ~= "" then
        append_msg(msg, true)
    end
end

local function on_duration(sec)
    if timer_label then
        timer_label:set_text(string.format("%02d:%02d", math.floor(sec / 60), sec % 60))
    end
end

local function on_record_done(data)
    has_record = (data and data.size and data.size > 0)
    if data then
        local sec = data.seconds or 0
        append_msg(string.format("[录音 %d 秒]", sec), true)
        if has_record then
            append_msg("点击「生成」制作 APP", true)
        end
    end
    update_controls()
end

local function on_make_status(data)
    if not data then return end
    local status = tonumber(data.status) or 1
    -- 展示新增的 history 进度（避免重复追加）
    local history = data.history
    if type(history) == "table" then
        for i = history_shown + 1, #history do
            local item = history[i]
            if type(item) == "table" then
                item = item.msg or item.text or ""
            end
            if type(item) == "string" and item ~= "" then
                append_msg(item, true)
            end
        end
        history_shown = #history
    elseif type(history) == "string" and history ~= "" and history_shown == 0 then
        append_msg(history, true)
        history_shown = 1
    end

    if status == 1 then
        -- 运行中
        generating = true
        update_controls()
    elseif status == 2 then
        -- 结束并成功
        generating = false
        make_link = data.link
        update_controls()
        local link_txt = ""
        if type(make_link) == "table" then
            link_txt = make_link[1] or ""
        else
            link_txt = tostring(make_link or "")
        end
        if link_txt ~= "" then
            append_msg("APP 生成成功", false)
            append_msg("点击下方「安装」按钮安装到设备", true)
        else
            append_msg("APP 生成成功（无安装链接）", true)
        end
    elseif status == 3 then
        -- 结束且失败
        generating = false
        make_link = nil
        update_controls()
        append_msg("APP 生成失败", true)
    end
end

local function on_make_error(err)
    generating = false
    update_controls()
    append_msg("生成失败: " .. tostring(err or "未知错误"), true)
end

-- ==================== UI 构建 ====================

local function build_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG,
    })

    local titlebar = require "settings_titlebar"
    local _, th = titlebar.create(main_container, "语音生成APP", screen_w, function()
        if window_id then exwin.close(window_id) end
    end)

    -- ===== 消息区（中间可滚动聊天区）=====
    local bottom_h = math.floor(120 * _G.density_scale)
    local msg_area_h = screen_h - th - bottom_h
    -- ⚠️ airui.table 默认 pad_all=6、border_width=1，若 col_width 设为全屏宽，
    -- 列宽+padding+border 会超过容器宽度导致内容溢出屏幕。故列宽内缩 margin 并去边框。
    local table_col_w = screen_w - math.floor(2 * margin)
    msg_table = airui.table({
        parent = main_container,
        x = 0, y = th,
        w = screen_w, h = msg_area_h,
        rows = 1, cols = 1,
        col_width = { table_col_w },
        row_height = last_row_h,
        style = {
            bg_color = COLOR_BG,
            cell_bg_color = COLOR_BG,
            cell_border_width = 0,
            border_width = 0,
            cell_text_color = COLOR_TEXT,
            cell_font_size = math.floor(22 * _G.density_scale),
            cell_text_align = airui.TEXT_ALIGN_LEFT,
        },
    })
    msg_rows = 0

    -- ===== 底部操作栏 =====
    local bar = airui.container({
        parent = main_container,
        x = 0, y = screen_h - bottom_h,
        w = screen_w, h = bottom_h,
        color = COLOR_CARD,
    })

    -- 计时显示
    timer_label = airui.label({
        parent = bar,
        x = 0, y = math.floor(8 * _G.density_scale),
        w = screen_w, h = math.floor(28 * _G.density_scale),
        text = "00:00",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 录音 / 停止 按钮
    local btn_w = math.floor((screen_w - 3 * margin) / 2)
    local btn_h = math.floor(56 * _G.density_scale)
    local btn_y = math.floor(44 * _G.density_scale)

    rec_btn = airui.button({
        parent = bar,
        x = margin, y = btn_y,
        w = btn_w, h = btn_h,
        text = "开始录音",
        font_size = math.floor(24 * _G.density_scale),
        bg_color = COLOR_PRIMARY,
        font_color = COLOR_WHITE,
        radius = 12,
        on_click = function()
            if generating then return end
            if current_state == "recording" then
                sys.publish("FACTORY_REC_STOP")
            else
                sys.publish("FACTORY_REC_START")
            end
        end,
    })

    -- 生成/安装按钮（有录音时生成 APP，生成成功后变为安装）
    -- ⚠️ airui.button 构造函数只读 style 子表字段（顶层 bg_color/font_color 不生效）；
    -- 默认样式带蓝色边框(border_color=0x1e90ff, border_width=2)，需在 style 里 border_width=0 去除
    send_btn = airui.button({
        parent = bar,
        x = margin + btn_w + margin, y = btn_y,
        w = btn_w, h = btn_h,
        text = "生成",
        font_size = math.floor(24 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            text_color = COLOR_TEXT_SECONDARY,
            border_width = 0,
            radius = 12,
        },
        on_click = function()
            if generating then return end
            -- 已有安装链接：点击安装生成的 APP
            if make_link then
                local link_txt = ""
                if type(make_link) == "table" then
                    link_txt = make_link[1] or ""
                else
                    link_txt = tostring(make_link or "")
                end
                if link_txt == "" then
                    append_msg("安装链接为空", true)
                    return
                end
                local msg_box = airui.msgbox({
                    w = math.min(400, screen_w - 80),
                    h = math.floor(screen_h * 0.28),
                    style = { text_font_size = math.floor(24 * _G.density_scale) },
                    title = "确认安装",
                    text = "是否将生成的 APP 安装到设备？",
                    buttons = { "确定", "取消" },
                    on_action = function(self, btn_label)
                        if btn_label == "确定" then
                            append_msg("开始安装生成的 APP...", true)
                            sys.publish("FACTORY_MAKE_INSTALL", link_txt)
                        end
                        self:hide()
                    end
                })
                msg_box:show()
                return
            end
            -- 正常生成流程
            if not has_record then return end
            generating = true
            history_shown = 0
            make_link = nil
            update_controls()
            append_msg("正在上传录音，创建生成任务...", true)
            sys.publish("FACTORY_MAKE_SEND")
        end,
    })

    update_controls()
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    current_state = "idle"
    generating = false
    has_record = false
    make_link = nil
    history_shown = 0
    sys.subscribe("FACTORY_REC_READY", on_ready)
    sys.subscribe("FACTORY_REC_STATE", on_state)
    sys.subscribe("FACTORY_REC_STATUS", on_status)
    sys.subscribe("FACTORY_REC_DURATION", on_duration)
    sys.subscribe("FACTORY_REC_DONE", on_record_done)
    sys.subscribe("FACTORY_MAKE_STATUS", on_make_status)
    sys.subscribe("FACTORY_MAKE_ERROR", on_make_error)
    -- 进入窗口才初始化音频驱动（进APP开关，不常开）
    sys.publish("FACTORY_REC_SETUP")
end

local function on_destroy()
    sys.unsubscribe("FACTORY_REC_READY", on_ready)
    sys.unsubscribe("FACTORY_REC_STATE", on_state)
    sys.unsubscribe("FACTORY_REC_STATUS", on_status)
    sys.unsubscribe("FACTORY_REC_DURATION", on_duration)
    sys.unsubscribe("FACTORY_REC_DONE", on_record_done)
    sys.unsubscribe("FACTORY_MAKE_STATUS", on_make_status)
    sys.unsubscribe("FACTORY_MAKE_ERROR", on_make_error)
    -- 退出时停止录音 + 下电 + 删临时文件
    sys.publish("FACTORY_REC_RESET")
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    msg_table = nil
    timer_label = nil
    rec_btn = nil
    send_btn = nil
    current_state = "idle"
    generating = false
    has_record = false
    make_link = nil
    history_shown = 0
    window_id = nil
end

local function ongf() end
local function onlf() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = ongf,
        on_lose_focus = onlf,
    })
end

sys.subscribe("OPEN_APP_FACTORY_WIN", open_handler)
