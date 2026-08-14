--[[
@module  wdt_app
@summary 短信测试用例
@version 1.0
@date    2026.08.06
@author  王城钧
]]

-- 引入看门狗扩展库
local exair153x_wdt = require("exair153x_wdt")

-- 看门狗任务
local function wdt_task()
    -- 初始化看门狗，使用 GPIO24 喂狗引脚
    -- 默认参数：脉冲宽度 200ms，自动喂狗周期 180s
    local success = exair153x_wdt.init({
        wdt_pin = 23,          -- 连接 WTDOG 的 GPIO 引脚号
    })

    -- 初始化失败则退出
    if not success then
        log.error("main", "看门狗初始化失败")
        return
    end

    log.info("main", "看门狗初始化成功，自动喂狗已启动")
    log.info("main", "当前版本: " .. exair153x_wdt.version())

    -- 演示：等待 30 秒后手动补喂狗
    sys.wait(30000)
    log.info("main", "执行手动补喂狗")
    exair153x_wdt.feed()

    -- 业务主循环
    while true do
        log.info("main", "正常运行中...")
        sys.wait(60000)
    end
end

-- 启动看门狗任务
sys.taskInit(wdt_task)