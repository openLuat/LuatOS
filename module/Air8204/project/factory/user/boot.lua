--[[
@module  boot
@summary 启动初始化与产测 / 出货分流
@version 1.0
@date    2026.09.28
@usage
由 main.lua 在 sys.run() 之前 require，完成以下工作：
  1. fskv.init()：初始化 KV 存储（产测标记 test_done 存储）
  2. gpio.setup(23, 1)：拉高 VREF，为板载上拉电阻提供参考电压，产测与出货全程常开
  3. wdt.init(9000) + 3s 喂狗：软狗防程序卡死（产测与出货统一启用）
  4. update.init()：libfota3 整机成品 FOTA，开机检测一次 + 每 8 小时循环（异步，不阻塞开机）
  5. 按 BOOT_MODE 与 fskv.get("test_done") 分流：
       - 出货：打印 OTP 中的 PROD / PCB，require "card_main"
       - 产测：require "factory"（独占 USB 虚拟串口 VUART_0）

BOOT_MODE 调试开关：
  "auto"    按产测标记自动分流（默认）
  "normal"  强制进入出货模式（调试用，无需先跑产测）
  "factory" 强制进入产测模式（调试用）
]]

local boot = {}

-- ==================== 【调试用】启动模式选择 ====================
-- "auto" 按产测标记自动分流 / "normal" 强制出货 / "factory" 强制产测
local BOOT_MODE = "auto"
-- ==============================================================

log.info("boot", _G.PROJECT, _G.VERSION)

-- 1. 初始化 fskv（产测标记 test_done 存储）
fskv.init()

-- 2. 打开全局上拉 VREF(GPIO23)：为板载上拉电阻提供参考电压，产测与出货全程常开
gpio.setup(23, 1)

-- 3. 软狗：Air8204 无外部看门狗，使用模组内部 wdt，9s 超时 / 3s 喂狗
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 4. FOTA：开机即执行，与工作模式无关（内部为异步后台执行，不阻塞开机流程）
local update = require "update"
update.init()

-- 5. 产测 / 出货分流
local boot_to_normal = false
if BOOT_MODE == "normal" then
    boot_to_normal = true
    log.info("boot", "BOOT_MODE=normal，强制进入出货模式（调试用）")
elseif BOOT_MODE == "factory" then
    boot_to_normal = false
    log.info("boot", "BOOT_MODE=factory，强制进入产测模式（调试用）")
else
    boot_to_normal = fskv.get("test_done") and true or false
end

if boot_to_normal then
    -- 出货模式：打印产测写入的工业模组型号(PROD)与硬件版本(PCB)（OTP，重刷固件不丢）
    -- 注意：变量名用 prodmeta，不用 pm（LuatOS 有 pm 电源管理库，易混淆）
    local prodmeta = require "prodmeta"
    log.info("boot", "已完成产测，进入出货模式")
    log.info("boot", "模组型号 PROD:", prodmeta.get("PROD"), "硬件版本 PCB:", prodmeta.get("PCB"))
    require "card_main"
else
    log.info("boot", "未完成产测，进入产测模式（USB 虚拟串口 VUART_0）")
    require "factory"
end

return boot
