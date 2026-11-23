--[[
@module  periph_uart
@summary 通用串口外设驱动（config.peripherals 中 type="uart"）
@version 1.1
@date    2026.11.20
@author  江访

=== 配置示例 ===

config/eng_xxx.lua 声明（同一 type 可多条，靠 id 区分）：
   peripherals = {
       { type = "uart", id = "uart2", name = "UART2", uart_id = 2,
         baud = 115200, databits = 8, parity = "N", stopbits = 1,
         power_pin = 41 },   -- [可选] 供电控制脚，经 air8606_resources 引用计数上/下电
   }

=== 接口 ===

M.init(params)    → handle | false, err
M.list()          → { {id=, name=, handle=}, ... }
M.get(id)         → handle
M.reset_all()     → 关闭全部实例并清空注册表

handle.id / handle.name / handle.params
handle:start()    → ok, err      打开串口
handle:send(data) → ok, err      发送数据
handle:recv()     → string       取走环形缓冲里的接收数据
handle:stop()     → ok           关闭串口
handle:status()   → { enabled=bool, info=string }

=== 约定 ===

- init 只登记参数，start 才执行 uart.setup
- parity 取字符串 "N"/"E"/"O"，或 uart.None / uart.Even / uart.Odd 常量
- 接收数据进环形缓冲，只保留最近 RING_MAX 条；收发计数按字节累计
- 接收回调为模块级具名函数，按 uart_id 反查实例；收到数据发布 PERIPH_RX(id, data)
- power_pin 供电控制脚：有 air8606_resources 时按引用计数上/下电（多路共用同一供电域时互不影响），
  没有该模块的型号树直接驱动；CAN 与 RS232 共用 UART2 装配的互斥走 share_group/share_kind
  仲裁（条目配了才参与，缺省不仲裁）
- 所有 uart.* 调用 pcall 包裹，失败返回 false + 错误串
]]

local M = {}

-- 共享仲裁与电源域引用计数是软依赖（模块名经变量传给 require，编译清单另行登记）：
-- 没有 air8606_resources 的型号树不参与仲裁、电源脚直接驱动，本模块照常可用
local RES_MOD = "air8606_resources"
local res_checked, res_cache = false, nil
local function resources()
    if not res_checked then
        res_checked = true
        local ok, m = pcall(require, RES_MOD)
        res_cache = (ok and type(m) == "table" and type(m.claim) == "function") and m or false
    end
    return res_cache or nil
end

-- 电源脚上/下电：有仲裁模块走引用计数，没有就直接驱动
local function power_set(self, on)
    local p = self and self.params
    if not p or not p.power_pin then return true end
    local r = resources()
    if r then
        if on then return r.power_on(p.power_pin, self) end
        return r.power_off(p.power_pin, self)
    end
    local ok, ret = pcall(gpio.setup, p.power_pin, on and 1 or 0)
    if not ok or not ret then return false, "供电脚 GPIO" .. tostring(p.power_pin) .. " 设置失败" end
    return true
end

-- 释放共享仲裁（条目配了 share_group 才参与）
local function unclaim(self)
    if self and self.share_group then
        local r = resources()
        if r then r.release(self.share_group, self) end
        self.share_group = nil
    end
end

-- 环形缓冲保留条数
local RING_MAX = 8

-- 已登记实例：id → handle
local instances = {}
-- 已登记实例：uart_id → handle
local uart_map = {}

-- 校验位 → uart 校验常量
local function parity_to_const(p)
    if type(p) == "number" then return p end
    local s = tostring(p or "N"):upper()
    if s == "E" or s == "EVEN" then return uart.Even end
    if s == "O" or s == "ODD" then return uart.Odd end
    return uart.None
end

-- 校验位 → 显示字符
local function parity_to_char(p)
    local s = tostring(p or "N"):upper()
    if s == "E" or s == "EVEN" then return "E" end
    if s == "O" or s == "ODD" then return "O" end
    return "N"
end

