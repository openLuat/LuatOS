--- speex编解码测试模块
-- @module speex_test

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local speex_test = {}

--- 生成测试用PCM正弦波数据
-- @param sample_rate 采样率
-- @param freq 频率
-- @param duration_ms 持续时间(毫秒)
-- @return zbuff PCM16LE数据
local function gen_sine_pcm(sample_rate, freq, duration_ms)
    local samples = math.floor(sample_rate * duration_ms / 1000)
    local buff = zbuff.create(samples * 2)
    for i = 0, samples - 1 do
        local val = math.floor(16000 * math.sin(2 * math.pi * freq * i / sample_rate))
        -- 写入16位小端
        buff:write(i * 2, string.pack("<i2", val))
    end
    buff:used(samples * 2)
    return buff
end

--- 测试codec.create创建speex NB编码器
function speex_test.test_speex_codec_create()
    log.info("speex_test", "test codec.create SPEEX_NB encoder")
    local encoder = codec.create(codec.SPEEX_NB, false, 8)
    assert(encoder ~= nil, "SPEEX_NB encoder create failed")
    codec.release(encoder)

    log.info("speex_test", "test codec.create SPEEX_NB decoder")
    local decoder = codec.create(codec.SPEEX_NB, true)
    assert(decoder ~= nil, "SPEEX_NB decoder create failed")
    codec.release(decoder)

    log.info("speex_test", "test codec.create SPEEX_WB encoder")
    local wb_enc = codec.create(codec.SPEEX_WB, false, 8)
    assert(wb_enc ~= nil, "SPEEX_WB encoder create failed")
    codec.release(wb_enc)

    log.info("speex_test", "test codec.create SPEEX_UWB encoder")
    local uwb_enc = codec.create(codec.SPEEX_UWB, false, 8)
    assert(uwb_enc ~= nil, "SPEEX_UWB encoder create failed")
    codec.release(uwb_enc)

    log.info("speex_test", "codec create PASS")
end

--- 测试Speex NB编码解码回环
function speex_test.test_speex_nb_encode_decode()
    log.info("speex_test", "test SPEEX_NB encode/decode roundtrip")

    -- 生成8kHz 20ms PCM数据 (160 samples)
    local pcm_in = gen_sine_pcm(8000, 440, 20)
    assert(pcm_in:used() == 320, "PCM input should be 320 bytes")

    -- 编码
    local encoder = codec.create(codec.SPEEX_NB, false, 8)
    assert(encoder ~= nil, "encoder create failed")

    local encoded = zbuff.create(512)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "SPEEX_NB encode failed")
    assert(encoded:used() > 0, "encoded data should not be empty")
    log.info("speex_test", "NB encoded", pcm_in:used(), "->", encoded:used(), "bytes")

    -- 编码后的数据应该比PCM小(压缩)
    assert(encoded:used() < pcm_in:used(), "encoded should be smaller than PCM")

    codec.release(encoder)

    -- 解码 - 将编码数据写入临时文件再解码
    local tmp_file = "/speex_nb_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.SPEEX_NB, true)
    assert(decoder ~= nil, "decoder create failed")

    local ok, fmt, ch, sr, bits, signed = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")
    assert(sr == 8000, "sample_rate should be 8000, got " .. tostring(sr))
    assert(ch == 1, "channels should be 1")

    local pcm_out = zbuff.create(1024)
    local dec_ret = codec.data(decoder, pcm_out, 320)
    assert(dec_ret == true, "SPEEX_NB decode failed")
    assert(pcm_out:used() == 320, "decoded PCM should be 320 bytes, got " .. tostring(pcm_out:used()))

    log.info("speex_test", "NB decoded", encoded:used(), "->", pcm_out:used(), "bytes")

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("speex_test", "NB roundtrip PASS")
end

--- 测试Speex WB编码解码回环
function speex_test.test_speex_wb_encode_decode()
    log.info("speex_test", "test SPEEX_WB encode/decode roundtrip")

    -- 生成16kHz 20ms PCM数据 (320 samples)
    local pcm_in = gen_sine_pcm(16000, 880, 20)
    assert(pcm_in:used() == 640, "PCM input should be 640 bytes")

    -- 编码
    local encoder = codec.create(codec.SPEEX_WB, false, 8)
    assert(encoder ~= nil, "WB encoder create failed")

    local encoded = zbuff.create(1024)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "SPEEX_WB encode failed")
    assert(encoded:used() > 0, "WB encoded data should not be empty")
    log.info("speex_test", "WB encoded", pcm_in:used(), "->", encoded:used(), "bytes")

    codec.release(encoder)

    -- 解码
    local tmp_file = "/speex_wb_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.SPEEX_WB, true)
    assert(decoder ~= nil, "WB decoder create failed")

    local ok, fmt, ch, sr, bits, signed = codec.info(decoder, tmp_file)
    assert(ok == true, "WB codec.info failed")
    assert(sr == 16000, "WB sample_rate should be 16000, got " .. tostring(sr))

    local pcm_out = zbuff.create(2048)
    local dec_ret = codec.data(decoder, pcm_out, 640)
    assert(dec_ret == true, "SPEEX_WB decode failed")
    assert(pcm_out:used() == 640, "WB decoded PCM should be 640 bytes, got " .. tostring(pcm_out:used()))

    log.info("speex_test", "WB decoded", encoded:used(), "->", pcm_out:used(), "bytes")

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("speex_test", "WB roundtrip PASS")
end

