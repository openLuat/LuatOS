--[[
@module  boot_app
@summary 启动编排与播放调度应用功能模块（屏幕 -> 触摸 -> TF卡 -> 素材清单 -> 背光）
@version 1.0
@date    2026.11.10
@author  江访
@usage
本文件为 Air8607 播放 SD 卡 HZV 素材 demo 的启动编排与播放调度应用功能模块，核心业务逻辑为：
1、boot_app.main_task_func 按固定顺序完成整个启动编排：
- lcd_app.init 先用 PWM3 压灭背光，再初始化 1024x600 RGB 屏并刷黑整屏，最后初始化 AirUI 与中文字库；
- tp_app.init 初始化 GT911 触摸并绑定到 AirUI，失败不中止启动，素材清单还能显示，只是点不动；
- sd_app.mount 把 TF 卡挂载到 /sd，挂载失败不中止启动，素材清单里只显示一句提示；
- sd_app.list_hzv 扫描卡根目录下的 *.hzv 素材，把列表同时交给 hzv_player.set_playlist 和 file_list.init；
- file_list.show 画出素材清单，sys.wait 等首帧画好之后再调 lcd_app.backlight_on 点亮背光，避免开机花屏；
2、play_req_msg_proc_func 处理"HZV_PLAY_REQ"消息：先收起素材清单给视频让出画面，
   消息参数为 0 时调 hzv_player.play_all 顺序轮播整张素材表，其他序号调 hzv_player.play_one 只播一条，
   起播失败时重新展开素材清单；
3、back_req_msg_proc_func 处理"HZV_BACK_REQ"消息：调 hzv_player.stop 停止播放并销毁视频组件，
   再展开素材清单；播放结束、点"返回列表"按钮、点视频画面都会发这条消息；
4、本文件被 main.lua 加载时，文件末尾的 sys.subscribe 与 sys.taskInit 立刻把两条消息的处理函数
   与主任务挂到系统调度，所以 main.lua 只需要按顺序 require 各功能模块，不写任何业务逻辑。

本文件的对外接口有3个：
1、sys.subscribe("HZV_PLAY_REQ", play_req_msg_proc_func)：订阅选片消息；
   素材清单的点选和"顺序播放全部"按钮都 publish 这条消息，消息参数是素材序号，0 表示顺序播放全部；
   本demo项目中file_list.lua中publish了这个消息；
2、sys.subscribe("HZV_BACK_REQ", back_req_msg_proc_func)：订阅返回消息；
   播放结束、点"返回列表"按钮、点视频画面都 publish 这条消息，不带参数；
   本demo项目中hzv_player.lua中publish了这个消息；
3、boot_app.main_task_func：启动编排主任务函数，由本文件末尾的 sys.taskInit 挂到系统调度；
]]

local boot_app = {}

-- 加载LCD显示初始化功能模块（压灭背光 + display 库初始化 RGB 屏 + airui.init + 中文字库）
local lcd_app = require "lcd_app"

-- 加载触摸初始化功能模块（GT911 初始化 + 绑定到 AirUI）
local tp_app = require "tp_app"

-- 加载TF卡挂载功能模块（挂载 /sd 并列举卡上的 *.hzv 素材）
local sd_app = require "sd_app"

-- 加载素材选择列表页功能模块（列出素材清单，触摸点选）
local file_list = require "file_list"

-- 加载HZV播放引擎功能模块（创建 airui.video 组件、播放控制、播放统计）
local hzv_player = require "hzv_player"

-- 素材清单画好之后到点亮背光之间的等待时间，单位 ms
-- 屏初始化阶段背光一直灭着、整屏已被 display.fill 刷黑，等清单画完再亮背光，开机就不会看到花屏
local T_BACKLIGHT_DELAY = 200

