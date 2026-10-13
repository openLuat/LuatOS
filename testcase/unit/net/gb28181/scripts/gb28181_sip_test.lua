--[[
GB28181 的 SIP 报文层单元测试。

被测对象是 Lua 侧的 exgb28181sip（它复用生态的 exsipproto），取代原先
由 C 绑定 gb28181.sip_build / sip_pop 承担的那一层。迁移的判据是**逐字节不变**，
所以本文件的主用例是"黄金报文比对"：sip_golden.lua 里的期望值取自迁移前 C 的实现，
改坏了这里必然红。

另有一批行为用例（半包/超大 Content-Length/响应回抄/缺参失败）与摘要用例，
原先住在 gb28181_c_test.lua 的"C 绑定"组里 —— SIP 不再是 C 的职责，故随实现一起搬过来。

注意 testrunner 用 pairs() 遍历用例，执行顺序不确定，每个用例自备状态。
]]

local sip   = require("exgb28181sip")
local proto = require("exsipproto")
local golden = require("sip_golden")

local t = {}

-- ---- 真实平台下发的报文/摘要（取自真实 WVP 交互） ----

local REAL_QUERY =
    "MESSAGE sip:35020000001320000001@172.22.0.1:53194 SIP/2.0\r\n" ..
    "Call-ID: bc9d6ac67da59c79d89b448c2e2cff25@0:0:0:0:0:0:0:0\r\n" ..
    "CSeq: 2 MESSAGE\r\n" ..
    "From: <sip:35020000002000000001@3502000000>;tag=3db1fdbb78354c85ada1d1f3777143fc\r\n" ..
    "To: <sip:35020000001320000001@172.22.0.1:53194>\r\n" ..
    "Via: SIP/2.0/UDP 127.0.0.1:8160;branch=z9hG4bK4207754998;rport\r\n" ..
    "Max-Forwards: 70\r\n" ..
    "User-Agent: WVP-Pro v2.7.4.2026-08-29T15:41:20Z\r\n" ..
    "Content-Type: Application/MANSCDP+xml\r\n"

local REAL_QUERY_BODY =
    "<?xml version=\"1.0\" encoding=\"GB2312\"?>\r\n" ..
    "<Query>\r\n" ..
    "<CmdType>DeviceInfo</CmdType>\r\n" ..
    "<SN>347281</SN>\r\n" ..
    "<DeviceID>35020000001320000001</DeviceID>\r\n" ..
    "</Query>\r\n"

-- 平台真实下发的 Digest 挑战头
local REAL_CHALLENGE =
    "Digest realm=\"3502000000\",qop=\"auth\"," ..
    "nonce=\"73a1002c90df9b154be4ad7f4100fe75\",algorithm=MD5"

local REAL_DIGEST_CFG = {
    username  = "35020000001320000001",
    password  = "wvp_sip_password",
    realm     = "3502000000",
    nonce     = "73a1002c90df9b154be4ad7f4100fe75",
    method    = "REGISTER",
    uri       = "sip:35020000002000000001@3502000000",
    qop       = "auth",
    nc        = "00000001",
    cnonce    = "qnv7a1uxmof91l1q",
    algorithm = "MD5",
}
local REAL_RESPONSE = "5ecbc51c3eafb1648786a6529c7dd112"

-- ---- 黄金报文：与 sip_golden.lua 一一对应（键名即 e2e 里的用例名） ----

