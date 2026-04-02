local crypto = assert(_G.crypto, "crypto is required (MD5). Please enable crypto in firmware")

local M = {}

local RTP_CODEC_PT = {
    PCMU = 0,
    PCMA = 8,
}

local RTP_PT_CODEC = {
    [0] = "PCMU",
    [8] = "PCMA",
}

local function log_info(...)
    if _G.log and type(log.info) == "function" then
        log.info(...)
    end
end

function M.parse_headers(resp)
    local headers = {}
    for line in resp:gmatch("([^\r\n]+)\r?\n") do
        if line == "" then break end
        local k, v = line:match("^([^:]+)%s*:%s*(.*)$")
        if k and v then
            headers[k:lower()] = v
        end
    end
    return headers
end

function M.sip_find_header_end(s)
    local p = s:find("\r\n\r\n", 1, true)
    if p then
        return p + 4
    end
    p = s:find("\n\n", 1, true)
    if p then
        return p + 2
    end
    return nil
end

function M.pop_stream_message(stream)
    local header_end = M.sip_find_header_end(stream)
    if not header_end then
        return nil, nil, stream
    end

    local head = stream:sub(1, header_end - 1)
    local headers = M.parse_headers(head)
    local cl = tonumber(headers["content-length"] or "0") or 0
    local total = header_end + cl - 1
    if #stream < total then
        return nil, nil, stream
    end

    local body = ""
    if cl > 0 then
        body = stream:sub(header_end, header_end + cl - 1)
    end
    local rest = stream:sub(total + 1)
    return head, body, rest
end

M.sip_pop_stream_message = M.pop_stream_message

function M.split_message(msg)
    local p = msg:find("\r\n\r\n", 1, true)
    if p then
        return msg:sub(1, p + 3), msg:sub(p + 4)
    end
    p = msg:find("\n\n", 1, true)
    if p then
        return msg:sub(1, p + 1), msg:sub(p + 2)
    end
    return msg, ""
end

M.split_sip_message = M.split_message

function M.parse_request_line(msg)
    local method, uri = msg:match("^([A-Z]+)%s+([^%s]+)%s+SIP/2%.0")
    if method and uri then
        return method, uri
    end
    return nil, nil
end

function M.parse_status(resp)
    local code, reason = resp:match("^SIP/2%.0%s+(%d%d%d)%s+([^\r\n]+)")
    if code then
        return tonumber(code), reason
    end
    return nil, nil
end

function M.parse_www_authenticate(www)
    if not www then return nil end
    if not www:lower():find("digest", 1, true) then return nil end

    local t = {}
    t.realm = www:match('realm="(.-)"')
    t.nonce = www:match('nonce="(.-)"')
    t.opaque = www:match('opaque="(.-)"')
    t.algorithm = (www:match('algorithm=([^,]+)') or "MD5"):gsub("%s+", "")

    local qop = www:match('qop="(.-)"') or www:match('qop=([^,]+)')
    if qop then
        t.qop = qop
    end

    return t
end

function M.pick_qop(qop)
    if not qop then return nil end
    qop = qop:gsub('"', ''):lower()
    for token in qop:gmatch("[^,%s]+") do
        if token == "auth" then
            return "auth"
        end
    end
    return nil
end

function M.digest_auth(params)
    local username = assert(params.username)
    local password = assert(params.password)
    local realm = assert(params.realm)
    local nonce = assert(params.nonce)
    local method = assert(params.method)
    local uri = assert(params.uri)

    local algorithm = (params.algorithm or "MD5"):gsub("%s+", ""):upper()
    if algorithm ~= "MD5" then
        return nil, "unsupported algorithm: " .. algorithm
    end

    local ha1 = crypto.md5(username .. ":" .. realm .. ":" .. password):lower()
    local ha2 = crypto.md5(method .. ":" .. uri):lower()

    local qop = M.pick_qop(params.qop)
    local cnonce = params.cnonce
    local nc = params.nc

    local response
    if qop and cnonce and nc then
        response = crypto.md5(ha1 .. ":" .. nonce .. ":" .. nc .. ":" .. cnonce .. ":" .. qop .. ":" .. ha2):lower()
    else
        response = crypto.md5(ha1 .. ":" .. nonce .. ":" .. ha2):lower()
    end

    return {
        username = username,
        realm = realm,
        nonce = nonce,
        uri = uri,
        response = response,
        algorithm = algorithm,
        qop = qop,
        cnonce = cnonce,
        nc = nc,
        opaque = params.opaque,
    }
end

M.sip_digest_auth = M.digest_auth

