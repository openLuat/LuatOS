--[[
@module  ui_rank
@summary 排行榜页 - 每款游戏的前 5 名（成绩 + 日期），左侧标签切换
@version 1.0
@date    2026.11.03
@usage
1、ui_rank.init(games)   由 ui_shell 注入七款游戏模块（顺序 = 标签顺序 = 大厅卡片顺序）
2、ui_rank.build(root)   由 ui_shell 当作普通页面构建，返回页面对象
   o.update / o.onTap / o.onEnter / o.restart / o.stats
@note
这一页是"只读展示"，没有逐帧动画需求，所以：
  - 只在 onEnter / 点标签 / 清空之后读一次存储、刷一次文字（records 内部还有内存缓存，不碰 flash）
  - update() 只画静态框体（标签、名次徽章、分隔线），文字全部由 label 承担
这样它和其他游戏页共用同一套 build/update/onTap 接口，但几乎不花主循环的钱。
@note
成绩文案不在这里拼：每款游戏自己实现 format_value(v)（"45 步" / "4096 分" / "01:23"），
榜单页只负责把它摆到名次后面。想加新游戏时这一页不用改。
]]

local fx = require "fx"
local T = require "theme"
local records = require "records"

local M = {}

M.name = "排行榜"
M.en = "LEADERBOARD"
M.desc = "看看每款小游戏最厉害的成绩"
M.tip = "点左边的游戏名，就能换一个榜看"
M.accent = T.c.gold
M.is_rank = true
M.record_key = nil
M.rules = "这里记着每款小游戏最好的 5 个成绩。\n点左边的游戏名就能换一个榜看。\n成绩会自动保存，关机再开机也还在。\n想重新开始比，可以点右上角的清空。"

local games = {}

function M.init(list)
    games = list or {}
end

-- 大厅卡片上的固定说明（这一页没有 record_key，大堂显示不了"最佳成绩"）
M.card_note = "七款游戏 / 都能看前 5 名"

--[[大厅迷你预览：三级领奖台 + 冠军那颗会呼吸的金星]]
function M.preview(P, x, y, w, h, t)
    local bw = math.floor((w - 24) / 3)
    local ground = y + h - 6
    local hs = { 16, 28, 12 }
    for i = 1, 3 do
        local bx = x + 12 + (i - 1) * (bw + 6)
        P:box(bx, ground - hs[i], bw, hs[i],
            (i == 2) and T.c.gold or T.c.line2, 255, 5)
    end
    local k = 0.5 + 0.5 * fx.breathe(t, 0.4)
    P:dot(x + 12 + bw + 6 + math.floor(bw / 2), ground - 36, 4, T.c.gold,
        math.floor(180 + 75 * k))
end

local function value_text(g, v)
    if g.format_value then return g.format_value(v) end
    return tostring(v)
end

