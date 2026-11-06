--[[
@module  sip_test_app
@summary 功能测试-SIP通话 业务层：SIP 账号注册 / 拨号 / 接听 / 挂断 / 静音（移植自 SIP_APP）
@version 1.0
@date    2026.11.04
@author  功能测试
@usage
订阅: SIP_TEST_START(acct)   -- 注册上线：{server,port,domain,user,password,transport}
订阅: SIP_TEST_STOP          -- 注销下线
订阅: SIP_TEST_DIAL(num)     -- 拨号
订阅: SIP_TEST_ANSWER        -- 接听来电
订阅: SIP_TEST_HANGUP        -- 挂断/拒接
订阅: SIP_TEST_MUTE(on)      -- 静音开关
发布: SIP_TEST_STATE(state)  -- 状态推送：{state,detail,registered,peer,direction,duration,muted}

状态: idle(未启动) / connecting(注册中) / ready(已注册) / dialing(呼出)
      / incoming(来电) / talking(通话中) / ending(挂断中)

依赖：libs/sip/sipapp_exsip.lua / sipapp_client.lua / sipapp_rtp_ports.lua
      app/sip/sip_audio_app.lua（UART6 Air1103 PCM 桥）
]]

local M = {}

local audio = require "sip_audio_app"
local store = require "sip_test_store"
local engine = require "sipapp_exsip"
local client = require "sipapp_client"

-- ==================== 状态 ====================
local wanted = false          -- 用户是否希望 SIP 在线
local worker_run = false      -- 工作协程存活
local initialized = false
local generation = 0          -- 账号代次：换账号/STOP 自增，使旧循环失效
local epoch = 0               -- 事件订阅代次：过滤旧会话回调
local registered = false
local reconnect = false
local call = nil              -- {id,peer,direction,ts,connected,connected_tick,logged}
local pending = nil           -- 正在发送的 MESSAGE：{id}

local S = {
    state = "idle",
    detail = "",
    user = "",
    peer = nil,
    direction = nil,
    since = 0,
    muted = false,
}

-- ==================== 工具 ====================
local function elapsed_clock()
    if mcu and mcu.ticks2 then
        local seconds, micros = mcu.ticks2(0)
        return seconds + (micros or 0) / 1000000
    end
    return os.time()
end

-- 网络是否就绪：对齐参考 SIP_APP/net_app，以 IP_READY / IP_LOSE 事件维护标志。
-- 工厂由 net_manager(exnetif) 统一管理网络并发这两个事件；不要用 socket.dft()
-- 临时枚举默认网卡——exnetif 下默认网卡选择是异步的，轮询可能长期取不到而误判离线。
-- 网络是否就绪：与参考 SIP_APP 语义一致（参考用 net.is_up()）。
-- 工厂由 net_manager(exnetif) 统一管理并发 IP_READY/IP_LOSE；这里只维护标志，
-- 具体选哪张网卡完全交给 sipapp_client 内部 socket.dft() 逻辑，不在业务层另立口径。
local net_ready = false
local function default_adapter_up()
    if not socket then return false end
    local ok, id = pcall(socket.dft)
    if not ok or not id then return false end
    local rok, ready = pcall(socket.adapter, id)
    return rok and ready ~= nil and ready ~= false and ready ~= 0
end

local function online()
    -- 已由 IP_READY 确认在线时不再每次轮询 socket.dft()：exnetif 切网期间 dft 可能瞬时
    -- 取不到，按"瞬时取不到=离线"处理会让 SIP worker 无谓地断线重连，通话也会被踢掉。
    if net_ready then return true end
    return default_adapter_up()
end

sys.subscribe("IP_READY", function() net_ready = true end)
sys.subscribe("IP_LOSE", function() net_ready = default_adapter_up() end)
net_ready = default_adapter_up()

-- 从 SIP URI 里取纯号码：sip:1002@x -> 1002
local function pure_user(value)
    if type(value) ~= "string" then return "" end
    return value:match("[sS][iI][pP]:([^@>;%s]+)") or value
end

local function emit_error(text)
    text = tostring(text)
    log.error("sip_test_app", text)
    -- 对齐参考 SIP_APP 的 SIP_ERROR：工厂用 SIP_TEST_TOAST 把错误直接弹到界面，
    -- 便于暴露注册失败/媒体异常的真实原因，而不只是写日志。
    sys.publish("SIP_TEST_TOAST", text)
