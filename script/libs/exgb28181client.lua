--[[
@module exgb28181client
@summary GB28181 设备侧信令客户端：注册、心跳、查询应答、点播会话与媒体收发
@version 0.1.0
@date    2026.09.14
@usage
本库是 GB28181 设备侧的信令与媒体实现，处理：
  REGISTER(含 401/407 摘要重试)、心跳 Keepalive、平台的查询应答
  (DeviceInfo / DeviceStatus / ConfigDownload / Catalog 目录分页 /
   RecordInfo 录像列表)、
  实时点播(INVITE/SDP 协商/ACK/BYE，UDP 与 TCP 两种承载)、
  会话失活回收、以及语音对讲/广播的两条腿。

协议编解码全部由 C 模块 gb28181 承担，本库只做状态机与 socket 收发。

**媒体是指"字节"不是"声音"**：本库收已编码的载荷(视频是 annex-b 访问单元、
音频是 G.711A)，PCM↔G.711A 与麦克风/喇叭都不在这里 —— 那些由
`exgb28181audio.lua` 接 LuatOS 的 audio_v2 完成(见该文件头)。

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
local g_audio_cb = nil    -- 下行音频回调。与 g_cb 一样放模块局部而不是 g_opts：
                          -- on_audio() 可能在 start() 之前被调用(音频桥先于信令起来)，
                          -- 挂在 g_opts 上会在那时炸 "attempt to index a nil value"
local g_playback_cb = nil -- 回放源钩子(见 on_playback)。同样放模块局部：
                          -- exgb28181playback 通常在 client.start() 之前就 setup()
local g_ptz_cb = nil      -- 云台指令处理者(见 on_ptz)。同上，应用会在 start() 前注册
local g_drag_zoom_cb = nil     -- 拉框缩放处理者(见 on_drag_zoom)，2022 新增
local g_home_position_cb = nil -- 看守位处理者(见 on_home_position)，2022 新增
local g_started = false
local st        = {}

local function reset_state()
    st = {
        netc       = nil,
        rx         = "",     -- TCP 残余缓冲
        online     = false,
        registered = false,
        local_ip   = nil,
        sip_port   = nil,    -- 信令 socket 实际用的端口（由 local_port 或系统分配，见 _reconnect_signaling）
        sn         = 0,
        call_id    = nil,
        from_tag   = nil,
        cseq       = 0,
        auth_tried = 0,
        next_reg   = 0,
        next_ka    = 0,
        sessions   = {},   -- 点播会话，按 Call-ID 索引(支持多路并发)
        talks      = {},   -- 设备主动发起的音频会话(Broadcast/Talk)，按 Call-ID 索引
        subs       = {},   -- 平台订阅(SUBSCRIBE)，按 Call-ID 索引；见 handle_subscribe

        -- 信令链路的重建状态，见 _signal_dead / _reconnect_signaling
        dead           = false,  -- 链路已失活，等 sip_task 重建
        reconnect_at   = 0,      -- 下次可尝试重建的时刻(现在是 0 = 立刻可试)
        reconnect_delay = nil,   -- 退避间隔；**只有注册成功才清零**(见 handle_register_response)
        -- 下面两个一起构成活口判据，**别只看 await_since**：
        --   await_since  非 nil = "有必须被应答的请求在外面等"（仅作开关）
        --   last_rx_at   = 上次**收到**任何报文的时刻（真正拿来算时长的）
        -- 分开的理由：发出请求会刷新 await_since，若拿它算时长，**keepalive 比
        -- 超时还短时看门狗会被自家探测包一直喂饱，链路死了永远判不出来**（见 tick）。
        await_since    = nil,
        last_rx_at     = nil,
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
    -- 同样不要 `% 0xFFFFFFFF`（32 位整数下是 -1 → 结果恒为 0，
    -- 退化成固定字符串 "0000000000000000"，等于所有 branch/tag 都一样）。
    -- os.time() 到 2106 年前都在 32 位内；ticks 是 32 位毫秒计数，自己会回绕。
    return string.format("%08x%08x", os.time(), ticks)
end

local function emit(event, action, payload)
    if type(g_cb) ~= "function" then return end
    local ok, err = pcall(g_cb, event, action, payload or {})
    if not ok then log_error("事件回调异常", event, action, err) end
end

-- ------------------------------------------------------------------
-- 录像列表：归一化（时间字符串 ↔ Unix 秒）
-- ------------------------------------------------------------------

--[[
把 "YYYY-MM-DDThh:mm:ss" 解析成 Unix 秒。**字母 T 分隔**，不是空格。
（也接受空格：有些设备的配置是手写的，把这两种都认下来只多一行，
而认不出来会让**整条回放链路**静默失效——不值得为格式洁癖付这个代价。）

按 os.time() 即**设备本地时区**解释，与 C 层 record_format_time 用的
localtime_r 同一口径。两边必须一致：平台拿设备报的字符串换算回放 SDP 的
t= 行(实测 WVP 如此)，设备拿同一个 Unix 秒去 seek 录像文件；一边本地、
一边 UTC 的话，平台上看到的回放起点会整体差一个时区。

@return int|nil Unix 秒；格式不符返回 nil
]]
local function parse_time(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, h, mi, se =
        s:match("^(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):(%d%d)$")
    if not y then return nil end
    return os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(se),
    })
end

--[[
把配置里的录像列表归一化成"能同时喂两条链路"的形态：

    RecordInfo 应答  ← start_time / end_time（回给平台的字符串）
    回放会话         ← start_unix / end_unix / epoch（定位文件、判断播完）

**两者必须同源**：平台按它看到的 StartTime 换算出 t=，设备要拿同一个时刻
去录像文件里 seek。归一化只做一次，之后两条链路都读这一份 —— 各算各的迟
早会漂（record 层头文件把这条写成契约：epoch 必须与报给平台的 StartTime 同源）。

时间字符串解析不出来时**保留原字符串原样上报**，只标 playable=false：
设备确实有这段录像、只是自己认不出它的时刻，这时编一个时刻告诉平台，
比"这段回放不了"更糟。回放层会跳过不可播的段并说明原因。
]]
local function normalize_records(list)
    local out = {}

    if type(list) ~= "table" then
        return out
    end

    for i = 1, #list do
        local src = list[i]
        if type(src) == "table" then
            local e = {}
            for k, v in pairs(src) do e[k] = v end

            local s_unix = parse_time(e.start_time)
            local e_unix = parse_time(e.end_time)
            if s_unix and e_unix and e_unix > s_unix then
                e.start_unix = s_unix
                e.end_unix   = e_unix
                e.epoch      = s_unix       -- 文件首帧时刻，record_open 要它
                e.path       = e.file_path  -- 本机路径即报给平台的 FilePath
                e.playable   = true

                -- 回给平台的字符串按**设备本地时间**重排，保证与 epoch 同源。
                -- 配置若写的是 UTC 时刻，这一步会把它改掉 —— 那说明配置本身
                -- 与平台口径不一致，故把差异打出来，而不是静默改掉
                if gb and type(gb.record_format_time) == "function" then
                    local ss = gb.record_format_time(s_unix)
                    local es = gb.record_format_time(e_unix)
                    if ss and es then
                        if ss ~= e.start_time or es ~= e.end_time then
                            log_warn("录像时间按本地时区归一化", tostring(e.name or i),
                                     tostring(e.start_time) .. "→" .. ss,
                                     tostring(e.end_time) .. "→" .. es)
                        end
                        e.start_time, e.end_time = ss, es
                    end
                end
            else
                e.playable = false
                log_warn("录像时间无法解析，本段不可回放",
                         tostring(e.name or i), tostring(e.start_time),
                         tostring(e.end_time))
            end
            out[#out + 1] = e
        end
    end
    return out
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

--[[
从 From/To/Contact 头里取出 `;tag=xxx` 的值。

对话内收发请求要靠这个 tag 配对：平台订阅我们之后，我们发的 NOTIFY 必须
把平台的 tag 放进 **To**、把我们自己给的 tag 放进 **From**，两端才能认出
这是同一个对话。取不到就返回 nil（那说明这一端还没给 tag）。
]]
local function tag_of(header_value)
    if type(header_value) == "string" then
        return header_value:match(";%s*[Tt][Aa][Gg]%s*=%s*([^;%s>]+)")
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
        port        = st.sip_port,
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

@param opts 可选，两处例外（只有建立对话的请求才需要）：
    opts.to_tag  给回抄的 To 补一个 tag。**SUBSCRIBE 必须补**：
                 平台靠应答里的 To-tag 记住对话，之后发来的 NOTIFY 才对得上，
                 少了它这一端就只是"收到了个 200"，对话没建起来。
    opts.headers 追加的头，数组 {name=,value=}，如订阅应答要带的
                 Expires / Contact / Event
]]
local function reply_ok(msg, opts)
    local vias = {}
    for _, h in ipairs(msg.header_list or {}) do
        if h.name:lower() == "via" then
            vias[#vias + 1] = h.value
        end
    end

    local cseq_hdr = msg.headers["cseq"] or "1 MESSAGE"
    local cseq_num = tonumber(cseq_hdr:match("^(%d+)")) or 1
    local cseq_method = cseq_hdr:match("%s+(%a+)$") or "MESSAGE"

    local to_raw = msg.headers["to"]
    if opts and opts.to_tag and type(to_raw) == "string" and
       not tag_of(to_raw) then
        -- 平台没给 tag 才补；已经带了就原样回抄（重新格式化会丢东西）
        to_raw = to_raw .. ";tag=" .. opts.to_tag
    end

    local text = gb.sip_build({
        code        = 200,
        reason      = "OK",
        via_list    = vias,
        from_raw    = msg.headers["from"],
        to_raw      = to_raw,
        call_id     = msg.headers["call-id"],
        cseq        = cseq_num,
        cseq_method = cseq_method,
        contact     = false,
        host        = st.local_ip,
        port        = st.sip_port,
        extra_headers = opts and opts.headers or nil,
    })
    if text then
        net_send(text)
    else
        log_warn("构造 200 OK 失败")
    end
    return text
end

-- ------------------------------------------------------------------
-- 注册
-- ------------------------------------------------------------------

--[[
发一次 REGISTER，并登记"在等应答"。

`st.await_since` 是**信令链路的唯一活口判据**，见 tick 里那段说明 ——
UDP 上对端消亡既不给 CLOSED 也不给错误，只能靠"请求发出去没人答"来发现。

**起表要无条件，不能等发送成功**（2026-09-22 修）：原先写成 `if text then`，
于是"压根没发出去"这一类比"发出去了没人答"更糟的情况**反而没有任何机制在看它** ——
实测表现是 socket 报到 ON_LINE、本地 IP 也拿得到，但 DNS 那次没解析出来、
`net_send` 直接失败，然后设备**停在"已建链路但从未注册"的状态直到重启**。

不另立"发送失败即判死"的分支，是为了避免误伤：TCP 发送缓冲瞬时打满这类
无害抖动也会让 net_send 失败，而重建链路会**清掉名下所有点播/音频会话**
（见 `_teardown_signaling`），代价不小。借用已有的 15 秒判据，语义一致、风险最小。
]]
local function send_register(auth)
    local text = send_request("REGISTER", {
        expires = g_opts.expires or 3600,
        auth    = auth,
    })
    st.await_since = now_ms()
    return text
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

--[[
前向声明：`report_alarm` 要用。

订阅那一节排在 `report_alarm` **后面**（它挨着 process_packet，与其它请求
处理在一起），不在这里先声明的话，`report_alarm` 里的这个名字会解析成
**全局名**，运行时是 nil —— 报错是 `attempt to call a nil value`，而那要等
真的有人报警时才炸。定义处也不能再写 `local function`，那会造出一个新局部，
和这里声明的不是同一个。
]]
local send_notify

local function handle_register_response(msg)
    if msg.code == 200 then
        st.registered = true
        st.auth_tried = 0
        -- 注册成功 = 链路确实可用，退避清零（下次再断从 1s 起重来）
        st.reconnect_delay = nil
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
    local text = send_request("MESSAGE", {
        to_uri       = string.format("sip:%s@%s", g_opts.server_id, g_opts.domain),
        content_type = "Application/MANSCDP+xml",
        body         = body,
    })
    -- 同样无条件起表（为什么不能等 `if text` 见 send_register 的说明）：
    -- 心跳是信令链路的探针，发不出去跟没人答一样要能被发现
    st.await_since = now_ms()
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
local function send_catalog(msg, sn, sink)
    local o = g_opts
    local chans = o.channels or {}
    local sum = #chans

    --[[
    目录体的**投递方式**由调用方定(D. 见 handle_subscribe 的一次性拉取)：
      · 不给 sink      → 用 MESSAGE，这是"平台查询、设备应答"那条路
      · 给了一个函数   → 交给它送同一份体，订阅那条路要用 NOTIFY 送
    只把"投递"抽出来，"分页造体"仍留在这里 —— 两条路的目录内容必须一模一样，
    分成两份实现迟早会漂。
    ]]
    local deliver = sink or function(body)
        send_request("MESSAGE", {
            to_uri       = uri_of(msg.headers["from"])
                           or string.format("sip:%s@%s", o.server_id, o.domain),
            content_type = "Application/MANSCDP+xml",
            body         = body,
        })
    end

    if sum == 0 then
        log_warn("未配置通道，回 ERROR")
        local fail = gb.xml_build_response_fail("Catalog", sn, o.device_id, "ERROR")
        if fail then
            deliver(fail)
        end
        return
    end

    local page = o.catalog_page_size or 10
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
            deliver(body)
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
录像查询(RecordInfo)应答 —— **回放链路的第一环**。

平台的回放界面要先拿到设备的录像列表，用户才能选时间段，最后平台才发
回放的 INVITE(带 t= 起止时间)。所以不答这个查询，平台侧根本点不出回放。

录像列表由 g_opts.records 提供，与 channels 同样由调用方配置：
    records = {{
        device_id = "<通道编码>", name = "rec1", file_path = "1",
        address = "<地址>", start_time = "2026-09-17T00:00:00",
        end_time = "2026-09-17T01:00:00",
    }}

**没配就诚实地回 ERROR**：设备上确实没有可回放的录像，回一个空列表或
编造的条目会让平台侧显示不存在的录像 —— 那比"回放不了"更糟。
(想在联调时造一条来触发平台回放，那是**调用方/测试脚本**的事，
让它显式配置 records 即可，本模块不替它说谎。)

**应答里的 `DeviceID` 必须回抄查询里的那个**（2026-09-22 在真实平台上撞出来的）：
录像机(类型 132)的录像查询，平台是按**通道编码**问的
（`<DeviceID>…131…</DeviceID>`），而本端设备编码是 `…132…`。
原先一律填本端设备编码，平台便把这个应答配不回那次请求 —— 表现是
**"录像查询界面一直转圈"**，而设备侧只看得见 `录像应答已发 1 条`，
从日志上完全看不出是哪个字段的问题。

@param msg       平台的查询报文(取其 From 作为应答目的地)
@param sn        查询里的 SN，原样回填
@param target_id 响应体里的 DeviceID：**查询问的是谁就填谁**(通道或设备)；
                 查询里没有该项时回落到本端设备编码
]]
local function send_record_info(msg, sn, target_id)
    local o = g_opts
    -- 用归一化后的那份（不是 g_opts.records）：时间字符串与回放 seek 用的
    -- epoch 必须同源，见 normalize_records
    local recs = st.records or {}
    local dst_id = target_id or o.device_id
    local to_uri = uri_of(msg.headers["from"])
                   or string.format("sip:%s@%s", o.server_id, o.domain)

    if #recs == 0 then
        log_warn("未配置录像，回 ERROR")
        local fail = gb.xml_build_response_fail("RecordInfo", sn,
                                                dst_id, "ERROR")
        if fail then
            send_request("MESSAGE", {
                to_uri       = to_uri,
                content_type = "Application/MANSCDP+xml",
                body         = fail,
            })
        end
        return
    end

    -- 录像条数远小于通道数，且每条都带一段文字时间，故先不分页；
    -- 真到了几十条再按 catalog 那样分页(C 层单页上限 32 条)
    local body = gb.xml_build_record_info({
        device_id = dst_id,
        name      = (o.device and o.device.name) or "Record",
        sum_num   = #recs,
        items     = recs,
    }, sn)

    if body == nil then
        log_warn("录像应答构造失败(必选字段缺失?)，回 ERROR")
        local fail = gb.xml_build_response_fail("RecordInfo", sn,
                                                dst_id, "ERROR")
        if fail then
            send_request("MESSAGE", {
                to_uri       = to_uri,
                content_type = "Application/MANSCDP+xml",
                body         = fail,
            })
        end
        return
    end

    send_request("MESSAGE", {
        to_uri       = to_uri,
        content_type = "Application/MANSCDP+xml",
        body         = body,
    })
    log_info("录像应答已发", #recs, "条")
end

--[[
设备状态应答里的 **Alarmstatus**(告警设备列表)。

由通道配置派生：通道项带 `duty_status` 的才算"告警设备"，值取标准里的
ONDUTY / OFFDUTY / ALARM。不带这个字段的通道不写进去 —— 列表的长度是
**告警设备数**，把普通通道凑数填进去会让平台上的告警列表凭空多出几条，
而平台拿它做值守统计，多算比少算更难发现。

一个都不带时返回空表，C 层据此写自闭合的 `<Alarmstatus Num="0"/>`。
@return table 形如 { {device_id=..., duty_status=...}, ... }
]]
local function alarm_items()
    local out = {}
    for _, ch in ipairs(g_opts.channels or {}) do
        if ch.duty_status then
            out[#out + 1] = {
                device_id   = ch.device_id,
                duty_status = ch.duty_status,
            }
        end
    end
    return out
end

--[[
应答平台的查询：先回 200 OK，再回带应答体的 MESSAGE。

先回 200 OK 是 SIP 的要求(任何请求都要有响应)，且必须回抄请求的 Via/
From/To；MESSAGE 里才是 MANSCDP 的业务应答。少任何一个，WVP 这类
平台都可能判定设备异常。
]]
--[[
处理平台下发的设备控制(DeviceControl)。

`DeviceControl` 只是一个**信封**，里面装的是哪一种控制由子元素决定，平台不会
额外告诉你。所以第一步永远是"识别控制项"（交给 C 层的 `devctl_parse`），
再按识别结果分派 —— 以前是直接 `xml_get(body, "PTZCmd")` 碰运气，取不到就
一律当"不支持"，分不清"平台发的是拉框缩放"和"报文坏了"。

**组件不碰硬件**：每一种控制都只解析出参数，交给应用注册的处理者去执行
（`on_ptz` / `on_drag_zoom` / `on_home_position`）。设备接的云台、ISP、
镜头千差万别，组件替它做主只会做错。

几个刻意的取舍：

  · **没有注册处理者时回 `Result=ERROR`**。设备确实没有对应能力，报"成功"
    是谎报 —— 平台上会显示操作成功而实际什么都没发生，那种"看着正常"的假象
    比明确失败难查得多。
  · 处理者抛异常也回 ERROR：异常既不能打断收包循环，也不能谎报成功。
  · 不认识的子类型也回 ERROR，并把 kind 打进日志 —— 至少能看出平台发了什么。

另外：**云台校验字节对不上不拒收**，只记一行日志。平台自己拼的包就有已知偏差
（变倍速度取 16 时 byte6 与其校验和差 0x10），设备因校验拒收会把"平台能用"
变成"设备不认"。
]]
local function handle_device_control(msg, sn)
    local o = g_opts

    local function answer(result)
        local text = gb.xml_build_response("DeviceControl", sn, o.device_id, result)
        if not text then
            log_error("设备控制应答构造失败")
            return
        end
        send_request("MESSAGE", {
            to_uri       = uri_of(msg.headers["from"])
                           or string.format("sip:%s@%s", o.server_id, o.domain),
            content_type = "Application/MANSCDP+xml",
            body         = text,
        })
    end

    --[[
    交给应用执行一个控制项。

    统一在这里收口，是为了让"没注册处理者""处理者抛异常"这两种情况在所有
    控制项上行为一致 —— 逐个子类型各写一遍迟早会漏掉一种，而漏掉的表现是
    平台侧一直等到超时。
    ]]
    local function dispatch(handler, ev_name, arg, desc)
        if type(handler) ~= "function" then
            log_warn("收到" .. desc .. "但没有注册处理者，回 ERROR", desc)
            emit(ev_name, "unsupported", { arg = arg })
            answer("ERROR")
            return
        end
        local ok, err = pcall(handler, arg)
        if not ok then
            log_error(desc .. "处理异常", err)
            answer("ERROR")
            return
        end
        answer("OK")
    end

    if type(gb.devctl_parse) ~= "function" then
        log_warn("C 层没有设备控制绑定(固件版本太旧?)，回 ERROR")
        answer("ERROR")
        return
    end

    local d = gb.devctl_parse(msg.body or "")
    if not d then
        log_warn("DeviceControl 无法识别，回 ERROR")
        answer("ERROR")
        return
    end

    -- 云台：8 字节位域指令，布局见 C 层 luat_gb28181_ptz.h
    if d.kind == gb.DEVCTL_PTZ then
        local cmd = gb.ptz_parse(d.ptz_hex)
        if not cmd then
            log_warn("PTZCmd 无法解析", tostring(d.ptz_hex))
            answer("ERROR")
            return
        end
        if not cmd.ok then
            log_warn("PTZCmd 校验字节对不上，仍按解析结果处理", d.ptz_hex)
        end
        dispatch(g_ptz_cb, "ptz", cmd, "云台指令")
        return
    end

    -- 2022 新增：拉框放大 / 缩小。六个参数的单位由平台前端决定，本层不换算
    if d.kind == gb.DEVCTL_DRAG_ZOOM_IN or d.kind == gb.DEVCTL_DRAG_ZOOM_OUT then
        dispatch(g_drag_zoom_cb, "drag_zoom", d, "拉框缩放指令")
        return
    end

    -- 2022 新增：看守位。**平台会等这条应答的 Result**（见 devctl.h 的表）
    if d.kind == gb.DEVCTL_HOME_POSITION then
        dispatch(g_home_position_cb, "home_position", d, "看守位指令")
        return
    end

    --[[
    其余已识别但本端不实现的控制项（远程启动、录像控制、布防撤防、告警复位、
    强制关键帧）。**它们里的好几项平台会等应答**，所以必须回 ERROR 而不是
    沉默 —— 沉默会让平台侧一直等到超时。
    ]]
    log_warn("本端未实现的 DeviceControl 子类型", tostring(d.kind),
             "value=" .. tostring(d.value))
    emit("device_control", "unsupported", { kind = d.kind, value = d.value })
    answer("ERROR")
end

local function handle_query(msg)
    --[[
    **Notify 与 Query 的处理方式完全不同，必须先分流**：

      Query  → 要回业务应答(MANSCDP 的 <Response>)，否则平台认为设备没响应
      Notify → 只需 SIP 200 OK，**不要回 MANSCDP 应答**

    早先这里不分，Notify 也走 Query 的分支 —— 未知 CmdType 会回一个
    `Result=ERROR` 的 Response。对 Query 那是"设备在线但给不了"，对 Notify
    却是**明确告诉平台"设备拒绝"**：实测 WVP 收到后不建立待接通的广播，
    于是设备随后按 §9.12 发起的 INVITE 被判"非语音广播"而 403 —— 整条
    语音广播/对讲链路断在这里。
    ]]
    if msg.body and msg.body:find("<Notify>", 1, true) then
        local q = gb.xml_parse_query(msg.body)
        local cmd = (q and q.cmd_type) or "?"
        reply_ok(msg)                     -- Notify 只要 SIP 200 OK
        log_info("收到 Notify", cmd, "SN=" .. tostring(q and q.sn))
        emit("notify", cmd, {
            sn = q and q.sn, device_id = q and q.device_id, body = msg.body,
        })

        -- §9.12：收到广播通知后，**设备应主动向平台发起 INVITE**。
        -- 这一步由本层自动完成，应用无需介入(可用 g_opts.auto_broadcast = false 关闭)
        if cmd == "Broadcast" and g_opts.auto_broadcast ~= false then
            local call_id, err = M.start_talk({ session_name = "Broadcast" })
            if call_id then
                log_info("已按广播通知发起音频会话", call_id)
            else
                log_warn("按广播通知发起音频会话失败", err)
            end
        end
        return
    end

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
            -- 扩展信息：配置里给了才写，没给就不出现 <Info>
            infos        = d.infos,
        }, sn)

    elseif cmd == "DeviceStatus" then
        body = gb.xml_build_device_status({
            device_id   = o.device_id,
            online      = "ONLINE",
            status      = "OK",
            encode      = "ON",
            record      = "OFF",
            device_time = os.date("%Y-%m-%dT%H:%M:%S"),
            -- 告警设备列表：由通道配置派生(通道项带 duty_status 才算告警设备)，
            -- 没有则 C 层写自闭合的 <Alarmstatus Num="0"/>
            alarms      = alarm_items(),
            infos       = (o.device or {}).infos,
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

    -- 录像查询走与 Catalog 同样的"独立发送"路径(应答体是列表，不是单条)
    if cmd == "RecordInfo" then
        emit("query", cmd, { sn = sn, supported = true })
        -- 把查询里的 DeviceID 带下去：录像机是按通道问的，见该函数说明
        send_record_info(msg, sn, q and q.device_id)
        return
    end

    -- 云台控制：与上面几个查询不同，它是**要设备做动作**的（见该函数的说明）
    if cmd == "DeviceControl" then
        handle_device_control(msg, sn)
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
        -- 点播会话与主动发起的音频会话共用这个端口池：
        -- 两者都真的占了 UDP 端口，分开分配迟早会撞在一起
        for _, s in pairs(st.sessions) do
            if s.local_port == p then used = true break end
        end
        if not used then
            for _, s in pairs(st.talks) do
                if s.port == p then used = true break end
            end
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

--[[
关闭会话的媒体通道。

**这是会话销毁的唯一出口**（BYE、失活回收、以及 INVITE 受理失败的各条分支
都走它），所以回放源也在这里被告知停止 —— 漏了这一步的表现是：会话没了而
回放泵还在读文件、往一个已关闭的 socket 推帧。
]]
local function media_close(sess)
    -- 先停回放再关 socket：回放泵可能正卡在 push_frame 里
    if sess.is_playback and g_playback_cb then
        local ok, err = pcall(g_playback_cb, sess, "stop")
        if not ok then log_error("停止回放异常", err) end
    end
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
        port        = st.sip_port,
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
--[[
剥离 RTP 头，返回音频载荷与"是否 PS 封装"。

头部长度**不是恒定的 12 字节**：CSRC 计数在字节 1 的低 4 位，扩展位(X)置位时
还要再跳过 4 字节扩展头 + 扩展内容，填充位(P)置位时末尾要按最后一个字节的值截断。
少算任何一项都不会报错，只会**静默地多切或少切几个字节** —— 听感上是持续的
背景噪声或周期性咔哒声，极难倒查到 RTP 头解析上。

@param pkt 完整 RTP 包
@return string|nil 载荷（**未做 PS 解封装**，由上层决定怎么处理）
@return boolean 载荷是否以 PS 起始码 00 00 01 BA 开头
]]
local function audio_payload(pkt)
    local n = #pkt
    if n < 12 then return nil end

    local b1 = string.byte(pkt, 1)
    local hdr = 12 + (b1 % 16) * 4          -- 固定头 + CSRC
    if (b1 % 32) >= 16 then                 -- X 位(bit4)：扩展头
        if n < hdr + 4 then return nil end
        local ext_words = (string.byte(pkt, hdr + 3) << 8) | string.byte(pkt, hdr + 4)
        hdr = hdr + 4 + ext_words * 4
    end
    if n <= hdr then return nil end

    local body = string.sub(pkt, hdr + 1)
    if (b1 % 64) >= 32 then                 -- P 位(bit5)：末尾填充
        local pad = body:byte(-1)
        if pad and pad > 0 and pad < #body then
            body = body:sub(1, #body - pad)
        end
    end
    if #body < 4 then return nil end

    local is_ps = (body:byte(1) == 0x00 and body:byte(2) == 0x00 and
                   body:byte(3) == 0x01 and body:byte(4) == 0xBA)
    return body, is_ps
end

--[[
投递一个收到的音频包：剥头 → 统计 → 交给上层回调。

前 5 个包打十六进制是**判定平台用哪种封装的直接证据**（PS 流以 00 00 01 BA 开头，
裸 PCMA 则直接是音频载荷），配合 rx_ps / rx_raw 两个累计计数，
一次对讲就能确定，不必再猜。

放在这里（而不是音频会话那段）是因为**发起方与受理方两处都要用** ——
Lua 的局部变量只能向后可见，定义在使用点之后会静默解析成全局 nil。
]]
local function audio_deliver(sess, pkt)
    sess.rx_pkts = (sess.rx_pkts or 0) + 1
    sess.rx_bytes = (sess.rx_bytes or 0) + #pkt
    if sess.rx_pkts <= 5 then
        local hex = {}
        for i = 1, math.min(16, #pkt) do
            hex[#hex + 1] = string.format("%02X", string.byte(pkt, i))
        end
        log_info("音频包", #pkt, "字节:", table.concat(hex, " "))
    end

    local body, is_ps = audio_payload(pkt)
    if not body then return end

    -- 两种封装的累计比例：跑一次对讲就能看出平台到底用哪种
    if is_ps then
        sess.rx_ps = (sess.rx_ps or 0) + 1
    else
        sess.rx_raw = (sess.rx_raw or 0) + 1
    end

    -- 回调里跑的是用户的播放逻辑，异常不能打断收包循环
    if type(g_audio_cb) == "function" then
        local ok, err = pcall(g_audio_cb, sess, body, is_ps)
        if not ok then log_error("音频回调异常", err) end
    end
end

--[[
受理**平台主动发起**的音频 INVITE（语音对讲的双向/上行方向）。

为什么必须受理：实测 WVP 在语音对讲过程中会发这样一条；设备若回 488，
平台判定对讲失败并**把整条对讲停掉** —— 现象是"音频收到一半就断"，
而 SIP 层此前一切正常，极难倒查。

本端只做**受理与收流**；把本端采集的音频回传（上行）是后续的事。
]]
local function handle_audio_invite(msg, s)
    local o = g_opts

    -- GB28181 的语音是 G.711A；平台若要求别的编码我们做不了
    if s.rtpmap and not s.rtpmap:match("^PCMA/") then
        log_warn("平台要求的音频编码不是 PCMA, 拒绝", s.rtpmap)
        reply(msg, 488, "Not Acceptable Here")
        emit("invite", "rejected", { reason = "非 PCMA 音频" })
        return
    end

    local port = alloc_rtp_port()
    if not port then
        log_warn("无可用端口")
        reply(msg, 503, "Service Unavailable")
        return
    end

    local call_id = msg.headers["call-id"]
    -- 打印平台发来的 SDP：这条 INVITE 的形态只在实机上见得到，
    -- 出问题时这行日志是唯一的线索
    log_info("收到平台的音频 INVITE", s.session_name or "?", "本地端口", port)
    for line in tostring(msg.body or ""):gmatch("[^\r\n]+") do
        log_info("  平台 SDP:", line)
    end

    local sess = {
        call_id      = call_id,
        session_name = s.session_name or "Talk",
        port         = port,
        incoming     = true,
        state        = "established",
        remote_ip    = s.conn_ip,
        remote_port  = s.port,
        rx_pkts      = 0,
        rx_bytes     = 0,
        -- 供失活判定：TCP 腿若始终连不上(如平台端口不可达)，要能被回收，
        -- 否则会一直挂在 talks() 里(实测见过"0 个包"挂几分钟的僵尸会话)
        started      = true,
        started_ms   = now_ms(),
    }

    --[[
    传输按平台 SDP 的 `m=` 协议走 —— 实测这条 INVITE 用的是 **TCP**
    （`m=audio 50503 TCP/RTP/AVP 8` + `a=setup:passive`）：平台侧 TCP 监听，
    本端要**作为客户端连过去**，之后按 RFC 4571 的 [2 字节长度][RTP 包] 取数据。
    按 UDP 处理的话一个包都收不到，而 SIP 层看起来完全正常。
    ]]
    local is_tcp = (s.tcp == true)
    sess.media_tcp = is_tcp
    sess.rxbuf = ""            -- TCP 下的字节流重组缓冲（RFC 4571 定界）

    local netc = socket.create(g_opts.adapter, function(sc, event, param)
        if event == socket.ON_LINE then
            sess.link_up = true
            sess.link_up_once = true      -- 供失活判定区分"从未连上"与"连上后断了"
            log_info("音频链路已建立")
            emit("talk", "socket", { call_id = sess.call_id, event = "online" })
            return
        end
        if event == socket.CLOSED then
            -- TCP 承载下连接失败/断开是**异步**的：connect 返回 true 只代表
            -- 开始连了。不记这个事件的话，连不上时表现为"静默地收不到数据"
            sess.link_up = false
            log_warn("音频链路断开")
            emit("talk", "socket", { call_id = sess.call_id, event = "closed" })
            return
        end
        if event ~= socket.EVENT or param ~= 0 then return end
        local rxbuf = zbuff.create(2048)
        if not rxbuf then return end
        while true do
            local ok, n = socket.rx(sc, rxbuf)
            if not ok or not n or n <= 0 then break end
            local d = rxbuf:toStr(0, rxbuf:used())
            rxbuf:del()
            if is_tcp then
                -- RFC 4571：TCP 上没有"包"的边界，必须按长度前缀切
                sess.rxbuf = sess.rxbuf .. d
                while #sess.rxbuf >= 2 do
                    local plen = (string.byte(sess.rxbuf, 1) << 8) | string.byte(sess.rxbuf, 2)
                    if #sess.rxbuf < 2 + plen then break end
                    local pkt = string.sub(sess.rxbuf, 3, 2 + plen)
                    sess.rxbuf = string.sub(sess.rxbuf, 3 + plen)
                    audio_deliver(sess, pkt)
                end
            else
                audio_deliver(sess, d)
            end
        end
    end)
    if not netc then
        log_warn("音频 socket 创建失败")
        reply(msg, 500, "Server Internal Error")
        return
    end

    if is_tcp then
        -- 平台是 passive，本端是 active：不绑本地端口，直接连过去
        if not s.conn_ip or not s.port or
           not socket.config(netc, 0, false) or
           not socket.connect(netc, s.conn_ip, s.port) then
            socket.close(netc)
            log_warn("音频 TCP 连接失败", s.conn_ip, s.port)
            reply(msg, 500, "Server Internal Error")
            return
        end
    else
        if not socket.config(netc, port, true) then
            socket.close(netc)
            log_warn("音频端口绑定失败")
            reply(msg, 500, "Server Internal Error")
            return
        end
        -- 必须 connect 到平台 SDP 给的那对地址：一来只收协商好的来源，
        -- 二来（实测）这套模拟器上未 connect 的 UDP socket 收不到任何数据
        if s.conn_ip and s.port then
            socket.connect(netc, s.conn_ip, s.port)
        end
    end
    sess.netc = netc

    -- 上行发送用的媒体队列。**载荷类型必须是 8(PCMA)** ——
    -- 队列默认的 96 是给 PS 视频的，音频用 96 平台会当视频解
    -- SSRC 用平台在它 SDP 的 y= 里给的那个：回传的流要和它对上
    sess.media = gb.media_new(s.ssrc or 0, 0, o.media_queue_size or 32768, 8)
    if not sess.media then
        socket.close(netc)
        log_warn("音频发送队列创建失败")
        reply(msg, 500, "Server Internal Error")
        return
    end
    sess.frame_ts = 0

    st.talks[call_id] = sess

    local answer = gb.sdp_build({
        owner_id     = o.device_id,
        ip           = st.local_ip,
        session_name = sess.session_name,
        media        = "audio",
        port         = port,
        payload_type = 8,
        rtpmap       = "PCMA/8000",
        -- 平台发起的这条是对讲（双向），本端应答可收可发；
        -- 上行发送尚未实现，故先只声明接收
        direction    = "recvonly",
        has_ssrc     = 0,
        -- 承载必须与平台要求一致；setup 方向取反（平台 passive → 本端 active）
        proto        = is_tcp and gb.PROTO_TCP or gb.PROTO_UDP,
        setup        = is_tcp and gb.TCP_SETUP_ACTIVE or nil,
        connection   = is_tcp and gb.TCP_CONN_NEW or nil,
    })
    if not answer then
        socket.close(netc)
        st.talks[call_id] = nil
        log_warn("音频应答 SDP 构造失败")
        reply(msg, 500, "Server Internal Error")
        return
    end

    reply(msg, 200, "OK", answer, "application/sdp")
    log_info("已受理平台的音频 INVITE", call_id)
    emit("talk", "accepted", {
        call_id = call_id, session_name = sess.session_name,
        local_port = port, incoming = true,
    })
end

local function handle_invite(msg)
    local o = g_opts

    --[[
    把收到的 SDP 原样打出来。**这是排查点播类问题的第一手证据**：
      s= 行区分实时(Play/Playback/Download)——同一个 INVITE 处理函数
         要服务三类语义完全不同的请求
      t= 行是回放的**起止时间**(两个 Unix 秒)，只在回放时给出
      u= 行是 `<设备编码>:<录像ID>`，**不是时间段** —— 实测(WVP-Pro
         2026-09-17)填的是 `:0`，曾经误以为它是起止时间
      m=/a=rtpmap 决定承载与封装：回放 offer 常见一次给多个载荷类型
         (如 `96 97 98 99` = PS/MPEG4/H264/H265)，要靠 m= 声明的那个去挑
    与对讲路径(handle_talk_response)保持同一做法，避免"音频有日志、视频没有"。
    ]]
    for line in tostring(msg.body or ""):gmatch("[^\r\n]+") do
        log_info("  平台 INVITE SDP:", line)
    end

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

    -- 语音对讲时平台还会**反向**给设备发一条音频 INVITE（双向/上行方向）
    if s.media == "audio" then
        handle_audio_invite(msg, s)
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
    --[[
    判回放：**优先看 t= 行**(has_time)，那是 SDP 自己规定的语义 ——
    t=0 0 是实时，给了具体时间段才是回放。

    s= 行的字符串只作兜底：平台对它的写法不统一(Play/Playback/Download…)，
    拿它当主判据会在换平台时失效。两者取或，任一成立即认为回放。

    (别去解析 u= 行 —— 实测它是 `<设备编码>:<录像ID>`，不是时间段)
    ]]
    local is_playback = (s.has_time == true) or
                        (s.session_name == "Playback" or
                         s.session_name == "Download")
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
        -- 回放的时间段(Unix 秒)，仅 is_playback 时有意义 ——
        -- 回放会话要据此在录像里定位起点(start)，end 用于判断是否播完
        t_start      = s.t_start,
        t_end        = s.t_end,
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
        -- 回放时给出时间段(Unix 秒)，实时点播为 nil —— 见 is_playback 的说明
        is_playback = is_playback,
        t_start = s.t_start,
        t_end   = s.t_end,
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

        --[[
        回放会话的媒体**不由应用推** —— 源是设备本地的录像文件，所以这里要
        直接交给回放源。实时点播照旧只发事件，等应用推帧。

        没注册回放源时不能静默：现象会是"平台建了会话却一个字节都收不到"，
        与"录像文件坏了"在日志里长得一样
        ]]
        if sess.is_playback then
            if type(g_playback_cb) == "function" then
                local ok, err = pcall(g_playback_cb, sess, "start")
                if not ok then
                    log_error("启动回放异常", err)
                    emit("playback", "error", { call_id = sess.call_id,
                                                reason = tostring(err) })
                end
            else
                log_warn("回放会话已建立，但没有注册回放源",
                         "请 require exgb28181playback 并 setup()")
                emit("playback", "unavailable", {
                    call_id = sess.call_id,
                    reason  = "未注册回放源(exgb28181playback)",
                })
            end
        end

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
        port         = st.sip_port,
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
--[[
 回收失活的会话。

 **点播会话（st.sessions）与音频会话（st.talks）都要遍历** ——
 实测出现过音频会话连不上（TCP 腿的端口没发布）却一直挂在 talks() 里的情况：
 `收流中 [xxx]: 0 个包`，既不报错也不消失。判据与点播共用
 session_death_reason（音频会话同样带 media_tcp / link_up / started 字段）。
    ]]
local function reap_dead_sessions()
    local now = now_ms()
    local function sweep(tbl, tag)
        for call_id, sess in pairs(tbl) do
            local reason = M.session_death_reason(sess, now)
            if reason then
                log_warn("回收失活会话", tag, call_id, reason)
                media_close(sess)
                tbl[call_id] = nil
                emit("call", "ended", { call_id = call_id, reason = reason })
            end
        end
    end
    sweep(st.sessions, "点播")
    sweep(st.talks, "音频")
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

    --[[
    时间戳按真实经过的毫秒数推进，避免与平台侧的时钟漂移。

    **这里原先写的是 `% 0xFFFFFFFF`，在 32 位整数下是错的**：`0xFFFFFFFF`
    会溢出成 -1，而 `x % -1` 恒等于 0 —— 于是**每一帧的 RTP 时间戳都是 0**。
    这是个"本地怎么测都看不出来"的故障：载荷是对的、包序是对的、ffmpeg 也能解，
    只有真正按时间戳组帧的接收端(ZLM)会拒收，表现为"平台收到了流但一直不出图"。
    实测就是这样：ZLM 打了"允许RTP推流"后再无下文，而把同一份字节流用递进的
    时间戳喂进去就正常注册。

    取模本来是想做 32 位回绕，但**不需要**：RTP 时间戳字段本就 32 位，C 层收的是
    uint32_t，超出部分在转换时自然回绕；32 位整数的 Lua 里加法自己也回绕。
    ]]
    local now = now_ms()
    if sess.last_ms then
        sess.frame_ts = sess.frame_ts + (now - sess.last_ms) * 90
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

-- ------------------------------------------------------------------
-- 设备主动发起的音频会话(里程碑 M6.1 第一步：发起方)
-- ------------------------------------------------------------------
--[[
GB28181-2016 §9.12 的语音广播/对讲与**点播方向相反**：

    平台发 Broadcast 通知(MANSCDP) → 设备回 200 OK
    → **设备向平台发起 INVITE**(s=Broadcast, m=audio, PCMA/8000)
    → 平台回 200 OK(带它自己的 SDP) → 设备回 ACK → 平台推音频

本段只做到"发起 → 应答 → ACK"，外加**观测**收到的音频包。
音频的解码与播放(PCMA→PCM→喇叭)是下一步的事，不在这一段里。

观测部分的意义不只在于功能：平台的应答 SDP 与随后真实的 RTP 载荷，
是判定"音频到底走裸 PCMA 还是 PS 内 PES 0xC0"的直接证据 ——
这个封装问题在标准与实现里两种都存在，只能实测。
]]

-- 绑定本地端口收音频。
-- **不 connect**：平台从哪个端口发音频要等它的应答 SDP 才知道，
-- 事先 connect 会把所有来源都过滤掉。生产环境可在拿到对端地址后再收紧。
local function audio_open(sess)
    local netc = socket.create(g_opts.adapter, function(sc, event, param)
        if event ~= socket.EVENT or param ~= 0 then return end
        local rxbuf = zbuff.create(2048)
        if not rxbuf then return end
        while true do
            local ok, n = socket.rx(sc, rxbuf)
            if not ok or not n or n <= 0 then break end
            local d = rxbuf:toStr(0, rxbuf:used())
            rxbuf:del()
            audio_deliver(sess, d)
        end
    end)
    if not netc then return false, "创建音频 socket 失败" end
    if not socket.config(netc, sess.port, true) then
        socket.close(netc)
        return false, "音频端口绑定失败"
    end
    sess.netc = netc
    return true
end

--[[
向平台发起一个音频会话(语音广播 / 对讲的收流方向)。

@api exgb28181client.start_talk([opts])
@table opts 可选 { session_name = "Broadcast"|"Talk", port = 本地端口 }
@return string|nil 本次会话的 Call-ID(后续 stop_talk 用它)
@return string|nil 失败原因
]]
function M.start_talk(opts)
    opts = opts or {}
    local o = g_opts

    if not st.registered then
        return nil, "尚未注册"
    end
    if not st.netc or not st.local_ip then
        return nil, "信令未就绪"
    end

    local port = opts.port or alloc_rtp_port()
    if not port then
        return nil, "无可用端口"
    end

    -- 对话标识必须**独立于注册**：注册那套 Call-ID/tag 属于注册事务，
    -- 拿来发起 INVITE 会让平台把两者混在一起
    local call_id  = gen_token("talk") .. "@" .. tostring(st.local_ip)
    local from_tag = "luat" .. gen_token("tag")

    local sess = {
        call_id      = call_id,
        from_tag     = from_tag,
        session_name = opts.session_name or "Broadcast",
        port         = port,
        state        = "inviting",
        rx_pkts      = 0,
        rx_bytes     = 0,
    }

    local sdp = gb.sdp_build({
        owner_id     = o.device_id,
        ip           = st.local_ip,
        session_name = sess.session_name,
        media        = "audio",
        port         = port,
        payload_type = 8,          -- G.711A
        rtpmap       = "PCMA/8000",
        -- 本端只收：这与 §9.12 里设备作为接收方一致
        direction    = "recvonly",
        -- 音频**不带 y=**：SSRC 由平台侧决定（它没收到会自己生成一个随机值）。
        -- 带上一个 0 反而可能被当成非法 SSRC —— 实测 WVP 对 y=0000000000
        -- 的处理就是"取不到来源"
        has_ssrc     = 0,
    })
    if not sdp then
        return nil, "音频 SDP 构造失败"
    end

    local ok, err = audio_open(sess)
    if not ok then
        return nil, err
    end

    st.talks[call_id] = sess

    --[[
    **Subject 头是必须的**，携带 GB28181 的
        <发送者ID>:<SSRC>,<接收者ID>:<SSRC>

    **顺序按媒体流方向，不是按谁发起请求**：本会话是 recvonly（平台发音频、
    本端收），故发送者是**平台**、接收者是**本端通道**。写反的后果实测是
    WVP 拿平台的 id 去查通道 → 查不到 → 403 Forbidden：
      WVP 的 InviteMessageInfo 里 channelIds[0]→targetChannelId、
      channelIds[1]→**sourceChannelId**，而它用 sourceChannelId 查通道。

    SSRC 段填 0：音频的 SSRC 由平台侧生成，本端不指定。
    多通道设备应传 channel_id 指定要对讲的通道，缺省用设备编码。
    ]]
    local chan = opts.channel_id or o.device_id
    local subject = string.format("%s:0,%s:0", o.server_id, chan)

    local text = send_request("INVITE", {
        -- To 是**平台**，不是本端(send_request 的默认是给注册用的)
        to_uri       = string.format("sip:%s@%s", o.server_id, o.domain),
        from_tag     = from_tag,
        call_id      = call_id,
        content_type = "application/sdp",
        extra_headers = { { name = "Subject", value = subject } },
        body         = sdp,
    })
    if not text then
        media_close(sess)
        st.talks[call_id] = nil
        return nil, "INVITE 发送失败"
    end

    log_info("已发起音频会话", sess.session_name, "本地端口", port, call_id)
    emit("talk", "inviting", { call_id = call_id, session_name = sess.session_name })
    return call_id
end

-- 给平台的 2xx 应答回 ACK：不回的话平台会重传 200 直到超时，音频也不会开始
local function send_ack(msg)
    local vias = {}
    for _, h in ipairs(msg.header_list or {}) do
        if h.name:lower() == "via" then vias[#vias + 1] = h.value end
    end
    local cseq = tonumber((msg.headers["cseq"] or "1"):match("^(%d+)")) or 1
    local text = gb.sip_build({
        method      = "ACK",
        uri         = string.format("sip:%s@%s", g_opts.server_id, g_opts.domain),
        transport   = string.upper(g_opts.transport),
        host        = st.local_ip,
        port        = st.sip_port,
        branch      = gen_token("z9hG4bK"),
        via_list    = vias,
        from_raw    = msg.headers["from"],
        to_raw      = msg.headers["to"],
        call_id     = msg.headers["call-id"],
        cseq        = cseq,
        cseq_method = "ACK",
        contact     = false,
    })
    if text then net_send(text) end
    return text
end

-- 处理发起的音频会话收到的应答
local function handle_talk_response(msg)
    local call_id = msg.headers["call-id"]
    local sess = st.talks[call_id]
    if not sess then return false end

    --[[
    1xx 是临时应答(Trying / Ringing 等)，**不是失败**：平台已受理，最终应答
    还在后面。这里必须原样等待，绝不能走下面的失败分支 —— 那会
    media_close() 释放本地端口，等真正的 200 OK 到达时会话已经没了。
    (实测踩到：WVP 先回 100 Trying，被当成拒绝，链路明明通了却看着像 403。)
    ]]
    if msg.code >= 100 and msg.code < 200 then
        log_info("音频会话临时应答", msg.code, msg.reason)
        return true
    end

    if msg.code >= 200 and msg.code < 300 then
        sess.state = "established"

        --[[
        按平台的应答 SDP 把音频 socket **connect 到对端的收流地址**。

        两重理由：
        1) 正确性：只接受协商好的那一对端，别把端口开给所有人
        2) **可工作性**：实测这套模拟器上，绑定了但未 connect 的 UDP socket
           **收不到任何数据**（回调不触发）—— 音频包全被丢掉，而 SIP 层
           看起来完全正常，极难倒查
        ]]
        local rs = gb.sdp_parse(msg.body)
        if rs and rs.conn_ip and rs.port and rs.port > 0 then
            if socket.connect(sess.netc, rs.conn_ip, rs.port) then
                sess.remote_ip, sess.remote_port = rs.conn_ip, rs.port
                log_info("音频收流已连向", rs.conn_ip, rs.port)
            else
                log_warn("音频收流 connect 失败", rs.conn_ip, rs.port)
            end
        else
            log_warn("平台 SDP 里没有可用的收流地址")
        end
        -- 记下对端 tag：结束时的 BYE 是**对话内**请求，To 必须带它，
        -- 否则平台按无对话的请求处理（回 481 或干脆不认）
        sess.remote_tag = (msg.headers["from"] or ""):match(";tag=([^;%s]+)")
        --[[
        平台的 SDP 里能看到它准备怎么发音频（`m=` 的协议、`a=rtpmap`）
        与从哪发（`c=`/`m=` 的地址端口）—— 这正是我们要的那条证据
        ]]
        log_info("音频会话已建立", call_id)
        for line in tostring(msg.body or ""):gmatch("[^\r\n]+") do
            log_info("  平台 SDP:", line)
        end
        send_ack(msg)
        emit("talk", "accepted", {
            call_id = call_id, session_name = sess.session_name,
            sdp = msg.body, local_port = sess.port,
        })
    else
        sess.state = "failed"
        log_warn("音频会话被拒", msg.code, msg.reason)
        media_close(sess)
        st.talks[call_id] = nil
        emit("talk", "failed", {
            call_id = call_id, code = msg.code, reason = msg.reason,
        })
    end
    return true
end

--[[
主动上报一条报警（Notify/Alarm，GB/T 28181 §9.11）。

**方向是设备 → 平台**：平台没问，设备自己发。门铃按下、移动侦测、防拆
这类事件都在这里出去。平台只回 SIP 层的 200 OK，不会回 MANSCDP 应答，
所以拿到 `true` 只代表"报文已经交给 socket"，不代表平台已经收下。

@api exgb28181client.report_alarm(opts)
@table opts 字段与 gb28181.xml_build_alarm 的 cfg 一致：
    device_id   必填，**平台的告警列表挂的是它**，通常是通道编码而不是设备编码
    priority    必填，1~4，1 最高
    method      必填，1 电话 / 2 设备 / 3 短信 / 4 GPS / 5 视频 / 6 设备故障 / 7 其他
    time        可选，"YYYY-MM-DDThh:mm:ss"；**缺省取本机当前时间**
    description / alarm_type / longitude / latitude 可选
    alarm_type  的含义随 method 变（同是 2，method=2 是"设备防拆"、
                method=5 是"移动侦测"），本层只透传不解释
@return boolean 是否已发出
@return string|nil 失败原因

失败**不重试、不缓存**，而是丢弃并 emit 一条 `alarm/failed` 事件：

  · 报警是应用触发的一次性事件，应用最清楚它有多要紧 —— 门铃按下的那一次
    与"温度超阈值"里的某一次，重试策略天差地别，组件替它决定只会做错；
  · 组件里排队还要定队列长度、超时、去重（同一事件重复触发时算一条还是两条），
    每一条都是业务判断，放在这里就是猜。

事件回调用 exgb28181client.on() 注册，可拿到 reason 与原始 opts：

    if event == "alarm" and action == "failed" then
        log.warn("gb28181", "报警没能上报", data.reason)
    end
]]
function M.report_alarm(opts)
    if type(opts) ~= "table" then
        emit("alarm", "failed", { reason = "opts 必须是 table" })
        return false, "opts 必须是 table"
    end
    if type(gb.xml_build_alarm) ~= "function" then
        emit("alarm", "failed", { reason = "C 层没有报警绑定(固件版本太旧?)", opts = opts })
        return false, "C 层没有报警绑定"
    end
    if g_opts == nil then
        -- start() 之前调用。emit 而不是直接抛：报警多发生在应用刚起来、
        -- 还没接到平台的时候，这里抛异常会把它变成一次崩溃
        emit("alarm", "failed", { reason = "服务未启动", opts = opts })
        return false, "服务未启动"
    end

    local o = g_opts
    local cfg = {}
    for k, v in pairs(opts) do cfg[k] = v end
    cfg.device_id = cfg.device_id or o.device_id
    -- 时间缺省取本机当前时间：ISO8601 且**不带时区**（平台那条解析链
    -- 最后一环没有兜底，格式不对会让对端抛异常）
    cfg.time = cfg.time or os.date("%Y-%m-%dT%H:%M:%S")

    st.sn = (st.sn or 0) + 1
    local body = gb.xml_build_alarm(cfg, st.sn)
    if not body then
        local reason = "报警报文构造失败(字段缺失或 time 格式不对)"
        log_error(reason, cfg.priority, cfg.method, tostring(cfg.time))
        emit("alarm", "failed", { reason = reason, opts = cfg })
        return false, reason
    end

    --[[
    有活跃的报警订阅就走 NOTIFY，否则走 MESSAGE。

    **这条选择规则只有一条**：平台订阅了，说明它明确要求用 NOTIFY 送警情；
    没订阅就走 MESSAGE（M6.5 已实测可用）。两条路的差别不止是信封 ——
    平台对同一条报警的落地结果并不相同（见文件里"平台订阅"那一段的说明），
    所以**不能两条都发**：那会让同一次警情在平台上出现两条记录。

    不看 is_registered()：未注册时 send_request/send_notify 本来就会失败并
    走下面的失败路径，多判一次只会多一处可能与实际状态不同步的判断。
    ]]
    local via, sub = M.alarm_transport(st.subs, now_ms())
    local text
    if sub ~= nil then
        text = send_notify(sub, body)
        via  = "NOTIFY(订阅)"
    else
        text = send_request("MESSAGE", {
            to_uri       = string.format("sip:%s@%s", o.server_id, o.domain),
            content_type = "Application/MANSCDP+xml",
            body         = body,
        })
    end
    if not text then
        -- 未注册/未连上时发送会失败。这里刻意不排队重发，理由见上面的说明
        local reason = "报警发送失败(未注册或链路不通)"
        log_warn(reason, "SN=" .. tostring(st.sn), via)
        emit("alarm", "failed", { reason = reason, opts = cfg, via = via })
        return false, reason
    end

    log_info("已上报报警", "method=" .. tostring(cfg.method),
             "SN=" .. st.sn, via)
    emit("alarm", "sent", { sn = st.sn, opts = cfg, via = via })
    return true
end

--[[
向平台发一条 MANSCDP 的 Broadcast 通知(Notify)。

GB28181-2016 §9.12 的方向是"平台通知设备"，但实测 WVP-Pro 这个分支里
**收通知的是平台**（`BroadcastNotifyMessageHandler` 挂在请求处理链上，
且 `AudioBroadcastManager.update()` 由它触发）—— 即设备先声明"我要广播"，
平台建立待接通记录，随后设备发起的 INVITE 才会被接受。

@api exgb28181client.send_broadcast_notify([target_id])
@string target_id 播放端编号，缺省用本端设备编码
@return boolean
]]
function M.send_broadcast_notify(target_id)
    local o = g_opts
    st.sn = (st.sn or 0) + 1
    local body = string.format(
        '<?xml version="1.0" encoding="GB2312"?>\r\n' ..
        '<Notify>\r\n' ..
        '<CmdType>Broadcast</CmdType>\r\n' ..
        '<SN>%d</SN>\r\n' ..
        '<SourceID>%s</SourceID>\r\n' ..
        '<TargetID>%s</TargetID>\r\n' ..
        '</Notify>\r\n',
        st.sn, o.device_id, target_id or o.device_id)

    local text = send_request("MESSAGE", {
        to_uri       = string.format("sip:%s@%s", o.server_id, o.domain),
        content_type = "Application/MANSCDP+xml",
        body         = body,
    })
    if not text then return false end
    log_info("已发出 Broadcast 通知", "SN=" .. st.sn)
    return true
end

--[[
向音频会话推送一段**已编码的 G.711A(PCMA)载荷**（对讲的上行方向）。

与视频侧的约定一致：**组件收已编码的数据**，PCM→PCMA 的编码归平台层
(LuatOS 的 multimedia 本来就有 .g711a 能力)。这样 src/ 不必引入 codec，
而"打包 + 发送"直接复用现成的媒体队列 —— 队列、背压、TCP 断点续发都是现成的。

时间戳按 8kHz 推进(G.711A 1 字节 = 1 采样)，与视频的 90kHz 不同 ——
同一会话里两者的时钟基准不一样。

@api exgb28181client.talk_push(session, pcma)
@table session
@string pcma 已编码的 G.711A 载荷(建议每包 160 字节 = 20ms@8kHz)
@return boolean
]]
function M.talk_push(sess, pcma)
    if type(sess) ~= "table" or type(pcma) ~= "string" or #pcma == 0 then
        return false
    end
    if not sess.media or not sess.netc then
        return false          -- 没有上行队列(TCP 腿未建立时)/会话已结束
    end
    if sess.media_tcp and not sess.link_up then
        return false          -- TCP 还没连上，发出去也会被丢
    end

    -- 音频的时钟就是采样率本身：每包按载荷字节数推进(PCMA 一字节一个采样)。
    -- **不要写 `% 0xFFFFFFFF`** —— 32 位整数下它是 -1，`x % -1` 恒为 0，
    -- 会让每包时间戳都变成 0（同样的坑在 push_frame 里踩过，见那里的说明）。
    -- 回绕由 32 位整数自身与 C 层的 uint32_t 转换完成。
    sess.frame_ts = (sess.frame_ts or 0) + #pcma
    if gb.media_push(sess.media, pcma, sess.frame_ts) == 0 then
        return false          -- 整包被丢弃(队列满)，统计里能查到
    end
    M.flush_session(sess)
    return true
end

--[[
注册**下行音频**回调：平台发来的音频包剥掉 RTP 头后交给它。

与 talk_push 恰好是一对 —— 一个负责上行(本端采集 → 平台)，一个负责下行
(平台 → 本端播放)。两者都只搬**已编码的 G.711A 字节**，PCM↔G.711A 的转换
与麦克风/喇叭都归平台的音频框架(LuatOS 的 audio_v2 自带
DATA_CODEC_TYPE_G711_ALAW，两端都用它即可，本组件不碰 codec)。

回调签名 f(sess, body, is_ps)：
  sess  音频会话表
  body  剥掉 RTP 头之后的载荷。is_ps 为 false 时**直接就是 G.711A**，
        可以原样喂给 audio_v2.input()
  is_ps 载荷是否以 PS 起始码 00 00 01 BA 开头。**平台两种封装都可能**，
        为 true 时需要先做 PS 解封装取出 PES(0xC0) 的载荷
返回值忽略。回调里抛异常不会打断收包循环（内部 pcall）。
会话上的 rx_ps / rx_raw 是两种封装的累计计数，跑一次对讲即可判定平台用哪种。

@api exgb28181client.on_audio(callback)
@function callback 回调函数，传 nil 取消注册
@return boolean
@usage
local client = require "exgb28181client"
client.on_audio(function(sess, body, is_ps)
    if is_ps then return end            -- PS 封装需先解封装，这里只处理裸 PCMA
    audio_v2.input(src_index, body, false)
end)
]]
function M.on_audio(callback)
    if callback ~= nil and type(callback) ~= "function" then
        return false
    end
    g_audio_cb = callback
    return true
end

--[[
结束由本端发起的音频会话：向平台发 BYE 并释放本地端口。

@api exgb28181client.stop_talk([call_id])
@string call_id 缺省结束全部
@return int 结束的会话数
]]
function M.stop_talk(call_id)
    local n = 0
    for id, sess in pairs(st.talks) do
        if call_id == nil or id == call_id then
            -- 对话内的 BYE 要带上对话的 tag 与 Call-ID，故不能用 send_request 的默认值
            if sess.state == "established" then
                send_request("BYE", {
                    to_uri      = string.format("sip:%s@%s", g_opts.server_id, g_opts.domain),
                    to_tag      = sess.remote_tag,   -- 对端 tag，对话内请求必需
                    from_tag    = sess.from_tag,
                    call_id     = id,
                    cseq_method = "BYE",
                })
            end
            media_close(sess)
            st.talks[id] = nil
            n = n + 1
            emit("talk", "ended", { call_id = id, reason = "local" })
        end
    end
    return n
end

-- 列出当前进行中的音频会话(供上层观察)
function M.talks()
    return st.talks
end

-- ---- 收包 ----

--[[
收包。

响应先看是不是某个会话的探针应答 —— 探针只关心"回没回"，任何状态码都算活着
（481 说明平台人还在，只是不认这个对话；要区分的是"回都不回"）。
]]
-- ------------------------------------------------------------------
-- 回放控制：SIP INFO 承载的 MANSRTSP
-- ------------------------------------------------------------------

--[[
把控制命令转给回放源。没有注册回放源时说明原因而不是静默 ——
现象是"拖进度条没反应"，与"平台没发命令"在日志里长得一样。
]]
local function playback_control(sess, action, arg)
    if type(g_playback_cb) ~= "function" then
        log_warn("收到回放控制但没有注册回放源", action)
        return false
    end
    local ok, err = pcall(g_playback_cb, sess, action, arg)
    if not ok then
        log_error("回放控制异常", action, err)
        return false
    end
    return true
end

--[[
处理 SIP INFO —— 回放的暂停/继续/拖动就从这里进来。

**平台界面上点暂停/拖进度条，发的就是这条 INFO**，真正的指令在消息体里
（`Content-Type: Application/MANSRTSP`），SIP 层看不出任何区别。报文形态与
"body 里的 CSeq 与 SIP 头的 CSeq 是两个值"等细节见 C 层
luat_gb28181_mansrtsp.h 的说明（取自真实平台源码，不是照标准推的）。

两个刻意的处理：

1. **SIP 层一律回 200**，业务上的"不支持"写在 MANSRTSP 的应答体里。
   标准要求"不支持的控制命令返回明确错误而不中断会话"—— 用 SIP 4xx 表达
   错误有被平台当成会话异常的风险，写进 body 则两边都满足。
   （实测 WVP 收到应答后并不解析 body，回什么它都行；换一家会解析的平台时
     这个体就是有效的。）

2. **实时点播会话收到 MANSRTSP 一律忽略**：没有时间轴可控制，拖它没有意义。
]]
local function handle_info(msg)
    local sess = st.sessions[msg.headers["call-id"]]

    if not sess or not sess.is_playback then
        log_info("INFO 非回放会话，仅回应答", tostring(msg.headers["call-id"]))
        reply_ok(msg)
        return
    end

    local ctype = (msg.headers["content-type"] or ""):lower()
    if not ctype:find("mansrtsp", 1, true) then
        log_info("INFO 不是 MANSRTSP，仅回应答", ctype)
        reply_ok(msg)
        return
    end

    if type(gb.mansrtsp_parse) ~= "function" then
        -- 固件里的 C 层太旧（没有 mansrtsp 绑定）：只回应答，别去调 nil
        log_warn("C 层没有 mansrtsp_parse，回放控制不可用（固件版本太旧?）")
        reply_ok(msg)
        return
    end

    local cmd, err = gb.mansrtsp_parse(msg.body or "")
    if not cmd then
        -- 读不懂就只回应答：连 CSeq 都拿不到，没法在 body 里指回它
        log_warn("MANSRTSP 解析失败", tostring(err))
        reply_ok(msg)
        return
    end

    local code, reason = 200, "OK"

    if cmd.method == gb.MANSRTSP_PAUSE then
        playback_control(sess, "pause")

    elseif cmd.method == gb.MANSRTSP_TEARDOWN then
        -- 平台的"停止回放"：停推流即可，会话终结由它随后发的 BYE 决定
        playback_control(sess, "stop")

    elseif cmd.method == gb.MANSRTSP_PLAY then
        if cmd.has_scale then
            -- 变速播放要改时间轴节奏，本端没做。**明确回不支持**：
            -- 静默忽略的话，用户看到的是"点了倍速没反应"，与"平台没发"无从区分
            code, reason = 501, "Not Implemented"
            log_warn("平台要求变速播放，本端不支持", tostring(cmd.scale))
        elseif cmd.npt_kind == gb.NPT_NOW then
            -- npt=now- 是"从当前位置继续"，**不能当成 0 秒去定位**
            playback_control(sess, "resume")
        elseif cmd.npt_kind == gb.NPT_POS then
            playback_control(sess, "seek", cmd.npt_sec)
        elseif cmd.has_range then
            code, reason = 501, "Not Implemented"   -- clock= 之类
            log_warn("平台给了本端不支持的 Range")
        else
            -- PLAY 不带 Range：RTSP 语义就是继续播
            playback_control(sess, "resume")
        end

    else
        code, reason = 501, "Not Implemented"
        log_warn("不支持的回放控制命令", tostring(cmd.method))
    end

    local body = gb.mansrtsp_response(code, reason, cmd.cseq)
    reply(msg, 200, "OK", body, body and "Application/MANSRTSP" or nil)
    log_info("回放控制", tostring(cmd.method), code, tostring(cmd.cseq))
end

-- ------------------------------------------------------------------
-- 平台订阅(SUBSCRIBE / NOTIFY)
-- ------------------------------------------------------------------
--[[
这条链路的方向与常见的"平台问、设备答"相反：

    SUBSCRIBE(平台 → 设备)  →  200 OK(设备 → 平台)  →  NOTIFY(设备 → 平台)

**设备是被订阅方(notifier)、平台才是订阅方**。平台发来 SUBSCRIBE 说"有警情
告诉我"，设备之后用 NOTIFY 把警情推回去 —— 注意这个 NOTIFY 是 **SIP 方法**，
与报警体里那个 MANSCDP 的 `<Notify>` 根元素**同名但不是一回事**，报文里
两层都会出现（外层 SIP NOTIFY，内层 `<Notify><CmdType>Alarm</CmdType>`）。

## 与 MESSAGE 那条路的取舍

报警既能用 MESSAGE 直接发（M6.5 已实现并实测过），也能走这条订阅链路。
**两者在平台侧落地的结果并不一样**（实测读 WVP 源码）：

  · MESSAGE 路径对 `AlarmMethod=7`（其他）有旁路：只发 Redis，**不入告警列表**；
    订阅链路那条路**没有**这个旁路，同样一条报警会照常入库。
  · GPS 报警(method=4)在两条路上的落点也不同：MESSAGE 走事件管线，
    订阅链路直接写通道经纬度。

所以"用哪条路"是有观测差异的，不是纯风格问题。

## 与标准的偏离（有意为之）

RFC 3265 要求收到 SUBSCRIBE 后**立即回一条 NOTIFY**（哪怕没有内容）。
**本组件不发那条空的**：GB28181 的报警订阅语义是"有警情才发"，而平台侧
对空 body 的 NOTIFY 只会记一行 `未获取到消息体` 的错误日志（实测 WVP 的
`NotifyRequestProcessor`），除了满足仪式感没有收益。真遇到要求它的平台，
在 `handle_subscribe` 末尾补一条 `send_notify(sub, nil)` 即可。
]]

--[[
订阅是否已到期。纯函数，便于单测（与 session_death_reason 同一做法）。

`expires` 是平台给的秒数，`expire_at` 是收到它的时刻 + expires。
用 `>=` 而不是 `>`：expires=0 的订阅不该存在（那是取消订阅，在
handle_subscribe 里就删掉了），真出现了也应当立刻清掉。
]]
function M.sub_expired(sub, now)
    if type(sub) ~= "table" or type(now) ~= "number" then
        return false
    end
    if type(sub.expire_at) ~= "number" then
        return false          -- 没记到期时间就不主动清，宁可留着
    end
    return now >= sub.expire_at
end

--[[
在一条订阅对话里发一条 NOTIFY。

**对话内的请求，三样东西必须与订阅对上**，否则平台认不出这是哪个订阅：

    Call-ID            原样用 SUBSCRIBE 的
    From 的 tag        用**我们**在 200 OK 里给的那个（平台记下了它）
    To   的 tag        用**平台**在 SUBSCRIBE 里给的那个

From 的 user 部分必须是设备编码 —— 实测平台是从 From 头取设备编码去查设备的
（`SipUtils.getUserIdFromFromHeader`），这里写错会让平台"找不到设备"。

@param sub  订阅记录
@param body 报警体(可空)
@return string|nil 报文
]]
function send_notify(sub, body)
    local o = g_opts

    sub.cseq = (sub.cseq or 0) + 1

    local text = gb.sip_build({
        method      = "NOTIFY",
        -- 对话内请求的请求行应指向订阅方的 Contact；平台没给就回落到服务端地址
        uri         = sub.contact or string.format("sip:%s@%s", o.server_id, o.domain),
        transport   = string.upper(o.transport),
        host        = st.local_ip,
        port        = st.sip_port,
        branch      = gen_token("z9hG4bK"),
        from_uri    = string.format("sip:%s@%s", o.device_id, o.domain),
        from_tag    = sub.to_tag,
        to_uri      = string.format("sip:%s@%s", o.server_id, o.domain),
        to_tag      = sub.from_tag,
        call_id     = sub.call_id,
        cseq        = sub.cseq,
        cseq_method = "NOTIFY",
        user_agent  = o.user_agent or "LuatOS-GB28181",
        contact     = false,
        content_type = body and "Application/MANSCDP+xml" or nil,
        body        = body,
        extra_headers = {
            -- 原样回抄订阅时的 Event(含 eventId)：平台刷新订阅时会带上它
            { name = "Event",              value = sub.event },
            -- 一次性拉取(Expires:0)那条路要写 terminated，见 handle_subscribe；
            -- 其余都是长订阅，active
            { name = "Subscription-State", value = sub.subscription_state or "active" },
        },
    })
    if not text then
        log_error("构造 NOTIFY 失败", sub.call_id)
        return nil
    end
    if not net_send(text) then
        log_warn("发送 NOTIFY 失败", sub.call_id)
        return nil
    end
    return text
end

--[[
在给定的一组订阅里挑一条能用来上报报警的，并回答**该用哪种传输**。

**纯函数**：只看传进来的表、不碰模块状态，便于单测（与 session_death_reason
同一做法）。`report_alarm` 是它唯一的调用方。

只挑 `CmdType=Alarm` 的：平台可能同时订阅了目录与移动位置(Catalog/MobilePosition)，
那些订阅不该拿来发报警 —— 平台的 `NotifyRequestProcessor` 按 CmdType 分发，
报警体配上报目录的订阅会被丢进"其它"分支，连日志都不显眼。

@param subs 订阅表(Call-ID -> 订阅记录)
@param now  当前毫秒时刻
@return string "NOTIFY" 或 "MESSAGE"
@return table|nil 选中的订阅(走 MESSAGE 时为 nil)
]]
function M.alarm_transport(subs, now)
    for _, sub in pairs(subs or {}) do
        if type(sub) == "table" and sub.cmd == "Alarm" and
           not M.sub_expired(sub, now) then
            return "NOTIFY", sub
        end
    end
    return "MESSAGE", nil
end

--[[
处理平台的订阅请求(SUBSCRIBE)。

平台的 SUBSCRIBE 里带一个 MANSCDP 的 `<Query><CmdType>…</CmdType></Query>`
说明订阅什么，`Expires` 头说明订多久。

  · `Event` 头的取值**不是** `alarm`：实测 WVP 订阅报警发的是 `presence`
    （目录订阅才是 `Catalog`），带一个 eventId。本层原样回抄，不解释。
  · 应答里必须补 To-tag（见 reply_ok 的说明），否则对话没建起来。
  · `Expires: 0` **不是"订 0 秒"，而且有两种含义**（RFC 3265 §3.1.1）：
      取消订阅          —— 删掉记录并回 `Expires: 0`，不再发 NOTIFY
      一次性拉取当前状态 —— 同样删记录回 `Expires: 0`，但**还要发一条**
                           带当前状态的 NOTIFY。平台靠 Catalog 这一条拿通道，
                           漏发不会报错，只会"设备永远不在线"。
    两种由 CmdType 区分，只给 Catalog 补 NOTIFY，详见下面那个分支的注释。
]]
local function handle_subscribe(msg)
    local o = g_opts
    local call_id = msg.headers["call-id"] or ""
    local event   = msg.headers["event"] or ""
    local expires = tonumber((msg.headers["expires"] or ""):match("^%s*(%d+)")) or 0

    local q = (msg.body ~= nil) and gb.xml_parse_query(msg.body) or nil
    local cmd = (q and q.cmd_type) or ""

    local contact_uri = uri_of(msg.headers["contact"])
    local platform_tag = tag_of(msg.headers["from"])

    if expires == 0 then
        -- 先把 tag 取出来再删记录 —— 反过来的话取到的永远是 nil，
        -- 应答里补不出 To-tag，平台侧那次取消就配不上对话
        local known = st.subs[call_id]
        local to_tag = (known and known.to_tag) or gen_token("")
        st.subs[call_id] = nil

        reply_ok(msg, {
            to_tag  = to_tag,
            headers = {
                { name = "Expires", value = "0" },
                { name = "Event",   value = event },
            },
        })

        --[[
        `Expires: 0` 还有**第二种用法**：一次性拉取当前状态。
        RFC 3265 §3.1.1 对它有两句话 —— "订阅终止"**和**"通知者必须发一条
        带当前状态的 NOTIFY"。这里原先只做了前一句，于是：

            平台 SUBSCRIBE(Event: Catalog;id=N, Expires: 0)
            设备 200 OK + Expires: 0        ← 平台要的目录一个字没给
            平台 29 秒后同 Call-ID、CSeq+1 再来一次 …… 无限循环
            现象：REGISTER 明明 200 OK，平台界面上设备始终"不在线"
                  （平台手里没有通道，就没有可播的通道）

        实测(2026-09-22，合宙 video.luatos.com / LiveMedia 平台)：CSeq 从 18
        一路涨上去、Call-ID 不变，是平台**等不到东西**在轮询，不是重传。

        只有 Catalog 补这条：报警订阅的"当前状态"没有对应语义(没有警情就是没有)，
        为它发一条空 NOTIFY 只会在平台侧留一行"未获取到消息体"的错误日志。
        ]]
        if cmd == "Catalog" then
            local sub = {
                call_id = call_id,
                -- NOTIFY 的 From tag 必须与刚发出去的 200 OK 里那颗一致，
                -- 否则平台侧配不上对话，收到也当野包丢掉
                to_tag   = to_tag,
                from_tag = platform_tag,
                contact  = contact_uri,
                cseq     = 0,
                event    = event,
                cmd      = cmd,
                -- 订阅确实终止了，按 RFC 的字面写 terminated
                subscription_state = "terminated",
            }
            -- 目录体与 MESSAGE 那条路共用 send_catalog，只换投递方式
            send_catalog(msg, (q and q.sn) or 0, function(body)
                send_notify(sub, body)
            end)
        end

        log_info("平台取消订阅", cmd, call_id)
        emit("subscribe", "removed", { call_id = call_id, cmd = cmd })
        return
    end

    -- 同一个 Call-ID 可能是刷新（平台到期前会带同样的对话信息重发）
    local sub = st.subs[call_id]
    if sub == nil then
        sub = {
            call_id  = call_id,
            -- 我们自己给这个对话的 tag：NOTIFY 的 From 用它
            to_tag   = gen_token(""),
            -- 平台的 tag：NOTIFY 的 To 用它
            from_tag = platform_tag,
            contact  = contact_uri,
            cseq     = 0,
        }
        st.subs[call_id] = sub
    end
    sub.cmd       = cmd
    sub.event     = event
    sub.expires   = expires
    sub.expire_at = now_ms() + expires * 1000
    -- 刷新时平台的 tag 不该变；变了说明平台换了个对话，跟着更新
    if platform_tag ~= nil then
        sub.from_tag = platform_tag
    end
    if contact_uri ~= nil then
        sub.contact = contact_uri
    end

    reply_ok(msg, {
        to_tag  = sub.to_tag,
        headers = {
            { name = "Expires", value = tostring(expires) },
            { name = "Event",   value = event },
            {
                name  = "Contact",
                value = string.format("<sip:%s@%s:%d>", o.device_id,
                                      st.local_ip or "0.0.0.0", st.sip_port or 0),
            },
        },
    })

    log_info("平台订阅", cmd, "expires=" .. tostring(expires), "Event=" .. event)
    emit("subscribe", "added", {
        call_id = call_id, cmd = cmd, expires = expires, event = event,
    })
end

--[[
回收已到期的订阅。平台到期前会主动刷新，没刷新就是它不打算继续订了。

**不向平台发 Expires:0 去"确认"**：订阅到期是订阅方的事，设备主动发取消
报文反而可能在平台侧把刚刷新好的订阅拆掉（两个报文交叉）。静默清掉即可 ——
平台下次要用会重新 SUBSCRIBE。
]]
local function reap_expired_subs(now)
    for call_id, sub in pairs(st.subs) do
        if M.sub_expired(sub, now) then
            st.subs[call_id] = nil
            log_info("订阅到期，已回收", sub.cmd, call_id)
            emit("subscribe", "expired", { call_id = call_id, cmd = sub.cmd })
        end
    end
end

local function process_packet(msg)
    if msg.code then
        --[[
        收到任何报文都说明链路还活着 —— 这是 UDP 上唯一可信的活口信号。
        清掉等待标记，并**盖章"刚刚听到对面了"** —— tick 里的超时判据算的是
        `now - last_rx_at`，所以这一行才是真正让它不误判的那一行。
        放在最前面：不管这条报文最终由谁处理，它已经证明了链路可用。
        ]]
        st.await_since = nil
        st.last_rx_at  = now_ms()

        -- 先看是不是本端发起的音频会话的应答(按 Call-ID 匹配)
        if handle_talk_response(msg) then return end

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

    -- 回放的暂停/继续/拖动走 INFO(承载 MANSRTSP)，见 handle_info
    if msg.method == "INFO" then
        handle_info(msg)
        return
    end

    -- 平台订阅：设备是被订阅方，之后用 NOTIFY 把警情推回去(见 handle_subscribe)
    if msg.method == "SUBSCRIBE" then
        handle_subscribe(msg)
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
-- 信令链路失活与重连
-- ------------------------------------------------------------------

--[[
把"信令链路已经死了"这件事记下来，交给 sip_task 去重建。

**为什么需要它**：平台重启、网络抖动、对端端口关闭，都会让这条 connected
UDP socket 失效。实测（2026-09-18，Air8101 真机）平台重启后的表现是
**设备 ping 得通、日志照刷、平台侧什么都收不到** —— 因为原来的代码只是把
`registered` 置了 false 就再也没做别的事：任务继续转，但永远不会再注册。

触发这个函数的**主要是"请求超时无应答"**（见 SIGNALING_REPLY_TIMEOUT_MS），
TCP 流错位与 CLOSED 事件也走这里 —— 后两者在 UDP 上实测**不会发生**。

（原代码在这里 `sys.publish(TOPIC_STOP)`，而 sip_task 等的是 TOPIC_CMD ——
那个 publish 没有任何人接收，是一条误导性的死代码。现在改成显式置标记，
由 sip_task 的 tick 统一处理重建。）

**不在回调里直接重建**：net_cb 跑在 socket 的事件上下文里，在里面重建 socket
等于在回调里销毁回调所属的对象，容易踩到栈上状态。置标记 + 让任务去处理，
时序最清楚。

**退避在这里就排下一次**（2026-09-22 改）：原先只在"重建失败"时退避，
而重建通常"成功"（socket 建出来了，毛病要等发报文才知道），于是退避从未累积，
实际节奏被那 15 秒超时钉死成恒定的 ~16s/轮。现在每判死一次就翻一倍，
真正可用与否以**注册成功**为准（那里才清零）。
]]
local _schedule_reconnect     -- 前向声明：定义在下面"socket 重建"那一节

local function _signal_dead(reason)
    if st.dead then
        return              -- 已经在重建流程里，别重复触发
    end
    st.online     = false
    st.registered = false
    st.dead       = true
    _schedule_reconnect()
    log_warn("信令链路失活:", reason, "将在退避后重建")
    emit("net", "closed", { reason = reason })
end

-- ------------------------------------------------------------------
-- 主任务
-- ------------------------------------------------------------------

local function net_cb(netc, event, param)
    -- 降为 debug：这是每包都打的调试信息，留在 INFO 级会在真机上持续刷屏
    log.debug("net_cb event =", event)
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
        -- 新链路从这一刻起算"多久没听到对面"：不重置的话，重建后
        -- last_rx_at 还停在上一轮的旧时刻，会立刻被误判成失活
        st.last_rx_at = now_ms()
        send_register(nil)

    elseif event == socket.EVENT then
        local rxbuf = zbuff.create(1500)
        if not rxbuf then return end
        while true do
            local succ, data_len = socket.rx(netc, rxbuf)
            if not succ then break end
            if not data_len or data_len <= 0 then break end
            local data = rxbuf:toStr(0, rxbuf:used())
            log.debug("收到", #data, "字节")   -- 同上，逐包调试信息
            rxbuf:del()
            if not feed(data) and string.upper(g_opts.transport) == "TCP" then
                log_warn("TCP 流错位, 断连重注册")
                _signal_dead("TCP 流错位")
                return
            end
        end

    elseif event == socket.CLOSED then
        _signal_dead("socket 已关闭")
    end
end

--[[
拆掉信令 socket 与它名下的一切，准备重建。

**已建立的点播/音频会话在这里一并清掉**（有意选定）：平台重启后那些会话在
它那边已经不存在了，留着只会占着媒体端口 —— `max_sessions` 默认 4，攒够
四个僵尸会话，之后平台怎么点都点不动，而日志上看不出任何异常。

代价是：万一只是信令抖动、媒体链路其实还活着，这一清会打断正在推的流。
权衡下来"确定性"更重要 —— 僵尸会话会把设备变成永久点不动，而重连后平台
重新点一次就能恢复。
]]
local function _teardown_for_reconnect()
    for call_id, sess in pairs(st.sessions) do
        media_close(sess)
        st.sessions[call_id] = nil
        emit("call", "ended", { call_id = call_id, reason = "signaling_lost" })
    end
    for call_id, sess in pairs(st.talks) do
        if sess.netc then socket.close(sess.netc) end
        st.talks[call_id] = nil
        emit("call", "ended", { call_id = call_id, reason = "signaling_lost" })
    end

    if st.netc then
        socket.close(st.netc)
        st.netc = nil
    end
    st.online     = false
    st.registered = false
    st.auth_tried = 0
    st.next_reg   = 0
    st.next_ka    = 0
    st.rx         = ""
    st.await_since = nil
    -- 与 await_since 成对：新链路的"上次听到"由 net_cb 的 ON_LINE 盖章，
    -- 在那之前不该拿上一轮的旧时刻去判活
    st.last_rx_at  = nil
end

-- 退避：1s → 2s → 4s → … 上限 30s。**不阻塞 tick 循环**，
-- 只算一个"下次可重连的时刻"，让每秒的 tick 去看 —— 否则平台长时间
-- 不可用时会把这个循环连同会话回收一起卡住。
--
-- **由 _signal_dead 调用（每次判死翻一倍）**，注册成功才清零；
-- 重建"成功"（socket 建出来）**不**清零 —— 那时链路还完全没被验证过。
local RECONNECT_MIN_MS = 1000
local RECONNECT_MAX_MS = 30000

--[[
信令请求多久没等到应答就认为链路已死（毫秒）。

**为什么不能靠 socket 的 CLOSED 事件**（实测，2026-09-18，Air8101 真机）：
平台重启后端口关闭，设备的 connected UDP socket **既不给 CLOSED 也不给错误
事件**，反而一直在报 `TX_OK`（socket.TX_OK = 0x2000012）—— 它以为发成功了。
日志里从头到尾没有出现过 `socket.CLOSED`（0x2000013）。
这是 §5.2 那条"UDP 上对端消亡不可观测"在信令 socket 上的同一回事。

好在信令是**有应答的协议**：REGISTER 与心跳都必然被平台回复。
"发了要应答的请求、超时没等到"就是 UDP 下唯一可信的活口判据。
平台正常时是毫秒级应答，15s 足够宽松；真的不回，多半就是它已经不在了。

**这个 15 秒量的是"距上次收到报文"，不是"距上次发出请求"**（2026-09-22 改）：
后者会被自家探测包刷新 —— keepalive 比它短时（比如 10s），就有探测包一直在
喂看门狗，链路死了也判不出来，而 `keepalive = 10` 是个看着完全合理的取值。
判据见 tick 里的 `last_rx_at`。
]]
local SIGNALING_REPLY_TIMEOUT_MS = 15000

-- 注意：**不能写 `local function`** —— 上面已用 `local _schedule_reconnect`
-- 前向声明（_signal_dead 要用它），这里再写 local 会造出另一个局部变量，
-- 前向声明那个永远是 nil，调用时炸 "attempt to call a nil value"。
_schedule_reconnect = function()
    local d = st.reconnect_delay or RECONNECT_MIN_MS
    st.reconnect_at    = now_ms() + d
    st.reconnect_delay = math.min(d * 2, RECONNECT_MAX_MS)
end

--[[
重建信令 socket 并重新注册。由 sip_task 的 tick 调用。
@return boolean, string|nil
]]
local function _reconnect_signaling()
    local o = g_opts

    _teardown_for_reconnect()

    local netc = socket.create(o.adapter, net_cb)
    if not netc then
        return false, "socket.create 失败"
    end
    st.netc = netc

    -- local_port 给 0 表示"由系统挑一个"（见下面读回的那段）
    if not socket.config(netc, o.local_port or 0,
                         string.upper(o.transport) ~= "TCP") then
        socket.close(netc)
        st.netc = nil
        return false, "socket.config 失败(端口可能被占用；可设 local_port = 0 让系统挑)"
    end

    if not socket.connect(netc, o.server_addr, o.server_port) then
        socket.close(netc)
        st.netc = nil
        return false, "socket.connect 失败"
    end

    -- 读回实际端口：local_port 给 0 时端口是底层挑的，而 Contact 必须写真实值
    -- （平台据此回 BYE/INFO）。旧固件没有 socket.localPort，退回配置值。
    if type(socket.localPort) == "function" then
        st.sip_port = socket.localPort(netc) or o.local_port or 5060
    else
        st.sip_port = o.local_port or 5060
    end

    st.dead = false
    -- 措辞保持中性：首次建链与重建走的是同一个函数，说"已重建"会让第一次看日志的人以为出了故障
    log_info("信令链路就绪, 等待 ON_LINE 后注册")
    -- 注：不在这里 send_register —— socket 还没 ON_LINE，本地 IP 也还没拿到。
    -- net_cb 的 ON_LINE 分支会取 IP 并发出 REGISTER。
    return true
end

local function sip_task()
    local o = g_opts

    --[[
    首次建链走与重连**同一套代码**。

    原来这里是三步各写一遍、任一步失败就 `g_started = false` 直接放弃 ——
    那意味着"开机那一刻平台正好不在"会让设备永久失联，而现场看到的只是
    "设备不注册"。现在失败只记一笔、交给退避重连，设备自己会回来。
    ]]
    local ok0, err0 = _reconnect_signaling()
    if not ok0 then
        log_error("信令链路建立失败:", err0)
        emit("error", "net", { reason = err0 })
        _schedule_reconnect()
    end

    log_info("信令任务启动", o.server_addr, o.server_port)

    -- 单 tick 循环：既响应命令，也检查重注册/心跳是否到期
    while g_started do
        -- **同时等两个主题**：TOPIC_STOP 是"信令链路死了"（由 net_cb 发），
        -- 不等它就只能在 1 秒的 tick 里被动发现，重连慢一拍。
        -- （原代码只等 TOPIC_CMD，而 net_cb 发的正是 TOPIC_STOP —— 没人接收。）
        sys.waitUntil({TOPIC_CMD, TOPIC_STOP}, 1000)
        local now = now_ms()

        --[[
        活口判据：**距上次收到报文**超过 15 秒，且手上有请求在外面等 → 链路已死。

        `await_since` 只当开关用（"有必须被应答的请求在外"），**不能拿它算时长**：
        它每次发心跳/REGISTER 都会被刷新，keepalive 短于 15s 时看门狗被自家
        探测包一直喂着，链路死了也判不出来。算时长的是 `last_rx_at`。

        见 SIGNALING_REPLY_TIMEOUT_MS 的说明：UDP 上这是唯一可信的信号。
        必须在重建判断**之前**做 —— 否则先重建、后判死，会把刚建好的链路又拆掉。
        ]]
        if not st.dead and st.await_since and st.last_rx_at and
           (now - st.last_rx_at) >= SIGNALING_REPLY_TIMEOUT_MS then
            _signal_dead("信令请求超时无应答")
        end

        -- 链路死了就退避重建。**放在 tick 里而不是 socket 回调里**：
        -- 回调里重建等于在回调中销毁回调所属的对象，时序容易出问题。
        --
        -- 重建成功**不清退避**：socket 建出来只说明"能创建"，链路可用与否
        -- 要等注册回来才算数（清零在 handle_register_response）。在这里清的话，
        -- 一个建得起来但永远不通的链路每轮都会从 1s 重来，退避等于没有。
        if st.dead and now >= (st.reconnect_at or 0) then
            local ok, err = _reconnect_signaling()
            if not ok then
                log_warn("重建信令链路失败:", err)
                _schedule_reconnect()
            end
        end

        if st.registered and st.next_reg > 0 and now >= st.next_reg then
            st.next_reg = 0
            log_info("重注册到期")
            send_register(nil)
        end

        if st.registered and st.next_ka > 0 and now >= st.next_ka then
            send_keepalive()
        end

        -- 回收到期的订阅。放在 tick 里而不是靠定时器：订阅可能同时有好几条
        -- (报警/目录/移动位置各一条)，逐个起定时器要管的东西比收益多
        reap_expired_subs(now)

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
    -- 0 表示"由系统挑端口"（见 _reconnect_signaling 里读回实际端口那段）
    if g_opts.local_port == nil then
        g_opts.local_port = 5060
    end
    -- 建链前的初值：建链成功后会换成**实际用的**那个端口（可能是系统挑的）
    st.sip_port = g_opts.local_port ~= 0 and g_opts.local_port or 5060
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

    -- 录像列表归一化一次，RecordInfo 应答与回放定位共用这一份(见 normalize_records)
    st.records = normalize_records(g_opts.records)

    g_cb = opts.event_callback

    -- 音频回调也可经 opts 传入（与 on_audio() 等价）。只在本轮显式给了才覆盖，
    -- 否则保留之前 on_audio() 注册的那个 —— 音频桥可能先于 start() 起来
    if opts.audio_callback ~= nil then
        g_audio_cb = opts.audio_callback
    end

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
列出当前有效的平台订阅，以 Call-ID 为键。

用来回答"平台到底订没订我、订的是什么、还有多久到期" —— 报警走 NOTIFY
还是 MESSAGE 完全取决于这里有没有一条 `cmd == "Alarm"` 的订阅，
排查时先看它比看报文快。

@api exgb28181client.subscriptions()
@return table Call-ID -> {cmd=,event=,expires=,expire_at=,...}
]]
function M.subscriptions()
    local out = {}
    for k, v in pairs(st.subs) do out[k] = v end
    return out
end

--[[
取归一化后的录像列表（回放源用）。

返回的是**内部那份**而不是副本：回放会话每开一段录像都要读它，而录像列表
在一次运行内不变。**调用方不要改它**。

@api exgb28181client.records()
@return table 录像列表（可能为空表）
]]
function M.records()
    return st.records or {}
end

--[[
注册回放源。**由 exgb28181playback 调，应用不需要直接用它。**

回放与实时点播的入口不同：实时点播的帧由应用推（数据源是摄像头），
回放的帧来自设备本地录像，应用手里没有这份数据，所以由回放模块在
会话建立/销毁/收到控制命令时接管(见 exgb28181playback.on_session)。

@api exgb28181client.on_playback(handler)
@function handler 原型 handler(sess, action, arg)，action 见 playback 模块
@return boolean
]]
function M.on_playback(handler)
    if handler ~= nil and type(handler) ~= "function" then
        return false
    end
    g_playback_cb = handler
    return true
end

--[[
注册云台(PTZ)指令的处理者。

**不注册也能跑**：平台发来的云台指令会被回 `Result=ERROR`（设备确实没有
可执行的云台 —— 报"成功"是谎报，见 handle_device_control 的说明）。

处理者拿到的是**解码后的指令**（C 层 ptz_parse 的结果，位域含义见
luat_gb28181_ptz.h），应用按自己接的云台决定怎么做：

    client.on_ptz(function(cmd, hex)
        if cmd.kind == gb.PTZ_MOVE then
            if cmd.up then 云台.上(cmd.tilt_speed) end
            ...
        elseif cmd.kind == gb.PTZ_PRESET and cmd.code == 0x82 then
            云台.调用预置位(cmd.param2)
        end
    end)

传 nil 可取消注册。**处理者返回什么不影响应答** —— 只要不抛异常就回 OK：
把"执行失败"的表达留给应用自己决定(它可以选择抛错，那就回 ERROR)。

@api exgb28181client.on_ptz(handler)
@function handler 原型 handler(cmd, hex)
@return boolean
]]
function M.on_ptz(handler)
    if handler ~= nil and type(handler) ~= "function" then
        return false
    end
    g_ptz_cb = handler
    return true
end

--[[
注册拉框放大/缩小(2022 新增)指令的处理者。

平台在界面上框选一块区域让设备放大，就是这个。处理者拿到的是
`gb28181.devctl_parse` 的结果：

    client.on_drag_zoom(function(d)
        if d.kind == gb.DEVCTL_DRAG_ZOOM_IN then
            -- 矩形中心 (d.mid_point_x, d.mid_point_y)，长宽 (d.length, d.width)
            图像.设置放大窗口(d.mid_point_x, d.mid_point_y, d.length, d.width)
        end
    end)

**六个参数的单位与取值范围由平台前端决定，本层只搬运不换算** ——
是"0-255 的像素"还是"万分比"，只有具体设备（ISP/镜头）知道，替调用方
挑一种解释，挑错了比不解释更难查。

**平台不等这条指令的应答**（实测 WVP 的 `dragZoomCmd` 不注册 Result 订阅），
但本层仍会回一条 —— 多回一条无害，而漏回会让"某天换了个平台"时出问题。

@api exgb28181client.on_drag_zoom(handler)
@function handler 原型 handler(d)，d 见 gb28181.devctl_parse 的返回
@return boolean
]]
function M.on_drag_zoom(handler)
    if handler ~= nil and type(handler) ~= "function" then
        return false
    end
    g_drag_zoom_cb = handler
    return true
end

--[[
注册看守位(2022 新增)指令的处理者。

    client.on_home_position(function(d)
        if d.enabled == 1 then
            云台.启用看守位(d.preset_index, d.reset_time)
        else
            云台.停用看守位()
        end
    end)

字段取值：`enabled` 为 0/1；`reset_time`(等待秒数)与 `preset_index`(预置位号)
**为 -1 表示平台没给** —— 0 是合法取值，不能用 0 兼作"没给"。

**这一项平台会等应答里的 `Result`**（实测 WVP 的 `homePositionCmd` 注册了
MessageEvent 订阅），所以千万别在这里默默失败：处理者抛异常时本层会回
ERROR，那就是正确的表达。

@api exgb28181client.on_home_position(handler)
@function handler 原型 handler(d)，d 见 gb28181.devctl_parse 的返回
@return boolean
]]
function M.on_home_position(handler)
    if handler ~= nil and type(handler) ~= "function" then
        return false
    end
    g_home_position_cb = handler
    return true
end

--[[
向上层派一个事件。

**给伴生模块用的**（目前是 exgb28181playback）：它们与 client 共用同一个
事件出口，应用只需注册一处 event_callback，不必再给每个模块各注册一个。

@api exgb28181client.emit_event(event, action, payload)
@return boolean 有回调且未抛异常时返回 true
]]
function M.emit_event(event, action, payload)
    if type(g_cb) ~= "function" then
        return false
    end
    emit(event, action, payload or {})
    return true
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
