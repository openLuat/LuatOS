--[[
@module  llm_chat
@summary AI 聊天助手业务层（WebSocket + 合宙 LuatOS 后台）
@version 4.1
@date    2026.08.25
@author  江访

启动流程:
  上电 → 加载模块 → 等 IP_READY → 连接 WebSocket
  用户打开 AI 助手 → UI 订阅事件 → 直接聊天
  断线 → 自动重连
]]

local exaudio = require("exaudio")

-- ==================== 常量 ====================

local WS_URL = "wss://chat.ai.luatos.com/device/ws"
local WS_SID = "YlEBtaotCPDQsei8aQTSaFBkA2ZlZT8H"
local PING_INTERVAL = 45000
local RECONNECT_DELAY = 5000
local TTS_MAX_CHUNK = 300  -- 保留兼容
local SYSTEM_PROMPT = "你是 LuatOS 助手，一个友好且专业的智能助手。"

local FSKV_SESSION = "ai_chat_session"
local FSKV_IOT_UID = "iot_uid"

-- ==================== 前向声明 ====================

local tts_stop, tts_deinit, tts_init
local process_ws_frame, do_connect

-- ==================== 状态 ====================

local ws_client = nil
local session_id = nil
local uid = ""
local dev_id = ""
local connected = false
local current_reply = ""
local reply_pending = false
local pending_text = nil
local recv_buf = ""
local reconnecting = false  -- 重连锁：防止多次并发重连

local tts_enabled = true          -- TTS 默认开启
local tts_inited = false
local tts_audio_setup_done = false  -- 是否已执行过 exaudio.setup（仅首次 setup，后续只 RESUME）
local tts_is_v2 = false
local tts_has_play_start = false
local tts_playing = false
local page_active = true          -- AI 助手页面是否在前台（不在前台就不起播、立刻停播）
local tts_queue = {}
local tts_voice = ""
local tts_fallback_timer = nil  -- done 帧丢失兜底定时器

-- ==================== 设备信息 ====================

local function init_device_info()
    local model = rtos.bsp() or "unknown"
    local devid = hmeta.devid() or "unknown"
    dev_id = model .. "_" .. devid
end

-- ==================== IoT uid ====================

local function load_iot_uid()
    local ok, val = pcall(fskv.get, FSKV_IOT_UID)
    if ok and type(val) == "string" and val ~= "" then
        uid = val
        return true
    end
    uid = ""
    return false
end

-- ==================== session 持久化 ====================

local function save_session()
    if session_id then pcall(fskv.set, FSKV_SESSION, session_id) end
end

local function load_session()
    local ok, val = pcall(fskv.get, FSKV_SESSION)
    if ok and type(val) == "string" and val ~= "" then session_id = val; return true end
    return false
end

local function clear_session()
    session_id = nil
    pcall(fskv.set, FSKV_SESSION, "")
end

-- ==================== TTS ====================

