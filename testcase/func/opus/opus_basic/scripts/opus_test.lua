--- opus编解码测试模块
-- @module opus_test
-- 自适应两种构建档位:
--   full   : 编码+解码, 走编码->解码回环
--   decode : 仅解码(LUAT_OPUS_MODE=decode), 编码测试跳过, 解码用内嵌样本

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local opus_test = {}

-- opus端口固定60ms帧长(opus_port.c DELAY_SAMPLES 60)
local FRAME_MS = 60

-- 内嵌解码样本: 16kHz 60ms 440Hz正弦波经opus编码(BITRATE 64000)的产物,
-- 格式与端口一致: 2字节大端长度头 + opus数据包。用于仅解码档的功能验证。
local EMBEDDED_SAMPLE_PKT = "\x01\xdf\xbb\x03\x7f\x1b\x21\x26\x15\xd3\x2c\x0e\x69\x72\x60\x88\xd2\x49\x5a\x57\x95\x10\xab\x84\x3f\xfe\xd6\x77\x5a\xaf\x5e\x08\x53\x9e\x67\x67\xd7\xdf\x36\x17\x02\x3b\x46\x41\x7b\x5d\xc6\x04\x2a\xab\x5f\xfe\x4d\x76\xba\x89\x7e\x5f\x03\xa8\xbd\xc8\x36\x40\x90\x2d\x8f\xe6\xb6\xc3\x7c\x9d\xd5\x17\x43\xa9\x3f\xc9\xcd\x6a\x0b\x1d\xcb\x7d\x51\xfd\x99\x5e\xb4\x10\x42\x64\xa2\xc4\x90\x19\xf2\x42\x70\xde\x0c\x67\x33\x8f\xc6\xd5\xc7\xca\xd7\x0b\xdf\x5a\xfe\x79\x47\xa2\xdb\x87\x7d\x27\x99\x2b\x1b\xde\x4b\xc9\x2c\xc4\x97\x2f\xc6\x3d\x62\xe4\x95\x36\x22\x93\x09\xa1\x19\xc4\xf8\xb0\x04\x72\xf0\x38\x49\xec\x54\x85\xcd\x26\x00\x37\xcd\xaf\x31\x42\x68\x6d\x59\x09\xbc\xec\x46\x37\x0a\x47\x90\x99\x93\x4e\x0c\x6c\xdd\x95\xc3\x60\x2a\xe6\xce\xb1\xd5\xa7\x65\x93\xa2\xb6\x9c\x9b\xf6\xf5\x7e\x21\x5b\xb9\x05\xce\xaf\x5c\xf6\x12\x95\xe0\x34\x65\xba\x12\x83\x73\xcc\xa8\xf3\xa6\x32\x9f\x43\x63\x1b\x45\x35\x1d\x0e\x1c\xad\x30\x69\x1d\x2e\x8b\xe1\x93\x4d\xc9\xf4\x4d\x07\x01\x50\x4c\x06\x9b\xab\x5c\xda\x78\x11\xa3\xda\x97\x12\xd3\xa0\x26\x4b\x8e\xa4\x4a\xc2\x4e\xc3\x5e\x81\xe4\x92\x80\x57\xaa\xfc\x9b\x60\x2b\xa3\xa7\x52\x31\x76\x98\xcb\x80\x43\x51\xd0\x58\x3b\x28\x5e\xab\xef\x4a\x6a\x43\x1c\x7b\x36\x64\x7e\x6b\xe0\x46\x50\xe4\x3e\xfe\xe2\x2b\x98\x60\x39\x2e\xf8\xfa\xec\xba\xf1\xd5\xf8\xc2\x14\xd0\x0f\x34\x9a\xed\xcc\xb0\x05\x05\xc7\xa7\x73\x94\x9a\xd5\xf6\x3e\x6e\x59\x6f\x85\x11\x80\xea\x2c\x00\x8d\x25\x92\xa9\xa4\x7c\x0b\x62\x4f\x00\xaa\x5d\x0e\xc8\x2e\x69\xa7\x09\xde\xd9\x5a\x42\x2d\xe2\x66\x6a\x0b\x4e\x8d\x03\x8f\xce\xa6\xdc\xf3\x68\xc5\x7f\x6a\x5f\xe3\x49\xf3\xe2\xb9\xa5\x2d\x1c\x1e\x50\x03\xed\x73\x87\x0d\xcb\xbb\xde\xb4\xed\x99\xb1\xa7\x48\xe9\x4d\xf2\xc0\x75\x5d\xe8\xfe\xce\xba\xa0\x8a\x1e\xd3\x0e\xbb\xee\x20\xee\x5a\x1f\x6e\x5b\x6b\x69\x53\x26\x31\xe3\xcb\x8a\x6a\x18\x3f\xe1\xb2\x99\x41\x3c\xa1\x29\x38\x26\xa8\x9b\xe9\x3f\x55\x3f\xc9\x78\xd5\x5f\xf2\x19\x67\x35\x37\x47\xa5\x3d\x38\x3f\x4a\x3c\x42\x64\x46\x50\x45"

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

