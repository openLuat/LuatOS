--[[
@module  main
@summary Air8000 系列 iRTU 正常固件入口（基于标准 iRTU + 预置配置，直连 AirCloud）
@version 2.0.0
@date    2026.10.21
@usage
本工程为 Air8000 全系（Air8000/A/W/G/T/U/N/GU/GN/XB/DB）正常固件：
    1. 开机直接进入 iRTU 正常模式，使用预置 irtu.cfg（默认通道=AirCloud），不请求网页端配置
    2. 多网卡：由 netdrv_device 按 factory_config.get_netdev() 四选一接入
       （4G=socket.LWIP_GP / WiFi=LWIP_STA / SPI外挂CH390H=LWIP_ETH / 多网优先级）
    3. 传感器（AirSHT30_1000 温湿度 / AirVOC_1000 空气质量）走硬件I2C0采集，
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
-- 机型切换：取消下面对应行的注释、注释掉当前行即可（PROJECT仅作工程名/升级标识，不决定硬件型号）
PROJECT = "Air8000A"   -- 当前启用：Air8000A
-- PROJECT = "Air8000"
-- PROJECT = "Air8000W"
-- PROJECT = "Air8000G"
-- PROJECT = "Air8000T"
-- PROJECT = "Air8000U"
-- PROJECT = "Air8000N"
-- PROJECT = "Air8000GU"
-- PROJECT = "Air8000GN"
-- PROJECT = "Air8000XB"
-- PROJECT = "Air8000DB"
VERSION = "001.001.000"

-- 预置配置直接连接 AirCloud，不请求网页端配置
-- 此KEY值仅针对合宙官方IOT平台FOTA，如需使用请替换为项目对应KEY
-- 参考 https://docs.openluat.com/Air8000/luatos/app/ota/fota/
PRODUCT_KEY = "SIsRml1ImTsP6XR4lvRAQVuksbZZuUpO"

log.info("main", PROJECT, VERSION)

-- 注意：Air8780 的 GPIO23 是全局上拉 VREF 使能脚；Air8000 的 pin23=GPIO20（普通IO），无 VREF 概念，
-- 因此此处【不】照搬 gpio.setup(23,1)，避免误把 GPIO20 拉高。

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

-- ============ 直接进入 iRTU 正常模式 ============
require "irtu_main"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
