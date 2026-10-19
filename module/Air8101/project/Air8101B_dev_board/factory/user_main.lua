--[[
@module  user_main
@summary 用户模式入口（产测通过后正常运行的那一半固件）
@version 1.0
@date    2026.10.16
@usage
由 main.lua 在用户模式分支 require（USER_MODULE = "user_main"）：

    sys.taskInit(function()
        board.power_on()                 -- 上电时序 + SPI0/I2C1 复用
        require "user_main"              -- 本模块
    end)

注意
1. 上电时序（board.power_on）已在 main.lua 里调用过，本模块不要再调一次；
2. 本模块只负责"按顺序拉起各功能模块"，业务逻辑都在 app_* / ui_* 里；
3. 与产测模式互斥：产测项（prod_*）在用户模式一概不加载，网络出口 UART1 由 4G 独占。
]]

local app_net    = require "app_net"
local aircloud_app = require "aircloud_app"
local airlbs_app = require "airlbs_app"
-- FOTA：后台自动升级（libfota3），无界面；未配 config.fota.project_key 时只告警
local fota_app   = require "fota_app"
-- 板载 SHT30 温湿度已由 485 温湿度传感器替代，不再加载/启动（app_sensor.lua 保留备查，不随固件打包）
local app_voc    = require "app_voc"
local app_devsel = require "app_devsel"
local app_storage = require "app_storage"

local AUDIO_DIAG = false

if AUDIO_DIAG then
    sys.taskInit(function()
        pcall(function() require("app_storage").init() end)   -- 为了 /sd 能读
        sys.wait(500)

        local exaudio = require "exaudio"
        local c = ((_G.project_config or {}).hw or {}).audio or {}
        local a = { model = "dac", pa_ctrl = c.pa_en, pa_on_level = c.pa_on_level or 1 }
        if c.dac_chl then a.dac_chl = c.dac_chl end

        local ok = exaudio.setup(a)
        log.info("audio_diag", "setup", ok, "pa_ctrl", tostring(c.pa_en),
            "pa_on_level", tostring(a.pa_on_level), "dac_chl", tostring(a.dac_chl))
        exaudio.vol(80)

        for _, f in ipairs({ "/luadb/test_sound.wav", "/sd/record.wav" }) do
            if io.exists(f) then
                log.info("audio_diag", "播放", f)
                exaudio.play_start({
                    type = 0, content = f,
                    cbfnc = function(e) log.info("audio_diag", "回调", e) end,
                })
                break
            end
        end
    end)
    return   -- 不启动界面
end

-- 状态服务：require 即启动（时间刷新 + 网络状态转发）
require "app_status"

-- 界面：内部自己起 task 初始化显示/触摸/AirUI，然后进欢迎页
require "ui_main"

sys.taskInit(function()
    sys.wait(300)          -- 让 UI 先把首屏画出来
    app_net.init()

    -- AirCloud 上报：enabled=false 或没配 auth_key 时只打日志、不联网
    aircloud_app.init()

    -- 多 WiFi 定位：enabled=false 或没配 LBS 项目时只打日志、不扫描
    airlbs_app.init()

    -- 外部存储：TF 卡挂到 /sd（文件浏览、音频播放要能读到卡里的音乐）。
    -- 挂载失败只告警，不影响其它功能；要在 task 里调（内部有 sys.wait）。
    app_storage.init()

    -- 配件板：现场一次只接一块（空气质量；温湿度已改用 485 传感器，不再启动板载 SHT30），
    -- 没有对应配件板时不探测、不占总线、不刷 not-found。
    sys.wait(800)
    local dev = app_devsel.get()
    log.info("user_main", "当前配件板:", app_devsel.name(dev))
    if dev == "voc" then
        app_voc.start()
    end

    -- 对时：拿到 IP 后自动同步，失败会自己重试；不影响其它功能
    app_net.sntp()

    -- FOTA：后台自动检测（libfota3 内部自己等 IP + 对时，这里只是把配置交给它）
    -- 未配 project_key 时只打一条 warn；升级过程全部走日志前缀 "fota"
    fota_app.start()
end)

log.info("user_main", "用户模式已启动", _G.PROJECT or "", _G.VERSION or "")
