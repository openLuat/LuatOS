--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.06.08
@author  江访
@usage
本demo主要使用Air1601 + AirCAMERA_1032 USB摄像头完成以下三个应用场景的演示：
1、camera_preview：摄像头实时画面预览到LCD屏幕
2、photo_uart_post：拍照后在LCD显示并通过UART上传到电脑
3、photo_to_aircloud：拍照后在LCD显示并上传到合宙云平台

注意：以下三个业务模块只能三选一打开，不能同时打开
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量
PROJECT：项目名，ascii string类型
VERSION：项目版本号，"XXX.YYY.ZZZ"格式
]]
PROJECT = "Air1601_AirCAMERA_1032_Demo"
VERSION = "001.000.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    -- 配置喂狗超时时间为9秒钟
    wdt.init(9000)
    -- 启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
    log.info("main", "看门狗初始化成功")
end

-- 加载LCD驱动模块（三个业务都需要LCD显示，必须加载）
require "lcd_drv"
require "tp_drv"

-- 加载网络驱动模块（仅 photo_to_aircloud 业务需要联网，其他业务请注释掉本行）
-- netdrv_device.lua 内部按需选择 WIFI / 以太网 / 4G / 多网卡，请到该文件内自行切换
--  require "netdrv_device"

-- 以下三个业务模块只能选一个打开，不能同时打开 ---------------------

-- 1、加载摄像头预览应用模块（AIRUI组件方式：画面嵌入组件树，按钮与画面共存）
require "preview"

-- 2、加载拍照+LCD显示+UART上传应用模块
-- require "photo_uart_post"

-- 3、加载拍照+LCD显示+云平台上传应用模块
--    使用该模块时需要同时打开上方的 netdrv_device 加载语句
--  require "photo_to_aircloud"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
