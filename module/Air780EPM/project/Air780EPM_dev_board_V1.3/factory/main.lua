--[[
@module  main
@summary Air780EPM V1.3 开发板默认出厂固件入口
@version 1.0.0
@date    2026.10.19
@usage
本工程为 Air780EPM V1.3 开发板的默认出厂固件：

功能：
  - 4G 联网（netdrv_4g）
  - VOC 空气质量 + 485温湿度采集，AirCloud 定时上报
  - 云端下行命令：cycle:秒数（改上报频率）/ led:blink|on|off
  - 竖屏 320×480 LCD（AirLCD_1000，ST7796）单页信息展示
  - 无 iRTU / 无 web / 无外置看门狗（仅内核软狗 wdt）

硬件配置（Air780EPM V1.3 开发板 + AirLCD_1000）：
  - 主控: Air780EPM（4G 原生）
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
PROJECT = "Air780EPM_DevBoard_V1.3"
VERSION = "001.999.000"

-- AirCloud 云平台鉴权密钥（FOTA/设备绑定共用）
PROJECT_KEY = "ICIYq4kH49x0aYX8yOT69KW3dV5Wskpf"

log.info("main", PROJECT, VERSION)

-- 硬件环境：固定 Air780EPM V1.3 开发板（lcd_drv 按此适配 GPIO29 控 LCD 电源、GPIO30 控背光）
HARDWARE_ENV = "DEV_BOARD_V1.3"

-- 内核软狗，防止程序卡死（无外置看门狗芯片）
if wdt then
    wdt.init(9000)                          -- 超时 9s
    sys.timerLoopStart(wdt.feed, 3000)      -- 3s 喂一次
end

-- ==================== 驱动层 ====================
lcd_drv = require "lcd_drv"     -- ST7796 320×480 竖屏（require 即初始化）
key_drv = require "key_drv"     -- BOOT/PWR 按键，发布 KEY_EVENT

-- ==================== 业务层 ====================
-- netdrv_device(4G/PC) → aircloud_app(云上报+命令) → sensor_app(VOC+485温湿度) → led_app(GPIO27)
require "app_main"

-- ==================== UI 层 ====================
require "ui_main"               -- 单页信息展示（网络/温湿度/VOC/设备信息）

-- 用户代码已结束
sys.run()
-- sys.run() 之后不要加任何语句
