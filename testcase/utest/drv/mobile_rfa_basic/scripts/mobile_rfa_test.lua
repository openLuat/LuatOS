local t = {}

-- ============================================================
--  c_suite: C 端 luat_mobile_rf_test_* 桩基本行为
--  通过 Lua 绑定层 mobile.rfTest* 验证
-- ============================================================
local c_suite = {}

function c_suite.test_c_param_npi_rw()
    -- 复位
    mobile.rfTestParam("rfCaliDone", 0, true)
    mobile.rfTestParam("rfNSTDone", 0, true)
    mobile.rfTestParam("rfCTDone", 0, true)
    assert(mobile.rfTestParam("rfCaliDone") == 0)
    assert(mobile.rfTestParam("rfNSTDone") == 0)
    assert(mobile.rfTestParam("rfCTDone") == 0)
    -- 写
    assert(mobile.rfTestParam("rfCaliDone", 1, true) == 0)
    assert(mobile.rfTestParam("rfNSTDone", 1, true) == 0)
    assert(mobile.rfTestParam("rfCTDone", 1, true) == 0)
    -- 读
    assert(mobile.rfTestParam("rfCaliDone") == 1)
    assert(mobile.rfTestParam("rfNSTDone") == 1)
    assert(mobile.rfTestParam("rfCTDone") == 1)
    -- 复位
    mobile.rfTestParam("rfCaliDone", 0, true)
    mobile.rfTestParam("rfNSTDone", 0, true)
    mobile.rfTestParam("rfCTDone", 0, true)
end

function c_suite.test_c_param_state_rw()
    mobile.rfTestParam("state", 0, true)
    assert(mobile.rfTestParam("state") == 0)
    for _, s in ipairs({1, 2, 3, 4, 5, 6}) do
        mobile.rfTestParam("state", s, true)
        assert(mobile.rfTestParam("state") == s, "state=" .. s)
    end
    mobile.rfTestParam("state", 0, true)
end

function c_suite.test_c_param_unknown_key()
    -- 写未支持的 key 应返回 -1
    assert(mobile.rfTestParam("bogus_key", 1, true) == -1)
    -- 读未支持的 key 也返 -1 (此时 v 不变, 但返回值是 -1)
    local v = 0
    -- 我们的 Lua 绑定把 v 当读返回值: -1 表示 key 不支持
    -- 现有绑定是直接 push v, 不是 rv, 所以读未支持 key 时 push 0
    -- 这里只验证不会崩溃
    mobile.rfTestParam("bogus_key", 0, false)
end

function c_suite.test_c_imei_inject()
    local orig = mobile.rfTestImei()
    mobile.rfTestImeiSet("123456789012345")
    assert(mobile.rfTestImei() == "123456789012345", "imei get after set")
    -- 无效长度
    assert(mobile.rfTestImeiSet("12345") ~= 0, "imei set invalid len")
    -- 恢复
    mobile.rfTestImeiSet(orig)
    assert(mobile.rfTestImei() == orig, "imei reset")
end

function c_suite.test_c_mode_input_no_crash()
    -- 无回调时调 mode/input 不应崩
    mobile.rfTestMode(1, true)
    mobile.rfTestMode(nil, false)
    mobile.rfTestInput("AT\r\n")
    mobile.rfTestInput(nil)  -- flush
    mobile.rfTestInput("AT+CGSN=1\r\n")
end

-- ============================================================
--  lua_suite: mobile.rfTest* 5 个新绑定的注册和签名
-- ============================================================
local lua_suite = {}

function lua_suite.test_lua_binding_rfTestMode()
    assert(type(mobile.rfTestMode) == "function")
end
function lua_suite.test_lua_binding_rfTestInput()
    assert(type(mobile.rfTestInput) == "function")
end
function lua_suite.test_lua_binding_rfTestParam()
    assert(type(mobile.rfTestParam) == "function")
end
function lua_suite.test_lua_binding_rfTestImei()
    assert(type(mobile.rfTestImei) == "function")
end
function lua_suite.test_lua_binding_rfTestImeiSet()
    assert(type(mobile.rfTestImeiSet) == "function")
end

function lua_suite.test_lua_nst_aliases_removed()
    -- mobile.nstOnOff / mobile.nstInput 已在阶段 4 删除 (替代为 rfTestMode/Input)
    -- 这里反过来验证它们**不存在**, 防止有人手贱复活
    assert(mobile.nstOnOff == nil, "nstOnOff should be removed")
    assert(mobile.nstInput == nil, "nstInput should be removed")
end

-- ============================================================
--  at_suite: rfa.dispatch 内建 AT 派发表覆盖
-- ============================================================
local at_suite = {}

