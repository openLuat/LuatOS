--[[
@module periph_can
@summary Air8606 CAN2 收发诊断，和 RS232 互斥
@version 1.0.0
@date 2026.11.10

send(data, msg_id) 返回的成功仅表示提交；PERIPH_CAN_TX(id, ok) 表示总线发送结果。
PERIPH_CAN_RX(id, frame) 提供 {id,extended,rtr,data}，不把本机提交当作外部收包。
]]
local resources = require "air8606_resources"
local M = {}
local instances = {}
local buses = {}

local function clear_tx(h)
    if h.ack_timer then sys.timerStop(h.ack_timer); h.ack_timer = nil end
    h.awaiting_ack = false
end

local function choose_timing(p)
    if p.timing then return table.unpack(p.timing) end
    if type(can.capacity) ~= "function" then return nil, "固件缺少 CAN 时钟查询接口" end
    local ok, valid, clk, div_min, div_max, div_step = pcall(can.capacity, p.can_id)
    if not ok or not valid or type(clk) ~= "number" then return nil, "CAN 时钟参数不可用" end
    local br, best, score = p.bitrate or 500000, nil, math.huge
    div_step = div_step or 1
    if br <= 0 or not div_min or not div_max or div_step <= 0 then return nil, "CAN 波特率/分频参数无效" end
    for pts = 1, 8 do
        for pbs1 = 1, 8 do
            for pbs2 = 2, 8 do
                local tq = 1 + pts + pbs1 + pbs2
                local div = clk / (br * tq)
                if div == math.floor(div) and div >= div_min and div <= div_max
                    and (div - div_min) % div_step == 0 then
                    local rank = math.abs((1 + pts + pbs1) / tq - 0.8) * 100 + math.abs(tq - 16)
                    if rank < score then best, score = {pts, pbs1, pbs2, 2}, rank end
                end
            end
        end
    end
    if not best then return nil, "CAN 时钟无法精确配置所选波特率" end
    return table.unpack(best)
end

