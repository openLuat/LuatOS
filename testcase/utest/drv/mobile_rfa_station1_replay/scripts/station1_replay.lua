--[[
Station1 Cal & NST AT 流程 1:1 回放测试
=======================================
数据来源:
  D:/Documents/Weixin/xwechat_files/wxid_eipfdmjb89nu12_bbff/msg/file/2026-06/
  EC718_#Cal&NstStation1/866597074693456_2026-06-12_16-51-17_Thread0/
  866597074693456_UartComm_Log_Port4.txt

本测试按原始日志顺序逐条重放 64 条 WRITE AT 命令，并校验：
  - 标准 AT 命令的响应关键字
  - ECRFNST 私有协议返回 MT...OK 格式
  - 状态机随校准/NST 推进到 WRITE_NV / DONE
  - RF 在校准前被 CFUN=0 关闭

注意：原始日志中的读取类 ECRFNST 返回的是设备相关实时数据，
      Lua 端 rfa 模块当前为占位实现，因此只验证响应格式和流程通过，
      不逐字节比对读取数据内容。
]]

local station1 = require("station1_data")
local rfa = require("rfa")

local suite = {}

-- 截断过长字符串，避免大数据包刷屏
local function shorten(s)
    local limit = 120
    if #s <= limit then return s end
    return s:sub(1, limit) .. "...(" .. #s .. " bytes)"
end

-- 规范化响应里的 \r\n：删除首尾空行，中间多个换行合并为一个空格
local function vis(s)
    return s:gsub("^[\r\n]+", ""):gsub("[\r\n]+$", ""):gsub("[\r\n]+", " ")
end

-- 校验某条命令的期望响应特征，同时打印一次 AT 交互
local function checkResp(idx, cmd, resp, expects)
    log.info("rfa.replay", string.format("[%02d] --> %s", idx, shorten(cmd)))
    log.info("rfa.replay", string.format("[%02d] <-- %s", idx, shorten(vis(resp))))
    assert(type(resp) == "string",
           "cmd[" .. idx .. "] resp not string: " .. tostring(resp))
    expects = expects or {}
    for _, e in ipairs(expects) do
        assert(resp:find(e, 1, true),
               "cmd[" .. idx .. "] expect [" .. e .. "] got [" .. resp .. "]")
    end
end

-- 按日志 1:1 顺序回放
function suite.test_station1_full_replay()
    rfa._reset_for_test()

    local flow = station1.STATION1_AT_FLOW
    assert(#flow == 64, "station1 flow must have 64 AT commands, got " .. #flow)

    for idx, cmd in ipairs(flow) do
        local resp = rfa.dispatch(cmd)

        if cmd == "AT" then
            checkResp(idx, cmd, resp, {"OK"})
        elseif cmd == "ATE0" or cmd == "ATE1" then
            checkResp(idx, cmd, resp, {"OK"})
        elseif cmd == "AT+CPIN?" then
            checkResp(idx, cmd, resp, {"CME ERROR"})
        elseif cmd == "AT+ECGMDATA?" then
            checkResp(idx, cmd, resp, {"OK"})
        elseif cmd == "AT+CGSN" then
            checkResp(idx, cmd, resp, {"OK"})
            assert(rfa.state() >= rfa.STATE.PREP, "CGSN advances state to PREP")
        elseif cmd == "AT+CFUN=0 " then
            checkResp(idx, cmd, resp, {"OK"})
            assert(rfa.rfOn() == false, "CFUN=0 turns RF off")
        elseif cmd:match("^AT%+ECNPICFG=") then
            checkResp(idx, cmd, resp, {"OK"})
        elseif cmd:match("^AT%+ECRFNST=") then
            -- 占位实现下，所有 ECRFNST 返回 MT...OK
            checkResp(idx, cmd, resp, {"MT", "OK"})
        else
            checkResp(idx, cmd, resp, {"OK"})
        end
    end

    -- 流程结束后应进入 WRITE_NV 或更晚状态（ECNPICFG=rfCaliDone,1 置位）
    assert(rfa.state() >= rfa.STATE.WRITE_NV,
           "final state should be WRITE_NV or later, got " .. rfa.state())

    -- 最后一条是 ATE1，恢复 echo
    checkResp(65, "ATE1", rfa.dispatch("ATE1"), {"OK"})
    log.info("rfa.replay", "final state=" .. rfa.state() .. " expected >= " .. rfa.STATE.WRITE_NV)
end

-- 独立校验：流程启动前 RF 默认开启，CFUN=0 后关闭
function suite.test_station1_rf_gate()
    rfa._reset_for_test()
    log.info("rfa.replay", "RF on after reset: " .. tostring(rfa.rfOn()))
    assert(rfa.rfOn() == true, "RF on after reset")
    local resp = rfa.dispatch("AT+CFUN=0")
    log.info("rfa.replay", "--> AT+CFUN=0")
    log.info("rfa.replay", "<-- " .. shorten(vis(resp)))
    assert(rfa.rfOn() == false, "RF off after CFUN=0")
    rfa.dispatch("ATE1")
end

-- 独立校验：ECRFNST 在飞行模式下可执行（校准前置条件）
function suite.test_station1_rfnst_under_flight()
    rfa._reset_for_test()
    local cmd = "AT+CFUN=0"
    log.info("rfa.replay", "--> " .. cmd)
    local resp1 = rfa.dispatch(cmd)
    log.info("rfa.replay", "<-- " .. shorten(vis(resp1)))
    local rfnst = "AT+ECRFNST=02040900010003000500080022002600270028002900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000034126000076A"
    log.info("rfa.replay", "--> " .. shorten(rfnst))
    local resp2 = rfa.dispatch(rfnst)
    log.info("rfa.replay", "<-- " .. shorten(vis(resp2)))
    assert(type(resp2) == "string" and resp2:find("MT", 1, true), "RFNST runs under flight mode")
end

return {
    suite = suite,
}