end

-- ==================== 状态推送 ====================
-- 未读数是状态里唯一要读 fskv 的字段（fskv.get 整张消息表 + 深拷贝），
-- 而 status() 会被通话层 500ms 定时器和每次状态推送调用。放进热路径会一直抖动
-- Lua 任务调度，直接表现就是通话音"卡顿/断续"。改为事件驱动刷新 + 只读缓存。
local unread_cache = 0
local function refresh_unread()
    local ok, n = pcall(store.unread_total)
    if ok and type(n) == "number" then unread_cache = n end
end

function M.call_duration()
    if not call or not call.connected_tick then return 0 end
    return math.max(0, math.floor(elapsed_clock() - call.connected_tick))
end

function M.status()
    local t = {}
    for k, v in pairs(S) do t[k] = v end
    t.registered = registered
    t.duration = M.call_duration()
    t.unread = unread_cache
    return t
end

local function state(value, detail)
    S.state = value
    if detail ~= nil then S.detail = detail end
    sys.publish("SIP_TEST_STATE", M.status())
end

local function idle_state()
    return registered and "ready" or (wanted and "connecting" or "idle")
end

-- 落一条通话记录（每通电话仅记一次）；typ: dialed/received/missed
local function log_call(typ)
    if not call or call.logged then return end
    call.logged = true
    local dur = 0
    if call.connected_tick then
        dur = math.max(0, math.floor(elapsed_clock() - call.connected_tick))
    end
    if not call.connected and call.direction == "in" then typ = "missed" end
    store.add_call({
        num = call.peer or "",
        name = store.find_name(call.peer or ""),
        type = typ,
        ts = call.ts or os.time(),
        dur = dur,
    })
end

-- ==================== 通话清理 ====================
local function clear_call(typ)
    if not call then return end
    log_call(typ)
    -- 对齐 demo：停铃但不复位、保留 MIC，避免复位(约1.4s)吞掉紧跟的挂断提示音。
    audio.stop_ringback(true, true)
    -- skip_recover=true：停桥但延后 MIC 恢复，避免复位吞掉紧跟的挂断提示音；
    -- 提示音播放收尾会自行 start_record 恢复 MIC
    audio.stop(true)
    call = nil
    S.peer = nil
    S.direction = nil
    S.since = 0
    S.muted = false
    if audio.set_mute then pcall(audio.set_mute, false) end
    pcall(audio.play_hangup)
end

-- 通话事件是否属于当前 call（按 Call-ID 匹配，忽略旧通话遗留回调）
local function call_matches(data)
    if not call or not call.id then return false end
    if data.call_id and call.id and data.call_id ~= call.id then return false end
    if data.call_id then call.id = data.call_id end
    return true
end

