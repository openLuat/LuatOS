--[[
@module  engine
@summary BEAT FORGE - 音序器引擎（采样时钟 / 步进调度 / PCM 混音 / 流式播放）
@version 1.0
@date    2026.10.22
@author  江访
@usage
一台"从采样时钟出发"的鼓机：
  1、synth.build() 开机合成 8 个鼓声采样表；
  2、混音任务按真实时间产出 PCM 缓冲，缓冲内按采样位置精确调度每一拍，
     命中的鼓声混进缓冲后经 exaudio.play_stream_write 流式推给 DAC；
  3、UI 侧只读 st（包络 / 脉冲 / 波形快照）+ playhead()，画面和声音同一台时钟。

=== 静音降级 ===
PC 模拟器 / 固件没有 exaudio 时进静音模式：混音照常跑（示波器仍有真实波形），
只是不推音频，节拍推进靠 sys.wait 按缓冲时长走。界面 100% 功能不受影响。

=== 时间基准 ===
sample_clock 是"已产出的采样数"（16000/秒），是全引擎唯一的时间真相；
mcu.ticks 只用于 playhead 外推，二者换算走 mcu.hz()（同 moto_dash）。

=== 节拍几何 ===
  步长 base = rate * 60 / bpm / 4（16 分音符）
  摇摆：偶数步（0 基）长 base+swing_off，奇数步短 base-swing_off，
  相邻两步平均仍是 base，鼓组"摇"起来但不会越走越偏。
]]

local T = require "theme"
local synth = require "synth"

local M = {}

local RATE = T.audio.rate
local NT = #T.tracks

-- ==================== 时间基准 ====================
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < -2147483648 then d = d + 4294967296 end
    return d
end

function M.timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
        log.info("beat", string.format("时间基准 mcu.hz()=%d", hz))
    else
        TICKS_PER_MS = 1
    end
end

-- ==================== 运行状态（UI 只读）====================
local st = {
    ready = false,
    silent = true,        -- 无音频硬件（PC / 固件未含 exaudio）
    playing = false,
    bpm = T.audio.bpm,
    swing = T.audio.swing,
    vol = T.audio.vol,
    pat_id = "A",
    step = 0,             -- 当前正在响的步 0..15
    beat = 0,             -- 已走拍数（1/4 音符）
    pulse = 0,            -- 节拍脉冲 1 -> 0，UI 每帧衰减
    env = {},             -- 轨道包络 1 -> 0，UI 每帧衰减
    mute = {},            -- 轨道静音
    wave = {},            -- 输出波形快照 -1..1（示波器用）
    wave_n = 96,
    pat = nil,            -- 当前工作图案 pat[track][step] = 0/1
    clock_t = 0,          -- sample_clock 最近一次推进的时刻
    step_lead = 0,        -- 距当前步起点已过去的采样数
}
M.st = st

-- ==================== 内部状态 ====================
local sounds          -- 合成采样
local pending = {}    -- 正在响的单发 {p, n, pos, off, gain}（p = int16 打包串）
local buf = {}        -- 混音缓冲（复用）
local pat_store = {}  -- 四套工作图案 { A = pat, B = pat, ... }

local sample_clock = 0      -- 已产出采样数
local abs_step = 0          -- 下一个待调度的绝对步号
local cur_abs = 0           -- 最近已调度步的绝对步号
local step_start_sample = 0 -- 最近已调度步的起点
local next_step_sample = 0  -- 下一步调度位置
local base_len = 0          -- 当前步长（采样）
local swing_off = 0

local function recalc_step_len()
    -- 采样数必须取整：步偏移直接当混音缓冲下标用，小数下标会读出 nil
    base_len = math.floor(RATE * 60 / st.bpm / 4 + 0.5)
    swing_off = math.floor(base_len * st.swing + 0.5)
end

-- 音量系数 = 滑块 x 主增益，打包与波形快照共用，示波器画的就是听到的。
-- 注意单位：mix_span 的增益含 32767 因子，buf 数值是"样本 x 32767"。
-- 打包必须除回 32767 再定标（折进 pack_gain，热路径仍是纯乘法）——
-- 1.x 之前漏了这步，PCM 输出常年满幅削波，是"又尖又爆"的真根因
local vol_gain = 0.45
local pack_gain = vol_gain / 32767

