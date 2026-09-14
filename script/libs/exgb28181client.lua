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
        sessions   = {},   -- 点播会话，按 Call-ID 索引(支持多路并发)
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
-- 点播会话(INVITE / ACK / BYE)
-- ------------------------------------------------------------------
--[[
一个会话由平台发 INVITE 发起：
    INVITE(带 SDP) -> 200 OK(带本端 SDP) -> ACK -> 推流 ... -> BYE
会话按 Call-ID 索引，因此可以同时被多个平台/多路点播。每条会话有**独立**
的 RTP 端口与 SSRC —— 共用会导致两路流在平台侧混在一起。
]]

-- 平台 SDP 里必须是 PS 流；GB28181 的视频载荷固定 96(PS/90000)
local PS_RTPMAP_PREFIX = "PS/"
local PS_PAYLOAD_TYPE  = 96

-- TCP 会话失活判定的默认阈值(毫秒)。默认值只此一处定义，
-- start() 与 session_death_reason() 共用 —— 两处各写一份迟早会漂
local DEFAULT_TCP_DEAD_MS      = 10000
local DEFAULT_TCP_LINK_WAIT_MS = 10000
-- 探针等应答的时长。SIP 是请求-应答，超过它还没回就算"平台不应答"
local DEFAULT_PROBE_TIMEOUT_MS = 4000

-- 读配置项，未 start() 时也能安全取到默认值
local function opt_or(name, def)
    local v = g_opts and g_opts[name]
    if v == nil then return def end
    return v
end

local function session_count()
    local n = 0
    for _ in pairs(st.sessions) do n = n + 1 end
    return n
end

-- 分配一个本地 RTP 端口：从配置的基址起，跳过已被占用的
local function alloc_rtp_port()
    local base = g_opts.rtp_port_base
    local n = g_opts.max_sessions or 4
    local i
    for i = 0, n - 1 do
        local p = base + i
        local used = false
        for _, s in pairs(st.sessions) do
            if s.local_port == p then used = true break end
        end
        if not used then return p end
    end
    return nil
end

--[[
决定 TCP 媒体承载下本端扮演的角色(setup 方向)。

SDP offer/answer 的硬性规则：两端不能同时是 passive，也不能同时是 active。
所以平台的 offer 已经指明方向时，本端只能取它的反面；只有在平台给
actpass(或压根不给该行)时，才轮到本端按自己的处境选。

取舍：passive(本端 listen 等平台连)更贴近多数 GB28181 设备实现，平台侧
行为可预期；active(本端连平台)在设备处于 NAT 之后时更容易穿透，
但要求平台侧地址确实可达。故缺省 passive，可用 prefer 改。

@api exgb28181client.tcp_setup_choice(offer_setup, prefer)
@string|nil offer_setup 平台 SDP 的 a=setup 值("active"/"passive"/"actpass")，缺失传 nil
@string|nil prefer      平台未指定方向时的倾向，缺省 "passive"
@return string|nil "active"|"passive"；非法 prefer 时返回 nil + 原因
]]
function M.tcp_setup_choice(offer_setup, prefer)
    local s = offer_setup and string.lower(offer_setup) or nil

    -- 平台已定方向：本端只能反向
    if s == "passive" then return gb.TCP_SETUP_ACTIVE end
    if s == "active"  then return gb.TCP_SETUP_PASSIVE end

    -- actpass 或平台没给该行：本端自选
    local p = prefer or "passive"
    p = string.lower(p)
    if p ~= "active" and p ~= "passive" then
        return nil, "TCP 承载的倾向只能是 active 或 passive, 实际 " .. tostring(prefer)
    end
    return p
end

