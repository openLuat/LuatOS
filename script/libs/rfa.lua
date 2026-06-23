--[[
rfa: Radio Factory Agent (RF 校准 Lua 端主控)
================================================
设计:
  - 纯函数 dispatch(line) → 响应 string (便于单测)
  - 状态机 7 阶段, 由 dispatch 副作用推进
  - UART 绑定通过 rfa.start() 完成 (内部 uart.on)
  - 私有协议 AT+ECRFNST 优先走 C 后端 mobile.rfTestNst (真机调用 RfAtNstCmdPreHandle)
  - 状态存取经 mobile.rfTestParam 走 PC 仿真器
  - 跨 PC 仿真和真机: 行为完全一致 (C 端只做字节透传)
]]

local M = { _VERSION = "2.0.0" }
M.STATE = { IDLE=0, PREP=1, CALIB=2, SELF_CAL=3, WRITE_NV=4, NST_TEST=5, DONE=6 }

local uart_id_, line_buf, rf_on_ = nil, "", true
local handlers_, rfnst_tpl_ = {}, {}
M._cmd_q = {}
M._q_running = false

-- C 端桥 (沿用 luat_mobile_rf_test_* 前缀)
-- 注意: 3rd arg 必须是 nil/false 才表示读, 整数 0 是 truthy 会被当写
local function param_get(k)  return mobile.rfTestParam(k, 0, nil) end
local function param_set(k,v) return mobile.rfTestParam(k, v, true) end
local function imei_get()     return mobile.rfTestImei() end

-- 状态机
function M.state()      return param_get("state") end
function M.setState(s)  return param_set("state", s) end
function M.rfOn()       return rf_on_ end
function M.reset()
    line_buf = ""
    rf_on_ = true
    param_set("state", 0)
    M.npiSet("rfCaliDone", 0, true)
    M.npiSet("rfNSTDone", 0, true)
    M.npiSet("rfCTDone", 0, true)
    mobile.rfTestParam("save", 0, true)
    return true
end

-- NPI
function M.npiGet(k)        return param_get(k) end
function M.npiSet(k, v, no_save)
    -- Lua 中 0 是 truthy, 不能直接用 `v and 1 or 0`
    local val = (v == true or v == 1) and 1 or 0
    local r = param_set(k, val)
    if not no_save and mobile and mobile.rfTestParam then
        mobile.rfTestParam("save", 0, true)
    end
    return r
end

-- IMEI
function M.imei()           return imei_get() end
function M.setImei(s)
    if type(s) ~= "string" or #s ~= 15 then return false, "imei length" end
    return mobile.rfTestImeiSet(s) == 0
end

-- 单测辅助
function M.setErrMode(on)   M._erf = on; param_set("erfMode", on and 1 or 0) end
function M._reset_for_test() line_buf = ""; M.reset() end

-- 扩展点
function M.register(cmd_prefix, fn)         handlers_[cmd_prefix] = fn end
function M.registerRfnst(cmd_id_hex, fn)    rfnst_tpl_[cmd_id_hex:upper()] = fn end

-- 派发 (纯函数)
function M.dispatch(line)
    if not line or #line == 0 then return nil end
    if M._erf then return "\r\nERROR\r\n" end

    -- 1) 私有协议优先
    -- 注: 校准就是要在飞行模式 (CFUN=0) 下跑, 不可被 rf_on_ 门控
    local hex = line:match("^AT%+ECRFNST=(.+)$")
    if hex then return M._handle_rfnst(hex) end

    -- 2) 扩展表
    for prefix, fn in pairs(handlers_) do
        if line:sub(1, #prefix) == prefix then
            return fn(line, {
                npiGet = M.npiGet, npiSet = M.npiSet,
                state  = M.state,  setState = M.setState,
            })
        end
    end

    -- 3) 内建表
    return M._builtin_dispatch(line)
end

