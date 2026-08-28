--[[
@module  factory_win
@summary 应用工厂-语音生成APP窗口（录音→生成→自动安装→打开）
@version 4.1
@date    2026.08.15
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
订阅: FACTORY_MAKE_INSTALL_STATUS → 安装过程提示（下载/解压中）
订阅: FACTORY_MAKE_INSTALL_DONE   → 安装完成（携带APP路径，自动打开后关闭本窗口）
订阅: FACTORY_MAKE_INSTALL_ERROR  → 安装/打开失败
发布: FACTORY_REC_SETUP      → 初始化音频（进入时）
发布: FACTORY_REC_START      → 开始录音
发布: FACTORY_REC_STOP       → 停止录音
发布: FACTORY_MAKE_SEND      → 发送录音生成应用
发布: FACTORY_MAKE_INSTALL   → 安装已生成的APP（携带链接）
发布: FACTORY_REC_RESET      → 清理下电（退出时）

设计要点:
- 进入窗口 on_create 时初始化音频驱动（进APP开关，不常开），
  初始化期间先在消息区显示"正在初始化音频..."，减少使用者焦虑感
- 退出窗口 on_destroy 时停止+下电
- 中间为消息区（airui.table 单列，新消息自动滚到底部）
- 底部为录音/停止 + 生成按钮，录音时显示计时
- 生成任务运行中每 interval 秒轮询，消息区显示进度 history
- 生成成功(status=2)后【自动下载安装并打开】生成的 APP：
  直接发布 FACTORY_MAKE_INSTALL 触发安装，安装成功由业务层打开 APP，
  本窗口收到 FACTORY_MAKE_INSTALL_DONE 后自动关闭，无需用户确认
]]

local window_id = nil
local main_container = nil

local screen_w, screen_h = 480, 800
local margin = 12

-- 消息区组件
local msg_table = nil
local msg_rows = 0          -- 已插入的消息行数
local last_row_h = 44       -- 消息行高
local init_row = nil        -- "正在初始化音频..."提示所在行（就地更新结果）

-- 底部控件
local timer_label = nil
local rec_btn = nil
local send_btn = nil
local textarea = nil
local keyboard = nil
local input_text = ""  -- STT 识别结果缓存

local current_state = "idle"     -- idle/recording
local generating = false         -- 是否正在生成应用（轮询中）
local installing = false         -- 是否正在自动下载安装生成的 APP
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
    if installing then
        rec_btn:set_disabled(true)
        send_btn:set_disabled(true)
        send_btn:set_text("安装中...")
        return
    end
    -- 生成成功有链接时，右侧按钮变为「安装」
    if make_link then
        rec_btn:set_disabled(false)
        rec_btn:set_text("录音")
        set_btn_style(rec_btn, COLOR_PRIMARY, COLOR_WHITE)
        send_btn:set_disabled(false)
        send_btn:set_text("安装")
        set_btn_style(send_btn, COLOR_GREEN, COLOR_WHITE)
        return
    end
    rec_btn:set_disabled(false)
    if current_state == "recording" then
        -- 录音中：按钮可点击停止，最长 30 秒自动停止
        rec_btn:set_text("停止")
        rec_btn:set_disabled(false)
        set_btn_style(rec_btn, COLOR_DANGER, COLOR_WHITE)
        send_btn:set_disabled(true)
    else
        rec_btn:set_text("录音")
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

-- 服务端 history 条目净化：
-- 1. 去掉行首时间戳前缀（"2026-08-15 12:14:23 309 创建新的任务" → "创建新的任务"）
-- 2. 过滤机器内部日志（Agent 内部步骤、AppEntity 对象 dump、纯 URL、项目编号等机器细节）
-- 返回 nil 表示该条目不显示，否则返回净化后的文本
local function sanitize_history_item(item)
    if type(item) == "table" then
        item = item.msg or item.text or ""
    end
    if type(item) ~= "string" then return nil end
    -- 去掉行首时间戳前缀（日期 时间 序号）
    local text = item:gsub("^%d+-%d+-%d+ %d+:%d+:%d+ %d+ ", "")
    -- 去掉纯 URL 行（下载链接不展示给用户，安装流程会自动处理）
    if text:match("^https?://") then return nil end
    -- 过滤机器内部日志（Agent 流程细节 / AppEntity 对象 dump / 项目编号）
    local internal_keywords = {
        "创建新的任务",
        "向Agent获取签名信息",
        "准备下发任务",
        "AppEntity",
        "项目编号",
    }
    for _, kw in ipairs(internal_keywords) do
        if text:find(kw, 1, true) then
            return nil
        end
    end
    if text == "" then return nil end
    return text
end