-- 打开会话的媒体 socket(独立于信令 socket)。
--
-- UDP 与 TCP 的建链方式完全不同，故分三条路：
--   UDP        直接 connect 到平台的收流地址
--   TCP active 同样 connect，但对端是"等连"的一方
--   TCP passive 本端 listen，等平台连进来(ON_LINE 才算就绪)
-- 后两者在连上之前不能发数据，故用 sess.link_up 标记就绪。
--
--[[
回调同时是"媒体链路是否还活着"的观测点。事件映射**很容易记反**，这里写明实测值：

    LINK=0x...10  ON_LINE=0x...11  TX_OK=0x...12  CLOSED=0x...13  EVENT=0x...14

  · ON_LINE            —— 链路可用
  · TX_OK              —— 每次发送完成后各来一条（不是"有新数据"）
  · EVENT(param == 0)  —— 有新数据可读
  · EVENT(param != 0)  —— **对端断开或本地错误，这才是"链路断了"的信号**
  · CLOSED             —— 只在**本端发起关闭**时回给我们（适配器里
                          EV_NW_RESULT_CLOSE 仅在 close_flag 时发出；
                          对端 FIN 走的是 NW_WAIT_EVENT 分支 → EVENT）

所以判据是 `EVENT 且 param ~= 0`，**不是 socket.CLOSED** —— 名字叫 CLOSED
很容易让人以为它是"连接被关闭"，用错的效果是每一次真实断开都被静默漏掉。
LuatOS 自己的惯例也是这个：见 l2tp_client.c / ovpn_client.c 的
`event->ID == EV_NW_RESULT_CLOSE || event->Param1 != 0`。

不过单条 param≠0 的事件不能立刻判死：适配器里本地错误（如收包时分配失败，
对应 EV_NW_SOCKET_ERROR）也走这条，那种是可恢复的。故记下"第一次可疑"的时刻，
期间任何一次发送成功或重新 ON_LINE 都会清掉它（见 session_death_reason）。
]]
local function media_create(sess)
    return socket.create(g_opts.adapter, function(sc, event, param)
        if event == socket.ON_LINE then
            sess.link_up = true
            sess.link_up_once = true
            sess.link_bad_ms = nil
        elseif event == socket.EVENT and param ~= nil and param ~= 0 then
            sess.link_up = false
            if not sess.link_bad_ms then
                sess.link_bad_ms = now_ms()
                log_warn("媒体链路中断 param=" .. tostring(param))
            end
        elseif event == socket.CLOSED then
            sess.link_up = false   -- 本端 close 完成，不据此判死
        end
    end)
end

local function media_open(sess)
    local netc = media_create(sess)
    if not netc then return false, "创建媒体 socket 失败" end

    local is_tcp = sess.media_tcp
    local ok

    if is_tcp and sess.tcp_setup == gb.TCP_SETUP_PASSIVE then
        -- 本端监听，等平台来连。TCP 媒体是长连接且一对一，故用一对一模式
        ok = socket.config(netc, sess.local_port, false)
        if ok then ok = socket.listen(netc) end
        if not ok then
            socket.close(netc)
            return false, "媒体端口监听失败"
        end
    else
        ok = socket.config(netc, sess.local_port, not is_tcp)
        if ok then ok = socket.connect(netc, sess.remote_ip, sess.remote_port) end
        if not ok then
            socket.close(netc)
            return false, "媒体通道建立失败"
        end
        -- UDP 无"建链"概念，create 之后即可发
        if not is_tcp then sess.link_up = true end
    end

    sess.netc = netc
    return true
end

local function media_close(sess)
    if sess.netc then
        socket.close(sess.netc)
        sess.netc = nil
        sess.link_up = false
    end
    if sess.media then
        gb.media_reset(sess.media)
        sess.media = nil
    end
end

