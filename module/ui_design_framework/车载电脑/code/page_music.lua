--[[
@module page_music
@summary 音乐页（左侧 dock / 首页·主题歌单标签 / 主题歌单卡 / 最近播放 / 播放条）
        对照 preview.html 的 .music-* 规则；顶栏与设计稿一致只留 返回+音乐+LOGO+宫格。
]]
local sys = require "sys"
local theme = require "theme"
require "mock"

local W, H = theme.W, theme.H

theme.make_page("music", function(root, M)
    local C = theme.C
    local db = theme.debounce()
    local mu = MOCK.music

    -- 顶栏：返回 + 音乐 + LOGO + 宫格（设计稿无状态图标/时间）
    theme.topbar(root, "back", false, true)

    local TOP = theme.TOP_H
    local BW = W - theme.PAD * 2

    ------------------------------------------------------------------
    -- 通用弹层：播放列表 / 收藏 / MV / 搜索（对照 preview.html 的 #scrim .sheet）
    ------------------------------------------------------------------
    local layer, draw_sheet
    local sh = { open = false, kind = nil }
    local function sheet_close()
        sh.open = false
        sh.kind = nil
        if layer then pcall(function() layer:destroy() end) layer = nil end
    end
    local function sheet_open(kind)
        sh.open = true
        sh.kind = kind
        if draw_sheet then draw_sheet() end
    end

    local function stxt(p, x, y, w, h, s, col, size, align)
        airui.label({ parent = p, x = math.floor(x), y = math.floor(y),
            w = math.floor(w), h = math.floor(h), text = s, color = col or C.text,
            font_size = size or 16, align = align or airui.TEXT_ALIGN_LEFT })
    end
    local function srow(p, x, y, w, n, t1, t2, on, fn)
        -- 行背景与弹层卡同色，只靠描边区分，避免出现两块不同底色
        airui.container({ parent = p, x = x, y = y, w = w, h = 44,
            color = on and C.sel_str or C.card, radius = 10,
            border_color = on and C.blue2 or C.line2, border_width = 1 })
        local tx = x + 16
        if n then
            stxt(p, tx, y + 11, 30, 22, n, C.dim, 16)
            tx = tx + 30
        end
        stxt(p, tx, y + 11, w - (tx - x) - (t2 and 70 or 16), 22, t1, C.text, 16)
        if t2 then stxt(p, x + w - 66, y + 11, 50, 22, t2, C.sub, 16, airui.TEXT_ALIGN_RIGHT) end
        if fn then theme.click(p, x, y, w, 44, fn, 10) end
    end

    draw_sheet = function()
        if layer then pcall(function() layer:destroy() end) layer = nil end
        if not sh.open then return end
        local cw, ch = 520, 470
        if sh.kind == "pl" then ch = 96 + #MOCK.music.extra * 52 end
        local cx = math.floor((W - cw) / 2)
        local cy = math.floor((H - ch) / 2)
        layer = airui.container({ parent = root, x = 0, y = 0, w = W, h = H,
            color = C.bg, color_opacity = 1 })
        airui.container({ parent = layer, x = 0, y = 0, w = W, h = H,
            color = 0x050B14, color_opacity = 150 })
        theme.click(layer, 0, 0, W, H, sheet_close)
        airui.container({ parent = layer, x = cx, y = cy, w = cw, h = ch,
            color = C.card, radius = 18, border_color = C.line2, border_width = 1 })
        theme.click(layer, cx, cy, cw, ch, function() end, 18)

        -- 关闭键 ×
        airui.container({ parent = layer, x = cx + cw - 42, y = cy + 13, w = 26, h = 26,
            color = C.card, radius = 13, border_color = C.line, border_width = 1 })
        airui.shape({ parent = layer, x = cx + cw - 42, y = cy + 13, w = 26, h = 26, items = {
            { type = "line", x1 = 10, y1 = 10, x2 = 16, y2 = 16, color = C.sub, width = 1 },
            { type = "line", x1 = 16, y1 = 10, x2 = 10, y2 = 16, color = C.sub, width = 1 } } })
        theme.click(layer, cx + cw - 46, cy + 9, 34, 34, sheet_close, 17)

        if sh.kind == "list" then
            stxt(layer, cx + 20, cy + 14, cw - 80, 26, "播放列表", C.title, 20)
            stxt(layer, cx + 20, cy + 46, cw - 40, 20, "我的歌单 · 共 " .. #mu.list .. " 首", C.dim, 16)
            local by = cy + 74
            for k, s in ipairs(mu.list) do
                srow(layer, cx + 20, by, cw - 40, tostring(k), s.title,
                    MOCK.mmss(s.dur), k == mu.cur, function()
                        MOCK.mu_pick(k)
                        sheet_close()
                        theme.rerender_current()
                    end)
                by = by + 52
            end
        elseif sh.kind == "pl" then
            stxt(layer, cx + 20, cy + 14, cw - 80, 26, "更多歌单", C.title, 20)
            local by = cy + 52
            for k, p in ipairs(MOCK.music.extra) do
                airui.container({ parent = layer, x = cx + 20, y = by, w = cw - 40, h = 44,
                    color = C.card, radius = 10, border_color = C.line2, border_width = 1 })
                theme.shapes(layer, cx + 36, by + 17, 10, 10, {
                    { type = "circle", cx = 5, cy = 5, r = 4, color = C.blue2, width = 1,
                      fill = true, fill_color = C.blue2 } })
                stxt(layer, cx + 58, by + 11, cw - 120, 22, p.name, C.text, 16)
                local pk, pn = k, p.name
                theme.click(layer, cx + 20, by, cw - 40, 44, function()
                    MOCK.mu_pick_pl(pk)
                    sheet_close()
                    theme.rerender_current()
                    sys.timerStart(function() theme.toast("已播放 · " .. pn) end, 60)
                end, 10)
                by = by + 52
            end
        elseif sh.kind == "fav" then
            stxt(layer, cx + 20, cy + 14, cw - 80, 26, "我的收藏", C.title, 20)
            local favs = MOCK.mu_fav_list()
            if #favs == 0 then
                -- 提示里的 ♡ 是 hzfont 没有的字符，渲染成一个空方框（用户反馈
                -- 「有一个方框」）→ 换成纯中文描述，不用任何符号
                stxt(layer, cx + 20, cy + 60, cw - 40, 22, "还没有收藏，点播放条右侧的收藏按钮试试", C.dim, 16)
            else
                local by = cy + 60
                for k, t in ipairs(favs) do
                    srow(layer, cx + 20, by, cw - 40, nil, t, nil, false, function()
                        MOCK.mu_pick_song(t)
                        sheet_close()
                        theme.rerender_current()
                    end)
                    by = by + 52
                end
            end
        elseif sh.kind == "mv" then
            stxt(layer, cx + 20, cy + 14, cw - 80, 26, "MV 视频", C.title, 20)
            stxt(layer, cx + 20, cy + 60, cw - 40, 22, "当前歌曲暂无 MV，先听听歌吧", C.dim, 16)
            srow(layer, cx + 20, cy + 100, cw - 40, nil, "返回音乐", nil, false, sheet_close)
        elseif sh.kind == "search" then
            stxt(layer, cx + 20, cy + 14, cw - 80, 26, "搜索歌曲", C.title, 20)
            airui.container({ parent = layer, x = cx + 20, y = cy + 50, w = cw - 160, h = 40,
                color = C.deep, radius = 10, border_color = C.blue2, border_width = 1 })
            stxt(layer, cx + 34, cy + 60, cw - 180, 22, "输入歌名 / 歌手", C.dim, 16)
            airui.container({ parent = layer, x = cx + cw - 130, y = cy + 50, w = 110, h = 40,
                color = C.sel_str, radius = 10, border_color = C.blue2, border_width = 1 })
            stxt(layer, cx + cw - 130, cy + 60, 110, 22, "搜索", C.blue2, 16, airui.TEXT_ALIGN_CENTER)
            theme.click(layer, cx + cw - 130, cy + 50, 110, 40, function()
                theme.toast("演示版：点下方热门歌曲试听")
            end, 10)
            stxt(layer, cx + 20, cy + 104, cw - 40, 20, "热门歌曲", C.dim, 16)
            local by = cy + 132
            for k, s in ipairs(mu.list) do
                srow(layer, cx + 20, by, cw - 40, nil, s.title, s.artist, false, function()
                    MOCK.mu_pick(k)
                    sheet_close()
                    theme.rerender_current()
                end)
                by = by + 52
            end
        end
    end

    ------------------------------------------------------------------
    -- 左侧 dock：5 个图标（首页/收藏/唱片/MV/搜索）
    ------------------------------------------------------------------
    local docks = { "home", "heart", "disc", "mv", "search" }
    -- 竖向铺满到播放条上方（原来固定 92 步距，底部空一大截）
    local dock_top = TOP + 14
    local dock_gap = math.floor(((H - 72 - 12) - dock_top - 5 * 46) / 4)
    for i, k in ipairs(docks) do
        local dy = dock_top + (i - 1) * (46 + dock_gap)
        local on = (k == "disc")
        airui.container({ parent = root, x = theme.PAD, y = dy, w = 54, h = 46,
            color = on and C.sel or C.card, radius = 12,
            border_color = on and C.blue2 or C.line, border_width = 1 })
        theme.icon(root, theme.PAD + 14, dy + 9, 20, k, C.icon,
            k == "home" and C.card or nil)
        local kk = k
        theme.click(root, theme.PAD, dy, 54, 46, function()
            if kk == "home" then
                theme.go_defer("home")
            elseif kk == "heart" then
                sheet_open("fav")
            elseif kk == "disc" then
                sheet_open("list")
            elseif kk == "mv" then
                sheet_open("mv")
            else
                sheet_open("search")
            end
        end, 12)
    end

    local mx = theme.PAD + 66
    local mw = W - theme.PAD - mx

    ------------------------------------------------------------------
    -- 标签：首页 / 主题歌单 / 更多歌单 >
    ------------------------------------------------------------------
    local tabs = { "首页", "主题歌单" }
    local tx = mx
    for i, name in ipairs(tabs) do
        local tw = 76 + (i == 2 and 22 or 0)
        local sel = (i == 2)
        theme.pill(root, { x = tx, y = TOP + 12, w = tw, h = 30 }, name, {
            bg = sel and C.sel_str or C.deep,
            color = sel and C.text or C.sub,
            border = sel and C.blue2 or C.line,
            font = 16,
        })
        local ti = i
        theme.click(root, tx, TOP + 12, tw, 30, function()
            if ti == 1 then theme.go_defer("home")
            else theme.toast("主题歌单：共 " .. #MOCK.music.mixes .. " 张") end
        end, 15)
        tx = tx + tw + 10
    end
    airui.label({ parent = root, x = mx + mw - 130, y = TOP + 17, w = 130, h = 22,
        text = "更多歌单 >", color = C.blue2, font_size = 16,
        align = airui.TEXT_ALIGN_RIGHT })
    local mb = airui.container({ parent = root, x = mx + mw - 140, y = TOP + 10, w = 140, h = 34,
        color = C.bg, color_opacity = 1 })
    mb:set_on_click(function()
        db(function() sheet_open("pl") end)
    end)

    ------------------------------------------------------------------
    -- 主题歌单卡（5 张，图形全部用安全图元：实心圆叠环 + 粗线）
    ------------------------------------------------------------------
    -- 5 张主题歌单：名字 / 渐变色 / 图形顺序与 preview.html 的 .tcard 一致
    local cards = {
        { title = "清新歌单", kind = "arc",   c1 = 0x0F9D6B, c2 = 0x0A3F52 },
        { title = "休闲歌单", kind = "ring",  c1 = 0x1E6BE0, c2 = 0x0A2E6E },
        { title = "醒脑歌单", kind = "dots",  c1 = 0x7A3BE8, c2 = 0x2A1160 },
        { title = "能量歌单", kind = "mount", c1 = 0xE23B5C, c2 = 0x7A0E22 },
        { title = "怀旧歌单", kind = "box",   c1 = 0x8A5A1E, c2 = 0x35200A },
    }
    local cgap = 12
    local cw = math.floor((mw - (5 - 1) * cgap) / 5)
    local ch = 180
    local cband = 38                 -- 底部名字条高度（对照原型 .tcard .nm 的 38px）
    local cart = ch - cband          -- 图形区高度
    local cy = TOP + 52

    for i, cd in ipairs(cards) do
        local x = mx + (i - 1) * (cw + cgap)
        local bg = theme.blend(cd.c1, cd.c2, 0.35)
        local pale = theme.blend(0xF2FAFF, bg, 0.60)
        -- 选中态（对照 html 的 .song-card.on）：蓝边加粗 + 左上角「正在播放」胶囊
        local on = (MOCK.music.mix or 1) == i
        airui.container({ parent = root, x = x, y = cy, w = cw, h = ch,
            color = bg, radius = 14,
            border_color = on and C.blue2 or C.line, border_width = on and 2 or 1 })

        -- 封面图形：整块 pcall 保护，任何失败都不影响后续卡片。
        -- 画布高度给足 cart，图形按 cart 区域定位；原来写死 132 高，卡片下半截
        -- 没有图、名字又排在卡外，看起来就是「缺了一块」。
        local it  = {}
        local cxl = math.floor(cw / 2)
        local acx = cxl
        local acy = math.floor(cart * 0.80)                    -- 彩虹半圆的圆心
        local r1  = math.max(20, math.floor(math.min(cw * 0.30, cart * 0.36)))
        local rw  = math.max(4, math.floor(r1 * 0.17))         -- 环宽
        local mcy = math.floor(cart * 0.50)                    -- 其余图形居中
        local function donut(ccx, ccy, ro, ri)
            theme._ci(it, ccx, ccy, ro, pale, 255)
            theme._ci(it, ccx, ccy, ri, bg, 255)
        end
        local function ring(ccy, ratio)
            local ro = math.max(2, math.floor(r1 * ratio))
            donut(acx, ccy, ro, math.max(1, ro - rw))
        end
        if cd.kind == "arc" then
            ring(acy, 1.0)
            ring(acy, 0.66)
            ring(acy, 0.33)
            -- 只留上半圈 → 三道彩虹弧（下半圈用卡底色盖掉）
            -- 遮罩必须缩进 2px：x=0 / w=cw 会把卡片左右 2px 的描边一起盖掉，
            -- 选中态蓝框就会在两侧中段「断开」（用户截图反馈的那个缺口）
            theme._rc(it, 2, acy, cw - 4, math.max(1, cart - acy), bg, 0)
        elseif cd.kind == "ring" then
            ring(mcy, 1.0)
            ring(mcy, 0.62)
            theme._ci(it, acx, mcy, math.max(2, math.floor(r1 * 0.18)), pale, 255)
        elseif cd.kind == "dots" then
            local k = r1 / 34
            theme._ci(it, acx - math.floor(18 * k), mcy + 4, math.floor(26 * k), pale, 200)
            theme._ci(it, acx + math.floor(20 * k), mcy - 10, math.floor(20 * k), pale, 160)
            theme._ci(it, acx + math.floor(2 * k),  mcy + 22, math.floor(16 * k), pale, 220)
        elseif cd.kind == "mount" then
            local k  = r1 / 34
            local bl = mcy + math.floor(34 * k)   -- 山脚
            local tp = mcy - math.floor(32 * k)   -- 山顶
            theme._ln(it, acx - math.floor(44 * k), bl, acx - math.floor(6 * k), tp, pale, 3)
            theme._ln(it, acx - math.floor(6 * k),  tp, acx + math.floor(32 * k), bl, pale, 3)
            theme._ln(it, acx - math.floor(20 * k), bl, acx + math.floor(2 * k), mcy - math.floor(2 * k), pale, 3)
            theme._ln(it, acx + math.floor(2 * k),  mcy - math.floor(2 * k), acx + math.floor(24 * k), bl, pale, 3)
        else
            local bw = math.floor(r1 * 1.9)
            local bh = math.floor(r1 * 1.4)
            theme._rc(it, acx - math.floor(bw / 2), mcy - math.floor(bh / 2), bw, bh, pale, 12)
            theme._ln(it, acx - math.floor(bw / 2), mcy, acx + math.floor(bw / 2), mcy, bg, 2)
        end
        pcall(theme.shapes, root, x, cy, cw, cart, it)

        -- 底部名字条（对照原型 .tcard .nm：半透明深色条 + 居中的名字）
        -- 左右各缩进 1px：与卡片同宽会把 2px 的选中描边压在下面，
        -- 蓝框两侧中段就会缺一截
        airui.container({ parent = root, x = x + 1, y = cy + cart, w = cw - 2, h = cband,
            color = theme.blend(bg, 0x04101C, 0.62), radius = 12 })
        airui.label({ parent = root, x = x + 1, y = cy + cart + 8, w = cw - 2, h = 22,
            text = cd.title, color = C.bright, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })

        -- 「正在播放」角标：深底 + 绿三角 + 绿字（和 preview.html 的 .nowbadge 一致）
        if on then
            airui.container({ parent = root, x = x + 8, y = cy + 8, w = 100, h = 28,
                color = 0x0B1C2E, radius = 14,
                border_color = theme.blend(C.green, 0x0B1C2E, 0.55), border_width = 1 })
            theme.icon(root, x + 14, cy + 15, 12, "play", C.green)
            airui.label({ parent = root, x = x + 30, y = cy + 11, w = 68, h = 22,
                text = "正在播放", color = C.green, font_size = 16 })
        end

        theme.click(root, x, cy, cw, ch, function()
            -- 切歌单：换「最近播放」列表 + 从头播；先重建再弹提示，
            -- 否则 toast 会挂在马上被销毁的旧 root 上
            MOCK.mu_mix(i)
            theme.rerender_current()
            sys.timerStart(function() theme.toast("已播放 · " .. cd.title) end, 60)
        end, 14)
    end

    ------------------------------------------------------------------
    -- 最近播放（3 张大卡）
    ------------------------------------------------------------------
    local ay = cy + ch + 12
    airui.label({ parent = root, x = mx, y = ay, w = 200, h = 22,
        text = "最近播放", color = C.title, font_size = 16 })

    -- 最近播放：横向滑动列表（用户要求音乐页有滑动效果）。
    -- 用 scrollable=true 的容器装所有歌单曲目（15 张卡，远宽于可视区），
    -- 手指左右拖拽即可滑动；容器本身不画底色之外的装饰，滑动时不会撕裂。
    local albums = MOCK.mu_all_albums()
    local agap = 12
    local aw = 240
    local ah = 200
    local aye = ay + 26
    local strip = airui.container({ parent = root, x = mx, y = aye, w = mw, h = ah,
        color = C.bg, color_opacity = 1, scrollable = true })

    for i, a in ipairs(albums) do
        local x = (i - 1) * (aw + agap)
        local cov = theme.blend(a.c1, a.c2, 0.5)
        airui.container({ parent = strip, x = x, y = 0, w = aw, h = ah,
            color = C.card, radius = 12, border_color = C.line, border_width = 1 })
        airui.container({ parent = strip, x = x + 6, y = 6, w = aw - 12, h = 126,
            color = cov, radius = 10 })

        -- 封面装饰 + 播放按钮
        local pale = theme.blend(0xFFFFFF, cov, 0.30)
        pcall(theme.shapes, strip, x + 6, 6, aw - 12, 126, {
            { type = "circle", cx = aw - 60, cy = 36, r = 28, color = pale, width = 1,
              fill = true, fill_color = pale, fill_opacity = 60 },
            { type = "circle", cx = aw - 96, cy = 68, r = 18, color = pale, width = 1,
              fill = true, fill_color = pale, fill_opacity = 40 },
        })
        local bx, by = x + math.floor(aw / 2) - 18, 54
        pcall(theme.shapes, strip, bx, by, 36, 36, {
            { type = "circle", cx = 18, cy = 18, r = 17, color = C.bright, width = 1,
              fill = true, fill_color = C.float, fill_opacity = 210 },
        })
        theme.icon(strip, bx + 10, by + 10, 16, "play", C.bright)

        airui.label({ parent = strip, x = x + 12, y = 142, w = aw - 60, h = 20,
            text = a.title, color = C.text, font_size = 16 })
        airui.label({ parent = strip, x = x + 12, y = 166, w = aw - 24, h = 20,
            text = a.artist, color = C.sub, font_size = 16 })
        theme.icon(strip, x + aw - 30, 144, 16, "more", C.dim)

        -- 点哪张卡就放哪首：不能用卡片序号去索引播放列表（会放到别的歌）
        theme.click(strip, x, 0, aw, ah, function()
            MOCK.mu_play_album(a)
            theme.rerender_current()
            sys.timerStart(function() theme.toast("正在播放 · " .. a.title) end, 60)
        end, 14)
    end

    ------------------------------------------------------------------
    -- 播放条 .playerbar
    ------------------------------------------------------------------
    local pb = { x = theme.PAD, y = H - 72, w = BW, h = 60 }
    theme.card(root, pb, { radius = 14 })

    -- 封面
    local song = MOCK.mu_song()
    airui.container({ parent = root, x = pb.x + 10, y = pb.y + 10, w = 40, h = 40,
        color = song.cv_bg, radius = 8 })
    theme.icon(root, pb.x + 20, pb.y + 20, 20, "disc", C.bright)

    -- 留引用：自动切歌后播放条左侧的曲名 / 歌手要跟着变
    local pb_title = airui.label({ parent = root, x = pb.x + 60, y = pb.y + 6, w = 170, h = 22,
        text = song.title, color = C.text, font_size = 16 })
    local pb_artist = airui.label({ parent = root, x = pb.x + 60, y = pb.y + 26, w = 170, h = 22,
        text = song.artist, color = C.sub, font_size = 16 })

    -- 进度条：换成视频页同款的 airui.slider —— 胶囊轨道 + 蓝色已播 + 白色圆钮，
    -- 手指可以左右拖动 seek。原来自绘的 theme.progress 只有 8px 高、旋钮 7px，
    -- 蓝条贴着细轨道，用户反馈「有点丑、想能滑动」。
    -- on_change 的参数是 slider 控件本身（不是数值），按 jq_music_studio 的范式
    -- 取 self:get_value()，并且只有拿到数字才回写，避免把控件句柄存进 pos。
    local prog, cur_lbl
    pcall(function()
        -- 轨道做细：LVGL slider 的旋钮直径 = 控件高度，h=26 时圆钮比时间字还高，
        -- 显得又粗又蠢（用户反馈「进度条小一点」）。h=12 → 旋钮 12px，
        -- 圆角同步改成 6，垂直位置下移让轨道落在时间上方居中的位置
        prog = airui.slider({ parent = root, x = pb.x + 240, y = pb.y + 16, w = 340, h = 12,
            min = 0, max = math.max(1, MOCK.mu_dur()), value = MOCK.music.pos,
            style = { bg_color = C.track, bg_opa = 255,
                indicator_color = C.blue, knob_color = C.knob,
                radius = 6, pad = 3 },
            on_change = function(self)
                local v
                if type(self) == "number" then
                    v = self
                else
                    pcall(function() v = self:get_value() end)
                end
                if type(v) ~= "number" then return end
                MOCK.mu_seek(v)
                pcall(function() cur_lbl:set_text(MOCK.mmss(MOCK.music.pos)) end)
            end })
    end)
    cur_lbl = airui.label({ parent = root, x = pb.x + 240, y = pb.y + 34, w = 70, h = 22,
        text = MOCK.mmss(MOCK.music.pos), color = C.dim, font_size = 16 })
    local dur_lbl = airui.label({ parent = root, x = pb.x + 510, y = pb.y + 34, w = 70, h = 22,
        text = MOCK.mmss(MOCK.mu_dur()), color = C.dim, font_size = 16,
        align = airui.TEXT_ALIGN_RIGHT })

    -- 控制按钮：上一首 / 播放 / 下一首 / 收藏 / 列表
    -- 圆形播放键中心在 cxp+62；上一首/下一首原来分别在 cxp、cxp+116（间距 53 / 63，
    -- 既不相等又太散），改成两侧各距中心 40px、图标放大到 20，三个键凑成一簇
    local cxp = pb.x + 640
    theme.icon(root, cxp + 12, pb.y + 20, 20, "prev", C.icon)
    theme.icon(root, cxp + 92, pb.y + 20, 20, "next", C.icon)
    -- 收藏心：收藏后变红（对照 html 的 .heart.on）
    theme.icon(root, cxp + 172, pb.y + 23, 16, "heart", mu.fav and C.pink or C.icon)
    theme.icon(root, cxp + 214, pb.y + 23, 16, "more", C.icon)

    -- 圆形播放键：浅蓝底 + 蓝色三角（对照 html 的 .pbtn）
    pcall(theme.shapes, root, cxp + 44, pb.y + 12, 36, 36, {
        { type = "circle", cx = 18, cy = 18, r = 17, color = C.blue2, width = 1,
          fill = true, fill_color = C.sel_str, fill_opacity = 255 },
    })
    local ppi = airui.shape({ parent = root, x = cxp + 52, y = pb.y + 20, w = 20, h = 20,
        items = {} })
    local function pp_items()
        if mu.playing then
            return {
                { type = "rect", x = 4, y = 3, w = 4, h = 14, color = C.blue2, width = 1,
                  radius = 1, fill = true, fill_color = C.blue2, fill_opacity = 255 },
                { type = "rect", x = 12, y = 3, w = 4, h = 14, color = C.blue2, width = 1,
                  radius = 1, fill = true, fill_color = C.blue2, fill_opacity = 255 },
            }
        end
        return {
            { type = "line", x1 = 4, y1 = 3, x2 = 17, y2 = 10, color = C.blue2, width = 3 },
            { type = "line", x1 = 17, y1 = 10, x2 = 4, y2 = 17, color = C.blue2, width = 3 },
            { type = "line", x1 = 4, y1 = 3, x2 = 4, y2 = 17, color = C.blue2, width = 3 },
        }
    end
    ppi:set_items(pp_items())

    -- 统一走 theme.click（on_click + 长按兜底，延迟 30ms 执行）：
    -- 透明容器 + set_on_click 在部分固件收不到点击
    local function hit(x, y, w, h, fn) theme.click(root, x, y, w, h, fn, 12) end
    -- 热区互相不重叠（各留 2px 空档）：上一首 4..38，播放键 40..84，下一首 86..120
    hit(cxp + 4, pb.y + 6, 34, 46, function()
        MOCK.mu_prev()
        theme.rerender_current()
    end)
    hit(cxp + 86, pb.y + 6, 34, 46, function()
        MOCK.mu_next()
        theme.rerender_current()
    end)
    hit(cxp + 40, pb.y + 2, 44, 54, function()
        MOCK.mu_toggle()
        pcall(function() ppi:set_items(pp_items()) end)
        theme.toast(MOCK.music.playing and "继续播放" or "已暂停")
    end)
    hit(cxp + 156, pb.y + 6, 44, 46, function()
        MOCK.mu_fav()
        theme.toast(MOCK.music.fav and "已收藏" or "已取消收藏")
        theme.rerender_current()
    end)
    hit(cxp + 198, pb.y + 6, 44, 46, function()
        sheet_open("list")
    end)

    return function()
        MOCK.mu_tick()
        local s = MOCK.mu_song() or { title = "", artist = "", dur = 1 }
        local dur = math.max(1, s.dur or 1)
        -- 每项单独 pcall：任一控件报错都不该把其余刷新带停
        -- 进度：手指正在拖时（slider 值与数据差得多）不回写，避免把拖动打断
        pcall(function()
            if not prog then return end
            local nv
            pcall(function() nv = prog:get_value() end)
            if type(nv) ~= "number" or math.abs(nv - MOCK.music.pos) <= 2 then
                prog:set_value(MOCK.music.pos)
            end
        end)
        pcall(function() cur_lbl:set_text(MOCK.mmss(MOCK.music.pos)) end)
        pcall(function() dur_lbl:set_text(MOCK.mmss(dur)) end)
        pcall(function() pb_title:set_text(s.title) end)
        pcall(function() pb_artist:set_text(s.artist) end)
        pcall(function() ppi:set_items(pp_items()) end)
    end
end)
