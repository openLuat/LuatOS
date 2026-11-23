--[[
@module mock
@summary 音频频谱页的静态数据（纯数据模块，不创建任何控件）
         采样率档位、曲目、频段定义
]]

local mock = {}

-- 采样率档位：切档同时改 FFT 谱线数（柱数），这样点一下肉眼就能看出区别
--   44.1 kHz → 36 根   48 kHz → 44 根   96 kHz → 60 根
-- 实机性能：谱线数直接决定每帧 set_items 的图元数量，60 根是流畅度与观感的上限，
-- 再往上加（72）帧率明显掉，画面发卡。
mock.RATES = {
    { label = "48 kHz",   hz = 48000, bins = 44 },
    { label = "44.1 kHz", hz = 44100, bins = 36 },
    { label = "96 kHz",   hz = 96000, bins = 60 },
}

-- 曲库（上一首/下一首切换）
-- c1/c2/c3：封面三层渐变的颜色（外 → 内）
-- accent    ：这首歌的"主色"，进度条 / 播放键 / 中心唱盘统一用它。
--             必须单独给，不能让 accent 直接取 c1 —— 之前 Afterglow 的外圈
--             也是青色，跟上一首撞色，切歌后中心盘/播放键看着"没变"。
mock.TRACKS = {
    { name = "霓虹地平线", artist = "极光实验室 · 午夜现场", dur = 198,
      c1 = 0x7C5CFF, c2 = 0x3B82F6, c3 = 0x22D3EE, accent = 0x7C5CFF },
    { name = "深海暗流",   artist = "潜入 · 蓝调时刻",       dur = 234,
      c1 = 0x22D3EE, c2 = 0x7C5CFF, c3 = 0x2E6BFF, accent = 0x2E6BFF },
    { name = "余晖",       artist = "枫与诺克斯 · 信号",     dur = 176,
      c1 = 0x22D3EE, c2 = 0x8B5CF6, c3 = 0xF472B6, accent = 0xF472B6 },
    { name = "玻璃雨",     artist = "顶点 · 夜曲",           dur = 212,
      c1 = 0xFBBF24, c2 = 0xF43F5E, c3 = 0xEC4899, accent = 0xFBBF24 },
}

-- 频段（与右侧 LOW/MID/HIGH 三行一一对应）
-- name 直接给中文短名（右侧频段栏一行只有 40px 宽）
mock.BANDS = {
    { key = "low",  name = "低频", cn = "低频" },
    { key = "mid",  name = "中频", cn = "中频" },
    { key = "high", name = "高频", cn = "高频" },
}

-- 频点换算：谱线 index(1..n) → 20Hz ~ 20kHz（对数）
function mock.freq(idx, n)
    if not n or n < 2 then return 20 end
    local k = (idx - 1) / (n - 1)
    return 20 * (1000 ^ k)
end

function mock.freq_text(idx, n)
    local f = mock.freq(idx, n)
    if f < 1000 then
        return string.format("%d Hz", math.floor(f + 0.5))
    end
    return string.format("%.1f kHz", f / 1000)
end

return mock
