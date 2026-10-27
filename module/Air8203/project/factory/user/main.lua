--[[
@module  main
@summary Air8203V 出厂固件入口（产测 + iRTU 合一，V3 机制，默认开启外置 Air510w GNSS）
@version 1.0.0
@date    2026.10.23
@usage
启动顺序：
1. fskv 初始化 + GPIO23 VREF 常开（SIM上拉+gsensor供电+GNSS备电）+ 软狗 9s
2. FOTA：update.init() 开机检测 + 每 8 小时（libfota3）
3. Air5101 蓝牙看门狗喂狗任务（产测/正常两模式共用，60s 超时 BLE 拉高 SWITCH 复位主控）
4. V3 四段分流（BOOT_MODE=auto 默认）：
   1) fskv model_retest   → 产测模式（返工，全程不动 OTP1，TEST_DONE 删标记）
   2) fskv model_firsttest→ 产测模式（裸板首测中途复位后回到产测）
   3) OTP1 为空           → 产测模式（首次产测，进产测前自动写 firsttest，重试3次失败不堵产线）
   4) OTP1 有值           → 正常模式（AirCloud 上报，默认开机即开外置 510w GNSS）
]]

-- LuaTools 需要 PROJECT 和 VERSION 这两个信息
PROJECT = "Air8203V"
VERSION = "001.001.000"

-- 此 KEY 仅针对合宙官方 IOT 平台 FOTA，如需使用请替换为项目对应 KEY
-- 参考 https://docs.openluat.com/air780epm/luatos/app/ota/fota/
PRODUCT_KEY = "0LkZx9Kn3tOhtW7uod48xhilVNrVsScV"

-- ==================== 【调试用】启动模式选择 ====================
--   "auto"    自动分流（默认）：fskv 返工标记 → 首测标记 → OTP1 判空
--   "normal"  强制正常模式（跳过检查），调试 AirCloud 上报/下行用
--   "factory" 强制产测模式（跳过检查），调试产测指令用
local BOOT_MODE = "auto"
-- ============================================================

log.info("main", PROJECT, VERSION)

-- 初始化 fskv（V3 双标记 model_retest / model_firsttest 存储）
fskv.init()

-- VREF(GPIO23) 常开：SIM 上拉 + gsensor 供电 + GNSS 备电，飞行模式才拉低
gpio.setup(23, 1)

-- 软狗防止程序卡死：9s 超时，3s 喂一次
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- ====== FOTA：开机即检测（与工作模式无关），之后每 8 小时自动检测 ======
-- update 内部硬 require "libfota3"（仅"添加默认lib"提供）。一旦缺库，
-- 硬 require("update") 会在开机此处报错终止 → 后面 GNSS 永不执行（"一条GNSS日志都没有"最靠前根因）。
-- 故 pcall 软加载：缺 libfota3 时仅跳过 FOTA，绝不阻断开机 GNSS。
do
    local ok_up, update = pcall(require, "update")
    if ok_up and update then
        update.init()
    else
        log.error("main", "update/libfota3 未打进固件，跳过FOTA，不影响GNSS")
    end
end
-- ====================================================================

-- ============================================================
-- Air5101 蓝牙硬件看门狗（产测 + 正常两模式共用，必须在模式分发前启动）
--   60s 不喂狗 → BLE 拉高 SWITCH 100ms 复位主控；30s 喂一次
--   底层走官方扩展库 exril_5101（UART1/9600 独占，AT/看门狗由库封装）
--   ble_wdt_config 设为全局：factory.lua 的 BLERESTART/TEST_DONE/FLYMODE 也要调
-- ============================================================
-- exril_5101 同样仅"添加默认lib"提供。pcall 软加载，缺库时跳过蓝牙看门狗，绝不阻断 GNSS。
local ok_exril, exril_5101 = pcall(require, "exril_5101")
if not ok_exril then
    exril_5101 = nil
    log.error("main", "exril_5101 未打进固件，跳过蓝牙看门狗，不影响GNSS")
end

local BLE_WDT_TIMEOUT_S = 60     -- 看门狗超时(秒)
local BLE_WDT_LEVEL = 1          -- 超时 SWITCH 电平：1=拉高复位主控
local BLE_WDT_WIDTH = 100        -- SWITCH 脉宽(ms)
local BLE_WDT_FEED_MS = 30000    -- 喂狗间隔(ms)，必须 < 超时

function ble_wdt_config(enable)
    if not exril_5101 then
        log.warn("BLE_WDT", "exril_5101 不可用，看门狗操作跳过")
        return false
    end
    if enable == false then
        local ok, msg = exril_5101.wdt.close()
        log.info("BLE_WDT", "看门狗关闭:", ok, msg)
        return ok
    end
    local ok, msg = exril_5101.wdt.init(BLE_WDT_TIMEOUT_S, BLE_WDT_LEVEL, BLE_WDT_WIDTH)
    if not ok then
        log.error("BLE_WDT", "看门狗配置失败:", msg)
        return false
    end
    -- 回读校验（AT+WDCFG?），确认参数真生效
    local sok, st = exril_5101.wdt.status()
    if sok and type(st) == "table" then
        log.info("BLE_WDT", string.format("已使能并回读: en=%s timeout=%ss level=%s width=%sms",
            tostring(st.en), tostring(st.timeout), tostring(st.level), tostring(st.width)))
    else
        log.warn("BLE_WDT", "看门狗已配置, 但回读失败")
    end
    return true