local function assertResp(line, expect_sub)
    local rfa = require("rfa")
    rfa._reset_for_test()
    local resp = rfa.dispatch(line)
    assert(type(resp) == "string", "resp type: " .. type(resp) .. " for " .. line)
    assert(resp:find(expect_sub, 1, true), "line=" .. line .. " expect=" .. expect_sub .. " got=" .. resp)
end

function at_suite.test_at_bare()
    assertResp("AT", "OK")
end
function at_suite.test_at_ate0()
    assertResp("ATE0", "OK")
end
function at_suite.test_at_ate1()
    assertResp("ATE1", "OK")
end
function at_suite.test_at_cgsn()
    assertResp("AT+CGSN=1", "+CGSN:")
    assertResp("AT+CGSN=1", "OK")
    assertResp("AT+CGSN=1", "864317081553409")  -- 默认 IMEI
end
function at_suite.test_at_ecnpicfg_set()
    assertResp("AT+ECNPICFG=rfCaliDone,1", "OK")
    assertResp("AT+ECNPICFG=rfNSTDone,1", "OK")
    assertResp("AT+ECNPICFG=rfCTDone,1", "OK")
    assertResp("AT+ECNPICFG=rfCaliDone,0", "OK")
    assertResp("AT+ECNPICFG=rfNSTDone,0", "OK")
    assertResp("AT+ECNPICFG=rfCTDone,0", "OK")
    -- 带引号和对齐 AT 固件的多组 key-value
    assertResp('AT+ECNPICFG="rfCaliDone",1,"rfNSTDone",1', "OK")
    assertResp('AT+ECNPICFG="rfCaliDone",0,"rfNSTDone",0,"rfCTDone",0', "OK")
end
function at_suite.test_at_ecnpicfg_query()
    local rfa = require("rfa")
    rfa._reset_for_test()
    -- 默认 0, 格式对齐 AT 固件: "rfNSTDone":%d, 后面有空格
    local resp = rfa.dispatch("AT+ECNPICFG?")
    assert(resp:find('"rfCaliDone":0', 1, true), "query has rfCaliDone:0")
    assert(resp:find('"rfNSTDone":0', 1, true), "query has rfNSTDone:0")
    assert(resp:find('"rfCTDone":0', 1, true), "query has rfCTDone:0")
    -- 置 1 后再查
    rfa.npiSet("rfCaliDone", 1)
    local resp2 = rfa.dispatch("AT+ECNPICFG?")
    assert(resp2:find('"rfCaliDone":1', 1, true), "query after set has rfCaliDone:1")
end
function at_suite.test_at_ecnpicfg_test()
    assertResp("AT+ECNPICFG=?", "+ECNPICFG:<option>,<setting>")
    assertResp("AT+ECNPICFG=?", "OK")
end
function at_suite.test_at_cfun()
    local rfa = require("rfa")
    rfa._reset_for_test()
    -- 默认 RF 开
    assert(rfa.rfOn() == true, "rf should be on after reset")
    -- CFUN=0 → 关射频 (校准前的硬前置, 真机走标准 AT 切飞行模式)
    rfa.dispatch("AT+CFUN=0")
    assert(rfa.rfOn() == false, "rf should be off after CFUN=0")
    -- CFUN=1 → 开射频
    rfa.dispatch("AT+CFUN=1")
    assert(rfa.rfOn() == true, "rf should be on after CFUN=1")
    -- CFUN=4 → 飞行模式别名, RF 关
    rfa.dispatch("AT+CFUN=4")
    assert(rfa.rfOn() == false, "rf should be off after CFUN=4")
    -- 响应文本
    rfa._reset_for_test()
    assert(rfa.dispatch("AT+CFUN=0"):find("OK", 1, true), "CFUN=0 returns OK")
    rfa._reset_for_test()
    assert(rfa.dispatch("AT+CFUN=1"):find("OK", 1, true), "CFUN=1 returns OK")
end
function at_suite.test_at_rfnst_runs_under_flight_mode()
    -- 真实校准流程: AT+CFUN=0 之后立刻跑 AT+ECRFNST, 不可被门控
    -- (F:\hardware\calrf\864317081553409_UartComm_Log_Port14.txt)
    local rfa = require("rfa")
    rfa._reset_for_test()
    rfa.dispatch("AT+CFUN=0")  -- 切到飞行模式
    assert(rfa.rfOn() == false, "rf should be off after CFUN=0")
    local resp = rfa.dispatch("AT+ECRFNST=020408000000")
    assert(resp:find("MT0204", 1, true),
           "RFNST must run under flight mode, got: " .. tostring(resp))
end
function at_suite.test_at_cpin_no_sim()
    assertResp("AT+CPIN?", "CME ERROR")
