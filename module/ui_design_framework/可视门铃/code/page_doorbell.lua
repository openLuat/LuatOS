--[[
@module page_doorbell
@summary 可视门铃室内机主页面（与 doorbell_ui/preview.html 1:1 对应）
         单 exwin 页 + 6 个屏容器：首页 / 通话 / 监视 / 门口取景 / 消息 / 设置

         === 关键做法（实机验证过的 AirUI 用法）===
         1. 6 屏一次性建好，切屏只 set_hidden，绝不 destroy + 重建：
            重建会留残影、画面错位，而且慢。
         2. 屏内状态（rail 高亮 / 场景选中 / 布防 / 音量 / 摄像头）全部就地改属性
            （set_color / set_items / set_text / set_pos），不重建。
         3. 首页两屏用 airui.tabview(switch_mode="swipe", tabbar_size=0) 实现左右滑动。
         4. 弹层每次新建（弹层在 root 上、盖住所有屏），回调统一 defer 一拍再关。
]]

local sys   = require "sys"
local theme = require "theme"

local C   = theme.C
local W, H = theme.W, theme.H

local function defer(fn) sys.timerStart(fn, 30) end

--------------------------------------------------------------------
-- 全局状态（对应 preview.html 里的 S 对象）
--------------------------------------------------------------------
local S = {
    screen = "home",
    page = 1,                        -- 首页：1 四宫格 / 2 场景
    volume = 60,
    brightness = 70,
    armed = false,
    scene = "在家",
    num = "",
    mic = true,                      -- 取景页麦克风：true 开 / false 静音
    cam = 1,                         -- 摄像头索引
    unread = 2,
    msgs_cleared = false,
}

local ORDER = { "home", "call", "monitor", "live", "msg", "set" }

local root
local sc = {}                        -- 屏容器
local R  = { home = {}, call = {}, monitor = {}, live = {}, msg = {}, set = {} }
local build = {}
local show, redraw, refresh_dots

local overlay, toast_obj, toast_timer
local open_elevator, open_volume, open_user, open_drawer, open_about, dial
local toggle_arm, set_scene, pick_cam

--------------------------------------------------------------------
-- 时间
--------------------------------------------------------------------
local WK = { "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" }

local function clock_texts()
    local ok, t = pcall(os.date, "*t")
    if not ok or not t then return "--:--", "----" end
    local hm = string.format("%02d:%02d", t.hour or 0, t.min or 0)
    local dt = string.format("%d-%d-%d %s", t.year or 0, t.month or 0, t.day or 0,
        WK[t.wday or 1] or "")
    return hm, dt
end

-- 中文字宽估算（中文 1 字、ASCII 约 0.55 字），用于 toast 自适应宽度
local function text_w(s, unit)
    local n = 0
    if utf8 and utf8.codes then
        for _, code in utf8.codes(s) do
            n = n + ((code < 128) and 0.55 or 1)
        end
    else
        for i = 1, #s do
            local b = string.byte(s, i)
            if b < 128 then n = n + 0.55 elseif b >= 224 then n = n + 1 end
        end
    end
    return math.floor(n * (unit or 18) + 0.5)
end

--------------------------------------------------------------------
-- toast（底部居中，1.8s 消失）
--------------------------------------------------------------------
local function clear_toast()
    if toast_timer then sys.timerStop(toast_timer) toast_timer = nil end
    if toast_obj then pcall(toast_obj.destroy, toast_obj) toast_obj = nil end
end

local function toast(msg)
    clear_toast()
    local w = math.max(200, text_w(msg, 18) + 56)
    local h = 52
    local x = math.floor((W - w) / 2)
    local y = H - 96 - h
    toast_obj = theme.box_a(root, x, y, w, h, C.blk, 10, 240)
    theme.txt(toast_obj, 0, 0, w, h, msg, C.white, 18, airui.TEXT_ALIGN_CENTER)
    toast_timer = sys.timerStart(function()
        toast_timer = nil
        if toast_obj then pcall(toast_obj.destroy, toast_obj) toast_obj = nil end
    end, 1800)
end

--------------------------------------------------------------------
-- 弹层
--------------------------------------------------------------------
local function clear_overlay()
    if overlay then pcall(overlay.destroy, overlay) overlay = nil end
end

local function open_modal(mw, mh, builder)
    clear_overlay()
    overlay = theme.box_a(root, 0, 0, W, H, C.mask, 0, C.mask_opa)
    if overlay.set_on_click then
        overlay:set_on_click(function() defer(clear_overlay) end)
    end
    local mx = math.floor((W - mw) / 2)
    local my = math.floor((H - mh) / 2)
    local mb = theme.box(overlay, mx, my, mw, mh, C.dlg, 14)
    if mb.set_on_click then mb:set_on_click(function() end) end
    builder(mb, mw, mh)
    return mb
end

-- 弹层底部按钮（右对齐）
local function modal_btns(mb, mw, mh, list)
    local n   = #list
    local gap = 12
    local bw, bh = 150, 52
    local total = bw * n + gap * (n - 1)
    local x = mw - 24 - total
    local y = mh - 24 - bh
    for i, it in ipairs(list) do
        local bx = x + (i - 1) * (bw + gap)
        theme.btn(mb, bx, y, bw, bh, it[1], it[2], it[3], it[2], 0, 10,
            function() defer(it[4]) end)
    end
