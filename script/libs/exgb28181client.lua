--[[
@module exgb28181client
@summary GB28181 设备侧信令客户端，负责注册、心跳与查询响应
@version 0.1.0
@date    2026.09.14
@usage
本库是 GB28181 的"信令侧"实现，处理：
  REGISTER(含 401/407 摘要重试)、心跳 Keepalive、以及平台的查询应答
  (DeviceInfo / DeviceStatus / ConfigDownload / Catalog 目录分页)。
不含点播与媒体收发，那些是后续里程碑。

协议编解码全部由 C 模块 gb28181 承担，本库只做状态机与 socket 收发。

基本用法：
local client = require "exgb28181client"

client.start({
    server_addr = "192.168.1.100",
    server_port = 5060,
    domain      = "3502000000",
    device_id   = "35020000001320000001",
    password    = "wvp_sip_password",
    transport   = "udp",
    device = {
        name         = "LuatOS-IPC",
        manufacturer = "LuatOS",
        model        = "Air8101",
        firmware     = "V1.0",
        channel      = 1,
    },
    event_callback = function(event, action, payload)
        if event == "register" and action == "ok" then
            log.info("gb28181", "注册成功")
        elseif event == "query" then
            log.info("gb28181", "收到查询", action, payload.supported)
        end
    end,
})

-- client.stop()

注意事项：
1、回调运行在 socket 回调或本库任务中，应保持短小
2、报文的 SN 由本库递增维护；平台查询里的 SN 会原样回填
3、收到畸形报文(TCP 下)会断连重注册 —— 流一旦错位无法可靠重新同步
4、device 表里的字段应为 ASCII(GB28181 的 MANSCDP 声明是 GB2312)，
   中文会因编码不符而乱码，详见 C 层 luat_gb28181_xml.h 的说明
]]

-- C 模块：真机走 require，PC 模拟器需回退全局表。
-- 该模拟器用自定义加载器接管了 require，不解析 C 内建模块，
-- require "gb28181" 在此会失败，但模块仍在全局表上。
local gb
do
    local ok, mod = pcall(require, "gb28181")
    gb = ok and mod or rawget(_G, "gb28181")
end

local M = {}

local TOPIC_CMD  = "GB28181_CMD"
local TOPIC_STOP = "GB28181_STOP"

local MAX_AUTH_RETRY = 2

local g_opts    = nil
local g_cb      = nil
local g_started = false
local st        = {}

local function reset_state()
    st = {
        netc       = nil,
        rx         = "",     -- TCP 残余缓冲
        online     = false,
        registered = false,
        local_ip   = nil,
        sn         = 0,
        call_id    = nil,
        from_tag   = nil,
        cseq       = 0,
        auth_tried = 0,
        next_reg   = 0,
        next_ka    = 0,
    }
end

-- ------------------------------------------------------------------
-- 工具
-- ------------------------------------------------------------------

local function log_info(...)
    if _G.log and type(log.info) == "function" then log.info("gb28181", ...) end
end
local function log_warn(...)
    if _G.log and type(log.warn) == "function" then log.warn("gb28181", ...) end
end
local function log_error(...)
    if _G.log and type(log.error) == "function" then log.error("gb28181", ...) end
end

local function now_ms()
    if _G.mcu and type(mcu.ticks) == "function" then return mcu.ticks() end
    return os.time() * 1000
end

--[[
生成随机 token(branch / tag / cnonce / call-id 用)。

C 层不做随机数——随机源属平台能力，放进 src/ 会破坏"只依赖 libc"的约束，
故由 Lua 侧生成后作为参数传入。
]]
local function gen_token(prefix)
    local ticks = 0
    if _G.mcu and type(mcu.ticks) == "function" then ticks = mcu.ticks() end
    local seed = string.format("%s:%d:%d:%d", prefix or "t", ticks,
                               os.time(), math.random(1000000))
    if _G.crypto and type(crypto.md5) == "function" then
        return crypto.md5(seed):lower():sub(1, 16)
    end
    log_warn("缺少 crypto，token 随机性不足")
    return string.format("%08x%08x", os.time() % 0xFFFFFFFF, ticks % 0xFFFFFFFF)
end

local function emit(event, action, payload)
    if type(g_cb) ~= "function" then return end
    local ok, err = pcall(g_cb, event, action, payload or {})
    if not ok then log_error("事件回调异常", event, action, err) end
end

local function next_sn()
    st.sn = st.sn + 1
    if st.sn > 999999 then st.sn = 1 end
    return st.sn
end

