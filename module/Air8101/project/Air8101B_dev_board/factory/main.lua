--[[
@module  main
@summary Air8101B V3.0 开发板出厂固件入口（产测 + 用户双模合一）
@version 001.999.000
@date    2026.10.15
@usage
上电 → 打印 PROJECT/VERSION → 软狗 → fskv → 模式分流：
  产测模式：只加载产测模块，独占调试串口，不初始化业务外设
  用户模式：上电时序 + 业务模块
分流依据：fskv.test_done（TEST_DONE# 写入，重烧脚本不丢）
BOOT_MODE 可强制：auto（默认）/ factory（强制重测）/ normal（跳过产测调试业务）

关于 user_main 缺失：此时只回落本次运行到产测模式，**不动 test_done**。
产测标记代表"这块板测过"，不能被"脚本没烧全"这种事作废；
补全脚本重烧后，下次上电直接进用户模式，不需要重测。

注意
所有脚本文件平铺在本目录（烧录合并器不支持子目录 require），require 直接用文件名。
]]

PROJECT = "Air8101_Factory"
VERSION = "001.999.001"

-- 强制模式：调试用，出货前保持 "auto"
local BOOT_MODE = "auto"

-- 用户模式入口模块名（仅用于日志；真正的加载见下方 USER_MODULE_REQUIRE）
local USER_MODULE = "user_main"
local USER_MODULE_REQUIRE = function() return require "user_main" end

log.info("main", PROJECT, VERSION)

-- 软狗：先于分流启动，两种模式都受保护
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)

-- 持久化（test_done 等标记）
fskv.init()

local function get_boot_mode()
    if BOOT_MODE == "factory" then return "factory" end
    if BOOT_MODE == "normal"  then return "normal"  end
    if fskv.get("test_done") then return "normal" end
    return "factory"   -- 新板首次上电 → 产测
end

local mode = get_boot_mode()
log.info("main", "boot mode:", mode)

local platform = require "platform_loader"
platform.load()

local board = require "board_init"

if mode == "factory" then
    -- 产测模式：上电时序 → 产测主控（不加载任何业务模块）
    sys.taskInit(function()
        board.power_on()
        require "factory"
    end)
else
    -- 用户模式：上电时序 → 业务模块
    sys.taskInit(function()
        board.power_on()
        local loaded, err = pcall(USER_MODULE_REQUIRE)
        if not loaded then
            log.error("main", "用户模块加载失败，本次回落产测模式（test_done 标记保留）:", tostring(err))
            log.error("main", "请检查脚本是否烧全，缺少:", USER_MODULE .. ".lua")
            require "factory"
        end
    end)
end

sys.run()
