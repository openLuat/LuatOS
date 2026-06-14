local t = {}

-- C层 utest 桥
local function run_c(case) return mobile.utest(case) == true end
local c_suite = {}
function c_suite.test_c_npi_bit_rw()     assert(run_c("rfcal_npi_bit_rw"), "C: npi rw") end
function c_suite.test_c_state_machine()  assert(run_c("rfcal_state_machine"), "C: state") end
function c_suite.test_c_imei_inject()    assert(run_c("rfcal_imei_inject"), "C: imei") end
function c_suite.test_c_at_handshake()   assert(run_c("rfcal_at_handshake"), "C: at") end
function c_suite.test_c_rfnst_known()    assert(run_c("rfcal_rfnst_known"), "C: rfnst") end
function c_suite.test_c_reset()          assert(run_c("rfcal_reset_clears_state"), "C: reset") end

-- Lua 绑定层
local lua_suite = {}
function lua_suite.test_lua_npi_set_get()
    mobile.rfcalReset()
    assert(mobile.rfcalNpiSet("rfCaliDone", 1) == 0)
    assert(mobile.rfcalNpiGet("rfCaliDone") == 1)
    assert(mobile.rfcalNpiSet("rfCaliDone", 0) == 0)
    assert(mobile.rfcalNpiGet("rfCaliDone") == 0)
end
function lua_suite.test_lua_at_dispatch_returns_resp()
    local resp = mobile.rfcalAt("AT")
    assert(type(resp) == "string" and resp:find("OK"), "AT 应返 OK")
end
function lua_suite.test_lua_rfnst_returns_mt()
    local out = mobile.rfcalRfnst("020408000000")
    assert(type(out) == "string" and out:sub(1,2) == "MT", "RFNST 应返 MT 头")
end
function lua_suite.test_lua_imei_inject_visible_in_cgsn()
    mobile.rfcalReset()
    mobile.rfcalSetImei("864317081553409")
    local resp = mobile.rfcalAt("AT+CGSN=1")
    assert(resp:find("864317081553409"), "IMEI 应出现在 CGSN 响应")
end
function lua_suite.test_lua_state_transitions()
    mobile.rfcalReset()
    assert(mobile.rfcalState() == 0)
    mobile.rfcalAt("AT+CGSN=1")
    assert(mobile.rfcalState() >= 1)
    mobile.rfcalAt("AT+ECNPICFG=rfCaliDone,1")
    assert(mobile.rfcalState() == 4)
end

-- AT server 层
local at_suite = {}
function at_suite.test_at_server_dispatch_table()
    local cases = {
        { line = "AT",                          expect = "OK" },
        { line = "ATE0",                        expect = "OK" },
        { line = "AT+CGSN=1",                   expect = "864317081553409" },
        { line = "AT+ECNPICFG=rfCaliDone,0",    expect = "OK" },
        { line = "AT+ECNPICFG=rfCaliDone,1",    expect = "OK" },
        { line = "AT+ECNPICFG=rfNSTDone,1",     expect = "OK" },
        { line = "AT+ECNPICFG?",                expect = "rfCaliDone" },
    }
    mobile.rfcalReset()
    for _, c in ipairs(cases) do
        local resp = mobile.rfcalAt(c.line)
        assert(resp and resp:find(c.expect, 1, true),
            string.format("AT '%s' 应包含 '%s',实际: %s", c.line, c.expect, tostring(resp)))
    end
end
function at_suite.test_at_server_unknown_returns_error()
    local resp = mobile.rfcalAt("AT+BOGUS")
    assert(resp:find("ERROR"), "未知命令应返 ERROR")
end
function at_suite.test_at_server_real_log_replay()
    mobile.rfcalReset()
    local resp = mobile.rfcalAt("AT+CGSN=1")
    assert(resp:find('"864317081553409"'), "真实日志 IMEI 应被回显")
    mobile.rfcalAt("AT+ECNPICFG=rfCaliDone,0")
    mobile.rfcalAt("AT+ECNPICFG=rfCaliDone,1")
    assert(mobile.rfcalNpiGet("rfCaliDone") == 1)
    mobile.rfcalAt("AT+ECNPICFG=rfNSTDone,1")
    assert(mobile.rfcalNpiGet("rfNSTDone") == 1)
end

t.c_suite = c_suite
t.lua_suite = lua_suite
t.at_suite = at_suite
return t
