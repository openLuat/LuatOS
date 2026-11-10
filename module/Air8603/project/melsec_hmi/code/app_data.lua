--[[
@module  app_data
@summary 三菱 FX 两路温度采集 + 量程换算 + 历史趋势缓存（纯只读）
@version 1.0.0
@date    2026.11.09

数据流：
  轮询(1000ms) → WR 读 D0~D1 → raw[i] → 量程换算 val[i]（0~4000 → 0~100.0℃）
  → 通知 UI → 采样任务(2s) 追加历史 → 曲线刷新

只读设计：不向 PLC 写任何数据（无 WW/BW），避免误改 PLC 里的运行参数。
错误判定用 fxlinks 的 err 字符串（NAK / 超时 / 校验错）。

注意：
  - fxlinks 的 read_words 内部用 sys.waitUntil 等待响应，只能在协程里调用；
  - 离线时保留最后一次有效值并置 online=false，UI 置灰，不做假 0 值，避免误报警；
  - 历史只在在线时追加，断线期间曲线停住，不画误导性的平直线。
]]
local M = {}

local conf = require "conf"
local alarm = require "app_alarm"
local fx = require "drv_fxlinks"

-- ===== 对外数据 =====
M.raw = {}            -- AD 原始值
M.val = {}            -- AD 工程量（℃）
M.hist = {}           -- 历史工程量，[ch][1..cap]
M.stamps = {}         -- 历史时间戳，与 hist 一一对应
M.online = false      -- 通讯是否在线
M.ok_count = 0        -- 成功次数
M.err_count = 0       -- 失败次数
M.fail_streak = 0     -- 连续失败次数
M.last_err = nil      -- 最近一次错误描述
M.opened = false      -- 串口是否已打开
M.poll_ms = conf.poll_ms or 1000

local listeners = {}

--[[
注册数据更新回调
@param fn function 回调，参数为事件名："poll" / "sample" / "online" / "offline"
@return nil
]]
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
原始值 → 温度换算（0~4000 → 0~100.0℃）
@param raw number 原始值
@return number 温度，已按量程钳位
]]
function M.raw_to_val(raw)
    local s = conf.scale
    local span = s.raw_max - s.raw_min
    if span == 0 then
        return s.val_min
    end
    local v = (raw - s.raw_min) * (s.val_max - s.val_min) / span + s.val_min
    if v < s.val_min then
        v = s.val_min
    elseif v > s.val_max then
        v = s.val_max
    end
    return v
end

local function push_hist(idx, v)
    local h, t = M.hist[idx], M.stamps[idx]
    h[#h + 1] = v
    t[#t + 1] = os.time()

    local cap = conf.trend.cap
    local over = #h - cap
    if over > 0 then
        -- 一次性裁掉头部超出部分，避免 table.remove(1) 反复搬移
        table.move(h, over + 1, #h, 1)
        table.move(t, over + 1, #t, 1)
        for i = #h, #h - over + 1, -1 do
            h[i] = nil
            t[i] = nil
        end
    end
end

--[[
判断一组点表是否地址连续（同软元件且 addr 逐 1 递增）
@param list table 点表
@return boolean
]]
local function is_contiguous(list)
    if #list < 1 then
        return false
    end
    for k = 2, #list do
        if list[k].dev ~= list[1].dev or list[k].addr ~= list[k - 1].addr + 1 then
            return false
        end
    end
    return true
end

--[[
读两路温度（D0/D1）：地址连续时一帧读完，否则逐点读
@return table|nil 原始值数组, string|nil 错误
]]
local function read_ad()
    local chs = conf.chs

    if is_contiguous(chs) then
        return fx.read_words(chs[1].dev, chs[1].addr, #chs)
    end

    local out = {}
    for i = 1, #chs do
        local v, err = fx.read_words(chs[i].dev, chs[i].addr, 1)
        if not v then
            return nil, err
        end
        out[i] = v[1]
    end
    return out
end

local function handle_success(raws)
    for i = 1, #conf.chs do
        local raw = raws[i]
        if raw then
            M.raw[i] = raw
            M.val[i] = M.raw_to_val(raw)
        end
    end

    M.ok_count = M.ok_count + 1
    M.fail_streak = 0
    M.last_err = nil

    if not M.online then
        M.online = true
        log.info("app_data", "PLC 通讯恢复")
        notify("online")
    end
    notify("poll")

    -- 报警判定挂在采集链路上，保证判定与显示用的是同一份数据
    for i = 1, #conf.chs do
        alarm.eval(i, M.val[i])
    end
end

local function handle_fail(err)
    M.err_count = M.err_count + 1
    M.fail_streak = M.fail_streak + 1
    M.last_err = err
    log.warn("app_data", "读取失败，连续", M.fail_streak, tostring(err))

    if M.online and M.fail_streak >= (conf.offline_retry or 3) then
        M.online = false
        log.error("app_data", "PLC 通讯中断")
        notify("offline")
    end
end

--[[
初始化数据结构（main 里在载入 conf 后调用一次）
@return nil
]]
function M.init()
    for i = 1, #conf.chs do
        M.raw[i] = M.raw[i] or 0
        M.val[i] = M.val[i] or 0
        M.hist[i] = M.hist[i] or {}
        M.stamps[i] = M.stamps[i] or {}
    end
end

--[[
启动采集任务与采样任务（板级上电完成后调用）
@return nil
]]
function M.start()
    -- 采集任务：开串口 → 循环读温度
    sys.taskInit(function()
        -- 开机首帧常因 485 方向脚首次切换失败，允许静默重试一次，不报警不计失败
        local warmup = 1

        while true do
            if not M.opened then
                local ok, err = fx.init(conf.uart, conf.plc)
                if ok then
                    M.opened = true
                else
                    log.error("app_data", "串口打开失败", tostring(err))
                    sys.wait(2000)
                end
            end

            if M.opened then
                local raws, err = read_ad()
                if raws then
                    warmup = 0
                    handle_success(raws)
                elseif warmup > 0 then
                    warmup = warmup - 1
                    log.info("app_data", "开机首帧预热失败，立即重试", tostring(err))
                else
                    handle_fail(err)
                end

                sys.wait(M.poll_ms)
            end
        end
    end)

    -- 采样任务：固定 2s 追加历史，与轮询周期解耦，保证曲线时间轴均匀
    sys.taskInit(function()
        while true do
            sys.wait(conf.trend.sample_ms)
            if M.online then
                for i = 1, #conf.chs do
                    push_hist(i, M.val[i])
                end
                notify("sample")
            end
        end
    end)
end

--[[
关闭串口（热复位/切工程时用）
@return nil
]]
function M.close()
    if M.opened then
        pcall(fx.close)
        M.opened = false
    end
end

return M
