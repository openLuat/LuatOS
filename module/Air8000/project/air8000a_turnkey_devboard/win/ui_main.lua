-- ui_main.lua - 仅初始化并发布启动消息

-- 加载所有页面模块
require "home_win"
require "all_app_win"
require "call_win"
require "camera_win"
require "network_select_win"
require "gps_win"
require "sensor_win"
require "iot_account_win"
require "bluetooth_win"
require "uart_win"
require "record_win"
require "tts_win"
require "apn_win"
require "ethernet_win"
require "wifi_win"
require "idle_win"

-- 全局变量（供所有页面使用）
sim_present = false
aircloud_qr = nil

-- UI 主任务：初始化硬件并发布启动消息
local function ui_main_task()
    lcd_drv.init()
    tp_drv.init()

    -- 发布打开开机画面的消息
    sys.publish("OPEN_IDLE_WIN")

    sys.wait(1000)
    -- 开启背光引脚供电
    gpio.setup(1, 1)

end

sys.taskInit(ui_main_task)