--[[
rfa: Radio Factory Agent (RF 校准 Lua 端主控)
================================================
扩展 STEST/SWIFIMAC/SWIFISCAN/SWIFIVER/YHM27XX/GSENSOREXEC，命令解析及响应使用 atc。
CGNSPWR/CGNSTST/CGNSCMD 支持 Air8000、Air780EGH/EGP/EGG 的内置 GNSS 产测。
产线按单端口顺序收发；AirLink 查询使用现有就绪状态/缓存，扫描最多 32 条。
参考 ec7xx-at 的 atec_am_airlink.c、atec_am_dev.c、atec_am_airlink_cnf_ind.c 和 am_gps_hdlr.c。
]]

local M = { _VERSION = "1.0.3" }

M._CFG_FILE_PATH = "/factory.cfg"
local rf_mode_ = true -- 默认处于 rfa 校准模式, 只有显式配置为false才表示退出rfa模式
local out_buff = zbuff.create(8000)
-- 支持多端口同时响应 (如 VUART_0 + UART1), 每个端口独立接收缓冲
local uart_ids = {}     -- 已启动的 uart id 列表
local in_buffs = {}     -- uart id -> zbuff
local atc_on_ = false   -- atc 回调只注册一次
local atc_src_id = nil  -- 最近一次向 atc 投喂数据的端口, atc 应答回写到该端口
local commands_created, commands_bound = false, 0
local active_cmd, response_owner
local command_echo -- 需补齐行尾的原始命令回显，不含行尾
local power_echo -- CGNSPWR 设置命令的回显随最终结果一次写出
local hardware_requests = {} -- 超时/关闭后仍保留，直到消费旧硬件完成事件
local COMMAND_TIMEOUT = 5000
-- luat_atc_define.h: AT_RESULT_NULL。结束自定义指令但不追加结果码。
local AT_RESULT_NONE = 0xFFFF
local GNSS_UART = 2
local gnss_models = {Air8000 = true, Air8000A = true, Air8000G = true, Air8000D = true, Air8000U = true, Air8000N = true, Air780EGH = true, Air780EGP = true, Air780EGG = true}
local gnss_session, gnss_owner
local gnss_tst = 0
M.rfCaliDone, M.rfNSTDone = 0, 0

-- RFA 共用 AT 通道 0；两个串口须顺序使用，收到最终响应后再发下一条。
local function command_finish(ctx, result, text)
    if active_cmd ~= ctx then return end
    active_cmd = nil
    if ctx.timer then sys.timerStop(ctx.timer) end
    -- 带参数唤醒 wait/waitUntil，清理协程自己的定时器和事件订阅。
    if ctx.task and coroutine.status(ctx.task) == "suspended" then
        sys.coresume(ctx.task, "RFA_ATC_CANCEL")
    end
    if ctx.cleanup then
        local cleanup = ctx.cleanup
        ctx.cleanup = nil
        cleanup()
    end
    response_owner = ctx
    if not ctx.port or in_buffs[ctx.src] ~= ctx.port then
        atc.response(0, AT_RESULT_NONE)
        return
    end
    if text then atc.response(0, text) end
    atc.response(0, result)
end

local function command_cme(ctx, code)
    -- RES_INPUT_ERROR 对应 765，内置 CME 格式也不同，故显式输出 AT 固件正文。
    command_finish(ctx, AT_RESULT_NONE, "+CME ERROR: " .. code .. (ctx.cme_suffix or ""))
end

local function command_timeout(ctx)
    if ctx.empty_scan then
        -- AT 固件空扫描不回 OK，由命令的总超时返回 ERROR。
        command_finish(ctx, atc.RES_ERROR)
    else
        command_cme(ctx, 100)
    end
end

