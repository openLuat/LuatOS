--[[
@module  ui_theme
@summary 儿童房控制面板 · 五套动漫主题令牌（运行中切换 + fskv 记忆）
@version 2.0.0
@usage   改配色只动本文件的 P 表；切主题用 T.next() / T.apply(idx)。
        颜色 0xRRGGBB；透明度 0-255（越小越透明）。
        docs/儿童房面板效果稿.html 是唯一视觉规格：body[data-theme] 的 CSS 变量 ↔ 这里 T.c 的字段，
        改一边必须改另一边（变量名对照：--bg/--band1/--sh/--on/…）。

        五套主题共用同一套层叠关系，只换色板、角色、曲目与奖励贴纸：
          1 toy    玩具总动员：浅蓝底 + 橙红主色
          2 bear   熊出没    ：浅绿底 + 森绿主色
          3 hero   奥特曼    ：雾蓝底 + 正红主色
          4 pocket 宝可梦    ：奶油黄底 + 亮红主色
          5 sheep  喜羊羊    ：薄荷绿底 + 草绿主色

        已知约束（真机验证）：
          - container 没有渐变参数，背景只能靠「色带 + 大圆角柔光斑」叠层近似；
          - 描边不吃透明度，卡片一律 border_width = 0，靠投影层做层次；
          - 已建控件不会跟随令牌变色，切主题必须销毁当前页重建（见 page_shell.next_theme）。
]]
local M = {}

-- ==================== 字号 / 圆角 / 动效 ====================
-- 最小字号 16：hzfont 在 16 号以下中文会糊，且行高兜底会吃掉行距。
M.f = { h1 = 40, h2 = 26, h3 = 22, body = 20, sub = 16, mini = 16 }
M.r = { card = 24, tile = 24, chip = 20, mini = 16, pill = 22 }
M.motion = {
    enabled  = true,   -- 全局动效开关
    instant  = true,   -- 即时模式：点击一帧落终态，不排队补间（真机手感最好）
    press_dy = 2,      -- 按下时目标下压像素
    press_ms = 90,     -- 按下反馈回复时间
    shadow   = 4,      -- 假投影下移像素
    twinkle_ms = 500,  -- 装饰贴纸呼吸节拍（低频，不做逐帧）
}

-- ==================== 色板 + 主题数据 ====================
-- reward = 奖励贴纸用套图的第几格（与效果稿 .kr 的映射一致）
local P = {}

P[1] = {
    key = "toy", name = "玩具总动员", suffix = "的小房间", reward = 2,
    cast = { "胡迪", "巴斯", "翠丝", "火腿", "抱抱龙" },
    songs = {
        { "飞向宇宙",   "冒险" },
        { "太空巡逻",   "星际" },
        { "玩具进行曲", "轻音乐" },
        { "牛仔很忙",   "儿歌" },
        { "安迪的房间", "晚安曲" },
    },
    c = {
        bg = 0xEAF4FF, band1 = 0xA9D8F8, band2 = 0xFFE0AE,
        blob1 = 0xF0932B, blob2 = 0x5BA9E8, blob3 = 0xE2543C,
        card = 0xFFFFFF, card2 = 0xFFF8EC, shadow = 0x966436,
        ink = 0x2B2340, ink2 = 0x6E5B48, ink3 = 0xA08D79,
        pri = 0xE2543C, pri2 = 0xFFB454, on = 0xFFF0E1, off = 0xF3EADF, track = 0xEADCC9,
        pink = 0xFF8FA3, mint = 0x7EE0C9, yellow = 0xFFD66B, sky = 0x7EBEFF,
        white = 0xFFFFFF,
    },
}

