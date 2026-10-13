--- g729编解码测试模块
-- @module g729_test

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local g729_test = {}

-- ITU TAME 测试序列: 20480字节PCM(16bit/8kHz/单声道) -> 1280字节码流(128帧)
local PCM_FILE = "/luadb/tame.pcm"
local REF_FILE = "/luadb/tame_ref.bit"
local PCM_LEN = 20480
local REF_LEN = 1280
local G729_PCM_FRAME = 160   -- 80采样点 * 2字节, 一帧PCM

local function read_file(path)
    local f = io.open(path, "rb")
    assert(f ~= nil, "open failed: " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

--- 编码对拍: 集成链路的输出必须与上游参考实现逐字节一致
function g729_test.test_encode_bitexact()
    log.info("g729_test", "test encode bit-exact vs reference bitstream")

    local pcm = read_file(PCM_FILE)
    assert(#pcm == PCM_LEN, "pcm size mismatch: " .. #pcm)
    local ref = read_file(REF_FILE)
    assert(#ref == REF_LEN, "ref bitstream size mismatch: " .. #ref)

    local encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "G729 encoder create failed")

    local inbuf = zbuff.create(PCM_LEN)
    inbuf:write(pcm)
    inbuf:used(#pcm)
    local outbuf = zbuff.create(REF_LEN)
    local ret = codec.encode(encoder, inbuf, outbuf)
    assert(ret == true, "G729 encode failed")
    assert(outbuf:used() == REF_LEN, "encoded size should be " .. REF_LEN .. ", got " .. outbuf:used())

    local encoded = outbuf:query(0, outbuf:used())
    assert(encoded == ref, "encoded bitstream is NOT bit-exact with the reference")

    codec.release(encoder)
    log.info("g729_test", "encode bit-exact PASS, 128 frames")
end

--- 编解码回环: encode -> 写文件 -> codec.info/codec.data 解码
function g729_test.test_roundtrip()
    log.info("g729_test", "test encode/decode roundtrip")

    local pcm = read_file(PCM_FILE)
    local encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "encoder create failed")
    local inbuf = zbuff.create(PCM_LEN)
    inbuf:write(pcm)
    inbuf:used(#pcm)
    local encoded = zbuff.create(REF_LEN)
    assert(codec.encode(encoder, inbuf, encoded) == true, "encode failed")
    assert(encoded:used() == REF_LEN, "encoded size mismatch")
    codec.release(encoder)

    local tmp_file = "/g729_test.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "decoder create failed")

    local ok, fmt, ch, sr, bits = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")
    assert(sr == 8000, "sample_rate should be 8000, got " .. tostring(sr))
    assert(ch == 1, "channels should be 1, got " .. tostring(ch))

    local pcm_out = zbuff.create(PCM_LEN)
    local total = 0
    for i = 1, REF_LEN / 10 do
        local dec_ret = codec.data(decoder, pcm_out, 4096)
        if not dec_ret then break end
        total = total + pcm_out:used()
    end
    assert(total == PCM_LEN, "decoded PCM should be " .. PCM_LEN .. ", got " .. total)

    codec.release(decoder)
    os.remove(tmp_file)
    log.info("g729_test", "roundtrip PASS,", REF_LEN, "bytes ->", total, "bytes PCM")
end

--- 解码对拍: 解码参考码流必须与 ITU 参考合成输出逐字节一致
function g729_test.test_decode_bitexact()
    log.info("g729_test", "test decode bit-exact vs ITU reference synthesis")

    local ref = read_file(REF_FILE)
    local pst = read_file("/luadb/tame_ref.pst")
    assert(#pst == PCM_LEN, "ref pst size mismatch: " .. #pst)

    local tmp_file = "/g729_dec_test.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(ref)
    f:close()

    local decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    local chunks = {}
    for i = 1, REF_LEN / 10 do
        local dec_ret = codec.data(decoder, pcm_out, 4096)
        if not dec_ret then break end
        chunks[#chunks + 1] = pcm_out:query(0, pcm_out:used())
    end
    codec.release(decoder)
    os.remove(tmp_file)

    local decoded = table.concat(chunks)
    assert(#decoded == PCM_LEN, "decoded size should be " .. PCM_LEN .. ", got " .. #decoded)
    assert(decoded == pst, "decoded PCM is NOT bit-exact with the ITU reference")

    log.info("g729_test", "decode bit-exact PASS,", #decoded, "bytes PCM")
end

--- audio_v2 常量、注册与接线检查
function g729_test.test_audio_v2_registration()
    log.info("g729_test", "test audio_v2 G729 registration")
    assert(audio_v2 ~= nil, "audio_v2 module missing")
    assert(audio_v2.DATA_CODEC_TYPE_G729 ~= nil, "DATA_CODEC_TYPE_G729 constant missing")
    -- get_codec_param 内部走 luat_audio_data_codec_find, 能取到值说明适配器已注册且接线正确
    local enc_in = audio_v2.get_codec_param(audio_v2.DATA_CODEC_TYPE_G729, audio_v2.DATA_CODEC_PARAM_ENCODE_INPUT_LEN)
    assert(enc_in == 160, "encode_min_input_len should be 160, got " .. tostring(enc_in))
    log.info("g729_test", "audio_v2 registration PASS, encode_min_input_len =", enc_in)
end

-- Annex B 参考: 上游库 VAD=1 编码 tame.pcm 的长度前缀容器 + 对应解码PCM
local VAD_REF_FILE = "/luadb/tame_vad_ref.bit"
local VAD_REF_PST  = "/luadb/tame_vad_ref.pst"
local VAD_REF_LEN = 1408   -- 128帧, 全部为语音帧: 128 * (1 + 10)

--- Annex B 编码对拍: VAD开启, 逐帧编码, 帧长和负载都必须与上游参考逐字节一致
function g729_test.test_annexb_encode_bitexact()
    log.info("g729_test", "test annexb encode bit-exact (per-frame, VAD on)")

    local pcm = read_file(PCM_FILE)
    local ref = read_file(VAD_REF_FILE)
    assert(#ref == VAD_REF_LEN, "vad ref size mismatch: " .. #ref)

    local encoder = codec.create(codec.G729, false, 1)  -- encode_level=1 开启VAD/DTX
    assert(encoder ~= nil, "G729 annexb encoder create failed")

    local inbuf = zbuff.create(G729_PCM_FRAME)
    local outbuf = zbuff.create(16)
    local pos = 1      -- pcm 偏移(string, 1-based)
    local rpos = 1     -- 容器偏移
    local frames = PCM_LEN / G729_PCM_FRAME
    for i = 1, frames do
        inbuf:seek(0)
        inbuf:write(pcm:sub(pos, pos + G729_PCM_FRAME - 1))
        inbuf:used(G729_PCM_FRAME)
        outbuf:seek(0)
        outbuf:used(0)
        assert(codec.encode(encoder, inbuf, outbuf) == true, "annexb encode frame " .. i .. " failed")

        local rec_len = ref:byte(rpos)
        assert(outbuf:used() == rec_len,
            "frame " .. i .. " len should be " .. rec_len .. ", got " .. outbuf:used())
        if rec_len > 0 then
            assert(outbuf:query(0, rec_len) == ref:sub(rpos + 1, rpos + rec_len),
                "frame " .. i .. " payload NOT bit-exact")
        end
        pos = pos + G729_PCM_FRAME
        rpos = rpos + 1 + rec_len
    end
    assert(rpos - 1 == VAD_REF_LEN, "container not fully consumed: " .. rpos)

    codec.release(encoder)
    log.info("g729_test", "annexb encode bit-exact PASS,", frames, "frames")
end

--- Annex B 静音DTX: 全零输入必须产生SID/NO_DATA帧, 且容器解码回环PCM长度正确
function g729_test.test_annexb_silence_dtx()
    log.info("g729_test", "test annexb silence DTX (SID/NO_DATA)")

    local frames = 100
    local encoder = codec.create(codec.G729, false, 1)
    assert(encoder ~= nil, "encoder create failed")

    local inbuf = zbuff.create(G729_PCM_FRAME)   -- 全零
    inbuf:used(G729_PCM_FRAME)
    local outbuf = zbuff.create(16)
    local voice, sid, nodata = 0, 0, 0
    local container = {}
    for i = 1, frames do
        outbuf:seek(0)
        outbuf:used(0)
        assert(codec.encode(encoder, inbuf, outbuf) == true, "silence encode frame " .. i .. " failed")
        local n = outbuf:used()
        if n == 10 then voice = voice + 1
        elseif n == 2 then sid = sid + 1
        elseif n == 0 then nodata = nodata + 1
        else assert(false, "frame " .. i .. " unexpected len " .. n) end
        container[#container + 1] = string.char(n) .. (n > 0 and outbuf:query(0, n) or "")
    end
    codec.release(encoder)
    assert(sid >= 1, "silence must produce at least one SID frame")
    assert(nodata > 0, "silence must produce NO_DATA frames")
    log.info("g729_test", "DTX pattern: voice=" .. voice .. " sid=" .. sid .. " nodata=" .. nodata)

    -- 容器写文件, 走文件解码路径回环
    local tmp_file = "/g729_silence.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(table.concat(container))
    f:close()

    local decoder = codec.create(codec.G729, true, 1)   -- 1 = 长度前缀容器
    assert(decoder ~= nil, "decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    local total = 0
    for i = 1, frames do
        if not codec.data(decoder, pcm_out, 4096) then break end
        total = total + pcm_out:used()
    end
    codec.release(decoder)
    os.remove(tmp_file)
    assert(total == frames * G729_PCM_FRAME,
        "decoded PCM should be " .. (frames * G729_PCM_FRAME) .. ", got " .. total)
    log.info("g729_test", "annexb silence DTX PASS, decoded", total, "bytes PCM")
end

--- Annex B 容器解码对拍: 与上游参考合成输出逐字节一致
function g729_test.test_annexb_decode_bitexact()
    log.info("g729_test", "test annexb container decode bit-exact")

    local ref = read_file(VAD_REF_FILE)
    local pst = read_file(VAD_REF_PST)
    assert(#pst == PCM_LEN, "vad ref pst size mismatch: " .. #pst)

    local tmp_file = "/g729_vad_dec.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(ref)
    f:close()

    local decoder = codec.create(codec.G729, true, 1)
    assert(decoder ~= nil, "decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    local chunks = {}
    for i = 1, PCM_LEN / G729_PCM_FRAME do
        if not codec.data(decoder, pcm_out, 4096) then break end
        chunks[#chunks + 1] = pcm_out:query(0, pcm_out:used())
    end
    codec.release(decoder)
    os.remove(tmp_file)

    local decoded = table.concat(chunks)
    assert(#decoded == PCM_LEN, "decoded size should be " .. PCM_LEN .. ", got " .. #decoded)
    assert(decoded == pst, "annexb decoded PCM is NOT bit-exact with the reference")
    log.info("g729_test", "annexb decode bit-exact PASS,", #decoded, "bytes PCM")
end

return g729_test
