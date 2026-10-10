--- g729逐阶段周期剖析测试模块
-- 用 codec.g729prof() 读取编码/解码每个阶段累计的CPU周期数与调用次数, 输出按ticks降序的分解
-- 兼作回归: 剖析器关闭时编码码流必须与ITU参考 tame_ref.bit 逐字节一致
-- @module g729_profile_test

local sys = require("sys")
-- codec是C内置模块, 通过全局变量访问(非require)
local codec = codec

local g729_profile_test = {}

-- ITU TAME 测试序列: 20480字节PCM(16bit/8kHz/单声道) -> 1280字节码流(128帧)
local PCM_FILE = "/luadb/tame.pcm"
local REF_FILE = "/luadb/tame_ref.bit"
local PCM_LEN = 20480
local REF_LEN = 1280
local G729_PCM_FRAME = 160   -- 80采样点 * 2字节, 一帧PCM
local FRAMES = PCM_LEN / G729_PCM_FRAME  -- 128帧
local MIN_SLOTS = 24         -- 剖析器阶段数(enc.* 21个 + dec.* 3个), 少于此说明端口没接上

local function read_file(path)
    local f = io.open(path, "rb")
    assert(f ~= nil, "open failed: " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

-- 打印一次统计: 按ticks降序输出每个有调用的阶段与总占比; 返回 (total_ticks, have_data)
local function dump_profile(tag, st)
    assert(type(st) == "table", tag .. ": no profile table returned")
    assert(st.slots and st.slots >= MIN_SLOTS,
        tag .. ": slot count " .. tostring(st.slots) .. " < " .. MIN_SLOTS .. " (g729 profiling not wired up?)")

    local rows, total = {}, 0
    for name, v in pairs(st) do
        if type(v) == "table" and v.calls then
            total = total + v.ticks
            if v.calls > 0 then
                rows[#rows + 1] = {name = name, ticks = v.ticks, calls = v.calls}
            end
        end
    end
    table.sort(rows, function(a, b) return a.ticks > b.ticks end)

    for _, r in ipairs(rows) do
        log.info("g729_prof", string.format("%-14s ticks=%-10d calls=%-6d avg=%-8.1f share=%.1f%%",
            r.name, r.ticks, r.calls, r.ticks / r.calls, 100 * r.ticks / total))
    end
    log.info("g729_prof", string.format("%s total_ticks=%d frames=%d per_frame=%.1f slots_reported=%d",
        tag, total, FRAMES, total / FRAMES, #rows))

    if total == 0 or #rows == 0 then
        -- 计数器的宽度/单位未知, 这里只保证"有没有数", 不做任何绝对值的解读
        log.warn("g729_prof", tag .. ": every slot reports 0 ticks -- the cycle counter appears UNAVAILABLE, " ..
            "read this run as NO DATA, not as zero cost")
        return total, false
    end
    return total, true
end

local function check_slots(st, expect, tag)
    for name, calls in pairs(expect) do
        local v = st[name]
        assert(v ~= nil, tag .. ": slot " .. name .. " missing from profile table")
        assert(v.calls == calls,
            tag .. ": slot " .. name .. " calls=" .. tostring(v.calls) .. ", expected " .. calls)
        assert(v.ticks > 0, tag .. ": slot " .. name .. " reports 0 ticks")
    end
end

--- 编码逐阶段分解: 先预热一趟(填满缓存/touch所有代码路径), 再清零统计测量128帧
function g729_profile_test.test_profile_breakdown()
    log.info("g729_prof", "encode stage breakdown: 128 frames")

    local pcm = read_file(PCM_FILE)
    assert(#pcm == PCM_LEN, "pcm size mismatch: " .. #pcm)

    codec.g729prof(true)   -- 启用并清零
    local encoder = codec.create(codec.G729, false)
    assert(encoder ~= nil, "G729 encoder create failed")

    local inbuf = zbuff.create(G729_PCM_FRAME)
    local outbuf = zbuff.create(16)

    -- 预热趟: 不计入统计
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

    -- 正式测量: 再清一次计数器
    codec.g729prof(true)

    for i = 1, FRAMES do
        local pos = (i - 1) * G729_PCM_FRAME + 1
        inbuf:seek(0)
        inbuf:write(pcm:sub(pos, pos + G729_PCM_FRAME - 1))
        inbuf:used(G729_PCM_FRAME)
        outbuf:seek(0)
        outbuf:used(0)
        assert(codec.encode(encoder, inbuf, outbuf) == true, "encode failed at frame " .. i)
        if i % 8 == 0 then sys.wait(1) end
    end

    -- 先读表再关闭(关闭会清零)
    local st = codec.g729prof()
    codec.g729prof(false)
    codec.release(encoder)

    local _, have_data = dump_profile("ENCODE", st)
    if have_data then
        -- enc.sf.filter 由两段组成(subframe前半: h1+xn, 后半: y1+gain_pit+xn2), 所以是 2 * 帧数 * 2子帧
        -- enc.sf.pitch 现在只包 g729_Enc_lag3(每子帧1次); g729_Pitch_fr3_fast 由
        -- enc.pitch.corhx/int/frac 三个子槽记账(每个子帧各1次, frac 早退路径也只记1次)
        -- enc.lspq.qua 已不再记账, 由 6 个 enc.lspq.* 子槽替代(不再包整只 g729_Qua_lsp)
        check_slots(st, {
            ["enc.pre"]      = FRAMES,
            ["enc.lpc"]      = FRAMES,
            ["enc.vad"]      = FRAMES,
            ["enc.wsp"]      = FRAMES,
            ["enc.sf.filter"] = FRAMES * 4,
            ["enc.sf.pitch"] = FRAMES * 2,
            ["enc.sf.fixed"] = FRAMES * 2,
            ["enc.sf.gain"]  = FRAMES * 2,
            ["enc.misc"]     = FRAMES,
            -- g729_Pitch_fr3_fast: 每帧2子帧, 每子帧各1段
            ["enc.pitch.corhx"] = FRAMES * 2,
            ["enc.pitch.int"]   = FRAMES * 2,
            ["enc.pitch.frac"]  = FRAMES * 2,
            -- g729_Qua_lsp: conv=lsf2+lsf2(2段), wgt=1, presel=2模式,
            -- sel12=2模式*(sel1+sel2), pred=2模式*3段+last_select, quant=1
            ["enc.lspq.conv"]   = FRAMES * 2,
            ["enc.lspq.wgt"]    = FRAMES,
            ["enc.lspq.presel"] = FRAMES * 2,
            ["enc.lspq.sel12"]  = FRAMES * 4,
            ["enc.lspq.pred"]   = FRAMES * 7,
            ["enc.lspq.quant"]  = FRAMES,
            -- 留在 cod_ld8a.c 里未拆的 LSP 插值/加权段
            ["enc.lspq.waz"]    = FRAMES,
        }, "ENCODE")
    end
end

--- 解码逐阶段分解: 参考码流写临时文件, 预热一趟后清零统计, 再测128帧
function g729_profile_test.test_decode_profile()
    log.info("g729_prof", "decode stage breakdown: 128 frames")

    local ref = read_file(REF_FILE)
    assert(#ref == REF_LEN, "ref bitstream size mismatch: " .. #ref)

    local tmp_file = "/g729_profile_dec.bit"
    local f = io.open(tmp_file, "wb")
    assert(f ~= nil, "open tmp file for write failed")
    f:write(ref)
    f:close()

    codec.g729prof(true)
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

    -- 正式测量: 码流已读到末尾, 重建解码器后清零
    decoder = codec.create(codec.G729, true)
    assert(decoder ~= nil, "G729 decoder re-create failed")
    assert(codec.info(decoder, tmp_file) == true, "codec.info failed")
    codec.g729prof(true)

    for i = 1, FRAMES do
        assert(codec.data(decoder, pcm_out, 4096) == true, "decode failed at frame " .. i)
        if i % 16 == 0 then sys.wait(1) end
    end

    local st = codec.g729prof()
    codec.g729prof(false)
    codec.release(decoder)
    os.remove(tmp_file)

    local _, have_data = dump_profile("DECODE", st)
    if have_data then
        check_slots(st, {
            ["dec.main"]     = FRAMES,
            ["dec.postfilt"] = FRAMES,
            ["dec.post"]     = FRAMES,
        }, "DECODE")
    end
end

--- 剖析器关闭时的编码bit-exact门控: 插桩不得改变码流
function g729_profile_test.test_profile_bitexact_still_ok()
    log.info("g729_prof", "encode bit-exact gate, profiler disabled")

    local pcm = read_file(PCM_FILE)
    local ref = read_file(REF_FILE)
    assert(#pcm == PCM_LEN and #ref == REF_LEN, "fixture size mismatch")

    codec.g729prof(false)   -- 统计关闭

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

    log.info("g729_prof", "encode bit-exact PASS (profiler off), 128 frames")
end

return g729_profile_test
