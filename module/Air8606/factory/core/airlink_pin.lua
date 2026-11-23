--[[
@module  airlink_pin
@summary WiFi 芯片侧 GPIO 门控（GPIO ≥100 等 airlink 链路就绪后再下发）
@version 1.2
@date    2026.11.05
@author  江访

=== 背景 ===

Air8000 / Air860x 的 WiFi 芯片（Air601S 等）侧 GPIO 映射在 GPIO100 以上，
按 Air8000 规则 W_GPIOn → GPIO(128+n)。这些脚不由主控直接驱动，要靠 airlink
通道代为下发，airlink 链路未建立时下发会失败或被丢弃。故 GPIO ≥100 一律等
airlink.ready() 之后再驱动。

=== 接口 ===

airlink_pin.is_wifi_pin(pin)          → 是否 WiFi 芯片侧引脚（GPIO ≥ 100）
airlink_pin.ready()                   → 现在能不能下发电平
airlink_pin.wait_ready(timeout)       → 等到能下发，返回是否就绪
airlink_pin.set(pin, level)           → 短等后下发，还没就绪就转 defer，不吊死调用方
airlink_pin.defer(pin, level, delay)  → 不阻塞调用方，链路就绪后按登记顺序重放

=== 约定 ===

- 只对声明了 airlink 网络的机型生效：没配 network.airlink 的板子一律立即下发，
  免得把 Air8000A 那类 GPIO ≥100 却是主控直驱的引脚也拖去等链路
- 无 airlink 库的机型（PC 模拟器等）一律立即下发
- 等待超时照样下发并告警：485 供电、UVC 供电不能因为链路没起来就永远不动作
- gpio.* 与 airlink.* 全部 pcall；airlink 判空在取函数引用之前，
  否则 pcall(airlink.ready) 会在解引用那步就抛错
]]

local tick_time = require "tick_time"

local M = {}

local WIFI_PIN_BASE = 100   -- GPIO ≥100 隶属 WiFi 芯片侧
local READY_TIMEOUT = 20000 -- 重放协程等链路就绪的最长时长
local SET_WAIT      = 3000  -- set 的短等时长，超时转 defer
local READY_POLL    = 500   -- 轮询间隔

local pending   = {}    -- 待重放队列 { {pin=, level=, delay=}, ... }
local worker_on = false -- 重放协程是否在跑

-- 本机型是否声明了 airlink 网络
local function gate_on()
    local list = _G.project_config and _G.project_config.network
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        local t = list[i] and list[i].type
        if type(t) == "string" and t:find("airlink", 1, true) then return true end
    end
    return false
end

-- airlink 库是否可用
local function has_airlink()
    return (airlink ~= nil) and (type(airlink.ready) == "function")
end

-- 是否在协程内（sys.wait 只在协程内有效）
local function in_coroutine()
    local co = coroutine and coroutine.running and coroutine.running()
    return co ~= nil
end

-- 直接写 GPIO
local function drive(pin, level)
    pcall(gpio.setup, pin, level)
    pcall(gpio.set, pin, level)
end

--[[
@function is_wifi_pin
@summary 是否 WiFi 芯片侧引脚
@param number pin  GPIO 编号
@return boolean
]]
function M.is_wifi_pin(pin)
    return (type(pin) == "number") and (pin >= WIFI_PIN_BASE)
end

--[[
@function ready
@summary 现在能不能下发电平（不需要门控 / 链路已就绪都算能）
@return boolean
]]
function M.ready()
    if not gate_on() then return true end
    if not has_airlink() then return true end
    local ok, r = pcall(airlink.ready)
    return ok and (r and true or false)
end

--[[
@function wait_ready
@summary 等到能下发电平，超时返回 false
@param number timeout  可选，最长等待毫秒
@return boolean
]]
function M.wait_ready(timeout)
    if M.ready() then return true end
    if not in_coroutine() then return M.ready() end
    local deadline = tick_time.deadline(timeout or READY_TIMEOUT)
    while not M.ready() do
        if tick_time.expired(deadline) then
            log.warn("airlink_pin", "等待 airlink 就绪超时，按现状下发")
            return false
        end
        pcall(sys.wait, READY_POLL)
    end
    return true
end

-- 链路就绪后按登记顺序重放
local function replay_worker()
    while #pending > 0 do
        local step = table.remove(pending, 1)
        M.wait_ready()
        drive(step.pin, step.level)
        log.info("airlink_pin", "airlink 就绪后补发", "GPIO" .. tostring(step.pin), step.level)
        if step.delay then pcall(sys.wait, step.delay) end
    end
    worker_on = false
end

--[[
@function defer
@summary 不阻塞调用方：能下发就立即下发，否则登记后等链路就绪重放
@param number pin    GPIO 编号
@param number level  电平 0/1
@param number delay  可选，重放后延时毫秒
@return boolean  true=已下发，false=已登记待重放
]]
function M.defer(pin, level, delay)
    if (not pin) or (level == nil) then return false end
    if (not M.is_wifi_pin(pin)) or M.ready() then
        drive(pin, level)
        return true
    end
    pending[#pending + 1] = { pin = pin, level = level, delay = delay }
    if not worker_on then
        worker_on = true
        sys.taskInit(replay_worker)
    end
    log.info("airlink_pin", "待 airlink 就绪后下发", "GPIO" .. tostring(pin), level)
    return false
end

--[[
@function set
@summary 就绪后下发电平；短等不到就转 defer，不吊死调用方
@param number pin    GPIO 编号
@param number level  电平 0/1
@return boolean  true=已下发
]]
function M.set(pin, level)
    if (not pin) or (level == nil) then return false end
    if not M.is_wifi_pin(pin) then
        drive(pin, level)
        return true
    end
    if M.ready() then
        drive(pin, level)
        return true
    end
    if in_coroutine() then M.wait_ready(SET_WAIT) end
    if M.ready() then
        drive(pin, level)
        return true
    end
    return M.defer(pin, level)
end

return M
