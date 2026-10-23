--[[
@module  periph_rs485
@summary RS485 外设驱动（config.peripherals 中 type="rs485"，支持多路）
@version 1.1
@date    2026.10.23
@author  江访

=== 配置示例 ===

config/eng_xxx.lua 声明（同一 type 可多条，靠 id 区分）：
   peripherals = {
       { type = "rs485", id = "485_1", name = "非隔离485", uart_id = 1,
         de_pin = 65, power_pin = 14, baud = 9600 },
       { type = "rs485", id = "485_2", name = "隔离485",   uart_id = 1,
         de_pin = nil, power_pin = 14, baud = 9600 },
   }

=== 接口 ===

M.init(params)     → handle | false, err
M.list()           → { {id=, name=, handle=}, ... }
M.get(id)          → handle
M.reset_all()      → 关闭全部实例并清空注册表

handle.id / handle.name / handle.params
handle:start()     → ok, err     上电 + DE 置接收态 + 打开串口
handle:send(data)  → ok, err     DE 置发送态 → 发送 → 延时 → DE 置接收态
handle:recv()      → data|nil    取走环形缓冲里的全部接收数据（拉取式）
handle:stop()      → ok          关闭串口 + DE 置接收态 + 释放供电
handle:status()    → { enabled=bool, info=string }

=== 事件 ===

收到数据时逐包广播：sys.publish("PERIPH_RX", handle.id, data)
订阅方（如 ui/rs485_test_win.lua）自行拼历史记录，驱动不维护发送历史。

=== 约定 ===

- power_pin 为所在供电域总使能脚，多路共用同一 power_pin：引用计数管理，
  首路上电拉高，末路断电才拉低
- de_pin 可为 nil（该路 DE 未引出 / 自动方向），缺失时跳过方向切换
- 同一 uart_id 上的多条记录共享该串口的收发计数与环形缓冲
- de_pin 接收态为低电平，发送态为高电平
- 所有 uart.* / gpio.* 调用 pcall 包裹，失败返回 false + 错误串
]]

local M = {}

-- 环形缓冲保留条数
local RING_MAX = 8

-- 已登记实例：id → handle
local instances = {}
-- 已登记实例：uart_id → { handle, ... }
local uart_users = {}
-- 供电脚引用计数：pin → 次数
local power_ref = {}

-- 校验位 → uart 校验常量
local function parity_to_const(p)
    if type(p) == "number" then return p end
    local s = tostring(p or "N"):upper()
    if s == "E" or s == "EVEN" then return uart.Even end
    if s == "O" or s == "ODD" then return uart.Odd end
    return uart.None
end

-- 等待毫秒，非协程环境跳过
local function wait_ms(ms)
    if not ms or ms <= 0 then return end
    local co = coroutine and coroutine.running and coroutine.running()
    if co == nil then return end
    pcall(sys.wait, ms)
end

-- 设置 GPIO 电平
local function pin_set(pin, level)
    if not pin then return end
    pcall(gpio.setup, pin, level)
    pcall(gpio.set, pin, level)
end

-- 供电脚上电（引用计数 +1，首路才拉高）
local function power_acquire(pin)
    if not pin then return end
    local n = (power_ref[pin] or 0) + 1
    power_ref[pin] = n
    if n == 1 then
        pin_set(pin, 1)
    end
end

-- 供电脚断电（引用计数 -1，末路才拉低）
local function power_release(pin)
    if not pin then return end
    local n = power_ref[pin] or 0
    if n <= 1 then
        power_ref[pin] = nil
        if n == 1 and pin ~= 12 then
            pin_set(pin, 0)
        end
        return
    end
    power_ref[pin] = n - 1
end

