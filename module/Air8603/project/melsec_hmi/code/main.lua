--[[
@module  main
@summary 三菱 FX 温度监控大屏入口（Air8603 / 10寸 1024×600 / RS485 计算机链接格式1）
@version 1.0.0
@date    2026.11.09

启动顺序（顺序不能乱）：
  0. fskv 初始化（阈值参数/报警记录都落在这里）
  1. 载入掉电参数（阈值）→ 恢复历史报警记录
  2. 板级上电时序 + RGB 屏 + airui + 触摸（这一步有 ms 级阻塞，含 485 芯片供电）
  3. 启动三菱协议采集（必须在 485 供电、串口可用之后）
  4. 建首页 → 首帧绘制完成后点亮背光（避免闪屏/残影）

固件要求：LUAT_USE_GUI（airui）、display（RGB）、tp（GT911）、uart；
报警语音另需 audio_v2 + TTS 能力与 exaudio 脚本库。
]]

--[[
=== 看门狗提醒 ===
860X上有合宙Air153D 看门狗芯片 其他项目参考本项目时，须确定你的项目硬件上有无看门狗芯片 如果有 但是未添加喂狗逻辑 约12分钟左右 860X会重启
]]

PROJECT = "melsec_hmi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION, rtos.bsp(), rtos.version())

local conf = require "conf"
local store = require "app_store"
local board = require "board"
local alarm = require "app_alarm"
local data = require "app_data"
local ui_main = require "ui_main"
local sound = require "app_sound"

sys.taskInit(function()
    -- 0. fskv 必须先初始化：未 init 时 fskv.get/set 直接返回 nil（只打印
    --    "call fskv.init() first!!!"），表现为参数读写全部静默失败
    if fskv and type(fskv.init) == "function" then
        local ok, ret = pcall(fskv.init)
        if ok and ret ~= false then
            log.info("main", "fskv 初始化成功")
        else
            log.error("main", "fskv 初始化失败，参数/报警记录只存内存", tostring(ret))
        end
    else
        log.warn("main", "固件未启用 fskv，参数/报警记录只存内存")
    end

    -- 1. 掉电参数 + 历史报警
    store.load_channels(conf.chs)
    alarm.init()
    data.init()

    -- 2. 板级初始化（上电时序 / 屏 / airui / 触摸）
    --    conf.board.power_on 里含 { 64, 1 } 给 485 收发芯片供电，缺了它串口能开但总线上没波形
    board.init()
    sys.wait(50)

    -- 3. 外部看门狗（板载 Air153D，不需要就设 conf.board.wdt_pin = false）
    if conf.board.wdt_pin then
        local ok, err = pcall(function()
            local wdt = require "exair153x_wdt"
            wdt.init({ wdt_pin = conf.board.wdt_pin })
        end)
        if ok then
            log.info("main", "外部看门狗已启动, GPIO" .. conf.board.wdt_pin)
        else
            log.warn("main", "外部看门狗启动失败（固件是否带 exair153x_wdt）", tostring(err))
        end
    end

    -- 4. 采集任务 + 首页
    data.start()
    ui_main.start()

    -- 5. 报警语音（异步起任务，不让音频初始化占开机时间）
    sound.start()

    -- 6. 首帧已出，点亮背光
    sys.wait(100)
    board.backlight_on()

    log.info("main", "启动完成")
end)

sys.run()
