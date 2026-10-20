--[[
@module  main
@summary Air8784 出厂固件主入口（产测 + SIP 业务 + CC 业务合一）
@version 1.5
@date    2026.10.17
@author  王世豪
@usage
本工程为 Air8784 出厂固件（外挂 Air1103 语音芯片的 SIP 通话产品），
产测 + 业务两阶段合一：
    1. 启动分流(fskv 返工标记 -> OTP1 出厂产测信息)：
       有返工标记            → 产测模式(返工产测)（USB VUART_0，指令以 # 结尾）
       无标记 且 OTP1 为空   → 产测模式(首次产测)
       无标记 且 OTP1 有值   → 正常模式(require "task_main")
       （调试可用常量 BOOT_MODE 强制 auto / normal / factory）
    2. 业务模式：沿用 sip_aircloud_setting 的网页任务逻辑（task_cloud 经 AirCloud
       Tag19/20 收发 air8784.sip.v1 指令），SIP 与 SIP_CC 由 fskv 中 sip_task_v1 的任务
       类型决定（pair/round 走单 SIP，phone 走 SIP_CC 桥接），不再使用本地产测预设参数
    3. FOTA：首次烧录即执行 libfota3 升级检测，之后每 8 小时自动检测；仅合宙可据 IMEI 推送
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
PROJECT = "Air8784_Factory"
VERSION = "001.000.005"

-- 出厂固件版本：业务模式由 AirCloud 网页任务下发配置（task_cloud，Tag19/20）
-- 此KEY值仅针对合宙官方IOT平台FOTA(libfota3)，如需使用请替换为项目对应KEY
-- 参考 https://docs.openluat.com/air780epm/luatos/app/ota/fota/
PRODUCT_KEY = "AVbrqZ5tldhyJV8oXqLqa2jPmTey2zMg"

-- ==================== 【调试用】启动模式选择 ====================
-- 可选值：
--   "auto"    按产测标记自动分流（出厂默认）：未产测 → 产测模式；已产测 → 业务模式
--   "normal"  强制进业务模式（跳过产测检查），调试 SIP / AirCloud 用，无需先跑产测
--   "factory" 强制进产测模式，调试产测指令用
-- 注意：强制 "normal" 时若未写号，日志 PROD/PCB 打印为 nil，不影响业务功能
local BOOT_MODE = "auto"
-- ============================================================

log.info("main", PROJECT, VERSION)

-- 初始化 fskv（返工标记等键值存储）
fskv.init()

-- 打开全局上拉 VREF(GPIO23)：按键与外设上拉依赖此参考电压，产测与业务模式全程常开
gpio.setup(23, 1)

-- SIM 卡自适应：双卡自动切换，优先使用 SIM0
mobile.simid(2, true)

-- 硬狗防止程序卡死
if wdt then
    wdt.init(9000)                              -- 9 秒超时
    sys.timerLoopStart(wdt.feed, 3000)          -- 3 秒喂一次
end

-- ====== FOTA 升级：开机即执行（与工作模式无关），之后每8小时自动检测一次 ======
-- 使用 libfota3（只能合宙人员根据客户提供的IMEI升级，客户无法自行操作）
-- update.init() 内部为异步后台执行，不阻塞开机流程
local update = require("update")
update.init()
-- ============================================================

-- ==================== 开机模式分发 ====================
-- 分流顺序：fskv 返工标记 -> OTP1(型号/硬件版本/IMEI)
--   有返工标记          -> 产测模式(返工产测)
--   无标记且 OTP1 为空   -> 产测模式(首次产测)
--   无标记且 OTP1 有值   -> 正常模式(业务)
-- 业务分支由 task_main 内的 task_runtime 按 fskv["sip_task_v1"] 选择单 SIP / SIP_CC
local prodmeta = require("prodmeta")
local retest = require("retest")

-- OTP1 是否有出厂产测信息(以型号 PROD 为准)
local function otp_ready()
    local prod = prodmeta.get("PROD")
    return prod ~= nil and prod ~= ""
end

local function decide_mode()
    if BOOT_MODE == "factory" then return "factory" end
    if BOOT_MODE == "normal" then return "business" end
    -- auto
    if retest.is_rework() then return "factory" end
    if not otp_ready() then return "factory" end
    return "business"
end

local mode = decide_mode()

-- 当前模式标记（factory / business），供日志与后续扩展使用
_G.WORK_MODE = mode

if mode == "factory" then
    log.info("main", "进入产测模式(USB 单通道)")
    require "factory"
else
    log.info("main", "模组型号 PROD:", prodmeta.get("PROD"), "硬件版本 PCB:", prodmeta.get("PCB"))
    -- SIP + Air1103 依赖原生 crypto.checksum，缺失会在音频初始化阶段才报错，这里提前拦
    assert(crypto and type(crypto.checksum) == "function", "Native crypto.checksum is required for Air1103")

    -- 正常模式仅注册 MODEL_RETEST 一条 USB 指令：返工时写标记并重启进入产测
    retest.init_normal()

    -- 业务模式：统一加载网页任务业务，SIP/CC 由任务类型决定
    -- FOTA(libfota3) 已在开机阶段 update.init() 启动，此处不再处理
    log.info("main", "进入业务模式:网页任务(SIP/CC 由 sip_task_v1 决定)")
    require "task_main"
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run() 之后不要添加任何语句!!!!!
