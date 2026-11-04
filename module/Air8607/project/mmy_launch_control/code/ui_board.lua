--[[
@module  ui_board
@summary 顶栏（品牌 / 发射窗口 / 阶段 / 大倒计时 / 时钟）与底部指令条
@version 1.0
@date    2026.11.04
]]
local conf    = require "conf"
local theme   = require "theme"
local kit     = require "kit"
local mission = require "mission"
local voice   = require "voice"

local C = theme.C
local M = {}

local cfg = conf.mission

-- ==================== 顶栏 ====================
function M.build_top(parent)
    theme.box(parent, 0, 0, conf.W, 56, C.bg3, 0, 255)
    theme.box(parent, 0, 0, conf.W, 2, C.amber, 0, 150)
    theme.hline(parent, 0, 56, conf.W, C.line)

    -- 品牌
    theme.box(parent, 16, 14, 3, 28, C.amber, 2)
    theme.label(parent, 27, 7, 250, 24, conf.en_name, 17, C.ink)
    theme.label(parent, 27, 31, 250, 16, cfg.vehicle .. " · 首次飞行", 11, C.ink3)

    -- 任务信息
    local function info(x, cap, val)
        theme.label(parent, x, 12, 110, 14, cap, 10, C.ink3)
        theme.label(parent, x, 26, 120, 20, val, 14, C.ink2)
    end
    info(276, "发射窗口", cfg.window)
    info(396, "发射工位", cfg.pad)

    -- 阶段胶囊
    local pill_box, pill_tx = theme.pill(parent, 524, 16, 100, 24, "待命", C.ink2, 12)

    -- 大倒计时
    local clock = theme.label(parent, 610, 0, 252, 44, "T-00:03:00", 34, C.amber,
        airui.TEXT_ALIGN_RIGHT)
    local clock_cap = theme.label(parent, 610, 42, 252, 14, "发射倒计时", 10, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    -- 时钟
    local time_lb = theme.label(parent, 874, 6, 134, 26, "--:--", 20, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local date_lb = theme.label(parent, 874, 32, 134, 14, "----/--/--", 11, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    return {
        pill_box = pill_box, pill_tx = pill_tx,
        clock = clock, clock_cap = clock_cap,
        time_lb = time_lb, date_lb = date_lb,
        last_clock = "", acc = 0,
    }
end

local WEEK = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

function M.tick_top(self, dt)
    self.acc = self.acc + dt
    if self.acc < 0.12 then return end
    self.acc = 0

    local st = mission.st
    local txt = kit.fmt_t(mission.clock())
    if txt ~= self.last_clock then
        self.last_clock = txt
        self.clock:set_text(txt)
    end

    local name, ckey = mission.phase_info()
    local col = C[ckey] or C.ink2
    if self.last_phase ~= st.phase then
        self.last_phase = st.phase
        self.pill_tx:set_text(name)
        self.pill_box:set_color(col, 40)
        self.pill_tx:set_color(col)
        self.clock_cap:set_text(st.phase == "standby" and "发射倒计时" or
            (st.phase == "check" and "起飞前自检" or "任务时间"))
    end

    -- 最后 3 秒倒计时转红
    local clock_col = C.amber
    if st.phase == "countdown" and st.mt > -3.5 then clock_col = C.red
    elseif st.phase == "orbit" then clock_col = C.green
    elseif st.phase == "standby" then clock_col = C.ink2 end
    if clock_col ~= self.last_clock_col then
        self.last_clock_col = clock_col
        self.clock:set_color(clock_col)
    end

    local t = os.date("*t")
    local hm = string.format("%02d:%02d", t.hour, t.min)
    if hm ~= self.last_hm then
        self.last_hm = hm
        self.time_lb:set_text(hm)
        self.date_lb:set_text(string.format("%02d/%02d %s", t.month, t.day,
            WEEK[(t.wday or 1)] or ""))
    end
end

-- ==================== 底部指令条 ====================
function M.build_bottom(parent, toast)
    theme.box(parent, 0, 520, conf.W, 80, C.bg3, 0, 255)
    theme.hline(parent, 0, 520, conf.W, C.line)

    local self = { toast = toast }

    self.btn_start = theme.button(parent, 12, 532, 200, 52, "开始倒计时", 19,
        C.amber, 0x0A0F18, function()
            local ok, err = mission.start()
            if not ok then toast(err or "无法启动") end
        end)

    theme.ghost(parent, 220, 532, 160, 52, "紧急中止", 16, C.red, function()
        local ok, err = mission.abort()
        if not ok then toast(err or "当前无需中止") end
    end, 0x5A2630)

    theme.ghost(parent, 388, 532, 124, 52, "重置任务", 16, C.ink2, function()
        mission.reset()
        toast("任务已重置，等待下一次发射")
    end)

    self.btn_auto = theme.ghost(parent, 520, 532, 160, 52, "自动演示 · 关", 15,
        C.ink2, function()
            local on = mission.set_auto(not mission.st.auto)
            toast(on and "自动演示已开启" or "自动演示已关闭")
        end)

    theme.label(parent, 692, 534, 236, 16, "全程约 58 秒 · 可随时中止", 11, C.ink3)
    theme.label(parent, 692, 554, 236, 16, "点「开始倒计时」手动发射", 11, C.ink3)

    -- 语音开关
    local mbox, mtx = theme.pill(parent, 936, 540, 74, 36, "语音 开", C.cyan, 12)
    mbox:set_on_click(function()
        if not voice.ready() then
            toast("当前固件无音频后端，仅界面模式")
            return
        end
        local on = voice.toggle()
        mtx:set_text(on and "语音 开" or "语音 关")
        mtx:set_color(on and C.cyan or C.ink3)
        toast(on and "语音播报已开启" or "语音播报已关闭")
    end)
    self.mute_tx = mtx

    return self
end

function M.tick_bottom(self)
    local auto = mission.st.auto
    if self.last_auto ~= auto then
        self.last_auto = auto
        self.btn_auto:set_text(auto and "自动演示 · 开" or "自动演示 · 关")
    end
end

-- ==================== 轻提示 ====================
function M.build_toast(parent)
    local box = theme.frame(parent, 748, 470, 264, 40, C.panel3, 10, C.amber, 1, 250)
    local lb = theme.label(box, 10, 11, 244, 20, "", 13, C.ink, airui.TEXT_ALIGN_CENTER)
    box:set_hidden(true)
    local self = { box = box, lb = lb, timer = nil }

    function self.show(text)
        self.lb:set_text(text or "")
        self.box:set_hidden(false)
        if self.timer then sys.timerStop(self.timer) end
        self.timer = sys.timerStart(function()
            self.timer = nil
            self.box:set_hidden(true)
        end, conf.toast.ms)
    end
    return self
end

return M
