--[[
@module  mbmaster
@summary Modbus 主站：三传输层（内置虚拟从站 / RS485 RTU / Modbus TCP）+ 轮询调度 + 统计
@version 1.0.0
@date    2026.10.25

传输方式（conf.comm.transport）：
  "sim"  内置虚拟从站（mbslave）。走完整 Modbus RTU 协议栈，并按波特率折算
         响应延迟，用于 PC 模拟器 / 未接总线时；
  "rtu"  真实 RS485 总线。使用 uart 的硬件 485 自动换向（rs485_gpio / rs485_level）；
  "tcp"  Modbus TCP。socket + libnet 长连接（Air8607 无网络，此方式主要用于 PC 验证）。

三者对外行为完全一致：组帧 → 发送 → 等待 → CRC/MBAP 校验 → 解析 → 超时重试。
]]
local conf = require "conf"
local modbus = require "modbus"
local mbdev = require "mbdev"
local mbslave = require "mbslave"

local M = {}

local TASK = "mbmaster"

local transport = conf.comm.transport
local paused = false

local stats = {
    ok = 0, fail = 0, timeout = 0, crc = 0, exception = 0,
    cycles = 0, total_ms = 0, last_ms = 0, avg_ms = 0,
}

local last_tx, last_rx = "", ""
local dev_fail = {}
local cycle = 0
local fault = nil
local manual_offline = {}

local function now_ms()
    if mcu and mcu.ticks then
        local ok, v = pcall(mcu.ticks)
        if ok and type(v) == "number" then return v end
    end
    return os.time() * 1000
end

-- ==================== 传输层：内置虚拟从站 ====================
local function sim_tx(slave, pdu, qty)
    local adu = modbus.rtu_wrap(slave, pdu)
    last_tx = adu
    -- 按波特率折算传输+响应时间，让时序更接近真实总线
    local n = #adu + 8
    local delay = math.ceil(n * 11 * 1000 / (conf.sim.baud_for_delay or 9600)) + 4
    if delay < 5 then delay = 5 end
    if delay > 80 then delay = 80 end
    sys.wait(delay)
    local resp, reason = mbslave.handle_rtu(adu)
    last_rx = resp or ""
    if not resp then return nil, (reason == "crc") and "crc" or ((reason == "offline") and "timeout" or "noresp") end
    local s, rpdu = modbus.rtu_unwrap(resp)
    if not rpdu then return nil, "crc" end
    if s ~= slave then return nil, "站号不符" end
    return modbus.parse_pdu(rpdu, qty)
end

-- ==================== 传输层：RS485 RTU ====================
local rtu_inited = false
local rx_buf = ""

local function rtu_init()
    if rtu_inited then return true end
    if not uart then return false, "固件无 uart 库" end
    local c = conf.comm.rtu
    local par = uart.None
    if c.parity == "even" and uart.Even then par = uart.Even end
    if c.parity == "odd" and uart.Odd then par = uart.Odd end
    local gpio485 = (c.rs485_de_pin > 0) and c.rs485_de_pin or nil
    local rx_level = (c.rs485_de_level == 1) and 0 or 1
    local ok
    if gpio485 then
        ok = uart.setup(c.uart_id, c.baud, c.databits, c.stopbits, par,
            uart.LSB, 1024, gpio485, rx_level, 2000)
    else
        ok = uart.setup(c.uart_id, c.baud, c.databits, c.stopbits, par)
    end
    if ok ~= 0 then return false, "uart.setup 失败(" .. tostring(ok) .. ")" end
    uart.on(c.uart_id, "receive", function(id, len)
        local s = uart.read(id, len)
        if s and #s > 0 then rx_buf = rx_buf .. s end
        sys.publish("MB_RTU_RX")
    end)
    rtu_inited = true
    log.info("mbmaster", string.format("RS485 就绪 uart%d %d %d%s%d", c.uart_id, c.baud, c.databits,
        (c.parity == "even") and "E" or (c.parity == "odd") and "O" or "N", c.stopbits))
    return true
end