--- 计算PCM16LE数据的能量(绝对值之和), 用于判断解码结果非全零
-- @param pcm_str PCM16LE字符串
-- @return number 能量值
local function pcm_energy(pcm_str)
    local energy = 0
    local samples = #pcm_str // 2
    for i = 1, samples do
        local v = string.unpack("<i2", pcm_str, (i - 1) * 2 + 1)
        energy = energy + math.abs(v)
    end
    return energy
end

--- 探测当前构建是否包含opus编码器(仅解码档下创建会失败)
local enc_available = nil
local function has_encoder()
    if enc_available == nil then
        local enc = codec.create(codec.OPUS, false, {sample_rate = 16000, num_channels = 1})
        enc_available = (enc ~= nil)
        if enc then codec.release(enc) end
    end
    return enc_available
end

--- 测试codec.create创建opus编码器/解码器
function opus_test.test_opus_codec_create()
    log.info("opus_test", "test codec.create OPUS decoder")
    local decoder = codec.create(codec.OPUS, true, {sample_rate = 16000, num_channels = 1})
    assert(decoder ~= nil, "OPUS decoder create failed")
    codec.release(decoder)

    if has_encoder() then
        log.info("opus_test", "test codec.create OPUS encoder")
        local encoder = codec.create(codec.OPUS, false, {sample_rate = 16000, num_channels = 1})
        assert(encoder ~= nil, "OPUS encoder create failed")
        codec.release(encoder)
    else
        log.info("opus_test", "decode-only build: encoder unavailable as expected")
        local encoder = codec.create(codec.OPUS, false, {sample_rate = 16000, num_channels = 1})
        assert(encoder == nil, "encoder should be unavailable in decode-only build")
    end

    log.info("opus_test", "codec create PASS")
end

