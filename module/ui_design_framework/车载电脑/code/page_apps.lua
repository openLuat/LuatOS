--[[
@module page_apps
@summary 全部应用宫格：5 列 × 3 行，94×94 圆角 22 图标 + 名称
布局与 preview.html 对应：apps-page padding 4/26/14，列距 8 行距 30

15 个入口全部可点（与 preview.html 的 appOpen() 行为一致）：
  智能语音 → voice 页；最美天气 → weather 页
  其余 → 居中弹层（遮罩 + 卡片 + 标题 + × + 内容），弹层内按钮也可点，
         并支持子视图（相册大图、用户手册章节、充电开始/停止）
弹层关闭键 × 与「← 返回」都只关弹层；右上角是「回主页」圆钮。
]]
local theme = require "theme"
require "mock"   -- 全局 MOCK：与 theme/page_weather/page_music 保持一致（mock.lua 不 return，依赖全局表）
local S = {}

-- hb: { txt, box, backbar, bigbtn, rowitem, note, stage, state, redraw, open, close }
function S.build(theme, hb)
    local C = theme.C
    local txt, box, backbar = hb.txt, hb.box, hb.backbar
    local bigbtn, rowitem, note, stage = hb.bigbtn, hb.rowitem, hb.note, hb.stage
    local sv, redraw, open = hb.state, hb.redraw, hb.open
    local T = {}

    ---------------------------------------------------------------- 相机
    T.camera = { w = 520, h = 470, title = "相机", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local sy = by + 38
        stage(p, bx, sy, bw, 250, { sun = true, badge = "行车中",
            tag = "F1.8 · 1/120s · ISO 200" })
        local ry = sy + 264
        box(p, bx + 24, ry + 8, 96, 44, C.deep, 10, C.line2, 1)
        txt(p, bx + 24, ry + 20, 96, 22, "切换镜头", C.text, 16, airui.TEXT_ALIGN_CENTER)
        theme.click(p, bx + 24, ry + 8, 96, 44, function()
            theme.toast("已切换至前视摄像头")
        end, 10)
        -- 快门
        local mx = bx + math.floor(bw / 2)
        airui.container({ parent = p, x = mx - 26, y = ry, w = 52, h = 52,
            color = C.sel_str, radius = 26, border_color = C.blue2, border_width = 2 })
        airui.container({ parent = p, x = mx - 16, y = ry + 10, w = 32, h = 32,
            color = C.card, radius = 16 })
        theme.click(p, mx - 26, ry, 52, 52, function()
            sv.pics = (sv.pics or 0) + 1
            theme.toast("已拍摄 1 张 · 自动存入相册")
            redraw()
        end, 26)
        box(p, bx + bw - 120, ry + 8, 96, 44, C.deep, 10, C.line2, 1)
        txt(p, bx + bw - 120, ry + 20, 96, 22, "相册", C.text, 16, airui.TEXT_ALIGN_CENTER)
        theme.click(p, bx + bw - 120, ry + 8, 96, 44, function() open("album") end, 10)
        note(p, bx, ry + 70, bw, "已拍摄 " .. tostring(sv.pics or 0) .. " 张 · 自动存入相册")
    end }

    ---------------------------------------------------------- 车辆全景影像
    T.surround = { w = 560, h = 520, title = "车辆全景影像", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local sy = by + 38
        stage(p, bx, sy, bw, 240, { ring = true })
        txt(p, bx + 10, sy + 104, 80, 20, "左视角", 0x9FB3C8, 16)
        txt(p, bx + bw - 90, sy + 104, 80, 20, "右视角", 0x9FB3C8, 16, airui.TEXT_ALIGN_RIGHT)
        txt(p, bx, sy + 192, bw, 20, "后视角", 0x9FB3C8, 16, airui.TEXT_ALIGN_CENTER)
        local names = { "前视角", "后视角", "左视角", "右视角", "3D 环视", "透明底盘" }
        local tw = math.floor((bw - 20) / 3)
        for i, nm in ipairs(names) do
            local tx = bx + ((i - 1) % 3) * (tw + 10)
            local ty = sy + 252 + math.floor((i - 1) / 3) * 74
            box(p, tx, ty, tw, 64, C.deep, 12, C.line2, 1)
            txt(p, tx, ty + 21, tw, 24, nm, C.text, 16, airui.TEXT_ALIGN_CENTER)
            theme.click(p, tx, ty, tw, 64, function() theme.toast("已切换：" .. nm) end, 12)
        end
    end }

    ---------------------------------------------------------------- 相册
    T.album = { w = 560, h = 340, title = "相册", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local gy = by + 38
        local gw = math.floor((bw - 20) / 3)
        local cs = { 0x1E3A8A, 0x0E4A3A, 0x5A2A0E, 0x2A1060, 0x0B2E4F, 0x4A1020 }
        for i = 1, 6 do
            local px1 = bx + ((i - 1) % 3) * (gw + 10)
            local py1 = gy + math.floor((i - 1) / 3) * 98
            airui.container({ parent = p, x = px1, y = py1, w = gw, h = 88,
                color = cs[i], radius = 10, border_color = C.line2, border_width = 1 })
            theme.icon(p, px1 + math.floor(gw / 2) - 16, py1 + 26, 32, "photo", 0xBFD3EC)
            theme.click(p, px1, py1, gw, 88, function() open("photo") end, 10)
        end
        note(p, bx, gy + 200, bw, "行车相机 · 6 张照片 · 点击查看大图")
    end }

    T.photo = { w = 560, h = 430, title = "照片预览", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local py1 = by + 38
        airui.container({ parent = p, x = bx, y = py1, w = bw, h = 250,
            color = 0x1E3A8A, radius = 12, border_color = C.line2, border_width = 1 })
        theme.icon(p, bx + math.floor(bw / 2) - 30, py1 + 96, 60, "photo", 0xBFD3EC)
        note(p, bx, py1 + 264, bw, "行车相机 · 2026-11-17 18:42 · 前视摄像头")
    end }

    ------------------------------------------------------------ 后排屏中心
    T.rear = { w = 520, h = 430, title = "后排屏中心", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local py1 = by + 38
        local pw = math.floor((bw - 12) / 2)
        for i = 1, 2 do
            local px1 = bx + (i - 1) * (pw + 12)
            box(p, px1, py1, pw, 128, C.deep, 12, C.line2, 1)
            txt(p, px1 + 14, py1 + 12, pw - 28, 24, i == 1 and "左后屏" or "右后屏", C.title, 17)
            txt(p, px1 + 14, py1 + 38, pw - 28, 22,
                i == 1 and "正在播放 · 儿歌串烧" or "正在播放 · 动画片", C.sub, 16)
            local key = i == 1 and "rear_l" or "rear_r"
            local paused = sv[key] == true
            box(p, px1 + 14, py1 + 70, pw - 28, 40, paused and C.deep or C.sel_str, 8,
                C.line2, 1)
            txt(p, px1 + 14, py1 + 80, pw - 28, 22, paused and "继续" or "暂停",
                C.blue2, 16, airui.TEXT_ALIGN_CENTER)
            theme.click(p, px1 + 14, py1 + 70, pw - 28, 40, function()
                sv[key] = not paused
                redraw()
            end, 8)
        end
        local ry = py1 + 140
        rowitem(p, bx, ry, bw, "儿童锁", sv.childlock and "已开启" or "已关闭", function()
            sv.childlock = not sv.childlock
            theme.toast(sv.childlock and "儿童锁已开启" or "儿童锁已关闭")
            redraw()
        end, sv.childlock and C.blue2 or C.dim)
        rowitem(p, bx, ry + 52, bw, "音量联动", "随主驾 ±5", function()
            theme.toast("音量联动：随主驾 ±5")
        end)
        bigbtn(p, bx, ry + 104, bw, "切换儿童锁", function()
            sv.childlock = not sv.childlock
            theme.toast(sv.childlock and "儿童锁已开启" or "儿童锁已关闭")
            redraw()
        end, sv.childlock)
    end }

    ------------------------------------------------------------ 智慧充电
    T.charge = { w = 460, h = 470, title = "智慧充电", draw = function(p, bx, by, bw)
        local on = sv.charging == true
        -- 电量圆环（粗描边圆）
        airui.container({ parent = p, x = bx, y = by, w = 96, h = 96, color = C.deep,
            radius = 48, border_color = on and C.blue2 or C.line2, border_width = 10 })
        local pct0 = sv.pct or 0.75
        local pct_s = math.floor(pct0 * 100 + 0.5) .. "%"
        sv._pct1 = airui.label({ parent = p, x = bx + 12, y = by + 52, w = 72, h = 26,
            text = pct_s, color = C.title, font_size = 18, align = airui.TEXT_ALIGN_CENTER })
        sv._pct2 = airui.label({ parent = p, x = bx + 112, y = by + 8, w = bw - 112, h = 34,
            text = pct_s, color = C.title, font_size = 26 })
        txt(p, bx + 112, by + 48, bw - 112, 22,
            on and "正在充电 · 60 kW" or "已插枪 · 待开始",
            on and C.green or C.sub, 16)
        -- 进度对象存到 sv，由 1.5s 刷新回调推进（模拟充电）
        sv._prog = theme.progress(p, { x = bx + 112, y = by + 76, w = bw - 112, h = 6,
            pct = on and pct0 or 0.0 })

        local ry = by + 112
        local hw = math.floor((bw - 12) / 2)
        box(p, bx, ry, hw, 48, on and C.deep or C.sel_str, 10,
            on and C.line2 or C.blue2, 1)
        txt(p, bx, ry + 12, hw, 24, "开始充电", on and C.text or C.blue2, 16,
            airui.TEXT_ALIGN_CENTER)
        theme.click(p, bx, ry, hw, 48, function()
            if sv.charging then theme.toast("已经在充电了") return end
            sv.charging = true
            theme.toast("已开始充电")
            redraw()
        end, 10)
        box(p, bx + hw + 12, ry, hw, 48, on and C.sel_str or C.deep, 10,
            on and C.blue2 or C.line2, 1)
        txt(p, bx + hw + 12, ry + 12, hw, 24, "停止充电", on and C.blue2 or C.text, 16,
            airui.TEXT_ALIGN_CENTER)
        theme.click(p, bx + hw + 12, ry, hw, 48, function()
            if not sv.charging then theme.toast("当前未充电") return end
            sv.charging = false
            theme.toast("已停止充电")
            redraw()
        end, 10)

        local rows = { { "充电功率", "60 kW", C.text },
                       { "预计充满", "40 分钟", C.text },
                       { "电池温度", "28℃（正常）", C.text },
                       { "当前电价", "0.68 元 / 度（谷时）", C.blue2 } }
        for i, r in ipairs(rows) do
            rowitem(p, bx, ry + 60 + (i - 1) * 52, bw, r[1], r[2], nil, r[3])
        end
    end }

    ------------------------------------------------------------ 哨兵模式
    T.sentinel = { w = 520, h = 480, title = "哨兵模式", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local sy = by + 38
        stage(p, bx, sy, bw, 200, { badge = sv.sentinel and "监控中" or "已关闭" })
        local ry = sy + 212
        rowitem(p, bx, ry, bw, "哨兵状态", sv.sentinel and "监控中" or "已关闭",
            nil, sv.sentinel and C.green or C.dim)
        bigbtn(p, bx, ry + 52, bw, "切换开关", function()
            sv.sentinel = not sv.sentinel
            theme.toast(sv.sentinel and "哨兵模式已开启" or "哨兵模式已关闭")
            redraw()
        end, sv.sentinel)
        rowitem(p, bx, ry + 112, bw, "最近事件", sv.sentinel and "车辆震动 · 1 分钟前" or "暂无",
            nil, C.dim)
    end }

    ---------------------------------------------------------- 行车记录仪
    T.dashcam = { w = 520, h = 460, title = "行车记录仪", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local sy = by + 38
        stage(p, bx, sy, bw, 190, { arrow = true, badge = "录像中" })
        local list = { { "今天 18:42", "02:30" }, { "今天 17:05", "03:12" },
                       { "昨天 21:30", "01:48" } }
        for i, it in ipairs(list) do
            local ry = sy + 202 + (i - 1) * 52
            -- 圆点要对齐文字行（文字块 y=ry+8 高 22，行中心 ry+19）
            airui.shape({ parent = p, x = bx + 2, y = ry + 12, w = 10, h = 14, items = {
                { type = "circle", cx = 5, cy = 7, r = 3, color = C.blue2, width = 1,
                  fill = true, fill_color = C.blue2 } } })
            txt(p, bx + 14, ry + 8, 220, 22, it[1], C.text, 16)
            txt(p, bx + bw - 90, ry + 8, 90, 22, it[2], C.sub, 16, airui.TEXT_ALIGN_RIGHT)
            theme.click(p, bx, ry, bw, 40, function()
                theme.toast("正在播放：" .. it[1])
            end, 6)
        end
    end }

    ------------------------------------------------------------ 游戏中心
    T.games = { w = 520, h = 250, title = "游戏中心", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local gy = by + 38
        local gw = math.floor((bw - 20) / 3)
        local gs = { { "极速狂飙", 0x8C1024 }, { "停车大师", 0x123C8A }, { "音浪冲浪", 0x0B4A3A } }
        for i, g in ipairs(gs) do
            local gx = bx + (i - 1) * (gw + 10)
            airui.container({ parent = p, x = gx, y = gy, w = gw, h = 96,
                color = g[2], radius = 12, border_color = C.line2, border_width = 1 })
            theme.icon(p, gx + math.floor(gw / 2) - 14, gy + 18, 28, "gamepad", 0xE6EEF8)
            txt(p, gx, gy + 58, gw, 22, g[1], 0xE6EEF8, 16, airui.TEXT_ALIGN_CENTER)
            theme.click(p, gx, gy, gw, 96, function()
                theme.toast("仅支持驻车状态下游玩：" .. g[1])
            end, 12)
        end
        note(p, bx, gy + 108, bw, "仅支持驻车状态下游玩，行车中会自动暂停")
    end }

    ------------------------------------------------------------ 用户手册
    local CHAPTERS = {
        { "快速入门", "长按方向盘语音键可唤醒小迪；主屏底部 dock 常驻空调与音量入口。" },
        { "空调与座椅", "双区温度独立调节，长按座椅图标可切换通风/加热。" },
        { "充电说明", "支持快充与家充，谷时电价更省；建议保持电量 20%~80%。" },
        { "安全辅助", "车道保持与自动紧急制动默认开启，可在车辆设置中调整灵敏度。" },
    }
    T.manual = { w = 520, h = 340, title = "用户手册", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local ly = by + 38
        for i, ch in ipairs(CHAPTERS) do
            local ry = ly + (i - 1) * 52
            box(p, bx, ry, bw, 44, C.deep, 10, C.line, 1)
            airui.shape({ parent = p, x = bx + 14, y = ry + 16, w = 12, h = 12, items = {
                { type = "rect", x = 0, y = 0, w = 10, h = 10, color = C.blue2, width = 1,
                  fill = true, fill_color = C.blue2, fill_opacity = 255 } } })
            txt(p, bx + 34, ry + 11, bw - 80, 22, ch[1], C.text, 16)
            theme.icon(p, bx + bw - 26, ry + 15, 14, "right", C.dim)
            theme.click(p, bx, ry, bw, 44, function() open("manual_ch", i) end, 10)
        end
        note(p, bx, ly + 212, bw, "共 4 个章节 · 支持离线查看")
    end }

    T.manual_ch = { w = 520, h = 240,
        title = function(st)
            local ch = CHAPTERS[st.arg or 1]
            return ch and ch[1] or "章节"
        end,
        draw = function(p, bx, by, bw)
        local idx = sv.arg or 1
        local ch = CHAPTERS[idx] or CHAPTERS[1]
        backbar(p, bx, by)
        txt(p, bx, by + 38, bw, 44, ch[2], C.sub, 16)
        bigbtn(p, bx, by + 92, bw, "← 返回目录", function() open("manual") end)
    end }

    ------------------------------------------------------------ 极速模式
    T.boost = { w = 480, h = 300, title = "极速模式", draw = function(p, bx, by, bw)
        local on = MOCK.boost.on == true
        local d = MOCK.boost_data()
        local mw = math.floor((bw - 20) / 3)
        local ms = { { string.format("%.1f", d.acc), "0-100km/h（秒）" },
                     { tostring(d.vmax), "最高时速（km/h）" },
                     { tostring(d.kw), "最大功率（kW）" } }
        for i, m in ipairs(ms) do
            local mx = bx + (i - 1) * (mw + 10)
            box(p, mx, by, mw, 66, C.deep, 12, C.line, 1)
            txt(p, mx, by + 10, mw, 28, m[1], C.blue2, 22, airui.TEXT_ALIGN_CENTER)
            txt(p, mx, by + 40, mw, 20, m[2], C.dim, 16, airui.TEXT_ALIGN_CENTER)
        end
        local ry = by + 78
        rowitem(p, bx, ry, bw, "弹射起步", on and "已开启" or "未开启",
            nil, on and C.green or C.dim)
        bigbtn(p, bx, ry + 56, bw, on and "关闭极速模式" or "开启极速模式", function()
            MOCK.boost.on = not on
            theme.toast(MOCK.boost.on and "极速模式已开启" or "极速模式已关闭")
            redraw()
        end, on)
        note(p, bx, ry + 118, bw, "开启后动力响应更激进，能耗会明显上升，建议在封闭场地使用。")
    end }

    ---------------------------------------------------------------- 下载
    T.download = { w = 520, h = 340, title = "下载", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local dy = by + 38
        -- 用模拟数据驱动：sv.dl 保存三条下载的实时进度，502ms 定时器推进，
        -- 弹层里的进度条和百分比跟着动（原来全是写死常量，用户反馈「不动」）
        if type(sv.dl) ~= "table" then sv.dl = { 0.68, 1.00, 0.42 } end
        sv.dlh = {}
        -- 100% 那条已经下完，保持不动；另两条每次 +0.6% 慢慢走
        local list = { { "高德地图车机版", "1.2 GB", "暂停", 1 },
                       { "车载音乐曲库包", "860 MB", "安装", nil },
                       { "行车记录仪固件", "46 MB", "暂停", 1 } }
        for i, it in ipairs(list) do
            local ry = dy + (i - 1) * 64
            local pct = tonumber(sv.dl[i]) or 0
            txt(p, bx, ry, bw - 90, 22, it[1], C.text, 16)
            local pl = txt(p, bx + bw - 90, ry, 90, 22,
                math.floor(pct * 100) .. "%", C.sub, 16, airui.TEXT_ALIGN_RIGHT)
            local bar = theme.progress(p, { x = bx, y = ry + 28, w = bw, h = 5, pct = pct,
                color = C.blue2 })
            txt(p, bx, ry + 40, 120, 20, it[2], C.dim, 16)
            local act = it[3]
            txt(p, bx + bw - 90, ry + 40, 90, 20, act, C.blue2, 16, airui.TEXT_ALIGN_RIGHT)
            theme.click(p, bx + bw - 96, ry + 36, 96, 28, function()
                theme.toast(it[1] .. "：" .. act)
            end, 6)
            sv.dlh[i] = { bar = bar, lbl = pl, step = it[4] }
        end
        note(p, bx, dy + 200, bw, "仅在驻车且连接 Wi-Fi 时自动下载")

        if not sv._dlt then
            sv._dlt = true
            local function tick()
                if not sv.open or sv.kind ~= "download" then sv._dlt = nil return end
                for i = 1, #sv.dl do
                    local h = sv.dlh and sv.dlh[i]
                    if h and h.step and (tonumber(sv.dl[i]) or 0) < 1 then
                        sv.dl[i] = math.min(1, (tonumber(sv.dl[i]) or 0) + 0.006)
                        pcall(function() h.bar:set(sv.dl[i]) end)
                        pcall(function()
                            h.lbl:set_text(math.floor(sv.dl[i] * 100) .. "%")
                        end)
                    end
                end
                sys.timerStart(tick, 502)
            end
            sys.timerStart(tick, 502)
        end
    end }

    ------------------------------------------------------------ 百变主题
    T.theme = { w = 392, h = 200, title = "百变主题", draw = function(p, bx, by, bw)
        local cur = theme.cur
        local items = { { "dark", "深色 · 星夜" }, { "light", "浅色 · 晨曦" } }
        for i, it in ipairs(items) do
            local ry = by + (i - 1) * 52
            local sel = (cur == it[1])
            box(p, bx, ry, bw, 44, sel and C.sel_str or C.deep, 10,
                sel and C.blue2 or C.line, 1)
            airui.shape({ parent = p, x = bx + 14, y = ry + 17, w = 12, h = 12, items = {
                { type = "circle", cx = 5, cy = 5, r = 4, color = C.blue2, width = 1,
                  fill = true, fill_color = C.blue2 } } })
            txt(p, bx + 34, ry + 11, bw - 120, 22, it[2], C.text, 16)
            if sel then
                txt(p, bx + bw - 80, ry + 11, 66, 22, "当前", C.sub, 16,
                    airui.TEXT_ALIGN_RIGHT)
            end
            theme.click(p, bx, ry, bw, 44, function()
                if theme.cur == it[1] then theme.toast("当前已是" .. it[2]) return end
                theme.toggle_theme()
                theme.rerender_current()
            end, 10)
        end
        note(p, bx, by + 112, bw, "点击即时切换 · 整屏配色同步生效")
    end }

    ------------------------------------------------------------ 文件管理
    T.files = { w = 520, h = 360, title = "文件管理", draw = function(p, bx, by, bw)
        backbar(p, bx, by)
        local ly = by + 38
        local list = { { "行车视频", "18 个 · 2.4 GB" }, { "音乐", "126 首 · 860 MB" },
                       { "图片", "42 张 · 128 MB" }, { "离线地图", "1 个 · 1.2 GB" },
                       { "其他", "36 MB" } }
        for i, it in ipairs(list) do
            local ry = ly + (i - 1) * 50
            box(p, bx, ry, bw, 42, C.deep, 10, C.line, 1)
            theme.icon(p, bx + 12, ry + 12, 18, "folder", C.blue2)
            txt(p, bx + 40, ry + 10, 220, 22, it[1], C.text, 16)
            txt(p, bx + bw - 200, ry + 10, 186, 22, it[2], C.sub, 16, airui.TEXT_ALIGN_RIGHT)
            theme.click(p, bx, ry, bw, 42, function()
                theme.toast("打开：" .. it[1])
            end, 10)
        end
    end }

    return T