local function recalc_vol()
    vol_gain = (st.vol / 100) * (T.audio.master or 0.45)
    pack_gain = vol_gain / 32767
end

-- ==================== 图案 ====================
local function pat_new()
    local p = {}
    for t = 1, NT do
        p[t] = {}
        for s = 1, 16 do p[t][s] = 0 end
    end
    return p
end

local function pat_load(p, id)
    local src = T.patterns[id]
    if not src then return end
    for t = 1, NT do
        local row = src[T.tracks[t].id] or ""
        for s = 1, 16 do
            p[t][s] = (row:sub(s, s) == "1") and 1 or 0
        end
    end
end

-- ==================== 调度 ====================
local function schedule_step(step1, off)
    local p = st.pat
    for t = 1, NT do
        if p[t][step1] == 1 and not st.mute[t] then
            local snd = sounds[T.tracks[t].id]
            if snd then
                pending[#pending + 1] = {
                    p = snd.p, n = snd.n, pos = 1, off = off,
                    gain = T.tracks[t].gain * 32767,
                }
                st.env[t] = 1
            end
        end
    end
    -- 每拍（4 步）一次脉冲：反应堆 / 背景闪光跟着它呼吸
    if step1 % 4 == 1 then
        st.pulse = 1
        st.beat = st.beat + 1
    end
end

-- 波形快照：缓冲按 st.wave_n 段取"段内绝对值最大"，示波器直接画
local function snapshot(n)
    local wn = st.wave_n
    local per = math.floor(n / wn)
    if per < 1 then return end
    local vs = st.wave
    for i = 1, wn do
        local a = (i - 1) * per + 1
        local peak, sgn = 0, 0
        for k = a, a + per - 1 do
            local v = buf[k]
            local av = v < 0 and -v or v
            if av > peak then peak = av; sgn = v >= 0 and 1 or -1 end
        end
        -- 与打包同一条增益链 + 限幅：示波器画的就是听到的
        local v = peak * sgn / 32767 * vol_gain
        if v > 1 then v = 1 elseif v < -1 then v = -1 end
        vs[i] = v
    end
end

-- int16 LE 打包：1024 个一批（格式串缓存复用）。输出按分片交给
-- play_stream_write 直写音频流——绝不用 table.concat：
-- 真机长跑后堆碎片化，concat 要一块 4KB 连续内存，拿不到就 OOM（1.0 崩溃点）
local pk = {}
local fmt_cache = {}
local parts = {}
local function pack_buf(n)
    local np = 0
    local i = 1
    while i <= n do
        local j = i + 511               -- 512 个/批：与 synth.pack16 同规格，
        if j > n then j = n end         -- 单次 string.pack 参数少，规避 VM 栈边界问题
        local m = j - i + 1
        local fmt = fmt_cache[m]
        if not fmt then
            fmt = "<" .. string.rep("i2", m)
            fmt_cache[m] = fmt
        end
        for k = 1, m do
            local v = buf[i + k - 1] * pack_gain
            if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
            pk[k] = math.floor(v)
        end
        np = np + 1
        parts[np] = string.pack(fmt, table.unpack(pk, 1, m))
        i = j + 1
    end
    for k = np + 1, #parts do parts[k] = nil end   -- 复用表，掐掉上轮尾巴
    return parts, np
end

-- 把打包采样的一段直接解出来乘增益加进 buf：16 个一批直角展开、
-- 零临时表（每 128ms 一轮混音，杜绝 GC 碎片）；零头用逐个解码收尾
local F16 = "<i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2"
local u16 = string.unpack
local function mix_span(p, i0, base, cnt, g)
    local k = 0
    while cnt - k >= 16 do
        local a1, a2, a3, a4, a5, a6, a7, a8,
            a9, a10, a11, a12, a13, a14, a15, a16 =
            u16(F16, p, (i0 + k - 1) * 2 + 1)
        local d = base + k
        buf[d + 1] = buf[d + 1] + a1 * g
        buf[d + 2] = buf[d + 2] + a2 * g
        buf[d + 3] = buf[d + 3] + a3 * g
        buf[d + 4] = buf[d + 4] + a4 * g
        buf[d + 5] = buf[d + 5] + a5 * g
        buf[d + 6] = buf[d + 6] + a6 * g
        buf[d + 7] = buf[d + 7] + a7 * g
        buf[d + 8] = buf[d + 8] + a8 * g
        buf[d + 9] = buf[d + 9] + a9 * g
        buf[d + 10] = buf[d + 10] + a10 * g
        buf[d + 11] = buf[d + 11] + a11 * g
        buf[d + 12] = buf[d + 12] + a12 * g
        buf[d + 13] = buf[d + 13] + a13 * g
        buf[d + 14] = buf[d + 14] + a14 * g
        buf[d + 15] = buf[d + 15] + a15 * g
        buf[d + 16] = buf[d + 16] + a16 * g
        k = k + 16
    end
    while k < cnt do
        local d = base + k
        buf[d + 1] = buf[d + 1] + u16("<i2", p, (i0 + k - 1) * 2 + 1) * g
        k = k + 1
    end