function M._builtin_dispatch(line)
    if line == "AT" or line:match("^ATE%d*$") then
        return "\r\nOK\r\n"
    end
    if line == "AT+CGSN" then
        M.setState(math.max(M.state(), M.STATE.PREP))
        return '\r\n' .. imei_get() .. '\r\n\r\nOK\r\n'
    end
    if line == "AT+CGSN=1" then
        M.setState(math.max(M.state(), M.STATE.PREP))
        return '\r\n+CGSN: "' .. imei_get() .. '"\r\n\r\nOK\r\n'
    end
    -- AT+ECNPICFG: NPI 状态读写 (对齐 AT 固件 atec_product.c)
    if line == "AT+ECNPICFG=?" then
        return "\r\n+ECNPICFG:<option>,<setting>\r\n\r\nOK\r\n"
    end
    if line == "AT+ECNPICFG?" then
        -- 注意 AT 固件格式中 "rfNSTDone":%d, 后面有一个空格
        return string.format(
            '\r\n+ECNPICFG: "rfCaliDone":%d,"rfNSTDone":%d, "rfCTDone":%d\r\n\r\nOK\r\n',
            M.npiGet("rfCaliDone"), M.npiGet("rfNSTDone"), M.npiGet("rfCTDone"))
    end
    local cfg_body = line:match("^AT%+ECNPICFG=(.+)$")
    if cfg_body then
        -- 支持带引号或不带引号的 key, 支持多组 key,value
        local ok = true
        local any_changed = false
        -- 先整体去掉可能存在的首尾引号, 简化解析
        cfg_body = cfg_body:gsub('"', '')
        -- 按逗号切分, 得到 [key1, val1, key2, val2, ...]
        local parts = {}
        for p in cfg_body:gmatch("[^,]+") do
            table.insert(parts, p)
        end
        if #parts == 0 or (#parts % 2) ~= 0 then
            ok = false
        else
            for i = 1, #parts, 2 do
                local k = parts[i]
                local v = tonumber(parts[i + 1])
                if not v or (v ~= 0 and v ~= 1) then
                    ok = false
                    break
                end
                if k == "rfCaliDone" or k == "rfNSTDone" or k == "rfCTDone" then
                    -- 只有值变化时才落 flash (与 AT 固件一致)
                    local old = M.npiGet(k)
                    M.npiSet(k, v, true)  -- no_save
                    if old ~= v then
                        any_changed = true
                    end
                    if k == "rfCaliDone" and v == 1 then M.setState(M.STATE.WRITE_NV) end
                    if k == "rfNSTDone"  and v == 1 then M.setState(M.STATE.DONE) end
                else
                    ok = false
                    break
                end
            end
        end
        if any_changed then
            -- 触发统一保存 (若 C 后端支持 save key)
            if mobile and mobile.rfTestParam then
                mobile.rfTestParam("save", 0, true)
            end
        end
        if ok then
            return "\r\nOK\r\n"
        else
            return "\r\n+CME ERROR: 50\r\n"  -- CME_INCORRECT_PARAM
        end
    end
    if line:match("^AT%+CFUN=0%s*$") then
        rf_on_ = false
        if mobile and mobile.flymode then mobile.flymode(0, true) end
        return "\r\nOK\r\n"
    end
    if line:match("^AT%+CFUN=1%s*$") then
        rf_on_ = true
        if mobile and mobile.flymode then mobile.flymode(0, false) end
        return "\r\nOK\r\n"
    end
    if line:match("^AT%+CFUN=4%s*$") then
        rf_on_ = false
        if mobile and mobile.flymode then mobile.flymode(0, true) end
        return "\r\nOK\r\n"
    end  -- 飞行模式别名
    if line == "AT+CPIN?"  then return rf_on_ and (mobile.simPin() and "\r\n+CPIN: READY\r\n\r\nOK\r\n" or "\r\n+CME ERROR: 10\r\n") or "\r\n+CME ERROR: 304\r\n" end

    -- AT+ECRST: software reset
    if line == "AT+ECRST" then
        if mobile and rtos.reboot then sys.timerStart(rtos.reboot, 100) end
        return "\r\nOK\r\n"
    end

    -- AT+ECCGSN=<type>,<sn/imei>: write IMEI/SN
    -- 优先匹配带引号格式: AT+ECCGSN="IMEI","862323089123503"
    local cg_type, cg_val = line:match('^AT%+ECCGSN=%s*"([^"]+)"%s*,%s*"([^"]+)"%s*$')

    -- 兼容不带引号格式: AT+ECCGSN=IMEI,862323089123503
    if not cg_type then
        cg_type, cg_val = line:match('^AT%+ECCGSN=%s*([^,]+)%s*,%s*(%S+)%s*$')
    end

    if cg_type then
        -- 去除首尾可能残留的引号（防御性）
        cg_type = cg_type:gsub('^"', ''):gsub('"$', '')
        cg_val  = cg_val:gsub('^"', ''):gsub('"$', '')
        
        if cg_type == "IMEI" and #cg_val == 15 then
            if M.setImei(cg_val) then
                return "\r\nOK\r\n"
            end
        end
        return "\r\nERROR\r\n"
    end

    -- AT+ECGMDATA: golden sample data read/write
    if line == "AT+ECGMDATA?" then
        local gm = (mobile and mobile.rfTestGmData) and mobile.rfTestGmData() or ""
        if gm and #gm > 0 then
            return '\r\n+ECGMDATA: "' .. gm .. '"\r\n\r\nOK\r\n'
        end
        return "\r\nOK\r\n"
    end
    local gm = line:match("^AT%+ECGMDATA=(.+)$")
    if gm then
        if mobile and mobile.rfTestGmDataSet then
            mobile.rfTestGmDataSet(gm)
        end
        return "\r\nOK\r\n"
    end

    -- AT+ECCHIPVER?: chip version (use hmeta.chip() when available)
    if line == "AT+ECCHIPVER?" then
        local ver = ""
        if hmeta and hmeta.chip then
            ver = hmeta.chip()
        elseif mobile and mobile.rfTestParam then
            ver = mobile.rfTestParam("chipVer") or 0
        else
            ver = 0
        end
        return string.format("\r\n+ECCHIPVER:%s\r\n\r\nOK\r\n", ver)
    end

    -- ATI: module version
    if line == "ATI" then
        local version = "Unknown"
        if rtos and rtos.version then
            local ver = rtos.version()
            local model = (hmeta and hmeta.model) and hmeta.model() or ""
            if model ~= "" then
                local suffix = #model > 3 and model:sub(4) or model
                version = "LuatOS_" .. suffix .. "_" .. ver
            else
                version = ver
            end
        end
        return "\r\n" .. version .. "\r\n\r\nOK\r\n"
    end

    -- AT+MUID?: MUID query
    if line == "AT+MUID?" then
        local muid = (mobile and mobile.muid) and mobile.muid() or ""
        return string.format("\r\n+MUID: %s\r\n\r\nOK\r\n", muid)
    end

    -- AT*I: module version and detailed information
    if line == "AT*I" then
        local model   = (hmeta and hmeta.model) and hmeta.model() or ""
        local hwver   = (hmeta and hmeta.hwver) and hmeta.hwver() or ""
        local suffix = (model ~= "" and #model > 3) and model:sub(4) or (model ~= "" and model or "Unknown")
        local version = "LuatOS_" .. suffix .. "_" .. ((rtos and rtos.version) and rtos.version() or "Unknown")
        local imei    = (mobile and mobile.imei) and mobile.imei() or ""
        local iccid   = (mobile and mobile.iccid) and mobile.iccid() or ""
        local imsi    = (mobile and mobile.imsi) and mobile.imsi() or ""
        local buildtm = os.date("%Y-%m-%d %H:%M:%S")
        local info = string.format(
            "Manufacturer: LuatOS\r\nModel: %s\r\nRevision: %s\r\nHWver: %s\r\nBuildtime: %s\r\nIMEI: %s\r\nICCID: %s\r\nIMSI: %s",
            model, version, hwver, buildtm, imei, iccid, imsi)
        return "\r\n" .. info .. "\r\n\r\nOK\r\n"
    end

    -- AT+ECBAND=?: supported bands (placeholder until C backend ready)
    if line == "AT+ECBAND=?" then
        local bands = (mobile and mobile.rfTestParam)
                      and mobile.rfTestParam("bandList") or 0
        return string.format("\r\n+ECBAND: (%s)\r\n\r\nOK\r\n",
                             bands ~= 0 and tostring(bands) or "1,3,5,8,34,38,39,40,41")
    end

    -- AT+ECICCID: ICCID
    if line == "AT+ECICCID" or line == "AT+ECICCID?" then
        local iccid = ""
        if mobile and mobile.iccid then
            iccid = mobile.iccid()
        end
        if iccid and #iccid > 0 then
            return '\r\n+ECICCID: "' .. iccid .. '"\r\n\r\nOK\r\n'
        end
        return "\r\nOK\r\n"
    end

    -- AT+ECPMUCFG: PMU mode (placeholder until C backend ready)
    local pmu_enable, pmu_mode = line:match("^AT%+ECPMUCFG=(%d),?(.*)$")
    if pmu_enable then
        if mobile and mobile.rfTestParam then
            mobile.rfTestParam("pmuEnable", tonumber(pmu_enable), true)
            if pmu_mode and #pmu_mode > 0 then
                mobile.rfTestParam("pmuMode", tonumber(pmu_mode), true)
            end
        end
        return "\r\nOK\r\n"
    end
    if line == "AT+ECPMUCFG?" then
        local en = (mobile and mobile.rfTestParam) and mobile.rfTestParam("pmuEnable") or 0
        local md = (mobile and mobile.rfTestParam) and mobile.rfTestParam("pmuMode") or 0
        return string.format("\r\n+ECPMUCFG: %d,%d\r\n\r\nOK\r\n", en, md)
    end

    -- AT+ECFACCHK=1: factory NV header check (placeholder until C backend ready)
    if line == "AT+ECFACCHK=1" then
        local chk = (mobile and mobile.rfTestParam) and mobile.rfTestParam("facChk") or 0
        return string.format("\r\n+ECFACCHK: %d\r\n\r\nOK\r\n", chk)
    end

    return "\r\nERROR\r\n"
end

-- 砍掉底层可能带下来的二进制脏尾, 只保留 MT + 合法 hex
function M._clean_nst_resp(resp)
    if type(resp) ~= "string" or #resp < 2 then return nil end
    if resp:sub(1, 2) == "MT" then
        local clean = resp:match("^(MT%x+)")
        return clean or resp:sub(1, 2)
    end
    return resp
end

-- 根据参考校准日志 866597074693456_UartComm_Log_Port4.txt 的格式:
-- 03 / 020F / 0A / 12: 先 MT 后 OK
-- 其它 02xx: 先 OK 后 MT(MT 由 PHY IND 异步回来)
local MT_FIRST_PREFIX = { ["03"]=true, ["0A"]=true, ["12"]=true, ["020F"]=true }

-- 后台顺序执行 ECRFNST 命令, 避免阻塞 UART 接收导致流水线丢包
function M._push_nst(item)
    table.insert(M._cmd_q, item)
    if not M._q_running and uart_id_ and _G.sys and _G.sys.taskInit then
        M._q_running = true
        _G.sys.taskInit(function()
            while #M._cmd_q > 0 do
                local it = table.remove(M._cmd_q, 1)
                -- 先 OK 后 MT 的命令: 让 OK 先真正离开发送缓冲, 再触发底层取 MT
                if it.mode == "ok_first" and _G.sys.wait then
                    _G.sys.wait(30)
                end
                local rc, resp = mobile.rfTestNst(it.hex)
                resp = M._clean_nst_resp(resp)
                if rc == -2 then
                    uart.write(uart_id_, "\r\nCRCERROR\r\n")
                elseif rc == -3 then
                    uart.write(uart_id_, "\r\nDBKERROR\r\n")
                elseif rc ~= 0 then
                    uart.write(uart_id_, "\r\nERROR\r\n")
                else
                    if it.mode == "mt_first" then
                        if resp and #resp > 0 then
                            uart.write(uart_id_, "\r\n" .. resp .. "\r\n\r\nOK\r\n")
                        else
                            -- 由 PHY IND 发了 MT, 这里补 OK
                            uart.write(uart_id_, "\r\nOK\r\n")
                        end
                    else
                        if resp and #resp > 0 then
                            uart.write(uart_id_, "\r\n" .. resp .. "\r\n")
                        end
                    end
                end
            end
            M._q_running = false
        end)
    end
end

function M._handle_rfnst(hex)
    hex = hex:upper()
    if #hex < 4 then return "\r\nERROR\r\n" end
    local cmd = hex:sub(1, 4)

    -- 1) 用户自定义模板最高优先级
    local tpl = rfnst_tpl_[cmd]
    if tpl then
        -- 自定义模板内部自己负责状态机或不推进, 这里不再二次推进
        return "\r\n" .. tpl(hex) .. "\r\nOK\r\n"
    end

    -- 2) 若 C 后端支持真正的 NST 处理, 走底层 (对齐 AT 固件 phyECRFNST)
    if mobile and mobile.rfTestNst then
        M._advance_by_cmd(cmd)

        local prefix2 = cmd:sub(1, 2)
        local mt_first = MT_FIRST_PREFIX[prefix2] or MT_FIRST_PREFIX[cmd:sub(1, 4)]

        -- 真机 UART 模式使用队列, 避免阻塞 UART 接收; 测试环境保持同步返回
        if uart_id_ and _G.sys and _G.sys.taskInit then
            if mt_first then
                M._push_nst({hex = hex, mode = "mt_first"})
                return nil
            else
                M._push_nst({hex = hex, mode = "ok_first"})
                return "\r\nOK\r\n"
            end
        end

        -- PC / 测试环境同步返回
        local rc, resp = mobile.rfTestNst(hex)
        resp = M._clean_nst_resp(resp)
        if rc == -2 then return "\r\nCRCERROR\r\n" end
        if rc == -3 then return "\r\nDBKERROR\r\n" end
        if rc ~= 0 then return "\r\nERROR\r\n" end
        if mt_first then
            if resp and #resp > 0 then
                return "\r\n" .. resp .. "\r\n\r\nOK\r\n"
            end
            return "\r\nOK\r\n"
        end
        if resp and #resp > 0 then
            return "\r\n" .. resp .. "\r\nOK\r\n"
        end
        return "\r\nOK\r\n"
    end

    -- 3) 默认占位模板
    M._advance_by_cmd(cmd)
    local mt = "MT" .. cmd .. "00000001000000000000"
    return "\r\n" .. mt .. "\r\nOK\r\n"
