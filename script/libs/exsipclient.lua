--[[
@module exsipclient
@summary SIP 信令客户端，支持 REGISTER、呼叫信令、MESSAGE、UDP/TCP 以及 401/407 Digest 认证。
@usage
本库实现的是“信令侧”的最小 SIP UA，只处理 REGISTER、INVITE、ACK、CANCEL、BYE、MESSAGE，
不包含 RTP 或音频媒体收发。媒体协商完成后会通过 event_callback 抛出结果，供外部媒体模块继续处理。

支持特性：
1、支持 UDP 和 TCP 传输
2、支持 401/407 Digest 鉴权，适用于常见 qop=auth 场景
3、基于 socket 异步回调和 sys.task 后台循环，适合常驻运行
4、通过统一事件回调向外抛出注册、通话、媒体、消息、错误等状态

基本用法：
local sip = require "exsipclient"

sip.start({
    server = "192.168.1.10",
    port = 5060,
    domain = "example.com",
    user = "1001",
    password = "123456",
    transport = "tcp",
    event_callback = function(event, action, payload)
        if event == "register" and action == "ok" then
            log.info("sip", "register ok", payload.expires)
        elseif event == "call" and action == "incoming" then
            log.info("sip", "incoming call", payload.from)
        elseif event == "message" and action == "rx" then
            log.info("sip", "message rx", payload.text)
        elseif event == "error" and action == "net" then
            log.warn("sip", "network error", payload.event, payload.param)
        end
    end
})

注意事项：
1、回调运行在 socket 回调或 SIP 任务中，应保持短小，避免长时间阻塞
2、如果服务器要求 TCP 或 TLS，请同步匹配 transport 和底层 socket 配置
3、Contact 使用本地 IP 和端口，若设备位于 NAT 后，需要服务端支持 rport 或 received 等机制
]]
local proto = require "exsipproto"

local M = {}
-- 全局回调/控制（单实例）
local g_callback = nil
local g_started = false
local g_stop = false

local SIP_EVENT = {
    LIFECYCLE = "lifecycle",
    REGISTER = "register",
    CALL = "call",
    MEDIA = "media",
    MESSAGE = "message",
    DTMF = "dtmf",
    ERROR = "error"
}

-- 统一事件回调分发。
local function emit_event(event, action, payload)
    if type(g_callback) ~= "function" then
        return
    end
    local ok, err = pcall(g_callback, event, action, payload or {})
    if not ok then
        log.error("sip", "callback error", event, action, err)
    end
end

local function emit_domain_event(event, action, payload)
    emit_event(event, action, payload or {})
end

local function emit_lifecycle(action, payload)
    emit_domain_event(SIP_EVENT.LIFECYCLE, action, payload)
end

local function emit_register(action, payload)
    emit_domain_event(SIP_EVENT.REGISTER, action, payload)
end

-- 将SIP服务器返回的REGISTER失败状态码转换为稳定的应用层原因枚举。
-- response_reason仍保留服务器原始原因短语，应用层无需依赖短语文本做逻辑判断。
local REGISTER_FAILURE_REASON = {
    [300] = "multiple_choices",              -- 多重选择，服务器返回多个注册地址
    [301] = "moved_permanently",              -- 永久移动，服务器返回新的注册地址
    [302] = "moved_temporarily",              -- 临时移动，服务器返回新的注册地址
    [305] = "use_proxy",                      -- 使用代理，服务器要求使用代理服务器
    [380] = "alternative_service",           -- 服务器建议使用备用服务
    [400] = "bad_request",                 -- 请求格式错误，服务器无法理解该REGISTER请求
    [401] = "authentication_failed",       -- 用户认证失败；首次401通常只是正常的鉴权挑战
    [403] = "forbidden",                   -- 服务器拒绝注册，常见原因是账号、密码或注册权限错误
    [404] = "not_found",                   -- 未找到注册账号、域或对应的服务器资源
    [405] = "method_not_allowed",          -- 服务器不允许使用REGISTER方法
    [406] = "not_acceptable",              -- 请求内容不满足服务器可接受的条件
    [407] = "proxy_authentication_failed", -- 代理服务器认证失败；首次407通常只是代理鉴权挑战
    [408] = "server_request_timeout",       -- 服务器等待请求完成超时
    [410] = "gone",                        -- 注册目标曾经存在，但现在已永久不可用
    [413] = "request_too_large",           -- REGISTER请求体过大
    [414] = "request_uri_too_long",        -- Request-URI长度超过服务器限制
    [415] = "unsupported_media_type",      -- 服务器不支持请求中的媒体类型
    [416] = "unsupported_uri_scheme",      -- 服务器不支持请求URI使用的协议类型
    [420] = "bad_extension",               -- 请求包含服务器不支持的SIP扩展
    [421] = "extension_required",          -- 服务器要求使用指定的SIP扩展
    [423] = "interval_too_brief",          -- 注册有效期过短，应根据Min-Expires增大Expires
    [480] = "temporarily_unavailable",     -- 注册目标当前暂时不可用
    [481] = "transaction_not_found",       -- 服务器找不到对应的事务或对话
    [482] = "request_merged",              -- 检测到合并或重复请求，可能与CSeq、Call-ID重复有关
    [483] = "too_many_hops",               -- 请求经过的代理跳数过多，Max-Forwards已耗尽
    [484] = "address_incomplete",          -- SIP地址不完整
    [485] = "ambiguous",                   -- SIP地址存在歧义，服务器匹配到多个目标
    [486] = "busy_here",                   -- 当前注册目标忙
    [487] = "request_terminated",          -- 请求在完成前被终止
    [488] = "not_acceptable_here",         -- 当前服务器无法接受该请求的部分参数
    [489] = "bad_event",                   -- 服务器不支持请求指定的事件类型
    [491] = "request_pending",             -- 同一事务或对话中已有待处理请求
    [493] = "undecipherable",              -- 服务器无法解密或解析请求中的加密内容
    [500] = "server_internal_error",       -- SIP服务器内部错误
    [501] = "not_implemented",             -- 服务器未实现处理该请求所需的功能
    [502] = "bad_gateway",                 -- 网关或上游SIP服务器返回异常
    [503] = "service_unavailable",         -- SIP服务暂时不可用，可关注Retry-After响应头
    [504] = "server_timeout",              -- 服务器等待上游服务器响应超时
    [505] = "version_not_supported",       -- 服务器不支持请求使用的SIP版本
    [513] = "message_too_large",           -- SIP消息整体长度超过服务器限制
    [600] = "busy_everywhere",             -- 注册目标在所有可达位置均忙
    [603] = "decline",                     -- 注册请求被明确拒绝
    [604] = "does_not_exist_anywhere",     -- 注册目标在服务器管理范围内不存在
    [606] = "not_acceptable_global"        -- 所有可达位置均无法接受该请求
}

local function register_failure_reason(code)
    return REGISTER_FAILURE_REASON[tonumber(code)] or "server_rejected"
end

-- 判断服务器地址是 IPv4、IPv6 还是域名，并拦截明显的格式错误。
-- 这里只做配置格式校验；格式正确的地址是否真实存在，仍需由 DNS/网络连接结果判断。
local function classify_server_address(address)
    if type(address) ~= "string" then
        return nil
    end

    local addr = address:match("^%s*(.-)%s*$")
    if not addr or addr == "" or #addr > 253 then
        return nil
    end

    local octets = {}
    for part in addr:gmatch("[^.]+") do
        octets[#octets + 1] = part
    end
    if #octets == 4 and addr:match("^%d+%.%d+%.%d+%.%d+$") then
        for _, part in ipairs(octets) do
            local value = tonumber(part)
            if not value or value < 0 or value > 255 then
                return nil
            end
        end
        return "ipv4"
    end

    -- 包含冒号的地址交给底层 IPv6 解析器处理，避免在 Lua 层重复实现完整 IPv6 语法。
    if addr:find(":", 1, true) then
        return addr:match("^[%x:%.]+$") and "ipv6" or nil
    end

    -- 纯数字和点组成但又不是合法 IPv4，属于明显的 IP 地址格式错误。
    if addr:match("^[%d%.]+$") then
        return nil
    end
    if addr:sub(1, 1) == "." or addr:sub(-1) == "." or addr:find("..", 1, true) then
        return nil
    end
    for label in addr:gmatch("[^.]+") do
        if #label > 63 or not label:match("^[%w%-]+$") or label:sub(1, 1) == "-" or label:sub(-1) == "-" then
            return nil
        end
    end
    return "hostname"
end

local function emit_call(action, payload)
    emit_domain_event(SIP_EVENT.CALL, action, payload)
end

local function emit_media(action, payload)
    emit_domain_event(SIP_EVENT.MEDIA, action, payload)
end

local function emit_message(action, payload)
    emit_domain_event(SIP_EVENT.MESSAGE, action, payload)
end

local function emit_dtmf(action, payload)
    emit_domain_event(SIP_EVENT.DTMF, action, payload)
end


-- 本地监听端口（0 表示随机端口；建议固定，方便服务器回包）
local LOCAL_PORT = 5062
-- 注册有效期（秒）
local REGISTER_EXPIRES = 600
-- 默认外呼超时时间（秒），超过该时间未接通则自动取消
local CALL_TIMEOUT = 30
-- RFC 3261 13.3.1.4：INVITE 2xx 按 T1/T2 重传，64*T1 内等待 ACK（毫秒）。
local SIP_T1 = 500
local SIP_T2 = 4000
-- 最多 8 通后台信令收尾，另留一个 RTP 端口给前台业务。
local MAX_CLOSING_DIALOGS = 8

-- ==================== 实现区 ====================

local TOPIC_DISCONNECT = "SIP_REG_DISCONNECT"
local TOPIC_CMD = "SIP_CMD"

-- 传输层选择：UDP/TCP
local SIP_TRANSPORT = "TCP"

-- 获取当前时间戳，优先使用 `mcu.ticks()`，否则退化到 `os.time()`。
-- 这里主要用于生成 branch/tag/call-id/cnonce 等临时标识。
local function now_ticks()
    if _G.mcu and type(mcu.ticks) == "function" then
        return mcu.ticks()
    end
    return (os.time() or 0) * 1000
end

-- 生成一个短 token，用于 branch/tag/call-id 等 SIP 标识。
local function gen_token(prefix)
    local raw = string.format("%s:%s:%s", prefix or "t", tostring(now_ticks()), tostring(os.time() or 0))
    return (crypto.md5(raw):lower():sub(1, 16))
end

-- 纯协议工具统一放到 sip_proto，主脚本只保留状态机和事务控制。
local parse_headers = proto.parse_headers
local sip_pop_stream_message = proto.pop_stream_message
local split_sip_message = proto.split_message
local parse_request_line = proto.parse_request_line

-- 从 `CSeq` 头中提取数字序号。
local function cseq_number(cseq)
    if not cseq then
        return nil
    end
    local n = cseq:match("^(%d+)")
    return n and tonumber(n) or nil
end

-- 从 `CSeq` 头中提取方法名，例如 REGISTER / INVITE / BYE。
local function cseq_method(cseq)
    if not cseq then
        return nil
    end
    local m = cseq:match("^%d+%s+([A-Z]+)")
    return m
end

local function header_tag_value(hval)
    if not hval then
        return nil
    end
    return hval:match(";tag=([^;>%s]+)")
end

-- 确保 `To` 头中带有 tag。
-- 在 UAS 返回 180/200 时，通常需要给 `To` 头补本地 tag。
local function ensure_to_has_tag(to_header, tag)
    if not to_header then
        return nil
    end
    if to_header:find(";tag=", 1, true) then
        return to_header
    end
    return to_header .. ";tag=" .. (tag or gen_token("tag"))
end

local parse_status = proto.parse_status
local parse_www_authenticate = proto.parse_www_authenticate
local sip_digest_auth = proto.digest_auth
local build_auth_header = proto.build_auth_header
local build_request = proto.build_request
local build_proto_response = proto.build_response
local build_media_session = proto.build_media_session

-- 构造 REGISTER 报文，可选携带 Digest Authorization。
local function build_register(state, auth)
    local uri = "sip:" .. state.sip_domain
    local from_to = string.format("<sip:%s@%s>", state.sip_username, state.sip_domain)

    return build_request({
        method = "REGISTER",
        uri = uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = state.branch
        },
        headers = {{"From", string.format("%s;tag=%s", from_to, state.from_tag)}, {"To", from_to},
                   {"Call-ID", string.format("%s@luatos", state.call_id)},
                   {"CSeq", string.format("%d REGISTER", state.cseq)}},
        contact_ctx = {
            user = state.sip_username,
            local_ip = state.local_ip,
            local_port = state.local_port,
            transport = state.sip_transport,
            header_params = {string.format("expires=%d", state.expires)}
        },
        user_agent = "LuatOS-SIP-REG",
        auth_header = auth and build_auth_header(auth) or nil
    })
