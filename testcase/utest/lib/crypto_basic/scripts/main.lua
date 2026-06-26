PROJECT = "crypto_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local crypto_test = require("crypto_test")

sys.taskInit(function()
    testrunner.runBatch("crypto_basic", {
        { testTable = crypto_test.cjson_suite, testcase = "C层utest-cjson(简单)" },
        { testTable = crypto_test.rsa_suite, testcase = "C层utest-rsa(中等)" },
        { testTable = crypto_test.gmssl_suite, testcase = "C层utest-gmssl(复杂)" }
    })
end)

sys.run()