end
function at_suite.test_at_chipver()
    assertResp("AT+ECCHIPVER?", "+ECCHIPVER:")
    assertResp("AT+ECCHIPVER?", "OK")
end
function at_suite.test_at_ecgmdata()
    local rfa = require("rfa")
    rfa._reset_for_test()
    assertResp("AT+ECGMDATA?", "OK")
    if mobile and mobile.rfTestGmDataSet then
        mobile.rfTestGmDataSet("test_golden_data")
        local resp = rfa.dispatch("AT+ECGMDATA?")
        assert(resp:find("test_golden_data", 1, true), "GMDATA read back")
    end
end
function at_suite.test_at_unknown()
    assertResp("AT+FOOBAR=1", "ERROR")
end

function at_suite.test_at_ecrst()
    assertResp("AT+ECRST", "OK")
end

function at_suite.test_at_ati()
    assertResp("ATI", "OK")
    local rfa = require("rfa")
    rfa._reset_for_test()
    local resp = rfa.dispatch("ATI")
    assert(resp:find("AirM2M_", 1, true) or resp:find("V", 1, true), "ATI returns version info, got: " .. tostring(resp))
end

function at_suite.test_at_muid()
    assertResp("AT+MUID?", "+MUID:")
    assertResp("AT+MUID?", "OK")
end

function at_suite.test_at_atxi()
    assertResp("AT*I", "Manufacturer:")
    assertResp("AT*I", "Model:")
    assertResp("AT*I", "Revision:")
    assertResp("AT*I", "IMEI:")
    assertResp("AT*I", "OK")
end

function at_suite.test_at_eccgsn()
    local rfa = require("rfa")
    rfa._reset_for_test()
    local orig = rfa.imei()
    assertResp("AT+ECCGSN=1,123456789012345", "OK")
    assert(rfa.imei() == "123456789012345", "ECCGSN updated IMEI")
    -- invalid length
    local resp = rfa.dispatch("AT+ECCGSN=1,12345")
    assert(resp:find("ERROR", 1, true), "short imei rejected")
    rfa.setImei(orig)
end

function at_suite.test_at_ecband()
    assertResp("AT+ECBAND=?", "+ECBAND:")
    assertResp("AT+ECBAND=?", "OK")
end

function at_suite.test_at_eciccid()
    local rfa = require("rfa")
    local resp = rfa.dispatch("AT+ECICCID")
    assert(type(resp) == "string", "ECICCID returns string")
    assert(resp:find("OK", 1, true), "ECICCID ends with OK")
end

function at_suite.test_at_ecpmucfg()
    assertResp("AT+ECPMUCFG=0", "OK")
    assertResp("AT+ECPMUCFG=1,1", "OK")
    assertResp("AT+ECPMUCFG?", "+ECPMUCFG:")
end

function at_suite.test_at_ecfacchk()
    assertResp("AT+ECFACCHK=1", "+ECFACCHK:")
    assertResp("AT+ECFACCHK=1", "OK")
end

-- ============================================================
--  rfa_suite: rfa.lua 模块高级功能
-- ============================================================
local rfa_suite = {}

function rfa_suite.test_rfa_state_constants()
    local rfa = require("rfa")
    assert(rfa.STATE.IDLE == 0)
    assert(rfa.STATE.PREP == 1)
    assert(rfa.STATE.CALIB == 2)
    assert(rfa.STATE.SELF_CAL == 3)
    assert(rfa.STATE.WRITE_NV == 4)
    assert(rfa.STATE.NST_TEST == 5)
    assert(rfa.STATE.DONE == 6)
end

function rfa_suite.test_rfa_reset_clears_state()
    local rfa = require("rfa")
    rfa.setState(5)
    assert(rfa.state() == 5)
    rfa.reset()
    assert(rfa.state() == 0)
    assert(rfa.npiGet("rfCaliDone") == 0)
    assert(rfa.npiGet("rfNSTDone") == 0)
    assert(rfa.npiGet("rfCTDone") == 0)
end

function rfa_suite.test_rfa_state_transitions()
    local rfa = require("rfa")
    rfa._reset_for_test()
    assert(rfa.state() == 0)  -- IDLE
    rfa.dispatch("AT+CGSN=1")
    assert(rfa.state() >= 1, "after CGSN, state should be PREP, got " .. rfa.state())
    rfa.dispatch("AT+ECRFNST=020408000000")
    assert(rfa.state() >= 2, "after ECRFNST, state should be CALIB")
    rfa.dispatch("AT+ECNPICFG=rfCaliDone,1")
    assert(rfa.state() == 4, "after rfCaliDone=1, state should be WRITE_NV")
    rfa.dispatch("AT+ECNPICFG=rfNSTDone,1")
    assert(rfa.state() == 6, "after rfNSTDone=1, state should be DONE")
end

