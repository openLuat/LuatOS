--[[
@module  main
@summary Air780EGH/EGP/EGG 出厂固件入口（内置GNSS，固定单一硬件配置，开机直接进入 iRTU 正常模式）
@version 2.1.0
@date    2026.10.14
@author   李源龙
@usage
本工程为 Air780EGH / Air780EGP / Air780EGG 核心板出厂固件，已移除产测模式与 RFA 校准逻辑，开机即进入正常模式：
    1. 不请求网页端配置，开机直接使用预置 irtu.cfg（默认通道=AirCloud）
    2. 开机即打开模组【内置 GNSS】（固定 UART2/115200），每 30 秒上报一次定位，
       GNSS 无定位时回退 LBS 基站定位；不采集 I2C 传感器
    3. 内置 GNSS 独占 UART2：本文件顶部置 _G.IRTU_DISABLE_UART2=true，禁止 iRTU 初始化 UART2
    4. 下行控制命令（tag 19）：cycle:秒数 / led:blink|on|off
    5. rrpc 指令（tag 21）：rrpc,getimei 等（原有 iRTU 指令保留）
    6. 固定配置，无外置看门狗 / 无音频 codec（仅内核软狗 wdt）
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
PROJECT = "Air780EGHFactory"
VERSION = "001.001.000"

-- 出厂固件版本：预置配置直接连接 AirCloud，不请求网页端配置
-- 此KEY值仅针对合宙官方IOT平台FOTA，如需使用请替换为项目对应KEY
-- 参考 https://docs.openluat.com/air780egh/luatos/app/ota/fota/
PRODUCT_KEY = "w1Nvdeca2nPLhOOEAwtnIoXuqav2hZ0o"

-- ==================== 内置 GNSS 独占 UART2 ====================
-- Air780EGH/EGP/EGG 内置 GNSS 固定挂 UART2(115200)，由 factory_app 内 exgnss 常开。
-- 必须在任何 iRTU 代码（driver.lua uart_INIT(2)）执行前置位，禁止 iRTU 抢占 UART2。
_G.IRTU_DISABLE_UART2 = true

log.info("main", PROJECT, VERSION)

-- 初始化 fskv（上报周期 report_cycle / airlbs 配置持久化）
fskv.init()

-- 打开全局上拉 VREF(GPIO23)：为板载上拉电阻提供参考电压，全程常开
gpio.setup(23, 1)

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- ====== FOTA 升级：开机即执行，之后每8小时自动检测一次 ======
-- 使用 libfota3（只能合宙人员根据客户提供的IMEI升级，客户无法自行操作）
-- update.init() 内部为异步后台执行，不阻塞开机流程
local update = require("update")
update.init()
-- ============================================================

-- ============ 开机直接加载 iRTU 正常模式（AirCloud 上报 / 内置GNSS / 串口透传） ============
log.info("main", "加载 iRTU 正常模式")
require "irtu_main"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
