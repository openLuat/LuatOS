--[[
@module  page_glass
@summary 方案D · 玻璃拟态中控页（深色/浅色双主题，1024x600 触摸）
@version 3.1.0
@note 视觉与信息架构对齐 docs/方案D_玻璃拟态.html：
        顶栏玻璃胶囊（含主题切换按钮） + 房间Tab + 气候/设备/安防三栏 + 底部场景Dock + 调档调节条。
        主题切换：顶栏按钮 → ui_theme.set_mode 保存（fskv）→ 重启进入新主题。
      验收纪律：最小字号 16 号；任何控件（含动画全程）永不探出父容器内容区。
      v2.2 滚动条整治（官方 airui.md §4.2.13）：
        AirUI 容器滚动条固定 AUTO 且无关闭接口，子控件探出内容区 1px 即画滚动条。
        全工程纪律：任何控件（含动画全程）永不探出父容器内容区，靠尺寸预算而非禁用动效 ——
        - 字号预算：label 行高 ≈ 字号×1.75，ui_widget.text 统一兜底 h = max(声明, ×1.75+2)
        - 隐藏面板：单套 6 磁贴原地复用（文字清空 + 透明），绝不 set_pos 到屏幕外
          （整页切换例外：ui_page 把整页根容器整体推到屏外负方向，见 AGENTS.md R13）
        - 入场浮动 +10 / 磁贴上浮 +12，行程均经边界核算；
          调档条常驻中栏底部空闲区（268~356），无屏幕级悬浮层——悬浮卡片的描边
          在背景透明后仍可见（幽灵框），且常驻控件会吸收磁贴触摸（按了没反应）
        - 静态布局：Dock.y=505 预留入场余量；摄像头卡/窗户芯片等按实际文字宽高放宽
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local C, G = T.c, T.glass
local M = {}

local SW, SH = T.screen.w, T.screen.h
local ROOT = airui.screen                    -- 本页根容器：由 ui_page 传入，默认回退屏幕

-- ==================== 布局常量（对应 HTML 1024x600，均已按内容区核算） ====================
local TOP = { x = 18, y = 16, w = 988, h = 54 }
local DASH_Y, DASH_H = 128, 368
local PN = {
    climate = { x = 18,  w = 296 },
    devices = { x = 328, w = 392 },
    sec     = { x = 734, w = 272 },
}
local DOCK = { x = 18, y = 505, w = 988, h = 76 }  -- y=505：root 高 h+7，入场浮动 +10 峰值 598 ≤ 600
local TW, TH, TGAP = 176, 64, 10                  -- 设备磁贴尺寸/间距（64：容纳 16 号字两行预算）
local GRID_X, GRID_Y = 15, 48                     -- 矩阵原点（48：计数标签底缘 44 之下留 4px，不重叠）
local GRID_MAX = 6                                -- 单房间最多 6 台设备（2 列 × 3 行）

local lbl_clock, lbl_toast, toast_seq = nil, nil, 0
local top_chips = {}                              -- 顶栏状态芯片 {arm, lock}
local lbl_room, lbl_count
local lb_temp, lb_humi, lb_acst, lb_ac_temp
local climate_chart, humi_dots                    -- 气候栏图形：趋势折线 / 湿度点阵
local room_tabs = {}
local grids_parent                               -- 磁贴挂载面板（中栏卡片）
local tiles = {}                                  -- 单套设备矩阵：6 个原地复用磁贴
local popup, popup_open = nil, false
local cur_dev, cur_tile
local handles = {}                                -- 入场淡入载体
local SEC_UI = {}                                 -- 安防行句柄（场景联动同步开关视觉）

-- 前置声明（闭包互相引用）
local switch_room, update_climate, update_count, refresh_tile
local open_popup, close_popup, popup_delta, popup_set

-- ==================== 提示条 ====================
local function toast(msg)
    toast_seq = toast_seq + 1
    local seq = toast_seq
    W.toast_in(lbl_toast, msg)
    sys.timerStart(function()
        if seq == toast_seq then pcall(function() lbl_toast:set_text("") end) end
    end, 3000)
end

-- ==================== 背景：深空底 + 四团彩色柔光 ====================
-- 光斑虽超出屏幕边缘，但挂在页面根 ROOT 上、且页面层无描边内容区裁切问题；
-- 若真机仍出现滚动条，把四个光斑坐标收进 0~SW/0~SH 即可。
local function build_background()
    airui.container({ parent = ROOT, x = 0, y = 0, w = SW, h = SH,
        color = G.bg, border_width = 0, radius = 0 })
    local orbs = {
        { x = 0,   y = 0,   w = 360, h = 220, r = 110, c = G.glow1, o = G.bg_glow_opa },
        { x = 680, y = 0,   w = 344, h = 260, r = 120, c = G.glow2, o = G.bg_glow_opa },
        { x = 620, y = 380, w = 404, h = 220, r = 110, c = G.glow3, o = 30 },
        { x = 0,   y = 360, w = 280, h = 240, r = 120, c = G.glow4, o = 28 },
    }
    for _, g in ipairs(orbs) do
        local o = airui.container({ parent = ROOT, x = g.x, y = g.y, w = g.w, h = g.h,
            color = g.c, radius = g.r, border_width = 0 })
        W.glass(o, g.c, g.o)
    end
end

-- ==================== 顶栏玻璃胶囊 ====================
local function status_chip(parent, x, y, w, name)
    local box = airui.container({ parent = parent, x = x, y = y, w = w, h = 36,
        color = C.card, radius = 18, border_width = 0 })
    W.glass(box, C.card, G.tile_opa)
    local dot = airui.container({ parent = parent, x = x + 12, y = y + 14, w = 8, h = 8,
        color = C.ok, radius = 4, border_width = 0 })
    W.glass(dot, C.ok, 255)
    local lbl = W.text_mid(parent, { text = name, x = x + 26, y = y, w = w - 30, h = 36,
        size = 16, color = C.text_sub })
    local handle = { box = box }
    function handle.set(ok, txt)
        W.glass(dot, ok and C.ok or C.warn, 255)
        pcall(function() lbl:set_text(name .. " " .. txt) end)
    end
    return handle
end

-- 主题切换胶囊：文字显示「点击后进入」的主题，保存偏好（fskv）后重启生效
local function theme_chip(p)
    local x, y, w, h = 566, 10, 120, 36
    local box = airui.container({ parent = p, x = x, y = y, w = w, h = h,
        color = C.card, radius = 18, border_width = 0 })
    W.glass(box, C.card, G.tile_opa)
    W.text_mid(p, { text = (T.mode == "dark") and "浅色主题" or "深色主题",
        x = x, y = y, w = w, h = h, size = 16, color = C.text_sub,
        align = airui.TEXT_ALIGN_CENTER })
    W.press_layer(p, { x = x, y = y, w = w, h = h, radius = 18, target = box, tx = x, ty = y,
        on_click = function()
            local next_mode = (T.mode == "dark") and "light" or "dark"
            T.set_mode(next_mode)
            toast("切换到" .. (next_mode == "light" and "浅色" or "深色") .. "主题，即将重启…")
            sys.timerStart(function()
                log.info("page_glass", "重启进入新主题", next_mode)
                if rtos and rtos.reboot then
                    rtos.reboot()
                elseif pm and pm.reboot then
                    pm.reboot()
                else
                    log.error("page_glass", "未找到可用的重启接口 rtos.reboot/pm.reboot")
                end
            end, 800)
        end })
end

local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h,
        fade_in = true })
    handles[#handles + 1] = g
    local p = g.card
    W.text(p, { text = "Home", x = 18, y = 12, w = 90, h = 36,
        size = 20, color = C.text, weight = 700 })
    top_chips.arm  = status_chip(p, 112, 10, 150, "安防")
    top_chips.lock = status_chip(p, 270, 10, 130, "门锁")
    top_chips.win  = status_chip(p, 408, 10, 150, "窗户")
    top_chips.win.set(false, "1 处未关")
    theme_chip(p)
    lbl_toast = W.text_mid(ROOT, { text = "", x = 430, y = 88, w = 540, h = 36,
        size = 16, color = C.pri, align = airui.TEXT_ALIGN_RIGHT })
    lbl_clock = W.text(p, { text = "", x = 700, y = 15, w = 270, h = 30,
        size = 16, color = C.text_sub, align = airui.TEXT_ALIGN_RIGHT })
end

-- ==================== 房间 Tab 行 ====================
local function build_roombar()
    lbl_room = W.text(ROOT, { text = "客厅", x = 18, y = 84, w = 130, h = 36,
        size = T.f.title, color = C.text, weight = 700 })
    for i, room in ipairs(S.rooms) do
        room_tabs[i] = W.chip(ROOT, { x = 150 + (i - 1) * 86, y = 84, w = 76, h = 36,
            text = room.name,
            -- 暗色玻璃 Tab：未选中几乎透明（只留文字），选中是青色半透明胶囊，
            -- 不再用纯白不透明底（之前的白色块过于抢眼）
            off_color = 0xFFFFFF, off_opa = 12, off_tcolor = C.text_sub,
            on_color = C.pri, on_opa = 60, on_tcolor = C.pri,
            on_click = function() switch_room(i) end })
    end
end

-- ==================== 通用小胶囊按钮（可整体透明/恢复，弹窗专用） ====================
local function pill(parent, cfg)
    local color, opa = cfg.color or C.btn_bg, cfg.opa or 230
    local box = airui.container({ parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        color = color, radius = cfg.radius or 12, border_width = 0 })
    W.glass(box, color, opa)
    local lbl = W.text_mid(parent, { text = cfg.text or "", x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, size = cfg.size or 16,
        color = cfg.tcolor or 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })
    local enabled = true
    local press = W.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        radius = cfg.radius or 12, on_click = function()
            if enabled and cfg.cb then cfg.cb() end
        end })
    local handle = { box = box, lbl = lbl }
    function handle.set_disabled(v)                    -- 热区命中开关（W.press_layer 内部闭包，零固件依赖）
        if press then press.set_disabled(v) end
    end
    function handle.set_visible(v)                     -- 原位显隐：底板 alpha + 清文字 + 关命中
        enabled = v and true or false
        handle.set_disabled(not v)
        if v then
            W.glass(box, color, opa)
            pcall(function() lbl:set_text(cfg.text or "") end)
        else
            W.glass(box, color, 0)
            pcall(function() lbl:set_text("") end)
        end
    end
    return handle
