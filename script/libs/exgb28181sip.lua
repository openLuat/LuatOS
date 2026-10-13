--[[
@module exgb28181sip
@summary GB28181 设备端的 SIP 报文构造与切包 —— 复用生态的 exsipproto，接口与被它取代的 C 绑定同形。

为什么要单独一层：GB28181 的头顺序与字段是**逐字节**和真实平台联调出来的；而 exsipproto 的
build_request / build_response 会把 Contact / User-Agent / Content-Type 放在它自己定的位置。

本模块的解法：**把全部头按 GB 的顺序塞进 ctx.headers[]，并传 max_forwards=false 抑制内置头** ——
于是头顺序完全由本模块决定，同时仍然复用 exsipproto 的起始行与 Content-Length 计算（最易错的两处）。
Via 也只在**一处**生成（`branch_prefix=""` + `rport_first=true`，与 C 的 format_via 逐字符一致）。

@usage
local sip = require "exgb28181sip"
local text, err = sip.build({ method = "REGISTER", uri = "sip:...", ... })
local status, msg, consumed = sip.pop(st.rx, g_opts.max_msg)
]]
local proto = require "exsipproto"

local M = {}

local DEFAULT_USER_AGENT = "LuatOS-GB28181"
local DEFAULT_MAX_HEADERS = 24

-- 追加一行头。name/value 两种写法都吃：{name=,value=} 与 {"Name","value"}
local function put(headers, name, value)
    if name ~= nil and value ~= nil then
        headers[#headers + 1] = { name = name, value = tostring(value) }
    end
end

-- 认证头在接口上是"整行"（含头名；407 用 Proxy-Authorization）。这里拆成 name/value，
-- 好让 Content-Length 之前的顺序与 C 完全一致。
local function put_raw_line(headers, raw)
    if type(raw) ~= "string" or raw == "" then
        return false
    end
    local line = raw:gsub("\r\n$", ""):gsub("\n$", "")
    local name, value = line:match("^([^:]+)%s*:%s*(.*)$")
    if not name then
        return false
    end
    put(headers, name, value)
    return true
end

--[[
构造一条 SIP 报文。入参与原 C 绑定的 sip_build 同形（`code` 非 0 即响应）。

@api exgb28181sip.build(cfg)
@table cfg 字段：method/uri/transport/host/port/branch/from_uri/from_tag/
           to_uri/call_id/cseq/cseq_method/user_agent/contact/contact_user/max_forwards/
           expires/content_type/body/auth/extra_headers；响应用 code/reason/via_list/from_raw/to_raw
@return string 报文；失败返回 nil
@return string 失败原因
]]
function M.build(cfg)
    if type(cfg) ~= "table" then
        return nil, "cfg 不是表"
    end
    local is_response = (tonumber(cfg.code) or 0) ~= 0
    local headers = {}

    -- 1) Via：请求新建；响应回抄（**可能多条**，缺 Via 的响应会被对端丢弃）
    if is_response then
        for _, v in ipairs(cfg.via_list or {}) do
            put(headers, "Via", v)
        end
    else
        if cfg.branch == nil then
            return nil, "请求必须给 branch"
        end
        put(headers, "Via", proto.build_via({
            transport     = cfg.transport,
            local_ip      = cfg.host,
            local_port    = cfg.port,
            branch        = cfg.branch,
            branch_prefix = "",    -- 与 C 的 format_via 一致：branch 原样写出（不加 magic cookie）
            rport_first   = true,  -- 且 rport 在前（rport 只对 UDP 输出）
        }))
    end

    -- 2) From / To：响应必须与请求逐字符一致回抄（含 tag），故走 *_raw
    local from = cfg.from_raw
    if from == nil then
        if cfg.from_uri == nil then
            return nil, "缺少 from_uri（响应需 from_raw）"
        end
        from = proto.build_name_addr(cfg.from_uri, cfg.from_tag)
    end
    put(headers, "From", from)

    local to = cfg.to_raw
    if to == nil then
        if cfg.to_uri == nil then
            return nil, "缺少 to_uri（响应需 to_raw）"
        end
        to = proto.build_name_addr(cfg.to_uri, cfg.to_tag)
    end
    put(headers, "To", to)

    -- 3) Call-ID / CSeq（CSeq 形如 "1 REGISTER"）
    put(headers, "Call-ID", cfg.call_id)
    put(headers, "CSeq", string.format("%d %s",
        tonumber(cfg.cseq) or 0, cfg.cseq_method or cfg.method or ""))

    -- 4) Contact：缺省输出，`contact=false` 关掉；user 缺省从 from_uri 推导（GB28181 里就是设备编码）
    if cfg.contact ~= false then
        local user = cfg.contact_user
        if user == nil then
            user = proto.uri_user(cfg.from_uri)
            if user == nil then
                return nil, "Contact 需要 contact_user，或 from_uri 中需含 user 部分"
            end
        end
        put(headers, "Contact", proto.build_contact({
            user      = user,
            local_ip  = cfg.host,
            local_port = cfg.port,
            transport = cfg.transport,
        }))
    end

    -- 5) Max-Forwards：仅请求
    if not is_response then
        put(headers, "Max-Forwards", cfg.max_forwards or 70)
    end

    -- 6) User-Agent：**响应也要发**（C 如此）
    put(headers, "User-Agent", cfg.user_agent or DEFAULT_USER_AGENT)

    -- 7) 可选头：Expires / Content-Type / auth / extra_headers
    local expires = tonumber(cfg.expires)
    if expires ~= nil and expires >= 0 then
        put(headers, "Expires", cfg.expires)
    end
    if cfg.content_type ~= nil then
        put(headers, "Content-Type", cfg.content_type)
    end
    if cfg.auth ~= nil and not put_raw_line(headers, cfg.auth) then
        return nil, "auth 不是合法的头行"
    end
    for _, h in ipairs(cfg.extra_headers or {}) do
        put(headers, h.name or h[1], h.value or h[2])
    end

    -- 8) 起始行 + Content-Length + body 交给 exsipproto（Content-Length 由它追加在末尾，与 C 一致）
    local body = cfg.body or ""
    if is_response then
        return proto.build_response({
            code    = tonumber(cfg.code),
            reason  = cfg.reason or "",
            headers = headers,
            body    = body,
        })
    end
    return proto.build_request({
        method       = cfg.method,
        uri          = cfg.uri,
        headers      = headers,
        max_forwards = false,   -- 抑制内置的 Max-Forwards —— 顺序要自己控制
        body         = body,
    })
