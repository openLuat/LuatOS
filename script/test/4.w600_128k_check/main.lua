
--local sys = require("sys")

local pre = [[
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
    1234567890
]]

local count = 0
--sys.taskInit(
function t()
    while count < 1000000 do
        local tab = {os.date(), pre, tostring(count)}
        --log.info("main", table.concat(tab))
        local data = table.concat(tab)
        log.info("main", data)
        count = count + 1
        --utest.w600_mem_check()
        --sys.wait(100)
        timer.mdelay(1)
        --collectgarbage()
    end
    print("PASS")
end
--)

err, result, any, any2 = pcall(t)
print(err, result, any, any2)

--sys.run()
