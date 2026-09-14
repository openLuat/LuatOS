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

--[[ info() 应给出配置建议值 ]]
function t.test_info_fields()
    local info = gb.info()
    assert(type(info) == "table", "info() 应返回表")
    assert(type(info.sip_buf_size) == "number" and info.sip_buf_size > 0)
    assert(type(info.max_channel) == "number" and info.max_channel > 0)
    assert(type(info.sip_local_port) == "number")
    assert(type(info.rtp_port_base) == "number")
end

return t
