--- exsipproto G.729 协商测试模块
-- @module exsipproto_g729_test
-- 纯协议层测试，无需网络与真实 SIP 服务器。
-- 真机/PBX 端到端互通（microSIP、Asterisk 等）需手动验证：
--   1. exsip.init({..., codecs = {"G729", "PCMU", "PCMA"}})
--   2. 对端强制或优先 G.729，确认 INVITE/200 SDP 中 m=audio 携带 18 且选中 G729
--   3. 通话双向语音正常，voip.stats() 的 tx/rx 包计数持续增长、rx_bad_payload 不增长

local sys = require("sys")
local proto = require("exsipproto")

local exsipproto_g729_test = {}

local function list_has(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

--- 编解码名称规范化：G729 及各种别名
function exsipproto_g729_test.test_normalize_codec_name()
    log.info("exsipproto_g729_test", "normalize codec names")
    assert(proto.normalize_codec_name("G729") == "G729", "G729 should normalize to G729")
    assert(proto.normalize_codec_name("g729") == "G729", "lowercase g729 should normalize")
    assert(proto.normalize_codec_name("G.729") == "G729", "G.729 alias should normalize")
    assert(proto.normalize_codec_name("G729A") == "G729", "G729A alias should normalize")
    assert(proto.normalize_codec_name("G729B") == "G729", "G729B alias should normalize")
    assert(proto.normalize_codec_name("PCMU") == "PCMU", "PCMU regression")
    assert(proto.normalize_codec_name("OPUS") == nil, "unsupported codec should return nil")
    log.info("exsipproto_g729_test", "normalize codec names PASS")
end

--- payload type 映射：G729 静态 PT 18
function exsipproto_g729_test.test_codec_payload_type()
    log.info("exsipproto_g729_test", "codec payload type")
    assert(proto.codec_payload_type("G729") == 18, "G729 payload type should be 18")
    assert(proto.codec_payload_type("G.729") == 18, "G.729 alias payload type should be 18")
    assert(proto.codec_payload_type("PCMU") == 0, "PCMU payload type regression")
    assert(proto.codec_payload_type("PCMA") == 8, "PCMA payload type regression")
    assert(proto.codec_payload_type("G723") == nil, "unsupported codec should return nil")
    log.info("exsipproto_g729_test", "codec payload type PASS")
end

--- 编解码列表规范化：去重、别名合并、默认值不变
function exsipproto_g729_test.test_normalize_codec_list()
    log.info("exsipproto_g729_test", "normalize codec list")
    local out = proto.normalize_codec_list({"g729", "PCMU", "G729A", "pcmu"})
    assert(#out == 2, "should dedup to 2 codecs, got " .. #out)
    assert(out[1] == "G729" and out[2] == "PCMU", "order should follow input: G729,PCMU")
    local dft = proto.normalize_codec_list({})
    assert(#dft == 2 and dft[1] == "PCMU" and dft[2] == "PCMA", "default list should stay PCMU,PCMA")
    log.info("exsipproto_g729_test", "normalize codec list PASS")
end

--- build_sdp：G729 出现在 m=audio 且带 rtpmap 与 annexb=no
function exsipproto_g729_test.test_build_sdp_g729()
    log.info("exsipproto_g729_test", "build sdp with G729")
    local sdp = proto.build_sdp({
        local_ip = "192.168.1.10",
        media = { local_rtp_port = 40000, codecs = { "G729", "PCMU" }, ptime = 20 }
    }, "sendrecv")
    assert(type(sdp) == "string" and #sdp > 0, "build_sdp should return sdp text")
    assert(sdp:find("m=audio 40000 RTP/AVP 18 0\r\n", 1, true) ~= nil, "m=audio should list 18 0, sdp:\n" .. sdp)
    assert(sdp:find("a=rtpmap:18 G729/8000\r\n", 1, true) ~= nil, "should carry rtpmap for G729")
    assert(sdp:find("a=fmtp:18 annexb=no\r\n", 1, true) ~= nil, "should carry fmtp annexb=no")
    assert(sdp:find("a=rtpmap:0 PCMU/8000\r\n", 1, true) ~= nil, "PCMU rtpmap regression")
    log.info("exsipproto_g729_test", "build sdp with G729 PASS")
end

--- parse_sdp：静态 PT 18 无需 rtpmap 即可识别
function exsipproto_g729_test.test_parse_sdp_static_pt18()
    log.info("exsipproto_g729_test", "parse sdp static pt 18")
    local sdp = table.concat({
        "v=0\r\n", "o=- 0 0 IN IP4 192.168.1.20\r\n", "s=-\r\n",
        "c=IN IP4 192.168.1.20\r\n", "t=0 0\r\n",
        "m=audio 5000 RTP/AVP 18 0 8\r\n",
        "a=ptime:20\r\n", "a=sendrecv\r\n"
    })
    local out = proto.parse_sdp(sdp)
    assert(out ~= nil, "parse_sdp failed")
    assert(out.audio_port == 5000, "audio port mismatch")
    assert(list_has(out.codecs, "G729"), "static PT 18 should map to G729")
    assert(list_has(out.codecs, "PCMU") and list_has(out.codecs, "PCMA"), "static PT 0/8 regression")
    assert(proto.codec_payload_type("G729") == 18, "payload type sanity")
    log.info("exsipproto_g729_test", "parse sdp static pt 18 PASS")
end

--- parse_sdp：动态 PT + rtpmap，含别名写法
function exsipproto_g729_test.test_parse_sdp_rtpmap_alias()
    log.info("exsipproto_g729_test", "parse sdp dynamic rtpmap aliases")
    local sdp = table.concat({
        "v=0\r\n", "o=- 0 0 IN IP4 192.168.1.20\r\n", "s=-\r\n",
        "c=IN IP4 192.168.1.20\r\n", "t=0 0\r\n",
        "m=audio 5000 RTP/AVP 96 97 98 0\r\n",
        "a=rtpmap:96 G729/8000\r\n",
        "a=rtpmap:97 G.729/8000\r\n",
        "a=rtpmap:98 G729A/8000\r\n",
        "a=sendrecv\r\n"
    })
    local out = proto.parse_sdp(sdp)
    assert(out ~= nil, "parse_sdp failed")
    assert(list_has(out.codecs, "G729"), "dynamic rtpmap G729 should be recognized")
    assert(list_has(out.codecs, "PCMU"), "PCMU regression")
    log.info("exsipproto_g729_test", "parse sdp dynamic rtpmap aliases PASS")
end

--- pick_common_codec：本地列表顺序即优先级
function exsipproto_g729_test.test_pick_common_codec()
    log.info("exsipproto_g729_test", "pick common codec priority")
    local picked = proto.pick_common_codec({ "G729", "PCMU" }, { "PCMU", "G729" })
    assert(picked == "G729", "local preference should win, got " .. tostring(picked))
    picked = proto.pick_common_codec({ "PCMU", "PCMA" }, { "G729" })
    assert(picked == nil, "no common codec should return nil")
    picked = proto.pick_common_codec({ "PCMU" }, { "G.729", "PCMU" })
    assert(picked == "PCMU", "alias on remote side should not break matching")
    log.info("exsipproto_g729_test", "pick common codec priority PASS")
end

--- build_media_session：端到端协商结果为 G729 且 payload_type=18
function exsipproto_g729_test.test_build_media_session_g729()
    log.info("exsipproto_g729_test", "build media session with G729")
    local session, err = proto.build_media_session({
        call_id = "call-1",
        remote_sdp = { conn_ip = "192.168.1.20", audio_port = 5000, codecs = { "G729", "PCMU" } },
        local_codecs = { "G729", "PCMU" },
        local_rtp_port = 40000,
        ptime = 20
    })
    assert(session ~= nil, "build_media_session failed: " .. tostring(err))
    assert(session.codec == "G729", "selected codec should be G729, got " .. tostring(session.codec))
    assert(session.payload_type == 18, "payload type should be 18, got " .. tostring(session.payload_type))
    assert(session.sample_rate == 8000 and session.channels == 1, "PCM format should stay 8kHz mono")
    assert(session.remote_port == 5000, "remote port mismatch")
    log.info("exsipproto_g729_test", "build media session with G729 PASS")
end

return exsipproto_g729_test
