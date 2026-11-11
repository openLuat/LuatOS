--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.2
@date    2026.11.10
@author  江访
@usage
本demo演示的核心功能为：
1、Air8607 整机播放 SD 卡（TF 卡）里的 HZV 音视频文件，
   HZV 格式说明见 https://docs.openluat.com/protocols/hzv/ ；
2、挂载 TF 卡到 /sd，扫描根目录下的 *.hzv 素材，在屏幕上列出素材清单；
3、触摸点选素材播放，也可以点"顺序播放全部"按文件名顺序轮播整张表；
4、用 airui.video 组件播放 HZV，组件参数为 format="hzv"、backend="videoplayer"、
   decode_mode="hw"、loop=false、auto_play=false；
5、按素材的真实分辨率在 1024x600 屏幕内居中显示，先设置软件音量、打开功放 PA，再开始播放；
6、播放期间画面右上角有"返回列表"按钮，点按钮或者点画面都回到素材清单；
7、播放期间定时打印 video:get_stats 的运行统计（帧率、总帧数、音视频偏差、丢帧、音频欠载）；
8、开屏顺序与出厂固件一致，避免开机花屏：
   先压灭背光 → display.init 初始化屏 → 刷黑整屏 → airui.init → 加载中文字库 →
   初始化触摸 → 列出素材清单 → sys.wait(200) → 最后点亮背光。

素材准备：
- 用 AirMaster 把普通视频（MP4/MOV/AVI 等）转成 .hzv，拷贝到 TF 卡根目录；
- 插卡上电后在清单里点选播放，卡里没有 .hzv 时清单里只有一句提示，屏幕保持黑屏；
- 素材转换方法与分辨率建议见本目录下的 readme.md 文件。

本文件只做一件事：按顺序加载各业务逻辑功能模块，不写任何业务逻辑。
各功能模块的说明如下：
1、lcd_app.lua：显示初始化（压灭背光 + display 库初始化 1024x600 RGB 屏 + airui.init + 中文字库）；
2、tp_app.lua：触摸初始化（GT911 初始化 + 绑定到 AirUI + 播放后补回触摸总线配置）；
3、sd_app.lua：TF 卡应用（挂载 /sd、卸载、列举卡上的 *.hzv 素材）；
4、file_list.lua：素材选择列表页（airui 列表 + 触摸点选 + 发选片/顺序播放消息）；
5、hzv_player.lua：HZV 播放引擎（airui.video 组件 + 功放 + 轮播 + 播放统计）；
6、boot_app.lua：启动编排与播放调度（屏幕 -> 触摸 -> TF卡 -> 素材清单 -> 背光）。

模块加载即挂起各自的任务与定时器，真正的启动编排和消息调度在 boot_app.lua 里。

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
PROJECT = "PLAY_HZV_SD"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


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
-- 排查大分辨率素材起播失败时打开它，观察内存余量
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


-- 加载LCD显示初始化功能模块（压灭背光 + display 库初始化 RGB 屏 + airui.init + 中文字库）
require "lcd_app"

-- 加载触摸初始化功能模块（GT911 初始化 + 绑定到 AirUI）
require "tp_app"

-- 加载TF卡挂载功能模块（挂载 /sd 并列举卡上的 *.hzv 素材）
require "sd_app"

-- 加载素材选择列表页功能模块（列出素材清单，触摸点选）
require "file_list"

-- 加载HZV播放引擎功能模块（创建 airui.video 组件、播放控制、播放统计）
require "hzv_player"

-- 加载启动编排与播放调度功能模块（屏幕 -> 触摸 -> TF卡 -> 素材清单 -> 背光）
require "boot_app"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
