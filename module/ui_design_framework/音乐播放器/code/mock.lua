--[[
@module mock
@summary 音乐播放器 HMI —— 曲目数据 / 设置默认值 / 运行时状态
         与 index.html 的 T[]、DEF 一一对应（8 首演示曲目）

         约定：
         1. 只放数据，不放控件、不调 airui。
         2. 所有可变状态挂在 mock.S（设置）与 mock.P（播放/交互），
            页面文件不要另开全局，否则预建的多屏之间对不上。
         3. 键名统一小写，存储与判断用同一套键（踩坑：中文键配英文判断）。
]]

local mock = {}

mock.PAGES = {
    { id = "play",      name = "媒体播放 / MEDIA" },
    { id = "library",   name = "曲库 / LIBRARY" },
    { id = "favorites", name = "收藏 / FAVORITES" },
    { id = "settings",  name = "设置 / SETTINGS" },
}

mock.MODES = { "列表循环", "单曲循环", "随机播放" }

-- 强调色：day 取压深色，night 取亮色（浅底用深墨才看得见）
mock.ACCENTS = {
    { key = "amber",  name = "琥珀", day = 0x96682C, night = 0xC8A26A },
    { key = "cyan",   name = "冷青", day = 0x356B72, night = 0x7FB0B6 },
    { key = "copper", name = "暖铜", day = 0x8F5334, night = 0xC08A6C },
}

mock.EQ_NAMES = { "平坦", "流行", "摇滚", "爵士", "古典" }
mock.EQ_VALS = {
    { 50, 50, 50, 50, 50 },
    { 38, 62, 58, 44, 56 },
    { 70, 44, 36, 62, 54 },
    { 46, 58, 66, 52, 44 },
    { 58, 42, 40, 48, 68 },
}

mock.FMTS = { "全部", "FLAC", "MP3", "WAV" }
mock.FMT_KEYS = { "all", "FLAC", "MP3", "WAV" }
mock.SORTS = { "默认排序", "按曲名", "按艺术家", "按时长" }
mock.SORT_KEYS = { "idx", "name", "artist", "dur" }

--[[ 曲目表：改这里就能换歌。
     g1/g2 封面底色，c1/c2 该曲目强调色；八首 c1 互不相同
     （踩坑："切歌看着没变" 就是主色撞色）]]
mock.TRACKS = {
    { n = "晴天",     en = "SUNNY DAY",                a = "周杰伦", al = "叶惠美",
      yr = 2003, d = 269, fmt = "FLAC · 44.1kHz / 16bit", art = "sun",
      g1 = 0x8FB8CE, g2 = 0xE3D2AE, c1 = 0xE2B96B, c2 = 0x7FA6BE },
    { n = "龙卷风",   en = "TORNADO",                  a = "周杰伦", al = "Jay",
      yr = 2000, d = 250, fmt = "FLAC · 44.1kHz / 16bit", art = "tornado",
      g1 = 0x3C4B52, g2 = 0x1B252B, c1 = 0x9FB7BC, c2 = 0xC2A178 },
    { n = "七里香",   en = "COMMON JASMINE ORANGE",    a = "周杰伦", al = "七里香",
      yr = 2004, d = 299, fmt = "FLAC · 48kHz / 24bit", art = "summer",
      g1 = 0xB9C79A, g2 = 0xE8D3A0, c1 = 0xC3A55F, c2 = 0x7E9A70 },
    { n = "稻香",     en = "FRAGRANCE OF RICE",        a = "周杰伦", al = "魔杰座",
      yr = 2008, d = 223, fmt = "MP3 · 320kbps", art = "rice",
      g1 = 0xD9B96A, g2 = 0x8E7A42, c1 = 0xE9CE86, c2 = 0xA58445 },
    { n = "夜曲",     en = "NOCTURNE",                 a = "周杰伦", al = "十一月的萧邦",
      yr = 2005, d = 226, fmt = "FLAC · 44.1kHz / 16bit", art = "nocturne",
      g1 = 0x2B3A56, g2 = 0x101A2B, c1 = 0xA8B6D6, c2 = 0xC2A178 },
    { n = "青花瓷",   en = "BLUE AND WHITE PORCELAIN", a = "周杰伦", al = "我很忙",
      yr = 2007, d = 239, fmt = "FLAC · 44.1kHz / 16bit", art = "porcelain",
      g1 = 0xEDF1EE, g2 = 0xC7D6DB, c1 = 0x3C6C96, c2 = 0x8AA5B4 },
    { n = "告白气球", en = "LOVE CONFESSION BALLOON",  a = "周杰伦", al = "周杰伦的床边故事",
      yr = 2016, d = 216, fmt = "MP3 · 320kbps", art = "balloon",
      g1 = 0xE7C6BA, g2 = 0xF0DED2, c1 = 0xC78374, c2 = 0xA6AFC0 },
    { n = "简单爱",   en = "SIMPLE LOVE",              a = "周杰伦", al = "范特西",
      yr = 2001, d = 270, fmt = "WAV · 44.1kHz / 16bit", art = "simple",
      g1 = 0x9FC5D6, g2 = 0xDCEBE8, c1 = 0x5E93A8, c2 = 0xD6A96E },
}

