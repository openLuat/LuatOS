--[[
@module ui
@summary 抓娃娃机 UI：airui.shape 图元实时绘制 + 标签层 + 触摸交互
@ver 1.0.0
@author cqd
@note 渲染约定（来自 air8607_demos 踩坑记录 + LVGL9 z序验证）：
      1) 坐标一律 math.floor 取整，小数在 C 层截断会让图元凭空消失；
      2) LVGL9 后建的同级控件在上层，因此本工程先建 shape、后建 label，
         文字天然压在图形之上；
      3) 文本带缓存节流，只有内容变化才 set_text。
      触摸走 airui.touch_subscribe：左右键长按移动、抓取键点按、
      玻璃柜内点按/拖动可直接把爪子移到目标位置。
@usage
local UI = require "ui"
local view = UI.new(config, model, sfx)
view:init()
view:render(model:snapshot())
]]

local fx = require "fx"

local W, H = 1024, 600

-- ==================== 配色 ====================
local C = {
    bg      = 0x0B0D23,
    bg2     = 0x12163A,
    panel   = 0x1A1F45,
    panel2  = 0x252C63,
    accent  = 0xFF4D8D,
    accent2 = 0xFFB84D,
    cyan    = 0x38D4FF,
    text    = 0xFFFFFF,
    dim     = 0x8D93C4,
    glass   = 0x101A33,
    steel   = 0x8890C0,
    steel2  = 0x5A6192,
    claw    = 0xFFD34D,
    cable   = 0xB8BEDC,
    rail    = 0x3A4278,
    ok      = 0x4FE38A,
    fail    = 0xFF6B6B,
    dark    = 0x2A2036,
}

-- ==================== 布局矩形 {x, y, w, h} ====================
local CASE       = { 40, 88, 648, 480 }
local CHUTE      = { 596, 468, 84, 92 }
local CHIP_SCORE = { 560, 22, 140, 34 }
local CHIP_TRY   = { 712, 22, 140, 34 }
local CHIP_SND   = { 864, 22, 136, 34 }
local STATUS     = { 712, 88, 288, 176 }
local BTN_LEFT   = { 712, 292, 138, 88 }
local BTN_RIGHT  = { 862, 292, 138, 88 }
local BTN_GRAB   = { 712, 404, 288, 120 }

local UI = {}
UI.__index = UI

local function in_rect(r, x, y)
    return x >= r[1] and y >= r[2] and x <= r[1] + r[3] and y <= r[2] + r[4]
end

-- ==================== 娃娃绘制 ====================
local function draw_toy(P, x, y, r, kind, color, t, phase)
    local dark = fx.shade(color, -0.25)
    if kind == "bunny" then
        P:box(x - r - 2, y - r - 32, 13, 38, color, 255, 7)
        P:box(x + r - 11, y - r - 32, 13, 38, color, 255, 7)
        P:box(x, y - r - 28, 7, 28, fx.shade(color, 0.3), 110, 4)
        P:box(x + r - 9, y - r - 28, 7, 28, fx.shade(color, 0.3), 110, 4)
    elseif kind == "bear" then
        P:dot(x - r + 1, y - r + 2, 13, color, 255)
        P:dot(x + r - 1, y - r + 2, 13, color, 255)
        P:dot(x - r + 1, y - r + 2, 7, fx.shade(color, 0.25), 150)
        P:dot(x + r - 1, y - r + 2, 7, fx.shade(color, 0.25), 150)
    elseif kind == "frog" then
        P:dot(x - r + 7, y - r - 1, 12, color, 255)
        P:dot(x + r - 7, y - r - 1, 12, color, 255)
    end
    -- 身体 + 高光 + 肚皮
    P:dot(x, y, r, color, 255)
    P:dot(x - r / 3, y - r / 3, math.floor(r / 2.6), fx.shade(color, 0.18), 60)
    P:dot(x, y + r / 3, math.floor(r * 0.55), fx.shade(color, 0.35), 150)
    -- 眼睛 + 腮红
    local ey = y - math.floor(r / 6)
    if kind == "frog" then
        P:dot(x - r + 7, y - r - 1, 4, C.dark, 255)
        P:dot(x + r - 7, y - r - 1, 4, C.dark, 255)
    else
        P:dot(x - math.floor(r / 2.4), ey, 4, C.dark, 255)
        P:dot(x + math.floor(r / 2.4), ey, 4, C.dark, 255)
    end
    P:dot(x - math.floor(r / 1.7), ey + 9, 5, 0xFF8FB1, 90)
    P:dot(x + math.floor(r / 1.7), ey + 9, 5, 0xFF8FB1, 90)
    -- 嘴
    if kind == "duck" then
        P:box(x - 8, ey + 5, 16, 6, 0xFF8C3D, 255, 3)
    elseif kind == "frog" then
        P:line(x - 9, ey + 12, x + 9, ey + 12, C.dark, 3, 255, true)
    else
        P:arc(x, ey + 3, 8, 30, 150, C.dark, 3, 255, true)
    end