local CFG = {
    register = {
        method = "REGISTER", uri = "sip:35020000002000000001@3502000000",
        transport = "UDP", host = "192.168.0.13", port = 5160, branch = "1234567890abcdef",
        from_uri = "sip:35020000001320000001@3502000000", from_tag = "abcdef01",
        to_uri = "sip:35020000001320000001@3502000000",
        call_id = "0123456789abcdef@192.168.0.13", cseq = 1, cseq_method = "REGISTER",
        user_agent = "LuatOS-GB28181", expires = 3600,
        auth = "Authorization: Digest username=\"35020000001320000001\", realm=\"3502000000\", " ..
               "nonce=\"abc\", uri=\"sip:x\", response=\"deadbeef\"\r\n",
    },
    message_manscdp = {
        method = "MESSAGE", uri = "sip:35020000002000000001@3502000000",
        transport = "UDP", host = "192.168.0.13", port = 5160, branch = "1234567890abcdef",
        from_uri = "sip:35020000001320000001@3502000000", from_tag = "abcdef01",
        to_uri = "sip:35020000001320000001@3502000000",
        call_id = "c1@192.168.0.13", cseq = 2, cseq_method = "MESSAGE",
        content_type = "Application/MANSCDP+xml",
        body = "<?xml version=\"1.0\"?>\r\n<Notify><CmdType>Keepalive</CmdType></Notify>\r\n",
    },
    invite_subject = {
        method = "INVITE", uri = "sip:35020000002000000001@3502000000",
        transport = "UDP", host = "192.168.0.13", port = 5160, branch = "1234567890abcdef",
        from_uri = "sip:35020000001320000001@3502000000", from_tag = "abcdef01",
        to_uri = "sip:35020000002000000001@3502000000",
        call_id = "c2@192.168.0.13", cseq = 3, cseq_method = "INVITE",
        contact_user = "35020000001320000001",
        content_type = "application/sdp",
        body = "v=0\r\no=35020000001320000001 0 0 IN IP4 192.168.0.13\r\ns=Talk\r\n",
        extra_headers = { { name = "Subject", value = "34020000001320000001:talk,34020000001320000001:0" } },
    },
    ack = {
        method = "ACK", uri = "sip:35020000002000000001@3502000000",
        transport = "UDP", host = "192.168.0.13", port = 5160, branch = "1234567890abcdef",
        from_uri = "sip:35020000001320000001@3502000000", from_tag = "abcdef01",
        to_uri = "sip:35020000002000000001@3502000000", to_tag = "plat01",
        call_id = "c3@192.168.0.13", cseq = 4, cseq_method = "ACK",
    },
    ok_single_via = {
        code = 200, reason = "OK",
        via_list = { "SIP/2.0/UDP 192.168.0.4:8160;branch=z9hG4bKplat" },
        from_raw = "<sip:35020000002000000001@3502000000>;tag=platfrom",
        to_raw = "<sip:35020000001320000001@3502000000>",
        call_id = "c4@192.168.0.4", cseq = 7, cseq_method = "MESSAGE",
        contact = false, host = "192.168.0.13", port = 5160,
    },
    ok_multi_via = {
        code = 200, reason = "OK",
        via_list = { "SIP/2.0/UDP 192.168.0.4:8160;branch=z9hG4bKa",
                     "SIP/2.0/UDP 192.168.0.9:8160;branch=z9hG4bKb" },
        from_raw = "<sip:35020000002000000001@3502000000>;tag=pf",
        to_raw = "<sip:35020000001320000001@3502000000>;tag=dev",
        call_id = "c5@192.168.0.4", cseq = 8, cseq_method = "SUBSCRIBE",
        contact = false, host = "192.168.0.13", port = 5160,
        extra_headers = { { name = "Expires", value = "3600" }, { name = "Event", value = "Catalog" } },
    },
    tcp_register = {
        method = "REGISTER", uri = "sip:35020000002000000001@3502000000",
        transport = "TCP", host = "192.168.0.13", port = 5160, branch = "1234567890abcdef",
        from_uri = "sip:35020000001320000001@3502000000", from_tag = "abcdef01",
        to_uri = "sip:35020000001320000001@3502000000",
        call_id = "c6@192.168.0.13", cseq = 9, cseq_method = "REGISTER", expires = 3600,
    },
    gone_with_body = {
        code = 410, reason = "Gone",
        via_list = { "SIP/2.0/UDP 192.168.0.4:8160;branch=z9hG4bKc" },
        from_raw = "<sip:a@b>;tag=f", to_raw = "<sip:c@d>;tag=t",
        call_id = "c7@x", cseq = 10, cseq_method = "INVITE", contact = false,
        host = "192.168.0.13", port = 5160, content_type = "Application/MANSCDP+xml",
        body = "<Response><CmdType>Catalog</CmdType></Response>",
    },
}

