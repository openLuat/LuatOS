--[[
@module  factory_rec_win
@summary 应用工厂-语音生成APP窗口（UI层）
@version 2.0
@date    2026.08.26
@author  江访

消息协议:
订阅: OPEN_FACTORY_REC_WIN   → 创建窗口
订阅: FACTORY_REC_READY      → 音频初始化结果
订阅: FACTORY_REC_STATE      → 状态变更 idle/recording
订阅: FACTORY_REC_STATUS     → 提示文本
订阅: FACTORY_REC_DONE       → 录音完成（触发 STT）
订阅: FACTORY_MAKE_STATUS    → 生成任务进度
订阅: FACTORY_MAKE_ERROR     → 生成失败
订阅: FACTORY_MAKE_INSTALL_STATUS → 安装进度
订阅: FACTORY_MAKE_INSTALL_DONE   → 安装完成
订阅: FACTORY_MAKE_INSTALL_ERROR  → 安装失败
发布: FACTORY_REC_SETUP      → 初始化音频
发布: FACTORY_REC_START      → 开始录音
发布: FACTORY_REC_STOP       → 停止录音
发布: FACTORY_MAKE_SEND      → 发送生成请求
发布: FACTORY_REC_RESET      → 清理
]]

local window_id = nil
local main_container = nil

-- UI 组件
local textarea = nil
local keyboard = nil
local rec_btn = nil
local gen_btn = nil
local status_label = nil
local timer_label = nil

-- 状态
local current_state = "idle"
local is_generating = false

-- 屏幕
local screen_w, screen_h = 480, 800
local margin = 12

-- 颜色
local COLOR_PRIMARY      = 0x007AFF
local COLOR_BG           = 0xF5F5F5
local COLOR_CARD         = 0xFFFFFF
local COLOR_TEXT         = 0x333333
local COLOR_TEXT_SEC     = 0x757575
local COLOR_DIVIDER      = 0xE0E0E0
local COLOR_WHITE        = 0xFFFFFF
local COLOR_DANGER       = 0xE63946
local COLOR_GREEN        = 0x34C759

local function update_screen_size()
    local r = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if r == 0 or r == 180 then screen_w, screen_h = pw, ph
    else screen_w, screen_h = ph, pw end
    margin = math.floor(screen_w * 0.025)
end

-- ==================== STT（语音转文字） ====================

local ASR_URL = "https://api.luatos.com/engine/asr/v1/audio/transcriptions"

local function asr_auth_headers()
    local pub_key = io.readFile("/luadb/public.pem")
    if not pub_key then return nil end
    local model = rtos.bsp()
    local devid = ""
    if model:find("Air1601") or model:find("Air1602") or model:find("PC") then
        devid = mcu.unique_id() or "PC"
    elseif model:find("Air8101") or model:find("Air6205") then
        devid = wlan.getMac() or ""
    elseif model:find("Air780E") or model:find("Air8000") then
        devid = mobile.imei() or "0"
    else
        devid = mcu.unique_id() or "unknown"
    end
    local ts = tostring(os.time())
    local ok, cipher = pcall(rsa.encrypt, pub_key, ts .. "," .. ts .. "," .. devid)
    if not ok or not cipher then return nil end
    local ak = string.toBase64(cipher) or ""
    if ak == "" then return nil end
    return { ["app-key"] = ak }
end