P[2] = {
    key = "bear", name = "熊出没", suffix = "的小屋", reward = 2,
    cast = { "熊大", "熊二", "光头强", "吉吉", "蹦蹦" },
    songs = {
        { "森林早晨",   "轻音乐" },
        { "蜂蜜甜甜",   "儿歌" },
        { "小熊跳舞",   "儿歌" },
        { "树洞晚安",   "晚安曲" },
        { "光头强来啦", "故事" },
    },
    c = {
        bg = 0xF2F8E9, band1 = 0xC6E5A6, band2 = 0xF2E0AE,
        blob1 = 0x8B5A2B, blob2 = 0x4F8F3E, blob3 = 0xF2B33C,
        card = 0xFFFFFF, card2 = 0xF7FBEE, shadow = 0x567432,
        ink = 0x24321C, ink2 = 0x5F7047, ink3 = 0x93A47C,
        pri = 0x4F8F3E, pri2 = 0x9AC96B, on = 0xEDF7E2, off = 0xEFF2E6, track = 0xDCE9CE,
        pink = 0xFF8FA3, mint = 0x7EE0C9, yellow = 0xFFD66B, sky = 0x7EBEFF,
        white = 0xFFFFFF,
    },
}

P[3] = {
    key = "hero", name = "奥特曼", suffix = "的基地", reward = 5,
    cast = { "迪迦", "赛罗", "泽塔", "巴尔坦", "银河" },
    songs = {
        { "变身时刻", "热血" },
        { "光之巨人", "主题曲" },
        { "城市守护", "故事" },
        { "星之光芒", "轻音乐" },
        { "晚安光波", "晚安曲" },
    },
    c = {
        bg = 0xE9F0FA, band1 = 0xC6D8EC, band2 = 0xE8EEF8,
        blob1 = 0xD9382F, blob2 = 0x2E6BD8, blob3 = 0x8FB6E8,
        card = 0xFFFFFF, card2 = 0xF3F7FC, shadow = 0x28406E,
        ink = 0x17233A, ink2 = 0x52658A, ink3 = 0x8A9AB6,
        pri = 0xD9382F, pri2 = 0x7FA8DE, on = 0xEDF2FB, off = 0xEAF0F8, track = 0xD8E2F0,
        pink = 0xFF8FA3, mint = 0x7EE0C9, yellow = 0xFFD66B, sky = 0x7EBEFF,
        white = 0xFFFFFF,
    },
}

P[4] = {
    key = "pocket", name = "宝可梦", suffix = "的小屋", reward = 1,
    cast = { "皮卡丘", "杰尼龟", "妙蛙草", "小火龙", "胖丁" },
    songs = {
        { "出发吧训练家", "冒险" },
        { "精灵球之歌",   "儿歌" },
        { "皮卡皮卡",     "轻音乐" },
        { "道馆挑战",     "故事" },
        { "晚安宝可梦",   "晚安曲" },
    },
    c = {
        bg = 0xFFF8E0, band1 = 0xFFDD5C, band2 = 0xFFC8BE,
        blob1 = 0xE23B2E, blob2 = 0xFFC93C, blob3 = 0x5EA9E8,
        card = 0xFFFFFF, card2 = 0xFFFAE9, shadow = 0xB08420,
        ink = 0x33260F, ink2 = 0x7A6435, ink3 = 0xAC9360,
        pri = 0xE23B2E, pri2 = 0xFFC93C, on = 0xFFF3D8, off = 0xF5EEDA, track = 0xEFDFB8,
        pink = 0xFF8FA3, mint = 0x7EE0C9, yellow = 0xFFD66B, sky = 0x7EBEFF,
        white = 0xFFFFFF,
    },
}

