--[[
@module mock
@summary 车载电脑 HMI - 虚拟模拟数据与交互状态（全局 MOCK）
数据与 preview.html 静态稿一致；交互状态由各页面通过 MOCK 的方法修改，
页面刷新回调（1.5s）读 MOCK 的值刷新 label。
]]

MOCK = MOCK or {}

--------------------------------------------------------------------
-- 顶栏
--------------------------------------------------------------------
MOCK.user = { name = "Joel Stokes" }
MOCK.time_str = "上午 9:41"

--------------------------------------------------------------------
-- 天气（首页卡 + 天气页 + 导航页天气卡）
--------------------------------------------------------------------
MOCK.weather = {
    city  = "杭州市",
    area  = "杭州市,西湖区",
    temp  = 27,  feels = 29,  cond = "小雨",
    rain  = "1", hum = "60%", aqi = "3级",
    tip   = "有零星阵雨。最低气温 19°。",
    date  = "11月17日 今天",
    nav_city = "上海市", nav_temp = 29, nav_cond = "小雨",
    -- 每小时预报（图表 / 列表共用；v=温度°C，p=降水概率%，fv=体感°C，ic=图标）
    hours = {
        { t = "17:00", v = 21, p = 8,  fv = 29, ic = "rain",   cond = "降雨" },
        { t = "当前",  v = 23, p = 86, fv = 20, ic = "rain",   cond = "降雨" },
        { t = "19:00", v = 27, p = 46, fv = 30, ic = "cloud",  cond = "多云" },
        { t = "21:00", v = 21, p = 85, fv = 27, ic = "moon",   cond = "晴夜" },
        { t = "23:00", v = 18, p = 79, fv = 24, ic = "moon",   cond = "晴夜" },
        { t = "01:00", v = 18, p = 77, fv = 23, ic = "moon",   cond = "晴夜" },
        { t = "03:00", v = 25, p = 7,  fv = 26, ic = "partly", cond = "局部多云" },
        { t = "05:00", v = 21, p = 15, fv = 28, ic = "sun",    cond = "晴朗" },
        { t = "07:00", v = 23, p = 20, fv = 29, ic = "partly", cond = "多云" },
        { t = "09:00", v = 21, p = 30, fv = 27, ic = "cloud",  cond = "多云" },
        { t = "11:00", v = 22, p = 40, fv = 28, ic = "cloud",  cond = "多云" },
        { t = "13:00", v = 26, p = 35, fv = 30, ic = "cloud",  cond = "多云" },
    },
    -- 七日预报（日期数字 + 星期 + 图标 + 高低温 + 天气描述）
    days = {
        { d = "17", w = "今天", ic = "rain",   hi = 28, lo = 19, cond = "小雨" },
        { d = "18", w = "明天", ic = "cloud",  hi = 28, lo = 16, cond = "多云" },
        { d = "19", w = "周四", ic = "partly", hi = 27, lo = 21, cond = "局部多云" },
        { d = "20", w = "周五", ic = "partly", hi = 25, lo = 17, cond = "局部多云" },
        { d = "21", w = "周六", ic = "cloud",  hi = 28, lo = 17, cond = "多云" },
        { d = "22", w = "周日", ic = "sun",    hi = 30, lo = 21, cond = "晴朗" },
        { d = "23", w = "周一", ic = "cloud",  hi = 26, lo = 16, cond = "多云" },
    },
    -- 与「天气预报」工程一致的 9 个指标
    tabs = { "概览", "降水", "风速", "湿度", "云量", "气压",
             "紫外线", "可见度", "体感温度" },
    tab_idx = 1,
    view = "chart",   -- "chart" / "list"
    feel = false,     -- 概览右侧「体感温度」开关
    chips = { "空气质量 70", "风速 东风 2级", "湿度 93%",
              "能见度 2.6 公里", "气压 1020 hPa", "露点 17°" },
}