-- 从 From/To 头里取出尖括号内的 URI
local function uri_of(header_value)
    if type(header_value) == "string" then
        return header_value:match("<([^>]+)>")
    end
    return nil
end

-- ------------------------------------------------------------------
-- 发送
-- ------------------------------------------------------------------

local function net_send(text)
    if not st.netc then return false end
    return socket.tx(st.netc, text)
end

--[[
构造并发送一条设备发起的请求。
@param method 方法名
@param extra  追加/覆盖的 gb28181.sip_build 字段
]]
local function send_request(method, extra)
    extra = extra or {}
    local o = g_opts

    st.cseq = st.cseq + 1

    local cfg = {
        method      = method,
        uri         = string.format("sip:%s@%s", o.server_id, o.domain),
        transport   = string.upper(o.transport),
        host        = st.local_ip,
        port        = o.local_port,
        branch      = gen_token("z9hG4bK"),
        from_uri    = string.format("sip:%s@%s", o.device_id, o.domain),
        from_tag    = st.from_tag,
        to_uri      = string.format("sip:%s@%s", o.device_id, o.domain),
        call_id     = st.call_id,
        cseq        = st.cseq,
        user_agent  = o.user_agent or "LuatOS-GB28181",
        cseq_method = method,
    }
    for k, v in pairs(extra) do cfg[k] = v end

    local text, err = gb.sip_build(cfg)
    if not text then
        log_error("构造报文失败", method, err)
        return nil
    end
    if not net_send(text) then
        log_warn("发送失败", method)
        return nil
    end
    return text
end

