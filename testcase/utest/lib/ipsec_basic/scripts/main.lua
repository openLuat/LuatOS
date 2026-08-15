PROJECT = "ipsec_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local ipsec_test = require("ipsec_test")

sys.taskInit(function()
    testrunner.runBatch("ipsec_basic", {
        { testTable = ipsec_test.mschapv2_suite, testcase = "C层utest-ipsec-mschapv2" },
        { testTable = ipsec_test.ike_suite, testcase = "C层utest-ipsec-ike-keymat" },
        { testTable = ipsec_test.esp_suite, testcase = "C层utest-ipsec-esp-roundtrip" },
    })
end)

sys.run()