local function on_can(bus_id, event, param)
    local h = buses[bus_id]
    if not h or not h.enabled then return end
    if event == can.CB_MSG then
        while true do
            local ok, received, id, extended, rtr, data = pcall(can.rx, bus_id)
            if not ok then h.last_error = tostring(received); break end
            if not received then break end
            local frame = { id=id, extended=extended == 1, rtr=rtr, data=data or "" }
            h.rx_count = h.rx_count + 1
            h.rx_ring[#h.rx_ring + 1] = frame
            if #h.rx_ring > 32 then table.remove(h.rx_ring, 1) end
            log.info("factory_can", "RX", bus_id, string.format("0x%X", id), #frame.data)
            sys.publish("PERIPH_CAN_RX", h.id, frame)
        end
    elseif event == can.CB_TX then
        if not h.awaiting_ack then return end
        clear_tx(h)
        h.last_tx = param == true
        if h.last_tx then
            h.tx_ok = h.tx_ok + 1
            h.last_error = nil
        else
            h.last_error = "CAN 总线发送失败/未收到 ACK"
        end
        log.info("factory_can", "TX_ACK", bus_id, h.last_tx)
        sys.publish("PERIPH_CAN_TX", h.id, h.last_tx)
    elseif event == can.CB_ERR then
        h.last_error = string.format("CAN 错误 0x%08X", param or 0)
        if h.awaiting_ack then
            clear_tx(h)
            h.last_tx = false
            sys.publish("PERIPH_CAN_TX", h.id, false)
        end
        log.warn("factory_can", bus_id, h.last_error)
        sys.publish("PERIPH_CAN_ERROR", h.id, h.last_error)
    elseif event == can.CB_STATE then
        h.bus_state = param
    end
end

local function start(self)
    if self.enabled then return true end
    if self.initialized then return false, "CAN 上次关闭未完成，请先关闭再开启" end
    if not can then return false, "Air1602 固件未编入 CAN 库" end
    for _, name in ipairs({"init", "on", "timing", "mode", "rx", "tx", "stop", "deinit"}) do
        if type(can[name]) ~= "function" then return false, "固件缺少 can." .. name end
    end
    local p = self.params
    if buses[p.can_id] then return false, "CAN 总线已被其它实例占用" end
    local pts, pbs1, pbs2, sjw = choose_timing(p)
    if not pts then return false, pbs1 end
    local ok, err = resources.claim("uart2", "can", self, self.stop)
    if not ok then return false, err end
    self.claimed = true
    ok, err = resources.power_on(p.power_pin, self)
    if not ok then
        resources.release("uart2", self)
        self.claimed = false
        return false, err
    end
    local function fail(reason)
        local closed, why = self:stop()
        if not closed then reason = reason .. " | " .. tostring(why) end
        return false, reason
    end
    local called, ret = pcall(can.init, p.can_id, 128)
    if not called or ret ~= true then return fail("CAN 初始化失败: " .. tostring(ret)) end
    self.initialized = true
    called, ret = pcall(can.timing, p.can_id, p.bitrate or 500000, pts, pbs1, pbs2, sjw)
    if not called or ret ~= true then return fail("CAN 时序设置失败: " .. tostring(ret)) end
    -- CCM CAN2 使用默认全接收；该平台非 FIFO 接收过滤器不配置 node/filter。
    called, ret = pcall(can.on, p.can_id, on_can)
    if not called then return fail("CAN 回调注册失败: " .. tostring(ret)) end
    buses[p.can_id] = self
    self.enabled = true
    called, ret = pcall(can.mode, p.can_id, can.MODE_NORMAL)
    if not called or ret ~= true then
        self.enabled = false
        buses[p.can_id] = nil
        return fail("CAN 工作模式设置失败")
    end
    self.last_error = nil
    return true
end

local function stop(self)
    if not self.claimed then return true end
    if self.initialized then
        local ok, ret = pcall(can.deinit, self.params.can_id)
        if not ok or ret ~= true then return false, "CAN 关闭失败，暂不释放共用引脚" end
        self.initialized = false
        -- V1032 的 can.on(id,nil) 释放 Lua 引用后保留旧索引。deinit 已停硬件，
        -- 下次 init 后用 can.on(id,fn) 替换仍有效的引用，即可反复开关 CAN2。
        clear_tx(self)
    end
    local off, err = resources.power_off(self.params.power_pin, self)
    if not off then return false, err end
    buses[self.params.can_id] = nil
    self.enabled = false
    self.claimed = false
    resources.release("uart2", self)
    return true
end

local function send(self, data, id)
    if not self.enabled then return false, "CAN 尚未开启" end
    if self.awaiting_ack then return false, "等待上一帧的总线应答" end
    if type(data) ~= "string" or #data > 8 then return false, "经典 CAN 数据长度为 0~8 字节" end
    local p = self.params
    id = tonumber(id) or p.tx_id or 0x123
    local limit = p.extended and 0x1FFFFFFF or 0x7FF
    if id < 0 or id > limit or id ~= math.floor(id) then return false, "CAN 帧 ID 越界" end
    self.awaiting_ack = true
    local ok, ret = pcall(can.tx, p.can_id, id, p.extended and 1 or 0, false, true, data)
    -- Lua 绑定实际返回底层整数错误码，0 表示提交成功。
    if not ok or ret ~= 0 then
        clear_tx(self)
        return false, "CAN 发送提交失败: " .. tostring(ret)
    end
    self.tx_count = self.tx_count + 1
    if self.awaiting_ack then
        self.ack_timer = sys.timerStart(function()
            if not self.awaiting_ack then return end
            clear_tx(self)
            can.stop(p.can_id)
            self.last_tx = false
            self.last_error = "1 秒内未收到 CAN 总线 ACK"
            log.warn("factory_can", "ACK_TIMEOUT", p.can_id, string.format("0x%X", id))
            sys.publish("PERIPH_CAN_TX", self.id, false)
        end, 1000)
    end
    log.info("factory_can", "TX", p.can_id, string.format("0x%X", id), #data)
    return true, "已提交，等待 CAN 总线 ACK"
end

local function status(self)
    return {
        enabled=self.enabled,
        info=string.format("CAN%d %s | %d bit/s | TX:%d ACK:%d RX:%d%s",
            self.params.can_id, self.enabled and "已开启" or "未开启", self.params.bitrate or 500000, self.tx_count, self.tx_ok, self.rx_count,
            self.last_error and (" | " .. self.last_error) or ""),
        stats={tx=self.tx_count,tx_ok=self.tx_ok,rx=self.rx_count},
        bus_state=self.bus_state,
    }
end

function M.init(params)
    if type(params) ~= "table" or not params.id or params.can_id == nil then return false, "缺少 CAN 配置" end
    if instances[params.id] then return false, "外设 ID 重复" end
    local h = {id=params.id,name=params.name,params=params,enabled=false,
        tx_count=0,tx_ok=0,rx_count=0,rx_ring={}}
    h.start, h.stop, h.send, h.status = start, stop, send, status
    h.recv = function(self)
        local frames = self.rx_ring
        self.rx_ring = {}
        return frames
    end
    instances[params.id] = h
    return h
end

function M.get(id) return instances[id] end
return M