-- ==================== 引擎事件 ====================
local function on_event(token, event, action, data)
    if token ~= epoch or not wanted then return end
    data = type(data) == "table" and data or {}

    if event == "register" then
        if action == "ok" then
            registered = true
            if not call then state("ready", "注册成功") end
        elseif action ~= "challenge" then
            registered = false
            reconnect = true
            clear_call()
            state("connecting", "注册失败，请检查账号或网络")
        end
    elseif event == "message" then
        if action == "rx" then
            local num, text = pure_user(data.from), tostring(data.body or "")
            if num ~= "" and text ~= "" then
                store.add_msg(num, "in", text, "recv")
                refresh_unread()      -- 只有收到消息才读一次 fskv
                state(S.state)        -- 刷新未读角标
            end
        elseif action == "sent" or action == "failed" then
            local id = data.message and tonumber(data.message.app_id)
            if pending and id == pending.id then
                if action == "sent" then
                    store.update_msg(id, "sent")
                else
                    store.update_msg(id, "failed", tostring(data.reason or "发送失败"))
                end
                pending = nil
            end
            state(S.state)
        end
    elseif event == "lifecycle" and (action == "offline" or action == "stopped") then
        registered = false
        reconnect = true
        clear_call()
        state("connecting", "连接断开，等待重连")
    elseif event == "call" then
        if action == "incoming" then
            if call then return end
            call = { id = data.call_id, peer = pure_user(data.from), direction = "in", ts = os.time() }
            S.peer = call.peer
            S.direction = "in"
            S.since = call.ts
            if not audio.is_ready() then
                engine.fail(480, "Audio unavailable")
                pcall(audio.request_init)   -- 后台重新拉起音频，下一次来电能正常接
                state(idle_state(), "来电但音频未就绪，已拒绝")
                call = nil
                S.peer = nil
                S.direction = nil
                return
            end
            state("incoming", "来电: " .. tostring(call.peer))
            local tone_ok = audio.play_ringback_loop()
            if not tone_ok then log.warn("sip_test_app", "来电提示音不可用") end
        elseif action == "dialing" and call and call.direction == "out" and not call.id then
            call.id = data.call_id
        elseif action == "dial_rejected" and call and call.direction == "out" and not call.id then
            clear_call("dialed")
            state(idle_state(), "呼出失败: " .. tostring(data.reason))
        elseif call_matches(data) then
            if action == "ringing" then
                if call.direction == "out" and S.state == "dialing" then
                    state("dialing", "对方响铃中")
                end
            elseif action == "connected" or action == "established" then
                call.connected = call.connected or os.time()
                call.connected_tick = call.connected_tick or elapsed_clock()
                -- 桥(M.start)在 media 阶段已启动并占用 Air1103，此时只能停振铃、
                -- 绝不能复位芯片：无参 stop_ringback() 会复位约1.4s并停 MIC，
                -- 直接造成播放卡顿、对端听不到。对齐 demo：(true,true) 不复位、保留 MIC。
                audio.stop_ringback(true, true)
                S.since = call.connected
                state("talking", "通话中")
            elseif action == "ended" or action == "failed" then
                clear_call(call.direction == "out" and "dialed" or "received")
                state(idle_state(), "通话结束")
            end
        end
    elseif event == "media" and action == "ready" then
        -- 媒体就绪在异步桥启动之前；2 秒后核对桥是否真的起来了，没起来就挂断
        local active = call
        sys.timerStart(function()
            if token ~= epoch or call ~= active or not call then return end
            if not audio.is_bridge_ok() then
                emit_error("音频桥启动失败，已结束通话")
                engine.hangUp()
                state("ending", "音频异常")
            end
        end, 2000)
    elseif event == "error" then
        emit_error("SIP错误: " .. tostring(action))
    end
end

-- ==================== SIP 配置 ====================
local function build_config(a)
    return {
        sip_server_addr = a.server,
        sip_server_port = tonumber(a.port) or 5060,
        sip_domain = (a.domain and a.domain ~= "") and a.domain or a.server,
        sip_username = a.user,
        sip_password = a.password,
        sip_transport = a.transport,
        codecs = { "PCMA", "PCMU" },
        ptime = 20,
        auto_answer = false,
        expires = 600,
        call_timeout = 45,
        audio_mode = voip and voip.AUDIO_MODE_BRIDGE,
        -- 不传 adapter：与参考 SIP_APP 完全一致，交给 sipapp_client 内部跟随
        -- socket.dft()（库已内置 exnetif 网卡就绪表与切换重连）。外部锁定网卡会与
        -- client 空闲态强制 socket.dft() 的逻辑冲突，导致注册一直 waiting for IP_READY。
    }
end

-- ==================== 主工作协程 ====================
local function run()
    while wanted do
        local mine = generation
        registered = false
        state("connecting", "等待网络")

        while wanted and mine == generation and not online() do sys.wait(500) end

        if wanted and mine == generation then
            epoch = epoch + 1
            local token = epoch
            reconnect = false
            local a = M._acct
            S.user = a.user .. "@" .. a.server
            engine.on(function(...) on_event(token, ...) end)

            -- 与参考 SIP_APP 一致：注册流程不阻塞在音频初始化上。
            -- 音频桥由模块加载时的后台任务独立就绪（audio.init 幂等），
            -- 这里只确保提示音音量跟随配置。
            pcall(audio.set_volume, store.get_vol())

            state("connecting", "注册中")
            local ok = engine.init(build_config(a)) and engine.start()
            if not ok then emit_error("SIP初始化失败，请检查固件及配置") end

            local elapsed_ms = 0
            while ok and wanted and mine == generation and online() and not reconnect do
                sys.wait(500)
                elapsed_ms = elapsed_ms + 500
                if not registered and elapsed_ms >= 30000 then break end
            end

            epoch = epoch + 1
            registered = false
            clear_call()
            engine.stop() -- yields；只在此协程内调用
            while client.is_running() do sys.wait(100) end

            if wanted and mine == generation then
                state("connecting", "连接失败，稍后重试")
                for _ = 1, 16 do
                    if not wanted or generation ~= mine then break end
                    sys.wait(500)
                end
            end
        end
    end
    worker_run = false
    state("idle", "已注销")