end

sys.taskInit(function()
    if not exril_5101 then return end   -- 库不可用，不启动喂狗任务
    sys.wait(500) -- 等 Air5101 上电稳定
    local ok, msg = exril_5101.mode(exril_5101.MODE_AT, 3000)
    if not ok then
        log.error("BLE_WDT", "进入 AT 模式失败:", msg)
    end
    ble_wdt_config(true)
    -- 主控重启期间 BLE 不断电，其看门狗可能早已在跑，配完立即喂第一次
    exril_5101.wdt.feed()
    while true do
        sys.wait(BLE_WDT_FEED_MS)
        local fed, fmsg = exril_5101.wdt.feed()
        if not fed then
            -- 连续失败超过 60s 主控会被 BLE 复位，必须打出来追
            log.error("BLE_WDT", "喂狗失败:", fmsg)
        end
    end
end)

-- ============ V3 开机模式分发：产测 / 正常（iRTU）合一 ============
local retest = require("retest")
local prodmeta = require("prodmeta")

-- OTP1 是否为空：读 key=value 表，空表视为裸板未产测
local function otp1_empty()
    local ok, all = pcall(prodmeta.get_all)
    if not ok or type(all) ~= "table" then
        log.error("main", "OTP1 读取失败，按未产测处理")
        return true
    end
    return next(all) == nil
end

local boot_to_normal = false
local boot_reason = ""
if BOOT_MODE == "normal" then
    boot_to_normal = true
    boot_reason = "BOOT_MODE=normal 强制正常模式（调试用）"
elseif BOOT_MODE == "factory" then
    boot_to_normal = false
    boot_reason = "BOOT_MODE=factory 强制产测模式（调试用）"
else
    -- auto：fskv 返工标记 → 首测进行中标记 → OTP1 判空
    if retest.is_set() then
        boot_to_normal = false
        boot_reason = "fskv 命中 model_retest，进入产测模式（返工，不动 OTP1）"
    elseif retest.first_is_set() then
        boot_to_normal = false
        boot_reason = "fskv 命中 model_firsttest，回到产测模式（首测中途曾复位）"
    elseif otp1_empty() then
        -- 裸板首测：写 model_firsttest 保护标记（读回校验，重试 3 次）
        local marked = false
        for i = 1, 3 do
            if retest.first_set() then
                marked = true
                break
            end
            log.error("main", "首测标记写入失败，重试", i)
        end
        if marked then
            log.info("main", "裸板首测，model_firsttest 已写入")
        else
            -- 不堵产线：放行，仅告警（此板中途复位无保护，需人工关注）
            log.error("main", "警告：model_firsttest 3 次均失败，首测中途无复位保护")
        end
        boot_to_normal = false
        boot_reason = "OTP1 为空，进入产测模式（首次产测）"
    else
        boot_to_normal = true
        boot_reason = "OTP1 有值，进入正常模式"
    end
end
log.info("main", boot_reason)

if boot_to_normal then
    log.info("main", "模组型号 PROD:", prodmeta.get("PROD"), "硬件版本 PCB:", prodmeta.get("PCB"))
    -- UART1 被 Air5101 蓝牙(9600)独占、UART2 被 Air510w GNSS(115200)独占，
    -- iRTU 不得再初始化这两路（driver.init 内据此跳过），避免数据回调抢占
    _G.IRTU_DISABLE_UART1 = true
    _G.IRTU_DISABLE_UART2 = true
    -- 先加载业务模块：开机 GNSS 自检/启动在此完成（start_default_gps 已 sys.taskInit 排队）。
    require "factory_app"
    -- irtu_main → default/driver/create，而 create 第16-20行【硬】require libnet/dtulib/excloud/lbsLoc2，
    -- 这些库工程 lib/ 内均无副本、全靠"添加默认lib"。一旦漏勾，硬 require 在此抛错 →
    -- 主 chunk 到不了 sys.run() → 上面已排队的 GNSS 自检 task 永不执行（"一条GNSS日志都没有"的最后堵点）。
    -- 故 pcall 软加载：网络链缺库只影响 AirCloud，绝不影响开机 GNSS（factory_app 经 gnss_volgpio=25 控制 UART2/供电）。
    local ok_im, irtu_main = pcall(require, "irtu_main")
    if not ok_im then
        log.error("main", "irtu_main 链(libnet/dtulib/excloud/lbsLoc2)缺库，跳过网络通道，不影响GNSS")
    end
else
    require "factory"
end

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