-- 切换日期（点击七日卡）：把选中日数据同步到 weather 顶层字段，
-- 页面渲染只读 weather.temp/feels/cond/tip/date/hours，切完 rerender 即可。
-- 按指标 tab 生成 12 个点的序列（确定性公式，不用随机数，
-- 否则每次重绘曲线都在跳）
-- 返回 { vals, y_min, y_max, color 语义名, type, unit }
function MOCK.weather_series(tab, feel)
    local h = MOCK.weather.hours
    local vals, lo, hi = {}, 999, -999
    for i = 1, #h do
        local v
        if tab == 1 then
            v = feel and h[i].fv or h[i].v
        elseif tab == 2 then
            v = h[i].p
        elseif tab == 3 then
            v = 6 + (h[i].v * 7 + i * 3) % 24          -- 6~29 km/h
        elseif tab == 4 then
            v = 52 + (h[i].p * 3 + i * 5) % 43         -- 52~94 %
        elseif tab == 5 then
            v = 25 + (h[i].p + i * 7) % 66             -- 25~90 %
        elseif tab == 6 then
            v = 1006 + (h[i].v * 2 + i) % 20           -- 1006~1025 hPa
        elseif tab == 7 then
            local hh = (17 + i * 2) % 24               -- 真实昼夜规律
            v = (hh >= 6 and hh <= 18) and math.floor(11 * math.sin(math.pi * (hh - 6) / 12) + 0.5) or 0
        elseif tab == 8 then
            v = 5 + (h[i].p + i * 11) % 16             -- 5~20 km
        else
            v = h[i].fv
        end
        vals[i] = v
        if v < lo then lo = v end
        if v > hi then hi = v end
    end
    -- 取整刻度，上下各留一点余量，避免曲线贴边
    local pad = math.max(1, math.floor((hi - lo) / 8 + 0.5))
    lo = math.max(0, lo - pad)
    hi = hi + pad
    if hi - lo < 4 then hi = lo + 4 end
    local color = (tab == 2) and "cyan" or (tab == 1 or tab == 9) and "yellow" or "blue2"
    return { vals = vals, y_min = lo, y_max = hi,
             color = color, type = (tab == 2) and "bar" or "line" }
end

MOCK.weather.cur = 1
MOCK.weather.base = {
    temp = 27, feels = 29, cond = "小雨",
    tip = "有零星阵雨。最低气温 19°。",
    date = "11月17日 今天",
}
MOCK.weather.base.hours = MOCK.weather.hours

local WX_T     = { "17:00", "当前", "19:00", "21:00", "23:00", "01:00",
                   "03:00", "05:00", "07:00", "09:00", "11:00", "13:00" }
local WX_ICONS = { "rain", "rain", "cloud", "moon", "moon", "moon",
                   "partly", "sun", "sun", "sun", "partly", "cloud" }
local WX_CONDS = { "降雨", "降雨", "多云", "晴夜", "晴夜", "晴夜",
                   "局部多云", "晴朗", "晴朗", "晴朗", "多云", "多云" }

function MOCK.weather_select(i)
    local w = MOCK.weather
    local d = w.days[i]
    if not d then return end
    w.cur = i
    if i == 1 then
        w.temp, w.feels, w.cond = w.base.temp, w.base.feels, w.base.cond
        w.tip, w.date = w.base.tip, w.base.date
        w.hours = w.base.hours
        return
    end
    local s = tonumber(d.d) or i
    w.temp = d.hi
    w.feels = d.hi - 2
    w.cond = d.cond or "多云"
    w.tip = d.cond .. "。最低气温 " .. d.lo .. "°。"
    w.date = "11月" .. d.d .. "日 " .. d.w
    local hrs = {}
    for k = 1, 12 do
        local v = 16 + ((s * 7 + k * 5) % 14)          -- 16..29
        local p = 5 + ((s * 13 + k * 11) % 90)         -- 5..94
        hrs[k] = { t = WX_T[k], v = v, p = p, fv = v + ((s + k) % 3) + 1,
                   ic = WX_ICONS[k], cond = WX_CONDS[k] }
    end
    w.hours = hrs
end

--------------------------------------------------------------------
-- 空调（首页拨盘 / 底栏双区温度 / 空调页共用一套状态）
--------------------------------------------------------------------
MOCK.ac = {
    t = { l = 23, r = 19 },          -- 底栏双区温度（首页拨盘显示 l）
    temp = { l = 25, r = 26 },       -- 空调页温度柱（.tempcol .v）
    seat = 2,                        -- 座椅角度档
    fan  = 3,                        -- 风量档
    on   = true,                     -- 空调开关
    recirc_on = true,                -- 内循环（底部第 3 个圆钮点亮）
    dial_deg = 210,                  -- 首页拨盘进度（对应 conic 210deg 起 120deg）
}
local AC_MIN, AC_MAX = 16, 30
local function _clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

