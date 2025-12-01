--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.11.25
@author  江访
@usage
本demo演示的核心功能为：
1、加载exeasyui扩展库；
2、根据选择的字体类型驱动，进行显示、触摸硬件以及字体的初始化，
   支持默认字体、外部矢量字库、内部软件矢量字库和外部自定义点阵字库四选一；
3、用户界面主循环，实现多页面切换和触摸事件处理；
4、系统看门狗配置，确保系统稳定运行；

更多说明参考本目录下的readme.md文件
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

-- 定义项目名称和版本号
PROJECT = "ui_demo" -- 项目名称
VERSION = "1.0.0"   -- 版本号

-- 在日志中打印项目名和项目版本号
log.info("ui_demo", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)

-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end


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


-- 必须加载才能启用exeasyui的功能
ui = require("exeasyui")


-- 加载lcd、tp和字库驱动管理功能模块，有以下四种：
-- 1、使用lcd内核固件中自带的12号中文字体的hw_default_font_drv，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 2、使用hzfont核心库驱动内核固件中支持的软件矢量字库的hw_hzfont_drv.lua，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 3、使用gtfont核心库驱动AirFONTS_1000矢量字库配件板的hw_gtfont_drv.lua，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 4、使用自定义字体的hw_customer_font_drv（目前开发中）
-- 最新情况可查看模组选型手册中对应型号的固件列表内，支持的核心库是否包含lcd、tp、12号中文、gtfont、hzfont，链接https://docs.openluat.com/air780epm/common/product/
-- 目前exeasyui V1.7.0版本支持使用已经实现的四种功能中的一种进行初始化，同时支持多种字体初始化功能正在开发中
require("hw_default_font_drv")
-- require("hw_hzfont_drv")
-- require("hw_gtfont_drv")
-- require("hw_customer_font_drv")开发中


-- 加载exeassyui扩展库实现的用户界面功能模块
-- 实现多页面切换、触摸事件分发和界面渲染功能
-- 包含主页、组件演示页、默认字体演示页、HZfont演示页、GTFont演示页和自定义字体演示页
require("ui_main")


-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
