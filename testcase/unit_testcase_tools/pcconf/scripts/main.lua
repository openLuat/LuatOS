PROJECT = "pcconftest"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

local pcconf_tests = require("pcconf_test")

local expected_network_enabled = tonumber(os.getenv("PCCONF_EXPECT_NETWORK_ENABLED") or "")

if expected_network_enabled == 0 then
    sys.taskInit(function()
        pcconf_tests.test_network_toggle_runtime()
        os.exit(0)
    end)
else
    local testrunner = require("testrunner")
    sys.taskInit(function()
        testrunner.runBatch("pcconf_suite", {
            { testTable = pcconf_tests, testcase = "pcconf.json 结构与迁移测试" }
        })
    end)
end

sys.run()
