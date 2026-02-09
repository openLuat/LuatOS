--[[
@module  main
@summary exEasyUI组件演示主程序入口
@version 1.0.0
@date    2026.01.27
@author  江访
@usage
本文件是exEasyUI演示程序的主入口，用于选择加载不同的UI组件演示模块。
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
PROJECT = "AirUI_demo" -- 项目名称，用于标识当前工程
VERSION = "001.000.000"      -- 项目版本号

-- 在日志中打印项目名和项目版本号
log.info("ui_demo", PROJECT, VERSION)

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

-- 加载显示驱动
lcd_drv = require("lcd_drv")
-- 加载触摸驱动
tp_drv = require("tp_drv")

-- 引入演示模块（每次只选择一个运行）
-- require("airui_label") --动态更新标签演示
-- require("airui_button")  --按钮演示
-- require("airui_image")  --图片显示演示
-- require("airui_container")  --容器演示
-- require("airui_bar")  --动态进度条演示
-- require("airui_dropdown")  --下拉框演示
-- require("airui_switch")  --开关组件演示
-- require("airui_msgbox")  --消息框组件演示
-- require("airui_input")  --输入框和键盘演示
-- require("airui_tabview")  --选项卡演示
-- require("airui_table") --表格演示
-- require("airui_win")  --标签窗口演示
require("airui_all_component") --所有组件综合演示
-- require("airui_switch_page")  --页面切换演示
-- require("airui_hzfont")  --内置软件矢量字体演示


-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
