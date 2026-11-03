--[[
@module  ui_home
@summary 游戏大厅 - 七张游戏卡片 + 一张排行榜入口 + 每张卡上的实时预览
@version 1.2
@date    2026.11.03
@usage
1、ui_home.init(list)      由 ui_shell 注入卡片列表（七款游戏 + 排行榜页，顺序即卡片位序）
2、ui_home.on_select(fn)   指定"点了第几张卡"的回调
3、ui_home.build(root)     搭大厅页面，返回页面对象（update / onTap / onEnter / stats）
@note
卡片网格 4 列 x 2 行，241x218，间距 10，正好铺满 994x446 的舞台内容区。
面向孩子的卡片不用深色玻璃感，而是"白纸贴纸"：
投影 + 纯白底 + 主题色描边 + 主题色浅底的预览窗，
八张卡颜色各不相同，孩子不认字也能靠颜色记住哪个是哪个。
卡片从第一版的 324 宽压到 241 宽，卡内版式跟着重排：
标题 / 英文 / 两行描述 / 预览窗(62 高) / 一行最佳成绩。
预览不是静态图：调用对应模块的 preview() 每帧现算，大厅一进去就是八张小卡片在动。
]]

local fx = require "fx"
local T = require "theme"
local records = require "records"

local M = {}

-- 页面元信息（ui_shell 直接读这几个字段）
M.name = "游戏大厅"
M.en   = "PUZZLE LOBBY"
M.desc = "七个小游戏 + 排行榜 / 想玩哪个点哪个"
M.tip  = "点一下卡片就开始玩，想换游戏按底下的大厅按钮"
M.accent = T.c.blue
M.is_home = true
M.record_key = nil
M.rules = "这里有七个小游戏，点卡片就能玩。\n\n不会玩没关系，每局里按底下的玩法按钮就有说明。\n玩出的成绩会记进排行榜，点最后一张卡片就能看到。"

local cards = {}
local on_select = nil

--[[注入卡片列表（顺序 = 卡片位序，第 8 张是排行榜入口）]]
function M.init(list)
    cards = list or {}
end

function M.on_select(fn)
    on_select = fn
end

function M.build(root, W, H)
    local o = {}

    local c = T.card
    local ox = math.floor((W - (c.cols * c.w + (c.cols - 1) * c.gap)) / 2)
    local oy = math.floor((H - (c.rows * c.h + (c.rows - 1) * c.gap)) / 2)

    local rects = {}
    local lbs_best = {}

    -- 241x218 的卡片比第一版窄 83px，卡内版式重排（自上而下）：
    --   13 主题色条 / 24 标题 / 54 英文 / 70 两行描述 / 110 预览窗 / 180 最佳成绩
    for i = 1, #cards do
        local col = (i - 1) % c.cols
        local row = math.floor((i - 1) / c.cols)
        local r = {
            x = ox + col * (c.w + c.gap),
            y = oy + row * (c.h + c.gap),
            w = c.w, h = c.h,
        }
        rects[i] = r

        local g = cards[i]
        airui.label({
            parent = root, x = r.x + 16, y = r.y + 24, w = r.w - 32, h = 30,
            text = g.name, font_size = T.f.body, color = T.c.txt,
            align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = root, x = r.x + 16, y = r.y + 54, w = r.w - 32, h = 14,
            text = g.en or "", font_size = T.f.mini, color = T.c.dim2,
            align = airui.TEXT_ALIGN_LEFT,
        })
        -- 描述给 34 高：窄卡上一句话放不下会折成两行，切掉半行比不显示更难看
        airui.label({
            parent = root, x = r.x + 16, y = r.y + 70, w = r.w - 32, h = 34,
            text = g.desc or "", font_size = T.f.sub, color = T.c.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
        lbs_best[i] = airui.label({
            parent = root, x = r.x + 16, y = r.y + 180, w = r.w - 32, h = 18,
            text = "", font_size = T.f.sub,
            color = fx.shade(g.accent or T.c.blue, -0.3),
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 各游戏"最佳成绩"的语义不同（最高分 / 最少步数 / 最短用时），
    -- 由游戏模块自己的 format_record(v) 决定文案，大厅只负责显示。
    -- 排行榜卡没有 record_key，用它自己的 card_note 说一句话。
    local function refresh_best()
        for i = 1, #cards do
            local g = cards[i]
            if not g.record_key then
                lbs_best[i]:set_text(g.card_note or "")
            elseif g.format_record then
                lbs_best[i]:set_text(g.format_record(records.best(g.record_key)))
            else
                lbs_best[i]:set_text(string.format("最佳 %d", records.best(g.record_key)))
            end
        end
    end
    refresh_best()

    o.onEnter = function() refresh_best() end

    --[[大厅帧绘制：投影 + 白卡 + 主题色描边 + 主题色浅底预览窗 + 八个实时预览]]
    o.update = function(self, P, t, dt)
        for i = 1, #cards do
            local r = rects[i]
            local g = cards[i]
            local acc = g.accent or T.c.blue

            P:shadow(r.x, r.y, r.w, r.h, 16, 44)
            P:box(r.x, r.y, r.w, r.h, T.c.panel, 255, 18)
            -- 描边用 75% 的主题色：白底上要够浓，孩子才看得出"这是哪一张卡"
            P:frame(r.x, r.y, r.w, r.h, fx.mix(acc, T.c.panel, 0.25), 2, 255, 18)

            -- 左上角主题色条：轻微呼吸，让大厅看起来是"活的"
            local k = 0.55 + 0.45 * fx.breathe(t, i * 0.5)
            P:box(r.x + 16, r.y + 13, 44, 8, acc, math.floor(170 + 85 * k), 4)

            -- 预览窗：整块淡淡的主题色，八张卡一眼能分开
            local px, py = r.x + 16, r.y + 110
            local pw, ph = r.w - 32, 62
            P:box(px, py, pw, ph, fx.mix(acc, T.c.panel, 0.84), 255, 14)
            P:frame(px, py, pw, ph, fx.mix(acc, T.c.panel, 0.6), 2, 255, 14)

            if g.preview then
                g.preview(P, px + 6, py + 6, pw - 12, ph - 12, t)
            end
        end
    end

    --[[点击：命中哪张卡就进哪一页（前七张是游戏，第八张是排行榜）]]
    o.onTap = function(self, x, y)
        for i = 1, #cards do
            local r = rects[i]
            if T.hit(x, y, r.x, r.y, r.w, r.h) then
                if on_select then on_select(i) end
                return
            end
        end
    end

    o.stats = function(self)
        return string.format("%d 张卡片 / 七款游戏 + 排行榜", #cards),
            "成绩会自动记住，点排行榜就能看"
    end

    o.restart = function(self) refresh_best() end

    return o
end

return M
