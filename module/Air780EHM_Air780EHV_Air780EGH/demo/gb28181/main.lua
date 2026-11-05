--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.10.15
@usage
本demo演示的核心功能为：
Air780EHV 通过 4G（或 SPI 外挂 CH390H 以太网，见 config 的 M.NETDRV）
接入网络，作为 GB28181 设备端接入国标 28181-2016 平台
（平台参数见 gb28181_config.lua 第零节），完成：
1、注册 + 心跳保活 + 应答平台的目录(Catalog)查询；
2、平台点播时把本地 H.264 裸流打成 PS/RTP 持续推给平台；
3、平台语音广播/对讲时起音频引擎，双向收发 G.711A。

文件分工：
  netdrv_device.lua / netdrv/                   —— 网卡选择(4G / CH390H)
  gb28181_config.lua                            —— 平台参数、设备编码、通道表等，先改这里
  gb28181_app.lua                               —— 业务主体(注册/点播/对讲/状态)
  video_source.lua                              —— 视频源：切访问单元 + 推流节拍

更多说明参考本目录下的readme.md文件
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用 IoT 平台的远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果使用自建升级服务，根据自己项目的需求，自定义格式即可
]]
PROJECT = "GB28181"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


-- 加载网络驱动设备功能模块(4G 还是 CH390 由 gb28181_config.lua 的 M.NETDRV 决定)
require "netdrv_device"

-- 加载GB28181应用功能模块
require "gb28181_app"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