function MOCK.ac_step(key, d)          -- 底栏双区温度 ±1，联动首页拨盘
    MOCK.ac.t[key] = _clamp(MOCK.ac.t[key] + d, AC_MIN, AC_MAX)
end
function MOCK.ac_temp_step(key, d)     -- 空调页温度柱 ±1
    MOCK.ac.temp[key] = _clamp(MOCK.ac.temp[key] + d, AC_MIN, AC_MAX)
end
function MOCK.ac_dial_step(d)          -- 首页拨盘 ±1
    MOCK.ac.t.l = _clamp(MOCK.ac.t.l + d, AC_MIN, AC_MAX)
end
function MOCK.ac_seat_step(d) MOCK.ac.seat = _clamp(MOCK.ac.seat + d, 0, 5) end
function MOCK.ac_fan_step(d)  MOCK.ac.fan  = _clamp(MOCK.ac.fan + d, 0, 7) end
function MOCK.ac_power() MOCK.ac.on = not MOCK.ac.on end

--------------------------------------------------------------------
-- 影视（首页视频卡「续播」进度 + 影视详情弹层共用一份模拟数据）
-- 首页 1s 刷新回调里调 MOCK.video_tick() 推进 pos，卡片进度条与弹层同步
--------------------------------------------------------------------
MOCK.video = {
    playing = true,
    pos = 45 * 60 + 20,                 -- 45:20
    dur = 2 * 3600 + 13 * 60,           -- 02:13:00
}
function MOCK.video_tick(sec)
    local v = MOCK.video
    if type(v.pos) ~= "number" then v.pos = 0 end
    if type(v.dur) ~= "number" or v.dur <= 0 then v.dur = 1 end
    if not v.playing then return end
    v.pos = v.pos + (sec or 1)
    if v.pos >= v.dur then v.pos = 0 end   -- 放完回到片头（模拟循环）
end
-- 拖动进度：pos 必须夹在 [0, dur] 内且是数字（曾把 slider 控件句柄存进
-- pos，下一次做算术就 "attempt to perform arithmetic on a airui.slider"）
function MOCK.video_seek(p)
    local v = MOCK.video
    p = tonumber(p) or 0
    if p < 0 then p = 0 elseif p > v.dur then p = v.dur end
    v.pos = math.floor(p)
end

