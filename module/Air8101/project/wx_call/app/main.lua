--[[
@module  main
@summary 智能门禁系统 - 语音/视频通话主界面（Air8101B SIP 整机 10 寸）
@version 1.1.0
@date    2026.10.21
@usage
  依赖 LuatOS 核心库：lcd / tp / airui / pins / pwm / wlan / camera / gpio / i2c

  硬件：Air8101B SIP 整机，HX8282 RGB 1024x600 + GT911 触摸
  界面：顶栏（WLAN 信号/时间/USB 摄像头/微信通话）+ 主页 + 语音通话页 + 视频通话页
]]

-- PROJECT 与 VERSION 必须写在 main.lua 顶部（Luatools 与 FOTA 会读取）
PROJECT = "SmartDoor"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

if errDump then
    errDump.config(true, 600)
end

local lcd_drv = require "lcd_drv"
local tp_drv  = require "tp_drv"
local ui_main = require "ui_main"

require "net_mgr"          -- WiFi 连接 + 信号强度
require "usb_cam"          -- USB(UVC) 摄像头状态
require "wx_call"          -- 微信通话状态
local call_service = require "call_service"   -- 通话后端（tc_iot / 本地降级）
require "call_mgr"         -- 通话状态机

-- 硬件初始化：LCD 上电时序里有 sys.wait，必须放在协程里；背光最后开
sys.taskInit(function()
    sys.wait(50)
    if not lcd_drv.init() then
        log.error("main", "LCD 初始化失败，请检查 hw_config.lcd 的 model/params")
        return
    end
    tp_drv.init()
    lcd_drv.backlight_on()
    ui_main.build()
    call_service.start()
end)

sys.run()
-- sys.run() 之后不要加任何语句
