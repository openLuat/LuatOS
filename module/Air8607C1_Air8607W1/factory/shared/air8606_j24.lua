-- Air8606 U2/J24. GPIO40 controls U6; RST1 is only a test point.
local M = {}
local registered, running, spi_open, busy = false, false, false, false
local dhcp_started = false
local detail, factory_mac = "已关闭", nil
local generation = 0
local CHIP_ID = "\x00\x1C\x51\x91"
local NCR, NSR, PAR, GPR, VID, RSCCR = 0x00, 0x01, 0x10, 0x1F, 0x28, 0x51

local function hex(bytes)
    if not bytes then return "--" end
    return (bytes:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

local function close_spi(p)
    if spi_open then spi.close(p.spi_id); spi_open = false end
end

local function open_spi(p, mode)
    local edge = mode == 3 and 1 or 0
    spi_open = spi.setup(p.spi_id, nil, edge, edge, 8, p.speed) == 0
    return spi_open
end

local function power_off(p)
    close_spi(p)
    -- spi.close on Air1602 restores LCD alternate functions. Release the pads
    -- before cutting U6 so a high output cannot keep the unpowered U2 alive.
    for _, pin in ipairs({p.cs_pin, p.sck_pin, p.mosi_pin, p.miso_pin, p.irq_pin}) do
        assert(gpio.setup(pin, nil, 0), "GPIO" .. pin .. " 释放失败")
    end
    assert(gpio.setup(p.pwr_pin, 0), "J24 电源控制失败")
end

local function read_register(bus, addr)
    if spi.send(bus, string.char(addr)) == 1 then return spi.recv(bus, 1) end
end

local function read_regs(p, first, count)
    local bytes = {}
    for addr = first, first + count - 1 do
        gpio.set(p.cs_pin, 0)
        local ok, rx = pcall(read_register, p.spi_id, addr)
        gpio.set(p.cs_pin, 1)
        if not ok or type(rx) ~= "string" or #rx ~= 1 then return nil end
        bytes[#bytes + 1] = rx
    end
    return table.concat(bytes)
end

local function write_reg(p, addr, value)
    gpio.set(p.cs_pin, 0)
    local ok, sent = pcall(spi.send, p.spi_id, string.char(addr | 0x80, value))
    gpio.set(p.cs_pin, 1)
    return ok and sent == 2
end

local function read_byte(p, addr)
    local bytes = read_regs(p, addr, 1)
    return bytes and bytes:byte()
end

local function reg_hex(value)
    return value and string.format("%02X", value) or "--"
end

local function wake_clock(p)
    read_byte(p, RSCCR) -- Selecting 0x51 resumes the CH390H clock. Its return value is undefined.
    sys.wait(5)
end

local function probe(p, attempt)
    local id = read_regs(p, VID, 4)
    local mac = read_regs(p, PAR, 6)
    sys.wait(10)
    local id2 = read_regs(p, VID, 4)
    local mac2 = read_regs(p, PAR, 6)
    log.info("air8606_j24", "PROBE", attempt, "SPI5", p.speed, "ID", hex(id), hex(id2),
        "MAC", hex(mac), hex(mac2))
    if id ~= CHIP_ID or id2 ~= id then
        return false, "芯片 ID 异常 " .. hex(id) .. "/" .. hex(id2)
    end
    if not mac or mac ~= mac2 or mac == string.rep("\0", 6) or mac:byte(1) % 2 ~= 0 then
        return false, "出厂 MAC 异常 " .. hex(mac) .. "/" .. hex(mac2), true
    end
    factory_mac = hex(mac)
    return true
end

-- The native V1032 driver checks PAR before enabling the PHY. If PAR is
-- invalid, wake the controller on this same supply and leave PAR untouched.
local function recover_mac(p)
    wake_clock(p)
    local id = read_regs(p, VID, 4)
    if id ~= CHIP_ID then return false, "唤醒时芯片 ID 失去响应 " .. hex(id) end
    if not write_reg(p, NCR, 1) then return false, "软复位写入失败" end
    local ncr
    for _ = 1, 5 do
        sys.wait(2)
        ncr = read_byte(p, NCR)
        if ncr and (ncr & 1) == 0 then break end
    end
    if not ncr or (ncr & 1) ~= 0 then return false, "软复位未完成 NCR=" .. reg_hex(ncr) end
    local gpr = read_byte(p, GPR)
    if not gpr or gpr == 0xFF or not write_reg(p, GPR, gpr & 0xFE) then
        return false, "PHY 电源寄存器访问失败"
    end
    sys.wait(10)
    local actual = read_byte(p, GPR)
    log.info("air8606_j24", "PHY_WAKE", "NCR", reg_hex(ncr), "GPR", reg_hex(gpr), "->", reg_hex(actual))
    if not actual or (actual & 1) ~= 0 then return false, "PHY 上电未获确认" end

    local why
    for i, delay in ipairs({0, 1000, 4000}) do
        if delay > 0 then sys.wait(delay) end
        local ok, reason, identified = probe(p, "PHY" .. i)
        if ok then return true end
        if not identified then return false, reason end
        why = reason
    end
    local nsr = read_byte(p, NSR)
    local link = "未知"
    if nsr and nsr ~= 0xFF then link = (nsr & 0x40) ~= 0 and "已连接" or "未连接" end
    log.warn("air8606_j24", "PHY_STATUS", "NSR", reg_hex(nsr), "LINK", link, why)
    return false, "PHY 链路" .. link .. "，出厂 MAC 仍异常"
end

local function gpio_ids(p)
    local bus = spi.createSoft(p.cs_pin, p.mosi_pin, p.miso_pin, p.sck_pin, 0, 0, 8, spi.MSB, 1, 0)
    local function read_id(pull)
        assert(gpio.setup(p.miso_pin, nil, pull), "MISO 输入配置失败")
        local bytes = {}
        for addr = VID, VID + 3 do
            -- One half-duplex transfer keeps CS low for both address and data.
            local value = spi.transfer(bus, string.char(addr), 1, 1)
            if type(value) ~= "string" or #value ~= 1 then return nil end
            bytes[#bytes + 1] = value
        end
        return table.concat(bytes)
    end
    return read_id(gpio.PULLUP), read_id(gpio.PULLDOWN)
end

local function compare_spi(p)
    close_spi(p)
    local read_ok, up, down = pcall(gpio_ids, p)
    if not read_ok then log.warn("air8606_j24", "GPIO_READ_FAIL", up); up = nil end
    log.info("air8606_j24", "GPIO_ID", "UP", hex(up), "DOWN", hex(down))
    -- CS stays inactive while restoring the pads. HW SPI5 only changes the mux.
    assert(gpio.setup(p.cs_pin, 1, gpio.PULLUP), "J24 片选恢复失败")
    for _, pin in ipairs({p.sck_pin, p.mosi_pin, p.miso_pin}) do
        assert(gpio.setup(pin, nil, 0), "SPI5 引脚恢复失败")
    end
    if not open_spi(p, 0) then return false, "SPI5 恢复失败" end
    local ok, why, identified = probe(p, "HW0")
    if ok or identified then return ok, why, identified end
    if up == CHIP_ID and down == CHIP_ID then
        -- CH390H also supports mode 3. The native driver uses this same bus.
        close_spi(p)
        if not open_spi(p, 3) then return false, "SPI5 模式 3 打开失败" end
        ok, why, identified = probe(p, "HW3")
        if ok or identified then return ok, why, identified end
        return false, "GPIO 读 ID 正常，硬件 SPI5 读 ID 失败"
    end
    if up == string.rep("\255", 4) and down == string.rep("\0", 4) then
        return false, "芯片 ID 异常，MISO 读数随上下拉变化"
    end
    return false, why
end

local function detect(p)
    if spi_open then
        -- Late boot probes and the settings page both reuse U6's existing power.
        wake_clock(p)
        local ok, why, identified = probe(p, "RETEST")
        if ok or identified then return ok, why, identified end
    else
        for attempt = 1, 2 do
            power_off(p)
            sys.wait(100)
            assert(gpio.setup(p.pwr_pin, 1, gpio.PULLUP), "J24 电源开启失败")
            sys.wait(2)
            assert(gpio.setup(p.cs_pin, 1, gpio.PULLUP), "J24 片选初始化失败")
            sys.wait(50) -- CH390H requires at least 25 ms after power-on.
            if not open_spi(p, 0) then return false, "SPI5 打开失败" end
            wake_clock(p)
            local ok, why, identified = probe(p, attempt)
            if ok or identified then return ok, why, identified end
        end
    end
    return compare_spi(p)
end

local function start_dhcp()
    dhcp_started = netdrv.dhcp(socket.LWIP_ETH, true)
    if not dhcp_started then return false, "DHCP 客户端启动失败" end
    return true
end

local function start(p)
    local adapter = socket.LWIP_ETH
    local ok, why, identified = detect(p)
    if not ok then
        if not identified then return false, why, spi_open end -- an open bus can be retried on this supply
        local recovered, reason = recover_mac(p)
        if not recovered then
            log.warn("air8606_j24", "RECOVERY_FAIL", why, reason)
            return false, "ID 正常、首次 MAC 异常 | " .. reason
        end
    end
    -- Only the native driver may access SPI5 from this point until CTRL_UPDOWN=0.
    if registered then
        if not netdrv.ctrl(adapter, netdrv.CTRL_UPDOWN, 1) then return false, "网卡唤醒失败" end
    else
        if not netdrv.setup(adapter, netdrv.CH390, {spi=p.spi_id, cs=p.cs_pin, irq=p.irq_pin}) then
            return false, "CH390H 驱动注册失败"
        end
        registered = true
    end
    running = true
    return start_dhcp()
end

local function stop(p)
    if running then
        if not netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_UPDOWN, 0) then
            return false, "网卡停止失败"
        end
        running, dhcp_started = false, false
    end
    power_off(p)
    return true
end

-- Called in a sys task on boot and on a change of the network switch.
function M.set_enabled(p, enabled, restore_off_on_error)
    if busy then return false, "J24 正在切换" end
    if enabled and running then
        local ok, why = start_dhcp()
        detail = ok and "CH390H 已识别" or why
        return ok, why
    end
    busy = true
    generation = generation + 1
    if enabled then factory_mac = nil end
    detail = enabled and "正在读取芯片 ID 和出厂 MAC" or "正在关闭"
    local called, ok, why, retry_id = pcall(enabled and start or stop, p)
    if not called then why, ok = tostring(ok), false end
    if not ok and enabled and restore_off_on_error then
        local stopped, off, err = pcall(stop, p)
        if not stopped or not off then log.warn("air8606_j24", "关闭失败", err or off) end
    end
    if ok and not enabled then factory_mac = nil end
    detail = ok and (enabled and "CH390H 已识别" or "已关闭") or why
    busy = false
    log.info("air8606_j24", ok and "STATE" or "FAIL", detail)
    if retry_id and not restore_off_on_error then return false, why, true end
    return ok, why
end

function M.status()
    local link, ip
    local state = detail
    if running and not busy and factory_mac then
        local adapter = socket.LWIP_ETH
        if netdrv.mac(adapter) == factory_mac then
            link = netdrv.link(adapter)
            if link then ip = netdrv.ipv4(adapter) end
            if ip == "" or ip == "0.0.0.0" then ip = nil end
        elseif detail == "CH390H 已识别" then
            state = "已读出厂 MAC，等待驱动确认"
        end
    end
    return state, factory_mac, link, ip, generation
end

sys.subscribe("IP_LOSE", function(adapter)
    if adapter == socket.LWIP_ETH then generation = generation + 1 end
end)

function M.is_running()
    return running and dhcp_started
end

function M.test_http(wait_for_ip)
    local function failed(reason)
        log.warn("air8606_j24", "HTTP_FAIL", "J24", reason)
        return false, reason
    end
    local seq = generation
    local state, _, link, ip = M.status()
    if wait_for_ip then
        for attempt = 1, 40 do
            if ip then break end
            sys.wait(250)
            if seq ~= generation then return failed("测试期间 J24 链路已变化") end
            state, _, link, ip = M.status()
        end
    end
    if link == nil then return failed(state) end
    if not link then return failed("J24 链路未就绪") end
    if not ip then return failed("J24 正在等待 DHCP 地址") end
    local called, code, _, body = pcall(function()
        return http.request("GET", "https://httpbin.luatos.com/bytes/2048", nil, nil,
            {adapter=socket.LWIP_ETH, timeout=10000}).wait()
    end)
    local _, _, up, current_ip = M.status()
    if seq ~= generation or not up or current_ip ~= ip then return failed("测试期间 J24 链路已变化") end
    local bytes = type(body) == "string" and #body or 0
    local passed = called and code == 200 and bytes == 2048
    local result = string.format("HTTP %s / %d B", called and tostring(code) or "请求失败", bytes)
    log.info("air8606_j24", passed and "HTTP_PASS" or "HTTP_FAIL", "J24", ip, result)
    return passed, result
end

return M
