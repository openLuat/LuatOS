--[[
rfa: Radio Factory Agent (RF 校准 Lua 端主控)
================================================
]]

local M = { _VERSION = "1.0.2" }

M._CFG_FILE_PATH = "/factory.cfg"
local rf_mode_ = true -- 默认处于 rfa 校准模式, 只有显式配置为false才表示退出rfa模式
local out_buff = zbuff.create(8000)
-- 支持多端口同时响应 (如 VUART_0 + UART1), 每个端口独立接收缓冲
local uart_ids = {}     -- 已启动的 uart id 列表
local in_buffs = {}     -- uart id -> zbuff
local atc_on_ = false   -- atc 回调只注册一次
local atc_src_id = nil  -- 最近一次向 atc 投喂数据的端口, atc 应答回写到该端口
M.rfCaliDone, M.rfNSTDone = 0, 0


--解析AT指令，执行不同的操作; id 为收到数据的 uart 端口, 应答回写到同一端口
local function builtin_dispatch(line, id)
    log.info("rfa", "builtin_dispatch", line, line:toHex())
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
    local cfg, val = line:match('^AT%+SETCFG="?([^",]+)"?%s*,%s*"?([^",%s]+)"?%s*$')
    log.info("rfa", "builtin_dispatch", "AT+SETCFG", cfg, val)
    if cfg and val then
        in_buff:del()
        val = val:lower()
        log.info("val", val, val == "true", val == "false")
        if val == "true" or val == "false" then
            M.setRfOn(val == "true")
            log.info('true')
            return uart.write(id, string.format("\r\n+SETCFG: \"%s\",\"%s\"\r\n\r\nOK\r\n", cfg, val))
        else
            log.info('false')
            return uart.write(id, "\r\nERROR\r\n")
        end
    end

    -- AT+SETCFG?: get config (placeholder until C backend ready)
    if line == "AT+SETCFG?\r\n" then
        in_buff:del()
        return uart.write(id, string.format("\r\n+SETCFG: \"rfa_mode\",\"%s\"\r\n\r\nOK\r\n", M.getRFAOnStatus() and "true" or "false"))
    end

    atc_src_id = id
    atc.input(0, in_buff)
    in_buff:del()
end

--ATC 输出回调, 处理 ATC 模块的输出数据; 应答回写到发起该命令的端口
local function atc_out(id, event, param)
    local tx_id = atc_src_id or uart_ids[1]
    if tx_id then
        uart.tx(tx_id, out_buff)
    end
    local out_resp = out_buff:toStr(0, out_buff:used())
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
