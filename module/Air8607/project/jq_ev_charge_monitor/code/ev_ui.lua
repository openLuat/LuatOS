--[[
@module  ev_ui
@summary 电车充电站实时状态大屏 UI（Air8607 10寸 1024x600，airui/LVGL9，科技简洁风）
@version 1.0
@date    2026.10.23

=== 布局 ===
  顶栏      y   0..68   LOGO 竖条 + 站名 + 空闲/充电中/已完成统计 + 时钟
  桩位区    y  78..390  5 列 x 2 行，每张卡 186x150
  控制区    y 398..584  左：定时播报（勾选 + 分钟调节 + 快捷档）
                       右：手动播报（点击弹浮层：输入框 + 拼音候选 + 键盘 + 常用短语）

=== 电池图形（每张卡一节）===
用 shape 画：外壳描边 + 正极凸起 + 5 个暗色凹槽 + 已充电量段。
电量段按 soc 连续推进（不是整格跳变）：第 i 段填充宽度 = 16 * ((soc-(i-1)*20)/20)，
正在充的那一段用更亮的 cyan_deep，于是充电时能看到"电量在格子里往前推"。
  idle     外壳灰蓝，无填充
  charging 外壳/电量青色，末段亮青
  done     外壳/电量荧光绿，满格

=== 关键 API 约束（踩坑记录）===
- label / bar / button / shape 都没有 set_hidden，只有 container 有；
  所以需按状态显隐的东西要包一层 container。本版电池整体就是一个 shape，
  直接用 set_items 重绘表达状态，无需显隐。
- shape 在 C 层移除了 CLICKABLE，叠在卡片上做高亮不会挡点击。
- 字库为固件内置 hzfont，中文最小字号 16，故全文 >=16。
]]
local cfg = require "ev_config"
local mgr = require "ev_manager"
local voice = require "ev_voice"
local pinyin = require "ev_pinyin"

local M = {}

local C = cfg.C
local L = cfg.LAYOUT
local SW, SH = cfg.HW.screen.w, cfg.HW.screen.h

local R = { cards = {}, stat = {}, breath = 0, built = false,
            manual_text = "", editing = false, cand_py = "", suppress = false }

-- 完成态高亮图元（复用，避免每秒新建表）
local hl_inner = { type = "rect", radius = 10, color = C.lime_deep, width = 2, fill = false, opacity = 255 }
local hl_halo = { type = "rect", radius = 12, color = C.lime, width = 3, fill = false, opacity = 60 }
local hl_list = { hl_inner, hl_halo }

-- ==================== 小工具 ====================
local function label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = size or 16,
        color = color or C.text, align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opacity or 255, radius = radius or 0,
        border_width = 0,
    })
end

--[[秒数格式化：小于 1 小时 mm:ss，超过 h:mm:ss]]
local function fmt_dur(s)
    s = math.floor(s or 0)
    if s < 0 then s = 0 end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
    return string.format("%02d:%02d", m, sec)
end

--[[写一个矩形图元（每次把所有字段重写一遍，不依赖上一帧残留值）]]
local function rect_item(it, x, y, w, h, radius, color, filled, opacity)
    it.type = "rect"
    it.x, it.y, it.w, it.h = x, y, w, h
    it.radius = radius
    it.color = color
    it.fill_color = color
    it.fill = filled and true or false
    it.width = filled and 0 or 2
    it.opacity = 255
    it.fill_opacity = opacity or 255
    return it
end

-- 状态皮肤：main 用于状态竖条/圆点，deep 用于文字与描边，text 是状态名
local SKIN = {
    idle     = { main = C.slate, deep = C.slate_deep, text = "空闲" },
    charging = { main = C.cyan,  deep = C.cyan_deep,  text = "充电中" },
    done     = { main = C.lime,  deep = C.lime_deep,  text = "已完成" },
}