local function command_async(ctx, work)
    ctx.timer = sys.timerStart(command_timeout, COMMAND_TIMEOUT, ctx)
    if not ctx.timer then
        command_finish(ctx, atc.RES_ERROR)
        return
    end
    ctx.task = sys.taskInit(function()
        local ok, err = pcall(work, ctx)
        if not ok then
            log.error("rfa", "AT command failed", err)
            command_finish(ctx, atc.RES_ERROR)
        end
    end)
end

-- WLAN/YHM 的事件没有请求 ID。同类旧请求未完成时不再提交新请求，
-- 避免其迟到事件被下一条命令误用；AT 通道本身仍可处理其他指令。
local function wait_hardware(ctx, event, start)
    if hardware_requests[event] then
        command_finish(ctx, atc.RES_ERROR)
        return false
    end
    local callback
    callback = function(...)
        sys.unsubscribe(event, callback)
        hardware_requests[event] = nil
        if active_cmd == ctx then sys.publish("RFA_ATC_DONE", ctx, ...) end
    end
    hardware_requests[event] = callback
    sys.subscribe(event, callback)
    local ok, result = pcall(start)
    if not ok or result == false then
        sys.unsubscribe(event, callback)
        hardware_requests[event] = nil
        if not ok then log.error("rfa", "hardware request failed", result) end
        command_finish(ctx, atc.RES_ERROR)
        return false
    end
    while active_cmd == ctx do
        local _, owner, data = sys.waitUntil("RFA_ATC_DONE")
        if active_cmd == ctx and owner == ctx then return true, data end
    end
    return false
end

local function wait_airlink(ctx)
    while active_cmd == ctx do
        if airlink.ready() then return true end
        sys.wait(50)
    end
    return false
end

local function mac_hex(mac, upper)
    if type(mac) ~= "string" or #mac ~= 6 then return nil end
    return string.format(upper and "%02X%02X%02X%02X%02X%02X" or "%02x%02x%02x%02x%02x%02x", mac:byte(1, 6))
end

local function stest_command(ctx, kind, ...)
    if kind ~= atc.TYPE_WRITE or select("#", ...) ~= 1 then
        return command_finish(ctx, atc.RES_ERROR)
    end
    local value = ...
    local digits = value:match("^-?(%d+)$")
    local number = digits and tonumber(value)
    if not number or #digits > 10 or number < -2147483648 or number > 2147483647 then
        return command_cme(ctx, 50)
    end
    if not airlink or not airlink.power or not airlink.ready then
        return command_finish(ctx, atc.RES_ERROR)
    end
    command_async(ctx, function()
        -- Air8000 的 AirLink 由底层自动初始化；不重复 init/start。
        airlink.power(true)
        if wait_airlink(ctx) then command_finish(ctx, atc.RES_OK) end
    end)
end

local function swifimac_command(ctx, kind, ...)
    local count = select("#", ...)
    if kind == atc.TYPE_READ and count == 0 then
        if not airlink or not airlink.ready or not wlan or not wlan.getMac then
            return command_finish(ctx, atc.RES_ERROR)
        end
        command_async(ctx, function()
            while wait_airlink(ctx) do
                local sta = mac_hex(wlan.getMac(0, false), true)
                local ap = mac_hex(wlan.getMac(1, false), true)
                if sta and ap then
                    return command_finish(ctx, atc.RES_OK,
                        string.format('+SWIFIMAC: "STA","%s"\r\n+SWIFIMAC: "AP","%s"', sta, ap))
                end
                sys.wait(50)
            end
        end)
    elseif kind == atc.TYPE_WRITE and count == 2 then
        local mode, mac = ...
        -- 原 AT 固件只比较前三字节，不额外限制 STA 后缀或 MAC 地址类型。
        if #mode > 7 or mode:sub(1, 3):lower() ~= "sta" or #mac ~= 12 or not mac:match("^%x+$") then
            return command_cme(ctx, 50)
        end
        if not wlan or not wlan.setMac then return command_finish(ctx, atc.RES_ERROR) end
        local raw = mac:gsub("%x%x", function(byte) return string.char(tonumber(byte, 16)) end)
        command_finish(ctx, wlan.setMac(0, raw) and atc.RES_OK or atc.RES_ERROR)
    else
        command_finish(ctx, atc.RES_ERROR)
    end
