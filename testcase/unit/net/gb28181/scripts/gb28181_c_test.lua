--[[
GB28181 C 层绑定的单元测试（里程碑 1.8）。

与 gb28181_test.lua 的分工：
  gb28181_test.lua  测 Lua 门面 exgb28181.lua 的配置校验与事件
  本文件             测 C 绑定 gb28181.*，即 Lua 层实际依赖的那层

本文件里的报文与摘要期望值取自**真实 WVP 平台交互**，与
luatos-ext-components/gb28181/tests/test_platform_vectors.c 同源。
这样 Lua 侧也能验证"绑定没有把 C 层用错"。

注意 testrunner 用 pairs() 遍历用例，执行顺序不确定，每个用例自备状态。
]]

-- 取 C 模块：真机走 require，PC 模拟器需回退全局表。
-- 该模拟器用自定义加载器接管了 require(做脚本依赖裁剪)，不解析 C 内建模块，
-- require "gb28181" / "voip" 在这里都会失败，但模块仍在全局表上。
-- exgb28181.lua 的 load_core() 用的是同一套回退逻辑。
local ok, mod = pcall(require, "gb28181")
local gb = ok and mod or rawget(_G, "gb28181")

local t = {}

-- 真实平台下发的一条 MANSCDP 查询（DeviceInfo）
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

-- 真实交互中被平台接受的那组摘要参数与结果
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

--[[ C 绑定必须存在且是 rotable 风格模块(userdata) ]]
function t.test_c_module_available()
    assert(gb ~= nil, "require gb28181 失败")
    assert(type(gb.sip_pop) == "function", "gb28181.sip_pop 不存在")
    assert(type(gb.sip_build) == "function", "gb28181.sip_build 不存在")
    assert(type(gb.sip_digest) == "function", "gb28181.sip_digest 不存在")
end

--[[ 数据不足时应返回 need_more 且不消费任何字节 ]]
function t.test_sip_pop_need_more()
    local status, msg, consumed = gb.sip_pop("MESSAGE sip:a@b SIP/2.0\r\nCall-ID: x\r\n", 8192)
    assert(status == "need_more", "半包应返回 need_more, 实际 " .. tostring(status))
    assert(msg == nil, "非 ok 时不应返回报文表")
    assert(consumed == 0, "非 ok 时不应消费字节")
end

--[[ 畸形报文的 Content-Length 应被判为 bad，而不是无限缓冲 ]]
function t.test_sip_pop_rejects_oversized_content_length()
    local bad = "MESSAGE sip:a@b SIP/2.0\r\n" ..
                "Call-ID: x\r\n" ..
                "Content-Length: 2000000000\r\n\r\nshort"
    local status, msg, consumed = gb.sip_pop(bad, 8192)
    assert(status == "bad", "超大 Content-Length 应返回 bad, 实际 " .. tostring(status))
    assert(consumed == 0, "bad 时不应消费字节")
end