end

-- ==================== 爪子绘制 ====================
local function draw_claw(P, s)
    local cx = math.floor(s.claw_x)
    local cy = math.floor(s.claw_y)
    -- 轨道 + 滑车
    P:line(CASE[1] + 8, 132, CASE[1] + CASE[3] - 8, 132, C.rail, 8, 255, true)
    P:line(CASE[1] + 8, 132, CASE[1] + CASE[3] - 8, 132, C.steel2, 3, 255, true)
    P:box(cx - 30, 118, 60, 26, C.steel, 255, 8)
    P:box(cx - 20, 124, 40, 8, C.steel2, 255, 4)
    -- 吊绳 + 爪体
    P:line(cx, 136, cx, cy - 24, C.cable, 3, 220, true)
    P:box(cx - 27, cy - 24, 54, 32, C.claw, 255, 10)
    P:box(cx - 19, cy - 17, 38, 10, fx.shade(C.claw, 0.3), 130, 5)
    -- 三根爪指：prong=1 全张开，0 全闭合
    local spread = math.floor(8 + 34 * s.prong)
    local tip_y = cy + 52
    for i = -1, 1 do
        local tip_x = cx + i * spread
        P:line(cx + i * 10, cy + 6, tip_x, tip_y, C.claw, 7, 255, true)
        P:dot(tip_x, tip_y, 5, fx.shade(C.claw, -0.15), 255)
    end
    -- 吊挂的娃娃（弹簧摆动）
    if s.carried then
        local ox = math.floor(s.swing * 120)
        draw_toy(P, cx + ox, cy + 100, s.carried.r, s.carried.kind, s.carried.color, 0, 0)
    end
end

-- ==================== 构造 ====================
function UI.new(config, model, sfx)
    assert(type(config) == "table", "config required")
    assert(type(model) == "table" and model.snapshot, "model required")
    local self = setmetatable({}, UI)
    self.cfg = config
    self.model = model
    self.sfx = sfx or { play = function() end, toggle = function() return true end }
    self.sfx_on = true
    self.pressed = {}
    self.ptr = nil
    self.fx = {}
    self._texts = {}
    self._last_seq = 0

    -- 根容器（全屏深色底）
    self.root = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        style = { bg_color = C.bg },
    })

    -- 图元层必须先建：后建的 label 才会压在其上
    self.shape = airui.shape({
        parent = self.root, x = 0, y = 0, w = W, h = H, items = {},
    })

    local function label(text, x, y, w, h, size, color, align)
        return airui.label({
            parent = self.root, x = x, y = y, w = w, h = h,
            text = text, font = 0, font_size = size,
            text_color = color or C.text, align = align or "left",
        })
    end

    -- 顶栏
    label("欢乐抓娃娃", 40, 16, 400, 38, 32, C.text, "left")
    label("CLAW MACHINE", 40, 58, 400, 18, 12, C.dim, "left")
    self.lbScore = label("抓中 0", CHIP_SCORE[1], CHIP_SCORE[2], CHIP_SCORE[3], CHIP_SCORE[4], 17, C.text, "center")
    self.lbTry = label("尝试 0", CHIP_TRY[1], CHIP_TRY[2], CHIP_TRY[3], CHIP_TRY[4], 17, C.text, "center")
    self.lbSnd = label("音效 开", CHIP_SND[1], CHIP_SND[2], CHIP_SND[3], CHIP_SND[4], 15, C.dim, "center")

    -- 状态卡
    label("当前状态", 728, 102, 256, 18, 12, C.dim, "center")
    self.lbMsg = label("对准娃娃，按下抓取", 728, 136, 256, 64, 22, C.text, "center")
    self.lbRate = label("命中率 0%", 728, 222, 256, 18, 12, C.dim, "center")

    -- 控制按钮
    label("左移", BTN_LEFT[1], 316, BTN_LEFT[3], 36, 24, C.text, "center")
    label("右移", BTN_RIGHT[1], 316, BTN_RIGHT[3], 36, 24, C.text, "center")
    label("抓 取", BTN_GRAB[1], 428, BTN_GRAB[3], 56, 36, C.text, "center")
    label("GRAB", BTN_GRAB[1], 486, BTN_GRAB[3], 18, 12, 0x3B2A1E, "center")

    -- 提示与出货口
    label("长按左右移动 · 点柜内可移动爪子", 712, 540, 288, 16, 11, C.dim, "center")
    label("出货口", CHUTE[1], 516, CHUTE[3], 24, 14, C.accent2, "center")
    return self