end

-- ==================== 左栏：气候 ====================
-- 24h 趋势：相对当前室温的整数偏移（airui.chart 只吃整数，小数不显示）
local CURVE = { -3, -2, -1, 0, 2, 4, 5, 4, 2, 1, -1, -2 }
local BAR_H = { 28, 25, 31, 37, 45, 53, 49, 40 }  -- 旧固件回退：静态温度柱

-- 湿度点阵：20 点，每点代表 5%，比纯数字更快读
local function humi_items(pct)
    local n, lit = 20, math.floor(pct / 5 + 0.5)
    local items = {}
    for i = 1, n do
        local on = i <= lit
        local opa = on and 220 or 26
        items[#items + 1] = { type = "circle", cx = (i - 1) * 13 + 3, cy = 4, r = 3,
            color = on and C.pri or C.soft, width = 1, opacity = opa,
            fill = true, fill_color = on and C.pri or C.soft, fill_opacity = opa }
    end
    return items
end

-- 数据 → 图形：趋势折线 + 湿度点阵（图形组件缺失时静默跳过）
local function paint_climate(room)
    if climate_chart then
        local base = math.floor(room.temp + 0.5)
        local vals = {}
        for i = 1, #CURVE do
            local v = base + CURVE[i]
            if v < 16 then v = 16 elseif v > 32 then v = 32 end
            vals[i] = v
        end
        pcall(function() climate_chart:set_values(1, vals) end)
    end
    if humi_dots then
        pcall(function() humi_dots:set_items(humi_items(room.humi)) end)
    end
