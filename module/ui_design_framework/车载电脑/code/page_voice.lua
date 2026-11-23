--[[
@module page_voice
@summary 智能语音助手（布局对齐 preview.html 的 #voice 页）
顶部球体 → 小灰字提示 → 对话流（助手左 / 用户右，助手气泡内可带操作按钮）
→ 建议 chips 一排 → 麦克风圆钮
回复文案与 preview.html 的 VREPLY 一致。
]]
local theme = require "theme"

local W, H = theme.W, theme.H

-- 建议指令（与 preview.html 的 vchips 一致）
local CHIPS = { "小迪我想听音乐", "小迪导航去公司", "把空调调到24度",
                "今天天气怎么样", "我想看部电影" }

-- 回复库（与 preview.html 的 VREPLY 一致）
local REPLY = {
    ["小迪我想听音乐"] = { "好的，为你播放「清新歌单」，共 4 首。",
        acts = { { "去音乐页", "music" }, { "换一首", "reroll" } } },
    ["小迪导航去公司"] = { "好的，已为你规划去公司的路线，全程 12.4 公里，约 24 分钟。",
        acts = { { "去导航页", "nav" } } },
    ["把空调调到24度"] = { "空调已调到 24 度，风量 2 档，副驾同步。",
        acts = { { "去空调页", "ac" } } },
    ["今天天气怎么样"] = { "杭州西湖区 27 度小雨，晚高峰有零星阵雨，记得开雾灯。",
        acts = { { "看天气", "weather" } } },
    -- 别用「›」(U+203A)：字库没有这个码位，屏上会渲染成方框
    ["我想看部电影"] = { "找到 3 部适合的车内短片，已在「游戏中心 · 影院」等候。" },
}
local DEFAULT_REPLY = { "我不太确定你的意思，可以说「放首歌」或「调空调」。" }

