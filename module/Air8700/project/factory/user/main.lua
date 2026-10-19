--[[
@module  main
@summary Air8700P 出厂固件入口（产测 + iRTU 合一 V3，基于标准 iRTU + 预置配置）
@version 2.0.0
@date    2026.10.16
@author   李源龙
@usage
本工程为 Air8700P 工业模组出厂固件（板载 Air700ECP，与 Air780EPM 同固件系列），产测与正常模式合一（V3）：
    1. auto 分流按 fskv → OTP1 顺序：
       fskv 有返工标记 model_retest → require "factory" 进产测模式（返工，不动 OTP1）；
       fskv 无标记且 OTP1 为空 → 进产测模式（首测，通过后型号/硬件版本写入 OTP1）；
       fskv 无标记且 OTP1 有值 → require "irtu_main" 进正常模式（AirCloud 上报/下行）
       正常模式 USB 发 MODEL_RETEST#CONFIRM 写 fskv 返工标记并重启，详见 retest.lua
    2. 正常模式：不允许请求网页端配置，开机直接使用预置 irtu.cfg（默认通道=AirCloud）
    3. 定位：仅串口透传 + AirCloud 基础心跳上报（IMEI/CSQ/CPU温度）
    4. 下行控制命令（tag 19）：cycle:秒数 / led:blink|on|off
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
PROJECT = "Air8700P"
--8700H
-- PROJECT = "Air8700H"

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

-- ==================== 【调试用】RFA 校准模式开关 ====================
-- 可选值：
--   false 默认：跳过 RFA 校准流程，开机直接进入 iRTU（UART1 不被 RFA 占用，调试串口透传用）
--   true        启动 RFA AT 服务器（同时绑定 VUART_0 和 UART1），
--               rfa_mode 为 true 时 UART1 由 RFA 独占
-- 注意：量产固件应设为 true；false 时跳过 ecnpicfg 校准检查
local RFA_ENABLE = false
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

    local rfa = require("rfa")

    if RFA_ENABLE and rfa and atc then
        -- 启动 RFA AT 服务器，同时绑定 USB 虚拟串口 VUART_0 和 UART1，两个端口都能响应 RFA AT 指令
        -- 波特率对虚拟串口无实际意义，但保持 115200 与产线工具一致
        rfa.start(uart.VUART_0, 115200)
        rfa.start(1, 115200)
        sys.taskInit(function()
            local passed, status = mobile.ecnpicfg()
            if passed then
                -- 校准已完成: 允许加载irtu脚本, 再通过 AT+SETCFG? 查询是否处于rfa模式
                -- 只有 rfa_mode 明确为(false)才退出rfa模式, VUART_0归irtu, 正常处理irtu数据
                -- 读不到配置或rfa_mode为(true): 处于rfa模式, VUART_0归rfa的AT服务器, 禁用irtu的VUART_0数据回调
                local rfa_mode = rfa.getRFAOnStatus()
                log.info("main", "rfa_mode", rfa_mode)
                if rfa_mode then
                    log.info("main", "当前处于rfa模式, 禁用irtu的VUART_0和UART1数据回调")
                    -- 置位全局标志, 通知irtu的driver不要注册VUART_0和UART1的数据回调
                    _G.IRTU_DISABLE_VUART = true
                    _G.IRTU_DISABLE_UART1 = true
                    -- 内置 GNSS 的型号在 RFA 模式下由 GPS 测试指令独占 UART2。
                    local model = hmeta.model()
                    if model == "Air8000" or model == "Air8000A" or model == "Air8000G" or model == "Air8000D" or model == "Air8000U" or model == "Air8000N"
                        or model == "Air780EGH" or model == "Air780EGP" or model == "Air780EGG" then
                        _G.IRTU_DISABLE_UART2 = true
                    end
                else
                    log.info("main", "已退出rfa模式, 进入iRTU模式")
                    rfa.close()
                end
                -- 校准完成后无论是否退出rfa模式都加载irtu_main模块
                require "irtu_main"
            else
                -- 校准未完成: 禁止require irtu代码, VUART_0只响应rfa的校准指令
                log.info("main", "RFA校准查询超时或未完成，进入RFA校准模式，禁止加载irtu")
            end
        end)
    else
        if not RFA_ENABLE then
            log.info("main", "RFA_ENABLE=false 跳过RFA，直接进入iRTU模式")
        else
            log.info("main", "rfa模块未加载，默认iRTU模式")
        end
        --加载irtu_main模块
        require "irtu_main"
    end
else
    -- 产测模式：独占 VUART_0，响应产测指令（见 factory.lua 指令表）
    require "factory"
end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
