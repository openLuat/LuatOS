-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "g729_quality_test"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

-- 独立质量度量脚本: 不走testrunner, 直接在sys任务里顺序执行所有 test_* 用例, 设备/PC通用

-- 真机契约: 长用例必须有WDT喂狗任务, 否则长用例(>10秒)会被看门狗重启
if wdt and wdt.init then
    wdt.init(9000)
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            if wdt.feed then wdt.feed() end
        end
    end)
end

sys.taskInit(function()
    sys.wait(5000)  -- 等系统初始化稳定
    local g729_quality_test = require("g729_quality_test")

    local cases = {}
    for k, v in pairs(g729_quality_test) do
        if type(k) == "string" and k:sub(1, 5) == "test_" and type(v) == "function" then
            cases[#cases + 1] = k
        end
    end
    table.sort(cases)

    local pass, fail = 0, 0
    for _, name in ipairs(cases) do
        log.info("g729_qual", "===== RUN " .. name .. " =====")
        local ok, err = pcall(g729_quality_test[name])
        if ok then
            pass = pass + 1
            log.info("g729_qual", "===== PASS " .. name .. " =====")
        else
            fail = fail + 1
            log.error("g729_qual", "===== FAIL " .. name .. " =====", err)
        end
        sys.wait(100)
    end
    log.info("g729_qual", string.format("G729_QUALITY_DONE pass=%d fail=%d", pass, fail))
    -- PC模拟器测完直接退出; 真机保持运行便于查看日志
    if rtos.bsp() == "PC" then
        os.exit(fail == 0 and 0 or 1)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