--[[
对收到的请求回 200 OK。
SIP 要求响应必须回抄请求的 Via(可能多条)、From、To(含 tag)、Call-ID 与 CSeq，
少一样都可能被对端丢弃或无法匹配事务，故一律原样回抄而非重新格式化。
]]
local function reply_ok(msg)
    local vias = {}
    for _, h in ipairs(msg.header_list or {}) do
        if h.name:lower() == "via" then
            vias[#vias + 1] = h.value
        end
    end

    local cseq_hdr = msg.headers["cseq"] or "1 MESSAGE"
    local cseq_num = tonumber(cseq_hdr:match("^(%d+)")) or 1
    local cseq_method = cseq_hdr:match("%s+(%a+)$") or "MESSAGE"

    local text = gb.sip_build({
        code        = 200,
        reason      = "OK",
        via_list    = vias,
        from_raw    = msg.headers["from"],
        to_raw      = msg.headers["to"],
        call_id     = msg.headers["call-id"],
        cseq        = cseq_num,
        cseq_method = cseq_method,
        contact     = false,
        host        = st.local_ip,
        port        = g_opts.local_port,
    })
    if text then
        net_send(text)
    else
        log_warn("构造 200 OK 失败")
    end
end

-- ------------------------------------------------------------------
-- 注册
-- ------------------------------------------------------------------

local function send_register(auth)
    return send_request("REGISTER", {
        expires = g_opts.expires or 3600,
        auth    = auth,
    })
end

local function schedule_reregister()
    local expires = g_opts.expires or 3600
    local lead = (expires > 60) and 30 or 5
    st.next_reg = now_ms() + (expires - lead) * 1000
end

local function schedule_keepalive()
    local iv = g_opts.keepalive or 60
    if iv <= 0 then
        st.next_ka = 0
        return
    end
    st.next_ka = now_ms() + iv * 1000
end

-- 前向声明：sip_task 的 tick 里要用
local send_keepalive

local function handle_register_response(msg)
    if msg.code == 200 then
        st.registered = true
        st.auth_tried = 0
        local expires = tonumber(msg.headers["expires"]) or (g_opts.expires or 3600)
        log_info("REGISTER 成功, 有效期", expires)
        schedule_reregister()
        schedule_keepalive()
        emit("register", "ok", { expires = expires })
        return
    end

    if msg.code == 401 or msg.code == 407 then
        if st.auth_tried >= MAX_AUTH_RETRY then
            log_error("认证重试超限, 放弃")
            emit("register", "fail", { code = msg.code, reason = "认证重试超限" })
            return
        end
        st.auth_tried = st.auth_tried + 1

        local hname = (msg.code == 407) and "proxy-authenticate" or "www-authenticate"
        local chal = msg.headers[hname]
        if not chal then
            log_error("认证挑战缺失", hname)
            emit("register", "fail", { code = msg.code, reason = "缺少认证挑战" })
            return
        end
        local ch = gb.sip_parse_challenge(chal)
        if not ch then
            log_error("挑战解析失败")
            emit("register", "fail", { code = msg.code, reason = "挑战解析失败" })
            return
        end

        -- qop 可能是列表("auth,auth-int")，本实现只支持 auth
        local qop, nc, cnonce
        if ch.qop then
            qop = ch.qop:match("auth")
            if not qop then
                log_error("不支持的 qop", ch.qop)
                emit("register", "fail", { code = msg.code, reason = "不支持的 qop" })
                return
            end
            nc = string.format("%08x", st.auth_tried)
            cnonce = gen_token("cn")
        end

        local auth = gb.sip_authorization({
            username  = g_opts.device_id,
            password  = g_opts.password or "",
            realm     = ch.realm,
            nonce     = ch.nonce,
            method    = "REGISTER",
            uri       = string.format("sip:%s@%s", g_opts.server_id, g_opts.domain),
            qop       = qop,
            nc        = nc,
            cnonce    = cnonce,
            opaque    = ch.opaque,
            algorithm = ch.algorithm,
        })
        if not auth then
            log_error("摘要计算失败")
            emit("register", "fail", { code = msg.code, reason = "摘要计算失败" })
            return
        end
        log_info("收到挑战, 带摘要重发")
        send_register(auth)
        return
    end

    log_error("REGISTER 被拒", msg.code, msg.reason)
    emit("register", "fail", { code = msg.code, reason = msg.reason })
end

-- ------------------------------------------------------------------
-- 心跳
-- ------------------------------------------------------------------

send_keepalive = function()
    local body = gb.xml_build_keepalive(g_opts.device_id, next_sn(), "OK")
    if not body then
        log_error("构造心跳失败")
        return
    end
    schedule_keepalive()
    send_request("MESSAGE", {
        to_uri       = string.format("sip:%s@%s", g_opts.server_id, g_opts.domain),
        content_type = "Application/MANSCDP+xml",
        body         = body,
    })
end

-- ------------------------------------------------------------------
-- 查询应答
-- ------------------------------------------------------------------

--[[
应答目录查询：按页发多条 MESSAGE。

GB28181 的目录可以很长，标准要求分包发送 —— 每条 MESSAGE 的
SumNum 都是**通道总数**，平台据此累加并判断是否收全。
本函数每页独立构造，任何一页构造失败都只记日志并跳过该页，
不会发出残缺的页(那会让平台的目录出现空洞)。
]]
local function send_catalog(msg, sn)
    local o = g_opts
    local chans = o.channels or {}
    local sum = #chans

    if sum == 0 then
        log_warn("未配置通道，回 ERROR")
        local fail = gb.xml_build_response_fail("Catalog", sn, o.device_id, "ERROR")
        if fail then
            send_request("MESSAGE", {
                to_uri       = uri_of(msg.headers["from"])
                               or string.format("sip:%s@%s", o.server_id, o.domain),
                content_type = "Application/MANSCDP+xml",
                body         = fail,
            })
        end
        return
    end

    local page = o.catalog_page_size or 10
    local to_uri = uri_of(msg.headers["from"])
                   or string.format("sip:%s@%s", o.server_id, o.domain)
    local sent = 0
    local i = 1

    while i <= sum do
        local items = {}
        local last = math.min(i + page - 1, sum)
        for j = i, last do
            items[#items + 1] = chans[j]
        end

        local body = gb.xml_build_catalog({
            device_id = o.device_id,
            sum_num   = sum,
            items     = items,
        }, sn)

        if body then
            send_request("MESSAGE", {
                to_uri       = to_uri,
                content_type = "Application/MANSCDP+xml",
                body         = body,
            })
            sent = sent + #items
        else
            -- 构造失败多半是单页太大，记日志让人去调小 catalog_page_size
            log_error("目录分页构造失败, 本页跳过", i, last,
                      "请调小 catalog_page_size")
        end
        i = last + 1
    end

    log_info("目录应答已发", sent, "/", sum, "条")
end

--[[
应答平台的查询：先回 200 OK，再回带应答体的 MESSAGE。

先回 200 OK 是 SIP 的要求(任何请求都要有响应)，且必须回抄请求的 Via/
From/To；MESSAGE 里才是 MANSCDP 的业务应答。少任何一个，WVP 这类
平台都可能判定设备异常。
]]
local function handle_query(msg)
    -- XML 解析交给 C 层(协议编解码归 C，Lua 只做状态机)
    local q = gb.xml_parse_query(msg.body)
    if not q or not q.cmd_type then
        log_warn("查询报文中无 CmdType")
        reply_ok(msg)
        return
    end

    local cmd  = q.cmd_type
    local sn   = q.sn or 0
    local o    = g_opts
    local body

    if cmd == "DeviceInfo" then
        local d = o.device or {}
        body = gb.xml_build_device_info({
            device_id    = o.device_id,
            name         = d.name,
            manufacturer = d.manufacturer,
            model        = d.model,
            firmware     = d.firmware,
            channel      = d.channel or #(o.channels or {}) or 1,
        }, sn)

    elseif cmd == "DeviceStatus" then
        body = gb.xml_build_device_status({
            device_id   = o.device_id,
            online      = "ONLINE",
            status      = "OK",
            encode      = "ON",
            record      = "OFF",
            device_time = os.date("%Y-%m-%dT%H:%M:%S"),
            alarm_count = 0,
        }, sn)

    elseif cmd == "ConfigDownload" then
        if q.config_type == nil or q.config_type == "BasicParam" then
            body = gb.xml_build_config_download({
                device_id          = o.device_id,
                name               = "BasicParam",
                expiration         = o.expires or 3600,
                heartbeat_interval = o.keepalive or 60,
                heartbeat_count    = 3,
            }, sn)
        end
    end

    -- 1) SIP 层的 200 OK(任何查询都要回)
    reply_ok(msg)

    -- 2) MANSCDP 层的业务应答
    if cmd == "Catalog" then
        emit("query", cmd, { sn = sn, supported = true })
        send_catalog(msg, sn)
        return
    end

    local supported = (body ~= nil)
    if not supported then
        -- 尚未覆盖的查询：明确回一个非 OK 的 Result。
        -- 让平台知道"设备在线但暂时给不了"，远好于不回导致查询超时。
        log_info("暂不支持的查询", cmd, q.config_type)
        body = gb.xml_build_response_fail(cmd, sn, o.device_id, "ERROR")
    end

    emit("query", cmd, { sn = sn, supported = supported })

    if body then
        local to_uri = uri_of(msg.headers["from"])
                       or string.format("sip:%s@%s", o.server_id, o.domain)
        send_request("MESSAGE", {
            to_uri       = to_uri,
            content_type = "Application/MANSCDP+xml",
            body         = body,
        })
    end