-- 回一个 SIP 响应(状态码 + 可选 body)
--[[
回一条 SIP 响应。

to_tag 只在**建立对话**的应答（INVITE 的 200 OK）时给：RFC 3261 要求
UAS 在应答里给 To 加自己的 tag，对端之后发的 in-dialog 请求（BYE 等）
要靠这对 tag 匹配对话。缺了它，本端也组不出合法的 in-dialog 请求
（见 probe_session）。其余应答沿用已与真实平台验证过的写法，不动。
]]
local function reply(msg, code, reason, body, content_type, to_tag)
    local vias = {}
    for _, h in ipairs(msg.header_list or {}) do
        if h.name:lower() == "via" then vias[#vias + 1] = h.value end
    end
    local to_raw = msg.headers["to"]
    if to_tag and to_raw and not to_raw:find(";tag=", 1, true) then
        to_raw = to_raw .. ";tag=" .. to_tag
    end
    local cseq_hdr = msg.headers["cseq"] or "1 INVITE"
    local text = gb.sip_build({
        code        = code,
        reason      = reason,
        via_list    = vias,
        from_raw    = msg.headers["from"],
        to_raw      = to_raw,
        call_id     = msg.headers["call-id"],
        cseq        = tonumber(cseq_hdr:match("^(%d+)")) or 1,
        cseq_method = cseq_hdr:match("%s+(%a+)$") or "INVITE",
        contact     = (body ~= nil),
        -- 带 SDP 的应答必须给 Contact。此处走 from_raw 回抄，没有 from_uri
        -- 可供推导，故显式给出设备编码(GB28181 里 Contact 的 user 即设备编码)
        contact_user = g_opts.device_id,
        host        = st.local_ip,
        port        = g_opts.local_port,
        content_type = content_type,
        body        = body,
    })
    if text then net_send(text) end
    return text
end

--[[
处理 INVITE。
只接受视频 + PS/90000；不支持的请求回 488(Not Acceptable Here)，
让平台明确知道设备在但会话建立不了，好过静默丢弃让平台一直等超时。
]]
local function handle_invite(msg)
    local o = g_opts

    if session_count() >= (o.max_sessions or 4) then
        log_warn("并发会话已达上限, 拒绝")
        reply(msg, 486, "Busy Here")
        emit("invite", "rejected", { reason = "会话数超限" })
        return
    end

    local s = gb.sdp_parse(msg.body)
    if not s then
        log_warn("INVITE 的 SDP 无法解析, 拒绝")
        reply(msg, 488, "Not Acceptable Here")
        emit("invite", "rejected", { reason = "SDP 解析失败" })
        return
    end

    if s.media ~= "video" then
        log_warn("只支持视频点播, 拒绝", s.media)
        reply(msg, 488, "Not Acceptable Here")
        emit("invite", "rejected", { reason = "非视频媒体" })
        return
    end

    -- GB28181 的视频必须是 PS 流；平台若只要裸 H.264 我们做不了
    if s.rtpmap and not s.rtpmap:match("^" .. PS_RTPMAP_PREFIX) then
        log_warn("平台要求的编码不是 PS 流, 拒绝", s.rtpmap)
        reply(msg, 488, "Not Acceptable Here")
        emit("invite", "rejected", { reason = "非 PS 流" })
        return
    end

    if s.conn_ip == nil or s.port == 0 then
        log_warn("SDP 缺少媒体地址或端口, 拒绝")
        reply(msg, 488, "Not Acceptable Here")
        emit("invite", "rejected", { reason = "缺少媒体地址" })
        return
    end

    --[[
    媒体承载由 SDP 的 m= 协议决定，**不能拿信令的传输方式来推**：
    信令 UDP + 媒体 TCP 是常见组合，用信令去推会让 TCP 平台收到
    没有长度帧的裸 RTP(反之亦然)，表现是"连上了但解不出画面"。
    ]]
    local media_tcp = (s.tcp == true)

    -- TCP 承载的 setup 方向：平台指定了就反向，没指定才由本端选
    local tcp_setup
    if media_tcp then
        local err
        tcp_setup, err = M.tcp_setup_choice(s.setup, o.tcp_setup_prefer)
        if not tcp_setup then
            log_warn("无法满足平台的 TCP 承载要求, 拒绝", err)
            reply(msg, 488, "Not Acceptable Here")
            emit("invite", "rejected", { reason = err })
            return
        end

        -- a=connection:existing 要求媒体复用 SIP 那条 TCP 连接。
        -- 本端信令通常是 UDP，且把媒体泵进信令连接需要与信令共用一个
        -- socket 句柄 —— 本层做不到。明确回绝好过按 new 静默建立，
        -- 那会让平台在错误的连接上等媒体。
        if s.connection == gb.TCP_CONN_EXISTING then
            log_warn("平台要求复用 SIP 连接承载媒体, 本端不支持, 拒绝")
            reply(msg, 488, "Not Acceptable Here")
            emit("invite", "rejected", { reason = "不支持 connection:existing" })
            return
        end
    end

    -- 会话名决定业务语义，也决定 SSRC 的首位
    local is_playback = (s.session_name == "Playback" or s.session_name == "Download")
    local local_port = alloc_rtp_port()
    if not local_port then
        log_warn("无可用 RTP 端口")
        reply(msg, 503, "Service Unavailable")
        return
    end

    local ssrc = gb.ssrc_make(is_playback, o.domain, session_count() + 1)
    if not ssrc then
        log_warn("SSRC 生成失败")
        reply(msg, 500, "Server Internal Error")
        return
    end

    --[[
    对话标识：in-dialog 请求（探针、将来的 INFO 控制）要靠这一组值构造。

    **注意方向**：对方 INVITE 里 To 是**本端**、From 是**对端**；
    而本端在对话内发请求时要反过来 —— From 是本端、To 是对端。
    所以 local_uri 取自 INVITE 的 To，remote_uri 取自它的 From，
    不是原样照抄（照抄会把 To 填成本端自己的地址，平台必然匹配不到对话）。

      local_tag     本端 tag，写进 200 OK 的 To，之后作为请求的 From tag
      remote_tag    对端 tag，来自它 INVITE 的 From
      remote_target 对端 Contact —— in-dialog 请求的 Request-URI 用这个
    ]]
    local local_tag = "luat" .. gen_token("tag")

    local sess = {
        call_id      = msg.headers["call-id"],
        session_name = s.session_name or "Play",
        is_playback  = is_playback,
        remote_ip    = s.conn_ip,
        remote_port  = s.port,
        local_port   = local_port,
        ssrc         = ssrc,
        created      = now_ms(),
        started      = false,   -- 收到 ACK 才置位
        media_tcp    = media_tcp,
        tcp_setup    = tcp_setup,
        link_up      = false,   -- TCP 连上(或 accept)之后才置位
        frame_ts     = 0,       -- 90kHz 时间戳
        last_ms      = nil,

        local_tag    = local_tag,
        remote_tag   = (msg.headers["from"] or ""):match(";tag=([^;%s]+)"),
        -- 本端 URI 来自对方 INVITE 的 To；对端 URI 与 tag 来自它的 From
        local_uri    = uri_of(msg.headers["to"]),
        remote_uri   = uri_of(msg.headers["from"]),
        remote_target = uri_of(msg.headers["contact"]) or uri_of(msg.headers["from"]),
        invite_cseq  = tonumber((msg.headers["cseq"] or "1"):match("^(%d+)")) or 1,
    }

    local answer = gb.sdp_build({
        owner_id     = o.device_id,
        ip           = st.local_ip,
        session_name = sess.session_name,
        media        = "video",
        port         = local_port,
        payload_type = PS_PAYLOAD_TYPE,
        rtpmap       = "PS/90000",
        ssrc         = ssrc,
        has_ssrc     = 1,
        direction    = "sendonly",
        format       = o.media_format,   -- f= 行，可由配置覆盖
        -- 承载必须与平台要求的一致，且 setup 要给**本端**的方向
        proto        = media_tcp and gb.PROTO_TCP or gb.PROTO_UDP,
        setup        = media_tcp and tcp_setup or nil,
        connection   = media_tcp and gb.TCP_CONN_NEW or nil,
    })
    if not answer then
        log_warn("应答 SDP 构造失败")
        reply(msg, 500, "Server Internal Error")
        return
    end

    -- 媒体会话与队列(队列容量按配置，默认 32KB)
    local media = gb.media_new(ssrc, o.rtp_mtu, o.media_queue_size)
    if not media then
        log_warn("媒体队列创建失败")
        reply(msg, 500, "Server Internal Error")
        return
    end
    sess.media = media

    -- 访问单元规范化器：缓存 SPS/PPS，并在缺参数集的 IDR 前补上。
    -- 编码类型从 ps_cfg 推出来，不另开一个选项 —— 两者写不一致时
    -- 会补出与 PSM 声明不符的参数集，那种故障在平台上表现为花屏
    sess.nal = gb.nal_new(o.ps_cfg.video_stream_type == 0x24, o.nal_wait_idr)
    if not sess.nal then
        log_warn("访问单元规范化器创建失败")
        gb.media_reset(media)
        reply(msg, 500, "Server Internal Error")
        return
    end

    local ok, err = media_open(sess)
    if not ok then
        log_warn("媒体通道建立失败", err)
        gb.media_reset(media)
        reply(msg, 500, "Server Internal Error")
        return
    end

    st.sessions[sess.call_id] = sess
    reply(msg, 200, "OK", answer, "application/sdp", sess.local_tag)
    log_info("接受点播", sess.session_name,
             media_tcp and ("TCP/" .. tcp_setup) or "UDP",
             s.conn_ip, s.port, "本地端口", local_port)
    emit("invite", "accepted", {
        call_id = sess.call_id, session_name = sess.session_name,
        ssrc = ssrc, local_port = local_port,
        transport = media_tcp and "TCP" or "UDP",
        setup = tcp_setup,
    })
end

local function handle_ack(msg)
    local sess = st.sessions[msg.headers["call-id"]]
    if not sess then
        log_warn("ACK 对应不到会话")
        return
    end
    if not sess.started then
        sess.started = true
        sess.started_ms = now_ms()
        log_info("会话已建立, 开始推流", sess.call_id)
        emit("media", "ready", { call_id = sess.call_id, ssrc = sess.ssrc })
    end
    -- ACK 是请求，仍需回 200(部分平台要求)
end

--[[
判断一个会话是否已死、该死，返回原因。

**只有 TCP 能给出确定答案** —— 这是这套判据的全部诚实之处：
  · UDP 上"对端进程没了"在 socket 层不可观测。实测：对端端口关闭、
    ICMP port unreachable 回来后，socket.tx 依然返回成功，
    既没有 CLOSED 事件、也没有错误码。Play 会话里平台又只收不发，
    媒体 socket 全程静默。故 UDP 会话在这里永远判"活着" ——
    盲超时会误杀平台暂停中的会话，宁可不杀。
  · TCP 有连接状态机，对端 FIN/RST 必然体现在事件或发送失败上。

三个判据（都在 TCP 下才生效）：
  1. link_bad_ms —— 收到 param ~= 0 的 EVENT（对端 FIN 走的就是这条）。
     单条不立刻判死，因为本地可恢复的错误也走这条；持续到阈值才回收
  2. tx_fail_ms  —— 连续发送失败超过阈值。兜住"链路被中间设备静默切断"
     这类连事件都没有的情况，也用来确认第 1 条
  3. 链路迟迟建不起来 —— passive 等不到平台连入、active 连不上。
     平台既然在 SDP 里约定了连接，就一直建不起来的话这个会话是死的，
     端口没必要一直占着

@api exgb28181client.session_death_reason(sess, now, dead_ms)
@table sess   会话
@int now      当前毫秒(缺省取本库时钟)
@int dead_ms  发送失败的判定阈值(缺省用启动时的 tcp_dead_ms)
@return string|nil 死因；活着返回 nil
]]
function M.session_death_reason(sess, now, dead_ms)
    if type(sess) ~= "table" or not sess.media_tcp then
        return nil      -- 非 TCP：没有可信判据，不猜
    end

    now = now or now_ms()
    dead_ms = dead_ms or opt_or("tcp_dead_ms", DEFAULT_TCP_DEAD_MS)

    if sess.link_bad_ms and (now - sess.link_bad_ms) >= dead_ms then
        return "媒体链路中断且未恢复"
    end
    if sess.tx_fail_ms and (now - sess.tx_fail_ms) >= dead_ms then
        return "媒体连接持续发送失败"
    end
    --[[
    链路一直没建起来：从收到 ACK 起算，给足建链时间。

    只在**从未连上过**的情况下才走这条 —— 会话中途断链时 link_up 也会变 false，
    若不加这一层判断，这条就会立刻命中(started_ms 已是很久以前)，
    等于一条可疑事件就把会话杀了，正是上面刻意要避免的。
    ]]
    if sess.started and not sess.link_up and not sess.link_up_once and
       (now - (sess.started_ms or now)) >=
           opt_or("tcp_link_wait_ms", DEFAULT_TCP_LINK_WAIT_MS) then
        return "媒体链路未能建立"
    end
    return nil
end

--[[
对一个已建立的会话发一条 in-dialog 请求并跟踪其应答。

**不要拿它做失活判据 —— 已实测否决**（WVP-Pro v2.7.4，2026-09-14）：

  OPTIONS  平台完全不处理对话内 OPTIONS → 根本没应答
  INFO     WVP 用自己内部的事务表匹配，永远回 404「事务未找到」，
           因此**无法区分"对话还在"与"对话已被平台丢弃"**
  INVITE   回 500，并且 WVP 抛异常后直接注销流、停掉点播 ——
           探针把被探测的会话弄坏了

即便把 WVP 的内部匹配方式逆向对了也不该用：判据落在某个平台的实现细节上，
换一家平台就不成立，那就不是判据。另外 INFO 在 GB28181 里承载 MANSRTSP
（回放控制），在真的实现了它的平台上，这个空 INFO 可能被当成控制指令 ——
把它当"无害的 ping"是把平台行为想简单了。

保留本函数是因为它在**对接新平台时当诊断工具**很有用：想知道对方究竟认不认
本端的对话标识，发一条 INFO 看它回什么，比对着抓包猜快得多。
UDP 承载的失活判定仍然维持"不猜"（见 session_death_reason）。

@api exgb28181client.probe_session(sess, method)
@table sess   会话
@string method 缺省 "OPTIONS"；诊断时可传 "INFO" / "INVITE"
@return boolean, string|nil 失败原因
]]
function M.probe_session(sess, method)
    if type(sess) ~= "table" or not sess.call_id then
        return false, "无效会话"
    end
    if not sess.started then
        return false, "会话尚未建立(未收到 ACK)"
    end

    method = method or "OPTIONS"
    local probe_cseq = (sess.probe_cseq or sess.invite_cseq or 1) + 1
    local body = nil
    if method == "INFO" then
        -- 空体 INFO：只为要一个应答，不带任何控制语义
        body = ""
    end

    local text, err = gb.sip_build({
        method       = method,
        -- in-dialog 请求的 Request-URI 是对端的 Contact，不是 To
        uri          = sess.remote_target or sess.remote_uri,
        host         = st.local_ip,
        port         = g_opts.local_port,
        branch       = "z9hG4bK" .. gen_token("probe"),
        from_uri     = sess.local_uri,     -- 本端(来自对方 INVITE 的 To)
        from_tag     = sess.local_tag,     -- 本端 tag
        to_uri       = sess.remote_uri,    -- 对端(来自对方 INVITE 的 From)
        to_tag       = sess.remote_tag,    -- 对端 tag
        call_id      = sess.call_id,
        cseq         = probe_cseq,
        cseq_method  = method,
        contact      = true,
        contact_user = g_opts.device_id,
        body         = body,
    })
    if not text then
        return false, err or "构造探针失败"
    end

    sess.probe_cseq    = probe_cseq
    sess.probe_pending = { cseq = probe_cseq, method = method, at = now_ms() }
    net_send(text)
    return true
end

-- 探针未在超时内得到应答 → 记一笔。这是"平台不回"的唯一判据
local function check_probe_timeout()
    local now = now_ms()
    local limit = opt_or("probe_timeout_ms", DEFAULT_PROBE_TIMEOUT_MS)
    for call_id, sess in pairs(st.sessions) do
        local p = sess.probe_pending
        if p and (now - p.at) >= limit then
            sess.probe_pending = nil
            log_warn("探针无应答", call_id, p.method, "cseq=" .. p.cseq)
            emit("session", "probe_timeout",
                 { call_id = call_id, method = p.method, cseq = p.cseq })
        end
    end
end

-- 回收已死的会话。只在 tick 里调用，保证会话表的改动都发生在同一个上下文
local function reap_dead_sessions()
    local now = now_ms()
    for call_id, sess in pairs(st.sessions) do
        local reason = M.session_death_reason(sess, now)
        if reason then
            log_warn("回收失活会话", call_id, reason)
            media_close(sess)
            st.sessions[call_id] = nil
            emit("call", "ended", { call_id = call_id, reason = reason })
        end
    end
end

local function handle_bye(msg)
    local call_id = msg.headers["call-id"]
    local sess = st.sessions[call_id]

    reply(msg, 200, "OK")   -- BYE 必须先回 200
    if not sess then
        -- 会话表里没有它：可能是重复的 BYE(已回收过)，也可能是 Call-ID 对不上。
        -- 早先这里静默返回，导致"没收到 BYE"与"收到了但没认出来"在日志里
        -- 长得一模一样 —— 排查会话泄漏时分不清是哪一种
        log_warn("BYE 未匹配到会话", tostring(call_id))
        return
    end

    media_close(sess)
    st.sessions[call_id] = nil
    log_info("会话已结束", call_id)
    emit("call", "ended", { call_id = call_id, reason = "bye" })
end

--[[
向会话推送一帧编码数据。

frame 应为**一个完整的访问单元**(annex-b，可含多个 NALU)；
时间戳由本库按 90kHz 时钟自行推进，调用方不必关心。

帧会先过一遍访问单元规范化(见 gb28181.nal_process)：
  · 起播后的头几帧若不是 IDR，会被**有意丢弃** —— 接收端解不出，
    发出去只是浪费带宽。这是规格要求的"首个 PS 帧以 IDR 起始"
  · 每个缺参数集的 IDR 会补上缓存的 SPS/PPS(或 H.265 的 VPS/SPS/PPS)，
    让平台能随时接入

推送后立即尝试把队列发出去 —— 发送节奏由帧率驱动，而不是靠定时器
轮询，这样既没有额外延迟也不空转。

@api exgb28181client.push_frame(session, frame)
@table session  invite/accepted 事件给出的会话(或直接传该表)
@string frame 编码帧
@return boolean 成功返回 true
@return string|nil 未发出时的原因："waiting_idr" 表示在等首个 IDR(正常)
]]
function M.push_frame(sess, frame)
    if type(sess) ~= "table" or type(frame) ~= "string" or #frame == 0 then
        return false, "invalid"
    end
    if not sess.started or not sess.media or not sess.netc then
        return false, "not_ready"   -- 还没收到 ACK，或会话已结束
    end
    -- TCP 承载还要等连接真正建立(passive 是 accept，active 是 connect 完成)。
    -- 在 link_up 之前发，数据会落到一个还没建好的通道上白丢。
    if sess.media_tcp and not sess.link_up then
        return false, "link_down"
    end

    -- 时间戳按真实经过的毫秒数推进，避免与平台侧的时钟漂移
    local now = now_ms()
    if sess.last_ms then
        sess.frame_ts = (sess.frame_ts + (now - sess.last_ms) * 90) % 0xFFFFFFFF
    end
    sess.last_ms = now

    -- 规范化：学到参数集、等到 IDR、必要时补参数集。
    -- 返回 nil 表示这一帧不该发(还没等到首个 IDR)—— 这不是故障
    local au = gb.nal_process(sess.nal, frame)
    if not au then
        return false, "waiting_idr"
    end

    local ps = gb.ps_video(g_opts.ps_cfg, au, sess.frame_ts)
    if not ps then
        return false, "ps_fail"
    end

    -- 首帧前先发一次 PS 流头(Pack + System Header + PSM)：
    -- 平台靠 PSM 才能知道 0xE0 里装的是 H.264 还是 H.265。
    -- 注意要放在规范化**之后** —— 被丢弃的那些帧不该触发流头，
    -- 否则流头会先于第一个 IDR 很久就发出去
    if not sess.head_sent then
        local head = gb.ps_stream_head(g_opts.ps_cfg, sess.frame_ts)
        if head then
            gb.media_push(sess.media, head, sess.frame_ts)
        end
        sess.head_sent = true
    end

    if gb.media_push(sess.media, ps, sess.frame_ts) == 0 then
        -- 整帧被丢弃(队列满或帧过大)，统计里能查到
        return false, "queue_full"
    end

    M.flush_session(sess)
    return true
end

--[[
把会话队列里能发的包尽量发出去。

UDP 与 TCP 的失败处理必须不同，原因见 C 层 luat_gb28181_media.h：
  UDP 不可靠 -> 发送失败即丢本帧剩余，避免平台收到残帧
  TCP 可靠   -> 只是缓冲区满，记录断点续发，**绝不能丢**

"承载方式"取自**会话**而不是全局配置：同一个设备可能同时被要求走 UDP 和
TCP 的两路点播，用全局配置会让其中一路按错误的格式发。

发送路径用 peek + commit/advance 而不是 pop：失败或只发出去一部分时，
那个包必须留在队首 —— 否则既不知道 UDP 该从哪丢到哪，也无从 TCP 续发。

@api exgb28181client.flush_session(session)
@table session
@return int 本次发出的字节数
]]
function M.flush_session(sess)
    local sent = 0

    if not sess.media or not sess.netc then return 0 end

    while true do
        local pkt = gb.media_peek(sess.media)
        if not pkt then break end

        -- UDP 跳过 2 字节长度前缀；TCP 整块发 —— 那个前缀就是 RFC 4571 的长度帧
        local payload = sess.media_tcp and pkt or pkt:sub(3)
        local want    = #payload

        local ok, txlen = socket.tx(sess.netc, payload)
        if not ok then
            if sess.media_tcp then
                -- TCP 发不出去：连接可能已经断了(实测对端关闭后 tx 会一直失败)。
                -- 记下第一次失败的时刻，持续失败超过阈值才判定为死 ——
                -- 缓冲区一时满也会失败，但那种很快就能恢复，不会持续到阈值
                sess.tx_fail_ms = sess.tx_fail_ms or now_ms()
                break          -- 包留在队首，下次续发
            end
            gb.media_drop_partial(sess.media)   -- 拥塞：丢掉本帧剩余
            break
        end
        -- 发出去了：既证明链路可用，也说明之前的可疑事件是本地可恢复错误
        sess.tx_fail_ms = nil
        sess.link_bad_ms = nil

        txlen = txlen or want
        sent = sent + txlen

        if txlen >= want then
            gb.media_commit(sess.media)
        else
            -- 只发出去一部分：记下断点，下一轮 peek 从断点续发。
            -- UDP 不会走到这里(数据报要么整个发出要么整个失败)；
            -- txlen 为 0 时不再重试，否则会在原地空转
            gb.media_advance(sess.media, txlen)
            if txlen == 0 then break end
        end
    end
    return sent
end

-- ---- 收包 ----

--[[
收包。

响应先看是不是某个会话的探针应答 —— 探针只关心"回没回"，任何状态码都算活着
（481 说明平台人还在，只是不认这个对话；要区分的是"回都不回"）。
]]
local function process_packet(msg)
    if msg.code then
        local sess = st.sessions[msg.headers["call-id"]]
        local p = sess and sess.probe_pending
        if p and tonumber((msg.headers["cseq"] or ""):match("^(%d+)")) == p.cseq then
            sess.probe_pending = nil
            log_info("探针应答", p.method, msg.code, msg.reason)
            emit("session", "probe_reply", {
                call_id = sess.call_id, method = p.method,
                cseq = p.cseq, code = msg.code,
            })
            return
        end

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

    if msg.method == "INVITE" then
        handle_invite(msg)
        return
    end

    if msg.method == "ACK" then
        handle_ack(msg)
        return
    end

    if msg.method == "BYE" then
        handle_bye(msg)
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
    log_info("DBG event =", event)
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
            log_info("DBG 收到", #data, "字节")
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

        -- 回收已死的点播会话。不做这一步的话，平台侧异常退出留下的会话
        -- 会一直占着媒体端口与队列，max_sessions 打满后设备永久拒绝新点播
        reap_dead_sessions()
        check_probe_timeout()
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

    -- 点播相关默认值
    g_opts.rtp_port_base    = g_opts.rtp_port_base or 30000
    g_opts.max_sessions     = g_opts.max_sessions or 4
    g_opts.rtp_mtu          = g_opts.rtp_mtu or 0        -- 0 -> C 层默认(1400)
    g_opts.media_queue_size = g_opts.media_queue_size or 32768
    -- f= 行：描述媒体编码参数。取 0 表示由平台自行判断
    g_opts.media_format     = g_opts.media_format or "v/2/5/25/1/6000a/1a"
    -- PS 封装配置，随编码类型变化(H.264/H.265)
    g_opts.ps_cfg = g_opts.ps_cfg or { video_stream_type = 0x1B }
    -- 起播是否等到第一个 IDR 再发。规格要求首个 PS 帧以 IDR 起始并含
    -- SPS/PPS，故缺省 true；关掉只在"上层已保证从头推"时才合理
    if g_opts.nal_wait_idr == nil then g_opts.nal_wait_idr = true end
    -- TCP 媒体承载时本端的倾向(setup)，仅当平台没指定方向时生效。
    -- 具体取舍见 choose_tcp_setup 的注释
    g_opts.tcp_setup_prefer = g_opts.tcp_setup_prefer or "passive"
    -- TCP 会话的失活判定阈值(毫秒)。只在 TCP 下有意义，判据见
    -- session_death_reason：UDP 上"对端已死"不可观测，不做超时
    g_opts.tcp_dead_ms      = g_opts.tcp_dead_ms or DEFAULT_TCP_DEAD_MS
    -- TCP 链路从 ACK 起多久还没建起来就判死
    g_opts.tcp_link_wait_ms = g_opts.tcp_link_wait_ms or DEFAULT_TCP_LINK_WAIT_MS
    -- 会话探针等应答的时长(见 probe_session)
    g_opts.probe_timeout_ms = g_opts.probe_timeout_ms or DEFAULT_PROBE_TIMEOUT_MS

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
列出当前所有点播会话。平台点播后可据此推流。
@api exgb28181client.sessions()
@return table 以 Call-ID 为键的会话表(Call-ID -> {ssrc=,session_name=,remote_ip=,...})
]]
function M.sessions()
    local out = {}
    for k, v in pairs(st.sessions) do out[k] = v end
    return out
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
