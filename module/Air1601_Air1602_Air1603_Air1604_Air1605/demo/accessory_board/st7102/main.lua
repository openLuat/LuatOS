--[[
@module  main
@summary 86盒深色部件仪表盘demo入口文件，总体调度应用逻辑
@version 1.0
@date    2026.11.04
@author  江访
@usage
本demo演示的核心功能为：
1、用display核心库初始化ST7102屏幕，分辨率480x480，显示数据走RGB接口，寄存器初始化走SPI；
2、初始化airui控件库并加载hzfont矢量字库，整套界面只加载一次字库；
3、初始化ST7102触摸并绑定给airui，绑上之后点击由airui自己处理；
4、整屏铺纯黑底，界面横向两列、纵向三段排成部件式仪表盘；
5、左上一块大表盘，时间外面套一圈虚线点环，右上是日期，星期与月小字、日数字72大字号；
6、下半左边是音乐部件，封面、歌名歌手和一个播放暂停按钮，点按钮翻转播放状态；
7、下半右边上面是月历部件，当月6行7列日期网格，今天那格垫品红实心圆；
8、下半右边下面是家庭部件，3行配件带类型图标圆底和小开关，点一行翻转开关；
9、表盘时间走设备实时时刻，每秒刷新一次时间、日期和日数字；

更多说明参考本目录下的readme.md文件
]]

PROJECT = "st7102_home_dash"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

local home_dash_ui_main = require "home_dash_ui_main"

-- 看门狗，9秒超时，每3秒喂一次
-- airui内部有自己的刷新定时器，界面一直在刷新，不会饿死看门狗
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)

-- 深色部件仪表盘task的主函数
local function home_dash_task_func()
    -- 初始化屏幕、airui、触摸，并搭建整套界面
    -- 屏幕初始化在home_dash_ui_main内部完成，这里只需要一个入口
    local ok, err = home_dash_ui_main.create()
    if not ok then
        log.error("main", "界面创建失败", err)
        return
    end

    log.info("main", "深色部件仪表盘界面已显示")
end

--创建一个task，并且运行task的主函数home_dash_task_func
sys.taskInit(home_dash_task_func)

-- 结尾总是这一句
sys.run()
-- sys.run() 之后不要加任何语句（加了也不会被执行）