-- 音频初始化结果：就地更新"正在初始化音频..."一行的文本，避免追加多余行
local function on_ready(ok, msg)
    local text = ok and "音频就绪" or ("音频初始化失败: " .. tostring(msg or "未知错误"))
    if init_row and msg_table then
        msg_table:set_cell_text(init_row, 0, text)
        msg_table:set_row_height(init_row, calc_msg_height(text))
        init_row = nil
    else
        append_msg(text, true)
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
        if has_record and data.path then
            -- 录音完成，自动 STT
            sys.taskInit(function()
                append_msg("语音识别中...", true)
                local ASR_URL = "https://api.luatos.com/engine/asr/v1/audio/transcriptions"
                local pub_key = io.readFile("/luadb/public.pem")
                if not pub_key then append_msg("鉴权失败(缺公钥)", true); return end
                local model = rtos.bsp()
                local devid = ""
                if model:find("Air1601") or model:find("Air1602") or model:find("PC") then devid = mcu.unique_id() or "PC"
                elseif model:find("Air8101") or model:find("Air6205") then devid = wlan.getMac() or ""
                elseif model:find("Air780E") or model:find("Air8000") then devid = mobile.imei() or "0"
                else devid = mcu.unique_id() or "unknown" end
                local ts = tostring(os.time())
                local ok, cipher = pcall(rsa.encrypt, pub_key, ts .. "," .. ts .. "," .. devid)
                if not ok or not cipher then append_msg("鉴权失败(rsa)", true); return end
                local ak = string.toBase64(cipher) or ""
                if ak == "" then append_msg("鉴权失败(Base64)", true); return end
                local headers = { ["app-key"] = ak }
                local bd = "----WebKitFormBoundary" .. tostring(os.time())
                headers["Content-Type"] = "multipart/form-data; boundary=" .. bd
                local body = { "--" .. bd .. "\r\n", "Content-Disposition: form-data; name=\"file\"; filename=\"record.amr\"\r\n", "Content-Type: audio/amr\r\n\r\n" }
                local fdata = io.readFile(data.path)
                if not fdata then append_msg("读取录音失败", true); return end
                body[#body + 1] = fdata; body[#body + 1] = "\r\n--" .. bd .. "--\r\n"
                local code, _, rb = http.request("POST", ASR_URL, headers, table.concat(body), { timeout = 30000 }).wait()
                if code ~= 200 then append_msg("识别失败(" .. tostring(code) .. ")", true); return end
                local rok, resp = pcall(json.decode, rb)
                if not rok or type(resp) ~= "table" or resp.code ~= 0 then append_msg("识别结果解析失败", true); return end
                local text = (type(resp.value) == "table" and resp.value.text) or ""
                if text ~= "" then
                    if textarea then textarea:set_text(text) end
                    append_msg("识别完成，请编辑后点击生成", true)
                else
                    append_msg("未识别到文字", true)
                end
            end)
        end
    end
    update_controls()
end

local function on_make_status(data)
    if not data then return end
    local status = tonumber(data.status) or 1
    -- 展示新增的 history 进度（避免重复追加；净化后仅显示用户关心的进度）
    local history = data.history
    if type(history) == "table" then
        for i = history_shown + 1, #history do
            local text = sanitize_history_item(history[i])
            if text then
                append_msg(text, true)
            end
        end
        history_shown = #history
    elseif type(history) == "string" and history ~= "" and history_shown == 0 then
        local text = sanitize_history_item(history)
        if text then
            append_msg(text, true)
        end
        history_shown = 1
    end

    if status == 1 then
        -- 运行中
        generating = true
        update_controls()
    elseif status == 2 then
        -- 结束并成功：自动下载安装并打开生成的 APP
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
            append_msg("正在自动下载安装...", true)
            -- 生成成功即自动安装，无需用户确认
            installing = true
            update_controls()
            sys.publish("FACTORY_MAKE_INSTALL", link_txt)
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

-- 安装过程进度（下载中 xx% / 解压中 / 安装完成）
local function on_make_install_status(text)
    if text and text ~= "" then
        append_msg(text, true)
    end
end

-- 安装完成：业务层已自动打开生成的 APP，本窗口显示提示后关闭
local function on_make_install_done(data)
    installing = false
    update_controls()
    append_msg("安装完成，正在打开应用...", true)
    -- 延迟关闭本窗口，让新应用先展示
    sys.timerStart(function()
        if window_id then exwin.close(window_id) end
    end, 800)
end

local function on_make_error(err)
    generating = false
    installing = false
    update_controls()
    append_msg("生成失败: " .. tostring(err or "未知错误"), true)
end

-- 安装失败（业务层 FACTORY_MAKE_INSTALL_ERROR 转发）
local function on_make_install_error(err)
    installing = false
    update_controls()
    append_msg("安装失败: " .. tostring(err or "未知错误"), true)
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
    local bottom_h = math.floor(90 * _G.density_scale)
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

    -- ===== 底部操作栏（录音 | 输入框 | 生成）=====
    local bar = airui.container({
        parent = main_container,
        x = 0, y = screen_h - bottom_h,
        w = screen_w, h = bottom_h,
        color = COLOR_CARD,
    })

    local d = _G.density_scale
    -- 计时（录音中显示）
    timer_label = airui.label({
        parent = bar, x = 0, y = math.floor(2 * d),
        w = screen_w, h = math.floor(18 * d),
        text = "", font_size = math.floor(12 * d),
        color = COLOR_DANGER, align = airui.TEXT_ALIGN_CENTER,
    })

    pcall(function()
        keyboard = airui.keyboard({ x = 0, y = -math.floor(20 * d), w = screen_w, h = math.floor(180 * d),
            mode = "text", auto_hide = true, preview = true, on_commit = function(self) self:hide() end })
    end)

    local rec_w = math.floor(48 * d)
    local gen_w = math.floor(48 * d)
    local gap = math.floor(4 * d)
    local ta_w = screen_w - 2 * margin - rec_w - gen_w - 2 * gap
    local ta_h = math.floor(36 * d)
    local row_y = math.floor(22 * d)

    rec_btn = airui.button({
        parent = bar, x = margin, y = row_y, w = rec_w, h = ta_h,
        text = "录音", font_size = math.floor(13 * d),
        style = { bg_color = COLOR_PRIMARY, text_color = COLOR_WHITE, border_width = 0, radius = 8 },
        on_click = function()
            if generating or installing then return end
            if current_state == "recording" then
                sys.publish("FACTORY_REC_STOP")
            else
                sys.publish("FACTORY_REC_START")
            end
        end,
    })

    textarea = airui.textarea({
        parent = bar, x = margin + rec_w + gap, y = row_y, w = ta_w, h = ta_h,
        text = "", placeholder = "录音后文字出现在这里...",
        font_size = math.floor(16 * d), max_len = 500, keyboard = keyboard,
    })

    send_btn = airui.button({
        parent = bar, x = margin + rec_w + gap + ta_w + gap, y = row_y, w = gen_w, h = ta_h,
        text = "生成", font_size = math.floor(13 * d),
        style = { bg_color = COLOR_GREEN, text_color = COLOR_WHITE, border_width = 0, radius = 8 },
        on_click = function()
            if generating or installing then return end
            if keyboard then keyboard:hide() end
            -- 已有安装链接：点击安装
            if make_link then
                local link_txt = ""
                if type(make_link) == "table" then link_txt = make_link[1] or ""
                else link_txt = tostring(make_link or "") end
                if link_txt == "" then append_msg("安装链接为空", true); return end
                installing = true; update_controls()
                append_msg("开始安装生成的 APP...", true)
                sys.publish("FACTORY_MAKE_INSTALL", link_txt)
                return
            end
            -- 有输入框文字 → 走文字描述生成
            local txt = textarea and textarea:get_text() or ""
            txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
            if txt ~= "" then
                generating = true; history_shown = 0; make_link = nil
                update_controls()
                append_msg("正在用文字描述生成APP...", true)
                sys.publish("FACTORY_MAKE_SEND_TEXT", txt)
                return
            end
            -- 有录音 → 走录音文件生成
            if not has_record then
                append_msg("请先录音或输入文字描述", true)
                return
            end
            generating = true; history_shown = 0; make_link = nil
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
    installing = false
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
    sys.subscribe("FACTORY_MAKE_INSTALL_STATUS", on_make_install_status)
    sys.subscribe("FACTORY_MAKE_INSTALL_DONE", on_make_install_done)
    sys.subscribe("FACTORY_MAKE_INSTALL_ERROR", on_make_install_error)
    -- 音频未就绪前先显示初始化提示，减少使用者焦虑感
    -- 首条消息即初始化提示，记录行号供 on_ready 就地更新结果
    append_msg("正在初始化音频...", true)
    init_row = (msg_rows == 1) and 0 or nil
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
    sys.unsubscribe("FACTORY_MAKE_INSTALL_STATUS", on_make_install_status)
    sys.unsubscribe("FACTORY_MAKE_INSTALL_DONE", on_make_install_done)
    sys.unsubscribe("FACTORY_MAKE_INSTALL_ERROR", on_make_install_error)
    -- 退出时停止录音 + 下电 + 删临时文件
    sys.publish("FACTORY_REC_RESET")
    if keyboard then pcall(keyboard.destroy, keyboard); keyboard = nil end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    msg_table = nil; textarea = nil
    init_row = nil
    timer_label = nil
    rec_btn = nil
    send_btn = nil
    current_state = "idle"
    generating = false
    installing = false
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