theme.make_page("voice", function(root, M)
    local C = theme.C
    local cx = math.floor(W / 2)

    -- 顶栏：左上角是页面名（与 HTML 一致，不放返回箭头），右上角圆钮回主页
    theme.topbar(root, "back", false, false, false, "智能语音")

    ------------------------------------------------------------------
    -- 球体（外圈细描边 + 蓝色渐变球 + 两个高光）
    ------------------------------------------------------------------
    local by, br = 58, 58
    airui.shape({ parent = root, x = cx - br - 6, y = by - 6,
        w = (br + 6) * 2, h = (br + 6) * 2, items = {
        { type = "circle", cx = br + 6, cy = br + 6, r = br + 4,
          color = C.line2, width = 1 },
        { type = "circle", cx = br + 6, cy = br + 6, r = br,
          color = C.blue2, width = 1, fill = true, fill_color = C.blue2, fill_opacity = 255 },
        { type = "circle", cx = br + 6, cy = br + 6, r = br - 10,
          color = 0x1B4FA8, width = 1, fill = true, fill_color = 0x1B4FA8,
          fill_opacity = 255 },
        { type = "circle", cx = br - 6, cy = br - 8, r = 16,
          color = 0xC9DEFA, width = 1, fill = true, fill_color = 0xC9DEFA,
          fill_opacity = 140 },
        { type = "circle", cx = br + 20, cy = br + 24, r = 7,
          color = 0xC9DEFA, width = 1, fill = true, fill_color = 0xC9DEFA,
          fill_opacity = 110 } } })

    ------------------------------------------------------------------
    -- 提示小字
    ------------------------------------------------------------------
    airui.label({ parent = root, x = cx - 300, y = by + 2 * br + 16, w = 600, h = 22,
        text = "说出你的需求，或点下面的建议", color = C.dim, font_size = 16,
        align = airui.TEXT_ALIGN_CENTER })

    ------------------------------------------------------------------
    -- 对话流：助手消息左对齐、用户消息右对齐；最多保留最近 3 条
    ------------------------------------------------------------------
    local mv = { { role = "a",
        text = "你好，我是小迪。可以让我放歌、导航、调空调，也能查天气。" } }
    local msgbox
    local MY = 214                       -- 对话区顶部
    local ML, MR = 64, 960               -- 对话区左右边界
    local MAXW = 560                     -- 气泡最大宽度

    local function nchars(s)
        local ok, n = pcall(utf8.len, s)
        if ok and n then return n end
        return #s
    end

    local function redraw_msgs()
        if msgbox then
            pcall(function() msgbox:destroy() end)
            msgbox = nil
        end
        msgbox = airui.container({ parent = root, x = 0, y = MY, w = W, h = 260,
            color = C.bg, color_opacity = 1 })
        -- 对话从顶部往下排（气泡在上方，不再吊在底部），
        -- 且气泡高度按实际行数算：原来固定 46 高 + h=24 的单行 label，
        -- 长句折行后第二行直接被裁掉（表现为「字没显示完」）。
        local y = 8
        for _, m in ipairs(mv) do
            local cw_per = 17                    -- 16 号中文实际宽度约 17px
            local tw = nchars(m.text) * cw_per + 30
            if tw > MAXW then tw = MAXW end
            if tw < 130 then tw = 130 end
            local inner = tw - 30
            local lines = math.max(1, math.ceil(nchars(m.text) * cw_per / inner))
            local th = lines * 22 + 12           -- 文字块高度
            local bh = th + 10 + (m.acts and 40 or 0)
            local bx
            if m.role == "a" then
                bx = ML
            else
                bx = MR - tw
            end
            airui.container({ parent = msgbox, x = bx, y = y, w = tw, h = bh,
                radius = 14,
                color = (m.role == "a") and C.card2 or C.blue2,
                border_color = (m.role == "a") and C.line2 or C.blue2, border_width = 1 })
            airui.label({ parent = msgbox, x = bx + 15, y = y + 9, w = inner, h = th,
                text = m.text, color = (m.role == "a") and C.text or 0xFFFFFF,
                font_size = 16 })
            if m.acts then
                local ax = bx + 15
                -- 原来按钮宽 = 字数*16 + 22、高 30，四周留白太多，屏上「换一首」
                -- 只有一小条字、外面一个大方框（用户反馈「方框太大了」）。
                -- 收成 字数*17 + 10、高 26，正好包住文字。
                local bh2 = 26
                local by2 = y + th + 12
                for _, a in ipairs(m.acts) do
                    local aw = nchars(a[1]) * 17 + 10
                    airui.container({ parent = msgbox, x = ax, y = by2, w = aw, h = bh2,
                        color = C.deep, radius = 8, border_color = C.blue2, border_width = 1 })
                    airui.label({ parent = msgbox, x = ax, y = by2 + 3, w = aw, h = 20,
                        text = a[1], color = C.blue2, font_size = 16,
                        align = airui.TEXT_ALIGN_CENTER })
                    local dest = a[2]
                    theme.click(msgbox, ax, by2, aw, bh2, function()
                        if dest == "reroll" then
                            push("换一首", { "已为你换成下一首「星河」，共 4 首。",
                                acts = { { "去音乐页", "music" } } })
                        else
                            theme.go_defer(dest)
                        end
                    end, 8)
                    ax = ax + aw + 10
                end
            end
            y = y + bh + 12
        end
    end

    function push(say, reply)
        mv[#mv + 1] = { role = "u", text = say }
        mv[#mv + 1] = { role = "a", text = reply[1], acts = reply.acts }
        while #mv > 3 do table.remove(mv, 1) end
        redraw_msgs()
    end

    local function ask(say)
        push(say, REPLY[say] or DEFAULT_REPLY)
    end

    redraw_msgs()

    ------------------------------------------------------------------
    -- 建议 chips（一排居中）
    ------------------------------------------------------------------
    local gap = 10
    local total = 0
    for _, s in ipairs(CHIPS) do total = total + nchars(s) * 16 + 28 + gap end
    total = total - gap
    local x = math.floor((W - total) / 2)
    local cy2 = H - 122
    for _, s in ipairs(CHIPS) do
        local cw = nchars(s) * 16 + 28
        airui.container({ parent = root, x = x, y = cy2, w = cw, h = 32,
            color = C.card2, radius = 16, border_color = C.line2, border_width = 1 })
        airui.label({ parent = root, x = x, y = cy2 + 6, w = cw, h = 20,
            text = s, color = C.text, font_size = 16, align = airui.TEXT_ALIGN_CENTER })
        theme.click(root, x, cy2, cw, 32, function() ask(s) end, 16)
        x = x + cw + gap
    end

    ------------------------------------------------------------------
    -- 麦克风圆钮：点一次模拟朗读下一条建议
    ------------------------------------------------------------------
    local mic_y = cy2 + 40
    airui.shape({ parent = root, x = cx - 24, y = mic_y, w = 48, h = 48, items = {
        { type = "circle", cx = 24, cy = 24, r = 23, color = C.blue2, width = 1,
          fill = true, fill_color = C.blue2, fill_opacity = 255 } } })
    -- 48×48 圆里放 20px 图标：上下各留 14 才是正中。
    -- 原来 +11（偏上 3px），而且 mic 图形的墨迹中心比画布中心高 1.4px，
    -- 所以取 +15 让视觉重心落在圆心（用户反馈「麦克风没在圆圈正中间」）。
    theme.icon(root, cx - 10, mic_y + 15, 20, "mic", 0xFFFFFF)
    local mi = 0
    theme.click(root, cx - 24, mic_y, 48, 48, function()
        mi = mi % #CHIPS + 1
        ask(CHIPS[mi])
    end, 24)
end)
