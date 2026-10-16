--- exsipproto 的 GB28181 扩展测试模块
-- @module exsipproto_gb28181_test
-- 纯协议层测试，无需网络与真实 SIP 服务器。
--
-- 覆盖的是 **GB28181 迁移到 Lua 后新增在 exsipproto 的那几个口子**：
--   pop_message  三态切包 + 可选容忍缺失 Content-Length（GB 的 UDP 上平台常不发）、
--                max_msg 上限、保活空行
--   build_via    两个开关（branch_prefix / rport_first），默认值与旧行为一致
--   build_name_addr / uri_user / parse_head  报文拼装与保序头解析
--
-- 与 testcase/unit/net/gb28181/scripts/gb28181_sip_test.lua 的分工：那边测
-- exgb28181sip 这个 GB 专用层（含与冻结的 C 黄金报文逐字节比对）；这边测它脚下
-- 的通用原语在本库内**不回归** —— exsipclient 也走同一个 exsipproto。

local sys = require("sys")
local proto = require("exsipproto")

local exsipproto_gb28181_test = {}

-- 一条最小可用报文（头部以空行结束）
local HEAD = "MESSAGE sip:a@b SIP/2.0\r\nCall-ID: x\r\n"

--- 头部没收到空行：应报 need_more，且把原缓冲原样还回来（调用方继续累积）
function exsipproto_gb28181_test.test_pop_message_need_more_on_partial_head()
    log.info("exsipproto_gb28181_test", "pop_message partial head")
    local status, head, body, rest = proto.pop_message(HEAD, { max_msg = 8192 })
    assert(status == "need_more", "半包应 need_more, 实际 " .. tostring(status))
    assert(head == nil, "非 ok 不应给头部")
    assert(body == nil, "非 ok 不应给消息体")
    assert(rest == HEAD, "need_more 时应原样返回缓冲")
    log.info("exsipproto_gb28181_test", "pop_message partial head PASS")
end

--- 收全了头部但消息体还差一截：同样 need_more，不能把半条消息放出去
function exsipproto_gb28181_test.test_pop_message_need_more_on_partial_body()
    log.info("exsipproto_gb28181_test", "pop_message partial body")
    local raw = HEAD .. "Content-Length: 10\r\n\r\nabc"   -- 只到了 3 字节
    local status, _, _, rest = proto.pop_message(raw, { max_msg = 8192 })
    assert(status == "need_more", "消息体不全应 need_more, 实际 " .. tostring(status))
    assert(rest == raw, "need_more 时应原样返回缓冲")
    log.info("exsipproto_gb28181_test", "pop_message partial body PASS")
end

--- GB28181 的平台在 UDP 上常不发 Content-Length：默认严格（exsipclient 依赖），
--- 打开 allow_missing_content_length 才容忍（GB 侧走这条）
function exsipproto_gb28181_test.test_pop_message_missing_content_length()
    log.info("exsipproto_gb28181_test", "pop_message missing content-length")
    local raw = HEAD .. "\r\n"

    local status, _, _, _, err = proto.pop_message(raw, { max_msg = 8192 })
    assert(status == "bad", "默认应严格拒绝, 实际 " .. tostring(status))
    assert(err == "missing_content_length", "原因应为 missing_content_length, 实际 " .. tostring(err))

    local st, head, body, rest = proto.pop_message(raw, {
        allow_missing_content_length = true, max_msg = 8192,
    })
    assert(st == "ok", "容忍开关打开后应 ok, 实际 " .. tostring(st))
    assert(body == "", "无 Content-Length 时消息体应为空串")
    assert(rest == "", "应恰好消费整条")
    assert(head:find("Call-ID: x", 1, true) ~= nil, "头部应原样给出")
    log.info("exsipproto_gb28181_test", "pop_message missing content-length PASS")
end

--- Content-Length 非数字：按畸形处理，不能当成 0 悄悄放行
function exsipproto_gb28181_test.test_pop_message_rejects_non_numeric_content_length()
    log.info("exsipproto_gb28181_test", "pop_message non-numeric content-length")
    local raw = HEAD .. "Content-Length: abc\r\n\r\n"
    local status, _, _, _, err = proto.pop_message(raw, {
        allow_missing_content_length = true, max_msg = 8192,
    })
    assert(status == "bad", "非数字应 bad, 实际 " .. tostring(status))
    assert(err == "invalid_content_length", "原因应为 invalid_content_length, 实际 " .. tostring(err))
    log.info("exsipproto_gb28181_test", "pop_message non-numeric content-length PASS")
end

