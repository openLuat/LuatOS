--[[
@module  synth
@summary BEAT FORGE - 鼓声合成器（一次性合成 8 种单发 PCM 采样）
@version 1.2
@date    2026.10.22
@author  江访
@usage
开机时把 8 个鼓声合成成 int16 LE 打包串，引擎混音时按批解码累加。
存打包串而非数字表：2.6 万采样点的数字表要 200KB+ 常驻，真机堆被吃光后
连 concat 都拿不到连续内存（1.0 真机 OOM 根因）；打包串只要 56KB，
且混音解码零临时表，长跑不产生 GC 碎片。

音色四原则（真机反馈"不好听/太尖锐"的修正）：
1. 每个音首尾淡入淡出——收尾包络不为零就截断是爆音 click 的最大来源；
2. 噪声一律"限带"——保持插值压到 6kHz 以内再过一阶低通。16k 采样下纯白噪
   直顶奈奎斯特，又刺又炸（"太尖锐"主因）；
3. 全体过软饱和（tanh 近似）——圆瞬态、补奇次谐波的"暖"，去数字毛刺；
4. 噪声用自带 LCG 而不是 math.random——每次开机合成结果完全一致。

合成参数都写成"频率/衰减常数"这类音乐人能改的旋钮，改两个数就是另一种鼓。
]]

local M = {}

local TAU = math.pi * 2

-- ==================== 基础工具 ====================