end

-- ------------------------------------------------------------------
-- 收包
-- ------------------------------------------------------------------

local function process_packet(msg)
    if msg.code then
        if st.auth_tried > 0 or not st.registered then
            handle_register_response(msg)
        else
            log_info("收到响应", msg.code, msg.reason)
        end
        return
    end

    if msg.method == "MESSAGE" then
        handle_query(msg)
        return
    end

    log_info("暂不处理的请求", msg.method)
    reply_ok(msg)
end

--[[
喂入一段字节，内部切分并逐条处理。
@return boolean 处理是否正常(报文畸形返回 false)
]]
local function feed(data)
    if type(data) ~= "string" or #data == 0 then return true end

    if string.upper(g_opts.transport) == "TCP" then
        st.rx = st.rx .. data
    else
        st.rx = data
    end

    while #st.rx > 0 do
        local status, msg, consumed = gb.sip_pop(st.rx, g_opts.max_msg)
        if status == "ok" then
            st.rx = st.rx:sub(consumed + 1)
            local ok, err = pcall(process_packet, msg)
            if not ok then log_error("处理报文异常", err) end
        elseif status == "need_more" then
            break
        else
            log_error("报文畸形")
            st.rx = ""
            return false
        end
    end
    return true
end

-- ------------------------------------------------------------------
-- 主任务
-- ------------------------------------------------------------------

local function net_cb(netc, event, param)
    if event == socket.ON_LINE then
        st.online = true

        -- 本地 IP 必须等连上后才能取到(用于 Via 与 Contact)
        local ip = socket.localIP(g_opts.adapter)
        if type(ip) == "string" and #ip > 0 then
            st.local_ip = ip
        end
        if not st.local_ip then
            log_error("无法获取本地 IP, 无法构造 Via/Contact")
            emit("error", "net", { reason = "无法获取本地 IP" })
            return
        end
        log_info("网络就绪, 本地", st.local_ip, "开始注册")
        send_register(nil)

    elseif event == socket.EVENT then
        local rxbuf = zbuff.create(1500)
        if not rxbuf then return end
        while true do
            local succ, data_len = socket.rx(netc, rxbuf)
            if not succ then break end
            if not data_len or data_len <= 0 then break end
            local data = rxbuf:toStr(0, rxbuf:used())
            rxbuf:del()
            if not feed(data) and string.upper(g_opts.transport) == "TCP" then
                log_warn("TCP 流错位, 断连重注册")
                sys.publish(TOPIC_STOP)
                return
            end
        end

    elseif event == socket.CLOSED then
        st.online = false
        st.registered = false
        sys.publish(TOPIC_STOP)
    end