--- 重复的 Content-Length：值一致则容忍（有些实现爱重复发），冲突则拒绝
function exsipproto_gb28181_test.test_pop_message_duplicate_content_length()
    log.info("exsipproto_gb28181_test", "pop_message duplicate content-length")

    local same = HEAD .. "Content-Length: 2\r\nContent-Length: 2\r\n\r\nhi"
    local st = proto.pop_message(same, { max_msg = 8192 })
    assert(st == "ok", "值一致的重复应容忍, 实际 " .. tostring(st))

    local conflict = HEAD .. "Content-Length: 2\r\nContent-Length: 3\r\n\r\nhi"
    local status, _, _, _, err = proto.pop_message(conflict, { max_msg = 8192 })
    assert(status == "bad", "值冲突应 bad, 实际 " .. tostring(status))
    assert(err == "conflicting_content_length", "原因应为 conflicting_content_length, 实际 " .. tostring(err))
    log.info("exsipproto_gb28181_test", "pop_message duplicate content-length PASS")
end

--- 超大 Content-Length：判畸形，防止对端用一个数字把本机缓冲撑爆
function exsipproto_gb28181_test.test_pop_message_rejects_oversized()
    log.info("exsipproto_gb28181_test", "pop_message oversized")
    local raw = HEAD .. "Content-Length: 2000000000\r\n\r\nshort"
    local status, _, _, _, err = proto.pop_message(raw, { max_msg = 8192 })
    assert(status == "bad", "超大 Content-Length 应 bad, 实际 " .. tostring(status))
    assert(err == "sip_message_too_large", "原因应为 sip_message_too_large, 实际 " .. tostring(err))

    -- 连头部都还没收完，但缓冲本身已超上限 —— 同样要判畸形（否则会无限涨）
    local big = string.rep("X", 100)
    local st, _, _, _, e2 = proto.pop_message(big, { max_msg = 50 })
    assert(st == "bad" and e2 == "sip_message_too_large", "缓冲超上限应 bad")
    log.info("exsipproto_gb28181_test", "pop_message oversized PASS")
end

--- 粘包：一次返回一条，剩余流还给调用方接着切
function exsipproto_gb28181_test.test_pop_message_sticky_packets()
    log.info("exsipproto_gb28181_test", "pop_message sticky packets")
    local first  = HEAD .. "Content-Length: 2\r\n\r\nhi"
    local second = "MESSAGE sip:c@d SIP/2.0\r\nCall-ID: y\r\nContent-Length: 0\r\n\r\n"

    local st, _, body, rest = proto.pop_message(first .. second, { max_msg = 8192 })
    assert(st == "ok", "第一条应能切出")
    assert(body == "hi", "第一条的消息体应为 hi, 实际 " .. tostring(body))
    assert(rest == second, "剩余流应恰好是第二条")

    local st2, _, body2, rest2 = proto.pop_message(rest, { max_msg = 8192 })
    assert(st2 == "ok" and body2 == "" and rest2 == "", "第二条应能接着切出")
    log.info("exsipproto_gb28181_test", "pop_message sticky packets PASS")
end

--- 裸 LF 分界（有些对端只发 \n\n）：也要认
function exsipproto_gb28181_test.test_pop_message_bare_lf_separator()
    log.info("exsipproto_gb28181_test", "pop_message bare LF")
    local raw = "MESSAGE sip:a@b SIP/2.0\nCall-ID: x\nContent-Length: 0\n\n"
    local st, _, _, rest = proto.pop_message(raw, { max_msg = 8192 })
    assert(st == "ok", "裸 LF 分界应能识别, 实际 " .. tostring(st))
    assert(rest == "", "应恰好消费整条")
    log.info("exsipproto_gb28181_test", "pop_message bare LF PASS")
end

--- TCP 保活空行不属于任何一条报文：应被跳过
function exsipproto_gb28181_test.test_pop_message_skips_keepalive_crlf()
    log.info("exsipproto_gb28181_test", "pop_message keepalive CRLF")
    local raw = "\r\n\r\n" .. HEAD .. "Content-Length: 0\r\n\r\n"
    local st, head, _, rest = proto.pop_message(raw, { max_msg = 8192 })
    assert(st == "ok", "带前置保活空行应仍能切出, 实际 " .. tostring(st))
    assert(rest == "", "保活空行应被跳过而不是留在剩余流里")
    assert(head:sub(1, 1) == "M", "起始行不应残留空行")
    log.info("exsipproto_gb28181_test", "pop_message keepalive CRLF PASS")
end

--- 空输入不该崩（真机上 TCP 刚连上、缓冲区还是空的时会走到）
function exsipproto_gb28181_test.test_pop_message_empty_input()
    log.info("exsipproto_gb28181_test", "pop_message empty input")
    local st, _, _, rest = proto.pop_message("", { max_msg = 8192 })
    assert(st == "need_more", "空输入应 need_more, 实际 " .. tostring(st))
    assert(rest == "", "剩余应为空串")
    log.info("exsipproto_gb28181_test", "pop_message empty input PASS")
end