local function rtu_tx(slave, pdu, qty)
    local ok, err = rtu_init()
    if not ok then return nil, err end
    local c = conf.comm.rtu
    local adu = modbus.rtu_wrap(slave, pdu)
    last_tx = adu
    rx_buf = ""
    uart.write(c.uart_id, adu)

    -- 等待发送完成（按波特率估算），再进入接收
    local tx_ms = math.ceil((#adu * 11 * 1000) / c.baud) + 6
    sys.wait(tx_ms)

    local left = conf.comm.timeout_ms
    while left > 0 do
        local need = modbus.rtu_need_len(rx_buf)
        if need and #rx_buf >= need then break end
        local step = 100
        if left < step then step = left end
        sys.waitUntil("MB_RTU_RX", step)
        left = left - step
    end

    if #rx_buf < 4 then return nil, "timeout" end
    last_rx = rx_buf
    local s, rpdu = modbus.rtu_unwrap(rx_buf)
    if not rpdu then return nil, "crc" end
    if s ~= slave then return nil, "站号不符" end
    return modbus.parse_pdu(rpdu, qty)
end

-- ==================== 传输层：Modbus TCP ====================
local tcp_sock = nil
local tcp_rxb = nil
local tcp_txn = 0
local tcp_fail = 0
local TCP_GIVEUP = 3

local function tcp_adapter()
    if conf.comm.tcp.adapter then return conf.comm.tcp.adapter end
    if socket then
        -- PC 模拟器上真实可用的网卡是宿主协议栈（ETH0=17）；实机按内置以太/蜂窝顺序回退
        if socket.ETH0 ~= nil then return socket.ETH0 end
        if socket.LWIP_ETH ~= nil then return socket.LWIP_ETH end
        if socket.LWIP_GP ~= nil then return socket.LWIP_GP end
    end
    return 0
end

local function tcp_close()
    if not tcp_sock then return end
    pcall(function()
        if libnet and libnet.close then libnet.close(TASK, 2000, tcp_sock) end
        if socket.release then socket.release(tcp_sock) end
    end)
    tcp_sock = nil
end

local function tcp_connect()
    if tcp_sock then return true end
    local c = conf.comm.tcp
    local sock = socket.create(tcp_adapter(), TASK)
    if not sock then return false, "创建 socket 失败" end
    if not socket.config(sock, nil, nil, nil, 60, 10, 3) then
        socket.release(sock)
        return false, "socket 配置失败"
    end
    if not libnet.connect(TASK, conf.comm.timeout_ms * 3, sock, c.ip, c.port) then
        socket.release(sock)
        return false, "连接 " .. c.ip .. ":" .. tostring(c.port) .. " 失败"
    end
    tcp_sock = sock
    return true
end

local function tcp_tx(slave, pdu, qty)
    if not socket or not libnet then return nil, "固件无 socket/libnet" end
    if tcp_fail >= TCP_GIVEUP then return nil, "TCP 不可用（已放弃重连）" end

    local ok, err = tcp_connect()
    if not ok then
        tcp_fail = tcp_fail + 1
        return nil, err
    end
    tcp_txn = (tcp_txn + 1) & 0xFFFF
    local req = modbus.tcp_wrap(tcp_txn, slave, pdu)
    last_tx = req
    if not libnet.tx(TASK, conf.comm.timeout_ms, tcp_sock, req) then
        tcp_close()
        tcp_fail = tcp_fail + 1
        return nil, "发送失败"
    end

    local data = ""
    tcp_rxb = tcp_rxb or zbuff.create(512)
    local rxb = tcp_rxb
    rxb:del()
    local left = conf.comm.timeout_ms
    while left > 0 do
        while true do
            local r = socket.rx(tcp_sock, rxb)
            if not r then tcp_close(); tcp_fail = tcp_fail + 1; return nil, "连接断开" end
            if rxb:used() > 0 then
                data = data .. rxb:query()
                rxb:del()
            else
                break
            end
        end
        local need = modbus.tcp_need_len(data)
        if need and #data >= need then break end
        local step = 100
        if left < step then step = left end
        if not libnet.wait(TASK, step, tcp_sock) then break end
        left = left - step
    end

    if #data < 8 then return nil, "timeout" end
    last_rx = data
    local rpdu, e = modbus.tcp_unwrap(data, tcp_txn, slave)
    if not rpdu then return nil, e or "帧错误" end
    tcp_fail = 0
    return modbus.parse_pdu(rpdu, qty)
end

-- ==================== 统一事务入口 ====================
local function transact(slave, pdu, qty)
    if transport == "sim" then return sim_tx(slave, pdu, qty) end
    if transport == "rtu" then return rtu_tx(slave, pdu, qty) end
    if transport == "tcp" then return tcp_tx(slave, pdu, qty) end
    return nil, "未知传输方式 " .. tostring(transport)
end

local function book_fail(err, res)
    stats.fail = stats.fail + 1
    if err == "timeout" then stats.timeout = stats.timeout + 1 end
    if err == "crc" then stats.crc = stats.crc + 1 end
    if res and res.err == "exception" then stats.exception = stats.exception + 1 end
end

-- ==================== 故障注入（仅 sim） ====================
local function sim_fault_inject()
    if transport ~= "sim" or not conf.sim.inject_fault then return end
    if fault then
        fault.left = fault.left - 1
        if fault.left <= 0 then
            mbslave.set_offline(fault.dev, false)
            fault = nil
        end
        return
    end
    if cycle % conf.sim.fault_every == 0 then
        local devs = mbdev.devices()
        local d = devs[math.random(#devs)]
        if not manual_offline[d.id] then
            fault = { dev = d.id, left = conf.sim.fault_rounds }
            mbslave.set_offline(d.id, true)
        end
    end
    if cycle % (conf.sim.fault_every + 17) == 0 then
        local devs = mbdev.devices()
        mbslave.inject_crc_error(devs[math.random(#devs)].id)
    end
end

-- ==================== 一轮轮询 ====================
local function poll_once()
    cycle = cycle + 1
    stats.cycles = cycle

    mbslave.tick(conf.comm.poll_interval_ms)
    sim_fault_inject()

    for _, dev in ipairs(mbdev.devices()) do
        local ok_any = false
        for gi, g in ipairs(dev.polls) do
            local pdu = modbus.read_pdu(g.fc, g.addr, g.count)
            local res, err
            for _ = 0, conf.comm.retry do
                res, err = transact(dev.id, pdu, g.count)
                if res then break end
                if err and err ~= "timeout" and err ~= "crc" then break end
            end

            if res and res.ok then
                stats.ok = stats.ok + 1
                for _, pt in ipairs(dev.points) do
                    if pt.fc == g.fc and pt.addr >= g.addr and pt.addr < g.addr + g.count then
                        local off = pt.addr - g.addr
                        if pt.dtype == "bool" then
                            local b = res.bits and res.bits[off + 1]
                            if b ~= nil then mbdev.update(pt.key, nil, b) end
                        else
                            local n = modbus.reg_count(pt.dtype)
                            if res.regs and (off + n) <= #res.regs then
                                local regs = {}
                                for i = 1, n do regs[i] = res.regs[off + i] end
                                mbdev.update(pt.key, regs)
                            end
                        end
                    end
                end
                ok_any = true
            else
                book_fail(err, res)
            end
            if gi < #dev.polls then sys.wait(conf.comm.inter_frame_ms) end
        end

        if ok_any then
            dev_fail[dev.id] = 0
            mbdev.set_online(dev.id, true)
        else
            dev_fail[dev.id] = (dev_fail[dev.id] or 0) + 1
            if dev_fail[dev.id] >= conf.comm.offline_after then
                mbdev.set_online(dev.id, false)
            end
        end
    end
end

-- ==================== 对外接口 ====================
function M.init()
    mbdev.init()
    mbslave.init()
    local ok, seed = pcall(os.time)
    math.randomseed((ok and seed or 0) % 1000000 + 7)
    math.random(); math.random()
end

function M.start()
    if sys.taskInitEx then
        sys.taskInitEx(function() M._loop() end, TASK)
    else
        sys.taskInit(function() M._loop() end)
    end
end

function M._loop()
    while true do
        if not paused then
            local t0 = now_ms()
            local ok, e = pcall(poll_once)
            if not ok then log.error("mbmaster", "轮询异常", tostring(e)) end
            stats.last_ms = now_ms() - t0
            stats.total_ms = stats.total_ms + stats.last_ms
            stats.avg_ms = math.floor(stats.total_ms / math.max(1, stats.cycles))
        end
        sys.wait(conf.comm.poll_interval_ms)
    end
end

function M.transport() return transport end

function M.set_transport(t)
    if t ~= "sim" and t ~= "rtu" and t ~= "tcp" then return false, "不支持的传输方式" end
    if t == transport then return true end
    if transport == "tcp" then tcp_close() end
    transport = t
    conf.comm.transport = t
    tcp_fail = 0
    dev_fail = {}
    fault = nil
    for _, dev in ipairs(mbdev.devices()) do
        if not manual_offline[dev.id] then mbslave.set_offline(dev.id, false) end
    end
    stats.ok, stats.fail, stats.timeout, stats.crc, stats.exception = 0, 0, 0, 0, 0
    stats.cycles, stats.total_ms, stats.last_ms, stats.avg_ms = 0, 0, 0, 0
    log.info("mbmaster", "传输方式切换为", t)
    return true
end

function M.transport_name()
    if transport == "sim" then return "内置从站" end
    if transport == "rtu" then return "RS485 RTU" end
    if transport == "tcp" then return "Modbus TCP" end
    return tostring(transport)
end

function M.transport_desc()
    if transport == "sim" then return "回路仿真" end
    if transport == "rtu" then
        local c = conf.comm.rtu
        return string.format("UART%d %d %d%s%d", c.uart_id, c.baud, c.databits,
            (c.parity == "even") and "E" or (c.parity == "odd") and "O" or "N", c.stopbits)
    end
    if transport == "tcp" then return string.format("%s:%d", conf.comm.tcp.ip, conf.comm.tcp.port) end
    return ""
end

function M.stats() return stats end
function M.reset_stats()
    stats.ok, stats.fail, stats.timeout, stats.crc, stats.exception = 0, 0, 0, 0, 0
    stats.cycles, stats.total_ms, stats.last_ms, stats.avg_ms = 0, 0, 0, 0
end

function M.cycle() return cycle end
function M.last_tx() return last_tx end
function M.last_rx() return last_rx end
function M.last_tx_hex() return modbus.hex(last_tx) end
function M.last_rx_hex() return modbus.hex(last_rx) end

function M.set_paused(b) paused = b and true or false end
function M.paused() return paused end

function M.set_device_offline(dev_id, b)
    manual_offline[dev_id] = b and true or false
    mbslave.set_offline(dev_id, b)
    if b then
        fault = nil
        mbdev.set_online(dev_id, false)
    end
    return b
end

function M.is_device_offline(dev_id) return manual_offline[dev_id] == true end

--[[写点位：把工程量换算成寄存器值后下发 0x06 / 0x10 / 0x05]]
function M.write_point(key, eng)
    local pt = mbdev.point(key)
    if not pt then return false, "点位不存在" end
    if not pt.rw then return false, "该点位只读" end
    local dev = mbdev.dev_of(key)
    local pdu, regs
    if pt.dtype == "bool" then
        pdu = modbus.write_single_pdu(0x05, pt.addr, (eng ~= 0) and 0xFF00 or 0x0000)
    else
        regs = modbus.encode(math.floor((tonumber(eng) or 0) / pt.scale + 0.5), pt.dtype)
        if #regs == 1 then
            pdu = modbus.write_single_pdu(0x06, pt.addr, regs[1])
        else
            pdu = modbus.write_multi_reg_pdu(pt.addr, regs)
        end
    end
    local res, err = transact(dev.id, pdu)
    if res and res.ok then
        stats.ok = stats.ok + 1
        -- 写成功后立即把本地值刷新成刚写入的值，UI 无需等下一轮轮询
        if pt.dtype == "bool" then
            mbdev.update(key, nil, (eng ~= 0))
        else
            mbdev.update(key, regs)
        end
        return true, "写入成功"
    end
    book_fail(err, res)
    return false, modbus.err_text(res) .. (err and (" / " .. tostring(err)) or "")
end

--[[寄存器工具：按功能码读]]
function M.read_raw(slave, fc, addr, count)
    local pdu = modbus.read_pdu(fc, addr, count)
    local res, err = transact(slave, pdu, count)
    if res then return res, err end
    return nil, err
end

--[[寄存器工具：按功能码写]]
function M.write_raw(slave, fc, addr, value, extra)
    local pdu
    if fc == 0x05 then
        pdu = modbus.write_single_pdu(0x05, addr, (value ~= 0) and 0xFF00 or 0x0000)
    elseif fc == 0x06 then
        pdu = modbus.write_single_pdu(0x06, addr, value)
    elseif fc == 0x10 then
        local vals = {}
        for i = 1, (extra or 1) do vals[i] = (value >> ((i - 1) * 16)) & 0xFFFF end
        pdu = modbus.write_multi_reg_pdu(addr, vals)
    else
        return nil, "不支持的写功能码"
    end
    local res, err = transact(slave, pdu)
    if res then return res, err end
    return nil, err
end

return M