--[[ 解析真实平台下发查询的起始行与头字段 ]]
function t.test_sip_pop_real_platform_query()
    local raw = REAL_QUERY .. "Content-Length: " .. #REAL_QUERY_BODY ..
                "\r\n\r\n" .. REAL_QUERY_BODY
    local status, msg, consumed = gb.sip_pop(raw, 8192)

    assert(status == "ok", "应解析成功, 实际 " .. tostring(status))
    assert(consumed == #raw, "无剩余字节时应恰好消费全部")
    assert(msg.method == "MESSAGE", "method 应为 MESSAGE")
    assert(msg.uri == "sip:35020000001320000001@172.22.0.1:53194", "uri 不对")
    assert(msg.code == nil, "请求不应有 code")

    assert(msg.headers["content-type"] == "Application/MANSCDP+xml",
           "headers 的键应为小写")
    assert(msg.headers["call-id"] == "bc9d6ac67da59c79d89b448c2e2cff25@0:0:0:0:0:0:0:0",
           "Call-ID 含 IPv6 全零串时应原样保留")
    assert(msg.body == REAL_QUERY_BODY, "消息体应完整且逐字节一致")
end

--[[ 头字段取值应大小写不敏感，且能按线上顺序遍历 ]]
function t.test_sip_header_lookup_and_order()
    local raw = REAL_QUERY .. "Content-Length: 0\r\n\r\n"
    local status, msg = gb.sip_pop(raw, 8192)
    assert(status == "ok")

    assert(gb.sip_header(msg, "Call-ID") == msg.headers["call-id"],
           "sip_header 应大小写不敏感")
    assert(gb.sip_header(msg, "CONTENT-TYPE") == "Application/MANSCDP+xml",
           "大写名也应能取到")
    assert(gb.sip_header(msg, "X-Not-Exist") == nil, "不存在的头应返回 nil")

    -- header_list 保序，用于响应时原样回抄 Via
    assert(type(msg.header_list) == "table", "应有 header_list")
    assert(msg.header_list[1].name == "Call-ID", "header_list 应按线上顺序")
end

--[[ 构造的报文应能被本模块解析回（往返一致） ]]
function t.test_sip_build_roundtrip()
    local built = gb.sip_build({
        method    = "REGISTER",
        uri       = "sip:35020000002000000001@3502000000",
        host      = "192.168.1.100",
        port      = 5060,
        branch    = "z9hG4bKtest123",
        from_uri  = "sip:35020000001320000001@3502000000",
        from_tag  = "abcd",
        to_uri    = "sip:35020000001320000001@3502000000",
        call_id   = "call1@192.168.1.100",
        cseq      = 1,
        expires   = 3600,
    })
    assert(built ~= nil, "构造应成功")

    local status, msg, consumed = gb.sip_pop(built, 8192)
    assert(status == "ok", "构造结果应能被解析回, 实际 " .. tostring(status))
    assert(consumed == #built, "应恰好消费整条报文")
    assert(msg.method == "REGISTER")
    assert(msg.uri == "sip:35020000002000000001@3502000000")
    assert(msg.headers["cseq"] == "1 REGISTER", "CSeq 应为 '1 REGISTER'")
    assert(msg.headers["expires"] == "3600")
    assert(msg.headers["max-forwards"] == "70", "Max-Forwards 缺省应为 70")
    -- Contact 的 user 缺省从 from_uri 推导
    assert(msg.headers["contact"] == "<sip:35020000001320000001@192.168.1.100:5060>",
           "Contact 应为 <sip:设备编码@地址:端口>, 实际 " .. tostring(msg.headers["contact"]))
    -- UDP 下 Via 应带 rport
    assert(string.find(msg.headers["via"], ";rport", 1, true) ~= nil,
           "UDP 的 Via 应带 rport")
    assert(msg.headers["content-length"] == "0")
end

--[[ 带消息体时 Content-Length 应自动算对 ]]
function t.test_sip_build_auto_content_length()
    local body = REAL_QUERY_BODY
    local built = gb.sip_build({
        method       = "MESSAGE",
        uri          = "sip:35020000002000000001@3502000000",
        host         = "192.168.1.100", port = 5060,
        branch       = "z9hG4bKmsg",
        from_uri     = "sip:35020000001320000001@3502000000",
        to_uri       = "sip:35020000002000000001@3502000000",
        call_id      = "m1@a",
        cseq         = 20,
        content_type = "Application/MANSCDP+xml",
        body         = body,
    })
    assert(built ~= nil)

    local status, msg = gb.sip_pop(built, 8192)
    assert(status == "ok")
    assert(tonumber(msg.headers["content-length"]) == #body,
           "Content-Length 应等于 body 实际长度")
    assert(msg.body == body, "消息体应逐字节一致")
end

--[[ 缺必填项应返回 nil + 原因，而不是发出半成品报文 ]]
function t.test_sip_build_rejects_incomplete_config()
    local out, err = gb.sip_build({ method = "REGISTER" })
    assert(out == nil, "缺必填项应失败")
    assert(type(err) == "string", "应给出失败原因")

    -- 请求缺 branch（branch 需调用方用随机源生成）
    out, err = gb.sip_build({
        method = "REGISTER", uri = "sip:a@b",
        host = "1.1.1.1", port = 5060,
        from_uri = "sip:1@b", to_uri = "sip:2@b",
        call_id = "c@1", cseq = 1,
    })
    assert(out == nil, "请求缺 branch 应失败")
end

--[[
响应走 from_raw 回抄时没有 from_uri。
此时若还要 Contact，绑定必须显式拿到 contact_user 或**干净地失败** ——
曾经这里直接 strlen(NULL)，点播 INVITE 的 200 OK 应答当场段错误。
]]
function t.test_sip_build_response_contact_without_from_uri()
    local base = {
        code = 200, reason = "OK",
        via_list = { "SIP/2.0/UDP 127.0.0.1:8199;rport;branch=z9hG4bKabc" },
        from_raw = "<sip:35020000002000000001@3502000000>;tag=xyz",
        to_raw   = "<sip:35020000001320000001@3502000000>",
        call_id  = "abc@test", cseq = 1, cseq_method = "INVITE",
        host = "192.168.0.4", port = 5160,
    }

    -- 有 contact_user：应正常构造出 Contact
    local cfg = {}
    for k, v in pairs(base) do cfg[k] = v end
    cfg.contact = true
    cfg.contact_user = "35020000001320000001"
    local built, err = gb.sip_build(cfg)
    assert(built ~= nil, "给了 contact_user 就应构造成功: " .. tostring(err))

    local status, msg = gb.sip_pop(built, 8192)
    assert(status == "ok")
    assert(msg.headers["contact"] ==
           "<sip:35020000001320000001@192.168.0.4:5160>",
           "Contact 应为显式给出的设备编码, 实际 " .. tostring(msg.headers["contact"]))

    -- 没 contact_user：应返回 nil + 原因，绝不能崩
    cfg.contact_user = nil
    local out, reason = gb.sip_build(cfg)
    assert(out == nil, "缺 contact_user 且无 from_uri 应失败")
    assert(type(reason) == "string", "应给出失败原因")
end

--[[ 摘要必须与真实平台接受的值一致——这是绑定是否正确用 C 层的关键证据 ]]
function t.test_sip_digest_matches_real_platform()
    local resp = gb.sip_digest(REAL_DIGEST_CFG)
    assert(resp == REAL_RESPONSE,
           "摘要应与平台接受值一致: 期望 " .. REAL_RESPONSE .. ", 实际 " .. tostring(resp))

    -- 密码错则不该相同
    local wrong = {}
    for k, v in pairs(REAL_DIGEST_CFG) do wrong[k] = v end
    wrong.password = "wrong_password"
    assert(gb.sip_digest(wrong) ~= REAL_RESPONSE, "密码错误时摘要不应相同")
end

--[[ 缺 qop 时应走 RFC 2069 兼容路径(与带 qop 结果不同) ]]
function t.test_sip_digest_without_qop()
    local cfg = {}
    for k, v in pairs(REAL_DIGEST_CFG) do cfg[k] = v end
    cfg.qop, cfg.nc, cfg.cnonce = nil, nil, nil

    local noqop = gb.sip_digest(cfg)
    assert(type(noqop) == "string" and #noqop == 32, "无 qop 也应能算出摘要")
    assert(noqop ~= REAL_RESPONSE, "无 qop 的结果应与带 qop 的不同")
end

--[[ 挑战解析：真实平台下发的那一条 ]]
function t.test_sip_parse_challenge_real()
    local ch = gb.sip_parse_challenge(REAL_CHALLENGE)
    assert(ch ~= nil, "应解析出挑战")
    assert(ch.realm == "3502000000")
    assert(ch.nonce == "73a1002c90df9b154be4ad7f4100fe75")
    assert(ch.algorithm == "MD5")
    assert(ch.qop == "auth")
    assert(ch.opaque == nil, "平台未下发 opaque, 应为 nil")
end

--[[ 挑战解析的失败路径 ]]
function t.test_sip_parse_challenge_rejects_non_digest()
    assert(gb.sip_parse_challenge("Basic realm=\"x\"") == nil, "Basic 方案应被拒")
    assert(gb.sip_parse_challenge("Digest nonce=\"n\"") == nil, "缺 realm 应被拒")
    assert(gb.sip_parse_challenge("Digest realm=\"r\"") == nil, "缺 nonce 应被拒")
end

--[[ Authorization 字段值应含全部必需参数 ]]
function t.test_sip_authorization_contains_required_params()
    local v = gb.sip_authorization(REAL_DIGEST_CFG)
    assert(type(v) == "string", "应返回字符串")
    assert(string.sub(v, 1, 7) == "Digest ", "应以 'Digest ' 开头")
    assert(string.find(v, 'username="35020000001320000001"', 1, true) ~= nil)
    assert(string.find(v, 'realm="3502000000"', 1, true) ~= nil)
    assert(string.find(v, REAL_RESPONSE, 1, true) ~= nil, "应含 response")
    assert(string.find(v, "qop=auth", 1, true) ~= nil)
    assert(string.find(v, "nc=00000001", 1, true) ~= nil)
end

--[[ 目录应答：单通道，含全部必选字段 ]]
function t.test_xml_build_catalog_single()
    local body = gb.xml_build_catalog({
        device_id = "35020000001320000001",
        sum_num   = 1,
        items = {
            {
                device_id    = "35020000001320000001",
                name         = "CH1",
                manufacturer = "LuatOS",
                model        = "Air8101",
                owner        = "Owner",
                civil_code   = "350200",
                address      = "Address",
                parent_id    = "35020000002000000001",
            },
        },
    }, 42)

    assert(type(body) == "string", "应构造成功")
    assert(string.find(body, "<CmdType>Catalog</CmdType>", 1, true) ~= nil)
    assert(string.find(body, "<SN>42</SN>", 1, true) ~= nil, "SN 应原样回填")
    assert(string.find(body, "<SumNum>1</SumNum>", 1, true) ~= nil)
    assert(string.find(body, '<DeviceList Num="1">', 1, true) ~= nil)
    assert(string.find(body, "<Name>CH1</Name>", 1, true) ~= nil)
    assert(string.find(body, "<RegisterWay>1</RegisterWay>", 1, true) ~= nil,
           "register_way 缺省应为 1")
    assert(string.find(body, "<Status>ON</Status>", 1, true) ~= nil,
           "status 缺省应为 ON")
end

--[[ 目录应答：Num 是本页条数，SumNum 是通道总数 —— 平台靠后者判断是否收全 ]]
function t.test_xml_build_catalog_pagination_semantics()
    local body = gb.xml_build_catalog({
        device_id = "35020000001320000001",
        sum_num   = 5,          -- 设备共 5 个通道
        items = {               -- 本页只带 2 条
            { device_id = "35020000001320000001", name = "CH1",
              manufacturer = "LuatOS", model = "M", owner = "O",
              civil_code = "350200", address = "A",
              parent_id = "35020000002000000001" },
            { device_id = "35020000001320000002", name = "CH2",
              manufacturer = "LuatOS", model = "M", owner = "O",
              civil_code = "350200", address = "A",
              parent_id = "35020000002000000001" },
        },
    }, 7)

    assert(type(body) == "string", "应构造成功")
    assert(string.find(body, "<SumNum>5</SumNum>", 1, true) ~= nil,
           "SumNum 必须是通道总数")
    assert(string.find(body, '<DeviceList Num="2">', 1, true) ~= nil,
           "Num 必须是本页条数")
end

--[[ 必选字段缺失应被拒 —— 平台解析不了残缺目录项，且失败表现很难反查 ]]
function t.test_xml_build_catalog_rejects_missing_required()
    local fields = { "device_id", "name", "manufacturer", "model",
                     "owner", "civil_code", "address", "parent_id" }
    for _, f in ipairs(fields) do
        local it = {
            device_id = "35020000001320000001", name = "CH1",
            manufacturer = "LuatOS", model = "M", owner = "O",
            civil_code = "350200", address = "A",
            parent_id = "35020000002000000001",
        }
        it[f] = nil
        local body, err = gb.xml_build_catalog({
            device_id = "35020000001320000001", sum_num = 1, items = { it },
        }, 1)
        assert(body == nil, "缺 " .. f .. " 时应失败")
        assert(type(err) == "string", "应给出失败原因")
    end
end

--[[ 目录应答的非法入参 ]]
function t.test_xml_build_catalog_rejects_bad_args()
    local good = {
        device_id = "35020000001320000001", name = "CH1",
        manufacturer = "LuatOS", model = "M", owner = "O",
        civil_code = "350200", address = "A",
        parent_id = "35020000002000000001",
    }

    -- items 为空
    local body = gb.xml_build_catalog({
        device_id = "d", sum_num = 0, items = {},
    }, 1)
    assert(body == nil, "空 items 应被拒")

    -- items 不是数组
    body = gb.xml_build_catalog({ device_id = "d", sum_num = 0, items = "x" }, 1)
    assert(body == nil, "items 非表应被拒")

    -- 缺 device_id
    body = gb.xml_build_catalog({ sum_num = 1, items = { good } }, 1)
    assert(body == nil, "缺 device_id 应被拒")

    -- 超出单页上限
    local many = {}
    for i = 1, 64 do many[i] = good end
    body = gb.xml_build_catalog({
        device_id = "d", sum_num = 64, items = many,
    }, 1)
    assert(body == nil, "超出单页上限应被拒")
end

--[[ 通道名中的特殊字符应被转义 ]]
function t.test_xml_build_catalog_escapes_name()
    local body = gb.xml_build_catalog({
        device_id = "35020000001320000001",
        sum_num   = 1,
        items = { {
            device_id = "35020000001320000001", name = "A&B<C>",
            manufacturer = "LuatOS", model = "M", owner = "O",
            civil_code = "350200", address = "A",
            parent_id = "35020000002000000001",
        } },
    }, 1)
    assert(type(body) == "string")
    assert(string.find(body, "<Name>A&amp;B&lt;C&gt;</Name>", 1, true) ~= nil,
           "特殊字符应被转义")
end

--[[ SSRC：按附录 C 生成并格式化为 10 位十进制 ]]
function t.test_ssrc_make_and_format()
    local ssrc = gb.ssrc_make(false, "3402000000", 1)
    assert(type(ssrc) == "number", "应返回数字")
    assert(gb.ssrc_format(ssrc) == "0000000001", "实时点播首位为 0")

    ssrc = gb.ssrc_make(true, "3402000000", 1)
    assert(gb.ssrc_format(ssrc) == "1000000001", "历史回放首位为 1")

    -- 非法入参
    assert(gb.ssrc_make(false, "1234", 1) == nil, "域不足 5 位应失败")
    assert(gb.ssrc_make(false, "3402000000", 10000) == nil, "序号越界应失败")
end

--[[ SDP：构造后能被本模块解析回 ]]
function t.test_sdp_build_and_parse_roundtrip()
    local sdp = gb.sdp_build({
        owner_id = "35020000001320000001",
        ip = "192.168.1.100",
        session_name = "Play",
        media = "video",
        port = 30000,
        payload_type = 96,
        rtpmap = "PS/90000",
        ssrc = 1000000001,
        has_ssrc = 1,
        direction = "recvonly",
    })
    assert(type(sdp) == "string", "SDP 应构造成功")
    assert(string.find(sdp, "m=video 30000 RTP/AVP 96", 1, true) ~= nil)
    assert(string.find(sdp, "a=rtpmap:96 PS/90000", 1, true) ~= nil)
    assert(string.find(sdp, "y=1000000001", 1, true) ~= nil, "必须有 y= 行")

    local s = gb.sdp_parse(sdp)
    assert(s ~= nil, "应能解析回")
    assert(s.media == "video")
    assert(s.port == 30000)
    assert(s.payload_type == 96)
    assert(s.rtpmap == "PS/90000")
    assert(s.ssrc == 1000000001)
    assert(s.session_name == "Play")
end

--[[ SDP：解析平台下发的多条 rtpmap，取与 m= 载荷类型匹配的那条 ]]
function t.test_sdp_parse_picks_matching_rtpmap()
    local sdp = "v=0\r\n" ..
                "o=35020000002000000001 0 0 IN IP4 192.168.1.200\r\n" ..
                "s=Playback\r\n" ..
                "c=IN IP4 192.168.1.200\r\n" ..
                "m=video 30200 RTP/AVP 96 98\r\n" ..
                "a=recvonly\r\n" ..
                "a=rtpmap:96 PS/90000\r\n" ..
                "a=rtpmap:98 H264/90000\r\n" ..
                "y=1000000123\r\n"
    local s = gb.sdp_parse(sdp)
    assert(s ~= nil)
    assert(s.payload_type == 96)
    assert(s.rtpmap == "PS/90000", "应取与 m= 匹配的那条, 实际 " .. tostring(s.rtpmap))
    assert(s.ssrc == 1000000123)
    assert(s.session_name == "Playback")
end

--[[ SDP：TCP 承载的 proto / setup / connection 往返 ]]
function t.test_sdp_tcp_carrier_roundtrip()
    local sdp = gb.sdp_build({
        owner_id = "35020000001320000001", ip = "192.168.0.4",
        session_name = "Play", media = "video", port = 31000,
        payload_type = 96, rtpmap = "PS/90000",
        ssrc = 1000000001, has_ssrc = 1, direction = "sendonly",
        proto = gb.PROTO_TCP,
        setup = gb.TCP_SETUP_PASSIVE,
        connection = gb.TCP_CONN_NEW,
    })
    assert(type(sdp) == "string", "TCP 承载的 SDP 应构造成功")
    assert(string.find(sdp, "m=video 31000 TCP/RTP/AVP 96", 1, true) ~= nil,
           "m= 应声明 TCP 承载")
    assert(string.find(sdp, "a=setup:passive", 1, true) ~= nil)
    assert(string.find(sdp, "a=connection:new", 1, true) ~= nil)

    local s = gb.sdp_parse(sdp)
    assert(s ~= nil)
    assert(s.proto == "TCP/RTP/AVP", "应解析回协议, 实际 " .. tostring(s.proto))
    assert(s.tcp == true, "tcp 应为 true")
    assert(s.setup == "passive")
    assert(s.connection == "new")
end

--[[ SDP：UDP 承载不应出现 setup/connection 行(平台会困惑) ]]
function t.test_sdp_udp_carrier_omits_tcp_attrs()
    local sdp = gb.sdp_build({
        owner_id = "35020000001320000001", ip = "192.168.0.4",
        session_name = "Play", media = "video", port = 31000,
        payload_type = 96, rtpmap = "PS/90000",
        proto = gb.PROTO_UDP,
        -- 即使误传了 setup/connection，也不该出现在 UDP 的 SDP 里
        setup = gb.TCP_SETUP_PASSIVE,
        connection = gb.TCP_CONN_NEW,
    })
    assert(type(sdp) == "string")
    assert(string.find(sdp, "m=video 31000 RTP/AVP 96", 1, true) ~= nil)
    assert(string.find(sdp, "a=setup", 1, true) == nil, "UDP 不该有 a=setup")
    assert(string.find(sdp, "a=connection", 1, true) == nil, "UDP 不该有 a=connection")

    local s = gb.sdp_parse(sdp)
    assert(s.tcp == false, "tcp 应为 false")
    assert(s.setup == nil, "未给 setup 时应为 nil")
end

--[[ sdp_is_tcp：大小写与短串 ]]
function t.test_sdp_is_tcp_tolerates_case_and_short()
    assert(gb.sdp_is_tcp("TCP/RTP/AVP") == true)
    assert(gb.sdp_is_tcp("tcp/rtp/avp") == true, "大小写应不敏感")
    assert(gb.sdp_is_tcp("RTP/AVP") == false)
    assert(gb.sdp_is_tcp("") == false)

    -- 解析平台下发的 TCP SDP：proto 原文保留，tcp 是判定结果
    local s = gb.sdp_parse(
        "v=0\r\n" ..
        "o=35020000002000000001 0 0 IN IP4 192.168.1.200\r\n" ..
        "s=Play\r\n" ..
        "c=IN IP4 192.168.1.200\r\n" ..
        "m=video 30200 tcp/RTP/AVP 96\r\n" ..
        "a=rtpmap:96 PS/90000\r\n" ..
        "a=setup:actpass\r\n" ..
        "y=1000000123\r\n")
    assert(s ~= nil)
    assert(s.proto == "tcp/RTP/AVP", "原文应保留, 实际 " .. tostring(s.proto))
    assert(s.tcp == true)
    assert(s.setup == "actpass")
    assert(s.connection == nil, "平台没给该行应为 nil")
end

-- ==================================================================
-- 访问单元规范化(里程碑 4.2)：参数集缓存与按需补插
-- ==================================================================

-- 拼一个 NAL：起始码 + 头字节 + 填充
local function nal(nal_type, payload, four_byte_sc)
    local sc = four_byte_sc and "\0\0\0\1" or "\0\0\1"
    return sc .. string.char(0x60 | nal_type) .. string.rep("x", payload)
end

--[[
起播必须等到 IDR：在那之前的帧接收端一律解不出，发出去只是浪费带宽。
但**参数集要留下** —— 它可能就藏在被丢弃的那个访问单元里。
]]
function t.test_nal_waits_for_idr_but_keeps_params()
    local h = gb.nal_new(false, true)
    assert(h ~= nil, "应能创建句柄")

    -- 参数集 + 一个 P 帧：这一帧要丢，但参数集要入缓存
    local au = nal(7, 5, true) .. nal(8, 3, true) .. nal(1, 8, true)
    assert(gb.nal_process(h, au) == nil, "没有 IDR 时应丢弃")
    local st = gb.nal_stats(h)
    assert(st.dropped_frames == 1, "应记一次丢弃")
    assert(st.has_params == true, "参数集必须留下 —— 否则后面的 IDR 补不出东西")

    -- 只带 IDR 的一帧：应当补上刚才学到的 SPS/PPS 再发
    local idr = nal(5, 20, true)
    local out = gb.nal_process(h, idr)
    assert(type(out) == "string", "IDR 应被发出")
    assert(#out > #idr, "应补上参数集(比原帧长)")

    --[[
    字节核算：补出来的应当**恰好**是"缓存的 SPS + 缓存的 PPS + 原帧"，
    不多不少。只断言"变长了"是不够的 —— 多补一份或少一段都不会被发现，
    而多补会让平台按参数集重新起流、少补直接解不出。
    ]]
    local sps_len = 4 + 1 + 5      -- 起始码 + 头字节 + 测试里的 SPS 载荷
    local pps_len = 4 + 1 + 3
    assert(#out == sps_len + pps_len + #idr,
           string.format("补出的总长应为 %d, 实际 %d",
                         sps_len + pps_len + #idr, #out))
    assert(string.sub(out, 1, 4) == "\0\0\0\1", "补出的参数集应带 4 字节起始码")
    assert(string.byte(out, 5) % 32 == 7, "补出的第一个应是 SPS")
    assert(string.byte(out, sps_len + 5) % 32 == 8, "补出的第二个应是 PPS")
    assert(string.sub(out, sps_len + pps_len + 1) == idr,
           "原帧应原样跟在参数集之后")

    st = gb.nal_stats(h)
    assert(st.injected == 1, "应记一次补插")
    assert(st.idr_frames == 1)
    assert(st.out_frames == 1)
end

--[[ 带了参数集的 IDR 不该重复补（省带宽，也避免与编码器发的版本不一致） ]]
function t.test_nal_does_not_inject_when_au_carries_params()
    local h = gb.nal_new(false, true)
    local au = nal(7, 5, true) .. nal(8, 3, true) .. nal(5, 16, true)

    local out = gb.nal_process(h, au)
    assert(out == au, "自带参数集时应原样透传")
    assert(gb.nal_stats(h).injected == 0, "不该补")
end

--[[ 3 字节起始码同样要认对 —— 4 字节起始码时按"起点+3"取头字节会读错 ]]
function t.test_nal_accepts_three_byte_start_code()
    local h = gb.nal_new(false, true)
    local au = nal(7, 4, false) .. nal(8, 3, false) .. nal(5, 12, false)
    local out = gb.nal_process(h, au)
    assert(out == au, "3 字节起始码的流也该原样透传")
    assert(gb.nal_stats(h).idr_frames == 1, "应认出 IDR")
end

--[[ H.265：类型在高 6 位，且 VPS/SPS/PPS 三者齐了才算有参数集 ]]
function t.test_nal_hevc_types()
    local h = gb.nal_new(true, true)

    -- 先只给 SPS+PPS(缺 VPS)，再加上 VPS 才算齐
    local sps = "\0\0\0\1" .. string.char(33 << 1) .. string.rep("s", 6)
    local pps = "\0\0\0\1" .. string.char(34 << 1) .. string.rep("p", 4)
    local vps = "\0\0\0\1" .. string.char(32 << 1) .. string.rep("v", 5)
    local idr = "\0\0\0\1" .. string.char(19 << 1) .. string.rep("i", 10)

    gb.nal_process(h, sps .. pps)
    assert(gb.nal_stats(h).has_params == false, "H.265 缺 VPS 不算参数集齐")

    gb.nal_process(h, vps)
    assert(gb.nal_stats(h).has_params == true, "VPS 到手后应算齐")

    local out = gb.nal_process(h, idr)
    assert(type(out) == "string", "IDR 应被发出")
    assert(#out > #idr, "应补上 VPS/SPS/PPS")
    assert(gb.nal_stats(h).injected == 1)
end

--[[ 无参数集可补时：原样发出并计数，不丢帧 ]]
function t.test_nal_without_params_still_sends()
    local h = gb.nal_new(false, false)      -- 不等 IDR
    local idr = nal(5, 10, true)
    local out = gb.nal_process(h, idr)
    assert(out == idr, "补不出参数集也应原样发，而不是丢掉")
    local st = gb.nal_stats(h)
    assert(st.injected == 0)
    assert(st.no_params == 1, "应记一笔，便于现场判断是不是编码器不发参数集")
end

--[[ 接口契约：非法入参、reset ]]
function t.test_nal_api_contract()
    local h = gb.nal_new(false, true)
    assert(gb.nal_process(h, "") == nil, "空帧应返回 nil")
    assert(gb.nal_process(h, string.rep("\1", 16)) == nil,
           "不含起始码的帧应返回 nil，且不崩")

    gb.nal_process(h, nal(7, 4, true) .. nal(8, 3, true) .. nal(5, 8, true))
    assert(gb.nal_stats(h).in_frames > 0)
    gb.nal_reset(h)
    local st = gb.nal_stats(h)
    assert(st.in_frames == 0, "reset 应清统计")
    assert(st.has_params == false, "reset 应清缓存")
end

--[[ PS 封装：流头与视频帧 ]]
function t.test_ps_build_video_frame()
    local head = gb.ps_stream_head({}, 0)
    assert(type(head) == "string", "流头应构造成功")
    -- 起始码 00 00 01 BA(BB 是系统头、BC 是 PSM)
    assert(string.byte(head, 1) == 0 and string.byte(head, 4) == 0xBA,
           "流头应以 Pack Header 起始码开头")

    local frame = string.rep("\0\0\0\1\x65", 1) .. string.rep("\xAA", 100)
    local ps = gb.ps_video({}, frame, 9000)
    assert(type(ps) == "string", "帧应封装成功")
    assert(#ps > #frame, "PS 应比原帧大(有封装开销)")
    assert(string.byte(ps, 4) == 0xBA, "每帧都应带 Pack Header")
    -- 载荷原样保留
    assert(string.sub(ps, #ps - 99) == string.rep("\xAA", 100), "载荷应原样透传")
end

--[[ info() 应给出配置建议值 ]]
function t.test_info_fields()
    local info = gb.info()
    assert(type(info) == "table", "info() 应返回表")
    assert(type(info.sip_buf_size) == "number" and info.sip_buf_size > 0)
    assert(type(info.max_channel) == "number" and info.max_channel > 0)
    assert(type(info.sip_local_port) == "number")
    assert(type(info.rtp_port_base) == "number")
end

--[[ 云台(PTZ)指令解码的绑定：素材与 C 层 tests/test_ptz.c 同源（按真实平台
     的构造算法算出），这里验"绑定没把 C 层用错" ]]
function t.test_ptz_parse_binding()
    assert(type(gb.ptz_parse) == "function", "固件太旧，没有 ptz_parse")

    -- 上：A5 0F 01 08 00 00 00 BD
    local p = gb.ptz_parse("A50F0108000000BD")
    assert(p ~= nil, "应能解析")
    assert(p.ok == true, "校验应通过")
    assert(p.kind == gb.PTZ_MOVE, "应归为方向/变倍类")
    assert(p.up == true and p.down == false and p.left == false and p.right == false)
    assert(p.pan_speed == 0 and p.tilt_speed == 0)

    -- 上左：组合值 0x0A，两个方向都要置位
    p = gb.ptz_parse("A50F010A5050005F")
    assert(p.up == true and p.left == true, "对角应是两位同时置位")

    -- 放大：速度在字节 6 的高 4 位
    p = gb.ptz_parse("A50F011000008045")
    assert(p.zoom_in == true and p.zoom_out == false)
    assert(p.zoom_speed == 8, "变倍速度应为 8，实际 " .. tostring(p.zoom_speed))

    -- 停止
    p = gb.ptz_parse("A50F0100000000B5")
    assert(p.kind == gb.PTZ_STOP, "应归为停止类")

    -- 调用预置位：号在 param2
    p = gb.ptz_parse("A50F01820005003C")
    assert(p.kind == gb.PTZ_PRESET)
    assert(p.param2 == 5, "预置位号应为 5，实际 " .. tostring(p.param2))

    -- 辅助开关
    p = gb.ptz_parse("A50F018C01000042")
    assert(p.kind == gb.PTZ_AUX and p.param1 == 1)

    -- FI 组
    p = gb.ptz_parse("A50F014132000028")
    assert(p.kind == gb.PTZ_FI and p.param1 == 50)

    -- 校验不过仍然解出结构（平台自己拼的包有已知偏差）
    p = gb.ptz_parse("A50F010800000000")
    assert(p ~= nil and p.ok == false, "校验应报 false")
    assert(p.up == true, "但动作仍应解出")

    -- 拒绝
    assert(gb.ptz_parse("B50F0108000000BD") == nil, "起始码不对应拒绝")
    assert(gb.ptz_parse("A50F0108000000B") == nil, "长度不足应拒绝")
    assert(gb.ptz_parse("hello") == nil, "非十六进制应拒绝")

    -- 常量都在
    for _, k in ipairs({ "PTZ_MOVE", "PTZ_STOP", "PTZ_FI", "PTZ_PRESET",
                         "PTZ_TOUR", "PTZ_SCAN", "PTZ_AUX",
                         "PTZ_B_UP", "PTZ_B_LEFT", "PTZ_B_ZOOM_IN" }) do
        assert(type(gb[k]) == "number", "缺常量 " .. k)
    end
end

--[[ 控制项常量都在；UNKNOWN 的值是 0，别被当成"没注册" ]]
function t.test_devctl_constants()
    for _, k in ipairs({ "DEVCTL_UNKNOWN", "DEVCTL_PTZ", "DEVCTL_DRAG_ZOOM_IN",
                         "DEVCTL_DRAG_ZOOM_OUT", "DEVCTL_HOME_POSITION",
                         "DEVCTL_TELE_BOOT", "DEVCTL_RECORD", "DEVCTL_GUARD",
                         "DEVCTL_ALARM", "DEVCTL_IFRAME" }) do
        assert(type(gb[k]) == "number", "缺常量 " .. k)
    end
    assert(gb.DEVCTL_UNKNOWN == 0, "UNKNOWN 约定为 0")
    -- 各分类不能撞值，否则分派会走错分支
    local seen = {}
    for _, k in ipairs({ "DEVCTL_UNKNOWN", "DEVCTL_PTZ", "DEVCTL_DRAG_ZOOM_IN",
                         "DEVCTL_DRAG_ZOOM_OUT", "DEVCTL_HOME_POSITION",
                         "DEVCTL_TELE_BOOT", "DEVCTL_RECORD", "DEVCTL_GUARD",
                         "DEVCTL_ALARM", "DEVCTL_IFRAME" }) do
        assert(seen[gb[k]] == nil, "常量撞值: " .. k)
        seen[gb[k]] = true
    end
end

--[[ 取任意元素：Control 类报文的字段随子类型变，故留了通用取值器 ]]
function t.test_xml_get_binding()
    assert(type(gb.xml_get) == "function", "固件太旧，没有 xml_get")
    local body = "<?xml version=\"1.0\"?>\r\n<Control>\r\n" ..
                 "<CmdType>DeviceControl</CmdType>\r\n<SN>1</SN>\r\n" ..
                 "<PTZCmd>A50F0108000000BD</PTZCmd>\r\n</Control>\r\n"
    assert(gb.xml_get(body, "PTZCmd") == "A50F0108000000BD", "应取出 PTZCmd")
    assert(gb.xml_get(body, "CmdType") == "DeviceControl")
    assert(gb.xml_get(body, "Nonexistent") == nil, "不存在的元素应返回 nil")
end

--[[ 通用 Result 应答：DeviceControl 要回 <Result>OK</Result> ]]
function t.test_xml_build_response_binding()
    assert(type(gb.xml_build_response) == "function")
    local ok = gb.xml_build_response("DeviceControl", 42, "35020000001320000001", "OK")
    assert(type(ok) == "string", "应构造出报文")
    assert(ok:find("<CmdType>DeviceControl</CmdType>", 1, true) ~= nil)
    assert(ok:find("<SN>42</SN>", 1, true) ~= nil, "SN 应原样回填")
    assert(ok:find("<Result>OK</Result>", 1, true) ~= nil)
    -- 缺省 result 就是 OK
    local d = gb.xml_build_response("DeviceControl", 1, "35020000001320000001")
    assert(d:find("<Result>OK</Result>", 1, true) ~= nil)
end

--[[ 扩展信息：DeviceInfo 的 <Info> 可出现多次(3.3 补全的完整字段) ]]
function t.test_xml_build_device_info_with_infos()
    local body = gb.xml_build_device_info({
        device_id = "35020000001320000001",
        name      = "IPC",
        channel   = 1,
        infos     = { "RegionCode", "Owner" },
    }, 9)

    assert(type(body) == "string", "应构造成功")
    assert(body:find("<Info>RegionCode</Info>", 1, true) ~= nil)
    assert(body:find("<Info>Owner</Info>", 1, true) ~= nil)
    -- 顺序应与传入一致
    assert(body:find("<Info>RegionCode</Info>", 1, true) <
           body:find("<Info>Owner</Info>", 1, true), "Info 顺序应与传入一致")
end

--[[ 不给 infos 时不应出现 <Info> 元素 ]]
function t.test_xml_build_device_info_without_infos()
    local body = gb.xml_build_device_info({
        device_id = "35020000001320000001",
        channel   = 1,
    }, 9)
    assert(type(body) == "string")
    assert(body:find("<Info>", 1, true) == nil, "没给 infos 就不该写 <Info>")
end

--[[ 告警设备列表：duty_status 逐条写出，没有时自闭合 ]]
function t.test_xml_build_device_status_alarmstatus()
    local body = gb.xml_build_device_status({
        device_id = "35020000001320000001",
        alarms    = {
            { device_id = "35020000001320000001", duty_status = "ONDUTY" },
            { device_id = "35020000001320000002", duty_status = "ALARM" },
        },
    }, 11)

    assert(type(body) == "string", "应构造成功")
    assert(body:find('<Alarmstatus Num="2">', 1, true) ~= nil, "Num 应是告警条数")
    assert(body:find("<DutyStatus>ONDUTY</DutyStatus>", 1, true) ~= nil)
    assert(body:find("<DutyStatus>ALARM</DutyStatus>", 1, true) ~= nil)

    local empty = gb.xml_build_device_status({ device_id = "d1" }, 11)
    assert(empty:find('<Alarmstatus Num="0"/>', 1, true) ~= nil)
end

--[[ 报警主动上报：报文形状与平台侧解析的字段一致(Notify/Alarm) ]]
function t.test_xml_build_alarm_binding()
    assert(type(gb.xml_build_alarm) == "function", "固件太旧，没有 xml_build_alarm")

    local body = gb.xml_build_alarm({
        device_id   = "35020000001320000001",
        priority    = 1,
        method      = 5,                      -- 视频报警
        time        = "2026-09-18T15:30:00",
        description = "MotionDetected",
        alarm_type  = "2",                    -- method=5 时是"移动侦测"
    }, 1001)

    assert(type(body) == "string", "应构造成功")
    assert(body:find("<Notify>", 1, true) ~= nil, "根元素必须是 Notify(主动上报)")
    assert(body:find("<CmdType>Alarm</CmdType>", 1, true) ~= nil)
    assert(body:find("<SN>1001</SN>", 1, true) ~= nil)
    assert(body:find("<AlarmPriority>1</AlarmPriority>", 1, true) ~= nil)
    assert(body:find("<AlarmMethod>5</AlarmMethod>", 1, true) ~= nil)
    assert(body:find("<AlarmTime>2026-09-18T15:30:00</AlarmTime>", 1, true) ~= nil)
    assert(body:find("<AlarmType>2</AlarmType>", 1, true) ~= nil)
end

--[[
报警时间格式错必须被拒：平台的解析链最后一环没有兜底，格式不对会让
**对端**抛异常，本端只表现为"报警没进去"。
]]
function t.test_xml_build_alarm_rejects_bad_time()
    local base = { device_id = "d1", priority = 1, method = 2 }

    for _, bad in ipairs({
        "2026-09-18 15:30:00",       -- 中间是空格不是 T
        "2026-09-18T15:30",          -- 缺秒
        "2026-09-18T15:30:00+08:00", -- 带时区
        "2026-13-01T00:00:00",       -- 月份越界
        "", nil,
    }) do
        local cfg = { device_id = base.device_id, priority = base.priority,
                      method = base.method, time = bad }
        local body, err = gb.xml_build_alarm(cfg, 1)
        assert(body == nil, "非法时间应被拒: " .. tostring(bad))
        assert(type(err) == "string", "应给出失败原因")
    end

    -- 缺 device_id 同样拒绝
    local body = gb.xml_build_alarm({
        priority = 1, method = 2, time = "2026-09-18T15:30:00",
    }, 1)
    assert(body == nil, "缺 device_id 应被拒")
end

--[[ 控制项识别：拉框缩放(2022) 与云台要走不同的分支 ]]
function t.test_devctl_parse_binding()
    assert(type(gb.devctl_parse) == "function", "固件太旧，没有 devctl_parse")

    local drag = gb.devctl_parse(
        "<Control><CmdType>DeviceControl</CmdType>" ..
        "<DragZoomIn><Length>100</Length><Width>200</Width>" ..
        "<MidPointX>300</MidPointX><MidPointY>400</MidPointY>" ..
        "<LengthX>500</LengthX><LengthY>600</LengthY></DragZoomIn></Control>")
    assert(drag ~= nil, "应识别成功")
    assert(drag.kind == gb.DEVCTL_DRAG_ZOOM_IN, "应识别为拉框放大")
    assert(drag.length == 100 and drag.width == 200, "参数应逐个取到")
    assert(drag.mid_point_x == 300 and drag.mid_point_y == 400)
    assert(drag.length_x == 500 and drag.length_y == 600)
    assert(drag.needs_response == false, "拉框缩放平台不等应答")

    local ptz = gb.devctl_parse(
        "<Control><PTZCmd>A50F0108000000BD</PTZCmd></Control>")
    assert(ptz.kind == gb.DEVCTL_PTZ, "应识别为云台")
    assert(ptz.ptz_hex == "A50F0108000000BD", "应带出十六进制串")

    -- 不认识的控制项归 UNKNOWN，而不是报错
    local unknown = gb.devctl_parse("<Control><SomeFutureCmd>1</SomeFutureCmd></Control>")
    assert(unknown ~= nil and unknown.kind == gb.DEVCTL_UNKNOWN)
end

--[[ 看守位(2022)：平台会等应答，且 0 是合法取值 ]]
function t.test_devctl_home_position_binding()
    local d = gb.devctl_parse(
        "<Control><HomePosition><Enabled>1</Enabled>" ..
        "<ResetTime>30</ResetTime><PresetIndex>5</PresetIndex></HomePosition></Control>")

    assert(d.kind == gb.DEVCTL_HOME_POSITION)
    assert(d.enabled == 1 and d.reset_time == 30 and d.preset_index == 5)
    assert(d.needs_response == true, "看守位平台会等 <Result>")

    -- 平台没给的可选字段是 -1，不能与合法的 0 混为一谈
    local zero = gb.devctl_parse("<Control><HomePosition><Enabled>0</Enabled>" ..
                                 "<ResetTime>0</ResetTime></HomePosition></Control>")
    assert(zero.reset_time == 0, "0 是合法取值")
    assert(zero.preset_index == -1, "没给的才是 -1")
end

--[[
xml_has 挡掉的是 xml_get 的两种"看走眼"：内容超容量、以及自闭合元素。
（注意 xml_get **不是**取不到容器内容 —— 容器内容没超容量时它会原样返回
里面那段 XML。这点曾经解释错过一次。）
]]
function t.test_xml_has_binding()
    assert(type(gb.xml_has) == "function", "固件太旧，没有 xml_has")

    local body = "<Control><DragZoomIn><Length>1</Length></DragZoomIn></Control>"
    assert(gb.xml_has(body, "DragZoomIn") == true)
    assert(gb.xml_has(body, "DragZoomOut") == false)

    -- 自闭合元素：xml_get 取不到文本，xml_has 认得出
    local selfclose = "<Control><SnapShot/></Control>"
    assert(gb.xml_has(selfclose, "SnapShot") == true, "自闭合也算在")
    assert(gb.xml_get(selfclose, "SnapShot") == nil, "自闭合没有文本可取")

    -- 内容超过取值缓冲(256 字节)：xml_get 返回 nil，看着像"不存在"
    local big = "<Control><HomePosition><Pad>" ..
                string.rep("x", 400) ..
                "</Pad><Enabled>1</Enabled></HomePosition></Control>"
    assert(gb.xml_get(big, "HomePosition") == nil, "内容超缓冲时 xml_get 取不到")
    assert(gb.xml_has(big, "HomePosition") == true, "但元素确实在")

    assert(gb.xml_has("<C><SNMP>1</SNMP></C>", "SN") == false, "不能被前缀命中")
end

return t
