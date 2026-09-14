--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.1
@date    2026.08.20
@author  王城钧
@usage
本demo主要使用 Air1601 + AirCAMERA_1034 USB摄像头（+ AirCAMERA_1034 人脸识别模组），
提供以下三个互斥的业务应用场景：

1、face_demo：人脸录入/验证
   - 需要 AirCAMERA_1034 人脸识别模组（UART2 通信）
   - 摄像头供电引脚 GPIO12
   - 不需要网络

2、photo_to_aircloud：循环拍照上传合宙云平台
   - 需要网络，必须同时打开 require "netdrv_wifi"
   - 摄像头供电引脚 GPIO58
   - 需要网络

3、audio_record：USB摄像头麦克风录音 + TF卡存储 + 板载DAC播放
   - 摄像头供电引脚 GPIO58
   - TF卡供电 GPIO56 + SPI1
   - 不需要网络

==================== 互斥关系（重要） ====================
1、face_demo / photo_to_aircloud / audio_record 三个业务模块
   一次只能打开一个，不能同时打开（USB摄像头同一时刻只能被一个业务占用）

2、photo_to_aircloud 依赖网络，必须同时打开 require "netdrv_wifi"；

3、硬件引脚冲突：
   - GPIO58（摄像头供电）被 photo_to_aircloud 和 audio_record 共用，
     这两个模块互斥，不能同时打开
   - GPIO12（摄像头供电）仅 face_demo 使用
   - audio_record 独占用 GPIO56（TF卡供电）和 SPI1，与其他模块互斥
==================== 互斥关系（重要） ====================
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


-- 加载网络驱动模块
-- 注意：仅 photo_to_aircloud（拍照上传云平台）需要网络时才打开；
--       face_demo、audio_record 不需要网络，请保持注释状态
-- 使用前需将 netdrv/ 目录和 netdrv_wifi.lua 
require "netdrv_wifi"

-- 人脸识别demo（AirCAMERA_1034 人脸模组，UART2 + GPIO12，不需要网络）
-- require "face_demo"

-- 拍照+云平台上传（需要网络 + GPIO58，需同时打开上面的 netdrv_wifi）
require "photo_to_aircloud"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
