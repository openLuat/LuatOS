--[[
@module  page_story
@summary 页3 故事时间：主题曲目列表 / 封面角色 / 播放控制 / 进度 / 音量 / 单曲循环
@version 2.0.0
@note 坐标按 docs/儿童房面板效果稿.html 页3 逐项对齐（内容区 1024x432）：
      左卡 16/380，中卡 392/380，右卡 784/208。
      曲目名与标签来自 ui_theme（每套主题 5 首专属），时长/图标固定在 app_state。
      播放推进由 page_shell.tick 每 500ms 调 app_state.story_tick，只刷可见页。
      进度条用 airui.bar（container 改不了宽度），点条前进 10%。
]]
local T = require "ui_theme"
local C = T.c
local W = require "ui_widget"
local S = require "app_state"
local CAST = require "ui_cast"

local M = {}
local ui = { rows = {}, bar = nil, cur_time = nil, dur_time = nil,
    name = nil, play = nil, vol_lbl = nil, vol_bar = nil, loop = nil, cover = nil }

local function fmt(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function refresh()
    local songs = S.songs()
    for i, r in ipairs(ui.rows) do
        local on = (i == S.story.cur)
        W.glass(r.box, C.on, on and 255 or 0)
        -- 播放符只在选中行出现（效果稿 .playmark 默认 color:transparent）
        W.glass(r.mark, C.pri, on and 255 or 0)
    end

    local cur = songs[S.story.cur] or songs[1]
    if ui.name and cur then pcall(function() ui.name:set_text(cur.name) end) end

    local pct, pos, dur = S.story_pct()
    if ui.bar then ui.bar.set(pct) end
    if ui.cur_time then pcall(function() ui.cur_time:set_text(fmt(pos)) end) end
    if ui.dur_time then pcall(function() ui.dur_time:set_text(fmt(dur)) end) end

    if ui.play then
        -- set_symbol 之后必须补一次 set_color：symbol 切换会把颜色刷回默认色，
        -- 否则主色圆钮上的暂停符号与底色同色（真机看起来「按钮空了」）
        pcall(function()
            ui.play:set_symbol(S.story.playing and airui.SYMBOL_PAUSE or airui.SYMBOL_PLAY)
            ui.play:set_color(C.white)
        end)
    end
    if ui.vol_lbl then pcall(function() ui.vol_lbl:set_text(S.story.vol .. "%") end) end
    if ui.vol_bar then ui.vol_bar.set(S.story.vol) end
    if ui.loop then ui.loop.set_active(S.story.loop) end

    -- 封面里坐当前角色（切角色 / 切主题都走这里）
    W.set_image(ui.cover, CAST.img(true))
end

function M.create(root)
    local songs = S.songs()

    -- ===== 左：主题曲目清单 =====
    local c1 = W.card(root, { x = 16, y = 0, w = 380, h = 428 })
    W.text_mid(c1.inner, { text = "儿歌清单", x = 24, y = 16, w = 240, h = 28,
        size = T.f.h3, color = C.ink })
    W.deco(c1.inner, { name = CAST.sticker(2), x = 330, y = 14, w = 30, h = 30 })

    for i, tr in ipairs(songs) do
        local y = 58 + (i - 1) * 72
        local box = W.box(c1.inner, 16, y, 348, 64, C.on, 18)
        W.glass(box, C.on, 0)
        W.sticker(box, { name = tr.icon, x = 12, y = 14, w = 36, h = 36 })
        W.text_mid(box, { text = tr.name, x = 58, y = 8, w = 230, h = 26,
            size = T.f.body, color = C.ink })
        W.text_mid(box, { text = tr.sub, x = 58, y = 34, w = 230, h = 22,
            size = T.f.sub, color = C.ink2 })
        -- 右侧播放符：主色小圆 + 白色三角，未选中整块透明（等价 color:transparent）
        local mark = W.box(box, 303, 19, 26, 26, C.pri, 13)
        W.glass(mark, C.pri, 0)
        W.icon(mark, { symbol = airui.SYMBOL_PLAY, x = 0, y = 0, w = 26, h = 26,
            size = 16, color = C.white })
        W.press(c1.inner, { x = 16, y = y, w = 348, h = 64, radius = 18,
            target = box, tx = 16, ty = y, flash = C.pri, flash_opa = 30,
            on_click = function()
                S.story_select(i)
                refresh()
            end })
        ui.rows[i] = { box = box, mark = mark }
    end

    -- ===== 中：封面与播放控制 =====
    -- 左卡到 396 结束，中卡从 408 起（原 392 与左卡重叠 4px）
    local c2 = W.card(root, { x = 408, y = 0, w = 380, h = 428 })
    local cover = W.box(c2.inner, 70, 20, 240, 240, C.card2, 28)
    W.glass(cover, C.card2, 255)
    ui.cover = W.sticker(cover, { name = CAST.img(true), x = 35, y = 24, w = 170, h = 170 })
    W.deco(cover, { name = CAST.sticker(2), x = 200, y = 20, w = 26, h = 26, twinkle = true })
    W.deco(cover, { name = CAST.sticker(4), x = 16, y = 18, w = 24, h = 24, twinkle = true })
    W.deco(c2.inner, { name = CAST.sticker(5), x = 336, y = 282, w = 30, h = 30 })

    ui.name = W.text_mid(c2.inner, { text = "", x = 0, y = 268, w = 380, h = 32,
        size = T.f.h2, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
    ui.bar = W.bar(c2.inner, { x = 30, y = 312, w = 320, h = 16, value = 0, tag = "story" })
    ui.cur_time = W.text_mid(c2.inner, { text = "0:00", x = 30, y = 332, w = 90, h = 22,
        size = T.f.sub, color = C.ink2 })
    ui.dur_time = W.text_mid(c2.inner, { text = "0:00", x = 260, y = 332, w = 90, h = 22,
        size = T.f.sub, color = C.ink2, align = airui.TEXT_ALIGN_RIGHT })

    -- 点进度条 = 前进 10%（不引入拖拽控件，孩子也不会误拖）
    W.press(c2.inner, { x = 30, y = 306, w = 320, h = 28, radius = 14,
        flash = C.pri, flash_opa = 24,
        on_click = function()
            local pct = S.story_pct()
            S.story_seek(math.min(100, pct + 10))
            refresh()
        end })

    W.button(c2.inner, { x = 78, y = 360, w = 64, h = 64, radius = 32,
        symbol = airui.SYMBOL_PREV, size = 24, bg = C.on, fg = C.pri,
        on_click = function() S.story_step(-1); refresh() end })
    local play_box = W.box(c2.inner, 152, 354, 76, 76, C.pri, 38)
    W.glass(play_box, C.pri, 255)
    ui.play = W.icon(c2.inner, { symbol = airui.SYMBOL_PLAY, x = 152, y = 354, w = 76, h = 76,
        size = 30, color = C.white })
    W.press(c2.inner, { x = 152, y = 354, w = 76, h = 76, radius = 38,
        target = play_box, tx = 152, ty = 354, flash = C.white, flash_opa = 50,
        on_click = function() S.story_toggle(); refresh() end })
    W.button(c2.inner, { x = 242, y = 360, w = 64, h = 64, radius = 32,
        symbol = airui.SYMBOL_NEXT, size = 24, bg = C.on, fg = C.pri,
        on_click = function() S.story_step(1); refresh() end })

    -- ===== 右：音量与循环 =====
    -- 中卡到 788 结束，右卡 800..992（原 784..992 与中卡重叠 4px）
    local c3 = W.card(root, { x = 800, y = 0, w = 192, h = 428 })
    W.text_mid(c3.inner, { text = "音量", x = 16, y = 16, w = 160, h = 28,
        size = T.f.h3, color = C.ink })
    W.deco(c3.inner, { name = CAST.sticker(2), x = 150, y = 16, w = 26, h = 26, twinkle = true })
    ui.vol_lbl = W.text_mid(c3.inner, { text = "", x = 0, y = 96, w = 192, h = 40,
        size = T.f.h2, color = C.pri, align = airui.TEXT_ALIGN_CENTER })
    -- 192 宽：左右各 16，控件统一 16..176，避免右侧只剩 8px 贴边
    ui.vol_bar = W.bar(c3.inner, { x = 16, y = 156, w = 160, h = 16, value = 65, tag = "vol" })
    W.button(c3.inner, { x = 16, y = 196, w = 72, h = 52, radius = 18, text = "-",
        size = 26, bg = C.on, fg = C.pri,
        on_click = function() S.vol_delta(-1); refresh() end })
    W.button(c3.inner, { x = 104, y = 196, w = 72, h = 52, radius = 18, text = "+",
        size = 26, bg = C.on, fg = C.pri,
        on_click = function() S.vol_delta(1); refresh() end })
    ui.loop = W.chip(c3.inner, { x = 16, y = 268, w = 160, h = 40, text = "单曲循环",
        on_click = function()
            S.story.loop = not S.story.loop
            refresh()
        end })
    W.deco(c3.inner, { name = CAST.sticker(1), x = 54, y = 326, w = 84, h = 84 })

    refresh()
    return { refresh = refresh }
end

return M
