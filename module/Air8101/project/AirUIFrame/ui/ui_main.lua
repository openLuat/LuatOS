--[[
@module  ui_main
@summary UI主模块，负责初始化硬件并启动UI系统
@version 1.0
@date    2026.03.26
@author  江访
]]

-- 加载所有需要的页面模块
require "welcome_win"
require "idle_win"
require "main_menu_win"
require "gps_win"
require "iot_account_win"
require "bluetooth_win"
require "wifi_win"
require "fota_win"
require "fota_progress_win"

local function ui_main_task()


    sys.publish("OPEN_WELCOME_WIN")

    sys.wait(1000)
    gpio.setup(5, 1)
end

sys.taskInit(ui_main_task)