end

local function swifiscan_command(ctx, kind, ...)
    if kind ~= atc.TYPE_EXEC or select("#", ...) ~= 0 then
        return command_finish(ctx, atc.RES_ERROR)
    end
    if not wlan or not wlan.init or not wlan.scan or not wlan.scanResult then
        return command_finish(ctx, atc.RES_ERROR)
    end
    command_async(ctx, function()
        local received = wait_hardware(ctx, "WLAN_SCAN_DONE", function()
            if not wlan.init() then return false end
            return wlan.scan()
        end)
        if not received then return end
        local results = wlan.scanResult(32)
        if #results == 0 then
            ctx.empty_scan = true
            -- 保留从本次命令开始计算的总超时，不能永久阻塞 AT 通道。
            sys.wait(COMMAND_TIMEOUT)
            return
        end
        local lines = {}
        for _, item in ipairs(results) do
            lines[#lines + 1] = string.format('+SWIFISCAN: "%s",%d,%d', mac_hex(item.bssid, false), item.rssi, item.channel)
        end
        command_finish(ctx, atc.RES_OK, table.concat(lines, "\r\n"))
    end)
end

local function swifiver_command(ctx, kind, ...)
    if kind ~= atc.TYPE_READ or select("#", ...) ~= 0 then
        return command_finish(ctx, atc.RES_ERROR)
    end
    if not airlink or not airlink.ready or not airlink.sver then
        return command_finish(ctx, atc.RES_ERROR)
    end
    command_async(ctx, function()
        if not wait_airlink(ctx) then return end
        local version = airlink.sver()
        -- 参考固件以 32 位 long 的 %ld 输出版本。
        if version >= 0x80000000 then version = version - 0x100000000 end
        command_finish(ctx, atc.RES_OK, string.format("+SWIFIVER: %d", version))
    end)
end

local function yhm27xx_command(ctx, kind, ...)
    if kind ~= atc.TYPE_EXEC or select("#", ...) ~= 0 then
        return command_finish(ctx, atc.RES_ERROR)
    end
    if not hmeta or not hmeta.model then return command_finish(ctx, atc.RES_ERROR) end
    local model = hmeta.model()
    if model:sub(1, 7) ~= "Air8000" then
        return command_finish(ctx, atc.RES_OK, "+YHM27XX: NOT AIR8000")
    end
    if model:sub(8, 8) == "G" then
        if not pm or not pm.chgcmd then return command_finish(ctx, atc.RES_ERROR) end
        local ok, value = pm.chgcmd(22, 0x04, 0x08)
        return command_finish(ctx, atc.RES_OK, "+YHM27XX: " .. (ok and value == 0xA0 and "OK" or "ERROR"))
    end
    if not pm or not pm.chginfo then return command_finish(ctx, atc.RES_ERROR) end
    command_async(ctx, function()
        local received, data = wait_hardware(ctx, "YHM27XX_REG", function()
            return pm.chginfo(152, 0x04)
        end)
        if not received then return end
        local present = type(data) == "string" and data:byte(9) == 0xA0
        command_finish(ctx, atc.RES_OK, "+YHM27XX: " .. (present and "OK" or "ERROR"))
    end)
end

-- am_gps_hdlr.c: at_gsensorexec_hdlr，仅检测芯片 ID，不配置运动检测。
local function gsensorexec_command(ctx, kind)
    -- ATS 的 PAT_respone_cmeecode 在错误正文末尾额外追加一组 CRLF。
    ctx.cme_suffix = "\r\n"
    if kind == atc.TYPE_READ or kind == atc.TYPE_TEST then
        return command_finish(ctx, atc.RES_OK)
    end
    if kind ~= atc.TYPE_EXEC then
        -- 参考固件的设置形式不解析参数，统一返回 operation not allowed。
        return command_cme(ctx, 3)
    end
    if not i2c or not i2c.setup or not i2c.transfer or i2c.SLOW == nil then
        return command_finish(ctx, atc.RES_ERROR)
    end
    local model = hmeta and hmeta.model and hmeta.model()
    local bus, power_pin = 0, nil
    -- 与 exvib 的内置 DA221 接线一致，LuatOS 两类平台的 I2C 编号不同。
    if model == "Air780EGP" or model == "Air780EGG" then
        bus, power_pin = 1, 23
    elseif model == "Air8000" then
        power_pin = 24
    end
    if power_pin and (not gpio or not gpio.setup) then
        return command_finish(ctx, atc.RES_ERROR)
    end
    command_async(ctx, function()
        -- 此电源同时用于 GNSS 备电，检测完成或取消后均保持开启。
        if power_pin then gpio.setup(power_pin, 1, gpio.PULLUP) end
        i2c.setup(bus, i2c.SLOW)
        sys.wait(50)
        if active_cmd ~= ctx then return end
        -- 使用组合读，对应参考固件 iot_i2c_read 内的 I2C_BlockRead。
        local ok, data = i2c.transfer(bus, 0x27, 0x01, nil, 1)
        sys.wait(20)
        if active_cmd ~= ctx then return end
        if ok and type(data) == "string" and data:byte(1) == 0x13 then
            command_finish(ctx, atc.RES_OK)
        else
            command_cme(ctx, 100)
        end
    end)
end

-- pm.GPS 按型号控制主电源；Air780EGH/EGP/EGG 开启时也会拉高 GPIO23。
-- 关闭只关主电源，保留 GNSS 备电，不影响热启动或 Air8000 的 GSensor 电源。
local function gnss_shutdown()
    local session = gnss_session
    gnss_session = nil -- 先使旧接收回调失效，再释放 UART 和电源。
    if not session then return true end
    local success = true
    local ok, result = pcall(uart.on, GNSS_UART, "receive", nil)
    if not ok then
        log.error("rfa", "GNSS receive close failed", result)
        success = false
    end
    ok, result = pcall(uart.close, GNSS_UART)
    if not ok then
        log.error("rfa", "GNSS UART close failed", result)
        success = false
    end
    if session.power_on then
        ok, result = pcall(pm.power, pm.GPS, false)
        if not ok or not result then
            log.error("rfa", "GNSS power off failed", result)
            success = false
        end
    end
    return success
end

local function gnss_receive(session, forward)
    while gnss_session == session do
        local data = uart.read(GNSS_UART, 1024)
        if not data or #data == 0 then return end
        if forward and gnss_tst == 1 and gnss_owner
            and in_buffs[gnss_owner.src] == gnss_owner.port then
            -- 原始产测数据不经过 atc.urc，避免额外添加 CRLF。
            uart.write(gnss_owner.src, data)
        end
    end
end

-- ATS 的无符号十进制参数最多十位；允许前导零，空值及符号不合法。
local function gnss_uint(value, maximum)
    if #value == 0 or #value > 10 or not value:match("^%d+$") then return nil end
    local number = tonumber(value)
    if number <= maximum then return number end
end

local function gnss_supported()
    return hmeta and hmeta.model and gnss_models[hmeta.model()]
end

local function cgnspwr_command(ctx, kind, ...)
    ctx.cme_suffix = "\r\n"
    local count = select("#", ...)
    if kind == atc.TYPE_READ and count == 0 then
        return command_finish(ctx, atc.RES_OK, "+CGNSPWR: " .. (gnss_session and 1 or 0))
    elseif kind == atc.TYPE_TEST and count == 0 then
        return command_finish(ctx, atc.RES_OK, "+CGNSPWR: (0-1)")
    elseif kind ~= atc.TYPE_WRITE or count ~= 1 then
        return command_cme(ctx, 3)
    end
    local power = gnss_uint(..., 1)
    if power == nil then return command_cme(ctx, 3) end
    if not gnss_supported() or not pm or pm.GPS == nil or not pm.power
        or not uart.setup or not uart.read or not uart.write or not uart.on or not uart.close then
        return command_finish(ctx, atc.RES_ERROR)
    end
    -- 与参考固件一致，每次有效设置（含重复设置）更新数据输出端口。
    gnss_owner = {src = ctx.src, port = ctx.port}
    if power == 0 then
        return command_finish(ctx, gnss_shutdown() and atc.RES_OK or atc.RES_ERROR)
    elseif gnss_session then
        return command_finish(ctx, atc.RES_OK)
    end
    command_async(ctx, function()
        local session = {}
        gnss_session = session
        ctx.cleanup = function()
            if gnss_session == session then gnss_shutdown() end
        end
        if uart.setup(GNSS_UART, 115200, 8, 1, uart.NONE) ~= 0 then
            return command_finish(ctx, atc.RES_ERROR)
        end
        uart.on(GNSS_UART, "receive", function()
            gnss_receive(session, true)
        end)
        session.power_on = true
        if not pm.power(pm.GPS, true) then
            return command_finish(ctx, atc.RES_ERROR)
        end
        sys.wait(200)
        if active_cmd ~= ctx then return end
        ctx.cleanup = nil -- 启动完成，资源由 CGNSPWR=0 或 RFA close 释放。
        command_finish(ctx, atc.RES_OK)
    end)
end

local function cgnstst_command(ctx, kind, ...)
    ctx.cme_suffix = "\r\n"
    local count = select("#", ...)
    if kind == atc.TYPE_READ and count == 0 then
        return command_finish(ctx, atc.RES_OK, "+CGNSTST: " .. gnss_tst)
    elseif kind == atc.TYPE_TEST and count == 0 then
        return command_finish(ctx, atc.RES_OK, "+CGNSTST: (0-1)")
    elseif kind ~= atc.TYPE_WRITE or count ~= 1 then
        return command_cme(ctx, 3)
    end
    local mode = gnss_uint(..., 1)
    if mode == nil then return command_cme(ctx, 3) end
    if mode ~= gnss_tst and gnss_session then
        -- 清掉尚未触发回调的旧数据，重开转发时不能补发关闭期间的缓存。
        gnss_receive(gnss_session, false)
    end
    gnss_tst = mode
    command_finish(ctx, atc.RES_OK)
end

local function cgnscmd_command(ctx, kind, ...)
    ctx.cme_suffix = "\r\n"
    if kind ~= atc.TYPE_WRITE or select("#", ...) ~= 2 then
        return command_cme(ctx, 3)
    end
    local mode, cmd = ...
    if gnss_uint(mode, 0) ~= 0 or #cmd < 3 or #cmd > 64 then
        return command_cme(ctx, 3)
    end
    if not gnss_supported() or not uart.write then return command_finish(ctx, atc.RES_ERROR) end
    if cmd:sub(1, 1) ~= "$" then cmd = "$" .. cmd end
    -- 固定内置 GNSS 文本协议：补 CRLF，不加校验和，不等待 ACK。
    -- 与参考无 ACK 分支一致，OK 表示已提交发送，不代表芯片执行成功。
    uart.write(GNSS_UART, cmd .. "\r\n")
    command_finish(ctx, atc.RES_OK)
end

local commands = {
    {"+STEST", stest_command},
    {"+SWIFIMAC", swifimac_command},
    {"+SWIFISCAN", swifiscan_command},
    {"+SWIFIVER", swifiver_command},
    {"+YHM27XX", yhm27xx_command},
    {"+GSENSOREXEC", gsensorexec_command},
    {"+CGNSPWR", cgnspwr_command},
    {"+CGNSTST", cgnstst_command},
    {"+CGNSCMD", cgnscmd_command},
}

local function register_commands()
    if not commands_created then
        if not atc.create(#commands) then
            log.error("rfa", "atc.create failed")
            return false
        end
        commands_created = true
    end
    for i = commands_bound + 1, #commands do
        local handler = commands[i][2]
        if not atc.bind(commands[i][1], function(kind, ...)
            local ctx = {src = atc_src_id, port = in_buffs[atc_src_id]}
            active_cmd = ctx
            if not ctx.port then return command_finish(ctx, AT_RESULT_NONE) end
            local ok, err = pcall(handler, ctx, kind, ...)
            if not ok then
                log.error("rfa", "AT command failed", err)
                command_finish(ctx, atc.RES_ERROR)
            end
        end) then
            log.error("rfa", "atc.bind failed", commands[i][1])
            return false
        end
        commands_bound = i
    end
    return true
end


--解析AT指令，执行不同的操作; id 为收到数据的 uart 端口, 应答回写到同一端口
local function builtin_dispatch(line, id)
    -- log.info("rfa", "builtin_dispatch", line, line:toHex())
    local in_buff = in_buffs[id]
    -- AT+ES8311: detect ES8311 codec via I2C
    if line == "AT+ES8311\r\n" then
        in_buff:del()
        local present = false
        local ES8311_ADDRESS = 0x18
        local ES8311_CHD1_REG = 0xFD
        local ES8311_CHD2_REG = 0xFE
        local ES8311_CHD1_VAL = 0x83
        local ES8311_CHD2_VAL = 0x11
        local function es8311_read_reg(reg)
            if i2c.send(0, ES8311_ADDRESS, reg) then
                local data = i2c.recv(0, ES8311_ADDRESS, 1)
                if data and #data == 1 then
                    return data:byte(1)
                end
            end
            return nil
        end
        gpio.setup(20, 1, gpio.PULLUP)  -- 开启es8311电源(Air780EHV)
        i2c.setup(0, i2c.SLOW)
        if i2c and i2c.SLOW then
            local chipId1 = es8311_read_reg(ES8311_CHD1_REG)
            local chipId2 = es8311_read_reg(ES8311_CHD2_REG)
            log.info("rfa", "ES8311 chipId1", chipId1, "chipId2", chipId2)
            if chipId1 == ES8311_CHD1_VAL and chipId2 == ES8311_CHD2_VAL then
                present = true
            end
        else
            log.warn("rfa", "AT+ES8311 not supported on this platform")
        end
        if present then
            uart.write(id, "\r\n+ES8311: OK\r\n\r\nOK\r\n")
        else
            uart.write(id, "\r\n+ES8311: ERROR\r\n\r\nOK\r\n")
        end
        return
    end

    -- AT+SETCFG: set config (placeholder until C backend ready)
    -- AT+SETCFG="rfa_mode","true"  // set rfa_mode to true
    -- AT+SETCFG="rfa_mode","false" // set rfa_mode to false
    -- 引号可省略: AT+SETCFG=rfa_mode,true / AT+SETCFG=rfa_mode,false (也兼容单边带引号)
    -- 先做前缀比较, 只有 SETCFG 命令才进 pattern match, 避免每条消息(尤其是 ECRFNST 长报文)都跑一遍匹配
    if line:sub(1, 9) == "AT+SETCFG" then
        -- AT+SETCFG?: get config (placeholder until C backend ready)
        if line == "AT+SETCFG?\r\n" then
            in_buff:del()
            return uart.write(id, string.format("\r\n+SETCFG: \"rfa_mode\",\"%s\"\r\n\r\nOK\r\n", M.getRFAOnStatus() and "true" or "false"))
        end
        local cfg, val = line:match('^AT%+SETCFG="?([^",]+)"?%s*,%s*"?([^",%s]+)"?%s*$')
        -- log.info("rfa", "builtin_dispatch", "AT+SETCFG", cfg, val)
        if cfg and val then
            in_buff:del()
            val = val:lower()
            if val == "true" or val == "false" then
                M.setRfOn(val == "true")
                return uart.write(id, string.format("\r\n+SETCFG: \"%s\",\"%s\"\r\n\r\nOK\r\n", cfg, val))
            else
                return uart.write(id, "\r\nERROR\r\n")
            end
        end
    end

    atc_src_id = id
    response_owner = nil
    local echo = line:match("^([^\r\n]+)[\r\n]+$")
    local name = echo and echo:match("^[Aa][Tt](%+[%w]+)")
    name = name and name:upper()
    command_echo = echo and (echo:sub(1, 12):upper() == "AT+SWIFIMAC="
        or name == "+GSENSOREXEC" or name == "+CGNSPWR"
        or name == "+CGNSTST" or name == "+CGNSCMD") and echo or nil
    -- 设置形式会等待 GNSS 启动；先暂存回显，避免与 200ms 后的 OK 分开发送。
    -- 查询/测试形式沿用原有输出时机，不自行解析设置参数。
    power_echo = name == "+CGNSPWR" and echo:match("=%s*[^%s?]")
        and {src = id, port = in_buff, text = ""} or nil
    atc.input(0, in_buff)
    in_buff:del()
end

--ATC 输出回调, 处理 ATC 模块的输出数据; 应答回写到发起该命令的端口
local function atc_out(id, event, param)
    local tx_id = atc_src_id or uart_ids[1]
    if response_owner then
        tx_id = in_buffs[response_owner.src] == response_owner.port and response_owner.src or nil
    end
    local out_resp = out_buff:toStr(0, out_buff:used())
    if tx_id then
        local changed = false
        if command_echo and out_resp:sub(1, #command_echo) == command_echo then
            -- atc 去掉了命令回显的行尾；补回显 CRLF，结果仍由 atc.response 输出。
            -- 兼容回显和结果合并输出；ATE0 时没有匹配的回显，不追加换行。
            local echo = command_echo .. "\r\n"
            out_resp = out_resp:sub(#command_echo + 1)
            command_echo = nil
            if power_echo and power_echo.src == tx_id and power_echo.port == in_buffs[tx_id] then
                power_echo.text = echo
            else
                out_resp = echo .. out_resp
            end
            changed = true
        end
        if power_echo and not active_cmd
            and power_echo.src == tx_id and power_echo.port == in_buffs[tx_id] then
            -- 回显通知可能先于 Lua 命令回调，须看到最终结果才能释放回显。
            -- 等待期间的 URC 照常输出，兼容数字结果及 native/ATS 两种 CME 格式。
            local result = out_resp:match("\r\n([^\r\n]+)\r\n[\r\n]*$")
            if result and (result == "OK" or result == "ERROR" or result == "0" or result == "4"
                or result:match("^%+?CME ERROR:%s*%d+$")) then
                out_resp = power_echo.text .. out_resp
                power_echo = nil
                changed = true
            end
        end
        if #out_resp > 0 then
            if changed then uart.write(tx_id, out_resp) else uart.tx(tx_id, out_buff) end
        end
    end
    if out_resp and out_resp:match("%+ECNPICFG:") then
        -- 解析 AT+ECNPICFG? 响应, 更新 rfCaliDone 和 rfNSTDone 状态
        local rfCaliDone, rfNSTDone = out_resp:match('"rfCaliDone":(%d+),"rfNSTDone":(%d+)')
        M.rfCaliDone = tonumber(rfCaliDone)
        M.rfNSTDone = tonumber(rfNSTDone)
        -- log.info("rfa", "ATC_OUT", id, event, M.rfCaliDone, M.rfNSTDone, out_resp)
        if M.rfCaliDone ~= nil and M.rfNSTDone ~= nil then
            sys.publish("RFA_ECNPI_CFG_READY")
        end
    end
end

--启动指定端口的 RFA AT 服务; 可多次调用, 让多个端口同时响应
function M.start(id, baud)
    id = id or uart.VUART_0
    baud = baud or 115200
    if in_buffs[id] then
        log.warn("rfa", "start: 端口已启动, 忽略重复调用", id)
        return
    end
    if not register_commands() then return false end
    uart.setup(id, baud, 8, 1)
    in_buffs[id] = zbuff.create(8000)
    table.insert(uart_ids, id)
    uart.on(id, "receive", function(rxid, len)
        local buff = in_buffs[rxid]
        if not buff then return end
        uart.rx(rxid, buff)
        builtin_dispatch(buff:toStr(0, buff:used()), rxid)  -- 处理内置 AT 指令
    end)
    if not atc_on_ then
        atc.on(0, atc_out, out_buff)
        atc_on_ = true
    end
end

--关闭 RFA AT 服务; 传 id 只关闭指定端口, 不传则关闭全部端口
function M.close(id)
    if not id or atc_src_id == id then command_echo = nil end
    if power_echo and (not id or power_echo.src == id) then power_echo = nil end
    if active_cmd and (not id or active_cmd.src == id) then
        command_finish(active_cmd, AT_RESULT_NONE)
    end
    if not id or (gnss_owner and gnss_owner.src == id)
        or (#uart_ids == 1 and uart_ids[1] == id) then
        gnss_shutdown()
        gnss_owner, gnss_tst = nil, 0
    end
    if id then
        if not in_buffs[id] then return end
        uart.on(id, "receive", nil)
        in_buffs[id] = nil
        for i, v in ipairs(uart_ids) do
            if v == id then
                table.remove(uart_ids, i)
                break
            end
        end
        if atc_src_id == id then atc_src_id = nil end
    else
        for _, v in ipairs(uart_ids) do
            uart.on(v, "receive", nil)
        end
        uart_ids = {}
        in_buffs = {}
        atc_src_id = nil
    end
    if #uart_ids == 0 and atc_on_ then
        atc.on(0, nil)
        atc_on_ = false
    end
end

-- 设置 RF 校准模式功能开关 (true=on, false=off)
function M.setRfOn(on)
    rf_mode_ = on and true or false

    local f = io.open(M._CFG_FILE_PATH, "w+")
    log.info("配置文件路径: ", M._CFG_FILE_PATH)
    if f then
        f:write(string.format("{\"isRFA_mode\":%d}\n", rf_mode_ and 1 or 0))
        f:close()
    else
        log.info("main", "写配置文件失败")
    end
    fskv.init()
    fskv.set("isRFA_mode", rf_mode_ and 1 or 0)
    return true
end

-- 获取 RF 校准模式功能开关状态 (return true=on, false=off)
-- 注意: 只有显式配置为0/false才表示退出rfa模式; 读不到任何配置时默认处于rfa校准模式
function M.getRFAOnStatus()
    local f = io.open(M._CFG_FILE_PATH, "r")
    log.info("配置文件路径: ", M._CFG_FILE_PATH)
    if f then
        log.info("main", "读取配置文件成功")
        local data = f:read("*a")
        f:close()
        if data then
            local cfg = json.decode(data)
            if cfg and cfg.isRFA_mode ~= nil then
                return cfg.isRFA_mode == 1 or cfg.isRFA_mode == true
            end
        end
    else
        log.info("main", "读取配置文件失败")
    end

    fskv.init()
    local v = fskv.get("isRFA_mode")
    if v ~= nil then
        log.info("main", "读取fskv配置成功")
        return v == 1
    end

    -- 文件和fskv都没有配置, 默认处于rfa校准模式
    return true
end

return M
