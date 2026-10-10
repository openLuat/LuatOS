--- g729性能定标测试模块
-- 逐帧测量编码/解码耗时(mcu.ticks2 微秒级), 输出 avg/min/max 与实时倍率(10ms帧=1x)
-- 兼作设备端 bit-exact 回归: 优化前后必须用本套件确认输出未变
-- @module g729_perf_test

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local g729_perf_test = {}

-- ITU TAME 测试序列: 20480字节PCM(16bit/8kHz/单声道) -> 1280字节码流(128帧)
local PCM_FILE = "/luadb/tame.pcm"
local REF_FILE = "/luadb/tame_ref.bit"
local PST_FILE = "/luadb/tame_ref.pst"
local PCM_LEN = 20480
local REF_LEN = 1280
local G729_PCM_FRAME = 160   -- 80采样点 * 2字节, 一帧PCM
local FRAMES = PCM_LEN / G729_PCM_FRAME  -- 128帧
local FRAME_US = 10000       -- 10ms 一帧, 实时倍率基准

local function read_file(path)
    local f = io.open(path, "rb")
    assert(f ~= nil, "open failed: " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

-- 微秒时间戳: mcu.ticks2(0) 返回 (秒部分, 微秒余数), 合成总微秒数
local function tick_us()
    local h, l = mcu.ticks2(0)
    return h * 1000000 + l
end

local function report(tag, total, tmin, tmax)
    local avg = total / FRAMES
    log.info("g729_perf", string.format(
        "%s total=%dus frames=%d avg=%.1fus/frame min=%dus max=%dus realtime=%.2fx",
        tag, total, FRAMES, avg, tmin, tmax, FRAME_US / avg))
end

--- 编码性能: 先跑一遍预热(消除flash XIP冷启动), 再逐帧计时(只计 codec.encode 本身), 每8帧让出一次调度喂狗
function g729_perf_test.test_encode_perf()
    log.info("g729_perf", "encode perf: 128 frames, per-frame timing")

    local pcm = read_file(PCM_FILE)
    assert(#pcm == PCM_LEN, "pcm size mismatch: " .. #pcm)

    local encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "G729 encoder create failed")

    local inbuf = zbuff.create(G729_PCM_FRAME)
    local outbuf = zbuff.create(16)

    -- 预热趟: 不计时, 把代码路径/数据表全部touch一遍
    for i = 1, FRAMES do
        local pos = (i - 1) * G729_PCM_FRAME + 1
        inbuf:seek(0)
        inbuf:write(pcm:sub(pos, pos + G729_PCM_FRAME - 1))
        inbuf:used(G729_PCM_FRAME)
        outbuf:seek(0)
        outbuf:used(0)
        assert(codec.encode(encoder, inbuf, outbuf) == true, "warmup encode failed at frame " .. i)
        if i % 8 == 0 then sys.wait(1) end
    end
    codec.release(encoder)
    sys.wait(10)

    encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "G729 encoder re-create failed")

    local total, tmin, tmax = 0, math.maxinteger, 0
    for i = 1, FRAMES do
        local pos = (i - 1) * G729_PCM_FRAME + 1
        inbuf:seek(0)
        inbuf:write(pcm:sub(pos, pos + G729_PCM_FRAME - 1))
        inbuf:used(G729_PCM_FRAME)
        outbuf:seek(0)
        outbuf:used(0)

        local t0 = tick_us()
        assert(codec.encode(encoder, inbuf, outbuf) == true, "encode failed at frame " .. i)
        local dt = tick_us() - t0

        total = total + dt
        if dt < tmin then tmin = dt end
        if dt > tmax then tmax = dt end
        if i % 8 == 0 then sys.wait(1) end
    end
    codec.release(encoder)

    report("ENCODE", total, tmin, tmax)
end

--- 解码性能: 参考码流写临时文件, 先预热一趟, 再逐帧 codec.data 计时
function g729_perf_test.test_decode_perf()
    log.info("g729_perf", "decode perf: 128 frames, per-frame timing")

    local ref = read_file(REF_FILE)
    assert(#ref == REF_LEN, "ref bitstream size mismatch: " .. #ref)

    local tmp_file = "/g729_perf_dec.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(ref)
    f:close()

    -- 预热趟
    local decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "G729 decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")
    local pcm_out = zbuff.create(4096)
    for i = 1, FRAMES do
        assert(codec.data(decoder, pcm_out, 4096) == true, "warmup decode failed at frame " .. i)
        if i % 16 == 0 then sys.wait(1) end
    end
    codec.release(decoder)
    sys.wait(10)

    -- 计时趟
    decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "G729 decoder re-create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local total, tmin, tmax = 0, math.maxinteger, 0
    for i = 1, FRAMES do
        local t0 = tick_us()
        assert(codec.data(decoder, pcm_out, 4096) == true, "decode failed at frame " .. i)
        local dt = tick_us() - t0

        assert(pcm_out:used() == G729_PCM_FRAME,
            "frame " .. i .. " should decode 160 bytes, got " .. pcm_out:used())
        total = total + dt
        if dt < tmin then tmin = dt end
        if dt > tmax then tmax = dt end
        if i % 16 == 0 then sys.wait(1) end
    end
    codec.release(decoder)
    os.remove(tmp_file)

    report("DECODE", total, tmin, tmax)
end

--- 设备端编码 bit-exact 门控: 优化前后输出必须与参考码流逐字节一致
function g729_perf_test.test_encode_bitexact()
    log.info("g729_perf", "encode bit-exact gate")

    local pcm = read_file(PCM_FILE)
    local ref = read_file(REF_FILE)
    assert(#pcm == PCM_LEN and #ref == REF_LEN, "fixture size mismatch")

    local encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "encoder create failed")

    local inbuf = zbuff.create(PCM_LEN)
    inbuf:write(pcm)
    inbuf:used(#pcm)
    local outbuf = zbuff.create(REF_LEN)
    assert(codec.encode(encoder, inbuf, outbuf) == true, "encode failed")
    assert(outbuf:used() == REF_LEN, "encoded size should be " .. REF_LEN .. ", got " .. outbuf:used())
    assert(outbuf:query(0, outbuf:used()) == ref, "encoded bitstream is NOT bit-exact with the reference")
    codec.release(encoder)

    log.info("g729_perf", "encode bit-exact PASS, 128 frames")
end

--- 设备端解码 bit-exact 门控: 解码输出必须与 ITU 参考合成逐字节一致
function g729_perf_test.test_decode_bitexact()
    log.info("g729_perf", "decode bit-exact gate")

    local ref = read_file(REF_FILE)
    local pst = read_file(PST_FILE)
    assert(#ref == REF_LEN and #pst == PCM_LEN, "fixture size mismatch")

    local tmp_file = "/g729_perf_gate.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(ref)
    f:close()

    local decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local pcm_out = zbuff.create(4096)
    local chunks = {}
    for i = 1, FRAMES do
        assert(codec.data(decoder, pcm_out, 4096) == true, "decode failed at frame " .. i)
        chunks[#chunks + 1] = pcm_out:query(0, pcm_out:used())
    end
    codec.release(decoder)
    os.remove(tmp_file)

    local decoded = table.concat(chunks)
    assert(#decoded == PCM_LEN, "decoded size should be " .. PCM_LEN .. ", got " .. #decoded)
    assert(decoded == pst, "decoded PCM is NOT bit-exact with the ITU reference")

    log.info("g729_perf", "decode bit-exact PASS,", #decoded, "bytes PCM")
end

return g729_perf_test
