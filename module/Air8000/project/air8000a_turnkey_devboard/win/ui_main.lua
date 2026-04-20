--[[
@module  ui_main
@summary UI主模块，负责初始化硬件并启动UI系统
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为UI系统的主入口模块，主要功能包括：
1、加载所有窗口模块，确保所有UI页面可用；
2、初始化LCD显示屏驱动；
3、初始化触摸屏驱动；
4、发布启动消息，打开欢迎窗口；
5、开启背光引脚供电；

本模块没有对外接口，直接作为UI系统启动模块运行；
]]

-- 加载所有页面模块
require "welcome_win"
require "idle_win"
require "main_menu_win"
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
require "temperature_win"
require "humidity_win"
require "air_win"
require "fota_win"
require "fota_progress_win"

--[[
UI主任务函数，初始化硬件并发布启动消息

@local
@function ui_main_task
@summary UI系统主任务，负责硬件初始化和系统启动
@return nil

@usage
-- 作为系统任务启动，执行以下操作：
-- 1、初始化LCD显示屏驱动
-- 2、初始化触摸屏驱动
-- 3、发布"OPEN_WELCOME_WIN"事件，打开欢迎窗口
-- 4、等待1秒确保硬件稳定
-- 5、开启GPIO引脚1（背光供电）
]]
local function ui_main_task()

    tp_drv.init()
    -- 发布打开开机画面的消息
    sys.publish("OPEN_WELCOME_WIN")

    sys.wait(1000)
    -- 开启背光引脚供电
    gpio.setup(1, 1)

end

sys.taskInit(ui_main_task)