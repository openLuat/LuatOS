--[[
@module  app_state
@summary 儿童房面板的模拟数据层（无外设：全部状态本地维护 + 定时推进）
@version 2.0.0
@note 本工程按需求「外设和接口暂不需要」实现，所有读数都是本地模拟值；
      接真设备时只改本文件，页面不感知数据来源。
      约定：页面改状态 → 调本文件的 set_xxx → 各页自己刷新（不跨页广播）。
      初值与 docs/儿童房面板效果稿.html 的 S（JS 状态表）逐项对齐。
]]
local T = require "ui_theme"

local M = {}

-- ==================== 环境与设备 ====================
M.env = {
    temp_in = 23,     -- 室内温度 ℃
    hum = 56,         -- 空气湿度 %
    temp_out = 18,    -- 室外温度 ℃
}

-- 效果稿初值：四台设备全开，投影 30 分钟，夜灯色号 0（紫）
M.dev = {
    lamp    = { on = true, bri = 60, color = 1 },   -- 小夜灯：亮/亮度/色号(1..8)
    proj    = { on = true },                        -- 星空投影
    curtain = { on = true },                        -- 窗帘：开/合
    humid   = { on = true },                        -- 加湿器
    ac      = { on = true, temp = 26 },             -- 空调
}

M.modes = { "常亮", "呼吸", "渐变" }
M.mode = 1                     -- 小夜灯模式下标（1..3）
M.proj_timer = 30              -- 投影定时（分钟）
M.PROJ_TIMERS = { 15, 30, 60 }
M.AC_MIN, M.AC_MAX = 18, 30
M.BRI_STEP = 5

function M.ac_delta(d)
    local v = M.dev.ac.temp + d
    if v < M.AC_MIN then v = M.AC_MIN end       -- 效果稿：到边界即停，不循环
    if v > M.AC_MAX then v = M.AC_MAX end
    M.dev.ac.temp = v
    return v
end

function M.bri_delta(d)
    local v = M.dev.lamp.bri + d * M.BRI_STEP
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    M.dev.lamp.bri = v
    return v
end

function M.toggle(name)
    local d = M.dev[name]
    if not d then return false end
    d.on = not d.on
    return d.on
end

--- 投影状态文案：开=「30 分」，关=「已关闭」
function M.proj_text()
    return M.dev.proj.on and (M.proj_timer .. " 分") or "已关闭"
end

-- ==================== 场景 ====================
-- 一键联动多张设备卡，取值与效果稿 SCENES 一一对应（色号已换算成 1..8）
M.scenes = {
    { name = "起床啦",   icon = "ic_sun" },
    { name = "学习时间", icon = "ic_book" },
    { name = "玩耍时间", icon = "ic_rocket" },
    { name = "睡觉觉",   icon = "ic_moon" },
}

function M.scene(name)
    if name == "起床啦" then
        M.dev.curtain.on = true
        M.dev.lamp.on = true
        M.dev.lamp.bri = 80
        M.dev.lamp.color = 3          -- 黄
        M.dev.proj.on = false
        M.dev.ac.on = true
    elseif name == "学习时间" then
        M.dev.curtain.on = true
        M.dev.lamp.on = true
        M.dev.lamp.bri = 100
        M.dev.lamp.color = 8          -- 紫罗兰
        M.dev.proj.on = false
    elseif name == "玩耍时间" then
        M.dev.lamp.on = true
        M.dev.lamp.bri = 70
        M.dev.lamp.color = 2          -- 蓝
        M.dev.proj.on = true
    elseif name == "睡觉觉" then
        M.dev.curtain.on = false
        M.dev.lamp.on = true
        M.dev.lamp.bri = 25
        M.dev.lamp.color = 1          -- 紫
        M.dev.proj.on = true
        M.proj_timer = 15
    else
        return false
    end
    return true
end

-- ==================== 故事机 ====================
-- 曲目名与标签随主题变（T.songs），时长与图标固定在设备侧（与效果稿 DUR 一致）
M.dur = { 130, 165, 118, 182, 150 }
M.song_icons = { "ic_star", "ic_moon", "ic_cloud", "ic_rocket", "ic_flower" }

--- 当前主题的曲目列表：{ name, sub, dur, icon }
function M.songs()
    local out = {}
    for i = 1, 5 do
        local s = T.songs[i] or { "未命名", "" }
        local d = M.dur[i]
        out[i] = {
            name = s[1],
            sub = string.format("%d:%02d · %s", math.floor(d / 60), d % 60, s[2] or ""),
            dur = d,
            icon = M.song_icons[i],
        }
    end
    return out
end

-- 效果稿初值：选中第 5 首并处于播放态，进度 1%
M.story = { cur = 5, playing = true, pos = 1.5, vol = 65, loop = true }

function M.story_toggle()
    M.story.playing = not M.story.playing
    return M.story.playing
end

function M.story_select(i)
    if not M.dur[i] then return end
    M.story.cur = i
    M.story.pos = 0
    M.story.playing = true
end

--- 切歌（dir = -1 上一首 / 1 下一首），循环到头回绕
function M.story_step(dir)
    local n = #M.dur
    local i = M.story.cur + dir
    if i < 1 then i = n end
    if i > n then i = 1 end
    M.story_select(i)
    return i