end

local W, H, TOP = theme.W, theme.H, theme.TOP_H

-- 图标种类与 MOCK.apps 顺序一一对应
local KINDS = { "robot", "disc", "bolt", "camera", "sun",
                "camera", "photo", "folder", "gamepad", "bolt",
                "grid", "screen", "shield", "book", "download" }

-- 入口 → 弹层类型 / 页面
local SHEET_OF = { [2] = "surround", [3] = "charge", [4] = "dashcam",
                   [6] = "camera", [7] = "album", [8] = "files", [9] = "games",
                   [10] = "boost", [11] = "theme", [12] = "rear", [13] = "sentinel",
                   [14] = "manual", [15] = "download" }
local GO_OF = { [1] = "voice", [5] = "weather" }

theme.make_page("apps", function(root, M)
    local C = theme.C

    -- 右上角是「回主页」圆钮（不再又进一次应用页）
    theme.topbar(root, "back", false, false, true, "全部应用")

    ------------------------------------------------------------------
    -- 弹层状态
    ------------------------------------------------------------------
    local layer
    local sv = { open = false, kind = nil, arg = nil, pics = 0 }

    local draw_sheet                -- 前置声明
    local SHEETS                    -- app_sheets 构建结果

    local function sheet_close()
        sv.open = false
        sv.kind = nil
        sv.arg  = nil
        sv.stack = nil
        if layer then
            pcall(function() layer:destroy() end)
            layer = nil
        end
    end

    -- 弹层返回栈：相机 → 相册 → 照片预览 可以逐级返回
    local function sheet_open(kind, arg)
        if sv.open and sv.kind then
            sv.stack = sv.stack or {}
            sv.stack[#sv.stack + 1] = sv.kind
        else
            sv.stack = {}
        end
        sv.open = true
        sv.kind = kind
        sv.arg  = arg
        if draw_sheet then draw_sheet() end
    end

    local function sheet_back()
        local st = sv.stack
        if st and #st > 0 then
            local k = st[#st]
            st[#st] = nil
            sv.open = true
            sv.kind = k
            sv.arg  = nil
            if draw_sheet then draw_sheet() end
        else
            sheet_close()
        end
    end

    ------------------------------------------------------------------
    -- 弹层内绘制小工具
    ------------------------------------------------------------------
    local function txt(p, x, y, w, h, s, col, size, align)
        airui.label({ parent = p, x = math.floor(x), y = math.floor(y),
            w = math.floor(w), h = math.floor(h), text = s,
            color = col or C.text, font_size = size or 16,
            align = align or airui.TEXT_ALIGN_LEFT })
    end

    local function box(p, x, y, w, h, col, radius, bcol, bw)
        return airui.container({ parent = p, x = math.floor(x), y = math.floor(y),
            w = math.floor(w), h = math.floor(h), color = col or C.deep,
            radius = radius or 10, border_color = bcol or C.line,
            border_width = bw or 1 })
    end

    local function backbar(p, bx, by)
        box(p, bx, by, 76, 30, C.deep, 8, C.line2, 1)
        theme.icon(p, bx + 9, by + 9, 13, "left", C.blue2)
        txt(p, bx + 26, by + 5, 44, 22, "返回", C.blue2, 16)
        theme.click(p, bx, by, 76, 30, sheet_back, 8)
    end

    local function bigbtn(p, bx, by, bw, text, fn, hot)
        box(p, bx, by, bw, 48, hot and C.sel_str or C.deep, 10,
            hot and C.blue2 or C.line2, 1)
        txt(p, bx, by + 12, bw, 24, text, hot and C.blue2 or C.text, 16,
            airui.TEXT_ALIGN_CENTER)
        if fn then theme.click(p, bx, by, bw, 48, fn, 10) end
    end

    local function rowitem(p, bx, by, bw, k, v, fn, vcol)
        box(p, bx, by, bw, 44, C.deep, 10, C.line, 1)
        txt(p, bx + 14, by + 11, bw - 120, 22, k, C.text, 16)
        txt(p, bx + bw - 200, by + 11, 186, 22, v, vcol or C.sub, 16,
            airui.TEXT_ALIGN_RIGHT)
        if fn then theme.click(p, bx, by, bw, 44, fn, 10) end
    end

    local function note(p, bx, by, bw, s)
        txt(p, bx, by, bw, 20, s, C.dim, 16)
    end

    ----------------------------------------------------------------
    -- 暗色模拟画面（相机 / 全景 / 哨兵 / 记录仪共用）
    ----------------------------------------------------------------
    local function stage(p, bx, by, bw, bh, o)
        o = o or {}
        airui.container({ parent = p, x = bx, y = by, w = bw, h = bh,
            color = 0x0A1020, radius = 12, border_color = 0x1B2C4A, border_width = 1 })
        local it = {}
        local ground = by + bh - 34
        for i = 1, 4 do
            local bwd = math.floor(bw * 0.085)
            local bh1 = math.floor(bh * (0.20 + 0.08 * ((i * 3) % 3)))
            local bx1 = bx + math.floor(bw * 0.09) + (i - 1) * math.floor(bw * 0.13)
            it[#it + 1] = { type = "rect", x = bx1, y = ground - bh1, w = bwd, h = bh1,
                color = 0x16304F, width = 1, fill = true,
                fill_color = 0x16304F, fill_opacity = 255 }
            it[#it + 1] = { type = "rect", x = bx1 + math.floor(bw * 0.46),
                y = ground - math.floor(bh1 * 0.78), w = bwd,
                h = math.floor(bh1 * 0.78), color = 0x16304F, width = 1,
                fill = true, fill_color = 0x16304F, fill_opacity = 255 }
        end
        it[#it + 1] = { type = "line", x1 = bx + 10, y1 = ground,
            x2 = bx + bw - 10, y2 = ground, color = 0x2A6EA8, width = 2 }
        local cw2, chh = math.floor(bw * 0.16), math.floor(bh * 0.19)
        local ccx = bx + math.floor((bw - cw2) / 2)
        local ccy = ground - chh - 6
        it[#it + 1] = { type = "rect", x = ccx, y = ccy, w = cw2, h = chh,
            color = 0xC0304A, width = 1, fill = true,
            fill_color = 0xC0304A, fill_opacity = 255 }
        it[#it + 1] = { type = "circle", cx = ccx + 10, cy = ccy + chh + 2, r = 5,
            color = 0x101018, width = 1, fill = true, fill_color = 0x101018 }
        it[#it + 1] = { type = "circle", cx = ccx + cw2 - 10, cy = ccy + chh + 2, r = 5,
            color = 0x101018, width = 1, fill = true, fill_color = 0x101018 }
        if o.sun then
            it[#it + 1] = { type = "circle", cx = bx + bw - 62, cy = by + 50, r = 24,
                color = 0xE0B41E, width = 1, fill = true, fill_color = 0xE0B41E }
        end
        if o.ring then
            local rcx, rcy, rr = bx + math.floor(bw / 2), by + math.floor(bh / 2), 76
            for i = 0, 7 do
                local a1 = (i * 45 + 8) * math.pi / 180
                local a2 = (i * 45 + 32) * math.pi / 180
                it[#it + 1] = { type = "line",
                    x1 = math.floor(rcx + rr * math.cos(a1)),
                    y1 = math.floor(rcy + rr * math.sin(a1)),
                    x2 = math.floor(rcx + rr * math.cos(a2)),
                    y2 = math.floor(rcy + rr * math.sin(a2)),
                    color = 0x22C4E0, width = 2 }
            end
        end
        if o.arrow then
            local mx = bx + math.floor(bw / 2)
            it[#it + 1] = { type = "line", x1 = mx - 44, y1 = by + bh - 40,
                x2 = mx - 12, y2 = by + bh - 12, color = 0x9FB3C8, width = 2 }
            it[#it + 1] = { type = "line", x1 = mx + 44, y1 = by + bh - 40,
                x2 = mx + 12, y2 = by + bh - 12, color = 0x9FB3C8, width = 2 }
        end
        -- 图元坐标都是绝对坐标，shape 画布必须从 (0,0) 开始，
        -- 否则会被 (bx,by) 再偏移一次，图形跑到画面外（全景影像里的青色斜线）
        airui.shape({ parent = p, x = 0, y = 0, w = W, h = H, items = it })
        if o.badge then
            airui.shape({ parent = p, x = bx + bw - 112, y = by + 12, w = 100, h = 16, items = {
                { type = "circle", cx = 5, cy = 8, r = 4, color = 0xE5484D, width = 1,
                  fill = true, fill_color = 0xE5484D } } })
            txt(p, bx + bw - 168, by + 10, 150, 20, o.badge, 0xE5484D, 16,
                airui.TEXT_ALIGN_RIGHT)
        end
        if o.tag then
            txt(p, bx + 12, by + bh - 26, bw - 24, 20, o.tag, 0x6E86A8, 16)
        end
    end

    SHEETS = S.build(theme, { txt = txt, box = box, backbar = backbar,
        bigbtn = bigbtn, rowitem = rowitem, note = note, stage = stage,
        state = sv, redraw = function() if draw_sheet then draw_sheet() end end,
        open = sheet_open, close = sheet_close })

    ------------------------------------------------------------------
    -- 弹层整体重绘
    ------------------------------------------------------------------
    draw_sheet = function()
        if layer then
            pcall(function() layer:destroy() end)
            layer = nil
        end
        if not sv.open then return end
        local d = SHEETS[sv.kind]
        if not d then return end
        local cw, ch = d.w, d.h
        local cx = math.floor((W - cw) / 2)
        local cy = math.floor((H - ch) / 2)

        layer = airui.container({ parent = root, x = 0, y = 0, w = W, h = H,
            color = C.bg, color_opacity = 1 })
        -- 遮罩（点空白处关闭）
        airui.container({ parent = layer, x = 0, y = 0, w = W, h = H,
            color = 0x050B14, color_opacity = 150 })
        theme.click(layer, 0, 0, W, H, sheet_close)
        -- 卡片
        airui.container({ parent = layer, x = cx, y = cy, w = cw, h = ch,
            color = C.card, radius = 18, border_color = C.line2, border_width = 1 })
        theme.click(layer, cx, cy, cw, ch, function() end, 18)

        local title = d.title
        if type(title) == "function" then title = title(sv) end
        txt(layer, cx + 20, cy + 14, cw - 80, 26, title or "", C.title, 20)

        -- 关闭键 ×
        airui.container({ parent = layer, x = cx + cw - 42, y = cy + 13, w = 26, h = 26,
            color = C.card, radius = 13, border_color = C.line, border_width = 1 })
        airui.shape({ parent = layer, x = cx + cw - 42, y = cy + 13, w = 26, h = 26, items = {
            { type = "line", x1 = 10, y1 = 10, x2 = 16, y2 = 16, color = C.sub, width = 1 },
            { type = "line", x1 = 16, y1 = 10, x2 = 10, y2 = 16, color = C.sub, width = 1 } } })
        theme.click(layer, cx + cw - 46, cy + 9, 34, 34, sheet_close, 17)

        airui.container({ parent = layer, x = cx + 20, y = cy + 48, w = cw - 40, h = 1,
            color = C.line })

        local ok, err = pcall(d.draw, layer, cx + 20, cy + 58, cw - 40)
        if not ok then print("[apps.sheet] " .. tostring(err)) end
    end

    ------------------------------------------------------------------
    -- 宫格（5 列 × 3 行）
    ------------------------------------------------------------------
    local PX = 26
    local colw = math.floor((W - PX * 2 - 4 * 8) / 5)     -- 188
    local rowh = 94 + 9 + 20                              -- 123
    -- 行间距按可用高度均分（原来固定 30 且整体垂直居中，底部空 72px）
    local avail = H - TOP - 18 - 3 * rowh
    local rgap = math.max(30, math.floor((avail - 20) / 2))
    local y0 = TOP + 10

    for i, app in ipairs(MOCK.apps) do
        local row = math.floor((i - 1) / 5)
        local col = (i - 1) % 5
        local cx = PX + col * (colw + 8) + math.floor((colw - 94) / 2)
        local cy = y0 + row * (rowh + rgap)
        local boost_on = app.boost and MOCK.boost.on

        airui.container({ parent = root, x = cx, y = cy, w = 94, h = 94,
            color = theme.blend(app.c1, app.c2, 0.55), radius = 22,
            border_color = boost_on and C.cyan or C.line,
            border_width = boost_on and 2 or 1 })
        if i == 5 then
            theme.icon(root, cx + 30, cy + 30, 34, "sun", 0xF0F8FF, C.yellow)
        else
            theme.icon(root, cx + 26, cy + 26, 42, KINDS[i], 0xF0F8FF, 0xF0F8FF)
        end
        airui.label({ parent = root, x = PX + col * (colw + 8), y = cy + 103,
            w = colw, h = 20, text = app.name, color = C.name, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })

        theme.click(root, cx, cy, 94, 94, function()
            if GO_OF[i] then
                theme.go_defer(GO_OF[i])
            elseif SHEET_OF[i] then
                sheet_open(SHEET_OF[i])
            end
        end, 22)
    end

    ------------------------------------------------------------------
    -- 1.5s 刷新：充电进度模拟（对照 html 的进度条动画）
    ------------------------------------------------------------------
    return function()
        if sv.open and sv.kind == "charge" and sv.charging then
            sv.pct = math.min(0.99, (sv.pct or 0.75) + 0.004)
            pcall(function()
                if sv._prog then sv._prog.set(sv.pct) end
                local s = math.floor(sv.pct * 100 + 0.5) .. "%"
                if sv._pct1 then sv._pct1:set_text(s) end
                if sv._pct2 then sv._pct2:set_text(s) end
            end)
        end
    end
end)