-- ==================== 背景 ====================
local function build_background()
    local items = {
        -- 底色 + 下沿略深，拉出一点纵深
        { type = "rect", x = 0, y = 0, w = SW, h = SH, fill = true, fill_color = C.bg, color = C.bg, width = 0 },
        { type = "rect", x = 0, y = 360, w = SW, h = SH - 360, fill = true,
          fill_color = C.bg2, color = C.bg2, width = 0, fill_opacity = 160 },
        -- 右上主光斑（科技冷光）
        { type = "ellipse", cx = 900, cy = -20, rx = 340, ry = 240,
          color = C.cyan, width = 0, fill = true, fill_color = C.cyan, fill_opacity = 16 },
        -- 左下弱光斑
        { type = "ellipse", cx = 60, cy = 600, rx = 300, ry = 200,
          color = C.cyan, width = 0, fill = true, fill_color = C.cyan, fill_opacity = 10 },
        -- 极淡网格，只负责"科技感"，不抢内容
        { type = "line", x1 = 205, y1 = 0, x2 = 205, y2 = SH, color = C.line, width = 1, opacity = 10 },
        { type = "line", x1 = 410, y1 = 0, x2 = 410, y2 = SH, color = C.line, width = 1, opacity = 10 },
        { type = "line", x1 = 615, y1 = 0, x2 = 615, y2 = SH, color = C.line, width = 1, opacity = 10 },
        { type = "line", x1 = 820, y1 = 0, x2 = 820, y2 = SH, color = C.line, width = 1, opacity = 10 },
        { type = "line", x1 = 0, y1 = 300, x2 = SW, y2 = 300, color = C.line, width = 1, opacity = 8 },
        { type = "line", x1 = 0, y1 = 396, x2 = SW, y2 = 396, color = C.line, width = 1, opacity = 8 },
    }
    airui.shape({ x = 0, y = 0, w = SW, h = SH, items = items })
end

-- ==================== 顶栏 ====================
local function build_top()
    -- 顶栏只靠一条细线收边，保持"简洁"
    airui.shape({
        x = 0, y = 0, w = SW, h = L.top_h,
        items = {
            { type = "rect", x = 0, y = 0, w = SW, h = L.top_h, fill = true,
              fill_color = C.panel, color = C.panel, width = 0, fill_opacity = 120 },
            { type = "rect", x = 0, y = L.top_h - 1, w = SW, h = 1, fill = true,
              fill_color = C.line2, color = C.line2, width = 0 },
            { type = "rect", x = 20, y = 16, w = 3, h = 36, fill = true,
              fill_color = C.cyan, color = C.cyan, width = 0, radius = 2 },
        },
    })

    label(nil, 32, 6, 340, 30, "电动汽车充电站", 22, C.text)
    label(nil, 32, 38, 360, 22, "EV CHARGING MONITOR · A 区 10 车位", 16, C.text3)

    -- 三个统计块：数字在上、标签在下，用间距分组，不加底色块
    local defs = {
        { key = "idle",     tag = "空闲",   color = C.slate_deep },
        { key = "charging", tag = "充电中", color = C.cyan_deep },
        { key = "done",     tag = "已完成", color = C.lime_deep },
    }
    for i, d in ipairs(defs) do
        local x = 500 + (i - 1) * 112
        R.stat[d.key] = label(nil, x, 4, 104, 30, "0", 22, d.color)
        label(nil, x, 34, 104, 22, d.tag, 16, C.text3)
    end

    R.clock = label(nil, 850, 4, 154, 30, "--:--", 22, C.text, airui.TEXT_ALIGN_RIGHT)
    R.date = label(nil, 850, 34, 154, 22, "营业中", 16, C.text3, airui.TEXT_ALIGN_RIGHT)
end