end

function M.story_seek(pct)
    local dur = M.dur[M.story.cur]
    M.story.pos = math.floor(dur * pct / 100)
end

function M.vol_delta(d)
    local v = M.story.vol + d * 5
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    M.story.vol = v
    return v
end

function M.story_pct()
    local dur = M.dur[M.story.cur]
    local p = math.floor(M.story.pos * 100 / dur)
    if p > 100 then p = 100 end
    if p < 0 then p = 0 end
    return p, math.floor(M.story.pos), dur
end

--- 播放推进（由主循环每 500ms 调一次），返回是否发生了变化
function M.story_tick(dt_ms)
    if not M.story.playing then return false end
    local dur = M.dur[M.story.cur]
    M.story.pos = M.story.pos + dt_ms / 1000
    if M.story.pos >= dur then
        if M.story.loop then
            M.story.pos = 0
        else
            M.story_step(1)
        end
    end
    return true
end

-- ==================== 任务与奖励 ====================
M.tasks = {
    { name = "自己刷牙 2 分钟",  sub = "已得 1 颗星星",       done = true },
    { name = "把玩具收进箱子",   sub = "已得 1 颗星星",       done = true },
    { name = "读一本绘本",       sub = "点一下就能得到星星",   done = false },
    { name = "9 点前上床睡觉",   sub = "点一下就能得到星星",   done = false },
}

M.stars_base = 10
M.week = { 3, 2, 5, 4, 1, 6, 2 }        -- 周一到周日
M.week_day_names = { "一", "二", "三", "四", "五", "六", "日" }
M.alarm = { sleep = { h = 21, m = 0 }, wake = { h = 7, m = 0 } }   -- 效果稿：21:00 / 07:00

function M.task_toggle(i)
    local t = M.tasks[i]
    if not t then return nil end
    t.done = not t.done
    t.sub = t.done and "已得 1 颗星星" or "点一下就能得到星星"
    return t.done
end

function M.stars()
    local n = M.stars_base
    for _, t in ipairs(M.tasks) do
        if t.done then n = n + 1 end
    end
    return n
end

--- 本周还差多少颗（效果稿目标 20 颗）
function M.stars_need()
    local n = 20 - M.stars()
    if n < 0 then n = 0 end
    return n
end

--- 今天是周几（1..7，周一=1）。按真实日期高亮，不写死「六」。
function M.week_today()
    local w = tonumber(os.date("%w")) or 6      -- 0 = 周日
    if w == 0 then return 7 end
    return w
end

local function hhmm(a)
    return string.format("%02d:%02d", a.h, a.m)
end

function M.alarm_delta(kind, d)
    local a = M.alarm[kind]
    if not a then return nil end
    local total = a.h * 60 + a.m + d * 15
    total = (total + 24 * 60) % (24 * 60)
    a.h = math.floor(total / 60)
    a.m = total % 60
    return hhmm(a)
end

function M.alarm_text(kind)
    return hhmm(M.alarm[kind])
end

-- ==================== 时钟 ====================
--- 问候语只给前缀，名字由 ui_theme.kid_name 拼（效果稿是「早安，」+ 可编辑名字）
function M.clock()
    local t = os.date("*t")
    local h, mi = t.hour, t.min
    local greet
    if h >= 5 and h < 11 then
        greet = "早安，"
    elseif h >= 11 and h < 14 then
        greet = "午安，"
    elseif h >= 14 and h < 18 then
        -- 顶栏问候位只有 3 个字的宽度，4 个字的「下午好，」会把名字挤掉
        greet = "下午好"
    else
        greet = "晚安，"
    end
    local hint
    if h >= 21 or h < 6 then
        hint = "该睡觉啦"
    elseif h >= 6 and h < 9 then
        hint = "该起床啦"
    else
        hint = "今天要开心哦"
    end
    return {
        hhmm = string.format("%02d:%02d", h, mi),
        date = string.format("%d月%d日 星期%s", t.month, t.day, M.week_day_names[M.week_today()]),
        greet = greet,
        hint = hint,
        hour = h,
    }
end

--- 孩子名字（顶栏第二段，可点开键盘改）
function M.kid_name()
    return T.kid_name or "小星星"
end

--- UTF-8 字符数：中文一个字 3 字节，绝不能用 #s 当字数
local function ulen(s)
    local n = 0
    for _ in s:gmatch("[^\128-\191]") do n = n + 1 end
    return n
end

--- 按「字符」截断，避免把一个汉字切成半个（截断后仍是合法 UTF-8）
local function ucut(s, maxcp)
    if ulen(s) <= maxcp then return s end
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then          -- 字符首字节
            n = n + 1
            if n > maxcp then return s:sub(1, i - 1) end
        end
    end
    return s
end

--- 名字：去空白、最多 6 个字符（不是 6 字节）、空则回落默认名
function M.set_kid_name(name)
    name = tostring(name or "")
    name = name:gsub("%s+", "")
    name = ucut(name, 6)
    if #name == 0 then name = "小星星" end
    T.kid_name = name
    T.save_name()
    return name
end

return M