end

--------------------------------------------------------------------
-- 电梯呼梯
--------------------------------------------------------------------
local FLOORS = { "B1" }
for i = 1, 13 do FLOORS[#FLOORS + 1] = i .. "F" end

open_elevator = function()
    open_modal(520, 470, function(mb, mw, mh)
        theme.txt(mb, 24, 18, mw - 48, 34, "电梯呼梯", C.text, 22)
        theme.txt(mb, 24, 56, mw - 48, 26,
            "选择要呼叫的楼层，室内机将联动门口机呼梯。", C.sub, 18)
        for i, f in ipairs(FLOORS) do
            local col = (i - 1) % 5
            local row = math.floor((i - 1) / 5)
            local x = 24 + col * 96
            local y = 100 + row * 84
            theme.box_b(mb, x, y, 84, 72, C.card2, 10, C.line, 1)
            theme.txt(mb, x, y, 84, 72, f, C.text, 22, airui.TEXT_ALIGN_CENTER)
            theme.hit(mb, x, y, 84, 72, function()
                defer(function()
                    clear_overlay()
                    toast("电梯已呼至 " .. f)
                end)
            end)
        end
        modal_btns(mb, mw, mh, {
            { "取消", C.card2, C.text, function() clear_overlay() end },
        })
    end)
end

--------------------------------------------------------------------
-- 广播音量
--------------------------------------------------------------------
open_volume = function()
    open_modal(520, 300, function(mb, mw, mh)
        theme.txt(mb, 24, 18, mw - 48, 34, "广播音量", C.text, 22)
        theme.txt(mb, 24, 56, mw - 48, 26,
            "拖动调节室内机的提示音 / 广播音量。", C.sub, 18)
        theme.txt(mb, 24, 96, 200, 32, "音量", C.text, 19)
        local vlab = theme.txt(mb, mw - 24 - 152, 96, 152, 32,
            tostring(S.volume), C.orange, 24, airui.TEXT_ALIGN_RIGHT)
        theme.slider(mb, 24, 140, mw - 48, S.volume, function(self)
            local v = self:get_value()
            S.volume = v
            pcall(vlab.set_text, vlab, tostring(v))
        end)
        modal_btns(mb, mw, mh, {
            { "完成", C.orange, C.white, function()
                clear_overlay()
                if R.set.vol_val then
                    pcall(R.set.vol_val.set_text, R.set.vol_val, tostring(S.volume))
                end
                if R.home.vol then
                    pcall(R.home.vol.set_text, R.home.vol, tostring(S.volume))
                end
            end },
        })
    end)
end

--------------------------------------------------------------------
-- 呼叫住户（细线分隔列表，跟 html 一致）
--------------------------------------------------------------------
local USERS = {
    { "张先生", "1203 主卧" },
    { "李女士", "1201" },
    { "物业中心", "大堂" },
    { "门岗", "1F 门厅" },
}

open_user = function()
    open_modal(520, 430, function(mb, mw, mh)
        theme.txt(mb, 24, 18, mw - 48, 34, "呼叫住户", C.text, 22)
        for i, u in ipairs(USERS) do
            local y = 62 + (i - 1) * 68
            theme.circle(mb, 24, y + 12, 40, C.card2)
            theme.txt(mb, 24, y + 12, 40, 40, string.sub(u[1], 1, 3),
                C.blue, 17, airui.TEXT_ALIGN_CENTER)
            theme.txt(mb, 76, y, 240, 64, u[1], C.text, 19)
            theme.txt(mb, 300, y, mw - 324, 64, u[2], C.sub, 17,
                airui.TEXT_ALIGN_RIGHT)
            theme.box(mb, 24, y + 64, mw - 48, 1, C.line, 0)
            theme.hit(mb, 24, y, mw - 48, 66, function()
                defer(function()
                    clear_overlay()
                    dial(u[1])
                end)
            end)
        end
        modal_btns(mb, mw, mh, {
            { "取消", C.card2, C.text, function() clear_overlay() end },
        })
    end)
end

--------------------------------------------------------------------
-- 全部功能（4 列抽屉）
--------------------------------------------------------------------
open_drawer = function()
    local apps = {
        { "通话", "phone",    C.tile_call, function() show("call") end },
        { "消息", "chat",     C.tile_msg,  function() show("msg") end },
        { "监视", "eye",      C.tile_mon,  function() show("monitor") end },
        { "设置", "gear",     C.tile_set,  function() show("set") end },
        { "电梯", "elevator", 0x6B8CFF,    function() open_elevator() end },
        { "音量", "volume",   C.orange,    function() open_volume() end },
        { "布防", "shield",   C.green2,    function() toggle_arm() end },
        { "主题", "moon",     C.purple,    function()
            theme.toggle_theme()
            redraw()
        end },
    }
    open_modal(600, 440, function(mb, mw, mh)
        theme.txt(mb, 24, 18, mw - 48, 34, "全部功能", C.text, 22)
        local cw = math.floor((mw - 48) / 4)          -- 列宽按弹窗宽度均分
        for i, a in ipairs(apps) do
            local col = (i - 1) % 4
            local row = math.floor((i - 1) / 4)
            local cx = 24 + col * cw
            local cy = 74 + row * 142
            local ic = math.floor((cw - 104) / 2)     -- 图标块在列内居中
            theme.box(mb, cx + ic, cy, 104, 104, a[3], 30)
            theme.icon(mb, cx + ic + 24, cy + 24, 56, a[2], C.white, a[3])
            theme.txt(mb, cx, cy + 112, cw, 26, a[1], C.text, 18,
                airui.TEXT_ALIGN_CENTER)
            theme.hit(mb, cx, cy, cw, 138, function()
                defer(function()
                    clear_overlay()
                    a[4]()
                end)
            end)
        end
        modal_btns(mb, mw, mh, {
            { "关闭", C.card2, C.text, function() clear_overlay() end },
        })
    end)
end

--------------------------------------------------------------------
-- 关于本机
--------------------------------------------------------------------
open_about = function()
    open_modal(520, 330, function(mb, mw, mh)
        theme.txt(mb, 24, 18, mw - 48, 34, "关于本机", C.text, 22)
        local lines = {
            "型号：海康威视 可视对讲室内机",
            "主控：Air8603 · 1024×600",
            "固件：LuatOS V1028",
            "UI 框架：airui（1:1 预览稿）",
        }
        for i, s in ipairs(lines) do
            theme.txt(mb, 24, 60 + (i - 1) * 38, mw - 48, 30, s, C.sub, 18)
        end
        modal_btns(mb, mw, mh, {
            { "知道了", C.orange, C.white, function() clear_overlay() end },
        })
    end)
end

--------------------------------------------------------------------
-- 正在呼叫（2.6 秒后自动接听进入取景）
--------------------------------------------------------------------
local dial_timer

dial = function(target)
    local who = target or ((S.num ~= "") and ("房号 " .. S.num) or "主单元门口机")
    if dial_timer then sys.timerStop(dial_timer) dial_timer = nil end
    open_modal(520, 300, function(mb, mw, mh)
        theme.txt(mb, 0, 18, mw, 34, "正在呼叫", C.text, 22, airui.TEXT_ALIGN_CENTER)
        theme.txt(mb, 0, 80, mw, 40, who, C.text, 24, airui.TEXT_ALIGN_CENTER)
        theme.txt(mb, 0, 132, mw, 28, "请稍候，正在建立可视对讲连接…", C.sub, 18,
            airui.TEXT_ALIGN_CENTER)
        modal_btns(mb, mw, mh, {
            { "取消", C.card2, C.text, function()
                if dial_timer then sys.timerStop(dial_timer) dial_timer = nil end
                clear_overlay()
            end },
            { "挂断", C.red, C.white, function()
                if dial_timer then sys.timerStop(dial_timer) dial_timer = nil end
                clear_overlay()
                toast("已挂断")
            end },
        })
    end)
    dial_timer = sys.timerStart(function()
        dial_timer = nil
        if overlay then
            clear_overlay()
            show("live")
            toast("对方已接听，进入取景画面")
        end
    end, 2600)
end

--------------------------------------------------------------------
-- 局部状态更新（不重建控件）
--------------------------------------------------------------------
toggle_arm = function()
    S.armed = not S.armed
    if R.home.shield then
        theme.set_icon(R.home.shield, "shield", 24,
            S.armed and C.red2 or C.green2, C.bg)
    end
    if R.set.sw_track then
        theme.set_switch(R.set.sw_track, R.set.sw_dot, 16 + 992 - 18 - 62,
            364 + 15, S.armed)
    end
    toast(S.armed and "已布防：门窗磁、移动侦测全部生效" or "已撤防")
end

set_scene = function(name)
    S.scene = name
    for i, s in ipairs(R.home.scenes or {}) do
        local on = (s.name == name)
        pcall(s.ring.set_color, s.ring, on and C.orange or C.card, 255)
    end
    toast("已切换到 「" .. name .. "」 场景")
end

pick_cam = function(i)
    S.cam = i
    local CAMS = R.monitor.cams
    for k, chip in ipairs(CAMS) do
        pcall(chip.set_color, chip, (k == i) and C.orange2 or C.chip,
            (k == i) and 255 or C.chip_opa)
    end
    if R.monitor.name then
        pcall(R.monitor.name.set_text, R.monitor.name,
            ({ "主单元门口机", "仓库枪机 01", "仓库球机 02" })[i])
    end
    if R.live.name then
        pcall(R.live.name.set_text, R.live.name,
            ({ "主单元门口机", "仓库枪机 01", "仓库球机 02" })[i])
    end
    if R.monitor.tag then
        pcall(R.monitor.tag.set_text, R.monitor.tag,
            ({ "IPC", "IPC-01", "IPC-02" })[i])
    end
    toast("已切换到 " .. ({ "主单元门口机", "仓库枪机 01", "仓库球机 02" })[i])
end

--------------------------------------------------------------------
-- 背光亮度：PWM3（main.lua 里已 open/setup，这里只需改占空比）
-- setDuty 只在 start/open 状态下生效；万一没启动过就兜底 setup + start
-- 拖动每帧都回调，这里做 60ms 节流，避免高频刷 PWM 造成闪烁
--------------------------------------------------------------------
local bl_timer

local function set_backlight(v)
    v = math.floor(v)
    if v < 10 then v = 10 end          -- 下限 10%，拖到 0 会直接黑屏
    if v > 100 then v = 100 end
    if bl_timer then sys.timerStop(bl_timer) end
    bl_timer = sys.timerStart(function()
        bl_timer = nil
        local ok, ret = pcall(pwm.setDuty, 3, v)
        if ok and ret then return end
        pcall(pwm.setup, 3, 1000, 100)
        pcall(pwm.start, 3)
        pcall(pwm.setDuty, 3, v)
    end, 60)
end

--------------------------------------------------------------------
-- 通用标题栏
--------------------------------------------------------------------
local function titlebar(p, title, right_text, on_right)
    theme.box(p, 0, 0, W, 62, C.card)
    theme.box(p, 0, 61, W, 1, C.line)
    theme.icon(p, 26, 19, 24, "back", C.sub)
    theme.hit(p, 18, 11, 40, 40, function() show("home") end)
    if title then
        theme.txt(p, 68, 11, W - 136, 40, title, C.text, 20,
            airui.TEXT_ALIGN_CENTER)
    end
    if right_text then
        theme.txt(p, W - 18 - 96, 11, 96, 40, right_text, C.sub, 17,
            airui.TEXT_ALIGN_RIGHT)
        theme.hit(p, W - 118, 11, 100, 40, on_right)
    end
end

--------------------------------------------------------------------
-- 屏 1：首页
--------------------------------------------------------------------
local TILES = {
    { x = 40,  name = "通话", icon = "phone", s = 76, key = "tile_call", to = "call" },
    { x = 276, name = "消息", icon = "chat",  s = 76, key = "tile_msg",  to = "msg" },
    { x = 512, name = "监视", icon = "eye",   s = 80, key = "tile_mon",  to = "monitor" },
    { x = 748, name = "设置", icon = "gear",  s = 78, key = "tile_set",  to = "set" },
}

local SCENES = {
    { x = 40,  name = "在家",   icon = "home", col = "blue2" },
    { x = 276, name = "外出",   icon = "car",  col = "blue2" },
    { x = 512, name = "睡眠",   icon = "moon", col = "orange" },
    { x = 748, name = "自定义", icon = "bars", col = "blue2" },
}

-- 分页圆点：两组（第 1 屏左长右短 / 第 2 屏左短右长），切换靠 set_hidden
-- 注意：子控件不能超出父容器（会被裁剪），所以每个圆点都独立建在屏上
refresh_dots = function()
    if not R.dots then return end
    local p1 = (S.page == 1)
    for i, d in ipairs(R.dots) do
        pcall(d.set_hidden, d, (i <= 2) ~= p1)
    end
end

build.home = function(p)
    theme.box(p, 0, 0, W, H, C.bg)

    -- 主题切换（只放在首页）
    theme.box_a(p, 20, 14, 44, 44, C.pin, 22, C.pin_opa)
    theme.icon(p, 26, 20, 32, (theme.cur == "dark") and "moon" or "sun",
        C.text, C.bg)
    theme.hit(p, 20, 14, 44, 44, function()
        theme.toggle_theme()
        redraw()
    end)

    -- 状态栏
    theme.icon(p, 864, 24, 24, "user", C.icon)
    theme.hit(p, 858, 18, 36, 36, function() open_user() end)

    R.home.shield = theme.icon(p, 918, 24, 24, "shield",
        S.armed and C.red2 or C.green2, C.bg)
    theme.hit(p, 912, 18, 36, 36, function() toggle_arm() end)

    theme.icon(p, 972, 24, 24, "grid", C.icon)
    theme.hit(p, 966, 18, 36, 36, function() open_drawer() end)

    -- 时钟 / 日期
    local hm, dt = clock_texts()
    R.home.clock = theme.txt(p, 52, 50, 440, 100, hm, C.text, 84)
    R.home.date  = theme.txt(p, 56, 158, 460, 32, dt, C.sub, 20)

    -- 快捷：电梯 / 音量
    theme.box_a(p, 782, 124, 62, 62, C.pin, 31, C.pin_opa)
    theme.icon(p, 798, 140, 30, "elevator", C.icon)
    theme.hit(p, 782, 124, 62, 62, function() open_elevator() end)

    theme.box_a(p, 866, 124, 62, 62, C.pin, 31, C.pin_opa)
    theme.icon(p, 882, 140, 30, "volume", C.icon)
    theme.box(p, 906, 162, 28, 26, C.card, 13)
    R.home.vol = theme.txt(p, 906, 162, 28, 26, tostring(S.volume), C.icon, 16,
        airui.TEXT_ALIGN_CENTER)
    theme.hit(p, 866, 124, 68, 70, function() open_volume() end)

    -- 两屏（可左右滑动）
    local tv = airui.tabview({
        parent = p, x = 0, y = 276, w = W, h = 272,
        tabs = { "a", "b" }, active = S.page - 1,
        switch_mode = "swipe",
        page_style = {
            tabbar_size = 0,                     -- 隐藏 tab 栏（靠滑动）
            pad = { method = 0, value = 0 },      -- 页面内边距清零，坐标=屏幕坐标
            bg_opa = 255,
            bg_color = C.bg,
        },
    })
    R.home.tv = tv

    -- 第 1 屏：四宫格
    local pg1 = tv:get_content(0)
    theme.box(pg1, 0, 0, W, 272, C.bg)
    for _, t in ipairs(TILES) do
        theme.box(pg1, t.x, 30, 190, 190, C[t.key], 54)
        local ic = math.floor((190 - t.s) / 2)
        theme.icon(pg1, t.x + ic, 30 + ic, t.s, t.icon, C.white, C[t.key])
        theme.txt(pg1, t.x, 236, 190, 30, t.name, C.text, 22,
            airui.TEXT_ALIGN_CENTER)
        theme.hit(pg1, t.x, 30, 190, 236, function() show(t.to) end)
    end
    -- 未读角标：label 没有 set_hidden，必须包一层容器才能隐藏
    -- 方块右边缘 466 / 上边缘 30，角标整体挪到方块右上外侧，不与图标重叠
    local badge = theme.box_b(pg1, 470, 22, 34, 34, C.red2, 17, 0xF7A92B, 3)
    theme.txt(badge, 0, 0, 34, 34, tostring(S.unread), C.white, 18,
        airui.TEXT_ALIGN_CENTER)
    R.home.badge = badge
    if S.unread <= 0 then pcall(badge.set_hidden, badge, true) end

    -- 第 2 屏：场景
    local pg2 = tv:get_content(1)
    theme.box(pg2, 0, 0, W, 272, C.bg)
    R.home.scenes = {}
    for _, s in ipairs(SCENES) do
        local on = (S.scene == s.name)
        local ring = theme.circle(pg2, s.x, 30, 190, on and C.orange or C.card)
        theme.circle(pg2, s.x + 4, 34, 182, C.card)
        theme.icon(pg2, s.x + 62, 92, 66, s.icon, C[s.col], C.card)
        theme.txt(pg2, s.x, 236, 190, 30, s.name, C.text, 22,
            airui.TEXT_ALIGN_CENTER)
        theme.hit(pg2, s.x, 30, 190, 236, function() set_scene(s.name) end)
        R.home.scenes[#R.home.scenes + 1] = { name = s.name, ring = ring }
    end

    tv:set_on_change(function(_, idx)
        S.page = idx + 1
        refresh_dots()
    end)

    -- 分页圆点（第 1 屏：长+短；第 2 屏：短+长，两组总宽都是 41，居中于 1024）
    R.dots = {
        theme.box(p, 491, 559, 22, 9, C.blue2, 4),
        theme.box(p, 523, 559, 9, 9, 0xB4C4D6, 4),
        theme.box(p, 491, 559, 9, 9, 0xB4C4D6, 4),
        theme.box(p, 510, 559, 22, 9, C.blue2, 4),
    }
    theme.hit(p, 471, 545, 82, 40, function()
        S.page = (S.page == 1) and 2 or 1
        if R.home.tv then pcall(R.home.tv.set_active, R.home.tv, S.page - 1) end
        refresh_dots()
    end)
    refresh_dots()
end

--------------------------------------------------------------------
-- 屏 2：通话
--------------------------------------------------------------------
local function call_tip()
    if S.num ~= "" then
        -- 中间用半角空格：全角空格（U+3000）在 hzfont 里没有字形，会显示成方框
        return "房号：" .. S.num .. "  （点绿色键呼叫）"
    end
    return "*请输入对方房号（如 1 室 2 楼），其中 4 位"
end

local function tap_num(n)
    if #S.num < 4 then
        S.num = S.num .. n
        if R.call.tip then
            pcall(R.call.tip.set_text, R.call.tip, call_tip())
        end
    end
end

local function back_num()
    S.num = string.sub(S.num, 1, math.max(0, #S.num - 1))
    if R.call.tip then
        pcall(R.call.tip.set_text, R.call.tip, call_tip())
    end
end

build.call = function(p)
    -- 标题栏（提示在左侧，不是居中标题）
    theme.box(p, 0, 0, W, 62, C.card)
    theme.box(p, 0, 61, W, 1, C.line)
    theme.icon(p, 26, 19, 24, "back", C.sub)
    theme.hit(p, 18, 11, 40, 40, function() show("home") end)
    R.call.tip = theme.txt(p, 68, 11, W - 300, 40, call_tip(), C.sub, 18)

    -- 数字键盘（列距 34 / 行距 8，与 html 的 grid 一致）
    local KEYS = { "1", "2", "3", "back",
                   "4", "5", "6", "0",
                   "7", "8", "9", "user" }
    for i, kk in ipairs(KEYS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 165 + col * 158
        local y = 88 + row * 118
        -- 按压反馈：点一下整格闪一层淡灰（120ms 后复原），否则按了没按看不出来
        local bg = theme.box_a(p, x, y, 124, 110, C.track, 10, 0)
        local function pressed()
            pcall(bg.set_color, bg, C.track, 70)
            sys.timerStart(function()
                pcall(bg.set_color, bg, C.track, 0)
            end, 120)
        end
        if kk == "user" then
            theme.icon(p, x + 45, y + 38, 34, "intercom", C.keypad)
            theme.hit(p, x, y, 124, 110, function() pressed() open_user() end)
        elseif kk == "back" then
            -- 退格：× 号（横线换成叉，同样不依赖字体字形）
            theme.icon(p, x + 42, y + 35, 40, "close", C.keypad)
            theme.hit(p, x, y, 124, 110, function() pressed() back_num() end)
        else
            theme.txt(p, x, y, 124, 110, kk, C.keypad, 34,
                airui.TEXT_ALIGN_CENTER)
            theme.hit(p, x, y, 124, 110, function() pressed() tap_num(kk) end)
        end
    end

    -- 右侧功能轨已去掉（电话 / 对讲 / 呼叫 三页内容完全一样，没有意义）

    -- 悬浮按钮（呼叫键保持绿色，键盘数字保持灰色）
    theme.box(p, 814, 292, 78, 78, C.green, 39)
    theme.icon(p, 833, 311, 40, "phone", C.white)
    theme.hit(p, 814, 292, 78, 78, function() dial(nil) end)

    theme.box(p, 814, 396, 78, 78, C.blue2, 39)
    theme.icon(p, 833, 415, 40, "user_f", C.white)
    theme.hit(p, 814, 396, 78, 78, function() open_user() end)
end

--------------------------------------------------------------------
-- 屏 3：监视
--------------------------------------------------------------------
local CAMS = {
    { name = "主单元门口机", tag = "IPC",    w = 150, x = 18 },
    { name = "仓库枪机 01",  tag = "IPC-01", w = 140, x = 176 },
    { name = "仓库球机 02",  tag = "IPC-02", w = 140, x = 324 },
}

build.monitor = function(p)
    theme.box(p, 0, 0, W, 62, C.card)
    theme.box(p, 0, 61, W, 1, C.line)
    theme.icon(p, 26, 19, 24, "back", C.sub)
    theme.hit(p, 18, 11, 40, 40, function() show("home") end)
    R.monitor.name = theme.txt(p, 68, 11, W - 136, 40, CAMS[S.cam].name, C.text, 20,
        airui.TEXT_ALIGN_CENTER)

    -- 画面（渐变不支持 → 三段纯色近似）
    theme.box(p, 10, 72, 918, 518, C.preview, 4)
    theme.box(p, 10, 72, 918, 190, 0x7C8896, 4)
    theme.box(p, 10, 262, 918, 150, 0x5F6B78, 0)
    theme.box(p, 10, 412, 918, 178, 0x39434E, 0)
    theme.box_a(p, 10, 435, 918, 155, C.floor, 0, 150)
    theme.box_a(p, 836, 72, 18, 363, 0x1E262E, 0, 150)
    theme.circle(p, 24, 84, 10, C.red2)
    theme.txt(p, 42, 76, 90, 24, "REC", C.white, 16)
    R.monitor.tag = theme.txt(p, 269, 264, 400, 72, CAMS[S.cam].tag, 0x9AA5B0, 62,
        airui.TEXT_ALIGN_CENTER)
    theme.txt(p, 414, 552, 500, 26, "07/02/021 Tue 17:42:56", C.white, 16,
        airui.TEXT_ALIGN_RIGHT)
    theme.hit(p, 10, 72, 918, 518, function() show("live") end)

    -- 设备工具列
    theme.box_b(p, 938, 74, 62, 62, C.card, 4, C.line, 1)
    theme.icon(p, 956, 92, 26, "grid", C.sub)
    theme.hit(p, 938, 74, 62, 62, function()
        toast("已刷新设备列表（3 台在线）")
    end)

    theme.box(p, 938, 146, 62, 62, C.orange2, 4)
    theme.icon(p, 956, 164, 26, "search", C.white)
    theme.hit(p, 938, 146, 62, 62, function()
        toast("正在搜索局域网内的 IPC…")
    end)

    -- 摄像头芯片
    R.monitor.cams = {}
    for i, cam in ipairs(CAMS) do
        local on = (S.cam == i)
        local chip = theme.box_a(p, cam.x, 544, cam.w, 46, C.chip, 23,
            on and 255 or C.chip_opa)
        if on then pcall(chip.set_color, chip, C.orange2, 255) end
        theme.txt(p, cam.x, 544, cam.w, 46, cam.name, C.white, 17,
            airui.TEXT_ALIGN_CENTER)
        theme.hit(p, cam.x, 544, cam.w, 46, function() pick_cam(i) end)
        R.monitor.cams[i] = chip
    end
end

--------------------------------------------------------------------
-- 屏 4：门口取景
--------------------------------------------------------------------
build.live = function(p)
    theme.box(p, 0, 0, W, 240, 0x7C8896)
    theme.box(p, 0, 240, W, 180, 0x5F6B78)
    theme.box(p, 0, 420, W, 180, 0x39434E)
    theme.box_a(p, 0, 408, W, 192, C.floor, 0, 155)
    theme.box_a(p, 942, 74, 20, 322, 0x1E262E, 0, 150)
    -- 光斑（html 用 blur，实机用半透明纯色圆近似）
    theme.box_a(p, 389, 48, 320, 320, C.cam1, 160, 110)
    theme.box_a(p, 655, 192, 260, 260, C.cam2, 130, 110)
    theme.box_a(p, 61, 324, 300, 300, C.cam3, 150, 110)

    -- 顶栏
    theme.box_a(p, 0, 0, W, 64, 0x000000, 0, 130)
    theme.icon(p, 24, 20, 24, "back", C.white)
    theme.hit(p, 16, 12, 40, 40, function() show("monitor") end)
    R.live.name = theme.txt(p, 0, 14, W, 36, CAMS[S.cam].name, C.white, 22,
        airui.TEXT_ALIGN_CENTER)
    theme.txt(p, 700, 18, 300, 28, "07/02/021 Tue 17:42:56", C.white, 16,
        airui.TEXT_ALIGN_RIGHT)

    -- 开锁
    local lock = theme.box_a(p, 26, 268, 64, 64, 0x000000, 32, 72)
    theme.icon(p, 43, 285, 30, "lock", C.white)
    theme.hit(p, 26, 268, 64, 64, function()
        toast("门已开启")
        pcall(lock.set_color, lock, C.green, 220)
        sys.timerStart(function()
            pcall(lock.set_color, lock, 0x000000, 72)
        end, 1200)
    end)

    -- 麦克风按钮（竖着放在开锁上方）：只做开 / 关，静音时图标叠一条红斜杠
    theme.box_a(p, 26, 188, 64, 64, 0x000000, 32, 72)
    local mico = theme.icon(p, 43, 205, 30, "mic", C.white)
    local function mic_items(on)
        local it = theme.icon_items("mic", 30, C.white)
        if not on then
            it[#it + 1] = { type = "line", x1 = 5, y1 = 25, x2 = 25, y2 = 5,
                color = C.red2, width = 5,
                round_start = true, round_end = true }
        end
        return it
    end
    if not S.mic then pcall(mico.set_items, mico, mic_items(false)) end
    theme.hit(p, 26, 188, 64, 64, function()
        S.mic = not S.mic
        pcall(mico.set_items, mico, mic_items(S.mic))
        toast(S.mic and "麦克风已开启" or "麦克风已静音")
    end)

    -- 挂断：回到通话页（原来错跳监视页）
    theme.box(p, 886, 518, 112, 56, C.red, 28)
    theme.icon(p, 906, 535, 22, "phone", C.white)
    theme.txt(p, 936, 518, 56, 56, "挂断", C.white, 18, airui.TEXT_ALIGN_CENTER)
    theme.hit(p, 886, 518, 112, 56, function() show("call") end)
end

--------------------------------------------------------------------
-- 屏 5：消息
--------------------------------------------------------------------
local MSGS = {
    { title = "主单元门口机 · 未接来电", time = "17:42", desc = "门口机呼叫 1203，无人接听",
      icon = "phone",   col = "green" },
    { title = "仓库枪机 01 · 移动侦测", time = "16:20", desc = "检测到画面变化，已抓拍 3 张",
      icon = "warning", col = "red" },
    { title = "门磁 · 门窗被打开", time = "昨天", desc = "1F 后门磁触发，请确认",
      icon = "lock",    col = "red" },
    { title = "系统通知", time = "11-14", desc = "新版本固件可用，建议在空闲时升级",
      icon = "info",    col = "blue" },
}

build.msg = function(p)
    titlebar(p, "消息", "清空", function()
        S.msgs_cleared = true
        S.unread = 0
        if R.home.badge then pcall(R.home.badge.set_hidden, R.home.badge, true) end
        for _, it in ipairs(R.msg.items) do
            pcall(it.set_hidden, it, true)
        end
        pcall(R.msg.empty.set_hidden, R.msg.empty, false)
        toast("消息已清空")
    end)

    R.msg.items = {}
    local y = 74
    for _, m in ipairs(MSGS) do
        local card = theme.box(p, 16, y, 992, 84, C.card, 10)
        theme.box_a(card, 16, 16, 52, 52, C[m.col], 26, 48)
        theme.icon(card, 29, 29, 26, m.icon, C[m.col])
        theme.txt(card, 82, 12, 700, 30, m.title, C.text, 19)
        theme.txt(card, 992 - 140, 14, 120, 26, m.time, C.sub, 16,
            airui.TEXT_ALIGN_RIGHT)
        theme.txt(card, 82, 46, 860, 26, m.desc, C.sub, 17)
        theme.hit(card, 0, 0, 992, 84, function() toast("打开：" .. m.title) end)
        R.msg.items[#R.msg.items + 1] = card
        y = y + 94
    end

    R.msg.empty = theme.box(p, 0, 200, W, 120, C.bg, 0)
    theme.txt(R.msg.empty, 0, 0, W, 60, "暂无消息", C.sub, 18,
        airui.TEXT_ALIGN_CENTER)
    if not S.msgs_cleared then
        pcall(R.msg.empty.set_hidden, R.msg.empty, true)
    else
        for _, it in ipairs(R.msg.items) do pcall(it.set_hidden, it, true) end
    end
end

--------------------------------------------------------------------
-- 屏 6：设置
--------------------------------------------------------------------
build.set = function(p)
    titlebar(p, "设置")

    local y = 72
    local function item(h)
        theme.box(p, 16, y, 992, h, C.card, 10)
        return y
    end

    -- 音量
    local y1 = item(102)
    theme.box_a(p, 34, y1 + 10, 44, 44, C.orange, 22, 46)
    theme.icon(p, 44, y1 + 20, 24, "volume", C.orange, C.card)
    theme.txt(p, 92, y1 + 10, 320, 44, "广播音量", C.text, 19)
    R.set.vol_val = theme.txt(p, 790, y1 + 10, 200, 44, tostring(S.volume),
        C.sub, 17, airui.TEXT_ALIGN_RIGHT)
    theme.slider(p, 34, y1 + 64, 956, S.volume, function(self)
        local v = self:get_value()
        S.volume = v
        pcall(R.set.vol_val.set_text, R.set.vol_val, tostring(v))
        if R.home.vol then
            pcall(R.home.vol.set_text, R.home.vol, tostring(v))
        end
    end)

    -- 亮度
    y = y1 + 110
    local y2 = item(102)
    theme.box_a(p, 34, y2 + 10, 44, 44, C.blue, 22, 42)
    theme.icon(p, 44, y2 + 20, 24, "sun", C.blue, C.card)
    theme.txt(p, 92, y2 + 10, 320, 44, "屏幕亮度", C.text, 19)
    R.set.bri_val = theme.txt(p, 790, y2 + 10, 200, 44, tostring(S.brightness),
        C.sub, 17, airui.TEXT_ALIGN_RIGHT)
    theme.slider(p, 34, y2 + 64, 956, S.brightness, function(self)
        local v = self:get_value()
        S.brightness = v
        pcall(R.set.bri_val.set_text, R.set.bri_val, tostring(v))
        set_backlight(v)                 -- 真调背光 PWM3 占空比
    end)

    -- 显示主题
    y = y2 + 110
    local y3 = item(64)
    theme.box_a(p, 34, y3 + 10, 44, 44, C.purple, 22, 42)
    theme.icon(p, 44, y3 + 20, 24, "moon", C.purple, C.card)
    theme.txt(p, 92, y3 + 10, 320, 44, "显示主题", C.text, 19)
    theme.txt(p, 790, y3 + 10, 200, 44,
        (theme.cur == "dark") and "深色" or "浅色", C.sub, 17,
        airui.TEXT_ALIGN_RIGHT)
    theme.hit(p, 16, y3, 992, 64, function()
        theme.toggle_theme()
        redraw()
    end)

    -- 离家布防
    y = y3 + 72
    local y4 = item(64)
    theme.box_a(p, 34, y4 + 10, 44, 44, C.green, 22, 46)
    theme.icon(p, 44, y4 + 20, 24, "shield", C.green, C.card)
    theme.txt(p, 92, y4 + 10, 320, 44, "离家布防", C.text, 19)
    local swx = 16 + 992 - 18 - 62
    R.set.sw_track, R.set.sw_dot = theme.switch(p, swx, y4 + 15, S.armed)
    theme.hit(p, 16, y4, 992, 64, function() toggle_arm() end)

    -- 电梯呼梯
    y = y4 + 72
    local y5 = item(64)
    theme.box_a(p, 34, y5 + 10, 44, 44, C.blue, 22, 42)
    theme.icon(p, 44, y5 + 20, 24, "elevator", C.blue, C.card)
    theme.txt(p, 92, y5 + 10, 320, 44, "电梯呼梯", C.text, 19)
    theme.txt(p, 790, y5 + 10, 200, 44, "B1 ~ 13F", C.sub, 17,
        airui.TEXT_ALIGN_RIGHT)
    theme.hit(p, 16, y5, 992, 64, function() open_elevator() end)

    -- 关于本机
    y = y5 + 72
    local y6 = item(64)
    theme.box_a(p, 34, y6 + 10, 44, 44, C.sub, 22, 40)
    theme.icon(p, 44, y6 + 20, 24, "info", C.sub, C.card)
    theme.txt(p, 92, y6 + 10, 320, 44, "关于本机", C.text, 19)
    theme.txt(p, 790, y6 + 10, 200, 44, "Air8603", C.sub, 17,
        airui.TEXT_ALIGN_RIGHT)
    theme.hit(p, 16, y6, 992, 64, function() open_about() end)
end

--------------------------------------------------------------------
-- 切屏 / 重建
--------------------------------------------------------------------
show = function(name)
    S.screen = name
    for _, k in ipairs(ORDER) do
        if sc[k] then pcall(sc[k].set_hidden, sc[k], k ~= name) end
    end
    if name == "msg" then
        S.unread = 0
        if R.home.badge then pcall(R.home.badge.set_hidden, R.home.badge, true) end
    end
end

-- 主题切换后必须整屏重建（颜色全部写死在创建时），只在这里 destroy
redraw = function()
    clear_overlay()
    clear_toast()
    for _, k in ipairs(ORDER) do
        if sc[k] then pcall(sc[k].destroy, sc[k]) sc[k] = nil end
    end
    R = { home = {}, call = {}, monitor = {}, live = {}, msg = {}, set = {} }
    for _, k in ipairs(ORDER) do
        sc[k] = theme.box(root, 0, 0, W, H, C.bg, 0)
        pcall(build[k], sc[k])
        pcall(sc[k].set_hidden, sc[k], k ~= S.screen)
    end
end

--------------------------------------------------------------------
-- 主入口
--------------------------------------------------------------------
local function build_root(root_in)
    root = root_in
    redraw()
    set_backlight(S.brightness)         -- 开机对齐：UI 显示多少就调到多少

    -- 时钟：1 秒轮询，只在分钟变化时写文本
    local last = ""
    return function()
        local hm, dt = clock_texts()
        if hm ~= last then
            last = hm
            if R.home.clock then
                pcall(R.home.clock.set_text, R.home.clock, hm)
            end
            if R.home.date then
                pcall(R.home.date.set_text, R.home.date, dt)
            end
        end
    end, 1000
end

theme.make_page(1, "可视门铃", build_root)
