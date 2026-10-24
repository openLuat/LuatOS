--[[
@module  ui_lock
@summary 锁屏页：4 位数字密码 + 数字键盘，同时承担“修改密码”的三步流程
@version 1.0
@date    2026.10.22

页面只用一个全屏容器 + 十几个按钮和标签，没有任何图片/大缓冲，
是整套 UI 里最轻的一页。

mode:
  unlock  开机解锁
  old     改密码：输入原密码
  new     改密码：输入新密码
  confirm 改密码：再输一次新密码
]]
local conf = require "conf"
local theme = require "theme"
local lock = require "lock"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local NDIGIT = conf.lock.digits

local root = nil
local app_ref = nil
local hintLabel = nil
local timeLabel = nil
local dateLabel = nil
local backBtn = nil
local dots = {}

local mode = "unlock"
local entered = ""
local tmp_pwd = nil
local msgTimer = nil

-- ==================== 文案 ====================
local HINT = {
    unlock  = { "请输入 4 位密码", C.ink2 },
    old     = { "请输入原密码", C.ink2 },
    new     = { "设置 4 位新密码", C.ink2 },
    confirm = { "再输入一次新密码", C.ink2 },
}

local function refresh_hint()
    if not hintLabel then return end
    local h = HINT[mode] or HINT.unlock
    hintLabel:set_text(h[1])
    hintLabel:set_color(h[2])
end

local function refresh_dots()
    for i = 1, #dots do
        if i <= #entered then
            dots[i]:set_color(C.accent)
        else
            dots[i]:set_color(0xEAD5C0)
        end
    end
end

-- ==================== 输入逻辑 ====================
local function fail(msg)
    if not root then return end
    entered = ""
    refresh_dots()
    if hintLabel then
        hintLabel:set_text(msg)
        hintLabel:set_color(C.red)
    end
    if msgTimer then sys.timerStop(msgTimer) end
    msgTimer = sys.timerStart(function()
        msgTimer = nil
        refresh_hint()
    end, 1600)
end

local function submit()
    if not root then return end
    local input = entered
    if #input < NDIGIT then return end

    if mode == "unlock" then
        if lock.check(input) then
            theme.defer(function()
                if app_ref then app_ref.on_unlock() end
            end)
        else
            fail("密码错误，请重试")
        end
        return
    end

    if mode == "old" then
        if lock.check(input) then
            M.set_mode("new")
        else
            fail("原密码不正确")
        end
        return
    end

    if mode == "new" then
        tmp_pwd = input
        M.set_mode("confirm")
        return
    end

    -- confirm
    if input == tmp_pwd then
        lock.set(tmp_pwd)
        theme.defer(function()
            if app_ref then app_ref.on_pwd_changed() end
        end)
    else
        M.set_mode("new")
        fail("两次输入不一致，请重新设置")
    end
end

local function on_digit(d)
    if #entered >= NDIGIT then return end
    entered = entered .. d
    refresh_dots()
    if #entered == NDIGIT then
        -- 让最后一个圆点先画出来，再去校验
        sys.timerStart(submit, 120)
    end
end

local function on_del()
    if #entered == 0 then return end
    entered = entered:sub(1, #entered - 1)
    refresh_dots()
    refresh_hint()
end

local function on_clear()
    entered = ""
    refresh_dots()
    refresh_hint()
end

-- ==================== 页面 ====================
function M.set_mode(m)
    mode = m or "unlock"
    entered = ""
    refresh_dots()
    refresh_hint()
end

function M.tick()
    if not timeLabel then return end
    local t = os.date("*t")
    timeLabel:set_text(string.format("%02d:%02d", t.hour, t.min))
    local week = { "日", "一", "二", "三", "四", "五", "六" }
    dateLabel:set_text(string.format("%04d年%02d月%02d日 星期%s",
        t.year, t.month, t.day, week[t.wday] or ""))
end

function M.build(app, m)
    M.destroy()
    app_ref = app
    mode = m or "unlock"
    entered = ""

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 8)

    -- 左侧文案
    theme.label(root, 88, 70, 440, 54, "家庭相册", 40, C.ink)
    theme.label(root, 90, 128, 440, 26, "FAMILY ALBUM", 15, 0xB4885C)

    hintLabel = theme.label(root, 90, 196, 440, 30, "", 21, C.ink2)

    for i = 1, NDIGIT do
        dots[i] = airui.container({
            parent = root, x = 140 + (i - 1) * 56, y = 246, w = 26, h = 26,
            color = 0xEAD5C0, radius = 13, border_width = 0,
        })
    end

    timeLabel = theme.label(root, 88, 318, 440, 80, "", 56, C.ink)
    dateLabel = theme.label(root, 90, 404, 440, 26, "", 18, C.ink2)

    -- 按钮组件没有 set_hidden，改密码流程才创建
    if mode ~= "unlock" then
        backBtn = theme.button(root, 88, 470, 170, 56, "返回首页", 20, 0xEFD9C2, C.ink,
            function()
                theme.defer(function()
                    if app_ref then app_ref.cancel_pwd() end
                end)
            end, 18)
    end

    -- 右侧数字键盘
    local kx, ky, bw, bh, gap = 560, 92, 112, 92, 14
    local keys = {
        { "1" }, { "2" }, { "3" },
        { "4" }, { "5" }, { "6" },
        { "7" }, { "8" }, { "9" },
        { "清空", on_clear }, { "0" }, { "删除", on_del },
    }
    for i = 1, 12 do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = kx + col * (bw + gap)
        local y = ky + row * (bh + gap)
        local label = keys[i][1]
        local cb = keys[i][2]
        local is_digit = (#label == 1)
        theme.button(root, x, y, bw, bh, label, is_digit and 30 or 18,
            is_digit and C.card or 0xEFD9C2, is_digit and C.ink or C.ink2,
            function()
                if cb then
                    cb()
                else
                    on_digit(label)
                end
            end, 18)
    end

    M.set_mode(mode)
    M.tick()
end

function M.destroy()
    if msgTimer then
        sys.timerStop(msgTimer)
        msgTimer = nil
    end
    dots = {}
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    hintLabel, timeLabel, dateLabel, backBtn = nil, nil, nil, nil
    entered = ""
    tmp_pwd = nil
end

function M.mode()
    return mode
end

return M
