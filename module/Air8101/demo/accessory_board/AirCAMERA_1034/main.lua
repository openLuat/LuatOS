--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.1
@date    2026.08.20
@author  王城钧
@usage
本示例提供三种 AirCAMERA_1034 用法。在下方选择一组 require，三种用法共用摄像头。

1、face_demo：通过 UART1 演示人脸录入和验证，启动后会清空已有用户。
2、photo_to_aircloud：循环拍照并上传合宙云平台，需同时加载 netdrv_wifi（默认）。
3、face_preview：在 Air8101B V3.0 开发板和 AirLCD_1100 上预览、拍照和保存到 TF 卡。
   需要人脸功能时，接好 UART1 并附加 exfacecam.lua，可在预览期间录入和验证。
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量
PROJECT：项目名，ascii string类型
VERSION：项目版本号，"XXX.YYY.ZZZ"格式
]]
PROJECT = "Air8101_AirCAMERA_1034_Demo"
VERSION = "001.999.000"
 
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


-- 循环拍照并上传合宙云平台（默认）。切换到其他示例时，同时注释下面两行。
require "netdrv_wifi"
require "photo_to_aircloud"

-- 串口人脸录入和验证示例。启动后会清空已有用户。
-- require "face_demo"

-- LCD 软件预览和人脸录入、验证。
-- require "face_preview"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
