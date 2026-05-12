--[[
@module  main
@summary app_engine_factory主程序入口
@version 1.0.1
@date    2026.04.28
@author  江访
@usage
通过注释/取消注释require语句来运行不同的演示。
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]

-- main.lua - 程序入口文件

-- 项目名称和版本定义
PROJECT = "app_engine_factory"                   -- 项目名称，用于标识当前工程
VERSION = "001.999.004"                          -- 项目版本号
PROJECT_KEY = "YdsyLfESvOKYSVuOBeKYmKFmoeTuuGUv" -- 项目key，此非真实项目key

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 平台检测（hmeta.model 为主，rtos.bsp 为回退）
local ok, _model = pcall(hmeta.model)
if not ok or not _model then _model = rtos.bsp() end
_G.model_str = tostring(_model or "")

-- 加载显示驱动/触摸驱动（根据平台选择对应驱动）
if _G.model_str:find("Air8000") then
    -- 配置引脚功能
    pins.setup(31, "PWM0")
    pins.setup(35, "PWM4")
    -- Air8000 显示/触摸驱动
    lcd_drv = require "lcd_drv_air8000w_4in"
    tp_drv = require "tp_drv_air8000w"
elseif _G.model_str:find("Air8101") then
    -- 配置引脚功能
    pins.setup(11, "I2C1_SDA")
    pins.setup(12, "I2C1_SCL")
    pins.setup(14, "PWM1")
    -- Air8101 显示/触摸驱动
    lcd_drv = require "lcd_drv_air8101_5in"
    tp_drv = require "tp_drv_air8101"
elseif _G.model_str:find("Air1601") or _G.model_str:find("Air1602") then
    -- Air1602 5\7\9\10寸屏显示驱动，默认5寸
    -- 取值可以是5、7、9、10，分别对应5寸屏、7寸屏、9寸屏、10寸屏
    local Air1602_lcd = 5
    if Air1602_lcd == 5 then
        -- 5寸屏显示/触摸驱动
        lcd_drv = require "lcd_drv_air1601_5in"
        tp_drv = require "tp_drv_air1601_5in"
    elseif Air1602_lcd == 7 or Air1602_lcd == 10 then
        -- 7寸/10寸屏显示/触摸驱动
        lcd_drv = require "lcd_drv_air1601_7_10"
        tp_drv = require "tp_drv_air1601_7or10"
    elseif Air1602_lcd == 9 then
        -- 9寸屏显示驱动
        -- lcd_drv = require "lcd_drv_air1601_9in"
        -- tp_drv = require "tp_drv_air1601_9in"
        -- elseif Air1602_lcd == 10 then
        -- 10寸屏显示驱动
        -- lcd_drv = require "lcd_drv_air1601_10in"
        -- tp_drv = require "tp_drv_air1601_7or10"
    end
else
    -- PC模拟器显示/触摸驱动，
    -- 取值可以是"Air8000W_4in"、"Air8101_5in"、"Air1601_5in"、"Air1601_7in"、"Air1601_9in"、"Air1601_10in"
    local pc_lcd = "Air8000W_4in"

    if pc_lcd == "Air8000W_4in" then
        lcd_drv = require "lcd_drv_air8101_5in"
        tp_drv = require "tp_drv_air8101"
    elseif pc_lcd == "Air8101_5in" then
        lcd_drv = require "lcd_drv_air8101_5in"
        tp_drv = require "tp_drv_air8101"
    elseif pc_lcd == "Air1601_5in" then
        -- 5寸屏显示/触摸驱动
        lcd_drv = require "lcd_drv_air1601_5in"
        tp_drv = require "tp_drv_air1601_5in"
    elseif pc_lcd == "Air1601_7in" or pc_lcd == "Air1601_10in" then
        -- 7寸/10寸屏显示/触摸驱动
        lcd_drv = require "lcd_drv_air1601_7_10"
        tp_drv = require "tp_drv_air1601_7or10"
        -- elseif pc_lcd == "Air1601_9in" then
        -- 9寸屏显示驱动
        -- lcd_drv = require "lcd_drv_air1601_9in"
        -- tp_drv = require "tp_drv_air1601_9in"
    end
end

exwin = require "exwin"

exapp = require "exapp"

-- 加载应用主模块
require "app_main"

-- 引入UI主模块
require "ui_main"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
