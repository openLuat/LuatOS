--[[
@module  hud
@summary 抬头与四角信息：顶部时间/日期/温度区间，左下城市，右下房间温湿度
@version 1.0
@date    2026.11.08

=== 布局（1024x600）===
  ┌────────────────────────────────────────────────────────────┐
  │ 08:24  03月02日 周一                     1 ~ 10C   (图标)  │  ← 顶部 0..104
  │                                                            │
  │                    （天空 / 角色 / 天气特效）               │
  │                                                            │
  │ (定位) 西安                            (房子)25C (水滴)55% │  ← 底部 520..570
  └────────────────────────────────────────────────────────────┘

=== 图标为什么用 shape 画 ===
内置点阵字库没有图标字形，用 airui.image 又要为每个图标准备 PNG。
定位针 / 房子 / 水滴 / 晴雨雪 用几个 circle+line+box 拼出来，
零素材、随主题色走，代价是只有天气变化时才重画一次（不是每帧）。

=== 字号 ===
hzfont 每出现一个新字号就建一份字体实例（带点阵缓存），
所以全工程只允许 conf.F 里这几个字号，不要在代码里算字号。
]]

local draw = require "draw"
local conf = require "conf"

local M = {}

local W, H = conf.W, conf.H
local F = conf.F

local C = {
    ink    = 0xF4F8FF,
    ink2   = 0xD6E2F5,
    ink3   = 0x9FB0CC,
    sun    = 0xFFD24A,
    moon   = 0xEBF1FF,
    cloud  = 0xF2F7FF,
    gray   = 0xB9C6D8,
    rain   = 0xBFDCF5,
}

local lb_time, lb_time_sh, lb_date, lb_lunar, lb_range, lb_city, lb_temp, lb_humi, lb_hint
local hud_shape, P
local last_icon_key = ""
-- 文本缓存：set_text 会触发重绘，值没变就别调（每秒都在刷的时钟尤其明显）
local last_time, last_date, last_lunar, last_range, last_city, last_temp, last_humi

--[[建标签
注意：airui.label 的构造配置里**没有 align 字段**（只有 x/y/w/h/color/font_size/font/text），
对齐必须建完再 set_align。第一步写成配置表里的 align 会被静默忽略，右侧的
温度/湿度就全变成左对齐，看着像"数字没靠右"。
]]
local function label(parent, x, y, w, h, text, size, color, align)
    local o = airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = size, color = color or C.ink,
    })
    o:set_align(align or airui.TEXT_ALIGN_LEFT)
    return o
end

-- ==================== 图标 ====================

local function pin_icon(P, cx, cy)
    P:ring(cx, cy, 11, C.ink, 3, 245)
    P:dot(cx, cy, 4, C.ink, 245)
    P:line(cx - 8, cy + 9, cx, cy + 20, C.ink, 3, 245, true)
    P:line(cx + 8, cy + 9, cx, cy + 20, C.ink, 3, 245, true)
end

local function house_icon(P, cx, cy)
    P:line(cx - 15, cy - 2, cx, cy - 15, C.ink2, 4, 245, true)
    P:line(cx, cy - 15, cx + 15, cy - 2, C.ink2, 4, 245, true)
    P:box(cx - 12, cy - 2, 24, 17, C.ink2, 245, 2)
    P:box(cx - 4, cy + 6, 8, 9, 0x1A2A3C, 200, 1)
end

local function drop_icon(P, cx, cy)
    P:dot(cx, cy + 4, 7, C.rain, 245)
    P:line(cx, cy - 8, cx - 5, cy, C.rain, 3, 245, true)
    P:line(cx, cy - 8, cx + 5, cy, C.rain, 3, 245, true)
end

local function sun_icon(P, cx, cy, r, color)
    P:dot(cx, cy, r, color, 255)
    for i = 0, 7 do
        local a = i * math.pi / 4
        local x1, y1 = cx + math.cos(a) * (r + 5), cy + math.sin(a) * (r + 5)
        local x2, y2 = cx + math.cos(a) * (r + 11), cy + math.sin(a) * (r + 11)
        P:line(x1, y1, x2, y2, color, 3, 235, true)
    end
end

local function moon_icon(P, cx, cy, r)
    P:dot(cx, cy, r, C.moon, 255)
    -- 挖出月牙：用一块比背景稍暗的圆盖住一侧（背景是天空色，这里取近似深蓝）
    P:dot(cx + r * 0.55, cy - r * 0.35, r * 0.86, 0x0B1730, 255)
