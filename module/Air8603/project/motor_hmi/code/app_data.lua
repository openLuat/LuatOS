--[[
@module  app_data
@summary 采集任务：按 conf.poll_ms 轮询各台变频器，解析状态位与频率
@version 1.0.0
@date    2026.11.12

每台电机每周期只发一帧：读 2100H~2104H 连续 5 个寄存器，
一次拿回 故障码 / 状态位 / 频率指令 / 输出频率 / 输出电流。
总线占用最小，且保证变频器 P91 的心跳要求（poll_ms 必须 < P91）。

注意：本机型（1.5kW）驱动 0.12kW 电机时，输出电流处于采样盲区，
2104H 长期为 0，界面不要用它做判断，仅作参考显示。
]]
local M = {}

local conf = require "conf"
local mb = require "drv_modbus"

M.motors = {}          -- 每台电机的实时状态
M.online = false       -- 是否至少有一台在线
M.ok_count = 0         -- 累计成功帧数
M.err_count = 0        -- 累计失败帧数
M.last_err = ""
M.forced = nil         -- 调试用强制故障码，nil = 跟随真实值

local cfg = conf.motors

--[[
初始化状态表
@return nil
]]
function M.init()
    M.motors = {}
    for i, c in ipairs(cfg) do
        M.motors[i] = {
            key       = c.key,
            name      = c.name,
            station   = c.station,
            online    = false,
            fault     = 0,
            running   = false,
            fwd       = false,
            rev       = false,
            freq_cmd  = 0.0,
            freq_out  = 0.0,
            current   = 0.0,
            fail      = 0,
            ok_count  = 0,
            err_count = 0,
        }
    end
end

--[[
解析一帧 5 个寄存器，更新第 i 台的状态
@param i number 索引
@param regs table { fault, state, freq_cmd, freq_out, current }
@return nil
]]
local function apply(i, regs)
    local d = M.motors[i]
    local st = regs[2]

    d.fault     = M.forced or regs[1] or 0
    d.running   = ((st >> conf.st.run_bit) & 1) == 1
    d.fwd       = ((st >> conf.st.fwd_bit) & 1) == 1
    d.rev       = ((st >> conf.st.rev_bit) & 1) == 1
    d.freq_cmd  = (regs[3] or 0) / 100
    d.freq_out  = (regs[4] or 0) / 100
    d.current   = (regs[5] or 0) / 10

    d.online = true
    d.fail = 0
    d.ok_count = d.ok_count + 1
end

--[[
采集一轮
@return number 本轮成功的台数
]]
local function poll_once()
    local okn = 0

    for i, c in ipairs(cfg) do
        local regs, err = mb.read_regs(c.station, conf.regs.fault, 5)

        if regs then
            apply(i, regs)
            okn = okn + 1
            M.ok_count = M.ok_count + 1
        else
            local d = M.motors[i]
            d.fail = d.fail + 1
            d.err_count = d.err_count + 1
            M.err_count = M.err_count + 1
            M.last_err = tostring(err)
            if d.fail >= conf.offline_retry then
                d.online = false
            end
        end
    end

    M.online = false
    for i = 1, #M.motors do
        if M.motors[i].online then
            M.online = true
            break
        end
    end

    return okn
end

--[[
启动采集任务
@return nil
]]
function M.start()
    sys.taskInit(function()
        M.init()

        -- 串口初始化（哑帧需要第一台的站号）
        if cfg[1] then
            mb.set_first_station(cfg[1].station)
        end

        local ok, err = mb.init(conf.uart, conf.modbus)
        if not ok then
            log.error("app_data", "串口初始化失败", tostring(err))
        end

        while true do
            local okn = poll_once()
            sys.publish("MOTOR_DATA", okn)
            sys.wait(conf.poll_ms)
        end
    end)
end

--[[
取某台电机状态
@param i number 索引
@return table|nil
]]
function M.get(i)
    return M.motors[i]
end

--[[
调试用：强制指定故障码，模拟报警（传 0 或 nil 清除）
@param code number|nil
@return nil
]]
function M.force_fault(code)
    if code == nil or code == 0 then
        M.forced = nil
    else
        M.forced = code
    end
end

--[[
统计：运行中台数 / 总台数
@return number running, number total
]]
function M.count_running()
    local n = 0
    for _, d in ipairs(M.motors) do
        if d.online and d.running then
            n = n + 1
        end
    end
    return n, #M.motors
end

return M