end

local function build_climate()
    local g = W.glass_card({ parent = ROOT, x = PN.climate.x, y = DASH_Y,
        w = PN.climate.w, h = DASH_H, fade_in = true })
    handles[#handles + 1] = g
    local p = g.card
    W.text(p, { text = "气候", x = 15, y = 14, w = 120, h = 28,
        size = 16, color = C.text_dim, weight = 700 })
    lb_temp = W.text(p, { text = "", x = 15, y = 42, w = 220, h = 82,
        size = T.f.temp, color = C.text, weight = 700 })
    lb_humi = W.text(p, { text = "", x = 15, y = 112, w = 130, h = 30,
        size = 16, color = C.text_sub })
    lb_acst = W.text(p, { text = "", x = 150, y = 112, w = 130, h = 30,
        size = 16, color = C.pri, align = airui.TEXT_ALIGN_RIGHT })
    -- 湿度点阵（20 点 × 5%，填满即 100%）
    humi_dots = W.shape(p, { x = 15, y = 148, w = 264, h = 8, items = humi_items(50) })
    -- 24h 趋势：折线 + 青色渐变填充 + 极淡网格；旧固件回退成静态温度柱
    climate_chart = W.chart(p, {
        x = 14, y = 160, w = 264, h = 94,       -- 内容区宽 292：右留 14 余量，绝不探出（否则出滚动条）
        type = "line", y_min = 16, y_max = 32, point_count = #CURVE,
        line_color = C.pri, line_width = 2, point_radius = 0,
        hdiv = 3, vdiv = 0, legend = false,
        x_axis = { enable = false }, y_axis = { enable = false },
        fill_fade = true, grid_color = 0xFFFFFF, grid_opa = 12, bg_opa = 0,
    })
    if not climate_chart then
        local bw, gap, bottom = 28, 6, 254
        for i, h in ipairs(BAR_H) do
            local bar = airui.container({ parent = p, x = 15 + (i - 1) * (bw + gap),
                y = bottom - h, w = bw, h = h,
                color = C.card, radius = 5, border_width = 0 })
            W.glass(bar, i == 6 and C.pri or C.card, i == 6 and 230 or 30)
        end
    end
    local xl = { "08时", "12时", "16时", "20时" }
    for i = 1, 4 do
        W.text_mid(p, { text = xl[i], x = 14 + (i - 1) * 66, y = 258,
            w = 66, h = 22, size = T.f.mini, color = C.text_dim,
            align = airui.TEXT_ALIGN_CENTER })
    end
    -- 极淡虚线分隔（把「当前读数」和「空调控制」两段分开，不用实线抢视觉）
    W.shape(p, { x = 15, y = 284, w = 264, h = 2, items = {
        { type = "line", x1 = 0, y1 = 1, x2 = 264, y2 = 1,
          color = C.soft, width = 1, opacity = 12, dash_width = 6, dash_gap = 6 },
    } })
    -- 空调快捷调节
    W.text_mid(p, { text = "空调", x = 15, y = 296, w = 44, h = 34,
        size = 16, color = C.text_sub })
    lb_ac_temp = W.text_mid(p, { text = "", x = 114, y = 292, w = 76, h = 42,
        size = 24, color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    W.button(p, { x = 66, y = 292, w = 42, h = 42, text = "-", on_click = function()
        local room = S.room()
        S.ac_delta(room, -1)
        pcall(function() lb_ac_temp:set_text(room.ac_t .. "℃") end)
        pcall(function() lb_acst:set_text(room.ac_t .. "℃ " .. room.ac_mode) end)
        W.temp_pulse(lb_ac_temp); g.sweep()
        toast(room.name .. "空调 " .. room.ac_t .. "℃")
    end })
    W.button(p, { x = 196, y = 292, w = 42, h = 42, text = "+", on_click = function()
        local room = S.room()
        S.ac_delta(room, 1)
        pcall(function() lb_ac_temp:set_text(room.ac_t .. "℃") end)
        pcall(function() lb_acst:set_text(room.ac_t .. "℃ " .. room.ac_mode) end)
        W.temp_pulse(lb_ac_temp); g.sweep()
        toast(room.name .. "空调 " .. room.ac_t .. "℃")
    end })
    return g
end

-- ==================== 中栏：设备矩阵（单套 6 磁贴原地复用，切换零位移） ====================
-- 设备 → 内置图标（按名称关键词推断，无需改动数据层）
local function dev_icon(d)
    local n = d.nm or ""
    if n:find("窗帘", 1, true) then return airui.SYMBOL_UP end
    if n:find("新风", 1, true) then return airui.SYMBOL_LOOP end
    if n:find("加湿", 1, true) then return airui.SYMBOL_CHARGE end
    if n:find("电热毯", 1, true) then return airui.SYMBOL_WARNING end
    if n:find("油烟机", 1, true) then return airui.SYMBOL_LOOP end
    if n:find("净水", 1, true) then return airui.SYMBOL_CHARGE end
    return airui.SYMBOL_POWER                      -- 灯（默认）
end

refresh_tile = function(d, t)
    pcall(function()
        t.ds:set_text(d.on and (d.ds .. d.val .. "%") or "关闭")
        t.ic:set_text(dev_icon(d))                 -- 图标亮灭：开 = 主色，关 = 灰
        t.ic:set_color(d.on and C.pri or C.text_dim)
    end)
end

update_count = function()
    local on, n = S.dev_on_count(S.room())
    pcall(function() lbl_count:set_text("设备 · " .. on .. "/" .. n .. " 开") end)
end

local function build_tile()
    local idx = #tiles + 1
    local col, row = (idx - 1) % 2, math.floor((idx - 1) / 2)
    local tx, ty = GRID_X + col * (TW + TGAP), GRID_Y + row * (TH + TGAP)
    local box = airui.container({ parent = grids_parent, x = tx, y = ty, w = TW, h = TH,
        color = C.card, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.card, 0)                          -- 初始透明，apply_room 上色
    -- 磁贴不再加顶部高光条（hl）：原 hl 在点击 sweep 后会被补间停在 hl_opa=60，
    -- 在磁贴顶边留下一条常亮横线（用户反馈「点完上面出现一横」），现整体移除。
    -- 左侧小图标：亮 = 主色，灭 = 灰（替代原来的色点，开关状态更直观）
    local ic = W.icon(box, { symbol = airui.SYMBOL_POWER, x = 8, y = 17,
        size = 22, w = 26, h = 26, color = C.text_dim })
    local nm =         W.text(box, { text = "", x = 40, y = 8, w = TW - 90, h = 30,
        size = 16, color = C.text, weight = 600 })
        local ds = W.text(box, { text = "", x = 40, y = 32, w = TW - 90, h = 28,
        size = 16, color = C.text_sub })
    local t = { box = box, x = tx, y = ty, ic = ic, nm = nm, ds = ds, dev = nil }
    function t.sweep() end                           -- 磁贴已移除顶部高光条，扫光同步关闭
    -- 调档按钮（打开弹窗），随磁贴一起显隐
    t.adj = pill(box, { x = TW - 44, y = 15, w = 34, h = 32, text = "调",
        cb = function() if t.dev then open_popup(t.dev, t) end end })
    t.adj.set_visible(false)
    -- 磁贴主体：点击开关（空磁贴直接忽略）
    W.press_layer(box, { x = 0, y = 0, w = TW - 52, h = TH, radius = T.r.panel,
        target = box, tx = tx, ty = ty, on_click = function()
            local d = t.dev
            if not d then return end
            d.on = not d.on
            refresh_tile(d, t)
            t.sweep()
            update_count()
            toast(d.nm .. (d.on and " 已打开" or " 已关闭"))
        end })
    tiles[idx] = t
    return t
end

-- 房间数据落到 6 个磁贴上：多余磁贴原地置透明（文字清空，绝不移出屏幕）
local function apply_room(i, animate)
    S.set_room(i)
    local room = S.room()
    pcall(function() lbl_room:set_text(room.name) end)
    local n = #room.devs
    for k = 1, GRID_MAX do
        local t = tiles[k]
        local d = k <= n and room.devs[k] or nil
        t.dev = d
        if d then
            pcall(function()
                t.nm:set_text(d.nm)
                t.ds:set_text(d.on and (d.ds .. d.val .. "%") or "关闭")
                t.ic:set_text(dev_icon(d))          -- 图标随设备类型 + 开关状态刷新
                t.ic:set_color(d.on and C.pri or C.text_dim)
            end)
            t.adj.set_visible(true)
        else
            -- 空磁贴：文字/图标清空（label 无 alpha，清空即不可见），热区随 adj 关闭
            pcall(function() t.nm:set_text(""); t.ds:set_text(""); t.ic:set_text("") end)
            t.adj.set_visible(false)
        end
        if animate and d and not T.motion.instant then
            -- 补间模式下的磁贴逐个上浮（+12px 起步，峰值底缘 272 ≤ 面板内容区 364）
            -- 错开延迟最小 5ms：rtos 定时器最小超时 1ms，传 0 会创建失败（静默）
            sys.timerStart(function()
                pcall(function() t.box:set_pos(t.x, t.y + 12) end)
                W.glass(t.box, C.card, 0)
                W.tween(T.motion.swap_fr, function(tt)
                    pcall(function() t.box:set_pos(t.x, t.y + math.floor(12 * (1 - tt))) end)
                    W.glass(t.box, C.card, math.floor(G.tile_opa * tt))
                end, function()                      -- 收尾自愈：强制落回最终态
                    pcall(function() t.box:set_pos(t.x, t.y) end)
                    W.glass(t.box, C.card, G.tile_opa)
                end)
            end, math.max(5, (k - 1) * T.motion.swap_gap))
        else
            pcall(function() t.box:set_pos(t.x, t.y) end)  -- 即时模式：直接落位
            W.glass(t.box, C.card, d and G.tile_opa or 0)
        end
    end
    for j, tab in ipairs(room_tabs) do tab.set_active(j == i) end
    update_count()
    update_climate(false)
end

local function build_devices()
    local g = W.glass_card({ parent = ROOT, x = PN.devices.x, y = DASH_Y,
        w = PN.devices.w, h = DASH_H, fade_in = true })
    handles[#handles + 1] = g
    local p = g.card
    lbl_count = W.text(p, { text = "设备", x = 15, y = 14, w = 200, h = 28,
        size = 16, color = C.text_dim, weight = 700 })
    grids_parent = p
    for _ = 1, GRID_MAX do build_tile() end
    return g
end

-- ==================== 右栏：安防 ====================
local function build_security()
    local g = W.glass_card({ parent = ROOT, x = PN.sec.x, y = DASH_Y,
        w = PN.sec.w, h = DASH_H, fade_in = true })
    handles[#handles + 1] = g
    local p = g.card
    W.text(p, { text = "安防", x = 15, y = 14, w = 120, h = 28,
        size = 16, color = C.text_dim, weight = 700 })

    -- 安防行：返回句柄供场景联动同步。handle.set(v, quiet) 同时更新
    -- 圆点 / app_state / 顶栏芯片 / 开关滑块；quiet=true 时不弹提示（场景批量执行用）。
    local function sec_row(y, nm, on, on_color, key, chip_on, chip_off, icon)
        local box = airui.container({ parent = p, x = 15, y = y, w = 242, h = 50,
            color = C.card, radius = T.r.panel, border_width = 0 })
        W.glass(box, C.card, G.tile_opa)
        local ic = W.icon(box, { symbol = icon, x = 11, y = 12, size = 20, w = 26, h = 26,
            color = on and C.ok or C.text_dim })
        W.text_mid(box, { text = nm, x = 42, y = 0, w = 138, h = 50, size = 16, color = C.text,
            align = airui.TEXT_ALIGN_CENTER })
        local handle = {}
        local function render(v)                     -- 图标亮灭跟开关状态走
            pcall(function() ic:set_color(v and C.ok or C.text_dim) end)
            S.security[key] = v
            local chip = (key == "armed") and top_chips.arm or top_chips.lock
            if chip then chip.set(v, v and chip_on or chip_off) end
        end
        local sw = W.switch(box, { x = 180, y = 11, w = 50, h = 28, on = on, on_color = on_color,
            on_change = function(v)                  -- 仅用户点开关时触发
                render(v)
                toast(nm .. (v and " 已开启" or " 已关闭"))
            end })
        function handle.set(v, quiet)                -- 场景联动入口
            render(v)
            if sw then sw.set(v, false) end
            if not quiet then toast(nm .. (v and " 已开启" or " 已关闭")) end
        end
        return handle
    end
    SEC_UI.arm  = sec_row(40, "布防模式", S.security.armed,  C.ok,  "armed",  "在家布防", "已撤防", airui.SYMBOL_BELL)
    SEC_UI.lock = sec_row(98, "门锁",     S.security.locked, C.pri, "locked", "已上锁",   "已开锁", airui.SYMBOL_KEYBOARD)
    -- 窗户（只读提示行）
    local win = airui.container({ parent = p, x = 15, y = 156, w = 242, h = 50,
        color = C.card, radius = T.r.panel, border_width = 0 })
    W.glass(win, C.card, G.tile_opa)
    W.icon(win, { symbol = airui.SYMBOL_HOME, x = 11, y = 12, size = 20, w = 26, h = 26,
        color = C.warn })
    W.text_mid(win, { text = "窗户", x = 42, y = 0, w = 98, h = 50, size = 16, color = C.text,
        align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(win, { text = "1 处未关", x = 140, y = 0, w = 92, h = 50, size = 16,
        color = C.warn, align = airui.TEXT_ALIGN_RIGHT })
    -- 摄像头缩略卡
    local cam = airui.container({ parent = p, x = 15, y = 282, w = 242, h = 70,
        color = C.deep, radius = T.r.panel, border_width = 0 })
    W.glass(cam, C.deep, 160)
    W.icon(cam, { symbol = airui.SYMBOL_VIDEO, x = 12, y = 8, size = 22, w = 28, h = 28,
        color = C.danger })
    W.text_mid(cam, { text = "LIVE", x = 170, y = 8, w = 62, h = 24, size = 16,
        color = C.danger, weight = 700, align = airui.TEXT_ALIGN_RIGHT })
    W.text(cam, { text = "门口摄像头 1080P", x = 12, y = 38, w = 220, h = 30,
        size = 16, color = C.text_sub, align = airui.TEXT_ALIGN_CENTER })
    W.press_layer(p, { x = 15, y = 282, w = 242, h = 70, radius = T.r.panel,
        on_click = function() toast("打开门口摄像头画面") end })
    return g
end

-- ==================== 场景联动 ====================
-- 点底部场景 → 同步安防开关 + 当前房间设备矩阵。
-- lights/curtains 按设备类型前缀（"亮度 "/"开合 "）套用；all_off/all_on 覆盖全部；
-- tape_only 只保留灯带（观影）。armed/locked 与顶部芯片、右侧开关三方同步。
local SCENE_RULES = {
    ["回家"] = { armed = false, locked = false, lights = true,  curtains = true  },
    ["离家"] = { armed = true,  locked = true,  all_off = true                    },
    ["睡眠"] = { armed = true,  locked = true,  lights = false, curtains = false },
    ["观影"] = { armed = false, locked = true,  lights = false, curtains = false, tape_only = true },
    ["起床"] = { armed = false, locked = false, lights = true,  curtains = true  },
    ["会客"] = { armed = false, locked = false, all_on = true                     },
}

local function apply_scene(name)
    local rule = SCENE_RULES[name]
    if not rule then return end
    -- 安防：静默同步，不逐条弹提示（避免和场景提示打架）
    if rule.armed ~= nil and SEC_UI.arm then SEC_UI.arm.set(rule.armed, true) end
    if rule.locked ~= nil and SEC_UI.lock then SEC_UI.lock.set(rule.locked, true) end
    -- 设备：作用于当前房间
    local room = S.room()
    for _, d in ipairs(room.devs) do
        local is_light = (d.ds == "亮度 ")
        local is_curtain = (d.ds == "开合 ")
        if rule.all_off then
            d.on = false
        elseif rule.all_on then
            d.on = true
            if is_curtain then d.val = 100 end
        elseif rule.tape_only then
            d.on = is_light and (string.find(d.nm, "灯带", 1, true) ~= nil)
        else
            if is_light and rule.lights ~= nil then d.on = rule.lights end
            if is_curtain and rule.curtains ~= nil then
                d.on = rule.curtains
                d.val = rule.curtains and 100 or 0
            end
        end
    end
    apply_room(S.active, false)                      -- 磁贴原地刷新（无动画）
end

-- ==================== 底部场景 Dock ====================
local dock_items, dock_active = {}, 1

-- 场景 → 内置图标（回家/离家/睡眠/观影/起床/会客）
local SCENE_ICON = {
    ["回家"] = airui.SYMBOL_HOME,
    ["离家"] = airui.SYMBOL_DRIVE,
    ["睡眠"] = airui.SYMBOL_MUTE,
    ["观影"] = airui.SYMBOL_PLAY,
    ["起床"] = airui.SYMBOL_BELL,
    ["会客"] = airui.SYMBOL_CALL,
}

-- 高亮「当前执行的场景」：选中项主色底 + 主色文字 + 图标亮灭，其余回到常态
local function set_dock_active(i)
    dock_active = i
    for k, it in ipairs(dock_items) do
        local on = (k == i)
        W.glass(it.box, on and C.pri or C.card, on and 60 or G.tile_opa)
        pcall(function()
            it.lbl:set_color(on and C.pri or C.text)
            if it.ic then it.ic:set_color(on and C.pri or C.text_sub) end
        end)
    end
end

local function build_dock()
    local g = W.glass_card({ parent = ROOT, x = DOCK.x, y = DOCK.y, w = DOCK.w, h = DOCK.h,
        fade_in = true })
    handles[#handles + 1] = g
    local p = g.card
    local bw = math.floor((DOCK.w - 28 - 5 * 10) / 6)
    for i, name in ipairs(S.scenes) do
        local bx = 14 + (i - 1) * (bw + 10)
        local box = airui.container({ parent = p, x = bx, y = 11, w = bw, h = 54,
            color = C.card, radius = T.r.panel, border_width = 0 })
        W.glass(box, C.card, G.tile_opa)
        local hl = airui.container({ parent = box, x = 10, y = 1, w = bw - 20, h = 2,
            color = 0xFFFFFF, radius = 1, border_width = 0 })
        W.glass(hl, 0xFFFFFF, G.hl_opa)
        local ic = W.icon(box, { symbol = SCENE_ICON[name] or airui.SYMBOL_PLAY,
            x = 10, y = 16, size = 18, w = 24, h = 24, color = C.text_sub })
        local lbl = W.text_mid(box, { text = name, x = 34, y = 0, w = bw - 42, h = 54, size = 16,
            color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
        dock_items[#dock_items + 1] = { box = box, lbl = lbl, ic = ic }
        W.press_layer(p, { x = bx, y = 11, w = bw, h = 54, radius = T.r.panel,
            on_click = function()
                set_dock_active(i)                   -- 点谁高亮谁（之前写死第一项、点击不更新）
                W.tween(T.motion.sweep_fr, function(tt)
                    local opa = G.hl_opa + (G.hl_sweep_opa - G.hl_opa) * math.sin(tt * math.pi)
                    W.glass(hl, 0xFFFFFF, math.floor(opa))
                end)
                apply_scene(name)                    -- 场景联动：安防开关 + 当前房间设备
                toast("执行场景：" .. name)
            end })
    end
    set_dock_active(1)                               -- 初始高亮「回家」
end

-- ==================== 调档条（中栏底部常驻，替代屏幕级悬浮弹窗） ====================
-- 调节条常驻中栏底部空闲带（磁贴矩阵占到内容区 y=260，268~356 空闲），用透明度显隐。
-- 不能用 hide()/open()：容器 hide 能生效，但 open() 在真机上恢复不回来（调节条打开后
-- 一片空白 = 「调点不了」的直接原因），所以显隐只依赖 alpha；调节条的热区是 container，
-- alpha 0 时彻底不可见，且命中由闭包开关控制（关闭态点它无效，底下也只有面板背景）。
-- 视觉：不贴白底卡片（白 @200 在暗色界面里像一块灯箱），而是「凹陷控制条」——
-- 底比面板更暗一档（G.inset_opa），中间 −  数值  + 收进一条内嵌轨道（G.track_opa），
-- 按钮本体全透明只留青色符号，关闭降级为灰字幽灵按钮，层级一目了然。
local ADJ_OPA = G.inset_opa

popup_delta = function(dv)
    if not cur_dev then return end
    popup_set(cur_dev.val + dv, true)
end

popup_set = function(v, silent)
    if not cur_dev then return end
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    cur_dev.val = v
    pcall(function() popup.val:set_text(v .. "%") end)
    if cur_tile then refresh_tile(cur_dev, cur_tile) end
    if not silent then W.temp_pulse(popup.val) end
end

open_popup = function(d, t)
    if not popup then return end
    cur_dev, cur_tile = d, t
    popup_open = true
    for _, part in ipairs(popup.parts) do
        part.set_visible(true)
        part.set_disabled(false)
    end
    pcall(function()
        popup.nm:set_text(d.nm)
        popup.sub:set_text(d.ds or "")
        popup.val:set_text(d.val .. "%")
    end)
    W.glass(popup.g, C.deep, ADJ_OPA)
    W.glass(popup.bar, C.pri, 190)
    W.glass(popup.track, 0xFFFFFF, G.track_opa)
    W.temp_pulse(popup.val)
end

close_popup = function()
    if not popup or not popup_open then return end
    popup_open = false
    for _, part in ipairs(popup.parts) do part.set_disabled(true) end
    W.tween(3, function(tt)
        W.glass(popup.g, C.deep, math.floor(ADJ_OPA * (1 - tt)))
    end, function()
        for _, part in ipairs(popup.parts) do part.set_visible(false) end
        pcall(function() popup.nm:set_text(""); popup.sub:set_text(""); popup.val:set_text("") end)
        W.glass(popup.g, C.deep, 0)
        W.glass(popup.bar, C.pri, 0)
        W.glass(popup.track, 0xFFFFFF, 0)            -- 轨道也要归零，否则关闭后底部留一块浅色圆角
    end)
end

local function build_popup()
    local p = grids_parent
    local g = airui.container({ parent = p, x = 15, y = 268, w = 358, h = 84,
        color = C.deep, radius = T.r.panel, border_width = 0 })
    W.glass(g, C.deep, 0)
    -- 左：主色竖条（焦点）+ 设备名 + 类型（亮度/开合/风量，取自 d.ds 前缀）
    local bar = airui.container({ parent = g, x = 8, y = 22, w = 3, h = 40,
        color = C.pri, radius = 2, border_width = 0 })
    W.glass(bar, C.pri, 0)
    local nm = W.text(g, { text = "", x = 20, y = 14, w = 106, h = 26,
        size = 16, color = C.text, weight = 600 })
    local sub = W.text(g, { text = "", x = 20, y = 42, w = 106, h = 20,
        size = 16, color = C.text_dim })
    -- 中：−  数值  + 收进一条内嵌轨道，符号用主色，底不抢戏
    local track = airui.container({ parent = g, x = 128, y = 20, w = 152, h = 44,
        color = 0xFFFFFF, radius = 12, border_width = 0 })
    W.glass(track, 0xFFFFFF, 0)                      -- 初始归零：子容器不随父容器 alpha 走，必须自己关
    local val = W.text_mid(g, { text = "", x = 168, y = 0, w = 72, h = 84,
        size = 22, color = C.pri, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    local parts = {}
    parts[#parts + 1] = pill(g, { x = 132, y = 24, w = 36, h = 36, text = "-", size = 20,
        color = 0xFFFFFF, opa = 0, tcolor = C.pri,
        cb = function() popup_delta(-5) end })
    parts[#parts + 1] = pill(g, { x = 240, y = 24, w = 36, h = 36, text = "+", size = 20,
        color = 0xFFFFFF, opa = 0, tcolor = C.pri,
        cb = function() popup_delta(5) end })
    -- 右：关闭降级为灰字幽灵按钮（不再是一块白底）
    parts[#parts + 1] = pill(g, { x = 288, y = 22, w = 56, h = 40, text = "关闭", size = 16,
        color = 0xFFFFFF, opa = 0, tcolor = C.text_sub,
        cb = close_popup })
    for _, part in ipairs(parts) do
        part.set_visible(false)
        part.set_disabled(true)
    end
    popup = { g = g, bar = bar, track = track, nm = nm, sub = sub, val = val, parts = parts }
end

-- ==================== 房间切换 / 气候刷新 ====================
switch_room = function(i)
    close_popup()
    apply_room(i, true)
    toast("已切换到 " .. S.room().name)
end

update_climate = function(pulse)
    local room = S.room()
    pcall(function()
        lb_temp:set_text(S.fmt_temp(room.temp) .. "°C")
        lb_humi:set_text("湿度 " .. room.humi .. "%")
        lb_acst:set_text(room.ac_t .. "℃ " .. room.ac_mode)
        lb_ac_temp:set_text(room.ac_t .. "℃")
    end)
    paint_climate(room)                              -- 图形跟着数据走（趋势折线 + 湿度点阵）
    if pulse then W.temp_pulse(lb_temp) end
end

-- ==================== 时钟 ====================
local function update_clock()
    local t = os.time()
    local txt = (t and t > 1700000000) and os.date("%m-%d  %H:%M", t) or "时间待同步"
    if lbl_clock then pcall(function() lbl_clock:set_text(txt) end) end
end

-- ==================== 构建入口 ====================
function M.create(root)
    ROOT = root or airui.screen
    build_background()
    build_topbar()
    build_roombar()
    build_climate()
    build_devices()
    build_security()
    build_dock()
    build_popup()
    -- 初始房间与状态（磁贴直接落位，不播动画）
    apply_room(1, false)
    top_chips.arm.set(S.security.armed, S.security.armed and "在家布防" or "已撤防")
    top_chips.lock.set(S.security.locked, S.security.locked and "已上锁" or "已开锁")
    update_clock()
    W.enter(handles)                                     -- 模块依次淡入（零位移）
    S.start_sim()
    sys.timerLoopStart(function() update_climate(true) end, 5000)
    sys.timerLoopStart(update_clock, 20000)
    log.info("page_glass", "方案D 玻璃拟态页已创建，微动", T.motion.enabled and "开" or "关")
end

return M