end

local function cloud_icon(P, cx, cy, s, color, opa)
    P:ellipse(cx, cy + 6 * s, 26 * s, 12 * s, color, 0, 0, true, opa)
    P:ellipse(cx - 12 * s, cy, 13 * s, 11 * s, color, 0, 0, true, opa)
    P:ellipse(cx + 4 * s, cy - 5 * s, 15 * s, 13 * s, color, 0, 0, true, opa)
end

--[[通用天气图标：右上角徽标与七天预报页共用同一套画法
@param number s 缩放（1 = 徽标大小，约 52px 见方）]]
function M.icon(P, cx, cy, cond, night, s)
    s = s or 1
    cond = cond or "晴"

    if cond == "晴" then
        if night then
            moon_icon(P, cx, cy, 20 * s)
            P:dot(cx - 26 * s, cy - 18 * s, 2, 0xFFFFFF, 150)
            P:dot(cx + 24 * s, cy + 16 * s, 2, 0xFFFFFF, 120)
        else
            sun_icon(P, cx, cy, 19 * s, C.sun)
        end
    elseif cond == "多云" then
        if night then
            moon_icon(P, cx + 12 * s, cy - 10 * s, 12 * s)
        else
            sun_icon(P, cx + 10 * s, cy - 8 * s, 13 * s, C.sun)
        end
        cloud_icon(P, cx - 6 * s, cy + 6 * s, 1.05 * s, C.cloud, 245)
    elseif cond == "阴" then
        cloud_icon(P, cx, cy, 1.2 * s, C.gray, 245)
        cloud_icon(P, cx + 16 * s, cy + 10 * s, 0.85 * s, draw.shade(C.gray, -0.15), 220)
    elseif cond == "雨" then
        cloud_icon(P, cx, cy - 4 * s, 1.15 * s, C.gray, 245)
        for i = -1, 1 do
            P:line(cx + i * 13 * s, cy + 16 * s, cx + i * 13 * s - 4 * s, cy + 30 * s, C.rain, 3, 235, true)
        end
    else -- 雪
        cloud_icon(P, cx, cy - 4 * s, 1.15 * s, C.cloud, 245)
        P:dot(cx - 13 * s, cy + 22 * s, 3, C.cloud, 240)
        P:dot(cx, cy + 26 * s, 3, C.cloud, 240)
        P:dot(cx + 13 * s, cy + 22 * s, 3, C.cloud, 240)
    end
end

--- 右上角的天气徽标
local function condition_icon(P, e, wx)
    M.icon(P, 954, 56, (wx and wx.condition) or e.condition, e.night, 1)
end

--[[顶部渐晕：从屏幕顶端往下压一层暗色，越往下越淡
作用有两个 —— 一是时间/日期/温度压在浅蓝天空上时也有足够对比度；
二是把顶部几条信息收成一个视觉条带，不再"散在天上"。
画在 hud_shape 里，所以它在云层之上（云就算飘上来也压不住文字）。

档数必须够多：一开始只给 8 档（每档 17px），结果每条之间有肉眼可见的
alpha 台阶，整片天空变成百叶窗。24 档 / 每档 5.8px、每档 alpha 只差 2 才看不出来。
]]
local function top_shade(P)
    local bands, total = 24, 140
    for i = 0, bands - 1 do
        local y0 = math.floor(i * total / bands)
        local y1 = math.floor((i + 1) * total / bands)
        local k = 1 - i / bands
        local a = math.floor(44 * k * k)
        if a > 0 then
            P:box(0, y0, W, y1 - y0, 0x061020, a)
        end
    end
end

local function draw_icons(e, wx)
    local key = table.concat({
        e.condition or "", e.night and "1" or "0", e.is_rain and "1" or "0",
        tostring(wx and wx.temp or ""),
    }, "|")
    if key == last_icon_key then return end
    last_icon_key = key

    P:reset()
    top_shade(P)
    pin_icon(P, 36, 534)
    house_icon(P, 760, 528)
    drop_icon(P, 890, 542)
    condition_icon(P, e, wx)
    P:finish()
    hud_shape:set_items(P.items)
end

-- ==================== 对外接口 ====================

