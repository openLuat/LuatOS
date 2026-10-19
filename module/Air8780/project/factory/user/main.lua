--[[
@module  main
@summary Air878x 系列出厂固件入口（产测 + iRTU 合一，基于标准 iRTU + 预置配置）
@version 2.1.0
@date    2026.10.15
@author  李源龙
@usage
本工程为 Air8780 全系 / Air8781P / 8782P 出厂固件，产测与正常模式合一（V3）：
    1. auto 分流按 fskv → OTP1 顺序：
       fskv 有返工标记 model_retest → require "factory" 进产测模式（返工，不动 OTP1）；
       fskv 无标记且 OTP1 为空 → 进产测模式（首测，通过后型号/硬件版本写入 OTP1）；
       fskv 无标记且 OTP1 有值 → require "irtu_main" 进正常模式（AirCloud 上报/下行）
       正常模式 USB 发 MODEL_RETEST#CONFIRM 写 fskv 返工标记并重启，详见 retest.lua
    2. 正常模式：不允许请求网页端配置，开机直接使用预置 irtu.cfg（默认通道=AirCloud）
    3. 传感器（AirSHT30_1000 温湿度 / AirVOC_1000 空气质量）走 I2C 采集，
       由 sensor_task + factory_app 模块上报结构化 TLV 数据到 AirCloud
    4. 下行控制命令（tag 19）：cycle:秒数 / led:blink|on|off / tts:文本
    5. rrpc 指令（tag 21）：rrpc,getimei 等（原有 iRTU 指令保留）
]]
--[[
必须定义PROJECT和VERSION变量,Luatools工具会用到这两个变量,远程升级功能也会用到这两个变量
PROJECT：项目名,ascii string类型
        可以随便定义,只要不使用,就行
VERSION：项目版本号,ascii string类型
        如果使用合宙iot.openluat.com进行远程升级,必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字,三个X表示的数字可以相同,也可以不同,同理三个Y和三个Z表示的数字也是可以相同,可以不同
            因为历史原因,YYY这三位数字必须存在,但是没有任何用处,可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级,根据自己项目的需求,自定义格式即可
]]
-- LuaTools需要PROJECT和VERSION这两个信息
-- 一份代码生成不同固件：取消下面对应型号 PROJECT 行的注释即可
-- 注意：PROJECT 决定固件名，功能分支由 factory_config.lua 的 DEVICE_VER 决定，两者按下表联动
-- ┌──────────────┬──────────────┬────────────────────────────────────────────┐
-- │ PROJECT      │ DEVICE_VER   │ 功能                                       │
-- ├──────────────┼──────────────┼────────────────────────────────────────────┤
-- │ Air8780P     │ "8780"       │ 基准：硬件I2C + 定时上报 + 串口透传        │
-- │ Air8780H     │ "8780"       │ 同上（基准）                               │
-- │ Air8780S     │ "8780"       │ 同上（基准）                               │
-- │ Air8780U     │ "8780"       │ 同上（基准）                               │
-- │ Air8780N     │ "8780"       │ 同上（基准）                               │
-- │ Air8780V     │ "8780V"      │ 基准 + 每10秒TTS播报"上海合宙欢迎你"       │
-- │ Air8780G     │ "8780G"      │ 基准 + 每30秒GPS上报（失败回退LBS）        │
-- └──────────────┴──────────────┴────────────────────────────────────────────┘
-- PROJECT = "Air8780V"
-- PROJECT = "Air8780P"
-- PROJECT = "Air8780H"
-- PROJECT = "Air8780S"
-- PROJECT = "Air8780U"
PROJECT = "Air8780N"
-- PROJECT = "Air8780G"

VERSION = "001.001.002"

-- 出厂固件版本：预置配置直接连接 AirCloud，不请求网页端配置
-- 此KEY值仅针对合宙官方IOT平台FOTA，如需使用请替换为项目对应KEY
-- 参考 https://docs.openluat.com/air780epm/luatos/app/ota/fota/
PRODUCT_KEY = "w1Nvdeca2nPLhOOEAwtnIoXuqav2hZ0o"

-- ==================== 【调试用】启动模式选择 ====================
-- 可选值：
--   "auto"   自动分流（默认）：fskv 返工标记 → OTP1 判空，命中任一产测条件进产测模式
--   "normal" 强制进入正常模式（跳过检查），调试 AirCloud 上报/下行用，无需先跑产测
--   "factory" 强制进入产测模式，调试产测指令用
-- 注意：强制 "normal" 时若未写号，日志 PROD/PCB 打印为 nil，不影响 iRTU 功能
local BOOT_MODE = "auto"
-- ============================================================

log.info("main", PROJECT, VERSION)

-- 初始化 fskv（V3 返工标记 model_retest 存储）
fskv.init()

-- 打开全局上拉 VREF(GPIO23)：为板载上拉电阻提供参考电压，产测与正常模式全程常开
gpio.setup(23, 1)

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- ====== FOTA 升级：开机即执行（与工作模式无关），之后每8小时自动检测一次 ======
-- 使用 libfota3（只能合宙人员根据客户提供的IMEI升级，客户无法自行操作）
-- update.init() 内部为异步后台执行，不阻塞开机流程
local update = require("update")
update.init()
-- ============================================================

-- ============ 开机模式分发：产测 / 正常（iRTU）合一（V3） ============
-- BOOT_MODE 控制：
--   "normal"  → 强制正常模式（跳过检查，调试用）
--   "factory" → 强制产测模式（跳过检查，调试用）
--   "auto"    → 按 fskv 返工标记 → OTP1 顺序分流（默认）：
--               1) fskv 有返工标记 model_retest → 产测模式（返工产测，全程不动 OTP1）
--               2) fskv 无标记且 OTP1 为空      → 产测模式（首次产测，通过后写号入 OTP1）
--               3) fskv 无标记且 OTP1 有值      → 正常模式
local retest = require("retest")
local RETEST_KEY = retest.KEY
local prodmeta = require("prodmeta")

-- OTP1 是否为空：读取 key=value 表，空表视为裸板未产测
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
    boot_reason = "BOOT_MODE=normal 强制进入正常模式（调试用）"
elseif BOOT_MODE == "factory" then
    boot_to_normal = false
    boot_reason = "BOOT_MODE=factory 强制进入产测模式（调试用）"
else
    -- auto：先查 fskv 返工标记，再查 OTP1
    if fskv.get(RETEST_KEY) then
        boot_to_normal = false
        boot_reason = "fskv 命中返工标记 model_retest，进入产测模式（返工）"
    elseif otp1_empty() then
        boot_to_normal = false
        boot_reason = "fskv 无返工标记且 OTP1 为空，进入产测模式（首次产测）"
    else
        boot_to_normal = true
        boot_reason = "fskv 无返工标记且 OTP1 有值，进入正常模式"
    end
end
log.info("main", boot_reason)

if boot_to_normal then
    -- 打印写入的模组型号和硬件版本（OTP，由产测写号写入）
    log.info("main", "模组型号 PROD:", prodmeta.get("PROD"), "硬件版本 PCB:", prodmeta.get("PCB"))
    -- 加载 iRTU 正常模式（无 RFA 校准流程）
    require "irtu_main"
else
    -- 产测模式：独占 VUART_0，响应产测指令（见 factory.lua 指令表）
    require "factory"
end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