--[[ 迁移的硬判据：构造结果与迁移前 C 的黄金报文字节一致 ]]
function t.test_golden_packets_byte_exact()
    for name, cfg in pairs(CFG) do
        local want = golden[name]
        assert(want ~= nil, "夹具里缺 " .. name)
        local got, err = sip.build(cfg)
        assert(got ~= nil, name .. " 构造失败: " .. tostring(err))
        if got ~= want then
            -- 报出首个差异位置，便于定位
            local n = math.min(#got, #want)
            local at = n + 1
            for i = 1, n do
                if got:byte(i) ~= want:byte(i) then at = i break end
            end
            error(string.format("%s 与黄金报文不一致: 长度 %d/%d, 首个差异 @%d", name, #got, #want, at))
        end
    end
end

--[[ 数据不足时应返回 need_more 且不消费任何字节 ]]
function t.test_sip_pop_need_more()
    local status, msg, consumed = sip.pop("MESSAGE sip:a@b SIP/2.0\r\nCall-ID: x\r\n", 8192)
    assert(status == "need_more", "半包应返回 need_more, 实际 " .. tostring(status))
    assert(msg == nil, "非 ok 时不应返回报文表")
    assert(consumed == 0, "非 ok 时不应消费字节")
end

--[[ 畸形报文的 Content-Length 应被判为 bad，而不是无限缓冲 ]]
function t.test_sip_pop_rejects_oversized_content_length()
    local bad = "MESSAGE sip:a@b SIP/2.0\r\nCall-ID: x\r\n" ..
                "Content-Length: 2000000000\r\n\r\nshort"
    local status, msg, consumed = sip.pop(bad, 8192)
    assert(status == "bad", "超大 Content-Length 应返回 bad, 实际 " .. tostring(status))
    assert(consumed == 0, "bad 时不应消费字节")
end

--[[ 解析真实平台下发查询的起始行与头字段 ]]
function t.test_sip_pop_real_platform_query()
    local raw = REAL_QUERY .. "Content-Length: " .. #REAL_QUERY_BODY ..
                "\r\n\r\n" .. REAL_QUERY_BODY
    local status, msg, consumed = sip.pop(raw, 8192)

    assert(status == "ok", "应解析成功, 实际 " .. tostring(status))
    assert(consumed == #raw, "无剩余字节时应恰好消费全部")
    assert(msg.method == "MESSAGE", "method 应为 MESSAGE")
    assert(msg.uri == "sip:35020000001320000001@172.22.0.1:53194", "uri 不对")
    assert(msg.code == nil, "请求不应有 code")

    assert(msg.headers["content-type"] == "Application/MANSCDP+xml", "headers 的键应为小写")
    assert(msg.headers["call-id"] == "bc9d6ac67da59c79d89b448c2e2cff25@0:0:0:0:0:0:0:0",
           "Call-ID 含 IPv6 全零串时应原样保留")
    assert(msg.body == REAL_QUERY_BODY, "消息体应完整且逐字节一致")
end

--[[ 头解析必须保序、且不丢重复头（响应要回抄多条 Via）]]
function t.test_sip_head_order_and_duplicates()
    local status, msg = sip.pop(REAL_QUERY .. "Content-Length: 0\r\n\r\n", 8192)
    assert(status == "ok")

    assert(msg.header_list[1].name == "Call-ID", "header_list 应按线上顺序（起始行不算头）")
    assert(msg.headers["content-type"] == "Application/MANSCDP+xml", "映射键应小写")

    -- 两条 Via 都要留住（旧实现用小写映射会只剩后者）
    local multi = REAL_QUERY .. "Via: SIP/2.0/UDP 10.0.0.1:1;branch=b2\r\nContent-Length: 0\r\n\r\n"
    local st, m = sip.pop(multi, 8192)
    assert(st == "ok")
    local vias = 0
    for _, h in ipairs(m.header_list) do
        if h.name:lower() == "via" then vias = vias + 1 end
    end
    assert(vias == 2, "两条 Via 都应保留, 实际 " .. vias)
end

--[[ 构造的报文应能被自己解析回（往返一致） ]]
function t.test_sip_build_roundtrip()
    local status, msg, consumed = sip.pop(golden.register, 8192)
    assert(status == "ok", "黄金报文应能被解析回, 实际 " .. tostring(status))
    assert(consumed == #golden.register, "应恰好消费整条报文")
    assert(msg.method == "REGISTER")
    assert(msg.uri == "sip:35020000002000000001@3502000000")
    assert(msg.headers["cseq"] == "1 REGISTER", "CSeq 应为 '1 REGISTER'")
    assert(msg.headers["expires"] == "3600")
    assert(msg.headers["max-forwards"] == "70", "Max-Forwards 缺省应为 70")
    assert(msg.headers["contact"] == "<sip:35020000001320000001@192.168.0.13:5160>",
           "Contact 的 user 应缺省取自设备编码")
    assert(string.find(msg.headers["via"], ";rport", 1, true) ~= nil, "UDP 的 Via 应带 rport")
    assert(msg.headers["content-length"] == "0")
end

--[[ 带消息体时 Content-Length 应自动算对 ]]
function t.test_sip_build_auto_content_length()
    local body = "<?xml version=\"1.0\"?>\r\n<Notify><CmdType>Keepalive</CmdType></Notify>\r\n"
    local status, msg = sip.pop(golden.message_manscdp, 8192)
    assert(status == "ok")
    assert(tonumber(msg.headers["content-length"]) == #body,
           "Content-Length 应等于 body 实际长度, 实际 " .. tostring(msg.headers["content-length"]))
    assert(msg.body == body, "消息体应逐字节一致")
end

--[[ 缺必填项应返回 nil + 原因，而不是发出半成品报文 ]]
function t.test_sip_build_rejects_incomplete_config()
    local out, err = sip.build({ method = "REGISTER" })
    assert(out == nil, "缺必填项应失败")
    assert(type(err) == "string", "应给出失败原因")

    -- 请求缺 branch（branch 需调用方用随机源生成）
    out, err = sip.build({
        method = "REGISTER", uri = "sip:a@b",
        host = "1.1.1.1", port = 5060,
        from_uri = "sip:1@b", to_uri = "sip:2@b",
        call_id = "c@1", cseq = 1,
    })
    assert(out == nil, "请求缺 branch 应失败")
end

--[[
响应走 from_raw 回抄时没有 from_uri。
此时若还要 Contact，必须显式拿到 contact_user 或**干净地失败** ——
曾经这里 strlen(NULL)，点播 INVITE 的 200 OK 应答当场段错误。
]]
function t.test_sip_build_response_contact_without_from_uri()
    local cfg = {
        code = 200, reason = "OK",
        via_list = { "SIP/2.0/UDP 127.0.0.1:8199;rport;branch=z9hG4bKabc" },
        from_raw = "<sip:35020000002000000001@3502000000>;tag=xyz",
        to_raw   = "<sip:35020000001320000001@3502000000>",
        call_id  = "abc@test", cseq = 1, cseq_method = "INVITE",
        host = "192.168.0.4", port = 5160,
        contact = true, contact_user = "35020000001320000001",
    }
    local built, err = sip.build(cfg)
    assert(built ~= nil, "给了 contact_user 就应构造成功: " .. tostring(err))

    local status, msg = sip.pop(built, 8192)
    assert(status == "ok")
    assert(msg.headers["contact"] == "<sip:35020000001320000001@192.168.0.4:5160>",
           "Contact 应为显式给出的设备编码, 实际 " .. tostring(msg.headers["contact"]))

    -- 没 contact_user：应返回 nil + 原因，绝不能崩
    cfg.contact_user = nil
    local out, reason = sip.build(cfg)
    assert(out == nil, "缺 contact_user 且无 from_uri 应失败")
    assert(type(reason) == "string", "应给出失败原因")
end

--[[ 摘要必须与真实平台接受的值一致——这是"我们发给平台的认证对不对"的关键证据 ]]
function t.test_sip_digest_matches_real_platform()
    local d = proto.digest_auth(REAL_DIGEST_CFG)
    assert(d ~= nil, "digest_auth 应返回参数表")
    assert(d.response == REAL_RESPONSE,
           "摘要应与平台接受值一致: 期望 " .. REAL_RESPONSE .. ", 实际 " .. tostring(d.response))

    -- 密码错则不该相同
    local wrong = {}
    for k, v in pairs(REAL_DIGEST_CFG) do wrong[k] = v end
    wrong.password = "wrong_password"
    assert(proto.digest_auth(wrong).response ~= REAL_RESPONSE, "密码错误时摘要不应相同")
end

--[[ 缺 qop 时应走 RFC 2069 兼容路径(与带 qop 结果不同) ]]
function t.test_sip_digest_without_qop()
    local cfg = {}
    for k, v in pairs(REAL_DIGEST_CFG) do cfg[k] = v end
    cfg.qop, cfg.nc, cfg.cnonce = nil, nil, nil

    local noqop = proto.digest_auth(cfg).response
    assert(type(noqop) == "string" and #noqop == 32, "无 qop 也应能算出摘要")
    assert(noqop ~= REAL_RESPONSE, "无 qop 的结果应与带 qop 的不同")
end

--[[ 挑战解析：真实平台下发的那一条 ]]
function t.test_sip_parse_challenge_real()
    local ch = proto.parse_www_authenticate(REAL_CHALLENGE)
    assert(ch ~= nil, "应解析出挑战")
    assert(ch.realm == "3502000000")
    assert(ch.nonce == "73a1002c90df9b154be4ad7f4100fe75")
    assert(ch.algorithm == "MD5")
    assert(ch.qop == "auth")
    assert(ch.opaque == nil, "平台未下发 opaque, 应为 nil")
end

--[[ 挑战解析的失败路径。
     语义差异须知：非 Digest 方案在此被拒；但缺 realm/nonce 时 exsipproto **不**在解析处拒绝，
     而是等 digest_auth 调用时抛错(C 层旧实现是在解析处返回错误码)。故只钉非 Digest 这条。 ]]
function t.test_sip_parse_challenge_rejects_non_digest()
    assert(proto.parse_www_authenticate("Basic realm=\"x\"") == nil, "Basic 方案应被拒")
end

--[[ 认证头应含全部必需参数。返回的是**整行**(含头名)，头名由调用方按 401/407 决定 ]]
function t.test_sip_authorization_contains_required_params()
    local v = proto.build_auth_header(proto.digest_auth(REAL_DIGEST_CFG))
    assert(type(v) == "string", "应返回字符串")
    assert(string.find(v, "Authorization: Digest ", 1, true) == 1, "应以 'Authorization: Digest ' 开头")
    assert(string.find(v, 'username="35020000001320000001"', 1, true) ~= nil)
    assert(string.find(v, 'realm="3502000000"', 1, true) ~= nil)
    assert(string.find(v, REAL_RESPONSE, 1, true) ~= nil, "应含 response")
    assert(string.find(v, "qop=auth", 1, true) ~= nil)
    assert(string.find(v, "nc=00000001", 1, true) ~= nil)
end

return t