end

-- ==================== 空间胶合（反馈 delay "房间"） ====================
-- 短回声垫在击打之间：尾巴把孤立的"嗒…嗒…"连成一片（"不连贯/发干"的解药）。
-- 回声路径一阶低通让重复声逐圈变闷（模拟空气吸收）；环形缓冲复用，零垃圾。
local DLY_N = 2048                -- 128ms @16k
local dly = nil
local dly_pos = 1
local dly_lp = 0
local function apply_room(n)
    if not dly then
        dly = {}
        for i = 1, DLY_N do dly[i] = 0 end
    end
    local wet = T.audio.room_wet or 0.18
    local fb = T.audio.room_fb or 0.30
    local lp_a = T.audio.room_lp or 0.32
    for i = 1, n do
        local x = buf[i]
        local di = dly_pos
        local y = dly[di]
        dly_lp = dly_lp + lp_a * (y - dly_lp)
        dly[di] = x + dly_lp * fb
        buf[i] = x + y * wet
        dly_pos = di + 1
        if dly_pos > DLY_N then dly_pos = 1 end
    end
end

-- ==================== 混音 ====================
--[[产出一整个 PCM 缓冲（n 采样），顺便推进采样时钟
@return string|nil PCM 数据（静音模式不打包，返回 nil）]]
local function mix_buffer(n, do_pack)
    for i = 1, n do buf[i] = 0 end
    local t0 = sample_clock

    -- 1、把落在本缓冲内的步全部调度掉（采样级对齐，不在帧边界上）
    if st.playing then
        if next_step_sample < t0 then next_step_sample = t0 end
        while next_step_sample < t0 + n do
            local off = math.floor(next_step_sample - t0 + 0.5)
            if off < 0 then off = 0 end
            schedule_step(abs_step % 16 + 1, off)
            cur_abs = abs_step
            step_start_sample = next_step_sample
            -- 偶数步长、奇数步短，摇摆只是把奇数步往后挪，两步均值不变
            local delta = base_len
            if (abs_step % 2) == 0 then
                delta = delta + swing_off
            else
                delta = delta - swing_off
            end
            next_step_sample = next_step_sample + delta
            abs_step = abs_step + 1
        end
    end

    -- 2、混入所有在响的单发（跨缓冲的尾巴留在 pending 里继续混）
    for i = #pending, 1, -1 do
        local h = pending[i]
        local p, n2, g = h.p, h.n, h.gain
        local pos, off = h.pos, h.off
        local kn = n2 - pos + 1
        local room = n - off
        if kn > room then kn = room end
        if kn > 0 then
            mix_span(p, pos, off, kn, g)
        end
        h.pos = pos + kn
        h.off = 0
        if h.pos > n2 then
            pending[i] = pending[#pending]
            pending[#pending] = nil
        end
    end

    -- 3、空间胶合 + 时钟推进 + 波形快照（快照取房间处理后的原始值，再交给打包限幅）
    apply_room(n)
    sample_clock = t0 + n
    st.clock_t = now_ms()
    st.step = cur_abs % 16
    st.step_lead = sample_clock - step_start_sample
    snapshot(n)

    if do_pack then return pack_buf(n) end
    return nil
end

-- ==================== PA 功放 ====================
-- PA功放开关，高电平使能
local function pa_set(on)
    gpio.setup(73, on and 1 or 0)
end

-- ==================== 音频任务 ====================
local function try_exaudio()
    local ex = rawget(_G, "exaudio")
    if ex then return ex end
    local ok, lib = pcall(require, "exaudio")
    if ok then return lib end
    return nil
end

local function on_play_event(event)
    -- 正常情况下流式播放不会结束；真结束了只记日志，混音任务继续跑
    -- cbfnc 只在播放完毕/停止时回调（结束类事件）：会话结束，关 PA
    pa_set(false)
    log.warn("beat", "音频播放事件", tostring(event))
end

local function mix_task()
    local ex = try_exaudio()
    -- 写粒度 2048 字节（1024 采样 / 64ms，满足"1024 整数倍"要求）：
    -- 比整块流缓冲细一半，触发延迟低、调度颗粒小
    local bytes = 2048
    if ex and ex.setup and ex.play_start then
        local ok = pcall(function()
            assert(ex.setup({
                model = "dac",          -- Air8607 内置 DAC + HT6873 功放
                pa_ctrl = 73,           -- AUDIOPA_EN = GPIO73，高电平使能
                pa_on_level = 1,
                dac_delay = 6,
            }), "exaudio.setup 返回失败")
            assert(ex.play_start({
                codec_id = 0,                 -- RAW/PCM
                type = 2,                     -- 流式
                cbfnc = on_play_event,
                sampling_rate = RATE,
                sampling_depth = 16,
                signed_or_unsigned = true,
            }), "exaudio.play_start 返回失败")
        end)
        if ok then
            st.silent = false
            pa_set(true)   -- 起播成功，开 PA
            local bs = ex.get_stream_buffer_size and ex.get_stream_buffer_size()
            log.info("beat", "音频就绪 流缓冲", bs or 0, "写粒度", bytes, "字节")
        else
            pa_set(false)  -- 起播失败，进静音模式，关 PA
            log.warn("beat", "exaudio 初始化失败，进静音模式（界面照常）")
        end
    else
        pa_set(false)      -- 无 exaudio 库，进静音模式，关 PA
        log.warn("beat", "无 exaudio 库，进静音模式（界面照常）")
    end

    local n = math.floor(bytes / 2)          -- 缓冲采样数（16bit 单声道）
    local buf_ms = n / RATE * 1000           -- 一缓冲的时长
    -- 流式模式用"领先量"节拍：始终保持约 2 缓冲"已产未播"的余量。
    -- 混音任务和 UI 同抢一个 Lua 调度器，UI 忙帧迟 100ms 很常见；
    -- 原来"产一块等一块"零余量，一饿流就断断续续（真机"不连贯"根因，
    -- 官方文档明言"需要及时传入音频流数据，不然会导致停止播放"）
    local TARGET_LEAD = buf_ms * 2
    local produced_ms, stream_t0 = 0, nil
    while true do
        local t0 = now_ms()
        if (not st.silent) and (not stream_t0) then stream_t0 = t0 end
        local data, npk = mix_buffer(n, not st.silent)
        produced_ms = produced_ms + buf_ms
        if data then
            -- 字段访问必须先取好再 pcall：ex 为 nil 时 `pcall(ex.xx, ...)`
            -- 在实参求值阶段就炸，整个混音任务带崩
            local wr = ex and ex.play_stream_write
            if not wr then
                st.silent = true
                pa_set(false)  -- 转静音模式，关 PA
                log.warn("beat", "无可用音频写入口，转静音模式")
            else
                for k = 1, npk do
                    local wok, ret = pcall(wr, data[k])
                    local okw = wok and ret ~= false
                    -- 写不进（流缓冲满）：等 10ms 重写同一片，绝不丢片——丢片就是爆音
                    for _ = 1, 20 do
                        if okw then break end
                        sys.wait(10)
                        wok, ret = pcall(wr, data[k])
                        okw = wok and ret ~= false
                    end
                    if not okw then
                        st.silent = true
                        pa_set(false)  -- 转静音模式，关 PA
                        log.warn("beat", "play_stream_write 连续失败，转静音模式")
                        break
                    end
                end
            end
        end
        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        if st.silent or not stream_t0 then
            -- 静音模式：等满本轮时长，让采样时钟和墙钟走同一速度
            local w = buf_ms - cost
            if w < 20 then w = 20 end
            sys.wait(w)
        else
            -- 流式模式：按"领先量"睡——余量够就等它被消耗，不够就立刻补产
            local el = tick_diff(now_ms(), stream_t0) / TICKS_PER_MS
            local lead = produced_ms - el
            if lead >= TARGET_LEAD then
                sys.wait(lead - TARGET_LEAD + 5)
            end
        end
    end
end

-- ==================== 对外接口 ====================
function M.boot()
    M.timebase()
    recalc_step_len()
    recalc_vol()
    for t = 1, NT do st.env[t] = 0; st.mute[t] = false end
    for i = 1, st.wave_n do st.wave[i] = 0 end
    -- 四套工作图案：预设装载进来随便改，切换图案不丢编辑
    for _, id in ipairs(T.pat_order) do
        pat_store[id] = pat_new()
        pat_load(pat_store[id], id)
    end
    st.pat = pat_store.A
    st.pat_id = "A"
    sounds = synth.build(RATE)
    st.ready = true
    log.info("beat", string.format("合成完成 %d 种鼓声，%d 轨 x 16 步", 8, NT))
    sys.taskInit(mix_task)
end

function M.play()
    if st.playing then return end
    st.playing = true
    pa_set(true)   -- 播放出声，开 PA
    abs_step = 0
    cur_abs = 0
    next_step_sample = sample_clock
    step_start_sample = sample_clock
    st.step_lead = 0
    log.info("beat", string.format("播放 PAT %s  BPM=%d", st.pat_id, st.bpm))
end

function M.stop()
    pa_set(false)  -- 停止即关 PA
    for i = #pending, 1, -1 do pending[i] = nil end   -- 停止即清 pending，尾巴随停止截断
    if not st.playing then return end
    st.playing = false
    st.pulse = 0
    log.info("beat", "停止")
end

function M.toggle_play()
    if st.playing then M.stop() else M.play() end
end

function M.set_bpm(v)
    v = math.floor(v + 0.5)
    if v < T.audio.bpm_min then v = T.audio.bpm_min end
    if v > T.audio.bpm_max then v = T.audio.bpm_max end
    st.bpm = v
    recalc_step_len()
end

function M.set_swing(v)
    if v < 0 then v = 0 elseif v > 0.3 then v = 0.3 end
    st.swing = v
    recalc_step_len()
end

function M.set_vol(v)
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    st.vol = math.floor(v + 0.5)
    recalc_vol()
end

function M.set_pat(id)
    if not pat_store[id] then return end
    st.pat_id = id
    st.pat = pat_store[id]
    log.info("beat", "切换图案", id)
end

function M.toggle_step(track, step1)
    local p = st.pat
    local v = 1 - p[track][step1]
    p[track][step1] = v
    return v
end

function M.toggle_mute(track)
    st.mute[track] = not st.mute[track]
    return st.mute[track]
end

function M.clear()
    local p = st.pat
    for t = 1, NT do
        for s = 1, 16 do p[t][s] = 0 end
    end
    log.info("beat", "图案已清空", st.pat_id)
end

-- 加花：尾拍通鼓滚奏 + 军鼓渐强，一下把气氛推上去
function M.fill()
    local p = st.pat
    p[6][13], p[6][15] = 1, 1              -- TOM
    p[2][14], p[2][16] = 1, 1              -- SNARE
    p[7][13], p[7][14], p[7][15], p[7][16] = 1, 1, 1, 1  -- RIM
    p[4][13], p[4][14], p[4][15], p[4][16] = 1, 1, 1, 1  -- HAT-C
    log.info("beat", "加花")
end

-- 手动触发一击（点反应堆 / 静音状态下当打击垫玩）
function M.hit(track)
    local snd = sounds and sounds[T.tracks[track].id]
    if not snd then return end
    pa_set(true)   -- 手动触发出声，开 PA
    pending[#pending + 1] = {
        p = snd.p, n = snd.n, pos = 1, off = 0,
        gain = T.tracks[track].gain * 32767,
    }
    st.env[track] = 1
end

--[[播放头（供 UI 画扫过光带）
@return number step  0..15 当前步
@return number frac  0..1.5 步内进度（>1 表示缓冲跨步，下一格微亮）]]
function M.playhead()
    if not st.playing then return st.step, 0 end
    local el = tick_diff(now_ms(), st.clock_t) / TICKS_PER_MS
    if el < 0 then el = 0 end
    local lead = st.step_lead + el / 1000 * RATE
    local frac = lead / base_len
    if frac < 0 then frac = 0 elseif frac > 1.5 then frac = 1.5 end
    return st.step, frac
end

return M