-- 设置默认值（html 的 DEF）
mock.DEF = {
    vol = 68, mode = 0, accent = "amber", eq = 1, fav = {},
    sound = true, spectrum = true, clock24 = true, sd = true, resume = true,
    theme = "day", sort = "idx", fmt = "all",
}

-- 音源状态标签：与 html 的 srcLabel() 一致（无本地 wav 时合成兜底）
mock.SRC_TAG, mock.SRC_SET = "SYNTH FALLBACK", "合成兜底"

mock.S = {}
for k, v in pairs(mock.DEF) do
    if type(v) == "table" then
        local t = {}
        for i = 1, #v do t[i] = v[i] end
        mock.S[k] = t
    else
        mock.S[k] = v
    end
end

mock.P = {
    i = 1, t = 0, playing = false,
    page = "play",
    lib_page = 1, q = "", sort_i = 1, fmt_i = 1,
    add_open = false, confirm_clear = false,
}

--------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------
function mock.pad2(x)
    x = math.floor(tonumber(x) or 0)
    return (x < 10 and "0" or "") .. x
end

function mock.fmt_t(s)
    s = math.floor(tonumber(s) or 0)
    if s < 0 then s = 0 end
    return mock.pad2(s / 60) .. ":" .. mock.pad2(s % 60)
end

function mock.track(i)
    return mock.TRACKS[((i - 1) % #mock.TRACKS) + 1]
end

function mock.is_fav(i)
    for k = 1, #mock.S.fav do
        if mock.S.fav[k] == i then return true, k end
    end
    return false, nil
end

function mock.set_fav(i, on)
    local has, k = mock.is_fav(i)
    if on and not has then
        mock.S.fav[#mock.S.fav + 1] = i
        return true
    elseif not on and has then
        table.remove(mock.S.fav, k)
        return true
    end
    return false
end

-- 按当前筛选/排序算出曲目下标列表（对应 html 的 filtered()）
function mock.filtered()
    local q = string.lower(mock.P.q or "")
    local out = {}
    for k = 1, #mock.TRACKS do
        local x = mock.TRACKS[k]
        local ok = true
        if q ~= "" then
            local hay = string.lower(x.n .. " " .. x.a .. " " .. x.al)
            if not string.find(hay, q, 1, true) then ok = false end
        end
        if ok and mock.S.fmt ~= "all" then
            if not string.find(x.fmt, mock.S.fmt, 1, true) then ok = false end
        end
        if ok then out[#out + 1] = k end
    end
    local sk = mock.S.sort
    if sk == "name" or sk == "artist" then
        local key = (sk == "name") and "n" or "a"
        table.sort(out, function(a, b) return mock.TRACKS[a][key] < mock.TRACKS[b][key] end)
    elseif sk == "dur" then
        table.sort(out, function(a, b) return mock.TRACKS[a].d < mock.TRACKS[b].d end)
    end
    return out
end

return mock
