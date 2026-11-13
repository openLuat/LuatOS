--[[
@module  app_seq
@summary 启停控制与多台顺序启动状态机（含启动间隔延时、急停锁存）
@version 1.0.0
@date    2026.11.12

=== 顺序启动语义 ===
conf.seq.gap_s 是「相邻两台电机之间的间隔」，不是「按下后延时多久」。
    t=0     第 1 台启动
    t=gap   第 2 台启动
    t=2gap  第 3 台启动
单台电机时不会观察到延时效果，这是正常的——参数本身仍然有效并被保存。

=== 急停 ===
本工程的急停是纯软件动作：
    立即向所有台发停止命令 + 锁存急停标志 + 记一条报警，
    之后必须手动点「急停复位」才能再次启动。
它不具备安全等级：RS485 有几十毫秒延迟，HMI 死机或断线时软急停失效。
真正的安全急停必须用硬件常闭触点切断变频器前端接触器。
软件侧另有一道兜底：变频器 P91 = 2s，通讯一断它自己停车。
]]
local M = {}

local conf = require "conf"
local mb = require "drv_modbus"
local data = require "app_data"

M.estop = false        -- 急停锁存
M.busy = false         -- 顺序启动进行中
M.step = 0             -- 已启动到第几台
M.seq_id = 0           -- 序列令牌，用于取消
M.last_msg = ""
M.fail_id = 0          -- 失败事件计数，UI 靠它判断要不要弹窗
M.fail_msg = ""

local listeners = {}

--[[
注册状态变化回调
@param fn function(msg)
@return nil
]]
function M.on_change(fn)
    listeners[#listeners + 1] = fn
end

local function notify(msg)
    M.last_msg = msg or M.last_msg
    for _, fn in ipairs(listeners) do
        pcall(fn, M.last_msg)
    end
    sys.publish("SEQ_STATE", M.last_msg)
end

--[[
记录一次「命令发出但没生效」的失败，UI 会据此弹窗
@param msg string 说明文字
@return nil
]]
local function fail(msg)
    M.fail_id = M.fail_id + 1
    M.fail_msg = msg
    notify(msg)
end

--[[
向单台发运转命令
@param i number 索引
@param value number conf.cmd.run_fwd / conf.cmd.stop
@return boolean ok, string|nil err
]]
local function send(i, value)
    local m = conf.motors[i]
    if not m then return false, "索引越界" end
    local ok, err = mb.write_reg(m.station, conf.regs.run, value)
    if not ok then
        return false, string.format("%s 写入失败：%s", m.name, tostring(err))
    end
    return true
end

--[[
立即停止全部电机（不发间隔、不等响应结果都试一遍）
@return number 成功台数
]]
local function stop_all_now()
    local n = 0
    for i = 1, #conf.motors do
        local ok = send(i, conf.cmd.stop)
        if ok then n = n + 1 end
    end
    return n
end

--[[
顺序启动全部电机
@return boolean ok, string|nil err
]]
function M.start_all()
    if M.estop then
        return false, "急停未复位，禁止启动"
    end
    if M.busy then
        return false, "启动序列进行中"
    end
    if not data.online then
        return false, "通讯离线，无法启动"
    end

    -- 故障锁存时变频器仍会应答 2000H 的写命令（原样回显），但不会启动。
    -- 必须前置拦掉，否则界面会误报「启动完成」。
    for i, c in ipairs(conf.motors) do
        local d = data.get(i)
        if d and d.fault and d.fault ~= 0 then
            local fname = conf.faults[d.fault] or ("故障码 " .. tostring(d.fault))
            return false, string.format("%s 处于故障状态：%s\n请先点「故障复位」再启动。",
                c.name, fname)
        end
    end

    M.busy = true
    M.seq_id = M.seq_id + 1
    local my_id = M.seq_id
    M.step = 0

    local total = #conf.motors
    local gap = conf.seq.gap_s

    sys.taskInit(function()
        for i = 1, total do
            if M.seq_id ~= my_id then
                -- 被新的操作打断（停止/急停）
                M.busy = false
                return
            end

            local ok, err = send(i, conf.cmd.run_fwd)
            M.step = i

            if ok then
                notify(string.format("已启动 %d/%d：%s", i, total, conf.motors[i].name))
            else
                fail(string.format("启动命令发送失败 %d/%d：%s", i, total, tostring(err)))
            end

            -- 最后一台之后不再等待间隔
            if i < total and gap > 0 then
                local left = gap
                while left > 0 do
                    sys.wait(200)
                    if M.seq_id ~= my_id then
                        M.busy = false
                        return
                    end
                    left = left - 0.2
                end
            end
        end

        if M.seq_id ~= my_id then
            M.busy = false
            return
        end

        -- 命令被接受 ≠ 电机真的转了。等一个轮询周期，用状态位复核。
        sys.wait(800)
        if M.seq_id ~= my_id then
            M.busy = false
            return
        end

        M.busy = false
        M.step = 0

        local running = 0
        for i = 1, total do
            local d = data.get(i)
            if d and d.running then
                running = running + 1
            end
        end

        if running == 0 then
            fail("启动命令已发出，但未检测到电机运行。\n请检查变频器是否处于故障锁存，或频率设定是否为 0。")
        elseif running < total then
            notify(string.format("部分启动完成（%d/%d 台在运行）", running, total))
        else
            notify(string.format("全部启动完成（%d 台在运行）", total))
        end
    end)

    return true
end

--[[
停止全部电机（同时取消进行中的启动序列）
@return boolean ok, string|nil err
]]
function M.stop_all()
    -- 递增令牌即可让进行中的启动序列自行退出
    M.seq_id = M.seq_id + 1
    M.busy = false
    M.step = 0

    local n = stop_all_now()
    if n == 0 then
        return false, "停止命令发送失败"
    end
    notify(string.format("已停止（%d 台）", n))
    return true
end

--[[
停止单台
@param i number 索引
@return boolean ok, string|nil err
]]
function M.stop_one(i)
    M.seq_id = M.seq_id + 1
    M.busy = false
    local ok, err = send(i, conf.cmd.stop)
    if ok then
        local m = conf.motors[i]
        notify(string.format("已停止：%s", m and m.name or tostring(i)))
    end
    return ok, err
end

--[[
急停：立即停车 + 锁存
@return nil
]]
function M.estop_press()
    M.seq_id = M.seq_id + 1
    M.busy = false
    M.step = 0
    M.estop = true
    stop_all_now()
    notify("急停已按下，所有电机停止")
end

--[[
急停复位（只解除锁存，不会自动启动）
@return nil
]]
function M.estop_reset()
    M.estop = false
    notify("急停已复位，可以启动")
end

--[[
故障复位：向所有在线变频器发 2002H = 2
@return number 成功台数
]]
function M.reset_fault()
    local n = 0
    for i = 1, #conf.motors do
        local ok = mb.write_reg(conf.motors[i].station, conf.regs.reset, conf.cmd.reset)
        if ok then n = n + 1 end
    end
    if n > 0 then
        notify(string.format("故障复位已下发（%d 台）", n))
    end
    return n
end

return M
