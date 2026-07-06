-- 音频编解码性能测试
-- 依赖：codec 库，无则跳过
-- 测试：AMR-NB 编码（合成 PCM，无需外部文件）
--       MP3 解码（如 /luadb/test_16k.mp3 存在则测，否则跳过）

local M = {}
local helper = require("perf_helper")

-- 一帧 AMR-NB：160 个 int16 PCM 样本 = 320 字节
local FRAME_SAMPLES = 160
local ENCODE_FRAMES = 50  -- 编码 50 帧（约 1 秒 8kHz 音频）

-- 构造 320 字节合成正弦 PCM（AMR-NB 帧大小）
local function make_pcm_frame()
    if not zbuff then return nil end
    local buf = zbuff.create(FRAME_SAMPLES * 2)
    for i = 0, FRAME_SAMPLES - 1 do
        local val = math.floor(8000 * math.sin(2 * math.pi * 300 * i / 8000) + 0.5)
        -- clamp to int16 range
        if val > 32767  then val = 32767  end
        if val < -32768 then val = -32768 end
        buf:seek(i * 2, zbuff.SEEK_SET)
        -- writeI16 不一定存在，用无符号模拟有符号写入
        local uval = val < 0 and (val + 65536) or val
        buf:writeU16(uval)
    end
    return buf
end

local function skip_if_no_codec()
    if not codec then
        log.warn("perf_codec", "codec 库不可用，跳过音频编解码性能测试")
        return true
    end
    return false
end

function M.test_perf_amr_nb_encode()
    if skip_if_no_codec() then return end
    if not zbuff then
        log.warn("perf_codec", "zbuff 不可用，跳过 AMR-NB 编码测试")
        return
    end
    helper.section("AMR-NB 编码吞吐量")

    -- 创建 AMR-NB 编码器
    local encoder = codec.create(codec.AMR, false)
    if not encoder then
        log.warn("perf_codec", "AMR-NB 编码器创建失败，跳过")
        return
    end

    local in_buf  = make_pcm_frame()
    local out_buf = zbuff.create(64)  -- AMR-NB 最大帧 31 字节
    assert(in_buf and out_buf, "PCM 缓冲区创建失败")

    local t0 = mcu.ticks()
    for i = 1, ENCODE_FRAMES do
        codec.encode(encoder, in_buf, out_buf)
        if i % 25 == 0 then sys.wait(2) end
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    local fps = ENCODE_FRAMES * 1000 / elapsed
    local real_time_ratio = ENCODE_FRAMES * 20 / elapsed  -- 每帧 20ms → 实时倍率
    log.info("perf", string.format("[AMR-NB encode] %d帧 %dms → %.1f fps, 实时倍率 %.1fx",
        ENCODE_FRAMES, elapsed, fps, real_time_ratio))

    codec.release(encoder)
end

function M.test_perf_mp3_decode()
    if skip_if_no_codec() then return end
    local mp3_path = "/luadb/test_16k.mp3"
    if not io.exists(mp3_path) then
        log.warn("perf_codec", "未找到 " .. mp3_path .. "，跳过 MP3 解码性能测试")
        return
    end
    if not zbuff then
        log.warn("perf_codec", "zbuff 不可用，跳过 MP3 解码测试")
        return
    end
    helper.section("MP3 解码吞吐量")

    local decoder = codec.create(codec.MP3)
    if not decoder then
        log.warn("perf_codec", "MP3 解码器创建失败，跳过")
        return
    end

    local info = codec.info(decoder, mp3_path)
    if not info then
        log.warn("perf_codec", "codec.info 解析 MP3 失败，跳过")
        codec.release(decoder)
        return
    end

    -- 分配输出缓冲区（4KB per frame for stereo 44.1kHz）
    local out_buf = zbuff.create(8192)
    local frame_count = 0
    local t0 = mcu.ticks()
    while true do
        local result = codec.data(decoder, out_buf)
        if not result or result <= 0 then break end
        frame_count = frame_count + 1
        if frame_count % 50 == 0 then sys.wait(2) end
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    log.info("perf", string.format("[MP3 decode] %d帧 %dms → %.1f frames/s",
        frame_count, elapsed, frame_count * 1000 / elapsed))

    codec.release(decoder)
end

return M
