--[[
rfa: Radio Factory Agent (RF 校准 Lua 端主控)
================================================
设计:
  - 纯函数 dispatch(line) → 响应 string (便于单测)
  - 状态机 7 阶段, 由 dispatch 副作用推进
  - UART 绑定通过 rfa.start() 完成 (内部 uart.on)
  - 私有协议 AT+ECRFNST 在 Lua 端解析 + 响应生成
  - 状态存取经 mobile.rfTestParam 走 PC 仿真器
  - 跨 PC 仿真和真机: 行为完全一致 (C 端只做字节透传)
]]

local M = { _VERSION = "2.0.0" }
M.STATE = { IDLE=0, PREP=1, CALIB=2, SELF_CAL=3, WRITE_NV=4, NST_TEST=5, DONE=6 }

local uart_id_, line_buf = nil, ""
local handlers_, rfnst_tpl_ = {}, {}

-- C 端桥 (沿用 luat_mobile_rf_test_* 前缀)
-- 注意: 3rd arg 必须是 nil/false 才表示读, 整数 0 是 truthy 会被当写
local function param_get(k)  return mobile.rfTestParam(k, 0, nil) end
local function param_set(k,v) return mobile.rfTestParam(k, v, true) end
local function imei_get()     return mobile.rfTestImei() end

-- 状态机
function M.state()      return param_get("state") end
function M.setState(s)  return param_set("state", s) end
function M.reset()
    line_buf = ""
    param_set("state", 0)
    param_set("rfCaliDone", 0)
    param_set("rfNSTDone", 0)
    param_set("rfCTDone", 0)
    return true
end

-- NPI
function M.npiGet(k)        return param_get(k) end
function M.npiSet(k, v)     return param_set(k, v and 1 or 0) end

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
    if line == "AT+CGSN=1" then
        M.setState(math.max(M.state(), M.STATE.PREP))
        return '\r\n+CGSN: "' .. imei_get() .. '"\r\n\r\nOK\r\n'
    end
    local k, v = line:match("^AT%+ECNPICFG=([%w]+),(%d)$")
    if k then
        M.npiSet(k, tonumber(v))
        if k == "rfCaliDone" and v == "1" then M.setState(M.STATE.WRITE_NV) end
        if k == "rfNSTDone"  and v == "1" then M.setState(M.STATE.DONE) end
        return "\r\nOK\r\n"
    end
    if line == "AT+ECNPICFG?" then
        return string.format(
            '\r\n+ECNPICFG: "rfCaliDone":%d,"rfNSTDone":%d,"rfCTDone":%d\r\n\r\nOK\r\n',
            M.npiGet("rfCaliDone"), M.npiGet("rfNSTDone"), M.npiGet("rfCTDone"))
    end
    if line == "AT+CFUN=0" then return "\r\nOK\r\n" end
    if line == "AT+CPIN?"  then return "\r\n+CME ERROR: 303\r\n" end
    if line == "AT+ECCHIPVER?" then return "\r\nERROR\r\n" end
    if line == "AT+ECGMDATA?" then return "\r\nOK\r\n" end
    return "\r\nERROR\r\n"
end

function M._handle_rfnst(hex)
    hex = hex:upper()
    if #hex < 4 then return "\r\nERROR\r\n" end
    local cmd = hex:sub(1, 4)
    local tpl = rfnst_tpl_[cmd]
    local mt = tpl and tpl(hex)
              or ("MT" .. cmd .. "00000001000000000000")
    if M.state() < M.STATE.CALIB then M.setState(M.STATE.CALIB) end
    return "\r\n" .. mt .. "\r\nOK\r\n"
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
        uart.on(id, "receive", function(chunk)
            for _, line in ipairs(M.feed(chunk)) do
                local resp = M.dispatch(line)
                if resp and uart.write then uart.write(id, resp) end
            end
        end)
    end
    if mobile and mobile.rfTestMode then mobile.rfTestMode(id, 1) end
end

function M.stop()
    if mobile and mobile.rfTestMode then mobile.rfTestMode(uart_id_, 0) end
    uart_id_ = nil
    line_buf = ""
end

return M