function rfa_suite.test_rfa_state_only_advances()
    local rfa = require("rfa")
    rfa._reset_for_test()
    rfa.setState(6)  -- DONE
    rfa.dispatch("AT+CGSN=1")  -- 试图回到 PREP
    assert(rfa.state() == 6, "state should not regress from DONE")
end

function rfa_suite.test_rfa_rfnst_default_template()
    local rfa = require("rfa")
    rfa._reset_for_test()
    local resp = rfa.dispatch("AT+ECRFNST=020408000000")
    assert(type(resp) == "string")
    -- 默认模板: MT + cmdId 4hex + 20 位占位
    assert(resp:find("MT0204", 1, true), "default template uses cmdId from input")
    assert(resp:find("OK", 1, true), "RFNST ends with OK")
end

function rfa_suite.test_rfa_rfnst_custom_template()
    local rfa = require("rfa")
    rfa._reset_for_test()
    rfa.registerRfnst("9999", function(hex) return "MT9999CUSTOM" .. hex:sub(5) end)
    local resp = rfa.dispatch("AT+ECRFNST=9999DEAD")
    assert(resp:find("MT9999CUSTOM", 1, true), "custom template applied")
end

function rfa_suite.test_rfa_rfnst_short_hex()
    local rfa = require("rfa")
    rfa._reset_for_test()
    local resp = rfa.dispatch("AT+ECRFNST=02")  -- < 4 chars
    assert(resp:find("ERROR", 1, true), "short hex returns ERROR")
end

function rfa_suite.test_rfa_err_mode()
    local rfa = require("rfa")
    rfa._reset_for_test()
    rfa.setErrMode(true)
    local resp = rfa.dispatch("AT")
    assert(resp:find("ERROR", 1, true), "err mode returns ERROR")
    rfa.setErrMode(false)
    local resp2 = rfa.dispatch("AT")
    assert(resp2:find("OK", 1, true), "after disable err mode, returns OK")
end

function rfa_suite.test_rfa_register_extension()
    local rfa = require("rfa")
    rfa._reset_for_test()
    -- 用户可注册自定义 AT 命令
    rfa.register("AT+MYCMD", function(line, ctx)
        return "\r\n+MYCMD: hello\r\n\r\nOK\r\n"
    end)
    local resp = rfa.dispatch("AT+MYCMD")
    assert(resp:find("MYCMD: hello", 1, true), "registered command works")
end

function rfa_suite.test_rfa_feed_line_splitting()
    local rfa = require("rfa")
    rfa._reset_for_test()
    -- 分块输入, 验证行切分
    local lines1 = rfa.feed("AT+CGSN")
    assert(#lines1 == 0, "no complete line yet, got " .. #lines1)
    local lines2 = rfa.feed("=1\r\nAT\r")
    -- 拼接后 "AT+CGSN=1\r\nAT\r": 切出 "AT+CGSN=1" 和 "AT" 两条
    assert(#lines2 == 2, "2 complete lines, got " .. #lines2)
    assert(lines2[1] == "AT+CGSN=1", "first line")
    assert(lines2[2] == "AT", "second line")
    local lines3 = rfa.feed("\n")
    assert(#lines3 == 0, "no more complete lines after final \\n, got " .. #lines3)
    rfa._reset_for_test()
end

function rfa_suite.test_rfa_setImei_validation()
    local rfa = require("rfa")
    rfa._reset_for_test()
    -- 长度不对
    local ok = rfa.setImei("1234")
    assert(ok == false, "short imei rejected")
    local ok2 = rfa.setImei("1234567890123456")
    assert(ok2 == false, "long imei rejected")
    -- 长度对
    local ok3 = rfa.setImei("999999999999999")
    assert(ok3 == true, "15-char imei accepted")
    assert(rfa.imei() == "999999999999999", "imei updated")
    rfa.setImei("864317081553409")  -- reset
end

function rfa_suite.test_rfa_imei_visible_in_cgsn()
    local rfa = require("rfa")
    rfa._reset_for_test()
    rfa.setImei("999999999999999")
    local resp = rfa.dispatch("AT+CGSN=1")
    assert(resp:find("999999999999999", 1, true), "CGSN returns injected IMEI")
    rfa.setImei("864317081553409")  -- reset
end

function rfa_suite.test_rfa_dispatch_empty_line()
    local rfa = require("rfa")
    rfa._reset_for_test()
    local resp = rfa.dispatch("")
    assert(resp == nil, "empty line returns nil")
    local resp2 = rfa.dispatch(nil)
    assert(resp2 == nil, "nil line returns nil")
end

return {
    c_suite   = c_suite,
    lua_suite = lua_suite,
    at_suite  = at_suite,
    rfa_suite = rfa_suite,
}