--- 测试Speex UWB编码解码回环
function speex_test.test_speex_uwb_encode_decode()
    log.info("speex_test", "test SPEEX_UWB encode/decode roundtrip")

    -- 生成32kHz 20ms PCM数据 (640 samples)
    local pcm_in = gen_sine_pcm(32000, 1000, 20)
    assert(pcm_in:used() == 1280, "PCM input should be 1280 bytes")

    -- 编码
    local encoder = codec.create(codec.SPEEX_UWB, false, 8)
    assert(encoder ~= nil, "UWB encoder create failed")

    local encoded = zbuff.create(2048)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "SPEEX_UWB encode failed")
    assert(encoded:used() > 0, "UWB encoded data should not be empty")
    log.info("speex_test", "UWB encoded", pcm_in:used(), "->", encoded:used(), "bytes")

    codec.release(encoder)

    -- 解码
    local tmp_file = "/speex_uwb_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.SPEEX_UWB, true)
    assert(decoder ~= nil, "UWB decoder create failed")

    local ok, fmt, ch, sr, bits, signed = codec.info(decoder, tmp_file)
    assert(ok == true, "UWB codec.info failed")
    assert(sr == 32000, "UWB sample_rate should be 32000, got " .. tostring(sr))

    local pcm_out = zbuff.create(4096)
    local dec_ret = codec.data(decoder, pcm_out, 1280)
    assert(dec_ret == true, "SPEEX_UWB decode failed")
    assert(pcm_out:used() == 1280, "UWB decoded PCM should be 1280 bytes, got " .. tostring(pcm_out:used()))

    log.info("speex_test", "UWB decoded", encoded:used(), "->", pcm_out:used(), "bytes")

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("speex_test", "UWB roundtrip PASS")
end

--- 测试不同quality等级编码
function speex_test.test_speex_quality_levels()
    log.info("speex_test", "test different quality levels")

    local pcm_in = gen_sine_pcm(8000, 440, 20)
    local last_size = 0

    for quality = 1, 10, 3 do
        local encoder = codec.create(codec.SPEEX_NB, false, quality)
        assert(encoder ~= nil, "encoder create failed for quality " .. quality)

        local encoded = zbuff.create(512)
        local ret = codec.encode(encoder, pcm_in, encoded)
        assert(ret == true, "encode failed for quality " .. quality)
        assert(encoded:used() > 0, "encoded empty for quality " .. quality)

        log.info("speex_test", "quality", quality, "size", encoded:used())

        -- 更高质量通常产生更大的编码数据
        if last_size > 0 then
            assert(encoded:used() >= last_size,
                "quality " .. quality .. " should produce >= bytes than lower quality")
        end
        last_size = encoded:used()

        codec.release(encoder)
    end

    log.info("speex_test", "quality levels PASS")
end

--- 测试多帧连续编码
function speex_test.test_speex_multi_frame()
    log.info("speex_test", "test multi-frame encoding")

    -- 生成8kHz 100ms PCM数据 (800 samples = 5 frames)
    local pcm_in = gen_sine_pcm(8000, 440, 100)
    assert(pcm_in:used() == 1600, "PCM input should be 1600 bytes")

    local encoder = codec.create(codec.SPEEX_NB, false, 8)
    assert(encoder ~= nil, "encoder create failed")

    local encoded = zbuff.create(2048)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "multi-frame encode failed")
    -- 5帧 * (2字节头 + 编码数据) 应该大于单帧
    assert(encoded:used() > 50, "multi-frame encoded too small: " .. tostring(encoded:used()))
    log.info("speex_test", "5 frames encoded:", pcm_in:used(), "->", encoded:used(), "bytes")

    codec.release(encoder)

    -- 解码全部帧
    local tmp_file = "/speex_multi_test.bin"
    local f = io.open(tmp_file, "wb")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.SPEEX_NB, true)
    local ok = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    -- 解码所有帧
    local total_decoded = 0
    for i = 1, 10 do
        local dec_ret = codec.data(decoder, pcm_out, 320)
        if not dec_ret then break end
        total_decoded = pcm_out:used()
        if total_decoded >= 1600 then break end
    end

    log.info("speex_test", "multi-frame decoded:", total_decoded, "bytes")
    assert(total_decoded >= 1600, "should decode at least 1600 bytes, got " .. tostring(total_decoded))

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("speex_test", "multi-frame PASS")
end

return speex_test