--- 测试解码内嵌样本(两种档位都可用)
function opus_test.test_opus_decode_embedded_sample()
    if EMBEDDED_SAMPLE_PKT == "@@EMBEDDED_SAMPLE_PKT@@" or #EMBEDDED_SAMPLE_PKT == 0 then
        log.warn("opus_test", "embedded sample not available, skip")
        return
    end
    log.info("opus_test", "test decode embedded sample", #EMBEDDED_SAMPLE_PKT, "bytes")

    local tmp_file = "/opus_embedded_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(EMBEDDED_SAMPLE_PKT)
    f:close()

    local decoder = codec.create(codec.OPUS, true, {sample_rate = 16000, num_channels = 1})
    assert(decoder ~= nil, "decoder create failed")

    local ok, fmt, ch, sr, bits, signed = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")
    assert(sr == 16000, "sample_rate should be 16000, got " .. tostring(sr))

    local pcm_out = zbuff.create(4096)
    local dec_ret = codec.data(decoder, pcm_out, 4096)
    assert(dec_ret == true, "decode embedded sample failed")
    assert(pcm_out:used() == 1920, "decoded PCM should be 1920 bytes, got " .. tostring(pcm_out:used()))

    local energy = pcm_energy(pcm_out:query(0, pcm_out:used()))
    assert(energy > 0, "decoded PCM is all zeros")
    log.info("opus_test", "embedded sample decoded, energy", energy)

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("opus_test", "embedded sample PASS")
end

--- 测试opus单帧编码解码回环(16kHz 60ms)
function opus_test.test_opus_encode_decode_roundtrip()
    if not has_encoder() then
        log.warn("opus_test", "encoder not available (decode-only build), skip roundtrip")
        return
    end
    log.info("opus_test", "test OPUS encode/decode roundtrip")

    -- 生成16kHz 60ms PCM数据 (960 samples = 1920 bytes, 恰好一帧)
    local frame_bytes = 16000 * FRAME_MS // 1000 * 2
    local pcm_in = gen_sine_pcm(16000, 440, FRAME_MS)
    assert(pcm_in:used() == frame_bytes, "PCM input should be " .. frame_bytes .. " bytes")

    -- 编码
    local encoder = codec.create(codec.OPUS, false, {sample_rate = 16000, num_channels = 1})
    assert(encoder ~= nil, "encoder create failed")

    local encoded = zbuff.create(4096)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "OPUS encode failed")
    assert(encoded:used() > 2, "encoded data should have header + payload")
    log.info("opus_test", "encoded", pcm_in:used(), "->", encoded:used(), "bytes")

    -- 校验帧格式: 2字节大端长度头 + 载荷
    local hdr = encoded:query(0, 2)
    local payload_len = string.unpack(">I2", hdr)
    assert(payload_len == encoded:used() - 2,
        "header length " .. tostring(payload_len) .. " != payload " .. tostring(encoded:used() - 2))

    -- 编码后的数据应该比PCM小(压缩)
    assert(encoded:used() < pcm_in:used(), "encoded should be smaller than PCM")

    codec.release(encoder)

    -- 解码 - 将编码数据写入临时文件再解码
    local tmp_file = "/opus_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.OPUS, true, {sample_rate = 16000, num_channels = 1})
    assert(decoder ~= nil, "decoder create failed")

    local ok, fmt, ch, sr, bits, signed = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")
    assert(sr == 16000, "sample_rate should be 16000, got " .. tostring(sr))
    assert(ch == 1, "channels should be 1")

    local pcm_out = zbuff.create(4096)
    local dec_ret = codec.data(decoder, pcm_out, 4096)
    assert(dec_ret == true, "OPUS decode failed")
    assert(pcm_out:used() == frame_bytes,
        "decoded PCM should be " .. frame_bytes .. " bytes, got " .. tostring(pcm_out:used()))

    log.info("opus_test", "decoded", encoded:used(), "->", pcm_out:used(), "bytes")

    -- 解码结果不能是全零
    local energy = pcm_energy(pcm_out:query(0, pcm_out:used()))
    assert(energy > 0, "decoded PCM is all zeros")
    log.info("opus_test", "decoded PCM energy", energy)

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("opus_test", "roundtrip PASS")
end