--------------------------------------------------------------------
-- 音乐（首页迷你播放器 / 导航页小卡 / 音乐页共用）
--------------------------------------------------------------------
MOCK.music = {
    playing = true,
    cur = 2,
    pos = 0,
    list = {
        { title = "起风了", artist = "周深",   dur = 325, cv_bg = 0x0F5B45 },
        { title = "晴天",   artist = "周杰伦", dur = 269, cv_bg = 0x7C1220 },
        { title = "我记得", artist = "赵雷",   dur = 252, cv_bg = 0x123C8A },
        { title = "夜曲",   artist = "周杰伦", dur = 226, cv_bg = 0x6A2A78 },
        { title = "花海",   artist = "周杰伦", dur = 253, cv_bg = 0x8A5A1E },
    },
    -- 主题歌单：点卡片切歌单，「最近播放」的 3 张大卡换成该歌单的曲目
    -- （对照 preview.html：切歌单时下方列表整体刷新，并弹「已播放 · XX歌单」）
    mix = 1,
    mixes = {
        { albums = {
            { title = "起风了", artist = "周深",     dur = 325, c1 = 0x0F9D6B, c2 = 0x0A3F52 },
            { title = "晴天",   artist = "周杰伦",   dur = 269, c1 = 0x123C6E, c2 = 0x0A2E4E },
            { title = "我记得", artist = "赵雷",     dur = 252, c1 = 0x7A3BE8, c2 = 0x2A1160 } } },
        { albums = {
            { title = "夜空中最亮的星", artist = "逃跑计划", dur = 252, c1 = 0x8C1B2A, c2 = 0x2C070E },
            { title = "怒放的生命",     artist = "汪峰",     dur = 271, c1 = 0x123C6E, c2 = 0x0A2E4E },
            { title = "飞得更高",       artist = "汪峰",     dur = 288, c1 = 0x8A5A1E, c2 = 0x3A2008 } } },
        { albums = {
            { title = "稻香",       artist = "周杰伦", dur = 223, c1 = 0x1B4FA0, c2 = 0x0A2E4E },
            { title = "红豆",       artist = "王菲",   dur = 258, c1 = 0x8C1B2A, c2 = 0x2C070E },
            { title = "慢慢喜欢你", artist = "莫文蔚", dur = 241, c1 = 0x7A3BE8, c2 = 0x2A1160 } } },
        { albums = {
            { title = "小幸运",   artist = "田馥甄",     dur = 265, c1 = 0x8A5A1E, c2 = 0x3A2008 },
            { title = "春风十里", artist = "鹿先森乐队", dur = 232, c1 = 0x123C6E, c2 = 0x0A2E4E },
            { title = "夏夜晚风", artist = "伍佰",       dur = 246, c1 = 0x0F5B45, c2 = 0x0A3F52 } } },
        { albums = {
            { title = "月亮代表我的心", artist = "邓丽君", dur = 208, c1 = 0x0F5B45, c2 = 0x0A3F52 },
            { title = "甜蜜蜜",         artist = "邓丽君", dur = 195, c1 = 0x123C6E, c2 = 0x0A2E4E },
            { title = "同桌的你",       artist = "老狼",   dur = 245, c1 = 0x7A3BE8, c2 = 0x2A1160 } } },
    },
    fav = false,
    favs = {},   -- 收藏的歌曲标题集合（播放条 ♡ / 收藏弹层共用）
    -- 「更多歌单」里额外的 8 张歌单（对照 preview.html PL 里 PL_MAIN 之后的部分）
    extra = {
        { name = "深夜电台", songs = {
            { title = "夜曲",   artist = "周杰伦", dur = 226 },
            { title = "消愁",   artist = "毛不易", dur = 264 },
            { title = "像风一样", artist = "薛之谦", dur = 251 },
            { title = "失眠飞行", artist = "尹昔眠", dur = 218 } } },
        { name = "通勤路上", songs = {
            { title = "一路向北", artist = "周杰伦", dur = 289 },
            { title = "漂移",     artist = "周杰伦", dur = 242 },
            { title = "加速度",   artist = "张碧晨", dur = 231 },
            { title = "逆光",     artist = "孙燕姿", dur = 254 } } },
        { name = "国风新声", songs = {
            { title = "芒种",   artist = "音阙诗听", dur = 208 },
            { title = "赤伶",   artist = "何晶晶",   dur = 236 },
            { title = "琵琶行", artist = "奇然",     dur = 268 },
            { title = "踏山河", artist = "是七叔呢", dur = 197 } } },
        { name = "爵士午后", songs = {
            { title = "月半小夜曲", artist = "李克勤", dur = 275 },
            { title = "蓝调时刻",   artist = "方大同", dur = 246 },
            { title = "醇",         artist = "张碧晨", dur = 232 },
            { title = "慢板",       artist = "李泉",   dur = 288 } } },
        { name = "纯音乐", songs = {
            { title = "流水", artist = "轻音乐馆", dur = 214 },
            { title = "雨滴", artist = "轻音乐馆", dur = 196 },
            { title = "晨光", artist = "空灵乐队", dur = 235 },
            { title = "远山", artist = "秘境之声", dur = 248 } } },
        { name = "K歌必点", songs = {
            { title = "朋友",       artist = "周华健", dur = 268 },
            { title = "爱我别走",   artist = "张震岳", dur = 254 },
            { title = "突然好想你", artist = "五月天", dur = 292 },
            { title = "死了都要爱", artist = "信乐团", dur = 273 } } },
        { name = "经典粤语", songs = {
            { title = "富士山下", artist = "陈奕迅", dur = 272 },
            { title = "千千阙歌", artist = "陈慧娴", dur = 258 },
            { title = "一生所爱", artist = "卢冠廷", dur = 284 },
            { title = "红日",     artist = "李克勤", dur = 218 } } },
        { name = "轻音乐助眠", songs = {
            { title = "白噪音 · 雨", artist = "助眠实验室", dur = 600 },
            { title = "海浪",       artist = "助眠实验室", dur = 540 },
            { title = "森林清晨",   artist = "助眠实验室", dur = 480 },
            { title = "星空",       artist = "助眠实验室", dur = 520 } } },
    },
}
function MOCK.mu_song()
    local mu = MOCK.music
    local s = mu.list[mu.cur]
    if s then mu.fav = (mu.favs[s.title] == true) end
    return s
