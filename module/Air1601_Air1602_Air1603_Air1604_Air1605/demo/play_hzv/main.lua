--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.10.26
@author  拓毅恒
@usage
本demo演示的核心功能为：
1、播放合宙嵌入式音视频格式 HZV 文件（MJPEG 视频 + MP3/PCM 音频，单文件音画同步），
   关于 HZV 格式的详细说明见 https://docs.openluat.com/protocols/hzv/
2、按 HARDWARE_ENV 自动适配不同开发板的屏幕、背光、功放 PA 和 TF 卡供电脚，
   同一份代码可以在 Air8601/Air8602/Air8603/Air8605/Air8607 以及 Air1601 开发板上跑，
   板型参数集中在 hzv_hw.lua 里，业务模块只读参数、不判断板型；
3、演示 airui.video 组件的 HZV 播放控制接口：
   - video:play()：开始或恢复播放；
   - video:pause()：同时暂停视频调度和音频播放；
   - video:stop()：停止播放并回到初始状态；
   - video:get_stats()：查询实际帧率、音视频偏差、丢帧数、音频欠载次数等运行状态；
4、演示 TF 卡挂载流程，并从 /sd 顺序读取大文件 HZV（素材小的时候放 /luadb 也可以）；
5、两种运行模式，启动时自动选择：
   - 有触摸屏（hzv_hw 里配了 tp 段且 tp.init 成功）→ hzv_ui.lua 的选片界面：
     左侧是"内置存储 / TF 卡"目录切换 + 该目录下的 *.hzv 列表，点一下换片；
     底部播放/暂停/停止/音量-/音量+/刷新/全屏七个按钮，右下角实时显示 fps 与音量；
     点"全屏"后隐藏各栏、视频在整屏范围内居中播放，底部浮出播放/暂停/退出全屏控制栏；
   - 没有触摸屏或触摸初始化失败 → 自动演示模式：打开第一个素材后一直循环播放
6、开屏顺序与 8607 出厂固件一致，避免开机花屏：
   先压灭背光 → display.init 初始化屏 → 刷黑整屏 → airui.init + 加载中文字库 →
   建界面/开播 → sys.wait(200) → 最后点亮背光（lcd_app.backlight_on()）；

板型切换：
- 修改 hzv_hw.lua 顶部的 HARDWARE_ENV（默认 "8601_DEV_BOARD"）；
- 或者在下面"硬件环境配置"处给全局 HARDWARE_ENV 赋值，优先级高于 hzv_hw.lua 里的默认值；

素材准备：
- 默认素材 dont_sick.hzv 已经放在本 demo 目录里（480x320 / 15FPS / MP3 32kHz 单声道，约 2.9MB），
  用 Luatools 烧录整个 demo 目录时会一起打包进 luadb 分区，运行时路径就是 /luadb/dont_sick.hzv，
  上电默认播放它，客户不用另外拷文件；
- 想换素材：用 AirMaster 把普通视频（MP4/MOV/AVI 等）转成 .hzv，替换同名文件即可，
  或者改名后放进 TF 卡根目录（/sd/*.hzv），界面上可以直接选；
- 转素材时 Air1601 系列首跑推荐 480x320 / 10FPS / MP3 32kHz 单声道 64kbps，
  稳定后再往上加分辨率与帧率。

更多说明见本目录下的readme.md文件
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
PROJECT = "PLAY_HZV"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 硬件环境配置
-- 全局 HARDWARE_ENV 在 hzv_hw.lua 被 require 时读取，在这里先赋值可以覆盖 hzv_hw.lua 里的默认值
-- 可选值：8601_DEV_BOARD(默认) / 8602_DEV_BOARD / 8603_DEV_BOARD / 8605_DEV_BOARD /
--         8607_DEV_BOARD / 8607A_DEV_BOARD / 1601_EVB_V11 / 1601_EVB_V12
HARDWARE_ENV = "8607_DEV_BOARD"



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
-- 远程升级的详细用法，见fota的demo


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


-- 加载硬件环境配置模块（按 HARDWARE_ENV 区分板型，板型差异全部集中在这个文件里）
local hzv_hw = require "hzv_hw"

-- 加载LCD显示驱动功能模块（display 库初始化 RGB 屏 + airui.init）
local lcd_app = require "lcd_app"

-- 加载TF卡挂载功能模块（从 /sd 读取大文件 HZV，不需要 TF 卡时可以注释掉）
local sd_app = require "sd_app"

-- 加载HZV视频播放主应用功能模块
local hzv_player = require "hzv_player"

-- 加载HZV选片界面功能模块（有触摸屏时使用）
local hzv_ui = require "hzv_ui"


-- 启动应用任务：屏幕和 AirUI 必须先初始化成功，才能创建视频组件
-- 任务体用具名函数，便于日志定位，也避免在 sys.taskInit 里写匿名函数
local function main_task()
    log.info("main", "开始初始化，当前硬件环境", hzv_hw.name())

    -- ########## 1、初始化屏幕与 AirUI ##########
    if not lcd_app.init() then
        log.error("main", "屏幕/AirUI 初始化失败，HZV 无法显示，任务退出",
            "请确认固件开启了 LUAT_USE_DISPLAY 与 LUAT_USE_AIRUI")
        return
    end
    log.info("main", "屏幕初始化完成", lcd_app.get_size())

    -- ########## 2、挂载 TF 卡（可选） ##########
    -- 部分板型出厂就没有 SD 卡座（如 Air8607A），参数表里 sd 段为 nil，这里直接跳过；
    -- 有卡但挂载失败也不影响播放，hzv_player 会自动回退到 /luadb 里的素材
    if hzv_hw.has_sd() then
        if not sd_app.mount() then
            log.warn("main", "TF 卡挂载失败，只播放 /luadb 下的素材")
        end
    else
        log.info("main", "当前板型无 SD 卡，只播放 /luadb 下的素材")
    end

    -- ########## 3、有触摸就进选片界面，没有触摸就自动演示 ##########
    -- hzv_ui.start() 内部会初始化 GT911 触摸并绑定到 AirUI，
    -- 只要触摸没配置或初始化失败就返回 false，此时退回自动演示模式，保证没有触摸屏也能跑
    if not hzv_ui.start() then
        log.warn("main", "触摸不可用，进入自动演示模式（没有选片界面）")
        hzv_player.start_auto()
    else
        log.info("main", "触摸可用，已进入选片界面")
    end

    -- ########## 4、界面/首帧就绪后再点亮背光 ##########
    -- 这一步顺序很关键：屏初始化阶段背光一直灭着、屏已被 display.fill 刷黑，
    -- 等界面画好再亮背光，开机就不会看到花屏。
    -- 8607 出厂固件同样是"lcd init → 建界面 → wait(100) → backlight_on"。
    -- 这里 wait 200ms 让 AirUI 把首帧画完，这是全流程唯一的点灯入口（hzv_player 里不再点灯）。
    sys.wait(200)
    lcd_app.backlight_on()
end

sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