function M.build(parent)
    P = draw.pool()

    hud_shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H })

    --[[顶部：大时钟 + 日期 + 温度区间
    时钟先铺一层深色影子（右下偏 2px）再压白字：单色细体直接浮在浅蓝天上，
    笔画边缘会被背景吃掉，看着"发虚"。投影只在时钟上做，多了反而脏。]]
    lb_time_sh = label(parent, 28, 8, 210, 108, "08:24", F.clock, 0x0A1730, airui.TEXT_ALIGN_LEFT)
    lb_time = label(parent, 26, 6, 210, 108, "08:24", F.clock, C.ink, airui.TEXT_ALIGN_LEFT)

    -- 日期一行（带年份）+ 农历一行，与左侧大时钟垂直居中
    lb_date = label(parent, 254, 14, 400, 42, "2026/11/08 周日", F.mid, C.ink2, airui.TEXT_ALIGN_LEFT)
    lb_lunar = label(parent, 254, 56, 400, 34, "农历九月三十  丙午年", F.small, C.ink3, airui.TEXT_ALIGN_LEFT)

    -- 宽度给到 250：低温阴天会出现 "-10 ~ 3℃" 这种长串，窄了会被右对齐裁掉尾巴
    lb_range = label(parent, 650, 26, 250, 42, "1 ~ 10℃", F.mid, C.ink2, airui.TEXT_ALIGN_RIGHT)

    -- 左下：定位城市
    lb_city = label(parent, 60, 516, 250, 52, "西安", F.mid, C.ink, airui.TEXT_ALIGN_LEFT)

    -- 右下：房间温度 + 湿度（温度右端 874、湿度右端 1000，中间塞水滴图标，互不压）
    lb_temp = label(parent, 784, 516, 90, 52, "--℃", F.mid, C.ink, airui.TEXT_ALIGN_RIGHT)
    lb_humi = label(parent, 906, 516, 94, 52, "--%", F.mid, C.ink2, airui.TEXT_ALIGN_RIGHT)

    -- 底部操作提示（10 秒后由 ui_main 收起）
    lb_hint = label(parent, 260, 566, 504, 26,
        "点击中间的小人切换形象  |  左滑查看七天天气", F.tiny, 0x7E8CA6, airui.TEXT_ALIGN_CENTER)
end

--- 刷新文字（每帧调用；内部只在值变化时 set_text）
function M.refresh(now, wx, room)
    if lb_time and last_time ~= now.hhmm then
        last_time = now.hhmm
        lb_time:set_text(now.hhmm)
        if lb_time_sh then lb_time_sh:set_text(now.hhmm) end
    end

    local dstr = now.date_str .. " " .. now.wd_str
    if lb_date and last_date ~= dstr then
        last_date = dstr
        lb_date:set_text(dstr)
    end

    -- 农历 + 干支年（time_util 已按天缓存，这里只在值变化时刷）
    if lb_lunar then
        local lstr = (now.lunar and now.lunar ~= "") and (now.lunar .. "  " .. (now.lunar_gz or "")) or ""
        if last_lunar ~= lstr then
            last_lunar = lstr
            lb_lunar:set_text(lstr)
        end
    end

    if wx then
        local lo = wx.temp_min or wx.temp
        local hi = wx.temp_max or wx.temp
        -- ℃ 是 GB2312 A1 区的符号，hzfont 带得出来；万一固件是精简字库(缺该字形)，
        -- 把下面两处 "℃" 换成 "C" 即可
        local rstr = (lo and hi) and string.format("%d ~ %d℃", lo, hi) or "--"
        if last_range ~= rstr then
            last_range = rstr
            lb_range:set_text(rstr)
        end
        if wx.city and wx.city ~= last_city and wx.city ~= "" then
            last_city = wx.city
            lb_city:set_text(wx.city)
        end
    end

    if room then
        if lb_temp and last_temp ~= room.temp then
            last_temp = room.temp
            lb_temp:set_text(room.temp .. "℃")
        end
        if lb_humi and last_humi ~= room.humi then
            last_humi = room.humi
            lb_humi:set_text(room.humi .. "%")
        end
    end
end

--- 重画图标（天气 / 昼夜变化时才真的重画）
function M.draw_icons(e, wx)
    if not hud_shape then return end
    draw_icons(e, wx)
end

--- 隐藏底部提示
function M.hide_hint()
    if lb_hint then
        lb_hint:set_text("")
    end
end

return M
