--[[
@module  app_data
@summary Modbus 两路温度采集 + 量程换算 + 历史趋势缓存（纯只读）
@version 1.0.0
@date    2026.11.16

数据流：
  轮询(500ms) → 读 4x6700 起 4 个 → 解 CDAB 浮点 → 加偏移 → 通知 UI
  → 采样任务(5s) 追加历史 → 曲线刷新

注意：
  - 离线时保留最后一次有效值并置 online=false，UI 置灰，不造假 0，避免误报警；
  - 历史只在在线且非故障时追加，断线期间曲线停住，不画误导性的平直线。
]]
local M = {}

local conf = require "conf"
local alarm = require "app_alarm"
local mb = require "drv_modbus"

-- ===== 对外数据 =====
M.val = {}            -- 工程量（℃）
M.raw = {}            -- 原始读数（换算前）
M.hist = {}           -- 历史，[ch][1..cap]
M.online = false
M.ok_count = 0
M.err_count = 0
M.fail_streak = 0
M.last_err = nil
M.opened = false
M.last_ok_time = 0
M.offline_flag = false   -- 是否已判定为断线

local listeners = {}

function M.on_update(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

local function notify(evt)
    for i = 1, #listeners do
        pcall(listeners[i], evt)
    end
end

--[[
原始读数 → 温度
读到的浮点已经是摄氏度，这里主要是保留量程与偏移的接口
]]
function M.raw_to_val(raw, ch)
    local s = conf.scale
    local span = s.raw_max - s.raw_min
    local v
    if span == 0 then
        v = s.val_min
    else
        v = (raw - s.raw_min) * (s.val_max - s.val_min) / span + s.val_min
    end
    if ch and ch.offset then v = v + ch.offset end
    return v
end

local function push_hist(idx, v)
    local h = M.hist[idx]
    h[#h + 1] = v
    local cap = conf.trend.cap
    if #h > cap then
        table.move(h, #h - cap + 1, #h, 1)
        for i = cap + 1, #h do h[i] = nil end
    end
end

local function handle_success(regs)
    local s = conf.scale
    local c1 = mb.regs_to_float(regs[1] or 0, regs[2] or 0, s.word_swap)
    local c2 = mb.regs_to_float(regs[3] or 0, regs[4] or 0, s.word_swap)

    M.raw[1], M.raw[2] = c1, c2
    M.val[1] = M.raw_to_val(c1, conf.chs[1])
    M.val[2] = M.raw_to_val(c2, conf.chs[2])

    M.ok_count = M.ok_count + 1
    M.fail_streak = 0
    M.last_err = nil
    M.last_ok_time = os.time()

    if not M.online then
        M.online = true
        if M.offline_flag then
            M.offline_flag = false
            alarm.on_comm(true)
        end
        log.info("app_data", "PLC 通讯恢复")
        notify("online")
    end
    notify("poll")

    -- 判定挂在采集链路上，保证判定与显示用的是同一份数据
    for i = 1, #conf.chs do
        alarm.eval(i, M.val[i])
    end
end

local function handle_fail(err)
    M.err_count = M.err_count + 1
    M.fail_streak = M.fail_streak + 1
    M.last_err = err
    log.warn("app_data", "读取失败，连续", M.fail_streak, tostring(err))

    -- 用独立标志位判定：开机时 M.online 本来就是 false，
    -- 若只看 M.online 会漏掉"一上电就连不上"这种情况，界面会一直显示绿色正常
    if (not M.offline_flag) and M.fail_streak >= (conf.offline_retry or 3) then
        M.offline_flag = true
        M.online = false
        log.error("app_data", "PLC 通讯中断")
        alarm.on_comm(false)
        notify("offline")
    end
end

function M.init()
    for i = 1, #conf.chs do
        M.val[i] = M.val[i] or 0
        M.raw[i] = M.raw[i] or 0
        M.hist[i] = M.hist[i] or {}
    end
end

function M.start()
    -- 采集任务
    sys.taskInit(function()
        while true do
            if not M.opened then
                local ok, err = mb.init()
                if ok then
                    M.opened = true
                    log.info("app_data", "串口已打开", conf.uart.baud .. " 8N1")
                else
                    log.error("app_data", "串口打开失败", tostring(err))
                    sys.wait(2000)
                end
            end

            if M.opened then
                local regs, err = mb.read_raw(conf.plc.slave, conf.plc.reg, conf.plc.count)
                if regs then
                    handle_success(regs)
                else
                    handle_fail(err)
                end
            end

            sys.wait(conf.poll_ms)
        end
    end)

    -- 曲线采样任务（与轮询解耦，5s 一点）
    sys.taskInit(function()
        while true do
            sys.wait(conf.sample_ms)
            if M.online then
                for i = 1, #conf.chs do
                    local v = M.val[i]
                    -- 故障/断线时留空，曲线断开，不画假平线
                    if v and v > conf.alarm.raw_fault then
                        push_hist(i, v)
                    end
                end
                notify("sample")
            end
        end
    end)
end

return M
