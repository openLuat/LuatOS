--[[
@module page_home
@summary 首页：天气卡 / APP 列表 / 空调拨盘 / 视频 / 智能语音 / 音乐 / 地图
布局与 preview.html 的 .home-grid 逐列对应：
c1=206 c2=206 c3=194 c4=172 c5=flex，gap 12，左右边距 16
注意：整卡点击的透明容器必须先建，卡内可点子控件后建（后建的在最上层）
]]

local theme = require "theme"
local _ln = theme._ln
local W, H, TOP = theme.W, theme.H, theme.TOP_H

-- 栅格（与 CSS flex 比例换算的固定值一致）
local GX, GY = 16, TOP + 12
local GH = H - GY - 14
local C1W, C2W, C3W, C4W = 206, 206, 194, 172
local X1 = GX
local X2 = X1 + C1W + 12
local X3 = X2 + C2W + 12
local X4 = X3 + C3W + 12
local X5 = X4 + C4W + 12
local C5W = W - GX - X5

theme.make_page("home", function(root, M)
    local C = theme.C
    local db = theme.debounce()
    local go = theme.go_defer

    -- 顶栏（头像/LOGO/状态/时间/宫格）——首页右上角是「全部应用」
    theme.topbar(root, nil, true, false, "apps")

    ----------------------------------------------------------------
    -- 列1：天气卡（232 高）
    ----------------------------------------------------------------
    local w = { x = X1, y = GY, w = C1W, h = 232 }
    theme.card(root, w)
    airui.label({ parent = root, x = w.x + 14, y = w.y + 12, w = 100, h = 20,
        text = MOCK.weather.city, color = C.name, font_size = 16 })
    airui.label({ parent = root, x = w.x + 14, y = w.y + 34, w = 90, h = 44,
        text = tostring(MOCK.weather.temp), color = C.text, font_size = 40 })
    airui.label({ parent = root, x = w.x + 58, y = w.y + 66, w = 50, h = 20,
        text = "°C", color = C.sub, font_size = 16 })
    airui.label({ parent = root, x = w.x + 14, y = w.y + 84, w = 110, h = 20,
        text = MOCK.weather.cond, color = C.sub, font_size = 16 })
    theme.cloud_rain(root, w.x + 106, w.y + 22, 84, 52)

    -- 底部三项指标（分隔线 + 三列）
    local my = w.y + w.h - 46
    airui.container({ parent = root, x = w.x + 14, y = my, w = w.w - 28, h = 1,
        color = C.line2 })
    local mets = { { MOCK.weather.rain, "降雨量" }, { MOCK.weather.hum, "湿度" },
                   { MOCK.weather.aqi, "空气质量" } }
    local mw = math.floor((w.w - 28) / 3)
    for i, m in ipairs(mets) do
        local mx = w.x + 14 + (i - 1) * mw
        -- 三列均分只有 59px 宽，16 号「空气质量」4 个字要 68px，
        -- 最后一个「量」被裁掉（用户反馈「量字没有了」）。
        -- 文字缩到 14 号并给 label 左右各留 5px 溢出空间，仍保持视觉居中。
        airui.label({ parent = root, x = mx - 5, y = my + 8, w = mw + 10, h = 18,
            text = m[1], color = C.title, font_size = 14,
            align = airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = root, x = mx - 5, y = my + 26, w = mw + 10, h = 18,
            text = m[2], color = C.dim, font_size = 14,
            align = airui.TEXT_ALIGN_CENTER })
        if i < 3 then
            airui.container({ parent = root, x = mx + mw - 1, y = my + 6,
                w = 1, h = 34, color = C.line2 })
        end
    end
    local wcard = airui.container({ parent = root, x = w.x, y = w.y,
        w = w.w, h = w.h, color = C.bg, color_opacity = 1, radius = 14 })
    wcard:set_on_click(function() db(function() go("weather") end) end)

    ----------------------------------------------------------------
    -- 列1：APP 应用列表（填满余下高度）
    ----------------------------------------------------------------
    local a = { x = X1, y = GY + 232 + 12, w = C1W, h = GH - 232 - 12 }
    theme.card(root, a)
    theme.card_head(root, a, "APP应用列表", "更多", C.sub)
    local apps = {
        { name = "music",  c1 = 0x2E7DFF, c2 = 0x123C8A, kind = "music" },
        { name = "nav",    c1 = 0x22C4E0, c2 = 0x0B5C86, kind = "nav" },
        { name = "apps",   c1 = 0x35D6E8, c2 = 0x0E4F6B, kind = "grid" },
        { name = "task",   c1 = 0x7C5CFF, c2 = 0x2A1C6E, kind = "clock" },
        { name = "ac",     c1 = 0x34D399, c2 = 0x0B5B45, kind = "spark" },
        { name = "voice",  c1 = 0xF5A623, c2 = 0x8A4B06, kind = "mic" },
    }
    -- 图标必须是正方形（原来按剩余高度/2 拉成 54×110 的竖条，很难看）
    local iw = math.floor((a.w - 24 - 20) / 3)
    local ih = iw
    local gv = math.floor((a.h - 42 - 12 - ih * 2) / 3)   -- 上/中/下三段均分
    local gy0 = a.y + 42 + gv
    for i, ap in ipairs(apps) do
        local row = math.floor((i - 1) / 3)
        local col = (i - 1) % 3
        local ix = a.x + 12 + col * (iw + 10)
        local iy = gy0 + row * (ih + gv)
        local bgc = theme.blend(ap.c1, ap.c2, 0.55)
        airui.container({ parent = root, x = ix, y = iy, w = iw, h = ih,
            color = bgc, radius = 10, border_color = C.line, border_width = 1 })
        theme.icon(root, ix + math.floor((iw - 22) / 2),
            iy + math.floor((ih - 22) / 2), 22, ap.kind, C.bright)
        local b = airui.container({ parent = root, x = ix, y = iy, w = iw, h = ih,
            color = C.bg, color_opacity = 1, radius = 10 })
        b:set_on_click(function() db(function() go(ap.name) end) end)
    end
    local more = airui.container({ parent = root, x = a.x + a.w - 56, y = a.y + 8,
        w = 44, h = 26, color = C.bg, color_opacity = 1 })
    more:set_on_click(function() db(function() go("apps") end) end)

    ----------------------------------------------------------------
    -- 列2：空调卡（232 高，拨盘）—— 点击整卡的透明层先建，拨盘后建
    ----------------------------------------------------------------
    local acr = { x = X2, y = GY, w = C2W, h = 232 }
    theme.card(root, acr)
    theme.card_head(root, acr, "空调", "设置", C.sub)
    local accard = airui.container({ parent = root, x = acr.x, y = acr.y,
        w = acr.w, h = acr.h, color = C.bg, color_opacity = 1, radius = 14 })
    accard:set_on_click(function() db(function() go("ac") end) end)

    local dcx = acr.x + math.floor(acr.w / 2)
    local dcy = acr.y + 42 + 59
    -- 拨盘：210° 起顺时针 120° 渐亮弧 + 其余暗弧（对齐 conic-gradient）
    theme.arc_ring(root, dcx, dcy, 56, {
        { f = 0.18, color = C.cyan }, { f = 0.15, color = C.blue },
        { f = 0.67, color = C.track },
    }, -150, 4)
    local ac_temp_lbl = airui.label({ parent = root, x = dcx - 60, y = dcy - 22,
        w = 100, h = 44, text = tostring(MOCK.ac.t.l), color = C.text,
        font_size = 34, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = root, x = dcx + 20, y = dcy - 2, w = 40, h = 20,
        text = "°C", color = C.sub, font_size = 16 })
    -- 左侧上下小圆钮（±1 度）
    local function dial_btn(bx, by, up)
        airui.shape({ parent = root, x = bx, y = by, w = 22, h = 22, items = {
            { type = "circle", cx = 11, cy = 11, r = 10, color = C.line, width = 1,
              fill = true, fill_color = C.sel, fill_opacity = 255 } } })
        theme.icon(root, bx + 5, by + 5, 12, up and "up" or "down", C.icon)
        local b = airui.container({ parent = root, x = bx, y = by, w = 22, h = 22,
            color = C.bg, color_opacity = 1 })
        b:set_on_click(function()
            db(function()
                MOCK.ac_dial_step(up and 1 or -1)
                -- 只改数据不刷新文本的话，屏上温度永远停着不动
                pcall(function() ac_temp_lbl:set_text(tostring(MOCK.ac.t.l)) end)
            end)
        end)
    end
    -- 原来 x = dcx-65（圆心距 68），而圆环珠子外沿到 60，按钮内侧正好压上去
    -- （用户反馈「上下键和圆弧重叠」）→ 外移到 dcx-80，圆心距 80，留 9px 空隙
    dial_btn(dcx - 80, dcy - 53, true)
    dial_btn(dcx - 80, dcy + 31, false)

    ----------------------------------------------------------------
    -- 列2：视频卡（填满余下高度）
    ----------------------------------------------------------------
    local v = { x = X2, y = GY + 232 + 12, w = C2W, h = GH - 232 - 12 }
    theme.card(root, v)
    -- 海报：贴图 code/img/poster.png 56×264（暖金光柱 + 星芒 + 雾气，
    -- 竖幅电影海报氛围图，四角自带 9px 圆角）。
    -- 原来用 container + shapes 拼「棕色圆 + 黑方块」，用户反馈「画得太丑」。
    -- 图缺失时回退到原来的色块，保证不会开天窗。
    local ph = v.h - 20
    local poster = theme.img("poster.png")
    local poster_ok = false
    if poster then
        local ok = pcall(function()
            airui.image({ parent = root, src = poster,
                x = v.x + 12, y = v.y + 10, w = 56, h = ph })
        end)
        poster_ok = ok
    end
    if not poster_ok then
        airui.container({ parent = root, x = v.x + 12, y = v.y + 10, w = 56,
            h = ph, color = 0x3A2E22, radius = 9 })
        theme.shapes(root, v.x + 12, v.y + 10, 56, ph, {
            { type = "circle", cx = 30, cy = 44, r = 22, color = 0x6B4B2A, width = 1,
              fill = true, fill_color = 0x6B4B2A, fill_opacity = 130 },
            { type = "rect", x = 0, y = 88, w = 56, h = 60, color = 0x1A120C, width = 1,
              radius = 0, fill = true, fill_color = 0x1A120C, fill_opacity = 220 },
        })
    end
    local vx = v.x + 12 + 56 + 9
    airui.label({ parent = root, x = vx, y = v.y + 22, w = v.w - 90, h = 20,
        text = "神奇动物在哪里", color = C.text, font_size = 16 })
    airui.label({ parent = root, x = vx, y = v.y + 46, w = v.w - 90, h = 20,
        text = "2016 · 4.5 分", color = C.yellow, font_size = 16 })
    airui.label({ parent = root, x = vx, y = v.y + 70, w = v.w - 90, h = 20,
        text = "4.5 · 133分钟", color = C.sub, font_size = 16 })
    airui.label({ parent = root, x = vx, y = v.y + 94, w = v.w - 90, h = 20,
        text = "奇幻 · 冒险", color = C.dim, font_size = 16 })
    -- 简介 + 续播进度：单个 label 不会自动换行，24 字塞进 116 宽的列只会显示前 7 字
    -- （用户反馈「缺字」）；按 16 号字每行 7 字拆成 4 行
    local INTRO = { "纽特带着一箱", "神奇动物来到", "纽约，意外让", "它们四散逃走" }
    for i, line in ipairs(INTRO) do
        airui.label({ parent = root, x = vx, y = v.y + 122 + (i - 1) * 21,
            w = v.w - 90, h = 22, text = line, color = C.sub, font_size = 16 })
    end

    -- 影视播放进度：卡片"续播"条和详情弹层共用同一份数据（MOCK.video 可用），
    -- 1s 定时器推进 pos，卡片进度条跟着走（原来写死 0.34，用户反馈「进度条不动」）
    local vid = MOCK.video
    if type(vid.pos) ~= "number" then vid.pos = 45 * 60 + 20 end
    local function vhms(s)
        s = math.max(0, math.floor(tonumber(s) or 0))
        return string.format("%02d:%02d:%02d", math.floor(s / 3600),
            math.floor((s % 3600) / 60), s % 60)
    end
    -- 卡片上的「续播」只够放 121px：16 号字下「续播 00:45:20」超出被裁成
    -- 「续播 00:45:」（浅色主题下尤其明显）。这里不到 1 小时就不带小时位
    local function vshort(s)
        s = math.max(0, math.floor(tonumber(s) or 0))
        if s >= 3600 then
            return string.format("%d:%02d:%02d", math.floor(s / 3600),
                math.floor((s % 3600) / 60), s % 60)
        end
        return string.format("%02d:%02d", math.floor(s / 60), s % 60)
    end
    local function vpct()
        local d = tonumber(vid.dur) or 1
        if d <= 0 then d = 1 end
        local p = (tonumber(vid.pos) or 0) / d
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return p
    end
    -- theme.progress 建的时候内部已经 set(0) 了，紧接着再 set(0.34) 是第二次
    -- set_items，在部分固件上会失败并把后面的代码整段带走（右侧三列全黑就是这个）。
    -- 直接传 pct 一次成型，后续只做 set。
    local vbar = theme.progress(root, { x = vx, y = v.y + v.h - 60, w = v.w - 90,
        h = 4, pct = vpct() })
    local vlbl = airui.label({ parent = root, x = vx, y = v.y + v.h - 48,
        w = v.w - 85, h = 22,
        text = "续播 " .. vshort(vid.pos), color = C.sub, font_size = 16 })

    ----------------------------------------------------------------
    -- 影视详情弹层：点击视频卡打开，进度条可拖动（对照 preview.html 的 openVideo）
    ----------------------------------------------------------------
    local hl
    local function vclose()
        if hl then pcall(function() hl:destroy() end) hl = nil end
    end
    local function vopen()
        if hl then return end
        local cw, ch = 620, 380
        local cx = math.floor((W - cw) / 2)
        local cy = math.floor((H - ch) / 2)
        hl = airui.container({ parent = root, x = 0, y = 0, w = W, h = H,
            color = C.bg, color_opacity = 1 })
        airui.container({ parent = hl, x = 0, y = 0, w = W, h = H,
            color = 0x050B14, color_opacity = 160 })
        theme.click(hl, 0, 0, W, H, vclose)
        airui.container({ parent = hl, x = cx, y = cy, w = cw, h = ch,
            color = C.card, radius = 18, border_color = C.line2, border_width = 1 })
        theme.click(hl, cx, cy, cw, ch, function() end, 18)

        -- 关闭 ×
        airui.container({ parent = hl, x = cx + cw - 42, y = cy + 12, w = 26, h = 26,
            color = C.card, radius = 13, border_color = C.line, border_width = 1 })
        airui.shape({ parent = hl, x = cx + cw - 42, y = cy + 12, w = 26, h = 26, items = {
            { type = "line", x1 = 10, y1 = 10, x2 = 16, y2 = 16, color = C.sub, width = 1 },
            { type = "line", x1 = 16, y1 = 10, x2 = 10, y2 = 16, color = C.sub, width = 1 } } })
        theme.click(hl, cx + cw - 46, cy + 8, 34, 34, vclose, 17)

        -- 封面
        airui.container({ parent = hl, x = cx + 24, y = cy + 52, w = 150, h = 200,
            color = 0x2A1B10, radius = 10 })
        theme.shapes(hl, cx + 24, cy + 52, 150, 200, {
            { type = "circle", cx = 75, cy = 44, r = 26, color = 0xE8A54B, width = 1,
              fill = true, fill_color = 0xE8A54B, fill_opacity = 235 },
            { type = "line", x1 = 0, y1 = 200, x2 = 46, y2 = 138, color = 0x3A2317, width = 3 },
            { type = "line", x1 = 46, y1 = 138, x2 = 104, y2 = 200, color = 0x3A2317, width = 3 },
        })

        airui.label({ parent = hl, x = cx + 196, y = cy + 52, w = cw - 240, h = 30,
            text = "神奇动物在哪里", color = C.title, font_size = 22 })
        airui.label({ parent = hl, x = cx + 196, y = cy + 88, w = 160, h = 20,
            text = "2016 · 4.5 分", color = C.yellow, font_size = 16 })
        airui.label({ parent = hl, x = cx + 196, y = cy + 112, w = 200, h = 20,
            text = "133 分钟 · 奇幻 · 冒险", color = C.sub, font_size = 16 })
        airui.label({ parent = hl, x = cx + 196, y = cy + 140, w = cw - 240, h = 44,
            text = "纽特带着神奇动物来到纽约，一场意外让它们四散逃走……",
            color = C.sub, font_size = 16 })

        -- 进度：可拖动 slider + 时间
        -- 踩坑（模块重启根因）：airui.slider 的 on_change 回调参数是 **slider 控件
        -- 本身**，不是数值。之前写成 on_change = function(v) vid.pos = v end，
        -- 把控件句柄存进了 vid.pos，下一次 math.abs(nv - vid.pos) / vid.pos + 1
        -- 做算术就 "attempt to perform arithmetic on a airui.slider (field 'pos')"
        -- → Lua VM exit → reboot。这里按 jq_music_studio 的范式取 self:get_value()，
        -- 并且只有拿到数字才回写。
        local sl, cur_lbl
        pcall(function()
            sl = airui.slider({ parent = hl, x = cx + 196, y = cy + 210, w = 300,
                h = 26, min = 0, max = vid.dur, value = vid.pos,
                style = { bg_color = C.track, bg_opa = 255,
                    indicator_color = C.blue, knob_color = C.knob,
                    radius = 13, pad = 5 },
                on_change = function(self)
                    local v
                    if type(self) == "number" then
                        v = self
                    else
                        pcall(function() v = self:get_value() end)
                        if type(v) ~= "number" then
                            pcall(function() v = sl:get_value() end)
                        end
                    end
                    MOCK.video_seek(v)
                end })
        end)
        if not sl then
            theme.progress(hl, { x = cx + 196, y = cy + 218, w = 300, h = 6 })
            theme.click(hl, cx + 196, cy + 210, 300, 26, function() end)
        end
        -- 宽度要跟滑轨一致（300）：原来是 160，16 号字下
        -- "00:45:29 / 02:13:40" 直接溢出去，尾部被裁成 "02:13:"
        -- 进度条 26 高、旋钮半径 13，文字贴着 y+236 时正好压在旋钮下沿
        -- （用户反馈「时间和进度条重叠」）→ 文字下移到 244，按钮整体跟着挪 8px
        cur_lbl = airui.label({ parent = hl, x = cx + 196, y = cy + 244, w = 300, h = 22,
            text = vhms(vid.pos) .. " / " .. vhms(vid.dur), color = C.dim, font_size = 16 })

        -- 播放 / 暂停（只建一个 label，避免两段文字叠在一起）
        airui.container({ parent = hl, x = cx + 196, y = cy + 276, w = 108, h = 38,
            color = C.blue2, radius = 19 })
        local pbtn_lbl = airui.label({ parent = hl, x = cx + 196, y = cy + 285, w = 108, h = 20,
            text = vid.playing and "暂停" or "播放", color = 0xFFFFFF, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        theme.click(hl, cx + 196, cy + 276, 108, 38, function()
            vid.playing = not vid.playing
            pcall(function()
                pbtn_lbl:set_text(vid.playing and "暂停" or "播放")
            end)
            theme.toast(vid.playing and "继续播放" or "已暂停")
        end, 19)

        -- 加入片单：弹出片单面板（对照 preview.html 的「加入片单」弹窗：
        -- 标题 + 关闭 + 影片名 + 多条片单，右侧「加入 ›」）
        airui.container({ parent = hl, x = cx + 316, y = cy + 276, w = 108, h = 38,
            color = C.deep, radius = 19, border_color = C.line, border_width = 1 })
        airui.label({ parent = hl, x = cx + 316, y = cy + 285, w = 108, h = 20,
            text = "+ 加入片单", color = C.text, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        local PLAYLISTS = { "我的片单", "稍后观看", "科幻精选", "亲子影院", "纪录片频道" }
        local pl
        local function pl_close()
            if pl then pcall(function() pl:destroy() end) pl = nil end
        end
        local function pl_open()
            if pl then return end
            local pw, ph = 420, 348
            local px = math.floor((W - pw) / 2)
            local py = math.floor((H - ph) / 2)
            pl = airui.container({ parent = hl, x = 0, y = 0, w = W, h = H })
            -- 遮罩加厚：原来 130 太透，后面的卡片文字透上来像「两层叠在一起」
            airui.container({ parent = pl, x = 0, y = 0, w = W, h = H,
                color = 0x050B14, color_opacity = 190 })
            theme.click(pl, 0, 0, W, H, pl_close)
            airui.container({ parent = pl, x = px, y = py, w = pw, h = ph,
                color = C.card, radius = 16, border_color = C.line2, border_width = 1 })
            theme.click(pl, px, py, pw, ph, function() end, 16)
            airui.label({ parent = pl, x = px + 20, y = py + 14, w = pw - 80, h = 26,
                text = "加入片单", color = C.title, font_size = 18 })
            -- 关闭 ×
            airui.container({ parent = pl, x = px + pw - 44, y = py + 12, w = 28, h = 28,
                color = C.card, radius = 14, border_color = C.line, border_width = 1 })
            theme.shapes(pl, px + pw - 40, py + 16, 20, 20, {
                { type = "line", x1 = 5, y1 = 5, x2 = 15, y2 = 15, color = C.sub, width = 1 },
                { type = "line", x1 = 15, y1 = 5, x2 = 5, y2 = 15, color = C.sub, width = 1 } })
            theme.click(pl, px + pw - 48, py + 8, 36, 36, pl_close, 18)
            airui.container({ parent = pl, x = px + 20, y = py + 46, w = pw - 40, h = 1,
                color = C.line })
            airui.label({ parent = pl, x = px + 20, y = py + 56, w = pw - 40, h = 22,
                text = "神奇动物在哪里", color = C.text, font_size = 16 })
            for i, name in ipairs(PLAYLISTS) do
                local ly = py + 90 + (i - 1) * 46
                -- 蓝点要和行标题的文字中线对齐：文字 label 从 ly 起、16 号字，
                -- 字形中线约在 ly+8；形状盒 8px、圆心在盒内 (4,4)，
                -- 所以盒子 y 取 ly+4 → 圆心正好 ly+8。
                -- 原来写 ly+10，圆心落到 ly+14，比文字低 6px，看着「点掉在字下面」
                theme.shapes(pl, px + 20, ly + 4, 8, 8, {
                    { type = "circle", cx = 4, cy = 4, r = 3, color = C.blue2, width = 1,
                      fill = true, fill_color = C.blue2, fill_opacity = 255 } })
                airui.label({ parent = pl, x = px + 36, y = ly, w = pw - 150, h = 28,
                    text = name, color = C.text, font_size = 16 })
                -- 「›」(U+203A) 字库里没有，渲出来是个方框，换成半角 >
                airui.label({ parent = pl, x = px + pw - 104, y = ly, w = 80, h = 28,
                    text = "加入 >", color = C.sub, font_size = 16,
                    align = airui.TEXT_ALIGN_RIGHT })
                local pick = name
                theme.click(pl, px + 20, ly - 4, pw - 40, 38, function()
                    pl_close()
                    theme.toast("已加入 " .. pick)
                end, 8)
            end
        end
        theme.click(hl, cx + 316, cy + 268, 108, 38, pl_open, 19)

        -- 播放进度：pos 由 MOCK.video_tick()（页面 1s 刷新）统一推进，
        -- 这里只把最新位置同步到 slider / 时间文字（不要再自己累加，否则双倍速）
        local function vtick()
            if not hl then return end
            local p = tonumber(vid.pos) or 0
            pcall(function()
                if sl then
                    local nv
                    pcall(function() nv = sl:get_value() end)
                    -- 只在手指没在拖（数值与数据差很小）时回写，避免打断拖动
                    if type(nv) ~= "number" or math.abs(nv - p) <= 2 then
                        sl:set_value(p)
                    end
                end
                cur_lbl:set_text(vhms(p) .. " / " .. vhms(vid.dur))
            end)
            sys.timerStart(vtick, 1000)
        end
        sys.timerStart(vtick, 1000)
    end
    theme.click(root, v.x, v.y, v.w, v.h, vopen, 14)

    ----------------------------------------------------------------
    -- 列3：智能语音卡（整列）
    ----------------------------------------------------------------
    local vc = { x = X3, y = GY, w = C3W, h = GH }
    theme.card(root, vc)
    theme.card_head(root, vc, "智能语音", "Midea", C.blue2)
    -- 机器人头像（径向渐变 → 三层圆近似；插画用内容色，不随主题换肤）
    local rcx = vc.x + math.floor(vc.w / 2)
    local rcy = vc.y + 168
    theme.shapes(root, rcx - 42, rcy - 42, 84, 84, {
        { type = "circle", cx = 42, cy = 42, r = 40, color = 0x0A1E48, width = 1,
          fill = true, fill_color = 0x0A1E48, fill_opacity = 255 },
        { type = "circle", cx = 42, cy = 42, r = 33, color = 0x3B8BFF, width = 1,
          fill = true, fill_color = 0x3B8BFF, fill_opacity = 255 },
        { type = "circle", cx = 34, cy = 30, r = 14, color = 0x9FD8FF, width = 1,
          fill = true, fill_color = 0x9FD8FF, fill_opacity = 220 },
        { type = "circle", cx = 42, cy = 42, r = 40, color = 0x78BEFF, width = 1,
          fill = false },
        -- 眼白（svg 里是两个 rx9/ry11 白色椭圆，用圆近似）
        { type = "circle", cx = 31, cy = 38, r = 9, color = 0xEAF6FF, width = 1,
          fill = true, fill_color = 0xEAF6FF, fill_opacity = 240 },
        { type = "circle", cx = 53, cy = 38, r = 9, color = 0xEAF6FF, width = 1,
          fill = true, fill_color = 0xEAF6FF, fill_opacity = 240 },
        { type = "circle", cx = 31, cy = 39, r = 4, color = 0x0C2A5E, width = 1,
          fill = true, fill_color = 0x0C2A5E, fill_opacity = 255 },
        { type = "circle", cx = 53, cy = 39, r = 4, color = 0x0C2A5E, width = 1,
          fill = true, fill_color = 0x0C2A5E, fill_opacity = 255 },
        { type = "line", x1 = 33, y1 = 52, x2 = 37, y2 = 55, color = 0x0C2A5E, width = 2 },
        { type = "line", x1 = 37, y1 = 55, x2 = 42, y2 = 56, color = 0x0C2A5E, width = 2 },
        { type = "line", x1 = 42, y1 = 56, x2 = 47, y2 = 55, color = 0x0C2A5E, width = 2 },
    })
    airui.label({ parent = root, x = vc.x + 12, y = rcy + 62, w = vc.w - 24, h = 20,
        text = "你可以这样说", color = C.sub, font_size = 16,
        align = airui.TEXT_ALIGN_CENTER })
    local asks = { "小迪我想听音乐", "小迪我想看部电影", "小迪调整空调温度" }
    for i, q in ipairs(asks) do
        theme.pill(root, { x = vc.x + 16, y = rcy + 96 + (i - 1) * 56,
            w = vc.w - 32, h = 34, radius = 9 },
            q, { bg = C.sel, color = C.title, border = C.line2 })
    end
    -- 底部「长按方向盘按键唤醒」已按用户要求去掉
    local vbtn = airui.container({ parent = root, x = vc.x, y = vc.y,
        w = vc.w, h = vc.h, color = C.bg, color_opacity = 1, radius = 14 })
    vbtn:set_on_click(function() db(function() go("voice") end) end)

    ----------------------------------------------------------------
    -- 列4：音乐迷你卡（整列）—— 点击层先建，播放控制后建
    ----------------------------------------------------------------
    local mc = { x = X4, y = GY, w = C4W, h = GH }
    theme.card(root, mc)
    theme.card_head(root, mc, "音乐", "更多", C.sub)
    local mbtn = airui.container({ parent = root, x = mc.x, y = mc.y,
        w = mc.w, h = mc.h, color = C.bg, color_opacity = 1, radius = 14 })
    mbtn:set_on_click(function() db(function() go("music") end) end)

    -- 专辑封面：宽度撑满列宽，高度按列高取比例（原来固定 118，整列下方留一大片空白）
    local dh = math.floor(GH * 0.40)
    local disc = { x = mc.x + 10, y = mc.y + 40, w = mc.w - 20, h = dh }
    local cv = MOCK.mu_song().cv_bg
    airui.container({ parent = root, x = disc.x, y = disc.y, w = disc.w, h = disc.h,
        color = cv, radius = 10 })
    -- 封面下缘山形剪影：照 svg 的 path M0 78c26-16……采样成折线，
    -- 顶边有起伏，不再是齐齐一条直线（图元全部落在 disc 画布内）
    local dark = theme.blend(0x000000, cv, 0.35)
    local band = disc.h - math.floor(disc.h * 0.42)
    theme.shapes(root, disc.x, disc.y, disc.w, disc.h, {
        { type = "rect", x = 0, y = band + 6, w = disc.w,
          h = math.max(2, disc.h - band - 6), color = dark, width = 1, radius = 0,
          fill = true, fill_color = dark, fill_opacity = 255 },
    })
    local wave = {}
    local wpts = { { 0, 78 }, { 26, 62 }, { 52, 68 }, { 80, 60 },
                   { 108, 50 }, { 134, 46 }, { 160, 58 } }
    for i = 1, #wpts - 1 do
        local p, q = wpts[i], wpts[i + 1]
        _ln(wave, math.floor(p[1] * disc.w / 160), math.floor(p[2] * disc.h / 126),
                  math.floor(q[1] * disc.w / 160), math.floor(q[2] * disc.h / 126), dark, 5)
    end
    theme.shapes(root, disc.x, disc.y, disc.w, disc.h, wave)
    local mu_cover_txt = airui.label({ parent = root, x = disc.x + 10, y = disc.y + 10,
        w = disc.w - 20, h = 20,
        text = MOCK.mu_song().title, color = C.bright, font_size = 16 })
    local mu_title = airui.label({ parent = root, x = mc.x + 12, y = disc.y + disc.h + 10,
        w = mc.w - 24, h = 22, text = MOCK.mu_song().title, color = C.text, font_size = 17 })
    local mu_artist = airui.label({ parent = root, x = mc.x + 12, y = disc.y + disc.h + 34,
        w = mc.w - 24, h = 20, text = MOCK.mu_song().artist, color = C.sub, font_size = 16 })
    local prog = { x = mc.x + 12, y = disc.y + disc.h + 58, w = mc.w - 24, h = 4 }
    local progbar = theme.progress(root, prog)
    local mu_cur = airui.label({ parent = root, x = mc.x + 12, y = prog.y + 6,
        w = 60, h = 22, text = "00:00", color = C.dim, font_size = 16 })
    -- 总时长必须留引用：自动切歌后 dur 会变，写死的 label 会一直停在上一首的时长
    local mu_dur = airui.label({ parent = root, x = mc.x + mc.w - 72, y = prog.y + 6,
        w = 60, h = 22, text = MOCK.mmss(MOCK.mu_dur()), color = C.dim, font_size = 16,
        align = airui.TEXT_ALIGN_RIGHT })
    -- 歌词预览：3 行滚动 + 当前行高亮。
    -- 单个 label 不会自动换行（超宽直接裁掉），172 宽的列在 16 号字下
    -- 最多放 9 个汉字，所以歌词按 ≤9 字切行，宁可多切几行也不用小字号。
    -- 歌词按当前歌曲取（原来写死《七里香》，切歌后永远不变），
    -- 刷新回调里发现歌变了会重新取并强制重画这 3 行
    local LYRICS = MOCK.mu_lyrics()
    local lyr_song = MOCK.mu_song().title
    local lyric_y = prog.y + 32
    local mu_lyr = {}
    for k = 1, 3 do
        mu_lyr[k] = airui.label({ parent = root, x = mc.x + 12,
            y = lyric_y + (k - 1) * 26, w = mc.w - 20, h = 22,
            text = LYRICS[k], color = k == 1 and C.title or C.dim, font_size = 16 })
    end
    -- 每 5 秒推进一行（除数越小滚得越快）；初值 0 保证首帧就把歌词刷一遍
    local lyr_base = 0
    local function lyr_set(base)
        if base < 1 then base = 1 end
        if base > #LYRICS - 2 then base = math.max(1, #LYRICS - 2) end
        if base == lyr_base then return end
        lyr_base = base
        for k = 1, 3 do
            local t = LYRICS[base + k - 1] or ""
            pcall(function() mu_lyr[k]:set_text(t) end)
            pcall(function() mu_lyr[k]:set_color(k == 1 and C.title or C.dim) end)
        end
    end
    -- 播放控制（上一首 / 播放|暂停 / 下一首）—— 固定在列底部
    -- 卡宽 172、播放键中心在 +86；原来上一首 / 下一首贴在 20 和 132，
    -- 三个键散在整卡两端（用户反馈「离得有点远」）→ 两侧各收到距中心 38px
    local pcy = mc.y + mc.h - 56
    theme.icon(root, mc.x + 38, pcy, 20, "prev", C.icon)
    airui.shape({ parent = root, x = mc.x + math.floor(mc.w / 2) - 18, y = pcy - 8,
        w = 36, h = 36, items = { { type = "circle", cx = 18, cy = 18, r = 17,
        color = C.blue2, width = 1, fill = true, fill_color = C.sel,
        fill_opacity = 255 } } })
    local pp_shp = airui.shape({ parent = root,
        x = mc.x + math.floor(mc.w / 2) - 8, y = pcy + 2, w = 16, h = 16, items = {} })
    local function pp_set(playing)
        if playing then
            pp_shp:set_items({
                { type = "rect", x = 3, y = 2, w = 3, h = 12, color = C.bright,
                  width = 1, radius = 1, fill = true, fill_color = C.bright,
                  fill_opacity = 255 },
                { type = "rect", x = 10, y = 2, w = 3, h = 12, color = C.bright,
                  width = 1, radius = 1, fill = true, fill_color = C.bright,
                  fill_opacity = 255 },
            })
        else
            pp_shp:set_items({
                { type = "line", x1 = 3, y1 = 1, x2 = 14, y2 = 8, color = C.bright, width = 3 },
                { type = "line", x1 = 3, y1 = 15, x2 = 14, y2 = 8, color = C.bright, width = 3 },
                { type = "line", x1 = 3, y1 = 1, x2 = 3, y2 = 15, color = C.bright, width = 3 },
            })
        end
    end
    pp_set(MOCK.music.playing)
    theme.icon(root, mc.x + 114, pcy, 20, "next", C.icon)
    -- 播放控制热区：统一走 theme.click（创建参数 on_click + 长按兜底）。
    -- 原来用 color_opacity=1 的透明容器 + set_on_click，部分固件收不到点击，
    -- 表现就是「播放 / 下一首怎么点都没反应」，所以这里换成 theme.click。
    theme.click(root, mc.x + 30, pcy - 8, 36, 36, function()
        MOCK.mu_prev()
        pp_set(MOCK.music.playing)
    end, 8)
    theme.click(root, mc.x + math.floor(mc.w / 2) - 18, pcy - 8, 36, 36, function()
        MOCK.mu_toggle()
        pp_set(MOCK.music.playing)      -- 立刻切图标，不等 1.5s 刷新
    end, 18)
    theme.click(root, mc.x + 106, pcy - 8, 36, 36, function()
        MOCK.mu_next()
        pp_set(MOCK.music.playing)
    end, 8)

    ----------------------------------------------------------------
    -- 列5：地图迷你卡（整列）
    ----------------------------------------------------------------
    local mp = { x = X5, y = GY, w = C5W, h = GH }
    theme.card(root, mp, { hi = false })
    -- 地图底：深蓝底 + 格网 + 主干道
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, {
        { type = "rect", x = 0, y = 0, w = mp.w - 2, h = mp.h - 2,
          color = C.page, width = 1, radius = 14,
          fill = true, fill_color = 0x07131F, fill_opacity = 255 },
    })
    -- 地图图元坐标一律夹到画布内（越界会被画到画布外，表现为巨大色块 + 容器滚动）
    local function mpc(x, y)
        if x < 1 then x = 1 elseif x > mp.w - 2 then x = mp.w - 2 end
        if y < 1 then y = 1 elseif y > mp.h - 2 then y = mp.h - 2 end
        return math.floor(x), math.floor(y)
    end
    local function ML(items, x1, y1, x2, y2, col, wid)
        local a, b = mpc(x1, y1)
        local c, d = mpc(x2, y2)
        _ln(items, a, b, c, d, col, wid)
    end
    -- 严格照 preview.html 里 <svg viewBox="0 0 200 536"> 的坐标换算
    local fxm, fym = mp.w / 200, mp.h / 536
    local function SM(x, y) return mpc(x * fxm, y * fym) end
    local function SL(items, x1, y1, x2, y2, col, wid)
        local a, b = SM(x1, y1)
        local c, d = SM(x2, y2)
        _ln(items, a, b, c, d, col, wid)
    end
    -- 细路网（#123A5E / 1px / .55）
    local road = {}
    for _, l in ipairs({ { -20, 420, 220, 250 }, { -20, 320, 220, 150 },
                          { -20, 220, 220, 50 },  { 40, 560, 40, 0 },
                          { 120, 560, 120, 0 },   { -20, 520, 220, 350 } }) do
        SL(road, l[1], l[2], l[3], l[4], 0x123A5E, 1)
    end
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, road)
    -- 主干道（#1B4E78 / 3px / .7）
    local main = {}
    for _, l in ipairs({ { -10, 470, 210, 300 }, { 20, 560, 20, 40 } }) do
        SL(main, l[1], l[2], l[3], l[4], 0x1B4E78, 3)
    end
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, main)
    -- 路线：60,640 → 60,300 → 150,190 → 150,60，青→蓝渐变分三段近似
    local rt = {}
    for _, s in ipairs({ { 60, 640, 60, 300, 0.00, 0.35 },
                         { 60, 300, 150, 190, 0.35, 0.75 },
                         { 150, 190, 150, 60, 0.75, 1.00 } }) do
        SL(rt, s[1], s[2], s[3], s[4], theme.blend(0x35D6E8, 0x2E7DFF, s[6]), 6)
    end
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, rt)
    -- 定位点（#062033 底 + #35D6E8 环）+ 终点（#2E7DFF 光晕 + #EAF4FF 心）
    local ax, ay = SM(60, 300)
    local bx, by = SM(150, 190)
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, {
        { type = "circle", cx = ax, cy = ay, r = 7, color = 0x35D6E8, width = 3,
          fill = true, fill_color = 0x062033, fill_opacity = 255 },
        { type = "circle", cx = bx, cy = by, r = 11, color = 0x2E7DFF, width = 1,
          fill = true, fill_color = 0x2E7DFF, fill_opacity = 90 },
        { type = "circle", cx = bx, cy = by, r = 5, color = 0xEAF4FF, width = 1,
          fill = true, fill_color = 0xEAF4FF, fill_opacity = 255 },
    })
    -- 顶部转向提示（20 的图标居中于 38 的方块：偏移 9 = (38-20)/2）
    theme.pill(root, { x = mp.x + 12, y = mp.y + 12, w = 38, h = 38, radius = 10 },
        "", { bg = C.sel })
    theme.icon(root, mp.x + 21, mp.y + 21, 20, "left", C.bright)
    airui.label({ parent = root, x = mp.x + 58, y = mp.y + 12, w = mp.w - 70, h = 26,
        text = "300m", color = 0xFFFFFF, font_size = 22 })
    airui.label({ parent = root, x = mp.x + 58, y = mp.y + 40, w = mp.w - 70, h = 20,
        text = "向左转", color = C.sub, font_size = 16 })
    -- 底部目的地：16 号字在 166 宽的列里「1.2公里 所需时间8分钟」放不下一行，
    -- 原来 h=20 直接把换行后的第二行裁掉了。给足两行高度，并整体上移。
    airui.label({ parent = root, x = mp.x + 12, y = mp.y + mp.h - 78, w = mp.w - 24, h = 22,
        text = "当前目的地：西湖", color = C.name, font_size = 16 })
    airui.label({ parent = root, x = mp.x + 12, y = mp.y + mp.h - 54, w = mp.w - 24, h = 44,
        text = "1.2公里 所需时间8分钟", color = C.sub, font_size = 16 })
    local mbtn2 = airui.container({ parent = root, x = mp.x, y = mp.y,
        w = mp.w, h = mp.h, color = C.bg, color_opacity = 1, radius = 14 })
    mbtn2:set_on_click(function() db(function() go("nav") end) end)

    ----------------------------------------------------------------
    -- 1s 刷新：音乐进度 / 标题 / 播放图标 / 歌词滚动 / 拨盘温度
    ----------------------------------------------------------------
    return function()
        MOCK.mu_tick()
        -- 每一项单独 pcall：原来整块共用一个 pcall，中间任何一句抛错
        -- （例如 pp_set / progbar）都会把后面的歌词滚动一起带停，
        -- 表现就是「进度条在走、歌词永远不动」
        local s = MOCK.mu_song()
        pcall(function() mu_title:set_text(s.title) end)
        pcall(function() mu_artist:set_text(s.artist) end)
        pcall(function() mu_cover_txt:set_text(s.title) end)
        pcall(function() mu_cur:set_text(MOCK.mmss(MOCK.music.pos)) end)
        pcall(function() mu_dur:set_text(MOCK.mmss(MOCK.mu_dur())) end)
        pcall(function() progbar:set(MOCK.music.pos / math.max(1, MOCK.mu_dur())) end)
        pcall(function() pp_set(MOCK.music.playing) end)
        -- 影视续播：模拟数据推进 + 卡片进度条/文字跟着走（原来写死 0.34）
        pcall(function() MOCK.video_tick() end)
        pcall(function() vbar:set(vpct()) end)
        pcall(function() vlbl:set_text("续播 " .. vshort(vid.pos)) end)
        -- 切歌后歌词跟着换：重取歌词、清掉 lyr_base 强制把 3 行重画一遍
        -- （原来的常量歌词不随歌曲变，用户切歌后看到的还是上一首的歌词）
        if s.title ~= lyr_song then
            lyr_song = s.title
            LYRICS = MOCK.mu_lyrics()
            lyr_base = 0
        end
        -- 歌词每 4 秒推进一行，走完一轮回到开头（窗口数 = 行数 - 2）
        local nwin = math.max(1, #LYRICS - 2)
        lyr_set(math.floor(MOCK.music.pos / 4) % nwin + 1)
        pcall(function() ac_temp_lbl:set_text(tostring(MOCK.ac.t.l)) end)
    end
end)