P[5] = {
    key = "sheep", name = "喜羊羊", suffix = "的小屋", reward = 3,
    cast = { "喜羊羊", "懒羊羊", "美羊羊", "沸羊羊", "小灰灰" },
    songs = {
        { "羊村早晨",     "儿歌" },
        { "青草蛋糕",     "轻音乐" },
        { "灰太狼来了",   "故事" },
        { "喜羊羊美羊羊", "主题曲" },
        { "羊村晚安",     "晚安曲" },
    },
    c = {
        bg = 0xF0FAEE, band1 = 0xBEE8A6, band2 = 0xFFF2BC,
        blob1 = 0x46A146, blob2 = 0xFFD966, blob3 = 0x8FD0F0,
        card = 0xFFFFFF, card2 = 0xF4FBF0, shadow = 0x3E7444,
        ink = 0x1F3B22, ink2 = 0x547158, ink3 = 0x87A08B,
        pri = 0x46A146, pri2 = 0x97D48F, on = 0xE9F7E4, off = 0xEDF3E9, track = 0xD8EBD2,
        pink = 0xFF8FA3, mint = 0x7EE0C9, yellow = 0xFFD66B, sky = 0x7EBEFF,
        white = 0xFFFFFF,
    },
}

M.palettes = P
M.count = 5
M.idx = 1

-- 当前生效的令牌（原地覆盖，页面模块只读 M.c / M.cast / M.songs）
M.c = {}
M.key = P[1].key
M.name = P[1].name
M.suffix = P[1].suffix
M.cast = P[1].cast
M.songs = P[1].songs
M.reward = P[1].reward

-- 8 色圆点（与效果稿 COLORS 完全一致）
M.colors = {
    { name = "紫",     c = 0x7C6BF5 },
    { name = "蓝",     c = 0x7EBEFF },
    { name = "黄",     c = 0xFFE27A },
    { name = "粉",     c = 0xFF8FA3 },
    { name = "绿",     c = 0x7EE0C9 },
    { name = "橙",     c = 0xFFB35C },
    { name = "白",     c = 0xFFF6E0 },
    { name = "紫罗兰", c = 0x9B8CFF },
}

function M.apply(idx)
    idx = math.max(1, math.min(M.count, tonumber(idx) or 1))
    local p = P[idx]
    M.idx = idx
    M.key = p.key
    M.name = p.name
    M.suffix = p.suffix
    M.cast = p.cast
    M.songs = p.songs
    M.reward = p.reward
    for k, v in pairs(p.c) do M.c[k] = v end
    return p
end

-- ==================== fskv 记忆（可降级：fskv 不存在也要能跑） ====================
local KEY_THEME = "kid_theme"
local KEY_NAME  = "kid_name"
local KEY_CAST  = "kid_cast"      -- "0,1,2,0,3"，按主题顺序

M.kid_name = "小星星"
M.cast_idx = { 1, 1, 1, 1, 1 }    -- 每套主题各记一个角色下标（1..5）

local function kv_get(key)
    if not fskv then return nil end
    local ok, v = pcall(function()
        if fskv.init then fskv.init() end
        return fskv.get(key)
    end)
    if ok then return v end
    return nil
end

local function kv_set(key, val)
    if not fskv then return end
    pcall(function() fskv.set(key, tostring(val)) end)
end

function M.load()
    M.apply(tonumber(kv_get(KEY_THEME)) or 1)

    local n = kv_get(KEY_NAME)
    if type(n) == "string" and #n > 0 then M.kid_name = n end

    local cs = kv_get(KEY_CAST)
    if type(cs) == "string" then
        local i = 1
        for v in cs:gmatch("[^,]+") do
            local n2 = tonumber(v)
            if i <= 5 and n2 then M.cast_idx[i] = math.max(1, math.min(5, n2)) end
            i = i + 1
        end
    end

    log.info("ui_theme", "主题", M.idx, M.name, "名字", M.kid_name)
    return M.idx
end

function M.save_theme() kv_set(KEY_THEME, M.idx) end
function M.save_name() kv_set(KEY_NAME, M.kid_name) end
function M.save_cast()
    local t = {}
    for i = 1, 5 do t[i] = tostring(M.cast_idx[i] or 1) end
    kv_set(KEY_CAST, table.concat(t, ","))
end

--- 循环切到下一套主题，返回新下标
function M.next()
    M.apply(M.idx % M.count + 1)
    M.save_theme()
    return M.idx
end

M.load()
return M