-- 确定性白噪声，输出 -1..1
local function rng_new(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 1073741823.5 - 1
    end
end

-- 限带噪声：随机值保持 hold 个采样并线性插值，频谱压到 ~16k/(2*hold) 以内
local function noise_new(seed, hold)
    local rnd = rng_new(seed)
    local a, b = rnd(), rnd()
    local ph = hold
    return function()
        ph = ph + 1
        if ph > hold then
            ph = 1
            a = b
            b = rnd()
        end
        return a + (b - a) * (ph - 1) / hold
    end
end

-- 一阶低通，给噪声去火气（a 越小越闷）
local function lp_new(a)
    local v = 0
    return function(x)
        v = v + a * (x - v)
        return v
    end
end

local function alloc(n)
    local t = {}
    for i = 1, n do t[i] = 0 end
    return t
end

-- 软饱和：tanh 的 Padé 近似，圆瞬态、添奇次谐波的"暖度"。
-- 1.25 倍驱动小幅压缩峰值，比硬 clip 柔得多
local function soft_sat(t)
    for i = 1, #t do
        local x = t[i] * 1.25
        t[i] = x * (27 + x * x) / (27 + 9 * x * x)
    end
    return t
end

-- 抛光低通：削掉饱和新生的高频毛刺（α=0.85 约 4.8kHz，不伤镲的亮）
local function polish(t)
    local lp = lp_new(0.85)
    for i = 1, #t do t[i] = lp(t[i]) end
    return t
end

-- 首尾整形：起振淡入杀起始 click，收尾淡出杀结束 click
-- （在 soft_sat/polish 之后调用，强制首尾样本归零）
local function shape(t, rate, atk_ms, tail_ms)
    local n = #t
    local na = math.floor(rate * atk_ms / 1000)
    if na > 1 then
        for i = 1, na do t[i] = t[i] * (i - 1) / na end
    end
    local nf = math.floor(rate * tail_ms / 1000)
    if nf > 1 and nf < n then
        for i = n - nf + 1, n do
            t[i] = t[i] * (n - i) / nf
        end
    end
    return t
end

-- 归一化到峰值 0.98：每个鼓声单独定标，混音时靠轨道增益配平
local function normalize(t)
    local peak = 0
    for i = 1, #t do
        local v = t[i]
        if v < 0 then v = -v end
        if v > peak then peak = v end
    end
    if peak > 1e-6 then
        local k = 0.98 / peak
        for i = 1, #t do t[i] = t[i] * k end
    end
    return t
end

-- 打包成 int16 LE 串：512 个一批，格式串缓存复用
local fmt_cache = {}
local function pack16(t)
    local n = #t
    local parts = {}
    local np = 0
    local i = 1
    while i <= n do
        local j = i + 511
        if j > n then j = n end
        local m = j - i + 1
        local fmt = fmt_cache[m]
        if not fmt then
            fmt = "<" .. string.rep("i2", m)
            fmt_cache[m] = fmt
        end
        local args = {}
        for k = 1, m do
            local v = t[i + k - 1] * 32767
            if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
            args[k] = math.floor(v + 0.5)
        end
        np = np + 1
        parts[np] = string.pack(fmt, table.unpack(args, 1, m))
        i = j + 1
    end
    return table.concat(parts, "", 1, np)
end

-- ==================== 8 种鼓声 ====================
-- 底鼓：正弦扫频 157Hz -> 47Hz + 低通软 click
local function build_kick(rate)
    local n = math.floor(rate * 0.28)
    local out = alloc(n)
    local rnd = noise_new(101, 2)
    local click = lp_new(0.18)
    local ph = 0
    for i = 1, n do
        local t = (i - 1) / rate
        local f = 47 + 110 * math.exp(-t * 30)
        ph = ph + TAU * f / rate
        local v = math.sin(ph) * math.exp(-t * 7.5)
        if t < 0.006 then
            v = v + click(rnd()) * 0.10 * (1 - t / 0.006)
        end
        out[i] = v
    end
    return out
end

-- 军鼓：185Hz 基音 + 低通噪声，双衰减包络
local function build_snare(rate)
    local n = math.floor(rate * 0.22)
    local out = alloc(n)
    local rnd = noise_new(202, 2)
    local lpf = lp_new(0.38)
    local ph = 0
    for i = 1, n do
        local t = (i - 1) / rate
        ph = ph + TAU * 185 / rate
        out[i] = math.sin(ph) * math.exp(-t * 20) * 0.5
            + lpf(rnd()) * math.exp(-t * 14) * 0.75
    end
    return out
end

-- 拍手：3 个间隔 9ms 的低通噪声短爆 + 拖尾
local function build_clap(rate)
    local n = math.floor(rate * 0.20)
    local out = alloc(n)
    local rnd = noise_new(303, 2)
    local lpf = lp_new(0.32)
    local bursts = { 0, 0.009, 0.018 }
    for i = 1, n do
        local t = (i - 1) / rate
        local v = lpf(rnd()) * math.exp(-t * 10) * 0.4
        for b = 1, 3 do
            local dt = t - bursts[b]
            if dt >= 0 and dt < 0.035 then
                v = v + lpf(rnd()) * math.exp(-dt * 95) * 0.9
            end
        end
        out[i] = v
    end
    return out
end

-- 踩镲：限带噪声 + 单阶高通削低频，再低通去"滋滋"火气；闭镲短 / 开镲长
local function build_hat(rate, len, decay, seed)
    local n = math.floor(rate * len)
    local out = alloc(n)
    local rnd = noise_new(seed, 2)
    local lpf = lp_new(0.5)
    local prev = 0
    for i = 1, n do
        local t = (i - 1) / rate
        local x = rnd()
        local hp = x - prev
        prev = x
        out[i] = lpf(hp) * math.exp(-t * decay)
    end
    return out
end

-- 通鼓：正弦扫频 235Hz -> 105Hz
local function build_tom(rate)
    local n = math.floor(rate * 0.24)
    local out = alloc(n)
    local ph = 0
    for i = 1, n do
        local t = (i - 1) / rate
        local f = 105 + 130 * math.exp(-t * 24)
        ph = ph + TAU * f / rate
        out[i] = math.sin(ph) * math.exp(-t * 11)
    end
    return out
end

-- 边击：1650Hz 短音 + 低通 click，干脆但不扎耳的"嗒"
local function build_rim(rate)
    local n = math.floor(rate * 0.05)
    local out = alloc(n)
    local rnd = noise_new(404, 2)
    local lpf = lp_new(0.35)
    local ph = 0
    for i = 1, n do
        local t = (i - 1) / rate
        ph = ph + TAU * 1650 / rate
        out[i] = math.sin(ph) * math.exp(-t * 100) * 0.7
            + lpf(rnd()) * math.exp(-t * 180) * 0.28
    end
    return out
end

-- 贝斯：55Hz 正弦 + 轻二谐波，慢衰减垫底（收尾淡出给足，杜绝尾部爆音）
local function build_bass(rate)
    local n = math.floor(rate * 0.42)
    local out = alloc(n)
    local ph = 0
    for i = 1, n do
        local t = (i - 1) / rate
        ph = ph + TAU * 55 / rate
        out[i] = (math.sin(ph) * 0.82 + math.sin(ph * 2) * 0.22)
            * math.exp(-t * 4.2)
    end
    return out
end

--[[合成全部鼓声
@param number rate 采样率（须与 engine 播放采样率一致，默认 16000）
@return table sounds { KICK={p=打包串,n=长度}, ... } 键名与 theme.tracks 的 id 对齐
]]
function M.build(rate)
    rate = rate or 16000
    -- {发声原始表, 淡入ms, 淡出ms}：shape 必须放在饱和/抛光之后，
    -- 才能保证最终首尾样本严格归零（防 click 的最后一道闸）
    local spec = {
        KICK  = { build_kick(rate), 1, 40 },
        SNARE = { build_snare(rate), 2, 25 },
        CLAP  = { build_clap(rate), 1, 30 },
        HATC  = { build_hat(rate, 0.06, 95, 505), 1, 15 },
        HATO  = { build_hat(rate, 0.28, 11, 606), 1, 60 },
        TOM   = { build_tom(rate), 2, 25 },
        RIM   = { build_rim(rate), 1, 6 },
        BASS  = { build_bass(rate), 4, 45 },
    }
    local out = {}
    for k, s in pairs(spec) do
        local tbl = polish(soft_sat(s[1]))
        normalize(shape(tbl, rate, s[2], s[3]))
        out[k] = { p = pack16(tbl), n = #tbl }
    end
    return out
end

return M
