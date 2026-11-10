--[[
@module  ui
@summary 伺服脉冲 / 方向 控制界面（1024x600 触摸）
@version 4.0
@date    2026.11.05

界面布局：
  顶栏：标题 + 运行状态
  左上：方向输出（高/低电平两个按钮）
  左下：脉冲输出（固定 1kHz/50%，PWM启动 / PWM停止 两个按钮，启动 1 秒自动停止）
  右侧：运行状态（频率、转速、已运行时间）
]]
local M = {}

local conf = require "conf"
local pulse = require "servo_pulse"

local SW, SH = conf.screen.w, conf.screen.h
local U = conf.ui
local P = conf.pulse

-- ==================== 配色 ====================
local C = {
    bg     = 0x0E1116,
    panel  = 0x171D24,
    panel2 = 0x212933,
    line   = 0x2C3742,
    ink    = 0xE6EDF3,
    ink2   = 0xA3B1BF,
    ink3   = 0x6C7A88,
    accent = 0x2F81F7,
    ok     = 0x3FB950,
    warn   = 0xD29922,
    danger = 0xF85149,
}

-- 控件引用
local R = {}
local last = {}     -- 上一次的文本，用于避免重复 set_text
local input = ""    -- 键盘输入缓冲（空串表示没有正在输入的数字）

-- ==================== 小工具 ====================

--[[把动作挪出 LVGL 回调上下文执行；
定时器创建失败时直接执行，避免出现"点了没反应"]]
local function defer(fn)
    local ok, id = pcall(sys.timerStart, function()
        local ok2, err = pcall(fn)
        if not ok2 then log.error("ui", "defer error", tostring(err)) end
    end, 10)
    if not ok or not id or id == 0 then
        local ok3, err3 = pcall(fn)
        if not ok3 then log.error("ui", "defer inline error", tostring(err3)) end
    end
end

local function label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font_size = size or 20,
        color = color or C.ink,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function card(parent, x, y, w, h)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = C.panel, radius = 12, border_width = 0,
    })
end

local function button(parent, x, y, w, h, text, size, bg, fg, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = bg or C.panel2, bg_opa = 255,
            text_color = fg or C.ink,
            radius = 10, border_width = 0,
            border_color = bg or C.panel2,
            pressed_bg_color = C.line,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[只在文本变化时更新，减少重绘]]
local function set_text(key, text)
    if last[key] == text then return end
    last[key] = text
    local obj = R[key]
    if obj then obj:set_text(text) end
end

local function fmt_freq(hz)
    if hz >= 1000 then
        return string.format("%.1f kHz", hz / 1000)
    end
    return string.format("%d Hz", hz)
end

-- ==================== 个数输入（数字键盘） ====================

--[[把输入缓冲提交成目标脉冲数]]
local function commit_input()
    if input == "" then return end
    pulse.set_count(tonumber(input) or 0)
    input = ""
    M.refresh()
end

local function input_digit(d)
    if #input >= 7 then return end          -- 最大 9999999，set_count 再按上限截断
    if input == "0" then input = "" end
    input = input .. tostring(d)
    M.refresh()
end

--[[清零：缓冲置成 "0"，再点确定即为 0（连续输出）]]
local function input_clear()
    input = "0"
    M.refresh()
end