end

-- 后台独立就绪音频桥：参考 SIP_APP/boot.lua，音频与 SIP 注册互不阻塞。
-- audio.init 内部幂等；失败不影响注册（拨号/来电时仍会再次 gate 检查）。
local audio_booted = false
local function ensure_audio_background()
    if audio_booted then return end
    audio_booted = true
    sys.taskInit(function()
        sys.wait(200)
        local ok, err = pcall(audio.init)
        if not ok then
            log.warn("sip_test_app", "后台音频初始化失败，将在拨号前重试", tostring(err))
            audio_booted = false
            return
        end
        pcall(audio.set_volume, store.get_vol())
    end)
end

local function start_worker()
    if worker_run then return end
    worker_run = true
    ensure_audio_background()
    sys.taskInit(run)
end

-- ==================== 对外动作 ====================
local function acct_validate(a)
    if type(a) ~= "table" then return false, "参数错误" end
    if type(a.server) ~= "string" or a.server == "" then return false, "请填写服务器" end
    if type(a.user) ~= "string" or a.user == "" then return false, "请填写用户名" end
    if type(a.password) ~= "string" or a.password == "" then return false, "请填写密码" end
    if a.transport ~= "udp" and a.transport ~= "tcp" then a.transport = "udp" end
    local port = tonumber(a.port)
    if not port or port % 1 ~= 0 or port < 1 or port > 65535 then a.port = 5060 end
    for _, k in ipairs({ "server", "domain", "user" }) do
        if a[k] and a[k]:find("[\r\n]") then return false, "账号字段不能包含换行" end
    end
    return true
end

-- 注册上线
function M.start(acct)
    if call then return false, "请先结束当前通话" end
    local ok, err = acct_validate(acct)
    if not ok then return false, err end
    M._acct = {
        server = acct.server,
        port = tonumber(acct.port) or 5060,
        domain = acct.domain or "",
        user = acct.user,
        password = acct.password,
        transport = acct.transport or "udp",
    }
    generation = generation + 1
    epoch = epoch + 1
    wanted = true
    registered = false
    refresh_unread()
    start_worker()
    return true
end

-- 注销下线
function M.stop()
    if call then return false, "请先结束当前通话" end
    wanted = false
    registered = false
    generation = generation + 1
    epoch = epoch + 1
    state(worker_run and "connecting" or "idle", "正在注销")
    return true
end

-- 退出 SIP 页：若有通话先挂断，再注销、等待 worker 退出，最后释放音频硬件/UART6。
function M.shutdown()
    if call then
        pcall(M.hangup)
        local deadline = os.time() + 3
        while call and os.time() < deadline do sys.wait(100) end
    end
    wanted = false
    registered = false
    generation = generation + 1
    epoch = epoch + 1
    local deadline = os.time() + 5
    while worker_run and os.time() < deadline do sys.wait(100) end
    pcall(audio.teardown)
    return true
end

-- 拨号
function M.dial(num)
    if type(num) ~= "string" or num == "" or #num > 128 or num:find("[\r\n]") then
        return false, "号码格式错误"
    end
    if not registered or S.state ~= "ready" then return false, "未注册或当前忙" end
    if not audio.is_ready() then
        -- 音频没就绪就别让呼叫建立在"注定无声"的会话上：先把它拉起来，
        -- 下一通/重拨即可正常（这里不能 yield 等初始化，UI 是同步调用）。
        pcall(audio.request_init)
        return false, "音频尚未就绪，正在重新初始化，请稍后再拨"
    end
    call = { peer = num, direction = "out", ts = os.time() }
    S.peer = num
    S.direction = "out"
    S.since = call.ts
    if not engine.dial(num) then
        call = nil
        S.peer = nil
        S.direction = nil
        S.since = 0
        return false, "呼出失败"
    end
    state("dialing", "正在呼叫 " .. num)
    local tone_ok = audio.play_ringback_loop()
    if not tone_ok then log.warn("sip_test_app", "回铃音不可用") end
    return true