local function request_stt(file_path)
    if not file_path or not io.exists(file_path) then
        if status_label then status_label:set_text("录音文件无效") end
        return
    end
    if (io.fileSize(file_path) or 0) <= 0 then
        if status_label then status_label:set_text("录音文件为空") end
        return
    end
    if not socket.localIP() then
        if status_label then status_label:set_text("网络未连接") end
        return
    end
    local headers = asr_auth_headers()
    if not headers then
        if status_label then status_label:set_text("鉴权失败") end
        return
    end
    local bd = "----WebKitFormBoundary" .. tostring(os.time())
    headers["Content-Type"] = "multipart/form-data; boundary=" .. bd
    local body = {
        "--" .. bd .. "\r\n",
        "Content-Disposition: form-data; name=\"file\"; filename=\"record.amr\"\r\n",
        "Content-Type: audio/amr\r\n\r\n",
    }
    local fdata = io.readFile(file_path)
    if not fdata then
        if status_label then status_label:set_text("读取录音失败") end
        return
    end
    body[#body + 1] = fdata
    body[#body + 1] = "\r\n--" .. bd .. "--\r\n"
    if status_label then status_label:set_text("语音识别中...") end
    local code, _, rb = http.request("POST", ASR_URL, headers, table.concat(body), { timeout = 30000 }).wait()
    if code ~= 200 then
        if status_label then status_label:set_text("识别失败(" .. tostring(code) .. ")") end
        return
    end
    local ok, resp = pcall(json.decode, rb)
    if not ok or type(resp) ~= "table" or resp.code ~= 0 then
        if status_label then status_label:set_text("识别结果解析失败") end
        return
    end
    local text = (type(resp.value) == "table" and resp.value.text) or ""
    if text ~= "" then
        if textarea then textarea:set_text(text) end
        if status_label then status_label:set_text("识别完成，请编辑后点击生成") end
    else
        if status_label then status_label:set_text("未识别到文字") end
    end
end

-- ==================== 按钮状态 ====================

local function set_btn_style(btn, bg, fg)
    if btn then btn:set_style({ bg_color = bg, text_color = fg }) end
end

local function update_rec_btn()
    if not rec_btn then return end
    if current_state == "recording" then
        rec_btn:set_text("停止")
        set_btn_style(rec_btn, COLOR_DANGER, COLOR_WHITE)
    else
        rec_btn:set_text("录音")
        set_btn_style(rec_btn, COLOR_PRIMARY, COLOR_WHITE)
    end
end

local function update_gen_btn()
    if not gen_btn then return end
    if is_generating then
        gen_btn:set_disabled(true)
        gen_btn:set_text("生成中...")
        set_btn_style(gen_btn, COLOR_DIVIDER, COLOR_TEXT_SEC)
    else
        gen_btn:set_disabled(false)
        gen_btn:set_text("生成")
        set_btn_style(gen_btn, COLOR_GREEN, COLOR_WHITE)
    end
end

-- ==================== 事件回调 ====================

local function on_ready(ok, msg)
    if status_label then
        status_label:set_text(ok and "音频就绪" or (msg or "音频初始化失败"))
    end
end

local function on_state(data)
    if data and data.state then
        current_state = data.state
        update_rec_btn()
    end
end

local function on_status(msg)
    if status_label and msg then status_label:set_text(msg) end
end

local function on_rec_done(data)
    current_state = "idle"
    update_rec_btn()
    if data and data.size and data.size > 0 and data.path then
        sys.taskInit(function() request_stt(data.path) end)
    else
        if status_label then status_label:set_text("录音无效") end
    end
end

local function on_make_status(data)
    if not data then return end
    if data.status == 1 then
        is_generating = true
        update_gen_btn()
        if status_label then
            local h = data.history
            local last = type(h) == "table" and h[#h] or tostring(h or "")
            status_label:set_text("生成中: " .. last)
        end
    elseif data.status == 2 then
        is_generating = false
        update_gen_btn()
        if status_label then status_label:set_text("生成完成，准备安装...") end
    elseif data.status == 3 then
        is_generating = false
        update_gen_btn()
        if status_label then status_label:set_text("生成失败") end
    end
end

local function on_make_error(msg)
    is_generating = false
    update_gen_btn()
    if status_label then status_label:set_text("错误: " .. tostring(msg or "")) end
end

local function on_install_status(text)
    if status_label and text then status_label:set_text(text) end
end

local function on_install_done(data)
    is_generating = false
    update_gen_btn()
    if status_label then status_label:set_text("安装完成，正在打开...") end
end

local function on_install_error(msg)
    is_generating = false
    update_gen_btn()
    if status_label then status_label:set_text("安装失败: " .. tostring(msg or "")) end
end

-- ==================== UI 构建 ====================

local function build_ui()
    update_screen_size()
    local d = _G.density_scale or 1.0
    local tb_h = math.floor(48 * d)
    local tb_y = math.floor(4 * d)

    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h, color = COLOR_BG })

    -- 标题栏
    local titlebar = airui.container({ parent = main_container, x = 0, y = 0, w = screen_w, h = tb_h, color = COLOR_PRIMARY })
    airui.button({ parent = titlebar, x = margin, y = tb_y, w = math.floor(55 * d), h = math.floor(34 * d),
        text = "返回", font_size = math.floor(15 * d),
        style = { bg_color = COLOR_PRIMARY, text_color = COLOR_WHITE, border_width = 0, radius = 8 },
        on_click = function() if window_id then exwin.close(window_id) end end })
    airui.label({ parent = titlebar, x = math.floor(70 * d), y = tb_y, w = math.floor(screen_w - 140 * d), h = math.floor(34 * d),
        text = "语音生成APP", font_size = math.floor(18 * d), color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })

    -- 状态提示
    local status_y = tb_h + math.floor(8 * d)
    status_label = airui.label({ parent = main_container, x = margin, y = status_y,
        w = screen_w - 2 * margin, h = math.floor(24 * d),
        text = "录音后自动识别文字，可编辑后点击生成", font_size = math.floor(12 * d),
        color = COLOR_TEXT_SEC, align = airui.TEXT_ALIGN_CENTER })

    -- 说明区
    local info_y = status_y + math.floor(28 * d)
    local info_h = screen_h - tb_h - math.floor(90 * d) - math.floor(50 * d) - math.floor(28 * d)
    airui.label({ parent = main_container, x = margin, y = info_y, w = screen_w - 2 * margin, h = info_h,
        text = "使用方法：\n\n1. 点击「录音」按钮开始录音\n2. 再次点击停止录音\n3. 自动识别语音文字\n4. 可编辑识别结果\n5. 点击「生成」按钮生成APP",
        font_size = math.floor(14 * d), color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 输入区
    local input_area_h = math.floor(90 * d)
    local input_y = screen_h - input_area_h
    local input_area = airui.container({ parent = main_container, x = 0, y = input_y, w = screen_w, h = input_area_h, color = COLOR_CARD })

    pcall(function()
        keyboard = airui.keyboard({ x = 0, y = -math.floor(20 * d), w = screen_w, h = math.floor(180 * d),
            mode = "text", auto_hide = true, preview = true, on_commit = function(self) self:hide() end })
    end)

    local rec_w = math.floor(48 * d)
    local gen_w = math.floor(48 * d)
    local gap = math.floor(4 * d)
    local ta_w = screen_w - 2 * margin - rec_w - gen_w - 2 * gap
    local ta_h = math.floor(36 * d)
    local ta_y = math.floor(6 * d)

    rec_btn = airui.button({ parent = input_area, x = margin, y = ta_y, w = rec_w, h = ta_h,
        text = "录音", font_size = math.floor(13 * d),
        style = { bg_color = COLOR_PRIMARY, text_color = COLOR_WHITE, border_width = 0, radius = 8 },
        on_click = function()
            if current_state == "recording" then
                sys.publish("FACTORY_REC_STOP")
            else
                sys.publish("FACTORY_REC_START")
            end
        end })

    textarea = airui.textarea({ parent = input_area, x = margin + rec_w + gap, y = ta_y, w = ta_w, h = ta_h,
        text = "", placeholder = "录音后文字出现在这里...", font_size = math.floor(16 * d), max_len = 500, keyboard = keyboard })

    gen_btn = airui.button({ parent = input_area, x = margin + rec_w + gap + ta_w + gap, y = ta_y, w = gen_w, h = ta_h,
        text = "生成", font_size = math.floor(13 * d),
        style = { bg_color = COLOR_GREEN, text_color = COLOR_WHITE, border_width = 0, radius = 8 },
        on_click = function()
            if is_generating then return end
            if keyboard then keyboard:hide() end
            local text = textarea and textarea:get_text() or ""
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            if text == "" then
                if status_label then status_label:set_text("请输入或录音识别文字描述") end
                return
            end
            -- 文字描述走 description 字段，不走 file 字段
            is_generating = true
            update_gen_btn()
            sys.publish("FACTORY_MAKE_SEND_TEXT", text)
        end })

    -- 计时显示（录音中显示）
    local timer_y = ta_y + ta_h + math.floor(4 * d)
    timer_label = airui.label({ parent = input_area, x = margin, y = timer_y,
        w = screen_w - 2 * margin, h = math.floor(22 * d),
        text = "", font_size = math.floor(12 * d), color = COLOR_DANGER, align = airui.TEXT_ALIGN_CENTER })

    update_rec_btn(); update_gen_btn()
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    current_state = "idle"; is_generating = false
    sys.subscribe("FACTORY_REC_READY", on_ready)
    sys.subscribe("FACTORY_REC_STATE", on_state)
    sys.subscribe("FACTORY_REC_STATUS", on_status)
    sys.subscribe("FACTORY_REC_DONE", on_rec_done)
    sys.subscribe("FACTORY_MAKE_STATUS", on_make_status)
    sys.subscribe("FACTORY_MAKE_ERROR", on_make_error)
    sys.subscribe("FACTORY_MAKE_INSTALL_STATUS", on_install_status)
    sys.subscribe("FACTORY_MAKE_INSTALL_DONE", on_install_done)
    sys.subscribe("FACTORY_MAKE_INSTALL_ERROR", on_install_error)
    sys.publish("FACTORY_REC_SETUP")
end

local function on_destroy()
    sys.publish("FACTORY_REC_RESET")
    sys.unsubscribe("FACTORY_REC_READY", on_ready)
    sys.unsubscribe("FACTORY_REC_STATE", on_state)
    sys.unsubscribe("FACTORY_REC_STATUS", on_status)
    sys.unsubscribe("FACTORY_REC_DONE", on_rec_done)
    sys.unsubscribe("FACTORY_MAKE_STATUS", on_make_status)
    sys.unsubscribe("FACTORY_MAKE_ERROR", on_make_error)
    sys.unsubscribe("FACTORY_MAKE_INSTALL_STATUS", on_install_status)
    sys.unsubscribe("FACTORY_MAKE_INSTALL_DONE", on_install_done)
    sys.unsubscribe("FACTORY_MAKE_INSTALL_ERROR", on_install_error)
    if keyboard then pcall(keyboard.destroy, keyboard); keyboard = nil end
    if main_container then main_container:destroy(); main_container = nil end
    textarea = nil; rec_btn = nil; gen_btn = nil; status_label = nil; timer_label = nil
    current_state = "idle"; is_generating = false
    window_id = nil
end

local function ongf() end
local function onlf() end

local function open_handler()
    window_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_get_focus = ongf, on_lose_focus = onlf })
end

sys.subscribe("OPEN_FACTORY_REC_WIN", open_handler)
