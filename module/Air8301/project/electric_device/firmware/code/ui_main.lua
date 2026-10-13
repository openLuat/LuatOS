--[[
@module  ui_main
@summary UI主模块，负责初始化硬件并启动UI系统（Air8301）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
本模块为UI系统的主入口模块，主要功能包括：
1、加载所有窗口模块（welcome_win / home_win / wifi_win / settings_win / server_win）；
2、等待 LCD 初始化完成（LCD_READY）后初始化触摸屏驱动；
3、发布启动消息，打开欢迎窗口；
4、开启背光（PWM0）。

本模块没有对外接口，直接作为UI系统启动模块运行；
]]

-- 加载所有页面模块
require "welcome_win"
require "home_win"
require "wifi_win"
require "settings_win"
require "server_win"

--[[
UI主任务函数，初始化硬件并发布启动消息

@local
@function ui_main_task
@return nil

@usage
-- 作为系统任务启动，执行以下操作：
-- 1、等待 LCD 初始化完成（最多 8 秒）
-- 2、初始化触摸屏驱动
-- 3、发布"OPEN_WELCOME_WIN"事件，打开欢迎窗口
-- 4、等待1秒确保画面渲染完成
-- 5、开启背光（PWM0）
]]
local function ui_main_task()
    -- 等待 LCD 初始化完成（最多等待 8 秒，防止 LCD 初始化异常时 UI 任务无限阻塞）
    sys.waitUntil("LCD_READY", 8000)

    -- 初始化触摸屏驱动（GT911 + AirUI 触摸绑定）
    tp_drv.init()

    -- 发布打开开机画面的消息
    sys.publish("OPEN_WELCOME_WIN")

    -- 等待画面渲染完成，避免背光提前点亮导致白屏
    sys.wait(1000)

    -- 开启背光（PWM0）
    lcd_drv.backlight_on()
end

sys.taskInit(ui_main_task)
