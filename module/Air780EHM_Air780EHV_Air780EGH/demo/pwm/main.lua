--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.11.05
@author  马梦阳
@usage

本demo演示的核心功能为：
1. 旧风格 PWM 演示：
    使用 pwm.open() 完成 PWM 通道的配置与启动
    使用 pwm.close() 关闭 PWM 通道
    旧风格 PWM 接口不支持单独配置和动态调整占空比和信号频率
2. 新风格 PWM 演示：
    使用 pwm.setup() 完成 PWM 通道的配置
    使用 pwm.start() 启动 PWM 输出
    使用 pwm.setDuty() 动态调整占空比
    使用 pwm.setFreq() 动态调整信号频率
    使用 pwm.stop() 停止 PWM 输出
    新风格 PWM 接口支持在运行中动态调整占空比和信号频率

注意事项：
1. 本 demo 演示所使用的是 Air780EHM/EHV/EGH 模组的 PWM4 通道（GPIO27，PIN16）；
2. 该引脚需要通过 LuatIO 工具进行复用配置：
    pins_Air780EHM.json 为 Air780EHM 模组的复用配置文件；
    pins_Air780EHV.json 为 Air780EHV 模组的复用配置文件；
    pins_Air780EGH.json 为 Air780EGH 模组的复用配置文件；
3. 关于 LuatIO 工具的使用介绍以及如何生成 json 文件，请参考 https://docs.openluat.com/air780epm/common/luatio/；
3. 将通过 LuatIO 工具配置好复用关系后生成的 json 文件与脚本文件一同烧录到模组中即可实现 PWM 输出功能；

注意！！！！pwm.setFreq() 函数目前出现一些 BUG，调用成功后无法正常输出波形，正在紧急修复，时间 2025.10.29

更多说明参考本目录下的 readme.md 文件；
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
PROJECT = "PWM"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)





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


-- 加载 PWM 应用模块
require "pwm_app"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