end

-- 歌词：按歌名取（首页迷你播放器的 3 行滚动）。
-- 原来歌词是 page_home 里写死的《七里香》，切歌后永远不变（用户反馈）
-- 每行不超过 9 个汉字：172 宽的列在 16 号字下再长就被裁掉
MOCK.mu_lyric_map = {
    ["起风了"] = { "我曾难自拔于世界", "也沉溺于其中梦话", "不得真假 不做挣扎",
                   "不惧笑话", "我曾将青春翻涌成她", "也曾指尖弹出盛夏",
                   "心之所动 随缘去吧" },
    ["晴天"] = { "故事的小黄花", "从出生那年就飘着", "童年的荡秋千",
                 "随记忆一直晃到现在", "吹着前奏望着天空", "我想起花瓣试着掉落",
                 "为你翘课的那一天" },
    ["我记得"] = { "带着比身体重的行李", "游入尼罗河底", "经过几道闪电",
                   "看到一堆光圈", "不确定是不是这里", "我看到几个人站在一起",
                   "他们拿着剪刀摘走" },
    ["夜曲"] = { "为你弹奏肖邦的夜曲", "纪念我死去的爱情", "跟夜风一样的声音",
                 "心碎的很好听", "失去你 爱恨开始分明", "失去你 还有什么事",
                 "当鸽子不再象征和平" },
    ["花海"] = { "静止了 所有的花开", "遥远了 清晰了的爱", "你说你 想要逃",
                 "才逃到天涯海角", "天空灰得像哭过", "离开你 以后",
                 "并没有更自由" },
}
-- 歌单里没收录歌词的曲目用这段兜底（至少 3 行，滚动逻辑才不会除零）
MOCK.mu_lyric_default = { "纯音乐 请欣赏", "旋律缓缓响起", "让心慢慢安静",
                          "这一刻 只属于你" }
function MOCK.mu_lyrics()
    local s = MOCK.mu_song()
    local t = s and MOCK.mu_lyric_map[s.title]
    return t or MOCK.mu_lyric_default