-- 串口接收回调：读取数据写入环形缓冲、累计接收计数并广播给订阅方
local function on_receive(uart_id, len)
    local users = uart_users[uart_id]
    if not users then return end
    local ok, data = pcall(uart.read, uart_id, len or 0)
    if not ok or type(data) ~= "string" or #data == 0 then return end
    for i = 1, #users do
        local h = users[i]
        h.rx_count = h.rx_count + #data
        local ring = h.rx_ring
        ring[#ring + 1] = data
        while #ring > RING_MAX do table.remove(ring, 1) end
        sys.publish("PERIPH_RX", h.id, data)
    end
end

-- 计算 DE 方向切换等待时长（毫秒）
local function tx_delay_ms(self, datalen)
    local p = self.params
    if p.tx_delay then return p.tx_delay end
    local baud = p.baud or 9600
    if baud <= 0 then return 5 end
    return math.floor((datalen + 2) * 12 * 1000 / baud) + 2
end

-- 打开串口（上电 → DE 接收态 → uart.setup）
local function rs485_start(self)
    local p = self and self.params
    if not p then return false, "invalid handle" end
    if not p.uart_id then return false, "missing uart_id" end
    if self.enabled then return true end

    power_acquire(p.power_pin)
    pin_set(p.de_pin, 0)

    local baud = p.baud or 9600
    local ok, ret = pcall(uart.setup, p.uart_id, baud, p.databits or 8, p.stopbits or 1,
                          parity_to_const(p.parity))
    if not ok or (ret ~= nil and ret ~= 0) then
        power_release(p.power_pin)
        return false, "uart.setup: " .. tostring(ret)
    end

    self.baud     = baud
    self.tx_count = 0
    self.rx_count = 0
    self.rx_ring  = {}
    self.enabled  = true

    local users = uart_users[p.uart_id]
    if not users then
        users = {}
        uart_users[p.uart_id] = users
    end
    users[#users + 1] = self
    if #users == 1 then
        ok, ret = pcall(uart.on, p.uart_id, "receive", on_receive)
        if not ok then
            log.warn("periph_rs485", "接收回调注册失败", self.id, ret)
        end
    end
    log.info("periph_rs485", "485 已打开", self.id, p.uart_id, baud)
    return true
end

-- 发送数据（DE 切换到发送态）
local function rs485_send(self, data)
    if not self or not self.enabled then return false, "not started" end
    if type(data) ~= "string" or #data == 0 then return false, "empty data" end
    local p = self.params

    pin_set(p.de_pin, 1)
    local ok, ret = pcall(uart.write, p.uart_id, data)
    if not ok then
        pin_set(p.de_pin, 0)
        return false, "uart.write: " .. tostring(ret)
    end
    wait_ms(tx_delay_ms(self, #data))
    pin_set(p.de_pin, 0)

    if type(ret) == "number" and ret > 0 then
        self.tx_count = self.tx_count + ret
    else
        self.tx_count = self.tx_count + #data
    end
    return true
end

-- 取走环形缓冲里的全部接收数据（拉取式；订阅 PERIPH_RX 的一方无需调用）
local function rs485_recv(self)
    if not self then return nil end
    local ring = self.rx_ring
    if type(ring) ~= "table" or #ring == 0 then return nil end
    local data = table.concat(ring)
    self.rx_ring = {}
    return data
end

-- 关闭串口（DE 接收态 → 释放供电）
local function rs485_stop(self)
    if not self then return false end
    if not self.enabled then return true end
    local p = self.params

    if p.uart_id then
        local users = uart_users[p.uart_id]
        if users then
            for i = #users, 1, -1 do
                if users[i] == self then table.remove(users, i) end
            end
            if #users == 0 then
                uart_users[p.uart_id] = nil
                pcall(uart.close, p.uart_id)
            end
        end
    end
    pin_set(p.de_pin, 0)
    power_release(p.power_pin)
    self.enabled = false
    log.info("periph_rs485", "485 已关闭", self.id)
    return true
end

-- 读取状态
local function rs485_status(self)
    if not self then return { enabled = false, info = "invalid" } end
    local p = self.params or {}
    local de = p.de_pin and ("DE:GPIO" .. tostring(p.de_pin)) or "DE:自动"
    return {
        enabled = self.enabled and true or false,
        info = string.format("%s | UART%d | %s | %d", self.id or p.id or "?",
                             p.uart_id or 0, de, self.baud or p.baud or 9600),
        stats = { tx = self.tx_count or 0, rx = self.rx_count or 0 },
    }
end

-- 创建 handle 并挂载方法
local function make_handle(params)
    local h = {
        id      = params.id,
        name    = params.name or params.id,
        params  = params,
        enabled = false,
        tx_count = 0,
        rx_count = 0,
        rx_ring  = {},
    }
    h.start  = rs485_start
    h.send   = rs485_send
    h.recv   = rs485_recv
    h.stop   = rs485_stop
    h.status = rs485_status
    return h
end

--[[
登记 RS485 实例（不打开串口）
@param table params  config.peripherals 条目
@return table|false  handle 或 false, 错误串
]]
function M.init(params)
    if type(params) ~= "table" then return false, "params must be table" end
    if not params.id then return false, "missing id" end
    if not params.uart_id then return false, "missing uart_id" end
    if instances[params.id] then return false, "duplicated id: " .. tostring(params.id) end
    local h = make_handle(params)
    instances[params.id] = h
    log.info("periph_rs485", "485 已登记", params.id, params.uart_id)
    return h
end

--[[
列出已登记实例
@return table  { {id=, name=, handle=}, ... }
]]
function M.list()
    local out = {}
    for id, h in pairs(instances) do
        out[#out + 1] = { id = id, name = h.name, handle = h }
    end
    return out
end

--[[
取单个实例 handle
@param string id  实例 id
@return table|nil  handle
]]
function M.get(id)
    return instances[id]
end

-- 关闭全部实例并清空注册表
function M.reset_all()
    for id, h in pairs(instances) do
        pcall(h.stop, h)
        instances[id] = nil
    end
    uart_users = {}
    power_ref = {}
    return true
end

return M