function M.build_auth_header(auth)
    if not auth then return nil end

    local parts = {}
    parts[#parts + 1] = string.format('Digest username="%s"', auth.username)
    parts[#parts + 1] = string.format('realm="%s"', auth.realm)
    parts[#parts + 1] = string.format('nonce="%s"', auth.nonce)
    parts[#parts + 1] = string.format('uri="%s"', auth.uri)
    if auth.algorithm then
        parts[#parts + 1] = string.format('algorithm=%s', auth.algorithm)
    end
    if auth.opaque then
        parts[#parts + 1] = string.format('opaque="%s"', auth.opaque)
    end
    if auth.qop and auth.nc and auth.cnonce then
        parts[#parts + 1] = string.format('qop=%s', auth.qop)
        parts[#parts + 1] = string.format('nc=%s', auth.nc)
        parts[#parts + 1] = string.format('cnonce="%s"', auth.cnonce)
    end
    parts[#parts + 1] = string.format('response="%s"', auth.response)

    return string.format("%s: %s\r\n", auth.header_name or "Authorization", table.concat(parts, ", "))
end

local function append_header_line(lines, header)
    if not header then return end
    if type(header) == "string" then
        if header:find("\r\n", 1, true) then
            lines[#lines + 1] = header
        else
            lines[#lines + 1] = header .. "\r\n"
        end
        return
    end

    local name = header.name or header[1]
    local value = header.value or header[2]
    if name and value ~= nil then
        lines[#lines + 1] = string.format("%s: %s\r\n", name, tostring(value))
    end
end

function M.build_via(params)
    local transport = tostring(params.transport or "UDP"):upper()
    local suffix = (transport == "TCP") and "" or ";rport"
    return string.format(
        "SIP/2.0/%s %s:%d;branch=z9hG4bK%s%s",
        transport,
        params.local_ip or "0.0.0.0",
        tonumber(params.local_port) or 0,
        params.branch or "",
        suffix
    )
end

function M.build_contact(params)
    local uri_params = {}
    local header_params = {}

    if tostring(params.transport or "UDP"):upper() == "TCP" then
        uri_params[#uri_params + 1] = "transport=tcp"
    end
    for _, value in ipairs(params.uri_params or {}) do
        uri_params[#uri_params + 1] = value
    end
    for _, value in ipairs(params.header_params or {}) do
        header_params[#header_params + 1] = value
    end

    local uri_suffix = (#uri_params > 0) and (";" .. table.concat(uri_params, ";")) or ""
    local header_suffix = (#header_params > 0) and (";" .. table.concat(header_params, ";")) or ""

    return string.format(
        "<sip:%s@%s:%d%s>%s",
        tostring(params.user or ""),
        params.local_ip or "0.0.0.0",
        tonumber(params.local_port) or 0,
        uri_suffix,
        header_suffix
    )
end

function M.build_request(ctx)
    local body = ctx.body or ""
    local lines = {}

    lines[#lines + 1] = string.format("%s %s SIP/2.0\r\n", ctx.method, ctx.uri)
    if ctx.via_ctx then
        append_header_line(lines, { "Via", M.build_via(ctx.via_ctx) })
    elseif ctx.via then
        append_header_line(lines, { "Via", ctx.via })
    end

    if ctx.max_forwards ~= false then
        append_header_line(lines, { "Max-Forwards", tostring(ctx.max_forwards or 70) })
    end

    for _, header in ipairs(ctx.headers or {}) do
        append_header_line(lines, header)
    end

    if ctx.contact_ctx then
        append_header_line(lines, { "Contact", M.build_contact(ctx.contact_ctx) })
    elseif ctx.contact then
        append_header_line(lines, { "Contact", ctx.contact })
    end

    if ctx.user_agent then
        append_header_line(lines, { "User-Agent", ctx.user_agent })
    end

    append_header_line(lines, ctx.auth_header)

    if #body > 0 and ctx.content_type then
        append_header_line(lines, { "Content-Type", ctx.content_type })
    end
    append_header_line(lines, { "Content-Length", tostring(#body) })
    lines[#lines + 1] = "\r\n"
    lines[#lines + 1] = body
    return table.concat(lines)
end

function M.build_response(ctx)
    local body = ctx.body or ""
    local lines = {}

    lines[#lines + 1] = string.format("SIP/2.0 %d %s\r\n", ctx.code, ctx.reason or "")
    for _, header in ipairs(ctx.headers or {}) do
        append_header_line(lines, header)
    end

    if ctx.contact_ctx then
        append_header_line(lines, { "Contact", M.build_contact(ctx.contact_ctx) })
    elseif ctx.contact then
        append_header_line(lines, { "Contact", ctx.contact })
    end

    for _, header in ipairs(ctx.extra_headers or {}) do
        append_header_line(lines, header)
    end

    if #body > 0 and ctx.content_type then
        append_header_line(lines, { "Content-Type", ctx.content_type })
    end
    append_header_line(lines, { "Content-Length", tostring(#body) })
    lines[#lines + 1] = "\r\n"
    lines[#lines + 1] = body
    return table.concat(lines)
end

function M.normalize_codec_name(name)
    local key = tostring(name or ""):upper()
    if RTP_CODEC_PT[key] then
        return key
    end
    return nil
end

function M.normalize_codec_list(codecs)
    local out = {}
    local seen = {}
    for _, name in ipairs(codecs or {}) do
        local key = M.normalize_codec_name(name)
        if key and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    if #out == 0 then
        out = { "PCMU", "PCMA" }
    end
    return out
end

function M.pick_common_codec(local_codecs, remote_codecs)
    local remote_set = {}
    for _, name in ipairs(remote_codecs or {}) do
        local key = M.normalize_codec_name(name)
        if key then
            remote_set[key] = true
        end
    end
    for _, name in ipairs(local_codecs or {}) do
        local key = M.normalize_codec_name(name)
        if key and remote_set[key] then
            return key
        end
    end
    return nil
end

function M.codec_payload_type(codec)
    local key = M.normalize_codec_name(codec)
    if not key then
        return nil
    end
    return RTP_CODEC_PT[key]
end

function M.build_media_session(params)
    local remote_sdp = params.remote_sdp or {}
    local selected_codec = params.codec or M.pick_common_codec(params.local_codecs, remote_sdp.codecs)
    if not selected_codec then
        return nil, "no_common_codec"
    end

    local remote_port = tonumber(params.remote_port or remote_sdp.audio_port)
    if not remote_port or remote_port <= 0 then
        return nil, "invalid_remote_port"
    end

    return {
        call_id = params.call_id,
        remote_ip = params.remote_ip or remote_sdp.conn_ip,
        remote_port = remote_port,
        remote_direction = remote_sdp.direction,
        remote_codecs = remote_sdp.codecs,
        local_rtp_port = params.local_rtp_port,
        local_codecs = params.local_codecs,
        codec = selected_codec,
        payload_type = M.codec_payload_type(selected_codec),
        sample_rate = 8000,
        channels = 1,
        bits = 16,
        ptime = tonumber(params.ptime or remote_sdp.ptime),
        local_sdp = params.local_sdp,
        remote_sdp = params.remote_sdp_raw,
        source = params.source,
    }
end

function M.build_sdp(state, direction)
    local ip = state.local_ip or "0.0.0.0"
    log_info("test ip", ip)
    local media = state.media or {}
    local rtp_port = tonumber(media.local_rtp_port) or 0
    local ptime = tonumber(media.ptime) or 20
    local codecs = M.normalize_codec_list(media.codecs or { "PCMU", "PCMA" })
    local payloads = {}

    for _, cname in ipairs(codecs) do
        local pt = RTP_CODEC_PT[tostring(cname):upper()]
        if pt then
            payloads[#payloads + 1] = pt
        end
    end
    if #payloads == 0 then
        payloads = { 0, 8 }
    end

    local sdp = {}
    sdp[#sdp + 1] = "v=0\r\n"
    sdp[#sdp + 1] = string.format("o=luatos 0 0 IN IP4 %s\r\n", ip)
    sdp[#sdp + 1] = "s=LuatOS\r\n"
    sdp[#sdp + 1] = string.format("c=IN IP4 %s\r\n", ip)
    sdp[#sdp + 1] = "t=0 0\r\n"
    sdp[#sdp + 1] = string.format("m=audio %d RTP/AVP %s\r\n", rtp_port, table.concat(payloads, " "))
    for _, pt in ipairs(payloads) do
        if pt == 0 then
            sdp[#sdp + 1] = "a=rtpmap:0 PCMU/8000\r\n"
        elseif pt == 8 then
            sdp[#sdp + 1] = "a=rtpmap:8 PCMA/8000\r\n"
        end
    end
    sdp[#sdp + 1] = string.format("a=ptime:%d\r\n", ptime)
    sdp[#sdp + 1] = string.format("a=%s\r\n", direction or "sendrecv")
    return table.concat(sdp)
end

function M.parse_sdp(sdp)
    if type(sdp) ~= "string" or #sdp == 0 then return nil end
    log_info("sip", "parsing remote SDP", sdp)
    local out = {
        conn_ip = nil,
        audio_port = nil,
        payloads = {},
        codecs = {},
        direction = "sendrecv",
        ptime = nil,
    }

    for line in sdp:gmatch("([^\r\n]+)") do
        local c_ip = line:match("^c=IN%s+IP4%s+([^%s]+)")
        if c_ip then
            out.conn_ip = c_ip
        end

        local m_port, m_payloads = line:match("^m=audio%s+(%d+)%s+RTP/%u+%s+(.+)$")
        if m_port then
            out.audio_port = tonumber(m_port)
            for pt in tostring(m_payloads):gmatch("(%d+)") do
                local ptn = tonumber(pt)
                out.payloads[#out.payloads + 1] = ptn
                local known = RTP_PT_CODEC[ptn]
                if known then
                    out.codecs[#out.codecs + 1] = known
                end
            end
        end

        local map_pt, map_codec = line:match("^a=rtpmap:(%d+)%s+([^/]+)/")
        if map_pt and map_codec then
            local c = M.normalize_codec_name(map_codec)
            if c then
                out.codecs[#out.codecs + 1] = c
            end
        end

        local ptime = line:match("^a=ptime:(%d+)")
        if ptime then
            out.ptime = tonumber(ptime)
        end

        if line == "a=sendonly" then
            out.direction = "sendonly"
        elseif line == "a=recvonly" then
            out.direction = "recvonly"
        elseif line == "a=inactive" then
            out.direction = "inactive"
        elseif line == "a=sendrecv" then
            out.direction = "sendrecv"
        end
    end

    out.codecs = M.normalize_codec_list(out.codecs)

    return out
end

return M