-- nconv: var2-4 fn2-5 tag-short
--[[
@module  ui_main
@summary UI主模块，负责初始化硬件并启动UI系统
@version 1.0
@date    2026.03.26
@author  江访
]]
-- 加载所有页面模块
require "welcome_win"
require "idle_win"
-- require "wifi_list_win"
require "settings_win"
require "app_store_win"
require "speedtest_win"

local function umt()
    lcd_drv.init()
    tp_drv.init()
     -- 发布消息打开欢迎界面
    sys.publish("OPEN_WELCOME_WIN")
    -- 等待欢迎界面渲染完成后再开启背光，避免白屏
    sys.wait(100)
    lcd_drv.backlight_on()
end

sys.taskInit(umt)
