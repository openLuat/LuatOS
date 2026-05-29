PROJECT = "c_utest_crypto_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local c_utest_crypto_test = require("c_utest_crypto_test")

sys.taskInit(function()
    testrunner.runBatch("c_utest_crypto_basic", {
        { testTable = c_utest_crypto_test.cjson_suite, testcase = "C层utest-cjson(简单)" },
        { testTable = c_utest_crypto_test.rsa_suite, testcase = "C层utest-rsa(中等)" },
        { testTable = c_utest_crypto_test.gmssl_suite, testcase = "C层utest-gmssl(复杂)" }
    })
end)

sys.run()
