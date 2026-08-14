local M = {}

local function assert_ipsec_case(case_name)
    assert(netdrv and type(netdrv.ipsec_utest) == "function", "netdrv.ipsec_utest 不存在")
    local ok = netdrv.ipsec_utest(case_name)
    assert(ok == true, "netdrv.ipsec_utest(" .. tostring(case_name) .. ") 应返回 true")
end

local mschapv2_suite = {}
function mschapv2_suite.test_ipsec_mschapv2_rfc_vectors()
    assert_ipsec_case("mschapv2_rfc_vectors")
end

local ike_suite = {}
function ike_suite.test_ipsec_ike_key_derivation()
    assert_ipsec_case("ike_key_derivation")
end

local esp_suite = {}
function esp_suite.test_ipsec_esp_cbc_roundtrip_replay()
    assert_ipsec_case("esp_cbc_roundtrip_replay")
end

function esp_suite.test_ipsec_esp_gcm_roundtrip_replay()
    assert_ipsec_case("esp_gcm_roundtrip_replay")
end

M.mschapv2_suite = mschapv2_suite
M.ike_suite = ike_suite
M.esp_suite = esp_suite

return M
