--[[
@module  main
@summary Air1780HV V1.4 开发板默认出厂固件入口（正常模式 + 产测模式）
@version 1.0.0
@date    2026.10.20
@usage
本工程为 Air1780HV V1.4 开发板的默认出厂固件，按 V3 出厂流程开机分流：

启动流程（V3）：
  1. fskv 中存在 retest_flag        → 进入产测模式（返工产测）
  2. OTP1 为空（未写过任何 prodmeta）→ 进入产测模式（首次产测）
  3. 其他情况                        → 进入正常模式

产测模式（prod_test）：
  - 独占 USB 虚拟串口 uart.VUART_0（115200 8N1），不加载 LCD/按键/业务/UI
  - 指令表见 prod_test.lua，写号写入 OTP1（PROD/PCB）
  - Air1780HV 无 4G，IMEI/IMSI/ICCID/CSQ/ECNPICFG 指令固定回 ERROR#

正常模式：
  - 以太网联网（netdrv_eth_spi，SPI 外挂 CH390H）
  - VOC 空气质量 + 485温湿度采集，AirCloud 定时上报
  - 云端下行命令：cycle:秒数（改上报频率）/ led:blink|on|off
  - 竖屏 320×480 LCD（AirLCD_1000，ST7796）单页信息展示，界面由 AirUI 绘制
  - 加载 prod_retest，仅响应返工指令 MODEL_RETEST,CONFIRM#
  - 无 iRTU / 无 web / 无外置看门狗（仅内核软狗 wdt）

硬件配置（Air1780HV V1.4 开发板 + AirLCD_1000）：
  - 主控: Air1780HV（Air780EHV 去 4G 版本，Flash 8MB / RAM 8MB，管脚兼容）
  - 网络: CH390H 以太网，SPI0，供电使能 GPIO20，片选 GPIO8，DHCP
  - LCD: ST7796，320×480 竖屏，lcd.HWID_0，pin_rst=36，GPIO29 控 LCD 电源 + GPIO30 控背光
  - 输入: BOOT 键(GPIO0) + PWR 键(gpio.PWR_KEY)，无触摸
  - 传感器: VOC AGS02MA(0x1A)（硬件 I2C1）+ 485温湿度（Modbus RTU，UART1/GPIO24）
  - LED: GPIO27
]]

--[[
必须定义 PROJECT 和 VERSION 变量，Luatools 工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string 类型
VERSION：项目版本号，使用合宙 iot.openluat.com 远程升级需按 "XXX.YYY.ZZZ" 三段格式定义
]]
PROJECT = "Air1780HV_DevBoard_V1.4"
VERSION = "001.999.000"

-- AirCloud 云平台鉴权密钥（FOTA/设备绑定共用）
PROJECT_KEY = "71EgPqWiZRDtzlzdZksXK1o336ds9LzY"

log.info("main", PROJECT, VERSION)

-- 硬件环境：固定 Air1780HV V1.4 开发板（板级引脚与 Air780EHV 兼容：
-- lcd_drv 用 GPIO29 控 LCD 电源、GPIO30 控背光；485 方向脚 GPIO24）
HARDWARE_ENV = "DEV_BOARD_780_V1.4"

-- 初始化 fskv（V3 返工标记 retest_flag 存储）
fskv.init()

-- 内核软狗，防止程序卡死（无外置看门狗芯片）
if wdt then
    wdt.init(9000)                          -- 超时 9s
    sys.timerLoopStart(wdt.feed, 3000)      -- 3s 喂一次
end

-- ==================== 开机模式分流（V3） ====================
-- 调试时可强制指定："auto"=按 V3 自动判定, "factory"=强制产测, "normal"=强制正常模式
local BOOT_MODE = "normal"

-- 诊断：确认真机固件是否提供 otp 库（otp 为 nil 时无法判定 OTP1 是否为空）
log.info("main", "otp:", type(otp), "hmeta:", type(hmeta))

-- OTP1 是否为空：以产测写入的 PROD 为准（与 8782P 参考实现一致）
-- 不能用 next(prodmeta.get_all())：OTP1 中若有厂商/校准等残留字节，
-- 只要出现一个 '=' 就会被解析成 key，导致误判为“已写号”而进入正常模式
-- 固件未编入 otp 库时，prodmeta.get() 恒为 nil，开机固定进产测并报 otp module not found
local function otp1_empty()
    local prodmeta = require("prodmeta")
    return prodmeta.get("PROD") == nil
end

local function get_boot_mode()
    if BOOT_MODE == "factory" or BOOT_MODE == "normal" then
        return BOOT_MODE
    end
    if fskv.get("retest_flag") then
        return "factory"
    end
    if otp1_empty() then
        return "factory"
    end
    return "normal"
end

local boot_mode = get_boot_mode()

if boot_mode == "factory" then
    if fskv.get("retest_flag") then
        log.info("main", "检测到返工标记，进入产测模式（返工产测）")
    else
        log.info("main", "OTP1 为空，进入产测模式（首次产测）")
    end
    -- 产测模式：只加载 USB 指令通道 + 485/LED 产测，不加载 LCD/按键/业务/UI
    require "prod_test"
else
    local prodmeta = require("prodmeta")
    log.info("main", "已写入产测数据，进入正常模式",
             "PROD:", prodmeta.get("PROD"), "PCB:", prodmeta.get("PCB"))

    -- ==================== 驱动层 ====================
    lcd_drv = require "lcd_drv"     -- ST7796 320×480 竖屏 + AirUI 初始化（require 即执行）
    key_drv = require "key_drv"     -- BOOT/PWR 按键，发布 KEY_EVENT

    -- ==================== 业务层 ====================
    -- netdrv_device(以太网/PC) → aircloud_app(云上报+命令) → sensor_app(VOC+485温湿度)
    -- → led_app(GPIO27) → fota_app
    require "app_main"

    -- ==================== UI 层 ====================
    require "ui_main"               -- AirUI 单页信息展示（网络/温湿度/VOC/设备信息）

    -- ==================== 返工入口 ====================
    -- 正常模式下仅响应 MODEL_RETEST,CONFIRM# / MODEL_RETEST?#，写标记后重启进入产测模式
    require "prod_retest"
end

-- 用户代码已结束
sys.run()
-- sys.run() 之后不要加任何语句
