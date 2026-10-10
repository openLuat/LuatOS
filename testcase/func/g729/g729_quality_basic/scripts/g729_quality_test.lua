--- G.729A编码质量客观标尺(lossy优化前的度量基线)
-- 位精确构建下: 码流与ITU参考逐字节一致, 解码PCM与参考完全一致(与既有bit-exact门控等价)
-- lossy阶段: 把 EXPECT_BITEXACT 改成 false, 质量由 segSNR(分段信噪比)门槛把关
-- 度量本身的分辨率由 test_metric_sensitivity 证明: 单帧码流损坏必须被量成明显劣化,
-- 否则"质量测试通过"没有意义
-- @module g729_quality_test

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local g729_quality_test = {}

-- true while the codec is bit-exact; the lossy phase sets it false
local EXPECT_BITEXACT = true
-- 仅当 EXPECT_BITEXACT=false 时生效: 允许"解码PCM vs 源语音"的segSNR均值相对参考
-- 编解码器下降多少dB。注意门槛挂在这条源参照指标上, 不是挂在与参考码流的发散度上
-- (后者对任何逐帧判决变化都极敏感, 与可听质量无关, 见 test_metric_sensitivity 注释)。
local MAX_SEGSNR_LOSS_DB = 0.5

-- ITU TAME 测试序列: 20480字节PCM(16bit/8kHz/单声道, 10240采样点) <-> 1280字节码流(128帧)
local PCM_FILE  = "/luadb/tame.pcm"
local REF_FILE  = "/luadb/tame_ref.bit"
local PST_FILE  = "/luadb/tame_ref.pst"
local PCM_LEN   = 20480
local REF_LEN   = 1280
local G729_PCM_FRAME = 160    -- 80采样点 * 2字节, 一帧PCM
local G729_BIT_FRAME = 10     -- 一帧码流10字节
local FRAMES    = PCM_LEN / G729_PCM_FRAME   -- 128帧
local SAMPLE_FRAME = 80       -- segSNR的分段长度(采样点), 与编解码帧长一致
local SEGSNR_LO = 0.0         -- segSNR裁剪下限(dB)
local SEGSNR_HI = 35.0        -- segSNR裁剪上限(dB), 抑制静音段的小分母噪声

-- 单字节popcount表, 用于统计码流的比特差异
local POPCNT = {}
for i = 0, 255 do
    local v, c = i, 0
    while v > 0 do
        c = c + (v & 1)
        v = v >> 1
    end
    POPCNT[i] = c
end