--[[
"HZV_PLAY_REQ"消息的处理函数，素材清单点选的消息处理函数；

@summary 先收起素材清单给视频让出画面，再按消息参数起播，起播失败时重新展开素材清单

@param number index 素材序号，取值 1 到素材总数，由素材清单的点选消息带过来；
取值 0 表示按文件名顺序轮播整张素材表

@return nil

@usage
-- 由本文件末尾的 sys.subscribe 挂到系统调度，一般不直接调用
-- 其他应用模块如果需要起播，直接 sys.publish 这条消息即可
sys.publish("HZV_PLAY_REQ", 2)
]]
local function play_req_msg_proc_func(index)
    log.info("boot_app", "收到选片消息", tostring(index))

    -- 先收起清单，给视频让出画面
    file_list.hide()

    local ok = false
    if index == 0 then
        ok = hzv_player.play_all()
    else
        ok = hzv_player.play_one(index)
    end

    if not ok then
        log.error("boot_app", "起播失败，回到素材清单", tostring(index))
        file_list.show()
    end
end

--[[
"HZV_BACK_REQ"消息的处理函数，回到素材清单的消息处理函数；

@summary 停止播放并销毁视频组件、关闭功放，然后展开素材清单

@return nil

@usage
-- 由本文件末尾的 sys.subscribe 挂到系统调度，一般不直接调用
-- 播放结束、点"返回列表"按钮、点视频画面都会 sys.publish 这条消息
sys.publish("HZV_BACK_REQ")
]]
local function back_req_msg_proc_func()
    log.info("boot_app", "收到返回消息，回到素材清单")
    hzv_player.stop()
    file_list.show()
end

--[[
启动编排主任务函数；

@api boot_app.main_task_func()

@summary 按"屏幕 -> 触摸 -> TF卡 -> 素材清单 -> 背光"的顺序完成整个启动编排，
屏幕或 AirUI 初始化失败时中止启动，其他环节失败只打印原因并继续

@return nil

@usage
-- 由本文件末尾的 sys.taskInit 挂到系统调度，一般不直接调用
]]
function boot_app.main_task_func()
    log.info("boot_app", "开始初始化")

    -- ########## 1、初始化屏幕、AirUI 与触摸 ##########
    if not lcd_app.init() then
        log.error("boot_app", "屏幕初始化失败，无法播放 HZV")
        return
    end
    log.info("boot_app", "屏幕初始化完成", lcd_app.get_size())

    if not tp_app.init() then
        log.error("boot_app", "触摸初始化失败，清单点不动")
    end

    -- ########## 2、挂载 TF 卡、扫描素材、列出清单 ##########
    -- 挂载失败、卡里没有素材时 sd_app 会打印原因，清单里只显示一句提示
    local files = {}
    if sd_app.mount() then
        files = sd_app.list_hzv()
    end

    if not hzv_player.set_playlist(files) then
        log.error("boot_app", "没有可播放的素材",
            "把转换好的 .hzv 拷贝到 TF 卡根目录后重新上电")
    end

    if file_list.init(files) then
        file_list.show()
    end

    -- ########## 3、清单画好之后再点亮背光 ##########
    -- 这一步顺序很关键：屏初始化阶段背光一直灭着、整屏已被 display.fill 刷黑，
    -- 等清单画完再亮背光，开机就不会看到花屏
    sys.wait(T_BACKLIGHT_DELAY)
    lcd_app.backlight_on()
end

-- "HZV_PLAY_REQ"消息的处理函数，素材清单点选和"顺序播放全部"按钮 publish 这条消息
sys.subscribe("HZV_PLAY_REQ", play_req_msg_proc_func)

-- "HZV_BACK_REQ"消息的处理函数，播放结束、点返回按钮、点视频画面都 publish 这条消息
sys.subscribe("HZV_BACK_REQ", back_req_msg_proc_func)

-- 创建并且启动一个task
-- 运行这个task的主函数boot_app.main_task_func
-- 屏幕和 AirUI 必须先初始化成功，才能创建视频组件
sys.taskInit(boot_app.main_task_func)

return boot_app
