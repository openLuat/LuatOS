--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.1
@date    2026.10.30
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
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 启动一个循环定时器，每隔3秒钟打印一次总内存、实时的已使用内存、历史最高的已使用内存情况
-- 排查大分辨率素材起播失败时打开它，观察内存余量
-- local function mem_timer_cbfunc()
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end
-- sys.timerLoopStart(mem_timer_cbfunc, 3000)


-- 加载LCD显示初始化功能模块（display 库初始化 RGB 屏 + airui.init + 中文字库）
local lcd_app = require "lcd_app"

-- 加载触摸初始化功能模块（GT911 初始化 + 绑定到 AirUI）
local tp_app = require "tp_app"

-- 加载TF卡挂载功能模块（挂载 /sd 并列举卡上的 *.hzv 素材）
local sd_app = require "sd_app"

-- 加载素材选择列表页功能模块（列出素材清单，触摸点选）
local file_list = require "file_list"

-- 加载HZV播放引擎功能模块（创建 airui.video 组件、播放控制、播放统计）
local hzv_player = require "hzv_player"


-- 素材清单点选的消息处理函数，HZV_PLAY_REQ 的参数是素材序号，0 表示顺序播放全部
local function on_play_req(index)
    log.info("main", "收到选片消息", tostring(index))

    -- 先收起清单，给视频让出画面
    file_list.hide()

    local ok = false
    if index == 0 then
        ok = hzv_player.play_all()
    else
        ok = hzv_player.play_one(index)
    end

    if not ok then
        log.error("main", "起播失败，回到素材清单", tostring(index))
        file_list.show()
    end
end

-- 回到素材清单的消息处理函数，播放结束、点返回按钮、点画面都会发这条消息
local function on_back_req()
    log.info("main", "收到返回消息，回到素材清单")
    hzv_player.stop()
    file_list.show()
end

-- 加载即注册，两条消息在 main_task 之前就绪，避免消息早于订阅丢失
sys.subscribe("HZV_PLAY_REQ", on_play_req)
sys.subscribe("HZV_BACK_REQ", on_back_req)


-- 启动应用任务：屏幕和 AirUI 必须先初始化成功，才能创建视频组件
local function main_task()
    log.info("main", "开始初始化")

    -- ########## 1、初始化屏幕、AirUI 与触摸 ##########
    if not lcd_app.init() then
        log.error("main", "屏幕初始化失败，无法播放 HZV")
        return
    end
    log.info("main", "屏幕初始化完成", lcd_app.get_size())

    if not tp_app.init() then
        log.error("main", "触摸初始化失败，清单点不动")
    end

    -- ########## 2、挂载 TF 卡、扫描素材、列出清单 ##########
    -- 挂载失败、卡里没有素材时 sd_app 会打印原因，清单里只显示一句提示
    local files = {}
    if sd_app.mount() then
        files = sd_app.list_hzv()
    end

    if not hzv_player.set_playlist(files) then
        log.error("main", "没有可播放的素材",
            "把转换好的 .hzv 拷贝到 TF 卡根目录后重新上电")
    end

    if file_list.init(files) then
        file_list.show()
    end

    -- ########## 3、清单画好之后再点亮背光 ##########
    -- 这一步顺序很关键：屏初始化阶段背光一直灭着、整屏已被 display.fill 刷黑，
    -- 等清单画完再亮背光，开机就不会看到花屏
    sys.wait(200)
    lcd_app.backlight_on()
end

sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