-- 串口接收回调：读取数据写入环形缓冲并累计接收计数
local function on_receive(uart_id, len)
    local h = uart_map[uart_id]
    if not h then return end
    local ok, data = pcall(uart.read, uart_id, len or 0)
    if not ok or type(data) ~= "string" or #data == 0 then return end
    h.rx_count = h.rx_count + #data
    local ring = h.rx_ring
    ring[#ring + 1] = data
    while #ring > RING_MAX do table.remove(ring, 1) end
    sys.publish("PERIPH_RX", h.id, data)
end

-- 打开串口
local function uart_start(self)
    local p = self and self.params
    if not p then return false, "invalid handle" end
    if not p.uart_id then return false, "missing uart_id" end
    if self.enabled then return true end
    if not uart or type(uart.setup) ~= "function" then return false, "固件缺少 UART 库" end
    if uart_map[p.uart_id] then return false, "串口已被其它实例占用" end
    -- 共享仲裁（如 8606 的 UART2 = CAN/RS232 二选一）：条目配 share_group 才参与
    local r, group = resources(), p.share_group
    if r and group then
        local claimed, err = r.claim(group, p.share_kind or "rs232", self, self.stop)
        if not claimed then return false, err end
        self.share_group = group
    end
    local powered, perr = power_set(self, true)
    if not powered then
        unclaim(self)
        return false, perr
    end
    if p.ready_delay and coroutine.isyieldable() then sys.wait(p.ready_delay) end

    local baud     = p.baud or 115200
    local databits = p.databits or 8
    local stopbits = p.stopbits or 1
    local ok, ret = pcall(uart.setup, p.uart_id, baud, databits, stopbits, parity_to_const(p.parity))
    -- 返回值口径两树并集：参考库只认 0，本树旧版容忍 nil（不同固件版本口径不同）
    if not ok or (ret ~= nil and ret ~= 0) then
        power_set(self, false)
        unclaim(self)
        return false, string.format("UART%d 打开失败(%s)，该串口可能已被其它外设占用",
                                    p.uart_id, tostring(ret))
    end

    self.baud     = baud
    self.databits = databits
    self.stopbits = stopbits
    self.parity   = parity_to_char(p.parity)
    self.rx_count = 0
    self.tx_count = 0
    self.rx_ring  = {}
    self.enabled  = true
    uart_map[p.uart_id] = self

    ok, ret = pcall(uart.on, p.uart_id, "receive", on_receive)
    -- 只把显式 false 当失败：成功口径 nil / true 都随固件
    if not ok or ret == false then
        self:stop()
        return false, "接收回调注册失败: " .. tostring(ret)
    end
    log.info("periph_uart", "串口已打开", self.id, p.uart_id, baud)
    return true
end

-- 发送数据（TX 缓冲满时 uart.write 返回 0：短暂让出重试剩余部分，别把缓冲满当线接错）
local function uart_send(self, data)
    if not self or not self.enabled then return false, "not started" end
    if type(data) ~= "string" or #data == 0 then return false, "empty data" end
    local written = 0
    for _ = 1, 3 do
        local ok, ret = pcall(uart.write, self.params.uart_id, data:sub(written + 1))
        if not ok then return false, "uart.write: " .. tostring(ret) end
        if ret == false then return false, "uart.write 失败" end
        if type(ret) ~= "number" then       -- 固件不回统计，按全量计
            written = #data
            break
        end
        written = written + ret
        if written >= #data then break end
        if coroutine.isyieldable() then sys.wait(10) end
    end
    if written < #data then
        return false, string.format("UART%d 发送缓冲满，已发 %d/%d 字节，请重试",
            self.params.uart_id, written, #data)
    end
    self.tx_count = self.tx_count + written
    return true
end

local function uart_recv(self)
    local data = table.concat(self.rx_ring)
    self.rx_ring = {}
    return data
end

-- 关闭串口
local function uart_stop(self)
    if not self then return false end
    if not self.enabled then return true end
    if self.params and self.params.uart_id then
        local ok, ret = pcall(uart.close, self.params.uart_id)
        if not ok or ret == false then return false, "UART 关闭失败: " .. tostring(ret) end
        uart_map[self.params.uart_id] = nil
    end
    local ok, err = power_set(self, false)
    if not ok then return false, err end
    self.enabled = false
    unclaim(self)
    log.info("periph_uart", "串口已关闭", self.id)
    return true
end

-- 读取状态
local function uart_status(self)
    if not self then return { enabled = false, info = "invalid" } end
    local p = self.params or {}
    local name = self.name or p.id or "?"
    local baud = self.baud or p.baud or 115200
    local db   = self.databits or p.databits or 8
    local sb   = self.stopbits or p.stopbits or 1
    local par  = self.parity or parity_to_char(p.parity)
    return {
        enabled = self.enabled and true or false,
        info = string.format("%s | %d %d%s%d | TX:%d RX:%d", name, baud, db, par, sb,
                             self.tx_count or 0, self.rx_count or 0),
        stats = { tx=self.tx_count, rx=self.rx_count },
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
    h.start  = uart_start
    h.send   = uart_send
    h.recv   = uart_recv
    h.stop   = uart_stop
    h.status = uart_status
    return h
end

--[[
登记串口实例（不打开串口）
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
    log.info("periph_uart", "串口已登记", params.id, params.uart_id)
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
    uart_map = {}
    return true
end

return M
