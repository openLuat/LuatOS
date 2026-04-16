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

local function emit_call(action, payload)
    emit_domain_event(SIP_EVENT.CALL, action, payload)
end

local function emit_media(action, payload)
    emit_domain_event(SIP_EVENT.MEDIA, action, payload)
end

local function emit_message(action, payload)
    emit_domain_event(SIP_EVENT.MESSAGE, action, payload)
end


-- 本地监听端口（0 表示随机端口；建议固定，方便服务器回包）
local LOCAL_PORT = 5062
-- 注册有效期（秒）
local REGISTER_EXPIRES = 600

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
local function build_ack(state, dialog)
    return build_request({
        method = "ACK",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = gen_token("br")
        },
        headers = {{"From", dialog.from}, {"To", dialog.to}, {"Call-ID", dialog.call_id},
                   {"CSeq", string.format("%d ACK", dialog.invite_cseq)}}
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
    return build_request({
        method = "BYE",
        uri = dialog.remote_uri,
        via_ctx = {
            transport = state.sip_transport,
            local_ip = state.local_ip,
            local_port = state.local_port,
            branch = gen_token("br")
        },
        headers = {{"From", dialog.from}, {"To", dialog.to}, {"Call-ID", dialog.call_id},
                   {"CSeq", string.format("%d BYE", dialog.cseq)}}
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
    local sdp = dialog.local_sdp or build_sdp(state, "sendrecv")
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

-- SIP 主任务。
--
-- 职责：
-- 1. 管理 REGISTER 生命周期与续租
-- 2. 管理当前通话对话、来电缓存与 MESSAGE 事务
-- 3. 处理 socket 生命周期与自动重连
-- 4. 在正确时机把媒体协商结果通过回调抛给外部媒体层
local function sip_task(opts)
    local rxbuf = zbuff.create(2048)
    log.info("JQsip", "sip_task start")
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
        netc = nil,

        online = false,
        last_www = nil,

        -- 当前通话状态：
        -- - `dialog`: 已发起或已接听的通话对话
        -- - `incoming_invite`: 尚未接听的来电缓存
        dialog = nil, -- 当前通话（入/出）
        incoming_invite = nil,

        -- 当前正在进行的 MESSAGE 事务。
        msg_tx = nil, -- 正在发送的 MESSAGE

        -- 媒体协商结果缓存。
        -- SIP 层不会直接收发 RTP，但会把最终协商好的参数保存于此，
        -- 然后通过 event_callback("media", "ready", payload) 交给外部媒体模块。
        media = {
            local_rtp_port = tonumber(opts.rtp_port) or 40000,
            codecs = normalize_codec_list(opts.codecs or {"PCMU", "PCMA"}),
            ptime = tonumber(opts.ptime) or 20,
            active = false,
            session = nil
        }
    }

    -- 当本地 SDP 和远端 SDP 都齐备后，整理出媒体会话描述并通知上层。
    -- SIP 层只负责“协商结果”，不直接创建 RTP socket 或音频线程。
    local function maybe_start_media(dialog, source)
        if not dialog then
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
            local_rtp_port = state.media.local_rtp_port,
            local_codecs = state.media.codecs,
            local_sdp = dialog.local_sdp,
            ptime = state.media.ptime,
            source = source
        })
        if not session then
            log.warn("sip", "no common media codec")
            return
        end
        log.info("JQsip", "media session ready", session)
        -- 通知外部媒体层启动当前会话。

        state.media.active = true
        state.media.session = session
        emit_media("ready", session)
    end

    -- 通知外部媒体层停止当前会话。
    local function stop_media(reason)
        if state.media.active then
            emit_media("stop", {
                reason = reason,
                session = state.media.session
            })
        end
        state.media.active = false
        state.media.session = nil
    end

    -- 统一发送接口：写 socket 后调用 `socket.wait()`，尽量把发送与状态切换串起来。
    local function net_send_on(netc, data)
        if not netc or not data then
            return
        end
        socket.tx(netc, data)
        socket.wait(netc)
    end

    local function net_send(data)
        net_send_on(state.netc, data)
    end

    -- 停止注册续租定时器。
    local function stop_reg_timer()
        if state.reg_timer then
            sys.timerStop(state.reg_timer)
            state.reg_timer = nil
        end
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
    end

    -- 发起外呼。
    -- 这里只发送 INVITE + SDP offer，媒体要等 200 OK 后再启动。
    local function start_outgoing_call(target)
        if not state.online or not state.netc then
            log.warn("sip", "not online")
            return
        end
        if state.dialog then
            log.warn("sip", "busy")
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
        local from_to = string.format("<sip:%s@%s>", state.sip_username, state.sip_domain)
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
            local_sdp = build_sdp(state, "sendrecv")
        }
        state.dialog = dialog

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

        local dialog = {
            direction = "in",
            call_id = inv.headers["call-id"],
            from = inv.headers["from"],
            to = ensure_to_has_tag(inv.headers["to"], inv.local_tag),
            remote_uri = inv.uri,
            remote_ip = inv.remote_ip,
            invite_cseq = cseq_number(inv.headers["cseq"]) or 1,
            established = false,
            cseq = cseq_number(inv.headers["cseq"]) or 1,
            remote_sdp = inv.remote_sdp,
            remote_sdp_raw = inv.body
        }
        state.dialog = dialog

        local headers = {}
        local req_headers = {}
        for k, v in pairs(inv.headers) do
            req_headers[k] = v
        end
        req_headers["to"] = dialog.to

        -- 来电接听时，本端在 200 OK 中带回自己的 SDP answer。
        local body = build_sdp(state, "sendrecv")
        dialog.local_sdp = body
        local resp = build_response(state, req_headers, 200, "OK", headers, body)
        log.info("sip", "answer 200 OK")
        net_send(resp)
    end

    -- 挂断统一入口：
    -- - 来电未接：486 Busy Here
    -- - 外呼未接通：CANCEL
    -- - 已接通：BYE
    local function hangup_call()
        if not state.netc then
            return
        end
        if state.incoming_invite and not state.dialog then
            -- 来电未接，直接拒绝
            local inv = state.incoming_invite
            local req_headers = {}
            for k, v in pairs(inv.headers) do
                req_headers[k] = v
            end
            req_headers["to"] = ensure_to_has_tag(inv.headers["to"], inv.local_tag)
            local resp = build_response(state, req_headers, 486, "Busy Here", nil, "")
            log.info("sip", "reject incoming")
            net_send(resp)
            state.incoming_invite = nil
            return
        end

        local dialog = state.dialog
        if not dialog then
            log.warn("sip", "no dialog")
            return
        end

        if dialog.direction == "out" and not dialog.established then
            -- 外呼未接通：CANCEL
            local cancel = build_cancel(state, dialog)
            log.info("sip", "send CANCEL")
            net_send(cancel)
            return
        end

        -- 已建立：BYE
        local bye = build_bye(state, dialog)
        log.info("sip", "send BYE")
        net_send(bye)
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

    -- 订阅外部命令（call/answer/hangup/message）。
    -- 外部 API 只负责 `sys.publish()`，真正执行统一留在 SIP task 内。
    sys.subscribe(TOPIC_CMD, function(action, arg)
        log.info("sip", "cmd", action, arg or "")
        if action == "call" then
            start_outgoing_call(arg)
        elseif action == "answer" then
            answer_incoming()
        elseif action == "hangup" then
            hangup_call()
        elseif action == "message" and type(arg) == "table" then
            start_send_message(arg.target, arg.text)
        end
    end)

    -- socket 回调：整个 SIP 信令收发与状态推进的入口。
    local function netCB(netc, event, param)
        if param ~= 0 then
            log.warn("sip", "net error", event, param)
            stop_reg_timer()
            emit_event(SIP_EVENT.ERROR, "net", {
                event = event,
                param = param
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
            -- 尝试获取本地IP填Contact
            local ip = socket.localIP()
            if type(ip) == "string" and #ip > 0 then
                state.local_ip = ip
            end

            -- 每次重新连上 SIP 服务器，都把 REGISTER 事务状态重置到首发状态。
            state.branch = gen_token("br")
            state.cseq = 1
            state.auth_tried = 0

            local req = build_register(state, nil)
            log.info("sip", "send REGISTER", state.sip_server_addr, state.sip_server_port)
            net_send_on(netc, req)
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
                local local_tag = gen_token("tag")
                local to_hdr = ensure_to_has_tag(req_headers["to"], local_tag)
                req_headers["to"] = to_hdr
                state.incoming_invite = {
                    headers = req_headers,
                    uri = req_uri,
                    body = body,
                    remote_sdp = parse_sdp(body),
                    remote_ip = rip,
                    remote_port = remote_port,
                    local_tag = local_tag
                }
                net_send_on(netc, build_response(state, req_headers, 100, "Trying", nil, ""))
                net_send_on(netc, build_response(state, req_headers, 180, "Ringing", nil, ""))
                emit_call("incoming", {
                    from = req_headers["from"],
                    call_id = req_headers["call-id"],
                    uri = req_uri,
                    headers = req_headers,
                    body = body,
                    remote_sdp = state.incoming_invite.remote_sdp
                })
                emit_media("offer", {
                    call_id = req_headers["call-id"],
                    from = req_headers["from"],
                    sdp = state.incoming_invite.remote_sdp,
                    raw_sdp = body
                })
            end

            local function handle_ack_request(req_headers)
                if state.dialog and state.dialog.direction == "in" and state.dialog.call_id == req_headers["call-id"] then
                    state.dialog.established = true
                    state.incoming_invite = nil
                    maybe_start_media(state.dialog, "incoming_ack")
                    log.info("sip", "call established (incoming)")
                    emit_call("established", {
                        dialog = state.dialog
                    })
                end
            end

            local function handle_bye_request(req_headers)
                local to_hdr = req_headers["to"]
                if state.dialog and state.dialog.call_id == req_headers["call-id"] then
                    to_hdr = state.dialog.to
                end
                req_headers["to"] = to_hdr
                net_send_on(netc, build_response(state, req_headers, 200, "OK", nil, ""))
                local ended_dialog = state.dialog
                stop_media("peer_hangup")
                state.dialog = nil
                state.incoming_invite = nil
                log.info("sip", "peer hung up")
                emit_call("ended", {
                    reason = "peer_hangup",
                    dialog = ended_dialog
                })
            end

            local function handle_cancel_request(req_headers)
                net_send_on(netc, build_response(state, req_headers, 200, "OK", nil, ""))
                if state.incoming_invite and state.incoming_invite.headers and state.incoming_invite.headers["call-id"] ==
                    req_headers["call-id"] then
                    local inv_headers = {}
                    for k, v in pairs(state.incoming_invite.headers) do
                        inv_headers[k] = v
                    end
                    inv_headers["to"] = ensure_to_has_tag(inv_headers["to"], state.incoming_invite.local_tag)
                    net_send_on(netc, build_response(state, inv_headers, 487, "Request Terminated", nil, ""))
                else
                    net_send_on(netc,
                        build_response(state, req_headers, 481, "Call/Transaction Does Not Exist", nil, ""))
                end
                state.incoming_invite = nil
                stop_media("peer_cancel")
                state.dialog = nil
                log.info("sip", "incoming canceled")
                emit_call("ended", {
                    reason = "peer_cancel"
                })
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

            local function handle_request_packet(method, req_uri, req_headers, body, rip, remote_port)
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
                else
                    net_send_on(netc, build_response(state, req_headers, 501, "Not Implemented", nil, ""))
                end
            end

            local function handle_register_response(code, headers)
                if code == 200 then
                    local exp = headers["expires"]
                    if not exp then
                        local contact = headers["contact"]
                        if contact then
                            exp = contact:match("expires%s*=%s*(%d+)")
                        end
                    end
                    state.online = true
                    schedule_reregister(tonumber(exp) or state.expires)
                    emit_register("ok", {
                        expires = tonumber(exp) or state.expires,
                        headers = headers
                    })
                    return
                end

                if code == 401 or code == 407 then
                    if state.auth_tried >= 1 then
                        log.error("sip", "reg auth failed")
                        sys.publish(TOPIC_DISCONNECT)
                        return
                    end
                    local www_params = extract_auth_challenge(headers)
                    if not www_params then
                        log.error("sip", "reg no digest challenge")
                        sys.publish(TOPIC_DISCONNECT)
                        return
                    end
                    state.auth_tried = state.auth_tried + 1
                    send_register_with_auth(code, www_params)
                    emit_register("challenge", {
                        code = code,
                        auth = www_params
                    })
                end
            end

            local function handle_invite_response(code, reason, headers, body, rip)
                local function handle_invite_auth_challenge()
                    return retry_transaction_auth(code, headers, {
                        tx = state.dialog,
                        method = "INVITE",
                        auth_failed_log = "invite auth failed",
                        no_challenge_log = "invite no digest challenge",
                        digest_failed_log = "invite digest failed",
                        before_digest = function(dialog)
                            dialog.invite_cseq = (dialog.invite_cseq or 1) + 1
                            dialog.invite_branch = gen_token("br")
                        end,
                        send = function(digest)
                            net_send_on(netc, build_invite(state, state.dialog, digest))
                        end,
                        on_failed = function()
                            state.dialog = nil
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
                    state.dialog.remote_ip = rip
                    state.dialog.remote_sdp_raw = body
                    state.dialog.remote_sdp = parse_sdp(body)
                    state.dialog.established = true
                    net_send_on(netc, build_ack(state, state.dialog))
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
                    net_send_on(netc, build_ack_non2xx(state, state.dialog))
                    log.warn("sip", "call failed", code)
                    stop_media("call_failed")
                    local failed_dialog = state.dialog
                    state.dialog = nil
                    emit_call("failed", {
                        code = code,
                        reason = reason,
                        dialog = failed_dialog
                    })
                end

                if code == 401 or code == 407 then
                    handle_invite_auth_challenge()
                    return
                end

                if code == 200 then
                    handle_invite_success()
                    return
                end

                if code and code >= 300 then
                    handle_invite_failure()
                end
            end

            local function handle_dialog_teardown_response(code)
                if code == 200 then
                    stop_media("local_hangup")
                    local ended_dialog = state.dialog
                    state.dialog = nil
                    state.incoming_invite = nil
                    log.info("sip", "call cleared")
                    emit_call("ended", {
                        reason = "local_hangup",
                        dialog = ended_dialog
                    })
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

            local function handle_response_packet(code, reason, headers, body, rip)
                local call_id = headers["call-id"]
                local cseq = headers["cseq"]
                local cseq_m = cseq_method(cseq)

                if call_id and call_id:find(state.call_id, 1, true) then
                    handle_register_response(code, headers)
                elseif state.dialog and state.dialog.direction == "out" and call_id == state.dialog.call_id and cseq_m ==
                    "INVITE" then
                    handle_invite_response(code, reason, headers, body, rip)
                elseif state.dialog and call_id == state.dialog.call_id and (cseq_m == "BYE" or cseq_m == "CANCEL") then
                    handle_dialog_teardown_response(code)
                elseif state.msg_tx and call_id == state.msg_tx.call_id and cseq_m == "MESSAGE" then
                    handle_message_response(code, reason, headers)
                end
            end

            -- 统一处理一份已经拆好的 SIP 报文。
            local function process_packet(head, body, rip, remote_port)
                local method, req_uri = parse_request_line(head)
                if method then
                    local req_headers = parse_headers(head)
                    log.info("sip", "req", method, "from", rip, remote_port or 0)
                    handle_request_packet(method, req_uri, req_headers, body, rip, remote_port)
                    return
                end

                local code, reason = parse_status(head)
                log.info("sip", "resp", code or "?", reason or "?", "from", rip, remote_port or 0)
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
            -- CLOSED 表示当前连接生命周期结束：
            -- - 停止续租
            -- - 标记离线
            -- - 停止媒体
            -- - 清理通话与消息事务状态
            stop_reg_timer()
            state.online = false
            stop_media("socket_closed")
            state.dialog = nil
            state.incoming_invite = nil
            state.msg_tx = nil
            sys.publish(TOPIC_DISCONNECT)
            emit_lifecycle("offline", {
                reason = "socket_closed"
            })
            return
        end
    end

    -- 外层重连循环：只要未显式 stop，断线后就会等待 3 秒重连。
    while true do
        local netc = socket.create(opts.adapter, netCB)
        state.netc = netc
        socket.config(netc, state.local_port, (state.sip_transport == "udp"))

        local succ = socket.connect(netc, state.sip_server_addr, state.sip_server_port)
        if not succ then
            log.warn("sip", "connect start failed, retry")
            socket.close(netc)
            socket.release(netc)
            sys.wait(3000)
        else
            sys.waitUntil(TOPIC_DISCONNECT)
            stop_reg_timer()
            socket.close(netc)
            socket.release(netc)
            state.netc = nil
            if g_stop then
                break
            end
            sys.wait(3000)
        end
    end

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
    event_callback = function(event, action, payload)
        -- event 可取 lifecycle、register、call、media、message、error
        -- lifecycle: online、offline、stopped
        -- register: ok、challenge
        -- call: incoming、established、ended、failed、auth_retry
        -- media: offer、ready、stop
        -- message: rx、sent、auth_retry、failed
        -- error: net、rx_failed
    end
})
]]
function M.start(opts)
    
    log.info("JQsip", "starting with opts!!!!!!!!!!!!!!!!!!!!")
    if g_started then
        return true
    end
    
    log.info("JQsip", "starting with opts",g_started)
    -- 在这里要判断基础的参数合法性，如果不合法就直接返回 false，不启动后台 task。
    if not opts or type(opts) ~= "table" then
        return false
    end

    log.info("JQsip", "starting with opts", type(opts))

    if (not opts.sip_server_addr) or (not opts.sip_server_port) or (not opts.sip_domain) or (not opts.sip_username) then
        return false
    end
    
    log.info("JQsip", "starting with opts", opts.sip_server_addr, opts.sip_server_port, opts.sip_domain, opts.sip_username)

    if not opts.sip_transport  or (opts.sip_transport ~= "udp" and opts.sip_transport ~= "tcp" and opts.sip_transport ~= "tls") then
        return false
    end

    log.info("JQsip", "starting with opts", opts.sip_transport)

    if type(opts.event_callback) == "function" then
        g_callback = opts.event_callback
    end
    log.info("JQsip", "event callback set", type(g_callback))
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
@api exsipclient.call(target)
@string target 目标号码或 sip URI，例如 "1002" 或 "sip:1002@example.com"
@return nil 无返回值
@usage
exsipclient.call("1002")
]]
function M.call(target)
    -- 通过 topic 把命令投递到 SIP 主任务中串行执行，避免跨 task 直接操作内部状态。
    sys.publish(TOPIC_CMD, "call", target)
end

--[[
接听当前缓存的来电。
@api exsipclient.answer()
@return nil 无返回值
@usage
exsipclient.answer()
]]
function M.answer()
    -- 接听最近一次缓存的来电 INVITE。
    sys.publish(TOPIC_CMD, "answer")
end

--[[
挂断当前通话，或拒绝当前未接来电。
@api exsipclient.hangup()
@return nil 无返回值
@usage
exsipclient.hangup()
]]
function M.hangup()
    -- 挂断当前通话，或拒绝当前未接来电。
    sys.publish(TOPIC_CMD, "hangup")
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
return M