local function read_file(path)
    local f = io.open(path, "rb")
    assert(f ~= nil, "open failed: " .. path)
    local data = f:read("*a")
    f:close()
    assert(type(data) == "string" and #data > 0, "empty file: " .. path)
    return data
end

local function write_file(path, data)
    local f = io.open(path, "wb")
    assert(f ~= nil, "open for write failed: " .. path)
    f:write(data)
    f:close()
end

--- 16位小端PCM字节串 -> 有符号采样值数组(1-based)
local function pcm16(bytes)
    local n = #bytes
    assert(n % 2 == 0, "pcm byte length must be even, got " .. n)
    local out = {}
    for i = 1, n, 2 do
        local lo, hi = string.byte(bytes, i, i + 1)
        local v = lo + hi * 256
        if v >= 32768 then v = v - 65536 end
        out[(i + 1) // 2] = v
    end
    return out
end

--- [from, to) 区间的 10*log10(Σref² / Σ(ref-new)²)
-- 完全相同返回 +inf; ref全零而new非零返回 -inf(由segSNR的裁剪归一化)
-- 累加用浮点: 10240个样点的平方和可达1e13, 32位整数的VM上会溢出
local function snr_db(ref, new, from, to)
    local sig, err = 0.0, 0.0
    for i = from, to - 1 do
        local r = ref[i]
        local d = r - new[i]
        sig = sig + r * r
        err = err + d * d
    end
    if err == 0 then
        return math.huge
    end
    if sig == 0 then
        return -math.huge
    end
    return 10 * math.log10(sig / err)
end

--- 分段信噪比: 每 frame_len 个采样点一段, 每段值裁剪到 [0, 35]dB 后取平均
-- 返回 mean, min, p5(第ceil(5%)小的段值), 以及每段的原始值数组
local function segsnr_db(ref, new, frame_len)
    local n = #ref
    local vals = {}
    local sum = 0.0
    for f = 1, n, frame_len do
        local stop = f + frame_len - 1
        if stop > n then stop = n end
        local v = snr_db(ref, new, f, stop + 1)
        if v < SEGSNR_LO then
            v = SEGSNR_LO
        elseif v > SEGSNR_HI then
            v = SEGSNR_HI
        end
        vals[#vals + 1] = v
        sum = sum + v
    end

    local sorted = {}
    for i = 1, #vals do sorted[i] = vals[i] end
    table.sort(sorted)

    local p5idx = math.ceil(0.05 * #sorted)
    if p5idx < 1 then p5idx = 1 end

    return sum / #vals, sorted[1], sorted[p5idx], vals
end

local function rms(a)
    local s = 0.0
    for i = 1, #a do s = s + a[i] * a[i] end
    return math.sqrt(s / #a)
end

--- 20*log10(rms(a)/rms(b)): lossy改动若带来增益漂移, 这个数会偏离0dB
local function rms_ratio_db(a, b)
    local ra, rb = rms(a), rms(b)
    if rb == 0 then
        if ra == 0 then return 0.0 end
        return math.huge
    end
    if ra == 0 then
        return -math.huge
    end
    return 20 * math.log10(ra / rb)
end

--- 整文件编码(tame.pcm -> 1280字节码流), 与既有bit-exact门控用同样的调用方式
local function encode_tame()
    local pcm = read_file(PCM_FILE)
    assert(#pcm == PCM_LEN, "pcm size mismatch: " .. #pcm)

    local encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "G729 encoder create failed")

    local inbuf = zbuff.create(PCM_LEN)
    inbuf:write(pcm)
    inbuf:used(#pcm)
    local outbuf = zbuff.create(REF_LEN)
    assert(codec.encode(encoder, inbuf, outbuf) == true, "encode failed")
    codec.release(encoder)

    assert(outbuf:used() == REF_LEN,
        "encoded size should be " .. REF_LEN .. ", got " .. outbuf:used())
    return outbuf:query(0, outbuf:used())
end

--- 码流解码回PCM(逐帧 codec.data), 与既有解码bit-exact门控一致
local function decode_bits(bits, tmp_file)
    assert(#bits % G729_BIT_FRAME == 0,
        "bitstream length " .. #bits .. " is not a multiple of " .. G729_BIT_FRAME)
    write_file(tmp_file, bits)

    local decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "G729 decoder create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")

    local frames = #bits // G729_BIT_FRAME
    local pcm_out = zbuff.create(4096)
    local chunks = {}
    for i = 1, frames do
        assert(codec.data(decoder, pcm_out, 4096) == true, "decode failed at frame " .. i)
        assert(pcm_out:used() == G729_PCM_FRAME,
            "frame " .. i .. " should decode " .. G729_PCM_FRAME .. " bytes, got " .. pcm_out:used())
        chunks[#chunks + 1] = pcm_out:query(0, pcm_out:used())
        if i % 16 == 0 then sys.wait(1) end
    end
    codec.release(decoder)
    os.remove(tmp_file)

    local pcm = table.concat(chunks)
    assert(#pcm == frames * G729_PCM_FRAME, "decoded size mismatch: " .. #pcm)
    return pcm
end

--- 码流逐字节/逐比特/逐帧差异(帧号0-based)
local function bitstream_diff(ref, new)
    assert(#ref == #new, "length mismatch: " .. #ref .. " vs " .. #new)

    local d = {bytes = 0, bits = 0, frames = 0, first_frame = -1}
    for i = 1, #ref do
        local a, b = string.byte(ref, i), string.byte(new, i)
        if a ~= b then
            d.bytes = d.bytes + 1
            d.bits = d.bits + POPCNT[a ~ b]
        end
    end
    for f = 0, (#ref // G729_BIT_FRAME) - 1 do
        local off = f * G729_BIT_FRAME + 1
        if string.sub(ref, off, off + G729_BIT_FRAME - 1) ~= string.sub(new, off, off + G729_BIT_FRAME - 1) then
            d.frames = d.frames + 1
            if d.first_frame < 0 then d.first_frame = f end
        end
    end
    return d
end

--- 度量一组PCM: 全局SNR / segSNR(mean,min,p5) / rms比值, 并定位最差分段
local function measure(ref, new, tag)
    local snr = snr_db(ref, new, 1, #ref + 1)
    local mean, min, p5, vals = segsnr_db(ref, new, SAMPLE_FRAME)
    local rms_db = rms_ratio_db(new, ref)

    local worst, worst_v = 1, vals[1]
    for i = 1, #vals do
        if vals[i] < worst_v then
            worst, worst_v = i, vals[i]
        end
    end

    log.info("g729_qual", string.format(
        "%s: snr=%.2fdB segsnr_mean=%.2fdB segsnr_min=%.2fdB segsnr_p5=%.2fdB rms_ratio=%+.2fdB worst_seg=%d/%d(%.2fdB, samples %d..%d)",
        tag, snr, mean, min, p5, rms_db, worst, #vals, worst_v,
        (worst - 1) * SAMPLE_FRAME + 1, worst * SAMPLE_FRAME))

    return {snr = snr, mean = mean, min = min, p5 = p5, rms = rms_db,
            worst = worst, vals = vals}
end

--- 把给定(0-based)帧号的10字节码流按位取反, 长度不变
local function corrupt_frames(bits, frames)
    local out = {}
    for f = 0, (#bits // G729_BIT_FRAME) - 1 do
        local frame = string.sub(bits, f * G729_BIT_FRAME + 1, (f + 1) * G729_BIT_FRAME)
        local hit = false
        for i = 1, #frames do
            if frames[i] == f then
                hit = true
                break
            end
        end
        if hit then
            local inv = {}
            for i = 1, #frame do
                inv[i] = string.char(string.byte(frame, i) ~ 0xFF)
            end
            frame = table.concat(inv)
        end
        out[#out + 1] = frame
    end
    return table.concat(out)
end

--- 1) 码流差异: 与ITU参考逐字节/逐比特/逐帧比较
function g729_quality_test.test_bitstream_diff()
    log.info("g729_qual", "bitstream diff: tame.pcm -> 1280 bytes vs tame_ref.bit")

    local ref = read_file(REF_FILE)
    assert(#ref == REF_LEN, "ref bitstream size mismatch: " .. #ref)

    local new = encode_tame()
    assert(#new == REF_LEN, "encoded size mismatch: " .. #new)

    local d = bitstream_diff(ref, new)
    log.info("g729_qual", string.format(
        "bytes: %d/%d differ, bits: %d/%d differ, frames: %d/%d differ, first differing frame: %d (0-based)",
        d.bytes, REF_LEN, d.bits, REF_LEN * 8, d.frames, FRAMES, d.first_frame))

    if EXPECT_BITEXACT then
        assert(d.bytes == 0, string.format(
            "EXPECT_BITEXACT but %d/%d bytes differ (%d bits, %d/%d frames, first frame %d)",
            d.bytes, REF_LEN, d.bits, d.frames, FRAMES, d.first_frame))
    end
end

--- 2) PCM质量: 参考码流与本次编码码流各自解码, 与源语音/参考解码做多维比较
function g729_quality_test.test_pcm_quality()
    log.info("g729_qual", "pcm quality: decode tame_ref.bit and the encode of tame.pcm")

    local ref_bits = read_file(REF_FILE)
    assert(#ref_bits == REF_LEN, "ref bitstream size mismatch: " .. #ref_bits)
    local new_bits = encode_tame()

    -- 解码链路自检: 参考码流的解码输出必须与ITU参考解码tame_ref.pst完全一致
    local ref_pcm_bytes = decode_bits(ref_bits, "/g729_qual_ref.bit")
    local pst = read_file(PST_FILE)
    assert(#pst == PCM_LEN, "pst size mismatch: " .. #pst)
    assert(ref_pcm_bytes == pst,
        "decode(tame_ref.bit) is NOT byte-identical with tame_ref.pst -- the decode path is not ITU conformant")
    log.info("g729_qual", "self-check: decode(tame_ref.bit) == tame_ref.pst (20480 bytes) -- OK")

    local new_pcm_bytes = decode_bits(new_bits, "/g729_qual_new.bit")
    local same = (new_pcm_bytes == ref_pcm_bytes)
    log.info("g729_qual", "new_pcm == ref_pcm: " .. tostring(same))

    local src = pcm16(read_file(PCM_FILE))
    local ref = pcm16(ref_pcm_bytes)
    local new = pcm16(new_pcm_bytes)
    assert(#src == 10240 and #ref == 10240 and #new == 10240, "sample count mismatch")

    local m_new_ref = measure(ref, new, "new vs ref (encoded vs ITU bitstream)")
    local m_ref_src = measure(src, ref, "ref vs tame.pcm (ITU decode vs source)")
    local m_new_src = measure(src, new, "new vs tame.pcm (our decode vs source)")

    local d = bitstream_diff(ref_bits, new_bits)
    log.info("g729_qual", string.format(
        "G729_QUALITY expect_bitexact=%s bitdiff=%d bits=%d frames=%d segsnr_div=%.2f segsnr_src=%.2f ref_src=%.2f rms=%.2fdB",
        tostring(EXPECT_BITEXACT), d.bytes, d.bits, d.frames,
        m_new_ref.mean, m_new_src.mean, m_ref_src.mean, m_new_ref.rms))

    if EXPECT_BITEXACT then
        assert(same, "EXPECT_BITEXACT but the decoded PCM differs from the reference decode")
    else
        -- 门槛用"解码PCM vs 源语音", 即与参考编解码器自身的固有质量比较。
        -- 不用"new vs ref": 那是发散度指标(见 test_metric_sensitivity 的注释), 任何改变
        -- 逐帧判决的lossy改动都会把它从35dB打到~20dB, 与可听质量无关。
        -- 参考固有质量(PC实测): segsnr 18.46dB / snr 15.65dB / rms -0.66dB。
        assert(m_new_src.mean >= m_ref_src.mean - MAX_SEGSNR_LOSS_DB, string.format(
            "lossy regressed source-referenced segSNR: new %.2fdB vs ref %.2fdB (loss %.2fdB > tol %.2fdB)",
            m_new_src.mean, m_ref_src.mean, m_ref_src.mean - m_new_src.mean, MAX_SEGSNR_LOSS_DB))
    end
end

--- 3) 度量灵敏度: 单帧码流损坏必须被量成明显劣化, 且损伤定位在损坏帧附近
-- 这一步是"质量测试通过"有意义的前提: 度量若对单帧损坏无反应, 就没有分辨率
-- 实测(PC): 损坏第64帧(0-based)后, 该帧及其后所有分段都劣化, 到文件结尾也只回到~9dB
-- —— G.729解码器的自适应码本(gain_pit可达1.2)是正反馈, 状态一旦被污染不会自行恢复,
-- 所以"新码流 vs 参考码流"的segSNR对任何导致逐帧判决不同的lossy改动都非常敏感:
-- 单帧全字节取反就已经把均值从35dB打到19.9dB。lossy阶段的35dB门槛实际上等价于
-- "不许有任何一帧的判决改变", 若门槛过严, 应改用"解码PCM vs 源语音"那条基线度量。
function g729_quality_test.test_metric_sensitivity()
    log.info("g729_qual", "metric sensitivity: corrupt one bitstream frame and re-measure")

    local ref_bits = read_file(REF_FILE)
    assert(#ref_bits == REF_LEN, "ref bitstream size mismatch: " .. #ref_bits)

    local ref_pcm_bytes = decode_bits(ref_bits, "/g729_qual_sref.bit")
    local ref = pcm16(ref_pcm_bytes)
    local clean = measure(ref, ref, "clean ref (self)")

    -- 单帧损坏: 第64帧(0-based)的10字节全部取反, 码流长度不变
    local CORRUPT_FRAME = 64
    local corr_bits = corrupt_frames(ref_bits, {CORRUPT_FRAME})
    assert(#corr_bits == REF_LEN, "corrupted bitstream must keep the same length")

    local corr_pcm_bytes = decode_bits(corr_bits, "/g729_qual_scorr.bit")
    assert(corr_pcm_bytes ~= ref_pcm_bytes, "corrupted decode is identical to the clean decode")
    local corr = pcm16(corr_pcm_bytes)

    local m_corr = measure(ref, corr, string.format("corrupt frame %d (0-based)", CORRUPT_FRAME))

    -- 损伤定位: 单帧损坏的最差分段应落在损坏帧附近(允许编解码器记忆扩散几帧)
    local expect_seg = CORRUPT_FRAME + 1     -- 80采样点/段, 段号1-based
    local off = m_corr.worst - expect_seg
    local damaged = 0
    local first_damaged = -1
    for i = 1, #m_corr.vals do
        if m_corr.vals[i] < 20.0 then
            damaged = damaged + 1
            if first_damaged < 0 then first_damaged = i end
        end
    end
    log.info("g729_qual", string.format(
        "worst segment %d (expected near %d, offset %+d segment = %+d ms), damaged segments (<20dB): %d/%d from segment %d to %d (%.1fdB at the end)",
        m_corr.worst, expect_seg, off, off * 10, damaged, #m_corr.vals,
        first_damaged, #m_corr.vals, m_corr.vals[#m_corr.vals]))

    assert(m_corr.mean < 30.0, string.format(
        "segSNR mean %.2fdB is not clearly damaged (expected < 30dB)", m_corr.mean))
    assert(m_corr.mean < clean.mean, string.format(
        "segSNR mean did not drop: clean %.2fdB vs corrupted %.2fdB", clean.mean, m_corr.mean))
    assert(m_corr.min < 20.0, string.format(
        "segSNR min %.2fdB is not clearly damaged (expected < 20dB)", m_corr.min))
    assert(math.abs(off) <= 10, string.format(
        "worst segment %d is not localised near the corrupted frame %d", m_corr.worst, expect_seg))

    -- 附加数据点(不参与断言): 连续3帧损坏
    local corr3_bits = corrupt_frames(ref_bits, {CORRUPT_FRAME, CORRUPT_FRAME + 1, CORRUPT_FRAME + 2})
    local corr3 = pcm16(decode_bits(corr3_bits, "/g729_qual_scorr3.bit"))
    local m_corr3 = measure(ref, corr3, string.format("corrupt frames %d..%d (3 frames)", CORRUPT_FRAME, CORRUPT_FRAME + 2))
    log.info("g729_qual", string.format(
        "sensitivity summary: clean segsnr=%.2fdB min=%.2fdB | 1 frame segsnr=%.2fdB min=%.2fdB | 3 frames segsnr=%.2fdB min=%.2fdB",
        clean.mean, clean.min, m_corr.mean, m_corr.min, m_corr3.mean, m_corr3.min))
end

return g729_quality_test