-- ==================== 电池 ====================
--[[重绘某张卡的电池
只有 soc / 状态变化时才真正重绘，避免每秒无谓的 canvas 刷新]]
local function update_battery(r, p)
    local soc = p.soc or 0
    if soc < 0 then soc = 0 elseif soc > 100 then soc = 100 end
    if r._soc == soc and r._status == p.status then return end
    r._soc, r._status = soc, p.status

    local shell_col = C.line2
    local fill_col = nil
    if p.status == "charging" then
        shell_col, fill_col = C.cyan, C.cyan
    elseif p.status == "done" then
        shell_col, fill_col = C.lime, C.lime
    end

    local bi = r.bi
    local list = {}
    -- 外壳（描边）
    list[#list + 1] = rect_item(bi.shell, 0, 2, 100, 44, 7, shell_col, false)
    -- 正极凸起
    list[#list + 1] = rect_item(bi.cap, 100, 16, 7, 16, 2, shell_col, true)
    -- 5 个暗色凹槽先铺底，空电量也有"电池腔体"的观感
    for i = 1, 5 do
        list[#list + 1] = rect_item(bi.slot[i], 4 + (i - 1) * 19, 6, 16, 34, 3, C.bg, true)
    end
    -- 已充电量：按比例填进每一格
    if fill_col and soc > 0 then
        local cur_seg = math.floor(math.min(soc, 99.9) / 20) + 1
        for i = 1, 5 do
            local k = (soc - (i - 1) * 20) / 20
            if k > 0 then
                if k > 1 then k = 1 end
                local w = math.floor(16 * k + 0.5)
                if w < 2 then w = 2 end
                local col = fill_col
                if p.status == "charging" and i == cur_seg then col = C.cyan_deep end
                list[#list + 1] = rect_item(bi.fill[i], 4 + (i - 1) * 19, 6, w, 34, 3, col, true)
            end
        end
    end
    r.batt:set_items(list)
end

-- ==================== 一个充电桩卡片 ====================
local function build_card(i)
    local col = (i - 1) % 5
    local row = math.floor((i - 1) / 5)
    local cx = L.card_x + col * (L.card_w + L.gap_x)
    local cy = L.card_y + row * (L.card_h + L.gap_y)

    local card = airui.container({
        parent = nil, x = cx, y = cy, w = L.card_w, h = L.card_h,
        color = C.panel, color_opacity = 255, radius = 10,
        border_color = C.line, border_width = 1,
        on_click = function() mgr.toggle(i) end,
    })

    local r = { card = card, cx = cx, cy = cy, hl_on = false }
    r.bi = { shell = {}, cap = {}, slot = {}, fill = {} }
    for k = 1, 5 do
        r.bi.slot[k] = {}
        r.bi.fill[k] = {}
    end

    -- 左侧状态竖条
    r.chip = box(card, 0, 14, 3, 122, C.slate, 2, 255)

    r.lbNo = label(card, 14, 6, 44, 28, string.format("%02d", i), 20, C.text)
    r.lbBay = label(card, 58, 11, 48, 20, cfg.bay_name(i), 16, C.text2)
    r.dot = box(card, 110, 17, 6, 6, C.slate, 3, 255)
    r.lbState = label(card, 120, 10, 54, 22, "空闲", 16, C.slate_deep, airui.TEXT_ALIGN_RIGHT)

    -- 电池（局部坐标 0..110 x 0..48）
    r.batt = airui.shape({
        parent = card, x = L.batt_x, y = L.batt_y, w = L.batt_w, h = L.batt_h, items = {},
    })
    r.lbSoc = label(card, 124, 50, 50, 32, "0%", 22, C.text2, airui.TEXT_ALIGN_RIGHT)

    box(card, 12, 92, 162, 1, C.line, 0, 255)

    r.lbInfo = label(card, 12, 98, 162, 24, "", 18, C.text)
    r.lbFoot = label(card, 12, 124, 162, 20, "", 16, C.text3)

    R.cards[i] = r

    -- 完成态高亮：覆盖卡片外扩 4px，最后创建 => 浮在最上层
    r.hl = airui.shape({ x = cx - 4, y = cy - 4, w = L.card_w + 8, h = L.card_h + 8, items = {} })
    return r
end

-- ==================== 底部：定时播报 ====================
local function build_timer_panel(parent)
    label(parent, 20, 11, 104, 24, "定时播报", 18, C.text)
    label(parent, 124, 13, 340, 22, "完成后按间隔重复提醒，直至车辆驶离", 16, C.text3)

    -- 自绘勾选框（container 可点击，选中填青 + 白色对勾）
    local chk = airui.container({
        parent = parent, x = 20, y = 46, w = 26, h = 26,
        color = C.panel2, color_opacity = 255, radius = 6,
        border_color = C.line2, border_width = 1,
        on_click = function()
            mgr.set_timer(not mgr.timer_on)
            M.refresh_timer()
        end,
    })
    R.chk = chk
    R.chkTick = airui.shape({ parent = parent, x = 20, y = 46, w = 26, h = 26, items = {} })

    label(parent, 56, 47, 160, 22, "勾选后按间隔提醒", 16, C.text)

    label(parent, 20, 84, 44, 22, "间隔", 16, C.text2)

    local function step_btn(x, txt, delta)
        local b = airui.container({
            parent = parent, x = x, y = 80, w = 32, h = 30,
            color = C.panel2, color_opacity = 255, radius = 6,
            border_color = C.line2, border_width = 1,
            on_click = function()
                mgr.set_interval(mgr.interval_min + delta)
                M.refresh_timer()
            end,
        })
        label(b, 0, 3, 32, 22, txt, 18, C.text2, airui.TEXT_ALIGN_CENTER)
        return b
    end
    step_btn(64, "-", -1)
    R.lbMin = label(parent, 98, 80, 48, 30, "10", 20, C.cyan_deep, airui.TEXT_ALIGN_CENTER)
    step_btn(148, "+", 1)
    label(parent, 184, 84, 40, 22, "分钟", 16, C.text2)

    for i, m in ipairs(cfg.QUICK_MINUTES) do
        local x = 228 + (i - 1) * 50
        local b = airui.container({
            parent = parent, x = x, y = 80, w = 44, h = 30,
            color = C.panel2, color_opacity = 255, radius = 6,
            border_color = C.line2, border_width = 1,
            on_click = function()
                mgr.set_interval(m)
                M.refresh_timer()
            end,
        })
        label(b, 0, 3, 44, 22, tostring(m), 16, C.text2, airui.TEXT_ALIGN_CENTER)
    end

    R.lbTimerState = label(parent, 20, 118, 440, 22, "当前无待提醒车辆", 16, C.text3)
    R.lbVoiceState = label(parent, 20, 142, 440, 22, "语音：离线合成", 16, C.text3)

    box(parent, 470, 20, 1, 146, C.line, 0, 255)
end

-- ==================== 底部：手动播报 ====================
--[[手动播报内容显示区
这里刻意不放 textarea：键盘从底部弹出会正好盖住这块 440~492 的区域，
用户看不到自己打了什么。改成"可点击的显示框 + 中部编辑浮层"，
点一下就在屏幕中间弹出一个大输入框，键盘在它下方，内容始终可见。]]
local function build_manual_panel(parent)
    label(parent, 500, 11, 104, 24, "手动播报", 18, C.text)
    label(parent, 608, 13, 300, 22, "输入内容后点击播报，可随时停止", 16, C.text3)

    local ib = airui.container({
        parent = parent, x = 500, y = 42, w = 290, h = 52,
        color = C.panel2, color_opacity = 255, radius = 8,
        border_color = C.line2, border_width = 1,
        on_click = function() M.open_edit() end,
    })
    R.inputText = label(ib, 12, 15, 266, 24, "点击输入播报内容…", 16, C.text3)

    airui.button({
        parent = parent, x = 796, y = 42, w = 80, h = 52,
        text = "播报", font_size = 18,
        style = {
            bg_color = C.cyan, bg_opa = 255, text_color = 0x04202A, radius = 8,
            border_width = 1, border_color = C.cyan_deep,
            pressed_bg_color = C.cyan_deep, pressed_text_color = 0x04202A,
        },
        on_click = function() M.say_manual() end,
    })

    airui.button({
        parent = parent, x = 882, y = 42, w = 80, h = 52,
        text = "停止", font_size = 18,
        style = {
            bg_color = C.panel2, bg_opa = 255, text_color = C.text2, radius = 8,
            border_width = 1, border_color = C.line2,
            pressed_bg_color = C.lime_soft, pressed_text_color = C.lime_deep,
        },
        on_click = function() voice.stop() end,
    })

    -- 常用短语：显示短标签，点击把完整句子填进输入框
    local short = { "请勿占用车位", "请及时驶离", "本区即将闭站", "祝您出行愉快" }
    for i, s in ipairs(short) do
        airui.button({
            parent = parent, x = 500 + (i - 1) * 118, y = 102, w = 110, h = 28,
            text = s, font_size = 16,
            style = {
                bg_color = C.panel2, bg_opa = 255, text_color = C.text2, radius = 6,
                border_width = 1, border_color = C.line,
                pressed_bg_color = C.cyan_soft, pressed_text_color = C.cyan_deep,
            },
            on_click = function()
                M.set_manual_text(cfg.QUICK_PHRASES[i])
            end,
        })
    end

    label(parent, 500, 140, 462, 22, "提示：点卡片可切换 空闲 / 充电 / 完成 / 驶离", 16, C.text3)
end

-- ==================== 输入浮层 + 键盘 ====================
--[[编辑浮层
键盘（高 220）从底部弹出，浮层放在 150~330，自上而下是
标题 / 输入框 / 候选词行 / 操作按钮，四段互不遮挡。
候选词行是本工程自带的拼音输入（ev_pinyin），不依赖固件词库。]]
local function build_edit_overlay()
    -- 遮罩：点击空白处即"完成"并收起（保留已输入内容）
    R.mask = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 150, radius = 0, border_width = 0,
        on_click = function() M.close_edit() end,
    })
    R.mask:set_hidden(true)

    local card = airui.container({
        parent = nil, x = 262, y = 150, w = 500, h = 180,
        color = C.panel, color_opacity = 255, radius = 12,
        border_color = C.cyan, border_width = 1,
    })
    R.editCard = card
    card:set_hidden(true)

    label(card, 24, 10, 220, 24, "手动播报内容", 18, C.text)
    label(card, 220, 12, 256, 22, "打拼音，点候选词上屏", 16, C.text3)

    R.editTa = airui.textarea({
        parent = card, x = 24, y = 38, w = 452, h = 56,
        text = "", placeholder = "输入拼音后点候选词，或直接输入英文数字",
        font = "hzfont", font_size = 16,
        style = { bg_color = C.panel2, text_color = C.text, radius = 8, font_size = 16 },
    })
    R.editTa:set_on_text_change(function()
        if R.suppress then return end
        M.update_candidates()
    end)

    -- 候选词：固定 6 个坑位，按需显示/隐藏（label 本身不能隐藏，所以包一层 container）
    R.cands = {}
    for i = 1, 6 do
        local c = airui.container({
            parent = card, x = 24 + (i - 1) * 76, y = 98, w = 70, h = 28,
            color = C.panel2, color_opacity = 255, radius = 6,
            border_color = C.cyan, border_width = 1,
            on_click = function() M.pick_candidate(i) end,
        })
        c:set_hidden(true)
        R.cands[i] = {
            box = c,
            lb = label(c, 0, 3, 70, 22, "", 16, C.cyan_deep, airui.TEXT_ALIGN_CENTER),
            word = "",
        }
    end

    airui.button({
        parent = card, x = 24, y = 132, w = 100, h = 34,
        text = "清除", font_size = 16,
        style = {
            bg_color = C.panel2, bg_opa = 255, text_color = C.text2, radius = 6,
            border_width = 1, border_color = C.line2,
            pressed_bg_color = C.cyan_soft, pressed_text_color = C.cyan_deep,
        },
        on_click = function()
            if R.editTa then R.editTa:set_text("") end
            M.clear_candidates()
        end,
    })

    airui.button({
        parent = card, x = 132, y = 132, w = 130, h = 34,
        text = "播报", font_size = 16,
        style = {
            bg_color = C.cyan, bg_opa = 255, text_color = 0x04202A, radius = 6,
            border_width = 1, border_color = C.cyan_deep,
            pressed_bg_color = C.cyan_deep, pressed_text_color = 0x04202A,
        },
        on_click = function()
            -- 先落盘再播报，浮层保持打开，方便改完再播
            if R.editTa then M.set_manual_text(R.editTa:get_text() or "") end
            M.say_manual()
        end,
    })

    airui.button({
        parent = card, x = 270, y = 132, w = 130, h = 34,
        text = "完成", font_size = 16,
        style = {
            bg_color = C.panel2, bg_opa = 255, text_color = C.text, radius = 6,
            border_width = 1, border_color = C.cyan,
            pressed_bg_color = C.cyan_soft, pressed_text_color = C.cyan_deep,
        },
        on_click = function() M.close_edit() end,
    })
end

--[[共享键盘
必须最后创建：z 序最高，遮罩和浮层才不会挡住键盘。
mode 用 text（纯字母/数字）：中文由 ev_pinyin 的候选词行上屏。
不用 pinyin_26 的原因见 ev_pinyin.lua 头部——固件没开 LUAT_USE_PINYIN 时
airui 的 IME 没有词库，候选永远是空的，等于打不出中文。]]
local function build_keyboard()
    R.kb = airui.keyboard({
        w = SW, h = 220, mode = "text",
        auto_hide = false, preview = false,
        bg_color = C.panel2, font_size = 18,
        on_commit = function() M.close_edit() end,
    })
    -- auto_hide=false 时键盘创建后是显示态，必须手动收起
    if R.kb then R.kb:hide() end
end

-- ==================== 构建 ====================
--[[构建整屏 UI
每个分区单独 pcall：某个控件参数不被当前固件支持时只失去该分区，
不会因为一处异常导致整屏空白。]]
function M.build()
    if R.built then return end
    R.built = true

    local function try(what, fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then log.error("ev_ui", "构建失败:" .. what, err) end
    end

    try("背景", build_background)
    try("顶栏", build_top)
    for i = 1, cfg.PILE_COUNT do
        try("桩位" .. i, build_card, i)
    end

    local panel = airui.container({
        parent = nil, x = L.panel_x, y = L.panel_y, w = L.panel_w, h = L.panel_h,
        color = C.panel, color_opacity = 255, radius = 12,
        border_color = C.line, border_width = 1,
    })
    if panel then
        try("定时播报区", build_timer_panel, panel)
        try("手动播报区", build_manual_panel, panel)
    end

    -- 顺序有讲究：遮罩/浮层要盖住常规界面，键盘要盖住遮罩，所以从小到大依次创建
    try("输入浮层", build_edit_overlay)
    try("键盘", build_keyboard)

    mgr.on_change(function(pile) M.refresh_card(pile) end)
    M.refresh_all()
end

-- ==================== 单卡刷新 ====================
-- 充电态里变化最快的两个数，单卡刷新与整屏刷新共用同一份格式
local function update_charging_text(r, p)
    r.lbSoc:set_text(string.format("%d%%", math.floor(p.soc + 0.5)))
    r.lbFoot:set_text(string.format("%.1fkWh · %s", p.kwh, fmt_dur(mgr.charge_seconds(p.id))))
end

function M.refresh_card(p)
    local r = R.cards[p.id]
    if not r then return end
    local sk = SKIN[p.status] or SKIN.idle

    r.chip:set_color(sk.main, 255)
    r.dot:set_color(sk.main, 255)
    r.lbState:set_text(sk.text)
    r.lbState:set_color(sk.deep)

    if p.status == "idle" then
        r.lbSoc:set_text("0%")
        r.lbSoc:set_color(C.text3)
        r.lbInfo:set_text("可充电")
        r.lbInfo:set_color(C.slate_deep)
        r.lbFoot:set_text("扫码 / 刷卡启动")
        r.lbFoot:set_color(C.text3)

    elseif p.status == "charging" then
        r.lbSoc:set_color(C.cyan_deep)
        r.lbInfo:set_text(string.format("%.1f kW", p.kw))
        r.lbInfo:set_color(C.cyan_deep)
        r.lbFoot:set_color(C.text3)
        update_charging_text(r, p)

    else    -- done
        r.lbSoc:set_text(string.format("%d%%", math.floor(p.soc + 0.5)))
        r.lbSoc:set_color(C.lime_deep)
        r.lbInfo:set_text("等待 " .. fmt_dur(mgr.stay_seconds(p.id)))
        r.lbInfo:set_color(C.lime_deep)
        r.lbFoot:set_text("请及时驶离 · 超时收费")
        r.lbFoot:set_color(C.lime)
    end

    update_battery(r, p)

    r.hl_on = (p.status == "done")
    if not r.hl_on then
        r.hl:set_items({})
    end
end

-- ==================== 计时类刷新 ====================
function M.refresh()
    local idle, charging, done = mgr.counts()
    if R.stat.idle then
        R.stat.idle:set_text(tostring(idle))
        R.stat.charging:set_text(tostring(charging))
        R.stat.done:set_text(tostring(done))
    end

    if R.clock and R.date then
        local t = os.date("*t")
        if t and t.year and t.year >= 2020 then
            R.clock:set_text(string.format("%02d:%02d", t.hour, t.min))
            R.date:set_text(string.format("%04d-%02d-%02d", t.year, t.month, t.day))
        else
            R.clock:set_text("--:--")
            R.date:set_text("营业中")
        end
    end

    for i, p in ipairs(mgr.piles) do
        local r = R.cards[i]
        if r then
            if p.status == "done" then
                r.lbInfo:set_text("等待 " .. fmt_dur(mgr.stay_seconds(p.id)))
            elseif p.status == "charging" then
                update_charging_text(r, p)
                update_battery(r, p)
            end
        end
    end

    M.refresh_timer()
end

-- ==================== 定时播报区刷新 ====================
function M.refresh_timer()
    if not (R.chk and R.chkTick and R.lbMin and R.lbTimerState and R.lbVoiceState) then return end

    local on = mgr.timer_on
    R.chk:set_color(on and C.cyan or C.panel2, 255)
    if on then
        R.chkTick:set_items({
            { type = "line", x1 = 6, y1 = 13, x2 = 11, y2 = 18, color = C.white, width = 3, round_end = true },
            { type = "line", x1 = 11, y1 = 18, x2 = 20, y2 = 7, color = C.white, width = 3, round_end = true },
        })
    else
        R.chkTick:set_items({})
    end

    R.lbMin:set_text(tostring(mgr.interval_min))

    local p = mgr.first_done()
    if not p then
        R.lbTimerState:set_text("当前无待提醒车辆")
        R.lbTimerState:set_color(C.text3)
    else
        local stay = fmt_dur(mgr.stay_seconds(p.id))
        if not on then
            R.lbTimerState:set_text(string.format("%d号桩已等待 %s，定时播报未开启", p.id, stay))
            R.lbTimerState:set_color(C.text3)
        else
            local left = mgr.next_say_in(p.id)
            R.lbTimerState:set_text(string.format("%d号桩已等待 %s，%s 后再次播报",
                p.id, stay, fmt_dur(left or 0)))
            R.lbTimerState:set_color(C.lime_deep)
        end
    end

    local n = select(3, mgr.counts())
    if voice.busy() then
        R.lbVoiceState:set_text("播报中…点击「停止」可打断")
        R.lbVoiceState:set_color(C.cyan_deep)
    elseif voice.available() then
        R.lbVoiceState:set_text(string.format("语音：离线合成 · 已完成 %d 台待驶离", n))
        R.lbVoiceState:set_color(C.text3)
    else
        R.lbVoiceState:set_text(string.format("语音：无音频硬件（日志播报）· 已完成 %d 台", n))
        R.lbVoiceState:set_color(C.amber)
    end
end

-- ==================== 完成态呼吸高亮 ====================
function M.refresh_breath()
    R.breath = (R.breath + 0.42) % (math.pi * 2)
    local k = 0.5 - 0.5 * math.cos(R.breath)     -- 0..1..0

    hl_inner.x, hl_inner.y = 2, 2
    hl_inner.w, hl_inner.h = L.card_w, L.card_h
    hl_inner.opacity = math.floor(150 + 105 * k)

    hl_halo.x, hl_halo.y = 0, 0
    hl_halo.w, hl_halo.h = L.card_w + 4, L.card_h + 4
    hl_halo.opacity = math.floor(35 + 55 * k)

    for i = 1, cfg.PILE_COUNT do
        local r = R.cards[i]
        if r and r.hl_on then
            r.hl:set_items(hl_list)
        end
    end
end

-- ==================== 拼音候选 ====================
local function hide_cands()
    if not R.cands then return end
    for i = 1, #R.cands do
        R.cands[i].word = ""
        R.cands[i].box:set_hidden(true)
    end
end

function M.clear_candidates()
    R.cand_py = ""
    hide_cands()
end

--[[刷新候选行
取输入框末尾连续的 a-z 串当拼音，交给 ev_pinyin 做精确/前缀匹配。
用 lower 只影响 ASCII（长度不变），所以用原始字符串的字节长度减掉拼音长度即可定位。]]
function M.update_candidates()
    if not (R.editTa and R.cands) then return end
    local txt = R.editTa:get_text() or ""
    local py = txt:lower():match("([a-z]+)$") or ""
    if #py > 18 then py = py:sub(-18) end
    R.cand_py = py

    hide_cands()
    if py == "" then return end

    local words = pinyin.lookup(py, #R.cands)
    for i = 1, #words do
        local slot = R.cands[i]
        if slot then
            slot.word = words[i]
            slot.lb:set_text(words[i])
            slot.box:set_hidden(false)
        end
    end
end

--[[点候选词上屏：把末尾拼音串替换成中文
set_text 会同步触发 on_text_change，用 suppress 挡掉一次，避免自我递归。]]
function M.pick_candidate(idx)
    local slot = R.cands and R.cands[idx]
    if not slot or slot.word == "" then return end
    local py = R.cand_py or ""
    if py == "" then return end
    local cur = R.editTa:get_text() or ""
    if #cur < #py then return end

    local new = cur:sub(1, #cur - #py) .. slot.word
    R.suppress = true
    R.editTa:set_text(new)      -- set_text 后 LVGL 光标自动落在末尾
    R.suppress = false
    R.cand_py = ""
    hide_cands()
end

-- ==================== 手动播报 ====================
--[[刷新面板上的输入内容显示
文本可能很长，label 只有一行高，超出部分自然被裁掉，但开头始终可见。]]
local function update_input_display()
    if not R.inputText then return end
    local txt = R.manual_text or ""
    if txt == "" then
        R.inputText:set_text("点击输入播报内容…")
        R.inputText:set_color(C.text3)
    else
        R.inputText:set_text(txt)
        R.inputText:set_color(C.text)
    end
end

--[[设置手动播报内容（常用短语按钮与编辑完成都走这里）]]
function M.set_manual_text(txt)
    txt = (txt or ""):gsub("[\r\n]+", " ")
    R.manual_text = txt
    update_input_display()
end

--[[打开编辑浮层：把已有内容带进大输入框，键盘从底部弹出]]
function M.open_edit()
    if not (R.mask and R.editCard and R.editTa and R.kb) then return end
    R.editing = true
    R.suppress = true
    R.editTa:set_text(R.manual_text or "")
    R.suppress = false
    M.clear_candidates()
    R.mask:set_hidden(false)
    R.editCard:set_hidden(false)
    R.kb:set_target(R.editTa)
    R.kb:show()
end

--[[关闭编辑浮层：保存文本、收起键盘]]
function M.close_edit()
    if not R.editing then return end
    R.editing = false
    if R.editTa then
        M.set_manual_text(R.editTa:get_text() or "")
    end
    M.clear_candidates()
    if R.kb then R.kb:hide() end
    if R.mask then R.mask:set_hidden(true) end
    if R.editCard then R.editCard:set_hidden(true) end
end

function M.say_manual()
    local txt = (R.manual_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if txt == "" then
        if R.lbVoiceState then
            R.lbVoiceState:set_text("还没有内容，点输入框先输入或点选常用短语")
            R.lbVoiceState:set_color(C.amber)
        end
        return
    end
    txt = txt:gsub("[\r\n]+", " ")   -- TTS 逐行读会卡顿，统一成空格
    voice.say(txt, "manual")
    if R.lbVoiceState then
        -- 不回显原文：中文字符按字节截断会切出半个字
        R.lbVoiceState:set_text("已提交手动播报，正在播放…")
        R.lbVoiceState:set_color(C.cyan_deep)
    end
end

--[[播报状态回调（由 main 注册给 voice）]]
function M.on_voice_state(speaking)
    if not R.lbVoiceState then return end
    if speaking then
        R.lbVoiceState:set_text("播报中…点击「停止」可打断")
        R.lbVoiceState:set_color(C.cyan_deep)
    else
        R.lbVoiceState:set_text("语音就绪")
        R.lbVoiceState:set_color(C.text3)
    end
end

function M.refresh_all()
    for _, p in ipairs(mgr.piles) do M.refresh_card(p) end
    M.refresh()
end

return M
