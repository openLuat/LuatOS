--[[
@module  main
@summary LuatOS 用户应用脚本文件入口
@version 1.0
@date    2026.9.9
@author  许璐
@usage
本 demo 演示 exs_aht20 温湿度传感器扩展库的完整功能，业务逻辑见 aht20_app.lua
]]

--[[
=== 演示内容 ===

本 demo 演示 exs_aht20 扩展库的完整功能，顺序为：

1、初始化
2、周期读取温湿度数据
3、连续失败后软复位并重新初始化

更多说明参考本目录下的 readme.md 文件
]]

--[[
PROJECT：项目名，ascii string 类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string 类型
        如果使用合宙 iot.openluat.com 进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z 各表示 1 位数字，三个 X 表示的数字可以相同，也可以不同，同理三个 Y 和三个 Z 表示的数字也是可以相同，可以不同
            因为历史原因，YYY 这三位数字必须存在，但是没有任何用处，可以一直写为 000
        如果不使用合宙 iot.openluat.com 进行远程升级，根据自己项目的需求，自定义格式即可
]]

PROJECT = "sensor_aht20"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)



-- 如果内核固件支持 wdt 看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    wdt.init(9000)                      -- 配置喂狗超时时间为 9 秒
    sys.timerLoopStart(wdt.feed, 3000)  -- 每隔 3 秒喂一次狗
end

-- 如果内核固件支持 errDump 功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息
-- 可以初步分析一些设备运行异常的问题
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 使用 LuatOS 开发的任何一个项目，都强烈建议使用远程升级 FOTA 功能
-- 可以使用合宙的 iot.openluat.com 平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级



require "aht20_app"

sys.run()
-- sys.run() 之后不要加任何语句!!!!!
