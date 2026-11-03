--[[
@module  ui_beans
@summary 豆种档案：6 款豆的产地/处理法/一爆温度/推荐曲线，点按即切换
@version 1.0
@date    2026.10.30
]]
local conf = require("conf")
local theme = require("theme")
local sim = require("sim")
local art = require("art")
local app = require("app")

local C, SZ = theme.C, theme.SZ

local M = {}

function M.build(p)
    local alive = true
    local U = {}

    app.subbar(p, "豆种档案", "点按卡片切换当前豆种，烤炉参数自动套用推荐值")

    local cur = sim.state().bean
    U.cards = {}

    for i, b in ipairs(conf.beans) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = 20 + col * 332
        local y = 72 + row * 250

        local card = theme.card(p, x, y, 320, 238, {
            color = C.panel,
            border_color = (i == cur) and C.copper or C.line,
            border_width = (i == cur) and 2 or 1,
            on_click = function()
                if not alive then return end
                sim.set_bean(i)
                app.toast("已切换 · " .. b.name .. "（推荐参数已套用）", C.copper2)
                app.go("dash")
            end,
        })
        theme.box(card, 0, 0, 320, 2, b.color, 0, 110)
        theme.shape(card, 16, 16, 64, 64, art.bean_items(32, 32, 64, b.color, b.kind))
        theme.label(card, 92, 14, 200, 26, b.name, SZ.l, C.ink)
        theme.label(card, 92, 40, 200, 16, b.en, SZ.xs, C.copper2)
        theme.label(card, 92, 58, 210, 16, b.origin, SZ.xs, C.ink2)
        theme.label(card, 92, 76, 210, 16, b.process .. " · " .. b.altitude, SZ.xs, C.ink3)
        theme.label(card, 16, 94, 288, 16, b.flavor, SZ.xs, C.crema)
        theme.hline(card, 16, 116, 288, C.line)

        local rows = {
            { "一爆", b.crack .. "°C", C.gold },
            { "推荐", string.format("%s · %d~%d°C", b.level_hint, b.drop_min, b.drop_max), C.ink2 },
            { "时长", b.minutes .. " 分钟", C.ink2 },
        }
        for k, r in ipairs(rows) do
            local ry = 124 + (k - 1) * 22
            theme.label(card, 16, ry, 46, 18, r[1], SZ.xs, C.ink3)
            theme.label(card, 64, ry, 240, 18, r[2], SZ.xs, r[3])
        end

        theme.hline(card, 16, 194, 288, C.line)
        theme.label(card, 16, 200, 288, 16,
            string.format("推荐 火力 %d%% · 风门 %d%% · 滚筒 %d rpm", b.heat, b.air, b.drum),
            SZ.xs, C.copper2)

        if i == cur then
            local chip = theme.chip(card, 244, 200, 70, 22, "使用中", C.green, C.panel3)
            U.cards[i] = chip
        else
            theme.label(card, 16, 216, 288, 16, "点按切换到此豆种  ›", SZ.xs, C.ink3, theme.RT)
        end
    end

    theme.label(p, 20, 576, 984, 16,
        "参数为演示推荐值 · 一爆温度决定主屏发展阶段的起点与爆裂事件触发点", SZ.xs, C.ink3)

    local page = {}
    page.refresh = function() end
    page.refresh_clock = function() end
    page.destroy = function() alive = false end
    return page
end

return M