--- 测试多帧连续编码解码(16kHz 300ms = 5帧)
function opus_test.test_opus_multi_frame()
    if not has_encoder() then
        log.warn("opus_test", "encoder not available (decode-only build), skip multi-frame")
        return
    end
    log.info("opus_test", "test multi-frame encoding")

    local frame_count = 5
    local frame_bytes = 16000 * FRAME_MS // 1000 * 2
    local total_bytes = frame_bytes * frame_count

    -- 生成16kHz 300ms PCM数据 (5帧)
    local pcm_in = gen_sine_pcm(16000, 440, FRAME_MS * frame_count)
    assert(pcm_in:used() == total_bytes, "PCM input should be " .. total_bytes .. " bytes")

    local encoder = codec.create(codec.OPUS, false, {sample_rate = 16000, num_channels = 1})
    assert(encoder ~= nil, "encoder create failed")

    local encoded = zbuff.create(8192)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "multi-frame encode failed")
    -- 5帧 * (2字节头 + 编码数据) 应明显大于单帧
    assert(encoded:used() > 100, "multi-frame encoded too small: " .. tostring(encoded:used()))
    log.info("opus_test", "5 frames encoded:", pcm_in:used(), "->", encoded:used(), "bytes")

    codec.release(encoder)

    -- 解码全部帧
    local tmp_file = "/opus_multi_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.OPUS, true, {sample_rate = 16000, num_channels = 1})
    assert(decoder ~= nil, "decoder create failed")
    local ok = codec.info(decoder, tmp_file)
    assert(ok == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    -- codec.data每次解码一个数据包, 循环直到返回false
    local total_decoded = 0
    for i = 1, frame_count + 2 do
        local dec_ret = codec.data(decoder, pcm_out, 4096)
        if not dec_ret then break end
        total_decoded = total_decoded + pcm_out:used()
    end

    log.info("opus_test", "multi-frame decoded:", total_decoded, "bytes")
    assert(total_decoded >= total_bytes,
        "should decode at least " .. total_bytes .. " bytes, got " .. tostring(total_decoded))

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("opus_test", "multi-frame PASS")
end

--- 测试8kHz采样率回环(60ms = 480 samples = 960 bytes)
function opus_test.test_opus_8k_sample_rate()
    if not has_encoder() then
        log.warn("opus_test", "encoder not available (decode-only build), skip 8kHz roundtrip")
        return
    end
    log.info("opus_test", "test OPUS 8kHz roundtrip")

    local frame_bytes = 8000 * FRAME_MS // 1000 * 2
    local pcm_in = gen_sine_pcm(8000, 440, FRAME_MS)
    assert(pcm_in:used() == frame_bytes, "PCM input should be " .. frame_bytes .. " bytes")

    local encoder = codec.create(codec.OPUS, false, {sample_rate = 8000, num_channels = 1})
    assert(encoder ~= nil, "8k encoder create failed")

    local encoded = zbuff.create(4096)
    local ret = codec.encode(encoder, pcm_in, encoded)
    assert(ret == true, "8k encode failed")
    assert(encoded:used() > 2, "8k encoded data should have header + payload")
    log.info("opus_test", "8k encoded", pcm_in:used(), "->", encoded:used(), "bytes")

    codec.release(encoder)

    local tmp_file = "/opus_8k_test.bin"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(encoded:query(0, encoded:used()))
    f:close()

    local decoder = codec.create(codec.OPUS, true, {sample_rate = 8000, num_channels = 1})
    assert(decoder ~= nil, "8k decoder create failed")

    local ok, fmt, ch, sr, bits, signed = codec.info(decoder, tmp_file)
    assert(ok == true, "8k codec.info failed")
    assert(sr == 8000, "sample_rate should be 8000, got " .. tostring(sr))

    local pcm_out = zbuff.create(4096)
    local dec_ret = codec.data(decoder, pcm_out, 4096)
    assert(dec_ret == true, "8k decode failed")
    assert(pcm_out:used() == frame_bytes,
        "decoded PCM should be " .. frame_bytes .. " bytes, got " .. tostring(pcm_out:used()))

    local energy = pcm_energy(pcm_out:query(0, pcm_out:used()))
    assert(energy > 0, "decoded PCM is all zeros")

    log.info("opus_test", "8k decoded", encoded:used(), "->", pcm_out:used(), "bytes")

    codec.release(decoder)
    os.remove(tmp_file)

    log.info("opus_test", "8kHz roundtrip PASS")
end

return opus_test