-- 通过 exaudio.play_start 播放 TTS（统一走 exaudio 路径，兼容 DAC / ES8311 / TM8211 等所有 model）
-- 不再走旧框架 audio.tts()：旧框架在 DAC 模式下不出声（PA/DAC 通路未正确配置）
tts_play_text = function(text)
    log.info("llm_chat", "tts_play_text 调用, enabled=", tts_enabled, "len=", text and #text or 0)
    if not tts_enabled or not text or text == "" then return end
    -- 页面已不在前台（退回桌面 / 切到别的页面）：不起播，否则声音会跑到别的页面上。
    if not page_active then
        log.info("llm_chat", "AI 助手不在前台，跳过 TTS 播报")
        return
    end
    tts_stop(); if not tts_init() then log.warn("llm_chat", "TTS init 失败，放弃播放"); return end
    sys.wait(100)  -- 等 DAC/PA 硬件稳定（SHUTDOWN→setup 后上电需要时间）
    -- 这 100ms 里用户可能已经退出了 AI 助手：再查一次，别把声音播到别的页面上。
    if not page_active then
        log.info("llm_chat", "AI 助手已离开前台，取消本次 TTS 播报")
        return
    end
    tts_playing = true
    sys.publish("AI_CHAT_STATUS", "TTS 播放中")
    local done = false
    local ok = exaudio.play_start({
        type = 1, content = tts_voice .. text,
        cbfnc = function(event)
            if event == exaudio.PLAY_DONE then done = true end
        end
    })
    if ok then
        -- 起播这一瞬若已离开前台，立刻真停一次：此刻请求已登记，play_stop 能落到
        -- 驱动上；否则只能靠下面的静音分支挡，而它最多等 3s，长文本会漏声到别的页面。
        if not page_active then tts_stop() end
        local t = 0
        while not done and tts_playing and t < 30000 do
            sys.wait(100); t = t + 100
        end
        -- 被中断（关语音 / 离开 AI 助手页面）：先静音让播放自然结束，避免 I2C 死锁；
        -- 但 soft_volume 是驱动级全局增益，留在 0 会把 HZV 音轨等其它播放方一起弄哑，
        -- 所以等这一次请求真正收尾（或最多 3s）后，必须把音量还回去。
        if not done and not tts_playing then
            log.info("llm_chat", "TTS 被中断，静音等待播放结束")
            pcall(exaudio.vol, 0)  -- 静音（不走 I2C，立即生效）
            local tw = 0
            while not done and tw < 3000 do sys.wait(100); tw = tw + 100 end
            local ac2 = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
            pcall(exaudio.vol, (ac2 and ac2.play_vol) or 70)
        end
    else
        log.warn("llm_chat", "exaudio.play_start TTS 失败")
    end
    tts_playing = false
    sys.publish("AI_CHAT_STATUS", "")
end

tts_stop = function()
    log.info("llm_chat", "tts_stop 调用, playing=", tts_playing)
    local r1 = pcall(exaudio.play_stop, { type = 1 })
    log.info("llm_chat", "play_stop 结果:", r1)
    -- 不调 pm(SHUTDOWN)：参考 demo audio_tts.lua，TTS 只需 play_stop 即可，
    -- SHUTDOWN 会导致 DAC 下电，再 setup+play_start 会失败（Air8601 DAC 模式已验证）
    tts_playing = false
    tts_queue = {}
end

tts_deinit = function() if tts_inited then tts_stop(); tts_inited = false end end

tts_init = function()
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if not ac then log.warn("llm_chat", "TTS: project_config.hw.audio 不存在"); return false end
    -- 每次都做完整 setup：tts_stop 会调 pm(SHUTDOWN) 将 DAC 下电，
    -- 仅 pm(RESUME) 无法完整恢复 DAC 播放通路，导致 play_start 返回 false。
    -- exaudio.setup 在 audio_v2 下是幂等的，重复调用不会出错。
    local sp = { model = ac.model or "es8311", pa_ctrl = ac.pa_ctrl, pa_on_level = ac.pa_on_level or 1, dac_delay = ac.dac_delay }
    if ac.dac_ctrl then sp.dac_ctrl = ac.dac_ctrl end
    if ac.i2c_id then sp.i2c_id = ac.i2c_id end
    if ac.i2s_sample then sp.i2s_sample = ac.i2s_sample end
    if ac.bits_per_sample then sp.bits_per_sample = ac.bits_per_sample end
    if ac.i2s_framebit then sp.i2s_framebit = ac.i2s_framebit end
    if ac.channels then sp.channels = ac.channels end
    if ac.pa_delay then sp.pa_delay = ac.pa_delay end
    if ac.tx_bus_type and ac.rx_bus_type then
        sp.tx_bus_type = ac.tx_bus_type; sp.tx_bus_id = ac.tx_bus_id or 0
        sp.rx_bus_type = ac.rx_bus_type; sp.rx_bus_id = ac.rx_bus_id or 0
    end
    if ac.audio_mode then sp.audio_mode = ac.audio_mode end
    local ok, result = pcall(exaudio.setup, sp)
    if not ok or not result then
        log.warn("llm_chat", "TTS: exaudio.setup 异常/失败", ok, result)
    end
    tts_audio_setup_done = true
    exaudio.vol(ac.play_vol or 70)
    tts_is_v2 = (exaudio.get_audio_mode and exaudio.get_audio_mode() == "audio_v2")
    if tts_is_v2 and audio_v2 and audio_v2.config_codec_power_ctrl then pcall(audio_v2.config_codec_power_ctrl, false, 0, 0, 0, 0) end
    tts_has_play_start = (type(exaudio.play_start) == "function")
    if not tts_has_play_start then log.warn("llm_chat", "TTS: exaudio.play_start 不存在，无法播放"); return false end
    log.info("llm_chat", "TTS init ok, v2=", tts_is_v2)
    tts_inited = true
    return true
end

-- ==================== 下行帧处理 ====================

process_ws_frame = function(frame)
    local cmd = frame.cmd
    if cmd == "create" then
        if frame.code == 0 then
            session_id = frame.session_id; save_session()
            log.info("llm_chat", "会话创建:", session_id)
            sys.publish("AI_CHAT_CONNECTED"); sys.publish("AI_CHAT_STATUS", "已连接")
            if pending_text then
                local t = pending_text; pending_text = nil
                if ws_client then ws_client:send(json.encode({ cmd = "chat_text", session_id = session_id, text = t })) end
                reply_pending = true; current_reply = ""; sys.publish("AI_CHAT_STATUS", "生成中...")
            end
        else sys.publish("AI_CHAT_REPLY_ERROR", "创建失败:" .. tostring(frame.code)) end

    elseif cmd == "reuse" then
        if frame.code == 0 then
            log.info("llm_chat", "会话恢复 轮数:", frame.turns or 0)
            sys.publish("AI_CHAT_CONNECTED"); sys.publish("AI_CHAT_STATUS", "已连接")
            if pending_text then
                local t = pending_text; pending_text = nil
                if ws_client then ws_client:send(json.encode({ cmd = "chat_text", session_id = session_id, text = t })) end
                reply_pending = true; current_reply = ""; sys.publish("AI_CHAT_STATUS", "生成中...")
            end
        else
            session_id = nil; clear_session()
            if ws_client then ws_client:send(json.encode({ cmd = "create", uid = uid, sid = WS_SID, dev_id = dev_id, system = SYSTEM_PROMPT })) end
        end

    elseif cmd == "chat_resp" then
        if not frame.done then
            local token = tostring(frame.data) or ""
            if token ~= "" then
                current_reply = current_reply .. token
                sys.publish("AI_CHAT_TOKEN", token)
                -- 兜底：token 到达时启动/重置 3 秒定时器，done 帧丢了也能触发 TTS
                if reply_pending and tts_enabled then
                    if tts_fallback_timer then sys.timerStop(tts_fallback_timer) end
                    tts_fallback_timer = sys.timerStart(function()
                        tts_fallback_timer = nil
                        if reply_pending and #current_reply > 0 then
                            reply_pending = false
                            local final = current_reply; current_reply = ""
                            sys.publish("AI_CHAT_REPLY_DONE", final)
                            sys.taskInit(function() tts_play_text(final) end)
                        end
                    end, 3000)
                end
            end
        else
            -- done 帧到达：取消兜底定时器
            if tts_fallback_timer then sys.timerStop(tts_fallback_timer); tts_fallback_timer = nil end
            reply_pending = false
            if type(frame.error) == "string" and frame.error ~= "null" and frame.error ~= "" then
                sys.publish("AI_CHAT_REPLY_ERROR", tostring(frame.error)); current_reply = ""
            else
                local final = current_reply; current_reply = ""
                sys.publish("AI_CHAT_REPLY_DONE", final)
                if tts_enabled and #final > 0 then
                    sys.taskInit(function() tts_play_text(final) end)
                end
            end
        end

    elseif cmd == "error" then
        log.warn("llm_chat", "错误:", frame.msg)
        if frame.msg == "busy" then sys.publish("AI_CHAT_REPLY_ERROR", "上一条未完成")
        else sys.publish("AI_CHAT_REPLY_ERROR", tostring(frame.msg or "")) end
        reply_pending = false; current_reply = ""
    end
end

-- ==================== WebSocket 回调 ====================

local function ws_callback(wsc, event, data, fin, opcode)
    if event == "conack" then
        connected = true
        sys.publish("AI_CHAT_CONNECTED")
        log.info("llm_chat", "WS 连接成功")
        recv_buf = ""
        local cmd
        if session_id then
            cmd = json.encode({ cmd = "reuse", session_id = session_id, uid = uid, sid = WS_SID, dev_id = dev_id })
        else
            cmd = json.encode({ cmd = "create", uid = uid, sid = WS_SID, dev_id = dev_id, system = SYSTEM_PROMPT })
        end
        wsc:send(cmd)

    elseif event == "recv" then
        recv_buf = recv_buf .. (data or "")
        if fin == 1 then
            local payload = recv_buf; recv_buf = ""
            if payload and #payload > 0 then
                local fok, frame = pcall(json.decode, payload)
                if fok and type(frame) == "table" then process_ws_frame(frame) end
            end
        end

    elseif event == "disconnect" then
        connected = false; recv_buf = ""
        if tts_fallback_timer then sys.timerStop(tts_fallback_timer); tts_fallback_timer = nil end
        log.info("llm_chat", "WS 断开")
        reply_pending = false; current_reply = ""
        sys.publish("AI_CHAT_DISCONNECTED"); sys.publish("AI_CHAT_STATUS", "连接断开")

    elseif event == "error" then
        log.warn("llm_chat", "WS 错误:", tostring(data), "code=" .. tostring(opcode))
        connected = false; recv_buf = ""
    end
end

-- ==================== WebSocket 连接 ====================

do_connect = function()
    if connected or reconnecting then return end
    reconnecting = true

    -- 确保网络已就绪（双重保险；IP_READY 是即时消息，优先用 socket.localIP 判断）
    if not socket.localIP() then
        log.warn("llm_chat", "网络未就绪，等待IP_READY")
        local _, ip = sys.waitUntil("IP_READY", 30000)
        if not ip then
            log.warn("llm_chat", "IP_READY 等待超时，放弃连接")
            sys.publish("AI_CHAT_STATUS", "网络未就绪")
            reconnecting = false
            return
        end
    end

    -- 从 fskv 读取 uid
    load_iot_uid()
    if not uid or uid == "" then
        log.warn("llm_chat", "uid 为空，等待 IoT 登录")
        sys.publish("AI_CHAT_STATUS", "请先登录IoT账号")
        sys.publish("AI_CHAT_NEED_LOGIN")
        reconnecting = false
        return
    end

    sys.publish("AI_CHAT_STATUS", "连接中...")

    local wsc = websocket.create(nil, WS_URL)
    if not wsc then
        log.error("llm_chat", "create 失败")
        sys.publish("AI_CHAT_STATUS", "创建失败"); sys.wait(RECONNECT_DELAY); do_connect(); return
    end
    ws_client = wsc
    wsc:debug(true)
    wsc:on(ws_callback)

    local ok = wsc:connect()
    log.info("llm_chat", "connect:", ok)
    if not ok then
        log.error("llm_chat", "connect 失败")
        connected = false; wsc:close(); ws_client = nil
        reconnecting = false
        sys.publish("AI_CHAT_STATUS", "连接失败"); sys.wait(RECONNECT_DELAY); do_connect(); return
    end

    -- 等待连接真正建立（conack 回调设置 connected=true 并发布 AI_CHAT_CONNECTED）
    local ack = sys.waitUntil("AI_CHAT_CONNECTED", 15000)
    if not ack then
        log.error("llm_chat", "等待 conack 超时")
        wsc:close(); ws_client = nil; connected = false
        reconnecting = false
        sys.publish("AI_CHAT_STATUS", "握手超时"); sys.wait(RECONNECT_DELAY); do_connect(); return
    end

    -- 心跳 + 断线重连
    reconnecting = false  -- 连接成功，释放重连锁
    while true do
        while connected do
            if ws_client then pcall(ws_client.send, ws_client, json.encode({ cmd = "ping" })) end
            sys.wait(PING_INTERVAL)
        end
        -- 断开了，重连
        if ws_client then pcall(ws_client.close, ws_client); ws_client = nil end
        sys.publish("AI_CHAT_STATUS", "重连中...")
        sys.wait(RECONNECT_DELAY)
        do_connect()
        return  -- do_connect 会启动新的重连循环
    end
end

-- ==================== 发送消息 ====================

local function send_chat(text)
    if not text or text == "" then return end
    if reply_pending then sys.publish("AI_CHAT_REPLY_ERROR", "上一条未完成"); return end
    reply_pending = true; current_reply = ""; sys.publish("AI_CHAT_STATUS", "生成中...")
    if connected and ws_client and session_id then
        ws_client:send(json.encode({ cmd = "chat_text", session_id = session_id, text = text }))
    else pending_text = text end
end

-- ==================== STT ====================

local ASR_URL = "https://api.luatos.com/engine/asr/v1/audio/transcriptions"

local function asr_auth_headers()
    local pub_key = io.readFile("/luadb/public.pem")
    if not pub_key then return nil end
    local model = rtos.bsp()
    local devid = hmeta.devid() or "unknown"
    local ts = tostring(os.time())
    local ok, cipher = pcall(rsa.encrypt, pub_key, ts .. "," .. ts .. "," .. devid)
    if not ok or not cipher then return nil end
    local ak = string.toBase64(cipher) or ""
    if ak == "" then return nil end
    return { ["app-key"] = ak }
end

local function request_stt(file_path, callback)
    if not file_path or not io.exists(file_path) then callback(""); return end
    if (io.fileSize(file_path) or 0) <= 0 then callback(""); return end
    if not socket.localIP() then callback(""); return end
    local headers = asr_auth_headers()
    if not headers then callback(""); return end
    local bd = "----WebKitFormBoundary" .. tostring(os.time())
    headers["Content-Type"] = "multipart/form-data; boundary=" .. bd
    local body = { "--" .. bd .. "\r\n", "Content-Disposition: form-data; name=\"file\"; filename=\"record.amr\"\r\n", "Content-Type: audio/amr\r\n\r\n" }
    local fdata = io.readFile(file_path)
    if not fdata then callback(""); return end
    body[#body + 1] = fdata; body[#body + 1] = "\r\n--" .. bd .. "--\r\n"
    sys.publish("AI_CHAT_STATUS", "语音识别中...")
    local code, _, rb = http.request("POST", ASR_URL, headers, table.concat(body), { timeout = 30000 }).wait()
    if code ~= 200 then sys.publish("AI_CHAT_STATUS", ""); callback(""); return end
    local ok, resp = pcall(json.decode, rb)
    if not ok or type(resp) ~= "table" or resp.code ~= 0 then sys.publish("AI_CHAT_STATUS", ""); callback(""); return end
    local text = (type(resp.value) == "table" and resp.value.text) or ""
    sys.publish("AI_CHAT_STATUS", ""); callback(text)
end

-- ==================== 事件订阅 ====================

sys.subscribe("AI_CHAT_SEND", function(text) sys.taskInit(function() send_chat(text) end) end)
sys.subscribe("AI_CHAT_CLEAR", function()
    sys.taskInit(function()
        if tts_fallback_timer then sys.timerStop(tts_fallback_timer); tts_fallback_timer = nil end
        clear_session(); connected = false
        if ws_client then pcall(ws_client.close, ws_client); ws_client = nil end
        sys.publish("AI_CHAT_STATUS", "会话已清空"); sys.publish("AI_CHAT_DISCONNECTED")
    end)
end)
sys.subscribe("AI_CHAT_TTS_TOGGLE", function()
    sys.taskInit(function()
        log.info("llm_chat", "TTS_TOGGLE: tts_enabled=", tts_enabled, "→", not tts_enabled)
        tts_enabled = not tts_enabled
        tts_playing = false  -- 让 tts_play_text 的循环自行退出并停止音频
        sys.publish("AI_CHAT_TTS_STATUS", tts_enabled)
    end)
end)
sys.subscribe("AI_CHAT_TTS_PLAY", function(text) sys.taskInit(function() tts_play_text(text) end) end)
sys.subscribe("AI_CHAT_DEINIT", function() sys.taskInit(function() tts_deinit() end) end)
--[[AI 助手页面离开前台 → 立即停掉正在播的 TTS。

页面被销毁那条路由 AI_CHAT_CLOSE 覆盖；这里补的是「只失焦、不销毁」的路径
（别的窗口盖在本页之上、切一级菜单的过渡窗口等）。两条路合起来，
保证「退出 AI 助手去别的页面」时不会还有声音在念。]]
sys.subscribe("AI_CHAT_PAGE_ACTIVE", function(active)
    page_active = active and true or false
    -- 只在"确实有一次播报在进行"时才真停：tts_stop() 会走到 exaudio.play_stop，
    -- 而 play_stop 在 audio_v2_request_index 非 nil 时会顺带 pm(SHUTDOWN) 停驱动。
    -- on_destroy 那条路上 AI_CHAT_CLOSE 已经停过，空转一次纯属多余，
    -- 还会平白多停一次驱动（首页 HZV 音轨也是同一套驱动）。
    if not page_active and tts_playing then
        log.info("llm_chat", "AI 助手离开前台，停止 TTS 播报")
        -- 挪进独立任务：subscribe 回调跑在 sys 主事件循环里（sys.lua dispatch()），
        -- play_stop 要碰音频驱动，不能让主循环等它。
        sys.taskInit(function() tts_stop() end)
    end
end)
sys.subscribe("FACTORY_REC_READY", function(ok, msg)
    if ok then
        tts_audio_setup_done = true
        log.info("llm_chat", "FACTORY_REC_READY: audio already inited by factory_rec, TTS skip setup")
    end
end)
sys.subscribe("AI_CHAT_STT", function(fp) sys.taskInit(function() request_stt(fp, function(t) sys.publish("AI_CHAT_STT_RESULT", t) end) end) end)

-- ==================== 初始化 ====================

pcall(fskv.init)
init_device_info()
load_session()

-- 用户打开 AI 助手时连接
sys.subscribe("AI_CHAT_OPEN", function()
    log.info("llm_chat", "收到 AI_CHAT_OPEN")
    sys.taskInit(function()
        load_iot_uid()
        if not uid or uid == "" then
            sys.publish("AI_CHAT_STATUS", "请先登录IoT账号")
            return
        end
        -- 确保网络就绪：IP_READY 是即时消息（错过就没了），用 socket.localIP() 判断当前状态
        if not socket.localIP() then
            log.info("llm_chat", "网络未就绪，等待IP_READY")
            local _, ip = sys.waitUntil("IP_READY", 30000)
            if not ip then
                log.warn("llm_chat", "网络等待超时")
                sys.publish("AI_CHAT_STATUS", "网络未就绪")
                return
            end
        end
        sys.wait(2000)  -- 等网络稳定
        log.info("llm_chat", "网络就绪，准备连接")
        do_connect()
    end)
end)

-- 用户关闭 AI 助手 → 主动断开 WebSocket + 停止 TTS
sys.subscribe("AI_CHAT_CLOSE", function()
    log.info("llm_chat", "关闭 AI 助手，断开连接")
    tts_stop()
    connected = false; recv_buf = ""; reconnecting = false
    if ws_client then
        pcall(ws_client.close, ws_client)
        ws_client = nil
        log.info("llm_chat", "WebSocket 已关闭")
    end
    reply_pending = false; current_reply = ""
    sys.publish("AI_CHAT_STATUS", "")
end)

-- IoT 登录成功 → 刷新 uid（连接由 AI_CHAT_OPEN 触发，不自动连）
sys.subscribe("IOT_LOGIN_RESULT", function(result)
    if result and result.success and result.uid then
        uid = result.uid
        log.info("llm_chat", "IoT 登录成功")
    end
end)