--- parse_head：保序、留重复头（响应要回抄多条 Via），map 取最后一个
function exsipproto_gb28181_test.test_parse_head_order_and_duplicates()
    log.info("exsipproto_gb28181_test", "parse_head order")
    local head = "Call-ID: c1\r\nVia: a\r\nVia: b\r\ncseq: 2 MESSAGE\r\n\r\n"
    local ph = proto.parse_head(head, { max_headers = 8 })

    assert(ph.count == 4, "应解析出 4 条头, 实际 " .. tostring(ph.count))
    assert(ph.list[1].name == "Call-ID", "list 应按线上顺序")
    assert(ph.list[2].name == "Via" and ph.list[2].value == "a", "第一条 Via")
    assert(ph.list[3].name == "Via" and ph.list[3].value == "b", "重复的 Via 必须留住")
    assert(ph.map["call-id"] == "c1", "map 的键应为小写")
    assert(ph.map["cseq"] == "2 MESSAGE", "map 的值应保留前导空格之后的内容")
    log.info("exsipproto_gb28181_test", "parse_head order PASS")
end

--- parse_head：头数上限 —— 超了截断，不为一个"永不结束的头"无限吃内存
function exsipproto_gb28181_test.test_parse_head_max_headers()
    log.info("exsipproto_gb28181_test", "parse_head max_headers")
    local head = "A: 1\r\nB: 2\r\nC: 3\r\n\r\n"
    local ph = proto.parse_head(head, { max_headers = 2 })
    assert(ph.count == 2, "应被截断到 2 条, 实际 " .. tostring(ph.count))

    -- 非字符串输入不崩
    local empty = proto.parse_head(nil)
    assert(empty.count == 0 and #empty.list == 0, "非字符串应返回空结构")
    log.info("exsipproto_gb28181_test", "parse_head max_headers PASS")
end

--- build_via 默认行为不变（默认 magic cookie + rport 在末尾）—— 这是不回归的判据
function exsipproto_gb28181_test.test_build_via_defaults_unchanged()
    log.info("exsipproto_gb28181_test", "build_via defaults")
    local v = proto.build_via({
        transport = "UDP", local_ip = "192.168.0.13", local_port = 5160, branch = "abc",
    })
    assert(v == "SIP/2.0/UDP 192.168.0.13:5160;branch=z9hG4bKabc;rport",
           "默认应带 magic cookie 且 rport 在末尾, 实际 " .. v)
    log.info("exsipproto_gb28181_test", "build_via defaults PASS")
end

--- 两个开关：branch_prefix="" 不加前缀；rport_first=true 把 rport 挪到 branch 前面
--- （GB28181 侧要的正是这个形态，与 C 的 format_via 逐字符一致）
function exsipproto_gb28181_test.test_build_via_switches()
    log.info("exsipproto_gb28181_test", "build_via switches")
    local v = proto.build_via({
        transport = "UDP", local_ip = "192.168.0.13", local_port = 5160,
        branch = "abc", branch_prefix = "", rport_first = true,
    })
    assert(v == "SIP/2.0/UDP 192.168.0.13:5160;rport;branch=abc", "实际 " .. v)

    -- TCP 没有 rport 语义：两个开关都不该让它冒出来
    local t = proto.build_via({
        transport = "TCP", local_ip = "192.168.0.13", local_port = 5160,
        branch = "abc", branch_prefix = "", rport_first = true,
    })
    assert(t == "SIP/2.0/TCP 192.168.0.13:5160;branch=abc", "TCP 不应带 rport, 实际 " .. t)
    log.info("exsipproto_gb28181_test", "build_via switches PASS")
end

--- 名字地址：有/无 tag；uri 为空也不能拼出个半截字符串
function exsipproto_gb28181_test.test_build_name_addr()
    log.info("exsipproto_gb28181_test", "build_name_addr")
    assert(proto.build_name_addr("sip:a@b", "t1") == "<sip:a@b>;tag=t1")
    assert(proto.build_name_addr("sip:a@b") == "<sip:a@b>", "无 tag 时不应多出分号")
    assert(proto.build_name_addr("sip:a@b", "") == "<sip:a@b>", "空 tag 等同不给")
    assert(proto.build_name_addr(nil) == "<>", "空 uri 应给出空尖括号而不是崩")
    log.info("exsipproto_gb28181_test", "build_name_addr PASS")
end

--- uri_user：名字地址 / 带参数 / sips / host-only 四种形态
function exsipproto_gb28181_test.test_uri_user()
    log.info("exsipproto_gb28181_test", "uri_user")
    assert(proto.uri_user("sip:35020000001320000001@3502000000") == "35020000001320000001")
    assert(proto.uri_user("<sip:35020000001320000001@3502000000>;tag=x") == "35020000001320000001",
           "名字地址应在尖括号内取 user")
    assert(proto.uri_user("sips:alice@example.com") == "alice", "sips 的 scheme 也要跳掉")

    -- host-only：';' 或 '?' 先于 '@'，说明没有 user 部分
    assert(proto.uri_user("sip:example.com;transport=tcp") == nil, "host-only 应返回 nil")
    assert(proto.uri_user("sip:example.com") == nil, "无 @ 应返回 nil")
    assert(proto.uri_user("") == nil and proto.uri_user(nil) == nil, "空输入应返回 nil")
    log.info("exsipproto_gb28181_test", "uri_user PASS")
end

return exsipproto_gb28181_test
