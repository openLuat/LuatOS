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
require "wifi_list_win"
require "settings_win"
require "app_store_win"

local function ui_main_task()

    tp_drv.init()
     -- 发布消息打开欢迎界面
    sys.publish("OPEN_WELCOME_WIN")

    sys.wait(1000)

    --开启背光
    pwm.setup(0,1000,100)
    pwm.start(0)
end

sys.taskInit(ui_main_task)