end

--[[
从接收缓冲里弹出一条报文，返回形状与原 C 绑定的 sip_pop 相同。

@api exgb28181sip.pop(data, max_msg)
@string data 接收缓冲（TCP 为累积流，UDP 为单包）
@int max_msg 单条报文上限
@return string 状态："ok" / "need_more" / "bad"
@return table ok 时为消息表 { headers(小写映射), header_list(保序), body, code/reason 或 method/uri }
@return int ok 时为**已消费的字节数**（含被跳过的保活空行，故可直接 data:sub(consumed+1)）
]]
function M.pop(data, max_msg)
    -- UDP 上平台常不发 Content-Length，C 实现在此处是容忍的，故这里也容忍；
    -- TCP 由上层语义保证（同一函数容忍即可，与 C 的 sip_split 行为一致）。
    local status, head, body, rest, err = proto.pop_message(data, {
        allow_missing_content_length = true,
        max_msg = max_msg,
    })
    if status == "need_more" then
        return "need_more", nil, 0
    end
    if status ~= "ok" then
        return "bad", err, 0
    end

    -- 起始行单独解析，头部才交给 parse_head。
    -- 不能把整段 head 丢给 parse_head：起始行形如 `REGISTER sip:x@y SIP/2.0` 含冒号，
    -- 会被当成一条头（名为 "REGISTER sip"），比 C 的解析多出一条。
    local start_line, header_part = head:match("^([^\r\n]*)\r?\n(.*)$")
    local ph = proto.parse_head(header_part or "", { max_headers = DEFAULT_MAX_HEADERS })
    local msg = {
        headers     = ph.map,
        header_list = ph.list,
        body        = body or "",
    }
    local code, reason = proto.parse_status(start_line or head)
    if code then
        msg.code, msg.reason = code, reason
    else
        local method, uri = proto.parse_request_line(start_line or head)
        msg.method, msg.uri = method, uri
    end
    return "ok", msg, #data - #rest
end

return M
