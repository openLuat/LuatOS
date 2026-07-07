PROJECT = "memprof_basic"
VERSION = "1.0.0"

local memprof_tests = require("memprof_test")

sys.taskInit(function()
    sys.wait(100)
    local pass, fail = 0, 0
    for k, v in pairs(memprof_tests) do
        if type(k) == "string" and k:sub(1, 5) == "test_" and type(v) == "function" then
            local ok, err = pcall(v)
            if ok then
                log.info("suite", "✓ " .. k .. " passed")
                pass = pass + 1
            else
                log.error("suite", "✗ " .. k .. " failed: " .. tostring(err))
                fail = fail + 1
            end
            sys.wait(10)
        end
    end
    log.info("suite", string.format("Total: %d passed, %d failed", pass, fail))
    if rtos.bsp() == "PC" then
        os.exit(fail == 0 and 0 or 1)
    end
end)

sys.run()
