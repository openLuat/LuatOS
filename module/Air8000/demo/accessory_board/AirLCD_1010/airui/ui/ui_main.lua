--[[
@module  ui_main
@summary UI主程序，负责硬件初始化和窗口管理
@version 1.1.0
@date    2026-03-18
@author  江访
@usage
本文件管理UI系统启动，初始化硬件并采用exwin窗口管理扩展库。
所有窗口通过消息订阅方式打开，实现解耦。
]]


-- 加载所有窗口模块，使其可以注册消息订阅
require("home_win")
require("label_win")
require("button_win")
require("container_win")
require("bar_win")
require("switch_win")
require("dropdown_win")
require("table_win")
require("input_win")
require("msgbox_win")
require("image_win")
require("tabview_win")
require("win_win")
require("switch_demo_win")
require("hzfont_win")
require("game_win")
require("all_component_win")
require("chart_win")
require("qrcode_win") 

-- 主任务函数
local function ui_main_task()

    -- 发布打开首窗口消息
    sys.publish("OPEN_HOME_WIN")

    -- 等待硬件稳定
    sys.wait(500)

    -- 开启背光引脚供电
    gpio.setup(1, 1)

    log.info("ui_main", "UI系统启动完成，采用exwin窗口管理")
end

-- 启动UI主任务
sys.taskInit(ui_main_task)