end

-- 注册触摸订阅
function UI:init()
    airui.touch_subscribe(function(state, x, y, id, timestamp)
        self:touch(state, x, y, id, timestamp)
    end)
end

-- ==================== 触摸交互 ====================
function UI:touch(state, x, y, id, timestamp)
    if state == airui.TP_DOWN then
        local ctrl
        if in_rect(BTN_LEFT, x, y) then ctrl = "left"
        elseif in_rect(BTN_RIGHT, x, y) then ctrl = "right"
        elseif in_rect(BTN_GRAB, x, y) then ctrl = "grab"
        elseif in_rect(CHIP_SND, x, y) then ctrl = "sound"
        elseif in_rect(CASE, x, y) then ctrl = "case"
        end
        if not ctrl then return false end
        self.ptr = { id = id, ctrl = ctrl }
        if ctrl == "left" or ctrl == "right" then
            self.pressed[ctrl] = true
            self.model:input(ctrl == "left" and -1 or 1)
        elseif ctrl == "grab" then
            self.pressed.grab = true
            if self.model:grab() then self.sfx.play("press") end
        elseif ctrl == "sound" then
            self.pressed.sound = true
            self.sfx_on = self.sfx.toggle()
        elseif ctrl == "case" then
            self.model:target(x)
        end
        return true
    elseif state == airui.TP_UP then
        if self.ptr and self.ptr.id == id then
            self.pressed.left = false
            self.pressed.right = false
            self.pressed.grab = false
            self.pressed.sound = false
            self.model:input(0)
            self.ptr = nil
            return true
        end
        return false
    else
        -- TP_HOLD：长按持续移动 / 柜内拖动跟手
        if self.ptr and self.ptr.id == id then
            if self.ptr.ctrl == "case" then
                self.model:target(x)
            end
            return true
        end
        return false
    end
end

