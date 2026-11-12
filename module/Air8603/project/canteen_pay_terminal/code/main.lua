--[[
@module  main
@summary Air8603 食堂收费终端 · 入口（示例工程，已脱敏）
@usage   Luatools 直接把本目录作为工程下载即可；烧录前按 README §5.0 填 config.lua 占位符
@note    必须定义 PROJECT / VERSION，Luatools 与 FOTA 都会用到
]]

-- ▲【按需 O06】← 就是这两行：改成自己的项目名 / 版本号（Luatools 与 FOTA 会用到）
PROJECT = "CANTEEN_PAY_DEMO"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

-- 芯片内部任务级软件看门狗（9 秒超时，3 秒喂一次）；内部硬件狗由固件自动开启，无需配置
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- ==================== 板载 Air153D 外部硬件看门狗 ====================
-- 8603/8605 板载独立的外部看门狗芯片，喂狗脚 GPIO57 经 NPN 三极管接芯片 WTDOG。
-- 该芯片上电即计时（STRAP 选 10 分钟 / 60 分钟 / 12 小时 / 24 小时），不喂狗会
-- 超时拉 PWR_OFF → 拉低主控 RESET_N → 整机周期性硬件复位（约 10 多分钟一次）。
-- 上面的 wdt.init(9000) 只喂芯片内部软件狗，喂不到这颗外部芯片。
-- 编译系统按 require 的字面文本决定扩展库打包范围，故这里保持字面写法；
-- 烧录时须把仓库公共库 script/libs/exair153x_wdt.lua 加入脚本清单（见 README §1.3）。
-- ▲【按需 O03】换板型时改 config.lua 的 C.hw.ext_wdt_enable / ext_wdt_pin
local CFG = require "config"
if CFG.hw.ext_wdt_enable then
    local function load_exair153x_wdt()
        return require "exair153x_wdt"
    end
    local ok, ext_wdt = pcall(load_exair153x_wdt)
    if ok and type(ext_wdt) == "table" then
        -- init 内部会 gpio.setup 引脚并 sys.taskInit 一个独立自动喂狗任务：
        -- 首次喂狗立即执行，之后默认每 180 秒发一次脉冲，无需另加 sys.timerLoopStart。
        if not ext_wdt.init({ wdt_pin = CFG.hw.ext_wdt_pin }) then
            log.error("main", "external watchdog init failed, Air153D NOT fed")
        end
    else
        -- 库没打进固件时不会中断启动，但设备仍会被外部硬狗周期性复位，故显式报错
        log.error("main", "exair153x_wdt not packed in firmware, Air153D NOT fed")
    end
else
    -- 关闭喂狗只在「板子确实没有外部硬狗」时才安全
    log.warn("main", "external watchdog disabled by config; Air153D will reset the board periodically")
end

-- app.lua 内部起业务主任务：硬件初始化 → UI → 三条业务流程
require "app"

-- sys.run() 之后不要写任何语句，永远不会执行
sys.run()
