--[[
@module  main
@summary LuatOS mjpg视频播放应用主入口，负责加载功能模块
@version 1.0.0
@date    2026.05.25
@author  拓毅恒
@usage
本demo演示两种视频播放场景（二选一）：

场景一：播放本地烧录的视频（默认启用）
- 从 /luadb/fly_man_80.mjpg 加载并播放
- 需要将视频文件烧录到固件中

场景二：播放从服务器下载的视频
- 需要插入SIM卡并连接网络
- 从IOT云平台服务器下载视频后播放

使用说明：
根据需求启用对应的播放模式，注释掉不需要的模式
- 播放本地烧录的视频：  require "mjpg_player"
- 播放从服务器下载的视频：require "mjpg_player_server"

更多说明参考本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "PLAY_MJPG"
VERSION = "001.999.000"

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



-- 加载网络驱动模块（Air1601本身不支持4G，需要外挂模块）
require "netdrv_device"

-- 加载LCD驱动模块
require "lcd_drv"

-- 加载视频播放业务逻辑模块（二选一）
-- 场景一：播放本地烧录的视频（默认启用）
require "mjpg_player"
-- 场景二：播放从服务器下载的视频
-- 测试从服务器下载播放功能，取消注释下一行
-- require "mjpg_player_server"

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!