end

-- 根据 RFNST cmdId 推进状态机
function M._advance_by_cmd(cmd)
    if cmd == "0D0A" then
        -- self-calibration command pair, advance to SELF_CAL
        if M.state() < M.STATE.SELF_CAL then M.setState(M.STATE.SELF_CAL) end
    elseif cmd >= "0051" and cmd <= "005A" then
        -- non-signaling test range, advance to NST_TEST
        if M.state() < M.STATE.NST_TEST then M.setState(M.STATE.NST_TEST) end
    else
        if M.state() < M.STATE.CALIB then M.setState(M.STATE.CALIB) end
    end
end

-- 行切分
function M.feed(chunk)
    if not chunk or #chunk == 0 then return {} end
    line_buf = line_buf .. chunk
    local lines = {}
    while true do
        local s, e = line_buf:find("[\r\n]+")
        if not s then break end
        local line = line_buf:sub(1, s - 1)
        line_buf = line_buf:sub(e + 1)
        if #line > 0 then lines[#lines + 1] = line end
    end
    return lines
end

-- UART 集成 (内部 mobile.rfTestMode 走 C 端切模式)
function M.start(id, baud)
    uart_id_ = id
    line_buf = ""
    if uart and uart.setup then uart.setup(id, baud or 115200) end
    if uart and uart.on then
        uart.on(id, "receive", function(uart_id, len)
            -- 真机回调: id + len, 需 uart.read 读取缓冲区
            local chunk = ""
            repeat
                local s = uart.read(uart_id, 128)
                if s and #s > 0 then chunk = chunk .. s end
            until s == "" or not s
            if #chunk > 0 then
                for _, line in ipairs(M.feed(chunk)) do
                    local resp = M.dispatch(line)
                    if resp and uart.write then uart.write(uart_id, resp) end
                end
            end
        end)
    end
    if mobile and mobile.rfTestMode then mobile.rfTestMode(id, true) end
end

function M.stop()
    if mobile and mobile.rfTestMode then mobile.rfTestMode(uart_id_, false) end
    uart_id_ = nil
    line_buf = ""
end

return M