end
function MOCK.mu_dur()  return MOCK.mu_song().dur end
function MOCK.mu_fav_list()
    local out = {}
    for t in pairs(MOCK.music.favs) do out[#out + 1] = t end
    table.sort(out)
    return out
end
function MOCK.mu_pick_song(title)
    for i, s in ipairs(MOCK.music.list) do
        if s.title == title then MOCK.mu_pick(i) return end
    end
end

local function _mmss(sec)
    return string.format("%02d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end
MOCK.mmss = _mmss

-- 当前歌单的「最近播放」3 张大卡
function MOCK.mu_albums()
    local mx = MOCK.music.mixes[MOCK.music.mix or 1]
    return (mx and mx.albums) or {}
end
-- 全部歌单曲目（音乐页「最近播放」横向滑动列表用；同名去重，当前歌单排最前）
function MOCK.mu_all_albums()
    local out, seen = {}, {}
    local function push(a)
        if a and a.title and not seen[a.title] then
            seen[a.title] = true
            out[#out + 1] = a
        end
    end
    for _, a in ipairs(MOCK.mu_albums()) do push(a) end
    for _, mx in ipairs(MOCK.music.mixes) do
        for _, a in ipairs(mx.albums or {}) do push(a) end
    end
    return out
end
-- 切歌单：换列表 + 从头开始放（对照 html 点击卡片的「已播放 · XX歌单」）
function MOCK.mu_mix(i)
    MOCK.music.mix = i
    MOCK.music.pos = 0
    MOCK.music.playing = true
    -- 和原型 pickSong 一致：切歌单后播放的是这张歌单的第一首
    MOCK.mu_play_album((MOCK.mu_albums())[1])
end

-- 「更多歌单」：整张歌单替换播放列表，并从第一首开始放
function MOCK.mu_pick_pl(k)
    local mu = MOCK.music
    local pl = (mu.extra or {})[k]
    if not pl then return nil end
    local list = {}
    for i, s in ipairs(pl.songs) do
        list[i] = { title = s.title, artist = s.artist, dur = s.dur, cv_bg = 0x123C6E }
    end
    mu.list = list
    mu.cur = 1
    mu.pos = 0
    mu.playing = true
    return pl.name
end

-- 播放「最近播放」里的某一张卡。
-- 踩坑：原来点卡片走的是 MOCK.mu_pick(i)，i 是卡片序号（1..3），
-- 拿它去索引 music.list 取到的是完全无关的歌（点「夜空中最亮的星」放「起风了」）。
-- 这里按标题在播放列表里找，找不到就插进去，保证点谁放谁。
function MOCK.mu_play_album(a)
    if not a then return end
    local mu = MOCK.music
    local idx
    for i, s in ipairs(mu.list) do
        if s.title == a.title then idx = i break end
    end
    if not idx then
        mu.list[#mu.list + 1] = { title = a.title, artist = a.artist,
            dur = a.dur or 240, cv_bg = a.c1 or 0x123C6E }
        idx = #mu.list
    end
    mu.cur = idx
    mu.pos = 0
    mu.playing = true
end

-- 播放推进：由页面 1s 刷新回调调用，播放中则前进 1s
function MOCK.mu_tick()
    if MOCK.music.playing then
        MOCK.music.pos = MOCK.music.pos + 1
        -- 一曲放完自动切下一首（不要停留在末尾把时间继续累加）
        if MOCK.music.pos >= MOCK.mu_dur() then MOCK.mu_next() end
    end
end
function MOCK.mu_toggle() MOCK.music.playing = not MOCK.music.playing end
-- 拖动进度：pos 夹在 [0, dur] 内且必须是数字
-- （曾把 slider 控件句柄存进 pos，下一次做算术就 "attempt to perform arithmetic"）
function MOCK.mu_seek(p)
    local mu = MOCK.music
    p = tonumber(p) or 0
    local d = MOCK.mu_dur()
    if p < 0 then p = 0 elseif p > d then p = d end
    mu.pos = math.floor(p)
end
function MOCK.mu_prev()
    MOCK.music.cur = (MOCK.music.cur - 2) % #MOCK.music.list + 1
    MOCK.music.pos = 0
end
function MOCK.mu_next()
    MOCK.music.cur = MOCK.music.cur % #MOCK.music.list + 1
    MOCK.music.pos = 0
end
function MOCK.mu_pick(i)
    MOCK.music.cur = i
    MOCK.music.pos = 0
    MOCK.music.playing = true
end
function MOCK.mu_fav()
    local mu = MOCK.music
    local s = MOCK.mu_song()
    if not s then return end
    mu.favs[s.title] = not (mu.favs[s.title] == true)
    mu.fav = mu.favs[s.title] == true
end

--------------------------------------------------------------------
-- 音量（底栏音量键）
--------------------------------------------------------------------
MOCK.volume = { val = 18, muted = false }
function MOCK.volume_toggle()
    MOCK.volume.muted = not MOCK.volume.muted
end

--------------------------------------------------------------------
-- 导航（导航页）
--------------------------------------------------------------------
MOCK.nav = {
    dest = "淮海路", turn = "300m", turn_sub = "向左转",
    dist = "1.2公里 所需时间8分钟",
    bubble = "小迪去公司路况怎么样",
    recent = { "导航", "音乐", "车辆", "语音助手" },
}

--------------------------------------------------------------------
-- 车辆（车辆页 / 设置页 / 任务页缩略图）
--------------------------------------------------------------------
MOCK.car = {
    name = "唐 DM", sub = "四驱性能版 尊贵型",
    ev = 75, hev = 85, range = 456,
    mode = { l = 1, r = 1 },   -- 1=选中第一个胶囊（纯电/混动）
    lmodes = { "纯电模式", "节能模式", "运动模式" },
    rmodes = { "混动模式", "舒适模式", "驻车充电" },
    status = "良好", avg = "3.38度/每公里", total = "340公里",
    bat_small = { 36, 52, 44, 70, 58, 82, 62, 48, 74, 56, 40, 64 },  -- mini 柱状 %
    con = 3.3, fuel = 5.3,
    mile = { "3.5km", "1.0万km", "1.5万km" },
}
function MOCK.car_pick(side, idx) MOCK.car.mode[side] = idx end

--------------------------------------------------------------------
-- 设置（设置页）
--------------------------------------------------------------------
MOCK.set = {
    segs = { "驾驶模式", "经济模式", "运动模式", "防滑模式" },
    seg_idx = 1,
    speed = 65,
    gear = "N",
    tabs = { "车辆设置", "声音设置", "导航设置", "充电管理", "消息通知", "其他设置" },
    tab_idx = 2,
    -- 6 个分类各 6 行：{ 标题, 副标题, 开关默认值 }
    -- 数据与 preview.html 的 SET_DATA 完全一致
    data = {
        {
            { "驾驶模式记忆",   "记住上次选择的驾驶模式", true },
            { "自动驻车",       "停车后自动保持制动",     true },
            { "能量回收",       "标准回收强度",           true },
            { "转向手感",       "舒适 / 运动",            false },
            { "后视镜自动折叠", "锁车后自动收起",         true },
            { "车窗一键升降",   "长按钥匙控制",           true },
        },
        {
            { "汽车主驾驶音响", "主驾驶设置",                     true },
            { "副驾音响",       "副驾的声音立体声设置",           true },
            { "后排音响",       "后排声音设置，适用于娱乐氛围",   true },
            { "环绕立体声",     "在汽车里听电影院效果的声音",     true },
            { "高保真音响",     "适用于高级声音系统设置",         true },
            { "音乐厅效果",     "开启后仿佛在音乐厅一样的声音效果", true },
        },
        {
            { "语音播报",       "转弯与路况语音提醒",   true },
            { "实时路况避堵",   "自动避开拥堵路段",     true },
            { "高速优先",       "规划时优先选择高速",   false },
            { "电子眼提醒",     "测速与违章提醒",       true },
            { "停车场推荐",     "到达目的地附近推荐车位", false },
            { "离线地图更新",   "每月自动更新",         true },
        },
        {
            { "预约充电",       "低谷电价时段开始充电", true },
            { "充电上限",       "日常建议 80%",          false },
            { "对外放电",       "V2L 220V 输出",         false },
            { "充电完成提醒",   "手机与车机同时提醒",   true },
            { "电池预热",       "低温环境提升充电效率", true },
            { "低谷电价优先",   "自动选择低价时段",     true },
        },
        {
            { "车辆异常提醒",   "胎压 / 电池 / 门窗",   true },
            { "保养提醒",       "按里程与时间提醒",     true },
            { "系统更新通知",   "OTA 新版本推送",        false },
            { "违章提醒",       "同步交管数据",         true },
            { "营销推送",       "活动与优惠",           false },
            { "行程周报",       "每周驾驶报告",         true },
        },
        {
            { "语音唤醒词",     "“你好小迪”",            true },
            { "屏幕自动亮度",   "随环境光调节",         true },
            { "疲劳驾驶提醒",   "连续驾驶 2 小时提醒",   true },
            { "儿童锁",         "后排车窗与车门",       false },
            { "行车视频锁定",   "碰撞时自动锁定",       true },
            { "隐私模式",       "隐藏行程记录",         false },
        },
    },
}
-- 当前分类的 6 行（含运行期开关状态）
function MOCK.set_rows()
    local s = MOCK.set
    local d = s.data[s.tab_idx] or {}
    local out = {}
    for i, r in ipairs(d) do out[i] = { t = r[1], s = r[2], on = r[3] } end
    return out
end
-- 点「开启 / 关闭」：只改内存里的状态，页面重绘后依然保留
function MOCK.set_toggle(i, on)
    local s = MOCK.set
    local d = s.data[s.tab_idx]
    if d and d[i] then d[i][3] = on end
end

--------------------------------------------------------------------
-- 全部应用（应用宫格：名称 + 渐变起止色，均取自 preview.html）
--------------------------------------------------------------------
MOCK.apps = {
    { name = "智能语音",   c1 = 0x2E7DFF, c2 = 0x0B2A5E, go = "voice" },
    { name = "车辆全景影像", c1 = 0x22C4E0, c2 = 0x0A3D5E, go = "cluster" },
    { name = "智慧充电",   c1 = 0x35D6E8, c2 = 0x0B4F6B },
    { name = "行车记录仪", c1 = 0x34D399, c2 = 0x0B4A3A },
    { name = "最美天气",   c1 = 0x5AA7FF, c2 = 0x123C8A, go = "weather" },
    { name = "相机",       c1 = 0x2E7DFF, c2 = 0x123C8A },
    { name = "相册",       c1 = 0x4E8FE0, c2 = 0x123A6E },
    { name = "文件管理",   c1 = 0x58C8D8, c2 = 0x0B4A56 },
    { name = "游戏中心",   c1 = 0x35D6E8, c2 = 0x0B5C86 },
    { name = "极速模式",   c1 = 0x22C4E0, c2 = 0x0A3D5E, boost = true },
    { name = "百变主题",   c1 = 0x7C5CFF, c2 = 0x2A1C6E },
    { name = "后排屏中心", c1 = 0x5AA7FF, c2 = 0x1B4C8E },
    { name = "哨兵模式",   c1 = 0x3B8BFF, c2 = 0x123C8A },
    { name = "用户手册",   c1 = 0x34D399, c2 = 0x0F5B45 },
    { name = "下载",       c1 = 0x2E7DFF, c2 = 0x0B2A5E },
}

-- 极速模式（性能数据随开关变化，与 preview.html 行为一致）
MOCK.boost = { on = false,
    base = { acc = 4.3, vmax = 180, kw = 480 },
    boost = { acc = 3.9, vmax = 220, kw = 580 } }
function MOCK.boost_data()
    return MOCK.boost.on and MOCK.boost.boost or MOCK.boost.base
end

--------------------------------------------------------------------
-- 最近任务（任务页）
--------------------------------------------------------------------
MOCK.tasks = {
    { name = "车辆数据", go = "car" },
    { name = "应用APP",  go = "apps" },
    { name = "音乐",     go = "music" },
    { name = "车辆设置", go = "set" },
}

--------------------------------------------------------------------
-- 仪表盘（仪表页）
--------------------------------------------------------------------
MOCK.cluster = {
    time = "下午 8:08", weather = "晴 23°C",
    modes = { "ECO", "NORMAL", "SPORT" }, mode_idx = 1,
    dir = "东南", total = "总里程 2800 km",
    spd = 50, spd2 = 46, fuel = 62, bat = 95, gear = "D",
    NEOC = "NEOC 388km",
}
function MOCK.cluster_mode(d)
    MOCK.cluster.mode_idx = ((MOCK.cluster.mode_idx - 1 + d) % 3) % 3 + 1
    if MOCK.cluster.mode_idx < 1 then MOCK.cluster.mode_idx = 3 end
end
function MOCK.gear_pick(g) MOCK.cluster.gear = g end

--------------------------------------------------------------------
-- 手机投屏（手机页）
--------------------------------------------------------------------
MOCK.phone = { dest = "西湖", info = "1.2公里 所需时间6分钟" }

--------------------------------------------------------------------
-- 语音助手（语音页）
--------------------------------------------------------------------
MOCK.voice = {
    hello = "你好，我是小迪。可以让我放歌、导航、调空调，也能查天气。",
    state = "说出你的需求，或点下面的建议",
    chips = { "小迪我想听音乐", "小迪导航去公司", "把空调调到24度",
              "今天天气怎么样", "我想看部电影" },
    chat = {},
    answers = {
        ["小迪我想听音乐"] = "好的，正在为你播放《晴天》",
        ["小迪导航去公司"] = "已为你规划路线，全程 1.2 公里，约 8 分钟",
        ["把空调调到24度"] = "空调已设为 24 度，风向吹向面部",
        ["今天天气怎么样"] = "杭州今天小雨，27 度，注意带伞",
        ["我想看部电影"] = "已找到《流浪地球 2》，正在为你续播",
    },
}
function MOCK.voice_ask(q, a)
    MOCK.voice.chat[#MOCK.voice.chat + 1] = { q = q, a = a or (MOCK.voice.answers[q] or "收到，正在处理") }
end
function MOCK.voice_clear()
    MOCK.voice.chat = {}
end