-- ==================== 一次性事件 → 音效/特效 ====================
function UI:handle_events(s)
    if s.event_seq == self._last_seq then return end
    self._last_seq = s.event_seq
    local ev = s.last_event
    local t = s.elapsed_ms
    if ev == "grab_start" then
        self.sfx.play("drop")
    elseif ev == "grab_ok" then
        self.sfx.play("ok")
        self.fx[#self.fx + 1] = { kind = "spark", x = s.claw_x, y = s.claw_y, t0 = t }
    elseif ev == "grab_fail" then
        self.sfx.play("fail")
    elseif ev == "prize_drop" then
        self.sfx.play("grab")
        self.fx[#self.fx + 1] = { kind = "ring", x = CHUTE[1] + CHUTE[3] / 2, y = CHUTE[2] + CHUTE[4] / 2, t0 = t }
    elseif ev == "refill" then
        self.sfx.play("press")
    end
end

-- ==================== 逐层绘制 ====================
local function draw_bg(P)
    P:box(0, 0, W, H, C.bg, 255, 0)
    P:box(0, 88, W, H - 88, C.bg2, 255, 0)
end

local function draw_topbar(P, t)
    P:box(0, 0, W, 88, C.bg, 255, 0)
    P:line(0, 87, W, 87, C.rail, 2, 255)
    -- 状态徽章
    local chips = { CHIP_SCORE, CHIP_TRY, CHIP_SND }
    for i = 1, 3 do
        local r = chips[i]
        P:box(r[1], r[2], r[3], r[4], C.panel2, 255, 17)
        P:frame(r[1], r[2], r[3], r[4], C.cyan, 2, 60, 17)
    end
    -- 标题装饰点
    P:dot(28, 34, 6, C.accent, 255)
    P:dot(28, 34, 12, C.accent, 60)
    P:dot(46, 62, 3, C.accent2, 255)
end

local function draw_case(P, t)
    -- 玻璃柜
    P:box(CASE[1], CASE[2], CASE[3], CASE[4], C.glass, 255, 18)
    P:frame(CASE[1], CASE[2], CASE[3], CASE[4], C.cyan, 3, 120, 18)
    -- 内壁光泽（两条斜向高光带）
    P:poly({ CASE[1] + 60, CASE[1] + 180, CASE[1] + 300 }, { CASE[2] + CASE[4] - 20, CASE[2] + 20, CASE[2] + 20 }, 3, 0x2E7BD6, 26, 26, true)
    P:poly({ CASE[1] + 120, CASE[1] + 240, CASE[1] + 360 }, { CASE[2] + CASE[4] - 20, CASE[2] + 20, CASE[2] + 20 }, 3, 0x2E7BD6, 14, 18, true)
    -- 台面
    P:box(CASE[1] + 10, 540, CASE[3] - 20, 28, 0x1B2452, 255, 10)
    P:line(CASE[1] + 10, 540, CASE[1] + CASE[3] - 10, 540, C.cyan, 2, 90, true)
    -- 顶部霓虹灯带
    local glow = math.floor(80 + 40 * math.sin(t * 2))
    P:line(CASE[1] + 16, CASE[2] + 12, CASE[1] + CASE[3] - 16, CASE[2] + 12, C.accent, 4, glow, true)
end

local function draw_chute(P, t)
    local x, y, w, h = CHUTE[1], CHUTE[2], CHUTE[3], CHUTE[4]
    P:box(x, y, w, h, 0x07091C, 255, 12)
    P:box(x + 8, y + h - 30, w - 16, 22, 0x140B2E, 255, 8)
    local glow = math.floor(90 + 60 * math.sin(t * 3))
    P:frame(x - 3, y - 3, w + 6, h + 6, C.accent2, 3, glow, 12)
    P:frame(x - 3, y - 3, w + 6, h + 6, C.accent2, 2, 60, 12)
end

local function draw_toys(P, t, s)
    for _, toy in ipairs(s.toys) do
        if not toy.caught then
            local bob = math.floor(2 * math.sin(t * 1.4 + toy.id * 1.1))
            draw_toy(P, toy.x, toy.y + bob, toy.r, toy.kind, toy.color, t, bob)
        end
    end
    for _, f in ipairs(s.falling) do
        draw_toy(P, math.floor(f.x), math.floor(f.y), f.r, f.kind, f.color, t, 0)
    end
end

local function draw_button(P, r, pressed, base, hot)
    P:box(r[1], r[2], r[3], r[4], pressed and hot or base, 255, 18)
    P:frame(r[1], r[2], r[3], r[4], pressed and C.accent2 or C.cyan, 2, pressed and 200 or 80, 18)
    if not pressed then
        P:box(r[1] + 5, r[2] + 5, r[3] - 10, math.floor(r[4] / 2 - 5), fx.shade(base, 0.12), 70, 13)
    end
end

local function chevron(P, cx, cy, dir, color)
    P:line(cx + dir * 12, cy - 18, cx - dir * 12, cy, color, 6, 255, true)
    P:line(cx - dir * 12, cy, cx + dir * 12, cy + 18, color, 6, 255, true)
end

local function draw_panel(P, t, s, pressed)
    -- 状态卡
    P:box(STATUS[1], STATUS[2], STATUS[3], STATUS[4], C.panel, 255, 16)
    P:frame(STATUS[1], STATUS[2], STATUS[3], STATUS[4], C.rail, 2, 255, 16)
    -- 按钮
    draw_button(P, BTN_LEFT, pressed.left, C.panel2, 0x3D4890)
    draw_button(P, BTN_RIGHT, pressed.right, C.panel2, 0x3D4890)
    chevron(P, BTN_LEFT[1] + BTN_LEFT[3] / 2, 336, -1, pressed.left and C.accent2 or C.cyan)
    chevron(P, BTN_RIGHT[1] + BTN_RIGHT[3] / 2, 336, 1, pressed.right and C.accent2 or C.cyan)
    -- 抓取大按钮（呼吸高亮）
    local hot = math.floor(160 + 50 * math.sin(t * 3))
    draw_button(P, BTN_GRAB, pressed.grab, C.accent, 0xFF6E9E)
    P:frame(BTN_GRAB[1] - 2, BTN_GRAB[2] - 2, BTN_GRAB[3] + 4, BTN_GRAB[4] + 4, C.accent2, 3, hot, 20)
end

function UI:draw_fx(P, s)
    local now = s.elapsed_ms
    for i = #self.fx, 1, -1 do
        local f = self.fx[i]
        local age = now - f.t0
        if age > 900 then
            table.remove(self.fx, i)
        elseif f.kind == "ring" then
            for k = 0, 2 do
                local a = age - k * 160
                if a >= 0 and a < 700 then
                    local r = math.floor(18 + a * 0.22)
                    local opa = math.floor(230 * (1 - a / 700))
                    if opa > 0 then
                        P:frame(f.x - r, f.y - r, r * 2, r * 2, C.accent2, 3, opa, r)
                    end
                end
            end
        elseif f.kind == "spark" then
            for k = 0, 5 do
                local a = age - k * 60
                if a >= 0 and a < 500 then
                    local ang = k * math.pi / 3 + 0.5
                    local d = math.floor(a * 0.18)
                    local opa = math.floor(220 * (1 - a / 500))
                    if opa > 0 then
                        P:dot(math.floor(f.x + math.cos(ang) * d),
                              math.floor(f.y + math.sin(ang) * d),
                              4, k % 2 == 0 and C.accent2 or C.cyan, opa)
                    end
                end
            end
        end
    end
end

-- ==================== 文本更新（带缓存节流） ====================
function UI:update_labels(s)
    local function put(key, obj, text)
        if self._texts[key] ~= text then
            self._texts[key] = text
            obj:set_text(text)
        end
    end
    put("score", self.lbScore, "抓中 " .. tostring(s.score))
    put("try", self.lbTry, "尝试 " .. tostring(s.attempts))
    put("snd", self.lbSnd, self.sfx_on and "音效 开" or "音效 关")

    local p = s.phase
    local msg
    if p == "IDLE" then
        msg = "对准娃娃，按下抓取"
    elseif p == "DROP" then
        msg = "爪子出击！"
    elseif p == "GRAB" then
        msg = "闭爪抓取…"
    elseif p == "LIFT" then
        msg = s.result_ok and "抓紧了！" or "哎呀，滑走了…"
    elseif p == "CARRY" then
        msg = "运送中…"
    elseif p == "RELEASE" then
        msg = "放入出货口…"
    elseif p == "RESULT" then
        msg = s.result_ok and "抓到了！+1" or "差一点点，再试一次！"
    end
    put("msg", self.lbMsg, msg)

    local rate = 0
    if s.attempts > 0 then
        rate = math.floor(s.successes * 100 / s.attempts + 0.5)
    end
    put("rate", self.lbRate, "命中率 " .. rate .. "%")
end

-- ==================== 主渲染入口 ====================
function UI:render(s)
    self:handle_events(s)
    if not self.pool then
        self.pool = fx.pool()
    end
    local P = self.pool
    local t = s.elapsed_ms / 1000
    P:reset()
    draw_bg(P)
    draw_topbar(P, t)
    draw_case(P, t)
    draw_chute(P, t)
    draw_toys(P, t, s)
    draw_claw(P, s)
    draw_panel(P, t, s, self.pressed)
    self:draw_fx(P, s)
    P:finish()
    self.shape:set_items(P.items)
    self:update_labels(s)
end

return UI