end

local function sip_task()
    local o = g_opts

    local netc = socket.create(o.adapter, net_cb)
    if not netc then
        log_error("创建 socket 失败")
        emit("error", "net", { reason = "socket.create 失败" })
        g_started = false
        return
    end
    st.netc = netc

    if not socket.config(netc, o.local_port, string.upper(o.transport) ~= "TCP") then
        log_error("socket 配置失败")
        emit("error", "net", { reason = "socket.config 失败" })
        g_started = false
        return
    end

    if not socket.connect(netc, o.server_addr, o.server_port) then
        log_error("连接失败", o.server_addr, o.server_port)
        emit("error", "net", { reason = "socket.connect 失败" })
        g_started = false
        return
    end

    log_info("信令任务启动", o.server_addr, o.server_port)

    -- 单 tick 循环：既响应命令，也检查重注册/心跳是否到期
    while g_started do
        sys.waitUntil(TOPIC_CMD, 1000)
        local now = now_ms()

        if st.registered and st.next_reg > 0 and now >= st.next_reg then
            st.next_reg = 0
            log_info("重注册到期")
            send_register(nil)
        end

        if st.registered and st.next_ka > 0 and now >= st.next_ka then
            send_keepalive()
        end
    end

    if st.netc then
        socket.close(st.netc)
        st.netc = nil
    end
    st.registered = false
    st.online = false
    log_info("信令任务结束")
    emit("lifecycle", "stop")
end

-- ------------------------------------------------------------------
-- 对外接口
-- ------------------------------------------------------------------

--[[
启动 GB28181 信令客户端。
@api exgb28181client.start(opts)
@table opts 配置，见模块头部用法示例
@return boolean 成功返回 true
@return string|nil 失败原因
]]
function M.start(opts)
    if g_started then return false, "已在运行" end
    if type(opts) ~= "table" then return false, "opts 必须是 table" end
    -- 必须是 20 位**数字**：只查长度会放过 "...000a" 这类编码，
    -- 而设备编码会原样进 From/To/Contact 与 MANSCDP 报文，写错后很难排查
    if type(opts.device_id) ~= "string" or #opts.device_id ~= 20
       or not opts.device_id:match("^%d+$") then
        return false, "device_id 必须是 20 位数字的国标编码"
    end
    if type(opts.server_addr) ~= "string" or #opts.server_addr == 0 then
        return false, "server_addr 必填"
    end
    if gb == nil then
        return false, "固件未开启 LUAT_USE_GB28181"
    end

    reset_state()

    g_opts = {}
    for k, v in pairs(opts) do g_opts[k] = v end
    g_opts.server_port = g_opts.server_port or 5060
    g_opts.domain      = g_opts.domain or g_opts.device_id:sub(1, 10)
    -- 平台编号：未显式给出时按国标惯例用 域 + 20
    g_opts.server_id   = g_opts.server_id or (g_opts.domain .. "20")
    g_opts.transport   = g_opts.transport or "udp"
    g_opts.local_port  = g_opts.local_port or 5060
    g_opts.max_msg     = g_opts.max_msg or 8192

    g_cb = opts.event_callback

    -- 一次 start 内保持稳定的 Call-ID 与 From tag：
    -- 重注册若换了它们，服务端可能判为新事务甚至返回 482
    st.call_id  = gen_token("call") .. "@" .. g_opts.server_addr
    st.from_tag = gen_token("tag")

    g_started = true
    sys.taskInit(sip_task)
    return true
end

--[[
停止客户端并释放资源。
@api exgb28181client.stop()
@return boolean 成功返回 true
]]
function M.stop()
    if not g_started then return true end
    g_started = false
    sys.publish(TOPIC_STOP)
    return true
end

--[[
注册事件回调。
@api exgb28181client.on(callback)
@function callback 原型 callback(event, action, payload)
@return boolean 成功返回 true
]]
function M.on(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    g_cb = callback
    return true
end

--[[
查询当前是否已注册成功。
@api exgb28181client.is_registered()
@return boolean
]]
function M.is_registered()
    return st.registered == true
end

--[[
手动触发一次心跳(自检用)。
@api exgb28181client.keepalive()
@return boolean 触发成功返回 true
]]
function M.keepalive()
    if not st.registered then return false end
    send_keepalive()
    return true
end

return M