function M.build(root, W, H, host)
    local o = {}

    local sel = 1                 -- 当前查看的游戏（1..7）
    local lbs_tab = {}            -- 左侧 7 个标签
    local lbs_value, lbs_date, lbs_no = {}, {}, {}
    local lb_title, lb_sub, lb_empty, lb_clear

    local tr = T.rank.tab
    local bd = T.rank.board
    local row = T.rank.row

    -- ==================== 左侧游戏标签 ====================
    for i = 1, #games do
        local y = tr.y + (i - 1) * (tr.h + tr.gap)
        lbs_tab[i] = airui.label({
            parent = root,
            x = tr.x, y = y + 14, w = tr.w, h = 30,
            text = games[i].name, font_size = T.f.text, color = T.c.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- ==================== 右侧榜单卡 ====================
    lb_title = airui.label({
        parent = root, x = bd.x + 24, y = bd.y + 20, w = 420, h = 36,
        text = "", font_size = T.f.title, color = T.c.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })
    lb_sub = airui.label({
        parent = root, x = bd.x + 24, y = bd.y + 54, w = 460, h = 20,
        text = "", font_size = T.f.sub, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    lb_clear = airui.label({
        parent = root, x = bd.x + bd.w - 154, y = bd.y + 22, w = 130, h = 26,
        text = "清空这个榜", font_size = T.f.sub, color = 0xD9532B,
        align = airui.TEXT_ALIGN_CENTER,
    })

    for i = 1, 5 do
        local y = bd.y + row.y + (i - 1) * (row.h + row.gap)
        -- 名次数字要正好压在 update() 画的徽章圆心（行首 42px 处）上
        lbs_no[i] = airui.label({
            parent = root,
            x = bd.x + 20 + 42 - math.floor(T.rank.badge / 2), y = y + 18,
            w = T.rank.badge, h = 28,
            text = "", font_size = T.f.text, color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER,
        })
        lbs_value[i] = airui.label({
            parent = root, x = bd.x + 104, y = y + 14, w = 400, h = 38,
            text = "", font_size = T.f.body, color = T.c.txt,
            align = airui.TEXT_ALIGN_LEFT,
        })
        lbs_date[i] = airui.label({
            parent = root, x = bd.x + 520, y = y + 22, w = 260, h = 22,
            text = "", font_size = T.f.sub, color = T.c.dim2,
            align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    lb_empty = airui.label({
        parent = root, x = bd.x + 24, y = bd.y + 180, w = bd.w - 48, h = 60,
        text = "还没有成绩\n快去玩一局吧！", font_size = T.f.body, color = T.c.dim,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ==================== 刷新一屏文字 ====================
    local function refresh()
        local g = games[sel]
        if not g then return end

        for i = 1, #games do
            local on = (i == sel)
            lbs_tab[i]:set_color(on and 0xFFFFFF or T.c.dim)
        end

        lb_title:set_text(g.name)
        lb_sub:set_text(g.rank_hint or "成绩最好的排在最前面")

        local list = g.record_key and records.list(g.record_key) or {}
        local has = #list > 0
        lb_empty:set_text(has and "" or "还没有成绩\n快去玩一局吧！")
        -- 空榜没有可清的东西，按钮文字一起收起来（label 不能 set_hidden）
        lb_clear:set_text(has and "清空这个榜" or "")

        for i = 1, 5 do
            local it = list[i]
            if it then
                lbs_no[i]:set_text(tostring(i))
                lbs_value[i]:set_text(value_text(g, it.v))
                lbs_date[i]:set_text(records.fmt_date(it.t))
            else
                lbs_no[i]:set_text("")
                lbs_value[i]:set_text("")
                lbs_date[i]:set_text("")
            end
        end
    end

    o.onEnter = function() refresh() end

    -- ==================== 每帧绘制（只画框体）====================
    o.update = function(self, P, t, dt)
        local g = games[sel]
        local acc = (g and g.accent) or T.c.gold

        -- 左侧标签
        for i = 1, #games do
            local y = tr.y + (i - 1) * (tr.h + tr.gap)
            local ga = games[i]
            local on = (i == sel)
            if on then
                P:shadow(tr.x, y, tr.w, tr.h, 12, 44)
                P:box(tr.x, y, tr.w, tr.h, ga.accent or T.c.blue, 255, 16)
            else
                P:box(tr.x, y, tr.w, tr.h, T.c.panel, 255, 16)
                P:frame(tr.x, y, tr.w, tr.h,
                    fx.mix(ga.accent or T.c.blue, T.c.panel, 0.55), 2, 255, 16)
            end
        end

        -- 右侧榜单卡
        P:shadow(bd.x, bd.y, bd.w, bd.h, 16, 40)
        P:box(bd.x, bd.y, bd.w, bd.h, T.c.panel, 255, 20)
        P:frame(bd.x, bd.y, bd.w, bd.h, fx.mix(acc, T.c.panel, 0.35), 3, 255, 20)
        P:box(bd.x + 24, bd.y + 15, 56, 6, acc, 255, 3)

        local list = (g and g.record_key) and records.list(g.record_key) or {}
        local has = #list > 0

        -- 清空按钮：白底红字的小胶囊（空榜时按钮不存在，框也不画）
        if has then
            P:box(bd.x + bd.w - 156, bd.y + 20, 134, 30, 0xFFF3EF, 255, 12)
            P:frame(bd.x + bd.w - 156, bd.y + 20, 134, 30, 0xF3C7B8, 2, 255, 12)
        end

        if has then
            for i = 1, 5 do
                local y = bd.y + row.y + (i - 1) * (row.h + row.gap)
                if list[i] then
                    -- 第 1 名淡金底，其余淡奶油底：一眼看出谁是第一
                    local bg = (i == 1) and fx.mix(T.c.gold, T.c.panel, 0.84) or 0xFFFBF2
                    P:box(bd.x + 20, y, bd.w - 40, row.h, bg, 255, 14)

                    local cy = y + math.floor(row.h / 2)
                    local bc
                    if i == 1 then
                        bc = T.c.gold
                    elseif i == 2 then
                        bc = T.c.silver
                    elseif i == 3 then
                        bc = T.c.bronze
                    else
                        bc = 0xE8DFD0
                    end
                    P:dot(bd.x + 20 + 42, cy, math.floor(T.rank.badge / 2), bc, 255)
                    if i == 1 then
                        -- 冠军：徽章外面再加一圈金环，配合淡金底
                        local k = fx.breathe(t, 0)
                        P:ring(bd.x + 20 + 42, cy, math.floor(T.rank.badge / 2) + 4,
                            T.c.gold, 2, math.floor(120 + 90 * k))
                    end
                end
            end
        end
    end

    -- ==================== 点击 ====================
    o.onTap = function(self, x, y)
        -- 左侧标签切换
        for i = 1, #games do
            local ty = tr.y + (i - 1) * (tr.h + tr.gap)
            if T.hit(x, y, tr.x, ty, tr.w, tr.h) then
                if sel ~= i then
                    sel = i
                    refresh()
                    log.info("ui_rank", "切换到", games[i].name)
                end
                return
            end
        end

        -- 清空（要二次确认，孩子手滑很容易点到）
        if T.hit(x, y, bd.x + bd.w - 156, bd.y + 20, 134, 30) then
            local g = games[sel]
            if not g or not g.record_key then return end
            if #records.list(g.record_key) == 0 then return end   -- 空榜没什么可清
            local function do_clear()
                records.clear(g.record_key)
                refresh()
            end
            if host and host.confirm then
                host.confirm("清空这个榜？",
                    string.format("%s 的成绩会全部删掉，删了就找不回来啦。", g.name),
                    "确定清空", do_clear)
            else
                do_clear()
            end
            return
        end
    end

    o.stats = function(self)
        local g = games[sel]
        local list = (g and g.record_key) and records.list(g.record_key) or {}
        return string.format("正在看 %s", g and g.name or "--"),
            string.format("已记录 %d 个成绩 / 最多记 5 个", #list)
    end

    o.restart = function(self) refresh() end

    refresh()
    return o
end

return M
