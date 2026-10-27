--[[
@module  ui_home
@summary 首页：大量留白 + 一张入口卡片（商务一点，但保留暖色）
@version 1.2
@date    2026.10.22

=== 设计取向 ===
上一版是一家三口 + 房子 + 狗 + 草坡的插画（100 多个图元），温馨但偏“儿童房”。
这一版按“商务/克制”重做：
  - 去掉所有卡通插画，改成留白 + 细边卡片；
  - 配色从奶油桃子改为米白 + 暖灰，强调色只用一处（顶部的 FAMILY ALBUM 小标）；
  - 右侧只放一句短文案 + 一根竖线，不用图片、不用图形；
  - 全页只有 ~12 个对象（1 个渐变背景 + 3 张卡片 + 若干 label），内存基本为 0。

布局（1024x600）：
  x 72..552   标识 / 标题 / 相册入口卡 / SD 状态 / 锁屏、改密码
  x 640..952  竖线 + 短文案
]]
local conf = require "conf"
local theme = require "theme"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local app_ref = nil
local sdDot = nil
local sdLabel = nil
local clockLabel = nil
local dateLabel = nil

local ACCENT = 0xB4885C      -- 暖驼色，只用在极少量地方
local CARD_BG = 0xFFFFFF
local CARD_LINE = 0xEADFD2
local SOFT_BTN = 0xF3EAE0

-- ==================== 构建 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0xFBF7F2, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, 0xFBF7F2, 0xF1E8DE, 8)

    -- 左：标识 + 标题
    theme.label(root, 72, 62, 420, 20, "FAMILY ALBUM", 14, ACCENT)
    theme.label(root, 70, 88, 470, 54, "家庭相册", 40, C.ink)
    theme.label(root, 72, 148, 470, 24, "把日子收进相册里", 17, C.ink3)

    -- 右上：时间
    clockLabel = theme.label(root, 700, 54, 252, 46, "", 34, C.ink, airui.TEXT_ALIGN_RIGHT)
    dateLabel = theme.label(root, 650, 102, 302, 22, "", 15, C.ink3, airui.TEXT_ALIGN_RIGHT)
    M.tick()

    -- 相册入口卡（整块可点）
    local card = theme.card(root, 72, 204, 480, 126, CARD_BG, 16, CARD_LINE, 1)
    card:set_on_click(function()
        theme.defer(function()
            if app_ref then app_ref.open_album() end
        end)
    end)
    theme.label(card, 28, 28, 260, 32, "打开相册", 26, C.ink)
    theme.label(card, 30, 68, 320, 22, "浏览 SD 卡中的照片", 16, C.ink3)
    theme.label(card, 412, 34, 40, 40, ">", 26, 0xC6B09A, airui.TEXT_ALIGN_CENTER)

    -- SD 状态一行
    sdDot = airui.container({
        parent = root, x = 74, y = 366, w = 10, h = 10,
        color = 0x8AA86B, radius = 5, border_width = 0,
    })
    sdLabel = theme.label(root, 96, 360, 360, 22, "正在读取 SD 卡...", 15, C.ink3)
    theme.button(root, 470, 352, 82, 34, "刷新", 14, SOFT_BTN, C.ink2, function()
        theme.defer(function()
            if app_ref then app_ref.refresh_sd() end
        end)
    end, 10)

    -- 底部两个操作
    theme.button(root, 72, 416, 200, 54, "锁定屏幕", 18, SOFT_BTN, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.lock_now() end
        end)
    end, 12)
    theme.button(root, 288, 416, 200, 54, "设置", 18, SOFT_BTN, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.open_settings() end
        end)
    end, 12)

    -- 右：竖线 + 短文案（不用任何图形资源）
    airui.container({
        parent = root, x = 640, y = 236, w = 3, h = 92,
        color = 0xE3D2BF, radius = 2, border_width = 0,
    })
    theme.label(root, 668, 236, 320, 32, "把日子过成照片", 22, C.ink2)
    theme.label(root, 668, 280, 320, 32, "慢慢翻，慢慢看", 22, C.ink2)
    theme.label(root, 668, 332, 320, 22, "Air8607   1024 x 600", 13, C.ink3)
end

--[[SD 状态显示]]
function M.set_sd(ok, folders, photos, err)
    if not sdLabel then return end
    if not ok then
        sdLabel:set_text("未检测到 SD 卡，插入后点刷新")
        sdLabel:set_color(C.red)
        if sdDot then sdDot:set_color(C.red) end
        log.warn("home", "SD 不可用", tostring(err))
        return
    end

    if photos == 0 and folders == 0 then
        sdLabel:set_text("SD 卡已就绪，里面还没有照片")
    else
        sdLabel:set_text(string.format("SD 卡就绪：%d 个文件夹 / %d 张照片", folders or 0, photos or 0))
    end
    sdLabel:set_color(C.ink3)
    if sdDot then sdDot:set_color(0x8AA86B) end
end

--[[刷新时间/日期]]
function M.tick()
    local t = os.date("*t")
    local week = { "日", "一", "二", "三", "四", "五", "六" }
    if clockLabel then
        clockLabel:set_text(string.format("%02d:%02d", t.hour, t.min))
    end
    if dateLabel then
        dateLabel:set_text(string.format("%04d年%02d月%02d日 星期%s",
            t.year, t.month, t.day, week[t.wday] or ""))
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    sdDot, sdLabel, clockLabel, dateLabel = nil, nil, nil, nil
end

return M