end

-- 接听
function M.answer()
    if S.state ~= "incoming" or not call then return false, "当前没有来电" end
    if not engine.accept() then return false, "接听失败" end
    -- 桥随 media 启动；停铃不能复位芯片，否则卡顿/断 MIC。对齐 demo (true,true)。
    audio.stop_ringback(true, true)
    state("talking", "正在接通")
    return true
end

-- 挂断/拒接
function M.hangup()
    if not call then return false, "当前没有通话" end
    -- 对齐 demo：停铃不复位、保留 MIC；真正释放芯片由 ended->clear_call 的 audio.stop 负责。
    audio.stop_ringback(true, true)
    if S.state == "incoming" then
        engine.fail(486, "Busy Here")
    else
        engine.hangUp()
    end
    state("ending", "正在挂断")
    return true
end

-- 静音
function M.set_mute(on)
    if S.state ~= "talking" then return false, "当前不在通话中" end
    if not audio.set_mute then return false, "音频驱动不支持静音" end
    local ok, result = pcall(audio.set_mute, on == true)
    if not ok or result == false then return false, "静音设置失败" end
    S.muted = on == true
    state(S.state)
    return true
end

-- 发送 SIP MESSAGE（文本消息）
function M.send_message(num, text)
    if type(num) ~= "string" or num == "" then return false, "请填写号码" end
    if type(text) ~= "string" or text == "" then return false, "请填写消息内容" end
    if #text > 1024 then return false, "消息过长（最多1024字节）" end
    if not registered or S.state ~= "ready" then return false, "SIP 未在线" end
    local ok, id = store.add_msg(num, "out", text, "pending")
    if not ok then return false, id end
    if not engine.message(num, text, id) then
        store.update_msg(id, "failed", "发送失败")
        return false, "发送失败"
    end
    pending = { id = id, num = num }
    state(S.state)
    return true, id
end

-- 音量
function M.set_volume(v)
    local n, err = store.set_vol(v)
    if not n then return false, err end
    audio.set_volume(n)
    return true, n
end
function M.get_volume() return store.get_vol() end

-- 存储透传给 UI（联系人/记录/消息全部能力）
M.store = store

-- 供 UI 同步取状态
function M.get_state() return M.status() end
function M.is_online() return registered and S.state == "ready" end

-- ==================== 消息订阅 ====================
sys.subscribe("SIP_TEST_START", function(acct)
    sys.taskInit(function()
        local ok, err = M.start(acct)
        if not ok then
            sys.publish("SIP_TEST_TOAST", tostring(err))
        end
    end)
end)

sys.subscribe("SIP_TEST_STOP", function()
    sys.taskInit(function()
        local ok, err = M.stop()
        if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
    end)
end)

sys.subscribe("SIP_TEST_DIAL", function(num)
    sys.taskInit(function()
        local ok, err = M.dial(num)
        if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
    end)
end)

sys.subscribe("SIP_TEST_ANSWER", function()
    sys.taskInit(function()
        local ok, err = M.answer()
        if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
    end)
end)

sys.subscribe("SIP_TEST_HANGUP", function()
    sys.taskInit(function()
        local ok, err = M.hangup()
        if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
    end)
end)

sys.subscribe("SIP_TEST_MUTE", function(on)
    local ok, err = M.set_mute(on)
    if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
end)

sys.subscribe("SIP_TEST_SEND_MSG", function(num, text)
    sys.taskInit(function()
        local ok, err = M.send_message(num, text)
        if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
    end)
end)

sys.subscribe("SIP_TEST_VOL", function(v)
    sys.taskInit(function()
        local ok, err = M.set_volume(v)
        if not ok then sys.publish("SIP_TEST_TOAST", tostring(err)) end
    end)
end)

-- 音频桥故障：结束当前通话
sys.subscribe("AUDIO_BRIDGE_FAILED", function(reason)
    if not call or S.state == "ending" then return end
    emit_error("音频故障: " .. tostring(reason))
    engine.hangUp()
    state("ending", "音频故障，正在挂断")
end)

initialized = true
return M