end

-- LuatOS UDP `socket.rx()` 某些场景下返回 5 字节二进制地址，这里转成点分十进制字符串。
local function decode_udp_remote_ip(remote_ip)
    if not remote_ip then
        return nil
    end
    if #remote_ip == 5 then
        local ip1, ip2, ip3, ip4 = remote_ip:byte(2), remote_ip:byte(3), remote_ip:byte(4), remote_ip:byte(5)
        return string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
    end
    return nil
end

-- 从 Contact 头中提取 URI，优先匹配 <...> 形式，否则回退到裸 URI。
-- 从 Contact 头中提取 Remote Target URI。
-- RFC 3261 §12.1 要求对话内后续请求（BYE/ACK/re-INVITE）的 Request-URI
-- 必须使用对端在 INVITE/200 OK 中携带的 Contact URI，而非原始 AOR。
local function contact_uri(contact_header)
    if not contact_header then return nil end
    local uri = contact_header:match("<([^>]+)>")
    if uri then return uri end
    return contact_header:match("(sip:[^;%s>]+)")
end

-- 从 Record-Route 头中提取有序的 URI 列表（每项为裸 URI 字符串）。
local function parse_route_set(rr_header)
    if not rr_header or rr_header == "" then return {} end
    local routes = {}
    for entry in rr_header:gmatch("[^,]+") do
        local uri = entry:match("<([^>]+)>")
        if uri then routes[#routes + 1] = uri end
    end
    return routes
end

local function extract_auth_challenge(headers)
    local www = headers["www-authenticate"] or headers["proxy-authenticate"]
    local www_params = parse_www_authenticate(www)
    if not (www_params and www_params.realm and www_params.nonce) then
        return nil
    end
    return www_params
end

local function build_digest_retry_auth(state, code, www_params, method, uri)
    local digest, err = sip_digest_auth({
        username = state.sip_username,
        password = state.sip_password,
        realm = www_params.realm,
        nonce = www_params.nonce,
        opaque = www_params.opaque,
        algorithm = www_params.algorithm,
        qop = www_params.qop,
        method = method,
        uri = uri,
        nc = "00000001",
        cnonce = gen_token("cn")
    })
    if not digest then
        return nil, err
    end
    digest.header_name = (code == 407) and "Proxy-Authorization" or "Authorization"
    return digest
end

local normalize_codec_list = proto.normalize_codec_list
local build_sdp = proto.build_sdp
local parse_sdp = proto.parse_sdp

-- SDP 与媒体 session 使用同一通话固定的端口，不改写配置中的首选端口。
local function build_dialog_sdp(state, dialog)
    return build_sdp({
        local_ip = state.local_ip,
        media = {
            local_rtp_port = dialog.local_rtp_port,
            codecs = state.media.codecs,
            ptime = state.media.ptime
        }
    }, "sendrecv")
end

-- 构造通用 SIP 响应，用于 100/180/200/4xx/5xx 等请求应答场景。
local function build_response(state, req_headers, code, reason, extra_headers, body)
    return build_proto_response({
        code = code,
        reason = reason,
        headers = {req_headers["via"] and {"Via", req_headers["via"]} or nil,
                   req_headers["from"] and {"From", req_headers["from"]} or nil,
                   req_headers["to"] and {"To", req_headers["to"]} or nil,
                   req_headers["call-id"] and {"Call-ID", req_headers["call-id"]} or nil,
                   req_headers["cseq"] and {"CSeq", req_headers["cseq"]} or nil},
        contact_ctx = {
            user = state.sip_username,
            local_ip = state.local_ip,
            local_port = state.local_port,
            transport = state.sip_transport
        },
        extra_headers = extra_headers,
        body = body or "",
        content_type = (body and #body > 0) and "application/sdp" or nil
    })
end

-- 2xx INVITE 的 ACK 属于新事务，因此这里使用新的 branch。
-- Route 头与 BYE 逻辑一致：若存在路由集，必须在 From 之前依序写入，
-- 确保 ACK 经由与 INVITE 相同的代理链路到达对端（RFC 3261 §13.2.2.4）。
local function build_ack(state, dialog)
    local hdrs = {}
    if dialog.route_set and #dialog.route_set > 0 then
        for _, uri in ipairs(dialog.route_set) do
            hdrs[#hdrs + 1] = {"Route", "<" .. uri .. ">"}
        end
    end
    hdrs[#hdrs + 1] = {"From",    dialog.from}
    hdrs[#hdrs + 1] = {"To",      dialog.to}
    hdrs[#hdrs + 1] = {"Call-ID", dialog.call_id}
    hdrs[#hdrs + 1] = {"CSeq",    string.format("%d ACK", dialog.invite_cseq)}
    return build_request({
        method = "ACK",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = gen_token("br")
        },
        headers = hdrs
    })
end

-- 非 2xx INVITE 的 ACK 仍属于原事务，需要复用 INVITE 的 branch。
local function build_ack_non2xx(state, dialog)
    return build_request({
        method = "ACK",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = dialog.invite_branch
        },
        headers = {{"From", dialog.from}, {"To", dialog.to}, {"Call-ID", dialog.call_id},
                   {"CSeq", string.format("%d ACK", dialog.invite_cseq)}}
    })
end

-- BYE 用于结束已经建立的对话。
local function build_bye(state, dialog)
    dialog.cseq = (dialog.cseq or dialog.invite_cseq or 1) + 1
    -- 来电方向（UAS）发送 BYE 时，From/To 需与 UAC 视角一致：
    --   bye_from = 本端身份（INVITE 的 To + local_tag）
    --   bye_to   = 对端身份（INVITE 的 From）
    -- 外呼方向（UAC）bye_from/bye_to 未设置，直接沿用 dialog.from/to。
    local bye_from = dialog.bye_from or dialog.from
    local bye_to   = dialog.bye_to   or dialog.to

    -- Route 头必须按路由集顺序放在 From 之前（RFC 3261 §8.1.1）。
    local hdrs = {}
    if dialog.route_set and #dialog.route_set > 0 then
        for _, uri in ipairs(dialog.route_set) do
            hdrs[#hdrs + 1] = {"Route", "<" .. uri .. ">"}
        end
    end
    hdrs[#hdrs + 1] = {"From",    bye_from}
    hdrs[#hdrs + 1] = {"To",      bye_to}
    hdrs[#hdrs + 1] = {"Call-ID", dialog.call_id}
    hdrs[#hdrs + 1] = {"CSeq",    string.format("%d BYE", dialog.cseq)}

    log.info("sip", "BYE uri", dialog.remote_uri,
             "from", bye_from, "to", bye_to,
             "routes", dialog.route_set and #dialog.route_set or 0)
    return build_request({
        method = "BYE",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = gen_token("br")
        },
        headers = hdrs
    })
end

-- CANCEL 用于取消尚未建立的外呼 INVITE。
-- 关键点：必须复用原 INVITE 的 branch 与 CSeq 序号。
local function build_cancel(state, dialog)
    return build_request({
        method = "CANCEL",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = dialog.invite_branch
        },
        headers = {{"From", dialog.from}, {"To", dialog.to}, {"Call-ID", dialog.call_id},
                   {"CSeq", string.format("%d CANCEL", dialog.invite_cseq)}}
    })
end

-- 构造 INVITE，并附带本地 SDP offer。
-- 媒体真正启动要等对端 200 OK 携带 SDP answer 后再进行。
local function build_invite(state, dialog, auth)
    local uri = dialog.remote_uri
    local sdp = dialog.local_sdp or build_dialog_sdp(state, dialog)
    dialog.local_sdp = sdp

    dialog.invite_branch = dialog.invite_branch or gen_token("br")
    dialog.invite_cseq = dialog.invite_cseq or 1

    return build_request({
        method = "INVITE",
        uri = uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = dialog.invite_branch
        },
        headers = {{"From", dialog.from}, {"To", dialog.to}, {"Call-ID", dialog.call_id},
                   {"CSeq", string.format("%d INVITE", dialog.invite_cseq)}},
        contact_ctx = {
            user = state.sip_username,
            local_ip = state.local_ip,
            local_port = state.local_port,
            transport = state.sip_transport
        },
        user_agent = "LuatOS-SIP",
        auth_header = auth and build_auth_header(auth) or nil,
        body = sdp,
        content_type = "application/sdp"
    })
end

-- 构造即时消息 MESSAGE 请求。
local function build_message(state, msg, auth)
    local uri = msg.remote_uri
    local body = msg.body or ""

    msg.branch = msg.branch or gen_token("br")
    msg.cseq = msg.cseq or 1

    return build_request({
        method = "MESSAGE",
        uri = uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = msg.branch
        },
        headers = {{"From", msg.from}, {"To", msg.to}, {"Call-ID", msg.call_id},
                   {"CSeq", string.format("%d MESSAGE", msg.cseq)}},
        contact_ctx = {
            user = state.sip_username,
            local_ip = state.local_ip,
            local_port = state.local_port,
            transport = state.sip_transport
        },
        user_agent = "LuatOS-SIP",
        auth_header = auth and build_auth_header(auth) or nil,
        body = body,
        content_type = "text/plain"
    })
end

-- 构造已建立 dialog 内的 INFO 请求。INFO 与 BYE 一样必须沿用 dialog
-- 的路由集、Call-ID 和本地/远端 tag，但使用新的 branch 和递增的 CSeq。
local function build_info(state, dialog, tx, auth)
    local info_from = dialog.bye_from or dialog.from
    local info_to = dialog.bye_to or dialog.to
    local headers = {}
    if dialog.route_set and #dialog.route_set > 0 then
        for _, uri in ipairs(dialog.route_set) do
            headers[#headers + 1] = {"Route", "<" .. uri .. ">"}
        end
    end
    headers[#headers + 1] = {"From", info_from}
    headers[#headers + 1] = {"To", info_to}
    headers[#headers + 1] = {"Call-ID", dialog.call_id}
    headers[#headers + 1] = {"CSeq", string.format("%d INFO", tx.cseq)}
    return build_request({
        method = "INFO",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = tx.branch
        },
        headers = headers,
        contact_ctx = {
            user = state.sip_username,
            local_ip = state.local_ip,
            local_port = state.local_port,
            transport = state.sip_transport
        },
        user_agent = "LuatOS-SIP",
        auth_header = auth and build_auth_header(auth) or nil,
        body = proto.build_dtmf_relay_body(tx.digit, tx.duration),
        content_type = "application/dtmf-relay"
    })
end

-- 构造 OPTIONS 请求，用于 UDP NAT 保活 Ping。
-- 每次发送使用独立 Call-ID 和独立 options_cseq，不与 REGISTER 事务混淆。
local function build_options(state)
    local uri = "sip:" .. state.sip_domain
    local from_to = string.format("<sip:%s@%s>", state.sip_username, state.sip_domain)
    state.options_cseq = (state.options_cseq or 0) + 1
    return build_request({
        method = "OPTIONS",
        uri = uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = gen_token("br")
        },
        headers = {
            {"From", string.format("%s;tag=%s", from_to, gen_token("tag"))},
            {"To", string.format("<%s>", uri)},
            {"Call-ID", gen_token("opt") .. "@luatos"},
            {"CSeq", string.format("%d OPTIONS", state.options_cseq)},
            {"Accept", "application/sdp"},
            {"Allow", "INVITE, ACK, CANCEL, BYE, OPTIONS, MESSAGE, INFO"}
        },
        contact_ctx = {
            user = state.sip_username,
            local_ip = state.local_ip,
            local_port = state.local_port,
            transport = state.sip_transport
        },
        user_agent = "LuatOS-SIP"
    })
end

-- SIP 主任务。
--
-- 职责：
-- 1. 管理 REGISTER 生命周期与续租
-- 2. 管理当前通话对话、来电缓存与 MESSAGE 事务
-- 3. 处理 socket 生命周期与自动重连
-- 4. 在正确时机把媒体协商结果通过回调抛给外部媒体层
local function sip_task(opts)
    local rxbuf = zbuff.create(2048)
    opts = opts or {}

    -- `state` 是 SIP 主任务的唯一运行时状态容器。
    -- 这里把“注册状态”“对话状态”“消息事务状态”“媒体协商状态”集中管理，
    -- 避免全局散落多个可变变量，便于断线重连时整体重建。
    local state = {
        -- 账号与服务器配置。
        sip_username = opts.sip_username,
        sip_password = opts.sip_password,
        sip_domain = opts.sip_domain,
        sip_server_addr = opts.sip_server_addr,
        sip_server_port = opts.sip_server_port,
        adapter = opts.adapter,
        -- 锁定的适配器：第一次启动时的网卡，重连时始终使用这个
        locked_adapter = opts.adapter,
        local_port = opts.local_port or LOCAL_PORT,
        expires = opts.expires or REGISTER_EXPIRES,

        -- 传输层状态。
        sip_transport = opts.sip_transport,
        tcp_stream = "",

        -- REGISTER 事务基础字段。
        cseq = 1,
        call_id = gen_token("call"),
        from_tag = gen_token("tag"),
        branch = gen_token("br"),

        -- 注册与连接期状态。
        auth_tried = 0,
        reg_timer = nil,
        register_response_timer = nil,
        register_attempts = 0,
        register_response_timeout = math.max(1000, tonumber(opts.register_response_timeout) or 10000),
        register_max_attempts = math.max(1, tonumber(opts.register_max_attempts) or 3),
        last_register_response_code = nil,
        last_register_response_reason = nil,
        last_register_response_headers = nil,
        connect_fail_count = 0,
        connect_max_attempts = math.max(1, tonumber(opts.connect_max_attempts) or 3),
        server_address_type = classify_server_address(opts.sip_server_addr),
        netc = nil,

        online = false,
        last_www = nil,

        -- 当前通话状态：
        -- - `dialog`: 已发起或已接听的通话对话
        -- - `incoming_invite`: 尚未接听的来电缓存
        dialog = nil, -- 当前通话（入/出）
        incoming_invite = nil,
        -- 已结束本地业务、仍等待 ACK/BYE 的来电；不再发布业务或媒体事件。
        closing_dialogs = {},

        -- 当前正在进行的 MESSAGE 事务。
        msg_tx = nil, -- 正在发送的 MESSAGE

        -- 当前 SIP INFO DTMF 序列。一次序列仅允许一个在途 INFO，避免
        -- 交换平台按错误顺序接收号码。
        dtmf_tx = nil,
        dtmf_queue = {},
        dtmf_sequence = nil,
        dtmf_timer = nil,
        dtmf_timeout = tonumber(opts.dtmf_timeout) or 5000,

        -- UDP NAT 保活（OPTIONS Ping），TCP 模式下不使用。
        options_cseq = 0,
        options_timer = nil,
        options_pending = false,
        options_fail_count = 0,
        -- options_interval = tonumber(opts.options_interval) or 25000,
        options_interval = tonumber(opts.options_interval) or 60000,
        options_max_fail = tonumber(opts.options_max_fail) or 3,
        call_timeout = tonumber(opts.call_timeout) or CALL_TIMEOUT,
        debug_sip_response = opts.debug_sip_response == true,
        early_media = opts.early_media ~= false,
        early_media_response = tonumber(opts.early_media_response) or 183,

        -- 媒体协商结果缓存。
        -- SIP 层不会直接收发 RTP，但会把最终协商好的参数保存于此，
        -- 然后通过 event_callback("media", "ready", payload) 交给外部媒体模块。
        media = {
            local_rtp_port = tonumber(opts.rtp_port) or 40000,
            codecs = normalize_codec_list(opts.codecs or {"PCMU", "PCMA"}),
            ptime = tonumber(opts.ptime) or 20,
            active = false,
            session = nil
        },
        options_triggered_register = false, -- 是否因 OPTIONS Ping 触发过 REGISTER
    }
    log.info("sip", "SIP task uses locked adapter:", state.locked_adapter, "transport:", state.sip_transport)
    if not state.locked_adapter then
        state.locked_adapter = socket.dft()
        log.info("sip", "locked_adapter initialized to default:", state.locked_adapter)
    end

    local function copy_headers(headers)
        local out = {}
        for k, v in pairs(headers or {}) do
            out[k] = v
        end
        return out
    end

    -- 避免相同媒体参数的重复 ready 把上层音频引擎再次启动一遍。
    local function same_media_session(current, next_session)
        if not current or not next_session then
            return false
        end
        return tostring(current.call_id or "") == tostring(next_session.call_id or "") and
                   tostring(current.remote_ip or "") == tostring(next_session.remote_ip or "") and
                   tonumber(current.remote_port or 0) == tonumber(next_session.remote_port or 0) and
                   tostring(current.codec or "") == tostring(next_session.codec or "") and
                   tonumber(current.ptime or 0) == tonumber(next_session.ptime or 0) and
                   tonumber(current.local_rtp_port or 0) == tonumber(next_session.local_rtp_port or 0) and
                   tostring(current.remote_direction or "") == tostring(next_session.remote_direction or "")
    end

    -- 当本地 SDP 和远端 SDP 都齐备后，整理出媒体会话描述并通知上层。
    -- SIP 层只负责“协商结果”，不直接创建 RTP socket 或音频线程。
    local function maybe_start_media(dialog, source)
        if not dialog or dialog.terminating then
            return
        end
        if not dialog.local_sdp or not dialog.remote_sdp then
            return
        end
        if not dialog.remote_sdp.audio_port or dialog.remote_sdp.audio_port <= 0 then
            return
        end

        local session, err = build_media_session({
            call_id = dialog.call_id,
            remote_ip = dialog.remote_sdp.conn_ip or dialog.remote_ip or state.sip_server_addr,
            remote_sdp = dialog.remote_sdp,
            remote_sdp_raw = dialog.remote_sdp_raw,
            local_rtp_port = dialog.local_rtp_port,
            local_codecs = state.media.codecs,
            local_sdp = dialog.local_sdp,
            ptime = state.media.ptime,
            source = source
        })
        if not session then
            log.warn("sip", "no common media codec")
            return
        end
        -- 添加 SIP 层锁定的网卡适配器，确保媒体和 SIP 使用同一个网卡
        session.adapter = state.locked_adapter
        -- 某些设备会在通话建立后发 re-INVITE/重复 ACK；媒体未变化时不再重复通知上层。
        if state.media.active and same_media_session(state.media.session, session) then
            state.media.session = session
            return
        end

        -- 通知外部媒体层启动当前会话。

        state.media.active = true
        state.media.session = session
        emit_media("ready", session)
    end

    -- 通知外部媒体层停止当前会话。
    local function stop_media(reason)
        local active, session = state.media.active, state.media.session
        state.media.active = false
        state.media.session = nil
        if active then
            emit_media("stop", { reason = reason, session = session })
        end
    end

    local net_send_on

    -- 统一发送接口：写 socket 后调用 `socket.wait()`，尽量把发送与状态切换串起来。
    net_send_on = function(netc, data)
        if not netc or not data then
            return
        end
        socket.tx(netc, data)
        socket.wait(netc)
    end

    local function incoming_route_set(inv)
        local inv_rr = parse_route_set(inv.headers["record-route"])
        local uas_route_set = {}
        for i = #inv_rr, 1, -1 do uas_route_set[#uas_route_set + 1] = inv_rr[i] end
        return uas_route_set
    end

    local function closing_dialog_count()
        local count = 0
        for _ in pairs(state.closing_dialogs) do count = count + 1 end
        return count
    end

    local function allocate_rtp_port()
        local base = state.media.local_rtp_port
        local step = base + MAX_CLOSING_DIALOGS * 2 <= 65535 and 2 or -2
        for i = 0, MAX_CLOSING_DIALOGS do
            local port, used = base + i * step, false
            for _, dialog in pairs(state.closing_dialogs) do
                if dialog.local_rtp_port == port then used = true; break end
            end
            if not used then return port end
        end
    end

    local function is_closing_dialog(dialog)
        return dialog and state.closing_dialogs[dialog.call_id] == dialog
    end

    local function owns_dialog(dialog)
        return dialog and (state.dialog == dialog or is_closing_dialog(dialog))
    end

    local function ensure_incoming_dialog(inv)
        if not inv then
            return nil
        end
        if state.dialog and state.dialog.direction == "in" and state.dialog.call_id == inv.headers["call-id"] then
            return state.dialog
        end

        local dialog = {
            direction = "in",
            call_id = inv.headers["call-id"],
            from = inv.headers["from"],
            to = ensure_to_has_tag(inv.headers["to"], inv.local_tag),
            bye_from = ensure_to_has_tag(inv.headers["to"], inv.local_tag),
            bye_to = inv.headers["from"],
            remote_uri = contact_uri(inv.headers["contact"]) or inv.uri,
            remote_ip = inv.remote_ip,
            local_rtp_port = allocate_rtp_port(),
            invite_cseq = cseq_number(inv.headers["cseq"]) or 1,
            established = false,
            final_response_sent = false,
            early_media_sent = false,
            cseq = cseq_number(inv.headers["cseq"]) or 1,
            remote_sdp = inv.remote_sdp,
            remote_sdp_raw = inv.body,
            route_set = incoming_route_set(inv)
        }
        state.dialog = dialog
        return dialog
    end

    local function copy_incoming_headers(inv, dialog)
        local req_headers = {}
        for k, v in pairs(inv.headers) do
            req_headers[k] = v
        end
        req_headers["to"] = dialog.to
        return req_headers
    end

    local function progress_incoming()
        local inv = state.incoming_invite
        if not inv or not state.netc then
            log.warn("sip", "no incoming for progress")
            return
        end
        if not state.early_media then
            log.warn("sip", "early media disabled")
            return
        end
        local dialog = ensure_incoming_dialog(inv)
        if not dialog or dialog.established or dialog.final_response_sent then
            return
        end

        local body = dialog.local_sdp or build_dialog_sdp(state, dialog)
        dialog.local_sdp = body
        local code = state.early_media_response == 180 and 180 or 183
        local reason = (code == 180) and "Ringing" or "Session Progress"
        local resp_body = (code == 183) and body or ""
        local extra_headers = (code == 183) and {{"P-Early-Media", "sendrecv"}} or nil
        log.info("sip", "send early media", code)
        net_send_on(state.netc, build_response(state, copy_incoming_headers(inv, dialog), code, reason, extra_headers, resp_body))
        dialog.early_media_sent = true
        if code == 183 then
            maybe_start_media(dialog, "incoming_early_media")
        end
        emit_call("progress", {
            dialog = dialog,
            code = code,
            reason = reason
        })
    end

    local function fail_incoming(code, reason)
        local inv = state.incoming_invite
        local dialog = state.dialog
        if not inv or not state.netc then
            return false
        end
        if dialog and (dialog.established or dialog.final_response_sent) then
            return false
        end

        dialog = dialog or ensure_incoming_dialog(inv)
        code = tonumber(code) or 486
        reason = reason or ((code == 480) and "Temporarily Unavailable" or "Busy Here")
        log.info("sip", "fail incoming", code, reason)
        net_send_on(state.netc, build_response(state, copy_incoming_headers(inv, dialog), code, reason, nil, ""))
        stop_media("incoming_failed")
        local ended_dialog = dialog
        state.dialog = nil
        state.incoming_invite = nil
        emit_call("ended", {
            reason = "incoming_failed",
            code = code,
            dialog = ended_dialog
        })
        return true
    end

    local function net_send(data)
        net_send_on(state.netc, data)
    end

    local function stop_invite_response(dialog)
        local response = dialog and dialog.invite_response
        if not response then return end
        if response.retry_timer then sys.timerStop(response.retry_timer) end
        if response.timeout_timer then sys.timerStop(response.timeout_timer) end
        response.retry_timer = nil
        response.timeout_timer = nil
        response.waiting_ack = false
        -- 保留最后一份应答，重复 INVITE 只重发它，不再次启动媒体或延长等待。
    end

    local function schedule_invite_retry(response)
        response.retry_timer = sys.timerStart(function()
            sys.publish(TOPIC_CMD, "invite_2xx_retry", response)
        end, response.interval)
    end

    local function send_invite_ok(dialog, headers, body, request_to)
        local cseq = cseq_number(headers["cseq"])
        local response = dialog.invite_response
        if response and response.cseq == cseq then
            net_send(response.data)
            return
        end
        stop_invite_response(dialog)
        response = {
            dialog = dialog,
            cseq = cseq,
            request_to_tag = header_tag_value(request_to),
            data = build_response(state, headers, 200, "OK", nil, body),
            interval = SIP_T1,
            waiting_ack = true
        }
        dialog.invite_response = response
        schedule_invite_retry(response)
        response.timeout_timer = sys.timerStart(function()
            sys.publish(TOPIC_CMD, "invite_ack_timeout", response)
        end, 64 * SIP_T1)
        log.info("sip", "answer 200 OK, wait ACK", dialog.call_id, cseq)
        net_send(response.data)
    end

    local function is_pending_invite_response(response)
        return response and owns_dialog(response.dialog) and
            response.dialog.invite_response == response and response.waiting_ack and not g_stop
    end

    local function stop_call_timeout(dialog)
        dialog = dialog or state.dialog
        if dialog and dialog.timeout_timer then
            sys.timerStop(dialog.timeout_timer)
            dialog.timeout_timer = nil
        end
    end

    -- 结束一通前台业务时，只停止该对象的定时器。
    local function stop_dialog_timers(dialog)
        if not dialog then return end
        stop_call_timeout(dialog)
        stop_invite_response(dialog)
        if dialog.hangup_timer then
            sys.timerStop(dialog.hangup_timer)
            dialog.hangup_timer = nil
        end
    end

    local function release_closing_dialog(dialog, reason)
        if not is_closing_dialog(dialog) then return end
        stop_dialog_timers(dialog)
        state.closing_dialogs[dialog.call_id] = nil
        log.info("sip", "closing released", dialog.call_id, reason)
    end

    -- 连接生命周期结束时才统一清理全部对话，后台释放不触发业务回调。
    local function stop_all_call_timers()
        stop_dialog_timers(state.dialog)
        for _, dialog in pairs(state.closing_dialogs) do
            release_closing_dialog(dialog, "transport_closed")
        end
    end

    local function on_call_timeout()
        -- 额外检查：如果已停止，直接忽略
        if g_stop then
            log.warn("sip", "call timeout ignored - stopped")
            return
        end
        if not state.dialog or state.dialog.direction ~= "out" or state.dialog.established then
            log.warn("sip", "call timeout ignored - no active outgoing call or already established")
            return
        end
        log.warn("sip", "outgoing call timeout, canceling")
        -- 超时前清空定时器引用，避免重复触发
        state.dialog.timeout_timer = nil
        local cancel = build_cancel(state, state.dialog)
        net_send(cancel)
        local failed_dialog = state.dialog
        state.dialog = nil
        emit_call("failed", {
            code = 408,
            reason = "timeout",
            dialog = failed_dialog
        })
        emit_call("ended", {
            reason = "timeout",
            dialog = failed_dialog
        })
    end

    -- 停止等待 REGISTER 响应的定时器。
    local function stop_register_response_timer()
        if state.register_response_timer then
            sys.timerStop(state.register_response_timer)
            state.register_response_timer = nil
        end
    end

    -- REGISTER 发出后等待服务器响应。UDP 端口错误通常不会产生 socket 错误，
    -- 因此只能通过“连续多次发送 REGISTER 仍无任何 SIP 响应”识别为注册超时。
    local function start_register_response_timer()
        stop_register_response_timer()
        state.register_response_timer = sys.timerStart(function()
            state.register_response_timer = nil
            if state.online or not state.netc then
                return
            end

            if state.register_attempts < state.register_max_attempts then
                state.register_attempts = state.register_attempts + 1
                state.branch = gen_token("br")
                state.cseq = state.cseq + 1
                state.auth_tried = 0
                state.last_www = nil
                log.warn("sip", "REGISTER response timeout, retry",
                    state.register_attempts, "/", state.register_max_attempts,
                    state.sip_server_addr, state.sip_server_port)
                net_send(build_register(state, nil))
                start_register_response_timer()
                return
            end

            local has_sip_response = state.last_register_response_code ~= nil
            local failure_reason = has_sip_response and
                                       register_failure_reason(state.last_register_response_code) or
                                       "register_timeout"
            local failure_source = has_sip_response and "sip_response_timeout" or "timeout"
            local failure_hint = has_sip_response and
                                     "已收到SIP响应，但后续注册流程超时，请根据sip_code和response_reason排查" or
                                     "SIP服务器无响应，请检查服务器IP或域名、端口、传输协议、防火墙和SIP服务状态"
            log.error("sip", "REGISTER failed",
                "reason", failure_reason,
                "sip_code", state.last_register_response_code,
                "response_reason", state.last_register_response_reason,
                "attempts", state.register_attempts)
            emit_register("failed", {
                reason = failure_reason,
                source = failure_source,
                sip_code = state.last_register_response_code,
                response_reason = state.last_register_response_reason,
                headers = state.last_register_response_headers,
                attempts = state.register_attempts,
                server = state.sip_server_addr,
                port = state.sip_server_port,
                transport = state.sip_transport,
                retrying = true,
                hint = failure_hint
            })
            sys.publish(TOPIC_DISCONNECT)
        end, state.register_response_timeout)
    end

    -- 停止注册续租定时器，同时停止 UDP OPTIONS 保活定时器。
    local function stop_reg_timer()
        if state.reg_timer then
            sys.timerStop(state.reg_timer)
            state.reg_timer = nil
        end
        stop_register_response_timer()
        state.register_attempts = 0
        if state.options_timer then
            sys.timerStop(state.options_timer)
            state.options_timer = nil
        end
        state.options_pending = false
        state.options_fail_count = 0
        -- 清除“OPTIONS 404 已触发 REGISTER”的状态，
        -- 使下次重新连接后可以再次执行恢复注册。
        state.options_triggered_register = false
    end

    -- 按过期时间安排下一次 REGISTER 续租。
    -- 策略：尽量在到期前 30 秒续租，但最小间隔不低于 30 秒。
    local function schedule_reregister(expires)
        stop_reg_timer()
        local exp = tonumber(expires) or state.expires
        if exp < 60 then
            exp = 60
        end
        local delay_s = exp - 30
        if delay_s < 30 then
            delay_s = 30
        end
        state.reg_timer = sys.timerStart(function()
            if state.netc then
                state.branch = gen_token("br")
                state.cseq = state.cseq + 1
                state.auth_tried = 0
                local req = build_register(state, nil)
                log.info("sip", "re-register", "cseq", state.cseq)
                net_send(req)
            end
        end, delay_s * 1000)
        log.info("sip", "next register in", delay_s, "sec")
    end

    -- 启动 UDP OPTIONS 保活定时器（仅 UDP 模式下调用）。
    -- 每隔 options_interval ms 发一次 OPTIONS，连续 options_max_fail 次无响应则主动触发断线重连。
    local start_options_keepalive
    start_options_keepalive = function()
        if state.options_timer then
            return
        end
        local function do_options_ping()
            if not state.netc or not state.online then
                state.options_timer = nil
                return
            end
            if state.options_pending then
                state.options_fail_count = state.options_fail_count + 1
                log.warn("sip", "OPTIONS no reply, fail_count", state.options_fail_count)
                if state.options_fail_count >= state.options_max_fail then
                    log.warn("sip", "OPTIONS keepalive timeout, reconnecting")
                    state.options_timer = nil
                    sys.publish(TOPIC_DISCONNECT)
                    return
                end
            end
            state.options_pending = true
            local req = build_options(state)
            log.info("sip", "send OPTIONS ping")
            net_send(req)
            state.options_timer = sys.timerStart(do_options_ping, state.options_interval)
        end
        state.options_timer = sys.timerStart(do_options_ping, state.options_interval)
        log.info("sip", "UDP OPTIONS keepalive started, interval", state.options_interval, "ms")
    end

    -- 收到 REGISTER 的 401/407 后，构造带 Digest 的重试请求。
    local function send_register_with_auth(code, www_params)
        local uri = "sip:" .. state.sip_domain
        state.branch = gen_token("br")
        state.cseq = state.cseq + 1

        -- REGISTER 认证重试时：
        -- - 新事务使用新 branch
        -- - 同时提升 CSeq
        local digest, err = build_digest_retry_auth(state, code, www_params, "REGISTER", uri)

        if not digest then
            log.error("sip", "digest failed", err)
            return
        end

        local req = build_register(state, digest)
        log.info("sip", "send REGISTER (auth)", "cseq", state.cseq)
        net_send(req)
        start_register_response_timer()
    end

    -- 发起外呼。
    -- 这里只发送 INVITE + SDP offer，媒体要等 200 OK 后再启动。
    local function start_outgoing_call(target, from_number)
        if not state.online or not state.netc then
            log.warn("sip", "not online")
            emit_call("dial_rejected", { reason = "offline", target = target })
            return
        end
        if state.dialog or state.incoming_invite or closing_dialog_count() >= MAX_CLOSING_DIALOGS then
            log.warn("sip", "busy")
            emit_call("dial_rejected", { reason = "busy", target = target, dialog = state.dialog })
            return
        end

        local to_uri
        if type(target) == "string" and target:lower():find("^sip:") then
            to_uri = target
        else
            to_uri = string.format("sip:%s@%s", tostring(target or ""), state.sip_domain)
        end

        -- 外呼时会立即创建一个“待建立”的 dialog。
        -- 只有当收到 200 OK 并完成 ACK 后，该 dialog 才算真正 established。
        -- 非透传模式：From URI 始终保持注册账号，仅用显示名携带来电号码。
        -- 不传 from_number 时仍生成原有 From 格式。
        local from_to
        if type(from_number) == "string" and from_number:match("^[%d%+%-%._]+$") then
            from_to = string.format("\"%s\" <sip:%s@%s>",
                from_number, state.sip_username, state.sip_domain)
        else
            from_to = string.format("<sip:%s@%s>", state.sip_username, state.sip_domain)
        end
        local local_tag = gen_token("tag")
        local call_id = gen_token("call") .. "@luatos"

        local dialog = {
            direction = "out",
            call_id = call_id,
            from = string.format("%s;tag=%s", from_to, local_tag),
            to = string.format("<%s>", to_uri),
            remote_uri = to_uri,
            invite_cseq = 1,
            invite_branch = gen_token("br"),
            auth_tried = 0,
            established = false,
            cseq = 1,
            local_rtp_port = allocate_rtp_port()
        }
        state.dialog = dialog
        log.info("sip", "setting call timeout", state.call_timeout, "seconds")
        dialog.timeout_timer = sys.timerStart(on_call_timeout, state.call_timeout * 1000)

        local req = build_invite(state, dialog, nil)
        log.info("sip", "send INVITE", to_uri)
        net_send(req)
    end

    -- 接听当前缓存的来电 INVITE，回复 200 OK + SDP answer。
    local function answer_incoming()
        local inv = state.incoming_invite
        if not inv or not state.netc then
            log.warn("sip", "no incoming")
            return
        end
        if state.dialog and state.dialog.established then
            log.warn("sip", "already in call")
            return
        end

        local dialog = ensure_incoming_dialog(inv)
        if not dialog or dialog.terminating then
            return
        end

        -- 来电接听时，本端在 200 OK 中带回自己的 SDP answer。
        local body = dialog.local_sdp or build_dialog_sdp(state, dialog)
        dialog.local_sdp = body
        dialog.final_response_sent = true
        send_invite_ok(dialog, copy_incoming_headers(inv, dialog), body, inv.request_to)
    end

    -- INFO 队列清理函数在后面定义；提前声明，使挂断路径绑定到同一局部函数。
    local fail_dtmf

    -- ended 表示本地业务结束；后台信令只能释放自己的资源，不能再调用此入口。
    local function end_call_business(dialog, reason, code, action)
        if not dialog or state.dialog ~= dialog then return end
        dialog.terminating = true
        state.dialog = nil
        state.incoming_invite = nil
        stop_media(reason)
        fail_dtmf(reason, code)
        log.info("sip", "call cleared", dialog.call_id, reason, code or "")
        emit_call(action or "ended", { reason = reason, code = code, dialog = dialog })
    end

    local function finish_call(dialog, reason, code, action)
        if not dialog or state.dialog ~= dialog then return end
        stop_dialog_timers(dialog)
        end_call_business(dialog, reason, code, action)
    end

    local function send_dialog_bye(dialog)
        if dialog.bye_cseq then return end
        local bye = build_bye(state, dialog)
        dialog.bye_cseq = dialog.cseq
        log.info("sip", "send BYE", dialog.call_id, dialog.bye_cseq)
        net_send(bye)
    end

    local function start_hangup_timer(dialog)
        if dialog.hangup_timer then return end
        dialog.hangup_timer = sys.timerStart(function()
            sys.publish(TOPIC_CMD, "hangup_timeout", dialog)
        end, 5000)
    end

    -- 本地挂断先停媒体，再等待 SIP 最终响应；对端无响应时也有确定的清理出口。
    local function hangup_call(force)
        local dialog = state.dialog
        if force then
            finish_call(dialog, "hangup_timeout", 408)
            return
        end
        if not dialog then
            if state.incoming_invite then fail_incoming(486, "Busy Here") end
            return
        end
        if dialog.terminating then return end
        if state.incoming_invite and dialog.direction == "in" and
            not dialog.established and not dialog.final_response_sent then
            fail_incoming(486, "Busy Here")
            return
        end

        dialog.terminating = true
        stop_call_timeout(dialog)
        if not state.netc then
            finish_call(dialog, "local_hangup")
            return
        end
        if dialog.direction == "in" and dialog.invite_response and dialog.invite_response.waiting_ack then
            -- 不重建应答或定时器：仍以首次 200 的 64*T1 为截止时间。
            state.closing_dialogs[dialog.call_id] = dialog
            log.info("sip", "closing created, wait ACK", dialog.call_id, "rtp", dialog.local_rtp_port)
            end_call_business(dialog, "local_hangup")
            return
        end
        stop_media("local_hangup")
        fail_dtmf("local_hangup")
        start_hangup_timer(dialog)
        if dialog.direction == "out" and not dialog.established then
            log.info("sip", "send CANCEL")
            net_send(build_cancel(state, dialog))
        else
            send_dialog_bye(dialog)
        end
    end

    -- 发起一次 MESSAGE 事务。
    local function start_send_message(target, text)
        if not state.online or not state.netc then
            log.warn("sip", "not online")
            return
        end

        local to_uri
        if type(target) == "string" and target:lower():find("^sip:") then
            to_uri = target
        else
            to_uri = string.format("sip:%s@%s", tostring(target or ""), state.sip_domain)
        end

        local from_to = string.format("<sip:%s@%s>", state.sip_username, state.sip_domain)
        local local_tag = gen_token("tag")
        local call_id = gen_token("msg") .. "@luatos"

        local msg = {
            call_id = call_id,
            from = string.format("%s;tag=%s", from_to, local_tag),
            to = string.format("<%s>", to_uri),
            remote_uri = to_uri,
            cseq = 1,
            branch = gen_token("br"),
            auth_tried = 0,
            body = tostring(text or "")
        }
        state.msg_tx = msg

        local req = build_message(state, msg, nil)
        log.info("sip", "send MESSAGE", to_uri, "len", #msg.body)
        net_send(req)
    end

    local function stop_dtmf_timer(tx)
        if tx and tx.timeout_timer then
            sys.timerStop(tx.timeout_timer)
            tx.timeout_timer = nil
        end
        if state.dtmf_timer then
            sys.timerStop(state.dtmf_timer)
            state.dtmf_timer = nil
        end
    end

    fail_dtmf = function(reason, code)
        local sequence = state.dtmf_sequence
        local tx = state.dtmf_tx
        stop_dtmf_timer(tx)
        state.dtmf_tx = nil
        state.dtmf_queue = {}
        state.dtmf_sequence = nil
        if sequence then
            emit_dtmf("failed", {
                digits = sequence.digits,
                digit = tx and tx.digit or nil,
                index = sequence.index,
                code = code,
                reason = reason
            })
        end
    end

    local function complete_dtmf()
        local sequence = state.dtmf_sequence
        stop_dtmf_timer(state.dtmf_tx)
        state.dtmf_tx = nil
        state.dtmf_queue = {}
        state.dtmf_sequence = nil
        if sequence then
            emit_dtmf("completed", { digits = sequence.digits, code = sequence.last_code or 200 })
        end
    end

    local send_next_dtmf

    local function start_dtmf_timeout(tx)
        if tx.timeout_timer then
            sys.timerStop(tx.timeout_timer)
        end
        tx.timeout_timer = sys.timerStart(function()
            if state.dtmf_tx == tx then
                log.warn("sip", "INFO DTMF timeout", tx.digit)
                fail_dtmf("timeout", 408)
            end
        end, state.dtmf_timeout)
    end

    local function schedule_next_dtmf(interval)
        if interval <= 0 then
            send_next_dtmf()
            return
        end
        state.dtmf_timer = sys.timerStart(function()
            state.dtmf_timer = nil
            send_next_dtmf()
        end, interval)
    end

    send_next_dtmf = function()
        if state.dtmf_tx then
            return
        end
        local sequence = state.dtmf_sequence
        local dialog = state.dialog
        if not sequence then
            return
        end
        if not state.online or not state.netc or not dialog or not dialog.established or dialog.terminating then
            fail_dtmf("dialog_not_established")
            return
        end
        local digit = table.remove(state.dtmf_queue, 1)
        if not digit then
            complete_dtmf()
            return
        end
        sequence.index = sequence.index + 1
        dialog.cseq = (dialog.cseq or dialog.invite_cseq or 1) + 1
        local tx = {
            digit = digit,
            duration = sequence.duration,
            cseq = dialog.cseq,
            branch = gen_token("br"),
            call_id = dialog.call_id,
            auth_tried = 0
        }
        state.dtmf_tx = tx
        start_dtmf_timeout(tx)
        log.info("sip", "send INFO DTMF", digit, "index", sequence.index)
        net_send(build_info(state, dialog, tx))
    end

    -- 发送一串 dialog 内 DTMF。接口调用在 SIP task 中串行执行。
    local function start_dtmf(digits, duration, interval)
        digits = type(digits) == "string" and digits:upper() or ""
        if #digits == 0 or #digits > 32 or not digits:match("^[0-9A-D%*#]+$") then
            emit_dtmf("failed", { digits = digits, reason = "invalid_digits" })
            return
        end
        if state.dtmf_tx or state.dtmf_sequence then
            emit_dtmf("failed", { digits = digits, reason = "busy" })
            return
        end
        if not state.online or not state.netc or not state.dialog or not state.dialog.established then
            emit_dtmf("failed", { digits = digits, reason = "dialog_not_established" })
            return
        end
        duration = tonumber(duration) or 160
        interval = tonumber(interval) or 100
        if duration < 50 then duration = 50 end
        if duration > 2000 then duration = 2000 end
        if interval < 0 then interval = 0 end
        if interval > 5000 then interval = 5000 end
        state.dtmf_queue = {}
        for i = 1, #digits do
            state.dtmf_queue[#state.dtmf_queue + 1] = digits:sub(i, i)
        end
        state.dtmf_sequence = {
            digits = digits,
            duration = duration,
            interval = interval,
            index = 0
        }
        emit_dtmf("queued", { digits = digits, duration = duration, interval = interval })
        send_next_dtmf()
    end

    -- 在旧 socket 释放前完成一次离线清理；迟到 CLOSED 不能清理重连后的通话。
    local function clear_connection(netc)
        if state.netc ~= netc then return end
        state.netc = nil
        state.online = false
        stop_reg_timer()
        stop_all_call_timers()
        stop_media("socket_closed")
        state.dialog = nil
        state.incoming_invite = nil
        state.msg_tx = nil
        state.tcp_stream = ""
        fail_dtmf("socket_closed")
        emit_lifecycle("offline", { reason = "socket_closed" })
    end

    -- 订阅外部命令（call/progress/answer/fail/hangup/message/dtmf）。
    -- 外部 API 只负责 `sys.publish()`，真正执行统一留在 SIP task 内。
    local function command_handler(action, arg)
        if g_stop then return end
        log.info("sip", "cmd", action, arg or "")
        if action == "invite_2xx_retry" then
            if is_pending_invite_response(arg) then
                log.info("sip", "retry INVITE 200", arg.dialog.call_id, arg.cseq)
                net_send(arg.data)
                arg.interval = math.min(arg.interval * 2, SIP_T2)
                schedule_invite_retry(arg)
            end
        elseif action == "invite_ack_timeout" then
            if is_pending_invite_response(arg) then
                local dialog = arg.dialog
                log.warn("sip", "ACK timeout", dialog.call_id, arg.cseq)
                dialog.terminating = true
                stop_invite_response(dialog)
                if is_closing_dialog(dialog) then
                    start_hangup_timer(dialog)
                    send_dialog_bye(dialog)
                else
                    send_dialog_bye(dialog)
                    finish_call(dialog, "ack_timeout", 408)
                end
            end
        elseif action == "hangup_timeout" then
            if is_closing_dialog(arg) then
                release_closing_dialog(arg, "bye_timeout")
            else
                finish_call(arg, "hangup_timeout", 408)
            end
        else
            if type(arg) == "table" and arg.call_id then
                local inv = state.incoming_invite
                local active_id = state.dialog and state.dialog.call_id or (inv and inv.headers["call-id"])
                if active_id ~= arg.call_id then
                    log.info("sip", "ignore stale call command", action, arg.call_id)
                    return
                end
            end
            if action == "call" then
                if type(arg) == "table" then
                    start_outgoing_call(arg.target, arg.from_number)
                else
                    -- 兼容旧的内部命令格式。
                    start_outgoing_call(arg)
                end
            elseif action == "progress" then
                progress_incoming()
            elseif action == "answer" then
                answer_incoming()
            elseif action == "fail" then
                arg = type(arg) == "table" and arg or {}
                fail_incoming(arg.code, arg.reason)
            elseif action == "hangup" then
                hangup_call(arg == true or (type(arg) == "table" and arg.force == true))
            elseif action == "message" and type(arg) == "table" then
                start_send_message(arg.target, arg.text)
            elseif action == "dtmf" and type(arg) == "table" then
                start_dtmf(arg.digits, arg.duration, arg.interval)
            end
        end
    end
    sys.subscribe(TOPIC_CMD, command_handler)

    -- socket 回调：整个 SIP 信令收发与状态推进的入口。
    local function netCB(netc, event, param)
        if netc ~= state.netc then return end
        if param ~= 0 then
            log.warn("sip", "net error", event, param)
            stop_reg_timer()
            stop_all_call_timers()
                        state.connect_fail_count = state.connect_fail_count + 1
            if not state.online and state.connect_fail_count >= state.connect_max_attempts then
                local reason = state.server_address_type == "hostname" and "dns_or_connect_failed" or
                                   "server_unreachable"
                local hint = state.server_address_type == "hostname" and
                                 "服务器域名解析或连接失败，请检查域名、DNS、端口、网络和SIP服务状态" or
                                 "服务器IP或端口不可达，请检查IP、端口、路由、防火墙和SIP服务状态"
                log.error("sip", "server connection failed",
                    state.sip_server_addr, state.sip_server_port,
                    "attempts", state.connect_fail_count)
                emit_register("failed", {
                    reason = reason,
                    source = "network",
                    attempts = state.connect_fail_count,
                    server = state.sip_server_addr,
                    port = state.sip_server_port,
                    transport = state.sip_transport,
                    net_event = event,
                    net_error = param,
                    retrying = true,
                    hint = hint
                })
                state.connect_fail_count = 0
            end
            emit_event(SIP_EVENT.ERROR, "net", {
                event = event,
                param = param,
                server = state.sip_server_addr,
                port = state.sip_server_port,
                transport = state.sip_transport
            })
            sys.publish(TOPIC_DISCONNECT)
            return
        end

        if event == socket.LINK then
            -- 网卡 linkup 事件
            return
        end

        if event == socket.ON_LINE then
            -- ON_LINE: TCP/UDP connect 完成（或 DNS 完成），可以发 REGISTER
            state.connect_fail_count = 0
            -- 尝试获取本地IP填Contact
            local ip = socket.localIP(state.current_adapter)
            if type(ip) == "string" and #ip > 0 then
                state.local_ip = ip
            end

            -- 每次重新连上SIP服务器，创建新的REGISTER事务并清理认证状态。
            state.branch = gen_token("br")
            -- 同一个注册实例必须保持CSeq单调递增；如果保留Call-ID和From tag却把
            -- CSeq重置为1，网络切换后服务器可能将新REGISTER判为合并请求并返回482。
            state.cseq = state.cseq + 1
            state.auth_tried = 0
            state.last_www = nil
            state.last_register_response_code = nil
            state.last_register_response_reason = nil
            state.last_register_response_headers = nil

            local req = build_register(state, nil)
            log.info("sip", "send REGISTER", state.sip_server_addr, state.sip_server_port)
            net_send_on(netc, req)
            state.register_attempts = 1
            start_register_response_timer()
            state.online = false
            emit_lifecycle("online", {
                server = state.sip_server_addr,
                port = state.sip_server_port,
                transport = state.sip_transport,
                local_ip = state.local_ip
            })
            return
        end

        if event == socket.EVENT then
            local function retry_transaction_auth(code, headers, opts)
                local tx = opts.tx
                if tx.auth_tried >= 1 then
                    log.error("sip", opts.auth_failed_log)
                    if opts.on_failed then
                        opts.on_failed(tx)
                    end
                    return true
                end

                local www_params = extract_auth_challenge(headers)
                if not www_params then
                    log.error("sip", opts.no_challenge_log)
                    if opts.on_failed then
                        opts.on_failed(tx)
                    end
                    return true
                end

                tx.auth_tried = tx.auth_tried + 1
                if opts.before_digest then
                    opts.before_digest(tx)
                end

                local digest, err = build_digest_retry_auth(state, code, www_params, opts.method,
                    opts.uri or tx.remote_uri)
                if not digest then
                    log.error("sip", opts.digest_failed_log, err)
                    if opts.on_failed then
                        opts.on_failed(tx)
                    end
                    return true
                end

                opts.send(digest, tx)
                if opts.emit then
                    opts.emit(code, tx, www_params)
                end
                return true
            end

            local function handle_invite_request(req_headers, req_uri, body, rip, remote_port)
                local invite_cseq = cseq_number(req_headers["cseq"]) or 1
                local dialog = state.dialog
                local inv = state.incoming_invite
                local active_id = dialog and dialog.call_id or (inv and inv.headers["call-id"])
                if active_id and active_id ~= req_headers["call-id"] then
                    local busy_headers = copy_headers(req_headers)
                    busy_headers["to"] = ensure_to_has_tag(busy_headers["to"], gen_token("tag"))
                    net_send_on(netc, build_response(state, busy_headers, 486, "Busy Here", nil, ""))
                    return
                end
                if inv and not dialog then
                    -- 等待上一通清理或呼叫间隔时尚无 dialog，重传只重发临时应答。
                    local code = state.early_media and 100 or 180
                    net_send_on(netc, build_response(state, copy_headers(inv.headers), code,
                        code == 100 and "Trying" or "Ringing", nil, ""))
                    return
                end

                if dialog and dialog.direction == "in" and dialog.call_id == req_headers["call-id"] then
                    local resp_headers = copy_headers(req_headers)
                    resp_headers["to"] = dialog.to

                    local response = dialog.invite_response
                    if response and response.cseq == invite_cseq then
                        net_send_on(netc, response.data)
                        return
                    end
                    -- 仅发过早期媒体时重发 183，不能把 early media 误推进为接听。
                    if not dialog.established and invite_cseq == dialog.invite_cseq then
                        local resp_body = dialog.local_sdp or build_dialog_sdp(state, dialog)
                        dialog.local_sdp = resp_body
                        if dialog.early_media_sent then
                            net_send_on(netc, build_response(state, resp_headers, 183, "Session Progress", {{"P-Early-Media", "sendrecv"}}, resp_body))
                        else
                            net_send_on(netc, build_response(state, resp_headers, 100, "Trying", nil, ""))
                        end
                        return
                    end

                    local dialog_to_tag = header_tag_value(dialog.to)
                    local req_to_tag = header_tag_value(req_headers["to"])
                    -- 已建立来电对话内的 INVITE 按 re-INVITE 处理，不再抛成新的 incoming。
                    if dialog.established and not dialog.terminating and dialog_to_tag and req_to_tag == dialog_to_tag then
                        if response and response.waiting_ack then
                            net_send_on(netc, build_response(state, resp_headers, 491, "Request Pending", nil, ""))
                            return
                        end
                        local resp_body = build_dialog_sdp(state, dialog)
                        dialog.local_sdp = resp_body
                        dialog.remote_uri = req_uri or dialog.remote_uri
                        dialog.remote_ip = rip or dialog.remote_ip
                        dialog.remote_sdp_raw = body
                        dialog.remote_sdp = parse_sdp(body)
                        send_invite_ok(dialog, resp_headers, resp_body, req_headers["to"])
                        return
                    end
                end
                if dialog then
                    net_send_on(netc, build_response(state, req_headers, 481, "Call/Transaction Does Not Exist", nil, ""))
                    return
                end

                if closing_dialog_count() >= MAX_CLOSING_DIALOGS then
                    local unavailable = copy_headers(req_headers)
                    unavailable["to"] = ensure_to_has_tag(unavailable["to"], gen_token("tag"))
                    net_send_on(netc, build_response(state, unavailable, 480, "Temporarily Unavailable", nil, ""))
                    return
                end
                local request_to = req_headers["to"]
                local local_tag = gen_token("tag")
                local to_hdr = ensure_to_has_tag(req_headers["to"], local_tag)
                req_headers["to"] = to_hdr
                state.incoming_invite = {
                    headers = req_headers,
                    request_to = request_to,
                    uri = req_uri,
                    body = body,
                    remote_sdp = parse_sdp(body),
                    remote_ip = rip,
                    remote_port = remote_port,
                    local_tag = local_tag
                }
                net_send_on(netc, build_response(state, req_headers, 100, "Trying", nil, ""))
                if not state.early_media then
                    net_send_on(netc, build_response(state, req_headers, 180, "Ringing", nil, ""))
                end
                emit_call("incoming", {
                    from = req_headers["from"],
                    call_id = req_headers["call-id"],
                    uri = req_uri,
                    headers = req_headers,
                    body = body,
                    remote_sdp = state.incoming_invite.remote_sdp
                })
                emit_call("ringing", {
                    call_id = req_headers["call-id"],
                    from = req_headers["from"],
                    to = req_headers["to"],
                    headers = req_headers,
                    early_media = state.early_media
                })
                emit_media("offer", {
                    call_id = req_headers["call-id"],
                    from = req_headers["from"],
                    sdp = state.incoming_invite.remote_sdp,
                    raw_sdp = body
                })
            end

            local function handle_ack_request(req_headers)
                local dialog = state.dialog
                local response = dialog and dialog.invite_response
                if not dialog or dialog.direction ~= "in" or dialog.call_id ~= req_headers["call-id"] or
                    not response or not response.waiting_ack or response.cseq ~= cseq_number(req_headers["cseq"]) or
                    header_tag_value(req_headers["to"]) ~= header_tag_value(dialog.to) or
                    header_tag_value(req_headers["from"]) ~= header_tag_value(dialog.from) then
                    return
                end
                stop_invite_response(dialog)
                if dialog.terminating then
                    dialog.established = true
                    state.incoming_invite = nil
                    start_hangup_timer(dialog)
                    send_dialog_bye(dialog)
                    return
                end
                -- re-INVITE 的 ACK 只完成媒体更新，不再触发 established。
                if dialog.established then
                    maybe_start_media(dialog, "incoming_reinvite_ack")
                    return
                end
                dialog.established = true
                state.incoming_invite = nil
                maybe_start_media(dialog, "incoming_ack")
                log.info("sip", "call established (incoming)")
                emit_call("established", { dialog = dialog })
            end

            local function handle_bye_request(req_headers)
                local dialog = state.dialog
                if not dialog or dialog.call_id ~= req_headers["call-id"] then
                    net_send_on(netc, build_response(state, req_headers, 481, "Call/Transaction Does Not Exist", nil, ""))
                    return
                end
                req_headers["to"] = dialog.to
                net_send_on(netc, build_response(state, req_headers, 200, "OK", nil, ""))
                finish_call(dialog, "peer_hangup")
            end

            local function handle_cancel_request(req_headers)
                local inv = state.incoming_invite
                if not inv or not inv.headers or inv.headers["call-id"] ~= req_headers["call-id"] or
                    cseq_number(req_headers["cseq"]) ~= cseq_number(inv.headers["cseq"]) then
                    net_send_on(netc, build_response(state, req_headers, 481, "Call/Transaction Does Not Exist", nil, ""))
                    return
                end
                net_send_on(netc, build_response(state, req_headers, 200, "OK", nil, ""))
                -- 已发 200 的 INVITE 不能再被 CANCEL 取消，等待 ACK/BYE。
                if state.dialog and state.dialog.final_response_sent then return end
                local inv_headers = {}
                for k, v in pairs(inv.headers) do inv_headers[k] = v end
                inv_headers["to"] = ensure_to_has_tag(inv_headers["to"], inv.local_tag)
                net_send_on(netc, build_response(state, inv_headers, 487, "Request Terminated", nil, ""))
                if state.dialog then
                    finish_call(state.dialog, "peer_cancel")
                else
                    state.incoming_invite = nil
                    emit_call("ended", { reason = "peer_cancel", call_id = inv.headers["call-id"] })
                end
            end

            local function handle_message_request(req_headers, body)
                local local_tag = gen_token("tag")
                req_headers["to"] = ensure_to_has_tag(req_headers["to"], local_tag)
                net_send_on(netc, build_response(state, req_headers, 200, "OK", nil, ""))
                emit_message("rx", {
                    from = req_headers["from"],
                    call_id = req_headers["call-id"],
                    headers = req_headers,
                    text = body or "",
                    body = body or ""
                })
                log.info("sip", "message rx", #(body or ""))
            end

            local function handle_closing_request(dialog, method, headers)
                local response = dialog.invite_response
                local seq = cseq_number(headers["cseq"])
                local from_ok = header_tag_value(headers["from"]) == header_tag_value(dialog.from)
                local to_tag = header_tag_value(headers["to"])
                local dialog_tags = from_ok and to_tag == header_tag_value(dialog.to)
                local transaction_tags = from_ok and to_tag == response.request_to_tag
                local method_ok = cseq_method(headers["cseq"]) == method
                if method == "ACK" then
                    if method_ok and dialog_tags and seq == response.cseq and response.waiting_ack then
                        log.info("sip", "closing ACK", dialog.call_id, seq)
                        stop_invite_response(dialog)
                        start_hangup_timer(dialog)
                        send_dialog_bye(dialog)
                    end
                    return -- 无法匹配的 ACK 不应产生 SIP 响应。
                end
                if method_ok and transaction_tags and seq == response.cseq then
                    if method == "INVITE" then
                        net_send_on(netc, response.data)
                        return
                    elseif method == "CANCEL" then
                        local reply = copy_headers(headers)
                        reply["to"] = dialog.to
                        net_send_on(netc, build_response(state, reply, 200, "OK", nil, ""))
                        return
                    end
                end
                if method == "BYE" and method_ok and dialog_tags and seq then
                    if seq <= response.cseq then
                        net_send_on(netc, build_response(state, headers, 500, "Server Internal Error", nil, ""))
                    else
                        log.info("sip", "closing peer BYE", dialog.call_id, seq)
                        net_send_on(netc, build_response(state, headers, 200, "OK", nil, ""))
                        release_closing_dialog(dialog, "peer_bye")
                    end
                    return
                end
                net_send_on(netc, build_response(state, headers, 481, "Call/Transaction Does Not Exist", nil, ""))
            end

            local function handle_request_packet(method, req_uri, req_headers, body, rip, remote_port)
                local closing = state.closing_dialogs[req_headers["call-id"]]
                if closing then
                    handle_closing_request(closing, method, req_headers)
                    return
                end
                if method == "INVITE" then
                    handle_invite_request(req_headers, req_uri, body, rip, remote_port)
                elseif method == "ACK" then
                    handle_ack_request(req_headers)
                elseif method == "BYE" then
                    handle_bye_request(req_headers)
                elseif method == "CANCEL" then
                    handle_cancel_request(req_headers)
                elseif method == "MESSAGE" then
                    handle_message_request(req_headers, body)
                elseif method == "OPTIONS" then
                    -- 回应服务端发来的 OPTIONS 探活，避免被标记为不可达。
                    net_send_on(netc, build_response(state, req_headers, 200, "OK", {
                        {"Allow", "INVITE, ACK, CANCEL, BYE, OPTIONS, MESSAGE, INFO"},
                        {"Accept", "application/sdp"}
                    }, ""))
                else
                    net_send_on(netc, build_response(state, req_headers, 501, "Not Implemented", nil, ""))
                end
            end

            local function handle_register_response(code, response_reason, headers)
                -- 收到任何 REGISTER 响应都说明服务器已响应，先结束本次等待计时。
                stop_register_response_timer()
                state.last_register_response_code = code
                state.last_register_response_reason = response_reason
                state.last_register_response_headers = copy_headers(headers)
                if code == 200 then
                    local exp = headers["expires"]
                    if not exp then
                        local contact = headers["contact"]
                        if contact then
                            exp = contact:match("expires%s*=%s*(%d+)")
                        end
                    end
                    state.online = true
                    state.options_triggered_register = false

                    schedule_reregister(tonumber(exp) or state.expires)
                    if state.sip_transport == "udp" then
                        start_options_keepalive()
                    end
                    emit_register("ok", {
                        expires = tonumber(exp) or state.expires,
                        headers = headers
                    })
                    return
                end

                if code == 401 or code == 407 then
                    if state.auth_tried >= 1 then
                        log.error("sip", "reg auth failed")
                        emit_register("failed", {
                            reason = register_failure_reason(code),
                            source = "sip_response",
                            sip_code = code,
                            response_reason = response_reason,
                            headers = headers,
                            retrying = true
                        })
                        sys.publish(TOPIC_DISCONNECT)
                        return
                    end
                    local www_params = extract_auth_challenge(headers)
                    if not www_params then
                        log.error("sip", "reg no digest challenge")
                        emit_register("failed", {
                            reason = "missing_auth_challenge",
                            source = "sip_response",
                            sip_code = code,
                            response_reason = response_reason,
                            headers = headers,
                            retrying = true
                        })
                        sys.publish(TOPIC_DISCONNECT)
                        return
                    end
                    state.auth_tried = state.auth_tried + 1
                    send_register_with_auth(code, www_params)
                    emit_register("challenge", {
                        code = code,
                        auth = www_params
                    })
                    return
                end

                if code == 482 then
                    log.warn("sip", "reg 482 Request Merged, disconnect and retry")
                    emit_register("failed", {
                        reason = register_failure_reason(code),
                        source = "sip_response",
                        sip_code = code,
                        response_reason = response_reason,
                        headers = headers,
                        retrying = true
                    })
                    sys.publish(TOPIC_DISCONNECT)
                    return
                end
                if code == 404 then
                    log.warn("sip", "register returned 404, disconnect and retry")

                    emit_register("failed", {
                        reason = register_failure_reason(code),
                        source = "sip_response",
                        sip_code = code,
                        response_reason = response_reason,
                        headers = headers,
                        retrying = true
                    })

                    sys.publish(TOPIC_DISCONNECT)
                    return
                end
                if code and code >= 300 then
                    log.warn("sip", "register rejected", code, response_reason)
                    -- 清除“OPTIONS 404 已触发 REGISTER”的状态，
                    -- 使下次重新连接后可以再次执行恢复注册。
                    state.options_triggered_register = false
                    emit_register("failed", {
                        reason = register_failure_reason(code),
                        source = "sip_response",
                        sip_code = code,
                        response_reason = response_reason,
                        headers = headers,
                        retrying = false
                    })
                    return
                end
            end

            local function handle_invite_response(code, reason, headers, body, rip)
                if cseq_number(headers["cseq"]) ~= state.dialog.invite_cseq then return end
                local function handle_invite_auth_challenge()
                    if not state.dialog then
                        return
                    end

                    local ack_dialog = {
                        remote_uri = state.dialog.remote_uri,
                        from = state.dialog.from,
                        to = headers["to"] or state.dialog.to,
                        call_id = state.dialog.call_id,
                        invite_cseq = state.dialog.invite_cseq,
                        invite_branch = state.dialog.invite_branch
                    }

                    net_send_on(netc, build_ack_non2xx(state, ack_dialog))

                    return retry_transaction_auth(code, headers, {
                        tx = state.dialog,
                        method = "INVITE",
                        auth_failed_log = "invite auth failed",
                        no_challenge_log = "invite no digest challenge",
                        digest_failed_log = "invite digest failed",
                        before_digest = function(dialog)
                            dialog.invite_cseq = (dialog.invite_cseq or 1) + 1
                            dialog.cseq = dialog.invite_cseq
                            dialog.invite_branch = gen_token("br")
                        end,
                        send = function(digest)
                            net_send_on(netc, build_invite(state, state.dialog, digest))
                        end,
                        on_failed = function()
                            finish_call(state.dialog, "auth_failed", code, "failed")
                        end,
                        emit = function(retry_code)
                            emit_call("auth_retry", {
                                dialog = state.dialog,
                                code = retry_code
                            })
                        end
                    })
                end

                local function handle_invite_success()
                    local to_hdr = headers["to"]
                    if to_hdr then
                        state.dialog.to = to_hdr
                    end
                    -- UAC: 使用 200 OK 的 Contact 更新 remote_uri（RFC 3261 §12.1.2）
                    local remote_contact = contact_uri(headers["contact"])
                    if remote_contact then
                        state.dialog.remote_uri = remote_contact
                    end
                    -- UAC: 路由集 = 200 OK 中 Record-Route 的原序（RFC 3261 §12.1.2）
                    state.dialog.route_set = parse_route_set(headers["record-route"])
                    state.dialog.remote_ip = rip
                    state.dialog.remote_sdp_raw = body
                    state.dialog.remote_sdp = parse_sdp(body)
                    state.dialog.established = true
                    stop_call_timeout()
                    net_send_on(netc, build_ack(state, state.dialog))
                    if state.dialog.terminating then
                        -- CANCEL 与 200 交错：必须 ACK 后 BYE，不能重新启动媒体。
                        send_dialog_bye(state.dialog)
                        return
                    end
                    maybe_start_media(state.dialog, "outgoing_200")
                    log.info("sip", "call established (outgoing)")
                    emit_call("established", {
                        dialog = state.dialog
                    })
                end

                local function handle_invite_failure()
                    local to_hdr = headers["to"]
                    if to_hdr then
                        state.dialog.to = to_hdr
                    end
                    stop_call_timeout()
                    net_send_on(netc, build_ack_non2xx(state, state.dialog))
                    log.warn("sip", "call failed", code)
                    if state.dialog.terminating then
                        finish_call(state.dialog, "local_hangup", code)
                    else
                        finish_call(state.dialog, reason, code, "failed")
                    end
                end

                if state.dialog.terminating and code and code >= 300 then
                    handle_invite_failure()
                    return
                end
                if code == 401 or code == 407 then
                    handle_invite_auth_challenge()
                    return
                end

                if code == 200 then
                    handle_invite_success()
                    return
                end

                if code == 180 or code == 181 or code == 182 or code == 183 then
                    if state.dialog.terminating then return end
                    -- 处理 180 Ringing、181 Call Is Being Forwarded、182 Queued、183 Session Progress
                    log.info("sip", "invite provisional response", code, reason)
                    emit_call("ringing", {
                        dialog = state.dialog,
                        code = code,
                        reason = reason,
                        headers = headers
                    })
                    return
                end

                if code and code >= 300 then
                    handle_invite_failure()
                end
            end

            local function handle_dialog_teardown_response(code, method, headers)
                local dialog = state.dialog
                -- CANCEL 200 只确认 CANCEL 事务，INVITE 仍可能迟到 200/487。
                if method ~= "BYE" or not dialog.terminating or
                    cseq_number(headers["cseq"]) ~= dialog.bye_cseq then return end
                if code and code >= 200 then
                    -- 即使对端拒绝 BYE（如 500），本地也必须释放媒体和 dialog。
                    finish_call(dialog, "local_hangup", code)
                end
            end

            local function handle_message_response(code, reason, headers)
                if code == 200 or code == 202 then
                    local sent_message = state.msg_tx
                    emit_message("sent", {
                        message = sent_message,
                        to = state.msg_tx.to,
                        text = state.msg_tx.body,
                        body = state.msg_tx.body,
                        code = code
                    })
                    log.info("sip", "message sent ok", code)
                    state.msg_tx = nil
                    return
                end

                if code == 401 or code == 407 then
                    retry_transaction_auth(code, headers, {
                        tx = state.msg_tx,
                        method = "MESSAGE",
                        auth_failed_log = "message auth failed",
                        no_challenge_log = "message no digest challenge",
                        digest_failed_log = "message digest failed",
                        before_digest = function(message)
                            message.branch = gen_token("br")
                            message.cseq = (message.cseq or 1) + 1
                        end,
                        send = function(digest)
                            net_send_on(netc, build_message(state, state.msg_tx, digest))
                        end,
                        on_failed = function()
                            state.msg_tx = nil
                        end,
                        emit = function(retry_code)
                            emit_message("auth_retry", {
                                message = state.msg_tx,
                                code = retry_code
                            })
                        end
                    })
                    return
                end

                if code and code >= 300 then
                    log.warn("sip", "message failed", code)
                    local failed_message = state.msg_tx
                    state.msg_tx = nil
                    emit_message("failed", {
                        code = code,
                        reason = reason,
                        message = failed_message
                    })
                end
            end

            local function handle_dtmf_response(code, reason, headers)
                local tx = state.dtmf_tx
                if not tx then
                    return
                end
                if code and code >= 200 and code < 300 then
                    stop_dtmf_timer(tx)
                    state.dtmf_tx = nil
                    local sequence = state.dtmf_sequence
                    if sequence then sequence.last_code = code end
                    emit_dtmf("sent", {
                        digits = sequence and sequence.digits or "",
                        digit = tx.digit,
                        index = sequence and sequence.index or 0,
                        duration = tx.duration,
                        code = code
                    })
                    if sequence then
                        schedule_next_dtmf(sequence.interval)
                    end
                    return
                end
                if code == 401 or code == 407 then
                    retry_transaction_auth(code, headers, {
                        tx = tx,
                        method = "INFO",
                        auth_failed_log = "INFO DTMF auth failed",
                        no_challenge_log = "INFO DTMF no digest challenge",
                        digest_failed_log = "INFO DTMF digest failed",
                        before_digest = function(info_tx)
                            local dialog = state.dialog
                            if not dialog or not dialog.established then
                                fail_dtmf("dialog_not_established")
                                return
                            end
                            dialog.cseq = (dialog.cseq or info_tx.cseq) + 1
                            info_tx.cseq = dialog.cseq
                            info_tx.branch = gen_token("br")
                            start_dtmf_timeout(info_tx)
                        end,
                        send = function(digest)
                            if state.dtmf_tx and state.dialog then
                                net_send_on(netc, build_info(state, state.dialog, state.dtmf_tx, digest))
                            end
                        end,
                        on_failed = function()
                            fail_dtmf("auth_failed", code)
                        end
                    })
                    return
                end
                if code and code >= 300 then
                    log.warn("sip", "INFO DTMF failed", code, reason)
                    fail_dtmf(reason or "sip_error", code)
                end
            end

            local function handle_response_packet(code, reason, headers, body, rip)
                local call_id = headers["call-id"]
                local cseq = headers["cseq"]
                local cseq_m = cseq_method(cseq)
                local closing = state.closing_dialogs[call_id]
                if closing then
                    if cseq_m == "BYE" and closing.bye_cseq and cseq_number(cseq) == closing.bye_cseq and
                        header_tag_value(headers["from"]) == header_tag_value(closing.bye_from) and
                        header_tag_value(headers["to"]) == header_tag_value(closing.bye_to) and code and code >= 200 then
                        log.info("sip", "closing BYE response", call_id, code)
                        release_closing_dialog(closing, "bye_response")
                    end
                    return
                end
                if cseq_m == "OPTIONS" then
                    -- OPTIONS 响应：任意响应均视为保活成功，重置失败计数。
                    state.options_pending = false
                    state.options_fail_count = 0
                    if code == 404 and not state.options_triggered_register then
                        log.warn("sip", "OPTIONS returned 404, trigger REGISTER refresh")
                        -- 服务器可能因重启丢失注册信息，立即标记为未注册。
                        -- 这一行也很重要：REGISTER 响应超时定时器要求 online=false。
                        state.online = false
                        state.options_triggered_register = true
                        -- 通知上层注册已经失效。
                        -- sip_main 收到 failed 后会把 g_registered 设置为 false。
                        emit_register("failed", {
                            reason = "options_not_found",
                            source = "options_response",
                            sip_code = code,
                            response_reason = reason,
                            headers = headers,
                            retrying = true,
                            hint = "OPTIONS 返回404，服务器可能已丢失注册绑定，正在重新注册"
                        })

                        state.branch = gen_token("br")
                        state.cseq = state.cseq + 1
                        state.auth_tried = 0
                        state.last_www = nil
                        state.register_attempts = 1

                        state.last_register_response_code = nil
                        state.last_register_response_reason = nil
                        state.last_register_response_headers = nil
                        state.register_attempts = 1
                        
                        net_send(build_register(state, nil))
                        start_register_response_timer()
                    end
                return

                elseif call_id and call_id:find(state.call_id, 1, true) then
                    handle_register_response(code, reason, headers)
                elseif state.dialog and state.dialog.direction == "out" and call_id == state.dialog.call_id and cseq_m == "INVITE" then
                    handle_invite_response(code, reason, headers, body, rip)
                elseif state.dialog and call_id == state.dialog.call_id and (cseq_m == "BYE" or cseq_m == "CANCEL") then
                    handle_dialog_teardown_response(code, cseq_m, headers)
                elseif state.msg_tx and call_id == state.msg_tx.call_id and cseq_m == "MESSAGE" then
                    handle_message_response(code, reason, headers)
                elseif state.dtmf_tx and call_id == state.dtmf_tx.call_id and cseq_m == "INFO" and
                    cseq_number(cseq) == state.dtmf_tx.cseq then
                    handle_dtmf_response(code, reason, headers)
                end
            end

            -- 统一处理一份已经拆好的 SIP 报文。
            local function process_packet(head, body, rip, remote_port)
                local method, req_uri = parse_request_line(head)
                if method then
                    local req_headers = parse_headers(head)
                    log.info("sip", "req", method, "from", rip, remote_port or 0,
                        "call-id", req_headers["call-id"] or "", "cseq", req_headers["cseq"] or "")
                    handle_request_packet(method, req_uri, req_headers, body, rip, remote_port)
                    return
                end

                local code, reason = parse_status(head)
                log.info("sip", "resp", code or "?", reason or "?", "from", rip, remote_port or 0)
                if state.debug_sip_response then
                    log.info("sip", "response raw\r\n" .. head .. "\r\n\r\n" .. (body or ""))
                end
                local headers = parse_headers(head)
                handle_response_packet(code, reason, headers, body, rip)
            end

            while true do
                local succ, data_len, remote_ip, remote_port = socket.rx(netc, rxbuf)
                if not succ then
                    log.warn("sip", "rx failed")
                    emit_event(SIP_EVENT.ERROR, "rx_failed", {})
                    sys.publish(TOPIC_DISCONNECT)
                    return
                end
                if not data_len or data_len <= 0 then
                    break
                end

                local resp = rxbuf:toStr(0, rxbuf:used())
                rxbuf:del()

                if state.sip_transport == "TCP" then
                    -- TCP 是字节流：先拼到流缓冲里，再循环拆出完整 SIP 报文。
                    state.tcp_stream = state.tcp_stream .. resp
                    while true do
                        local head, body
                        head, body, state.tcp_stream = sip_pop_stream_message(state.tcp_stream)
                        if not head then
                            break
                        end
                        process_packet(head, body, state.sip_server_addr, state.sip_server_port)
                    end
                else
                    -- UDP 下一般一包就是一份 SIP 报文。
                    local rip = decode_udp_remote_ip(remote_ip) or "?"
                    local head, body = split_sip_message(resp)
                    process_packet(head, body, rip, remote_port)
                end
            end

            -- 继续等待下一次 EVENT
            return
        end

        if event == socket.TX_OK then
            -- 发完后切换到接收状态
            return
        end

        if event == socket.CLOSED then
            clear_connection(netc)
            sys.publish(TOPIC_DISCONNECT)
            return
        end
    end

    -- 维护可用网卡表
    local ready_adapters = {}

    local function ip_ready_handler(ip, adapter)
        log.info("sip", "IP_READY", adapter)
        ready_adapters[adapter] = true
    end

    local function ip_lose_handler(adapter)
        log.info("sip", "IP_LOSE", adapter)
        ready_adapters[adapter] = nil
        local current_adapter = (state.dialog or state.incoming_invite or next(state.closing_dialogs)) and state.locked_adapter or socket.dft()
        if adapter == current_adapter then
            emit_event(SIP_EVENT.ERROR, "network_changed", {
                reason = "current_adapter_lost",
                adapter = adapter
            })
            if state.netc then
                sys.publish(TOPIC_DISCONNECT)
            end
        end
    end

    -- 初始化已就绪网卡表（补偿订阅前已发出的 IP_READY）
    for _, adapter_id in ipairs({socket.LWIP_GP, socket.LWIP_STA, socket.LWIP_ETH, socket.LWIP_USER1, socket.LWIP_GP_GW}) do
        if socket.adapter(adapter_id) then
            ready_adapters[adapter_id] = true
        end
    end

    sys.subscribe("IP_READY", ip_ready_handler)
    sys.subscribe("IP_LOSE", ip_lose_handler)

    -- 订阅网络状态变化，非通话时若默认网卡变化则主动触发重连
    local function network_status_handler(net_type, adapter)
        if state.dialog or state.incoming_invite or next(state.closing_dialogs) then
            return
        end
        if adapter ~= state.current_adapter and state.netc then
            log.info("sip", "default network changed from", state.current_adapter, "to", adapter, ", trigger reconnect")
            sys.publish(TOPIC_DISCONNECT)
        end
    end
    sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS", network_status_handler)

    -- 外层重连循环：只要未显式 stop，断线后就会等待 3 秒重连。
    while true do
        local adapter_to_use
        if state.dialog or state.incoming_invite or next(state.closing_dialogs) then
            -- 来电/拨号/通话中：锁定为建立 SIP 时的网卡
            adapter_to_use = state.locked_adapter
        else
            -- 空闲/注册中：跟随当前默认网卡
            adapter_to_use = socket.dft()
        end

        state.current_adapter = adapter_to_use

        if not ready_adapters[adapter_to_use] then
            log.info("sip", "adapter not ready, waiting for IP_READY:", adapter_to_use)
            sys.wait(1000)
            if g_stop then
                break
            end
        else
            -- 非通话状态下重新注册时，让后续RTP媒体与新的SIP信令网卡保持一致。
            -- 通话中仍保持原来的locked_adapter，避免切换承载中的媒体网卡。
            if not state.dialog and not state.incoming_invite and not next(state.closing_dialogs) then
                state.locked_adapter = adapter_to_use
            end
            log.info("sip", "creating socket with adapter:", adapter_to_use, "locked_adapter:", state.locked_adapter)
            -- The C callback receives lightuserdata; compare the captured full handle.
            local netc
            netc = socket.create(adapter_to_use, function(_, event, param)
                netCB(netc, event, param)
            end)
            state.netc = netc
            socket.config(netc, state.local_port, (state.sip_transport == "udp"))

            local succ = socket.connect(netc, state.sip_server_addr, state.sip_server_port)
            if not succ then
                log.warn("sip", "connect start failed, retry")
                state.connect_fail_count = state.connect_fail_count + 1
                if state.connect_fail_count >= state.connect_max_attempts then
                    emit_register("failed", {
                        reason = "connect_start_failed",
                        source = "network",
                        attempts = state.connect_fail_count,
                        server = state.sip_server_addr,
                        port = state.sip_server_port,
                        transport = state.sip_transport,
                        retrying = true,
                        hint = "无法启动SIP服务器连接，请检查服务器地址、端口、网络和可用网卡"
                    })
                    state.connect_fail_count = 0
                end
                clear_connection(netc)
                socket.close(netc)
                socket.release(netc)
                sys.wait(3000)
            else
                sys.waitUntil(TOPIC_DISCONNECT)
                clear_connection(netc)
                socket.close(netc)
                socket.release(netc)
                if g_stop then
                    break
                end
                sys.wait(3000)
            end
        end
    end

    sys.unsubscribe(TOPIC_CMD, command_handler)
    sys.unsubscribe("IP_READY", ip_ready_handler)
    sys.unsubscribe("IP_LOSE", ip_lose_handler)
    sys.unsubscribe("EXLIB_NETDRV_NETWORK_STATUS", network_status_handler)

    emit_lifecycle("stopped", {})
end

-- ==================== 异步回调式对外 API（单实例） ====================

--[[
启动 SIP 客户端。
@api exsipclient.start(opts)
@table opts SIP 启动参数表，至少需要 server、port、domain、user、transport
@return boolean 参数合法并成功启动后台任务返回 true，否则返回 false
@usage
exsipclient.start({
    server = "192.168.1.10",
    port = 5060,
    domain = "example.com",
    user = "1001",
    password = "123456",
    transport = "tcp",
    local_port = 5062,
    expires = 600,
    rtp_port = 40000,
    codecs = {"PCMU", "PCMA"},
    ptime = 20,
    call_timeout = 30,
    debug_sip_response = false,
    event_callback = function(event, action, payload)
        -- event 可取 lifecycle、register、call、media、message、error
        -- lifecycle: online、offline、stopped
        -- register: ok、challenge
        -- call: incoming、established、ended、failed、dial_rejected、auth_retry
        -- media: offer、ready、stop
        -- message: rx、sent、auth_retry、failed
        -- error: net、rx_failed
    end
})
]]
function M.start(opts)
    
    if g_started then
        return true
    end
    
    -- 在这里要判断基础的参数合法性，如果不合法就直接返回 false，不启动后台 task。
    if not opts or type(opts) ~= "table" then
        return false
    end
if type(opts.event_callback) == "function" then
        g_callback = opts.event_callback
    end

    if (not opts.sip_server_addr) or (not opts.sip_server_port) or (not opts.sip_domain) or (not opts.sip_username) then
        log.error("sip", "invalid SIP config: required parameter missing")
        emit_register("failed", {
            reason = "invalid_config",
            source = "config",
            retrying = false,
            hint = "缺少SIP服务器地址、端口、域或用户名"
        })
        return false
    end

    local address_type = classify_server_address(opts.sip_server_addr)
    if not address_type then
        log.error("sip", "invalid SIP server address", opts.sip_server_addr)
        emit_register("failed", {
            reason = "invalid_server_address",
            source = "config",
            server = opts.sip_server_addr,
            port = opts.sip_server_port,
            retrying = false,
            hint = "SIP服务器地址格式错误，请填写合法的IPv4、IPv6地址或域名"
        })
        return false
    end

    local server_port = tonumber(opts.sip_server_port)
    if not server_port or server_port < 1 or server_port > 65535 or server_port % 1 ~= 0 then
        log.error("sip", "invalid SIP server port", opts.sip_server_port)
        emit_register("failed", {
            reason = "invalid_server_port",
            source = "config",
            server = opts.sip_server_addr,
            port = opts.sip_server_port,
            retrying = false,
            hint = "SIP服务器端口必须是1到65535之间的整数"
        })
        return false
    end
    opts.sip_server_port = server_port

    if not opts.sip_transport  or (opts.sip_transport ~= "udp" and opts.sip_transport ~= "tcp" and opts.sip_transport ~= "tls") then
        log.error("sip", "invalid SIP transport", opts.sip_transport)
        emit_register("failed", {
            reason = "invalid_transport",
            source = "config",
            transport = opts.sip_transport,
            retrying = false,
            hint = "SIP传输层必须是udp、tcp或tls"
        })
        return false
    end
    

    g_stop = false
    g_started = true

    -- 真正的 SIP 逻辑在后台 task 中运行。
    -- 这样 `start()` 本身保持非阻塞，适合在 LuatOS 主脚本初始化阶段直接调用。
    sys.taskInit(function()
        sip_task(opts)
        g_started = false
    end)
    return true
end

--[[
停止 SIP 客户端。
@api exsipclient.stop()
@return nil 无返回值
@usage
exsipclient.stop()
]]
function M.stop()
    -- 这里不直接强杀 task，而是通过发布断开事件让主循环自行收尾退出。
    g_stop = true
    sys.publish(TOPIC_DISCONNECT)
end

--[[
注册统一事件回调。
@api exsipclient.on(fn)
@function fn 事件回调函数，参数格式为 function(event, action, payload)
@return boolean 设置成功返回 true，参数不是函数时返回 false
@usage
exsipclient.on(function(event, action, payload)
    log.info("sip", event, action)
end)
]]
function M.on(fn)
    if type(fn) ~= "function" then
        return false
    end
    g_callback = fn
    return true
end

--[[
发起外呼。
@api exsipclient.call(target, from_number)
@string target 目标号码或 sip URI，例如 "1002" 或 "sip:1002@example.com"
@string from_number 可选，本次外呼写入 From 显示名的主叫号码
@return nil 无返回值
@usage
exsipclient.call("1002", "13800138000")
]]
function M.call(target, from_number)
    -- 通过 topic 把命令投递到 SIP 主任务中串行执行，避免跨 task 直接操作内部状态。
    sys.publish(TOPIC_CMD, "call", {
        target = target,
        from_number = from_number
    })
end

--[[
接听当前缓存的来电。
@api exsipclient.answer(call_id)
@string call_id 可选，仅应答指定通话，忽略旧通话的迟到命令
@return nil 无返回值
@usage
exsipclient.answer()
]]
function M.answer(call_id)
    sys.publish(TOPIC_CMD, "answer", { call_id = call_id })
end

--[[
发送 183 Session Progress + SDP，启动来电早期媒体。
@api exsipclient.progress(call_id)
@string call_id 可选，仅处理指定通话
@return nil 无返回值
@usage
exsipclient.progress()
]]
function M.progress(call_id)
    sys.publish(TOPIC_CMD, "progress", { call_id = call_id })
end

--[[
挂断当前通话，或拒绝当前未接来电。
@api exsipclient.hangup(force, call_id)
@boolean force 可选，true 强制清理本地会话；首参为字符串时按 call_id 处理
@string call_id 可选，仅挂断指定通话，兼容 hangup(call_id)
@return nil 无返回值
@usage
-- 等待来电 ACK 时挂断会立即上报 ended；旧信令在后台等待 ACK/BYE，不再触发业务事件。
exsipclient.hangup()
]]
function M.hangup(force, call_id)
    if type(force) == "string" then
        call_id, force = force, false
    end
    sys.publish(TOPIC_CMD, "hangup", { force = force == true, call_id = call_id })
end

--[[
使用指定 SIP 失败码结束尚未最终接听的来电。
@api exsipclient.fail(code, reason, call_id)
@number code SIP 状态码，默认 486
@string reason 原因短语
@string call_id 可选，仅拒绝指定通话
@return nil 无返回值
@usage
exsipclient.fail(480, "Temporarily Unavailable")
]]
function M.fail(code, reason, call_id)
    sys.publish(TOPIC_CMD, "fail", {
        code = code,
        reason = reason,
        call_id = call_id
    })
end

--[[
发送一条 SIP MESSAGE。
@api exsipclient.message(target, text)
@string target 目标号码或 sip URI，例如 "1002" 或 "sip:1002@example.com"
@string text 要发送的消息文本
@return nil 无返回值
@usage
exsipclient.message("1002", "hello")
]]
function M.message(target, text)
    -- 发起一条 SIP MESSAGE。
    sys.publish(TOPIC_CMD, "message", {
        target = target,
        text = text
    })
end

--[[
发送一串 SIP INFO DTMF。命令会投递到 SIP task 中，在当前已建立 dialog
内逐位发送；每一位必须收到 2xx 后才会发送下一位。
@api exsipclient.dtmf(digits[, duration_ms[, interval_ms] ])
@string digits DTMF 字符串
@number duration_ms 单位毫秒，默认 160
@number interval_ms 位间隔，单位毫秒，默认 100
]]
function M.dtmf(digits, duration_ms, interval_ms)
    sys.publish(TOPIC_CMD, "dtmf", {
        digits = digits,
        duration = duration_ms,
        interval = interval_ms
    })
end

return M
