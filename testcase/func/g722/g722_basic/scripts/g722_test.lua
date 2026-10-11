--- g722编解码测试模块
-- @module g722_test

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local g722_test = {}

-- 夹具由上游 libg722 直接生成: 32000字节PCM(16bit/16kHz/单声道, 1秒) -> 8000字节码流
local PCM_FILE = "/luadb/g722_tone.pcm"
local REF_FILE = "/luadb/g722_ref.bit"
local PST_FILE = "/luadb/g722_ref.pcm"
local PCM_LEN = 32000
local REF_LEN = 8000
local G722_PCM_FRAME = 640   -- 320采样点 * 2字节, 20ms一帧PCM
local G722_BIT_FRAME = 160   -- 20ms码流, 64kbps

local function read_file(path)
    local f = io.open(path, "rb")
    assert(f ~= nil, "open failed: " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

--- 编码对拍: 集成链路的输出必须与上游参考实现逐字节一致
function g722_test.test_encode_bitexact()
    log.info("g722_test", "test encode bit-exact vs reference bitstream")

    local pcm = read_file(PCM_FILE)
    assert(#pcm == PCM_LEN, "pcm size mismatch: " .. #pcm)
    local ref = read_file(REF_FILE)
    assert(#ref == REF_LEN, "ref bitstream size mismatch: " .. #ref)

    local encoder = codec.create(codec.G722, false)
    assert(encoder ~= nil, "G722 encoder create failed")

    local inbuf = zbuff.create(PCM_LEN)
    inbuf:write(pcm)
    inbuf:used(#pcm)
    local outbuf = zbuff.create(REF_LEN)
    local ret = codec.encode(encoder, inbuf, outbuf)
    assert(ret == true, "G722 encode failed")
    assert(outbuf:used() == REF_LEN, "encoded size should be " .. REF_LEN .. ", got " .. outbuf:used())

    local encoded = outbuf:query(0, outbuf:used())
    assert(encoded == ref, "encoded bitstream is NOT bit-exact with the reference")

    codec.release(encoder)
    log.info("g722_test", "encode bit-exact PASS,", PCM_LEN / G722_PCM_FRAME, "frames")
end

--- 编解码回环: encode -> 写文件 -> codec.info/codec.data 解码
function g722_test.test_roundtrip()
    log.info("g722_test", "test encode/decode roundtrip")

    local pcm = read_file(PCM_FILE)
    local encoder = codec.create(codec.G722, false)
    assert(encoder ~= nil, "encoder create failed")
    local inbuf = zbuff.create(PCM_LEN)
    inbuf:write(pcm)
    inbuf:used(#pcm)
    local encoded = zbuff.create(REF_LEN)
    assert(codec.encode(encoder, inbuf, encoded) == true, "encode failed")
    assert(encoded:used() == REF_LEN, "encoded size mismatch")
    codec.release(encoder)

    local tmp_file = "/g722_test.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.G722, true)
    assert(decoder ~= nil, "decoder create failed")

    local ok, fmt, ch, sr, bits = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")
    assert(sr == 16000, "sample_rate should be 16000, got " .. tostring(sr))
    assert(ch == 1, "channels should be 1, got " .. tostring(ch))

    local pcm_out = zbuff.create(4096)
    local total = 0
    for i = 1, REF_LEN / 160 + 2 do
        local dec_ret = codec.data(decoder, pcm_out, 4096)
        if not dec_ret then break end
        total = total + pcm_out:used()
    end
    assert(total == PCM_LEN, "decoded PCM should be " .. PCM_LEN .. ", got " .. total)

    codec.release(decoder)
    os.remove(tmp_file)
    log.info("g722_test", "roundtrip PASS,", REF_LEN, "bytes ->", total, "bytes PCM")
end

--- 解码对拍: 解码参考码流必须与上游参考合成输出逐字节一致
function g722_test.test_decode_bitexact()
    log.info("g722_test", "test decode bit-exact vs reference synthesis")

    local ref = read_file(REF_FILE)
    local pst = read_file(PST_FILE)
    assert(#pst == PCM_LEN, "ref pst size mismatch: " .. #pst)

    local tmp_file = "/g722_dec_test.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(ref)
    f:close()

    local decoder = codec.create(codec.G722, true)
    assert(decoder ~= nil, "decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    local chunks = {}
    for i = 1, REF_LEN / 160 + 2 do
        local dec_ret = codec.data(decoder, pcm_out, 4096)
        if not dec_ret then break end
        chunks[#chunks + 1] = pcm_out:query(0, pcm_out:used())
    end
    codec.release(decoder)
    os.remove(tmp_file)

    local decoded = table.concat(chunks)
    assert(#decoded == PCM_LEN, "decoded size should be " .. PCM_LEN .. ", got " .. #decoded)
    assert(decoded == pst, "decoded PCM is NOT bit-exact with the reference")

    log.info("g722_test", "decode bit-exact PASS,", #decoded, "bytes PCM")
end

--- audio_v2 常量、注册与接线检查
function g722_test.test_audio_v2_registration()
    log.info("g722_test", "test audio_v2 G722 registration")
    assert(audio_v2 ~= nil, "audio_v2 module missing")
    assert(audio_v2.DATA_CODEC_TYPE_G722 ~= nil, "DATA_CODEC_TYPE_G722 constant missing")
    -- get_codec_param 内部走 luat_audio_data_codec_find, 能取到值说明适配器已注册且接线正确
    local enc_in = audio_v2.get_codec_param(audio_v2.DATA_CODEC_TYPE_G722, audio_v2.DATA_CODEC_PARAM_ENCODE_INPUT_LEN)
    assert(enc_in == 640, "encode_min_input_len should be 640, got " .. tostring(enc_in))
    log.info("g722_test", "audio_v2 registration PASS, encode_min_input_len =", enc_in)
end

--- 56k/48k 码率冒烟: create成功, 且帧长保持 4:1 比例(非packed模式逐字节对齐)
function g722_test.test_rate_modes()
    log.info("g722_test", "test 56k/48k rate modes")
    local pcm = read_file(PCM_FILE)
    for _, level in ipairs({1, 2}) do
        local encoder = codec.create(codec.G722, false, level)
        assert(encoder ~= nil, "encoder create failed for level " .. level)
        local inbuf = zbuff.create(G722_PCM_FRAME)
        inbuf:write(pcm:sub(1, G722_PCM_FRAME))
        inbuf:used(G722_PCM_FRAME)
        local outbuf = zbuff.create(G722_BIT_FRAME)
        assert(codec.encode(encoder, inbuf, outbuf) == true, "encode failed for level " .. level)
        assert(outbuf:used() == G722_BIT_FRAME,
            "level " .. level .. " frame should be " .. G722_BIT_FRAME .. ", got " .. outbuf:used())
        codec.release(encoder)

        local decoder = codec.create(codec.G722, true, level)
        assert(decoder ~= nil, "decoder create failed for level " .. level)
        codec.release(decoder)
    end
    log.info("g722_test", "rate modes PASS")
end

--- 奇数采样尾: 输入PCM采样数为奇时自动补零, 不越界不失败
function g722_test.test_odd_sample_tail()
    log.info("g722_test", "test odd sample tail padding")
    local pcm = read_file(PCM_FILE)
    local odd_len = 319 * 2   -- 319个采样(奇数), 触发尾部补零路径
    local encoder = codec.create(codec.G722, false)
    assert(encoder ~= nil, "encoder create failed")
    local inbuf = zbuff.create(G722_PCM_FRAME)
    inbuf:write(pcm:sub(1, odd_len))
    inbuf:used(odd_len)
    local outbuf = zbuff.create(G722_BIT_FRAME)
    assert(codec.encode(encoder, inbuf, outbuf) == true, "odd-tail encode failed")
    -- 319采样 = 159对 + 1个补零对 => 160字节
    assert(outbuf:used() == G722_BIT_FRAME,
        "odd-tail output should be " .. G722_BIT_FRAME .. ", got " .. outbuf:used())
    codec.release(encoder)
    log.info("g722_test", "odd sample tail PASS")
end

return g722_test