local function input_back()
    if #input > 0 then
        input = input:sub(1, #input - 1)
        M.refresh()
    end
end

-- ==================== 界面构建 ====================

local function build_top()
    airui.container({
        parent = R.root, x = 0, y = 0, w = SW, h = 64,
        color = C.panel2, radius = 0, border_width = 0,
    })
    label(R.root, 24, 14, 560, 36, "伺服脉冲 / 方向 控制", 26, C.ink)
    R.top = label(R.root, 600, 18, 400, 28, "", 20, C.ink2, airui.TEXT_ALIGN_RIGHT)
    label(R.root, 24, 72, 900, 20,
        "PWM1 → GPIO65（脉冲）  ·  GPIO9（方向）  ·  固定 1kHz / 50%，个数由右侧键盘输入", 16, C.ink3)
end

local function build_dir()
    local c = card(R.root, 24, 100, 620, 132)
    label(c, 20, 12, 260, 28, "方向输出 GPIO" .. conf.dir.gpio, 20, C.ink)
    R.dir = label(c, 240, 6, 360, 36, "", 26, C.ok, airui.TEXT_ALIGN_RIGHT)

    button(c, 20, 62, 180, 52, "输出高电平", 20, C.ok, 0x06210C, function()
        defer(function()
            pulse.set_direction_level(1)
            M.refresh()
        end)
    end)
    button(c, 216, 62, 180, 52, "输出低电平", 20, C.panel2, C.ink, function()
        defer(function()
            pulse.set_direction_level(0)
            M.refresh()
        end)
    end)
    label(c, 416, 74, 184, 22, "点击立即生效", 16, C.ink3)
end

local function build_pulse()
    local c = card(R.root, 24, 248, 620, 336)
    label(c, 20, 12, 300, 28, "脉冲输出 PWM" .. P.pwm_ch, 20, C.ink)
    R.param = label(c, 20, 52, 300, 26, "", 18, C.ink2)

    -- 脉冲个数（目标值，由右侧键盘输入）
    label(c, 20, 118, 160, 24, "脉冲个数", 16, C.ink2)
    R.count = label(c, 200, 112, 380, 32, "", 20, C.accent, airui.TEXT_ALIGN_RIGHT)
    label(c, 20, 214, 560, 22, "个数由右侧键盘输入，0 = 连续输出；停止请点 PWM停止，停止前不能再启动", 16, C.ink3)

    -- 启停
    button(c, 20, 256, 280, 52, "PWM启动", 20, C.accent, 0xFFFFFF, function()
        log.info("ui", "点击：PWM启动")
        defer(function()
            commit_input()      -- 有没确认的输入先确认
            local ok, err = pulse.start()
            if not ok then
                log.warn("ui", "启动被忽略（消抖）：", tostring(err))
            end
            M.refresh()
        end)
    end)
    button(c, 320, 256, 260, 52, "PWM停止", 20, C.danger, 0xFFFFFF, function()
        -- 这条日志能区分"点击没进回调"和"进了回调但 PWM 停不下来"
        log.info("ui", "点击：PWM停止")
        defer(function() pulse.stop("界面停止"); M.refresh() end)
    end)
end

local function build_keypad()
    local c = card(R.root, 664, 306, 336, 278)
    label(c, 16, 8, 304, 26, "脉冲个数输入", 20, C.ink)

    -- 数字 1~9
    for row = 0, 2 do
        for col = 0, 2 do
            local d = row * 3 + col + 1
            button(c, 16 + col * 106, 40 + row * 45, 100, 40, tostring(d), 20,
                C.panel2, C.ink, function()
                    defer(function() input_digit(d) end)
                end)
        end
    end

    -- 第 4 行：清零 / 0 / 退格
    button(c, 16, 175, 100, 40, "清零", 20, C.panel2, C.ink, function()
        defer(input_clear)
    end)
    button(c, 122, 175, 100, 40, "0", 20, C.panel2, C.ink, function()
        defer(function() input_digit(0) end)
    end)
    button(c, 228, 175, 100, 40, "退格", 20, C.panel2, C.ink, function()
        defer(input_back)
    end)

    button(c, 16, 228, 304, 46, "确定", 20, C.ok, 0x06210C, function()
        log.info("ui", "点击：确定个数")
        defer(commit_input)
    end)
end

local function build_status()
    local c = card(R.root, 664, 100, 336, 190)
    label(c, 16, 12, 200, 28, "运行状态", 20, C.ink)
    R.run = label(c, 16, 44, 304, 40, "", 26, C.warn)

    R.freq    = label(c, 16, 92, 304, 22, "", 16, C.ink2)
    R.rpm     = label(c, 16, 116, 304, 22, "", 16, C.ink2)
    R.elapsed = label(c, 16, 140, 304, 22, "", 16, C.ink2)
end

-- ==================== 对外接口 ====================

function M.build()
    R.root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, radius = 0, border_width = 0,
    })
    build_top()
    build_dir()
    build_pulse()
    build_status()
    build_keypad()
    M.refresh()
    log.info("ui", "界面构建完成")
end

--[[刷新状态文本（只在内容变化时真正 set_text）]]
function M.refresh()
    local s = pulse.snapshot()

    set_text("top", string.format("%s   ·   方向 %s",
        s.running and "运行中" or "已停止", s.dir_level == 1 and "高" or "低"))

    set_text("dir", s.dir_level == 1 and "高电平 (3.3V)" or "低电平 (0V)")
    set_text("param", string.format("固定参数：频率 %s · 占空比 %d%%", fmt_freq(s.freq), s.duty))

    if input ~= "" then
        set_text("count", "输入 " .. input .. "_")
    else
        set_text("count", s.count == 0 and "连续输出" or tostring(s.count))
    end

    set_text("run", s.running and "运行中" or "已停止")
    set_text("freq", "频率  " .. fmt_freq(s.freq))
    set_text("rpm", string.format("转速  ≈ %.1f rpm", s.rpm))
    if s.running then
        set_text("elapsed", string.format("已运行  %.1f s", s.elapsed_ms / 1000))
    else
        set_text("elapsed", string.format("上次运行  %.1f s", (s.elapsed_ms or 0) / 1000))
    end
end

function M.run()
    sys.taskInit(function()
        while true do
            M.refresh()
            sys.wait(U.refresh_ms)
        end
    end)
end

return M
