--[[
@module  main
@summary 双路温度监控 · 程序入口（Air8603W1 / 10寸 1024x600）
@version 1.0.0
@date    2026.11.16

启动顺序：
  fskv → 载入阈值 → 报警模块 → 数据模块 → 板级（上电/屏/airui/触摸）
  → 看门狗 → 采集任务 → 界面 → 点亮背光

注意：背光放在最后，等首屏画完再亮，避免上电白屏闪烁。
]]

PROJECT = "tmon_hmi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION, rtos.bsp(), rtos.version())

local conf = require "conf"
local store = require "app_store"
local board = require "board"
local alarm = require "app_alarm"
local data = require "app_data"
local ui = require "ui"
local sound = require "app_sound"

sys.taskInit(function()
    -- 0. fskv 必须先初始化：未 init 时 get/set 静默返回 nil
    if fskv and type(fskv.init) == "function" then
        local ok, ret = pcall(fskv.init)
        if ok and ret ~= false then
            log.info("main", "fskv 初始化成功")
        else
            log.error("main", "fskv 初始化失败，参数只存内存", tostring(ret))
        end
    else
        log.warn("main", "固件未启用 fskv，参数只存内存")
    end

    -- 1. 载入掉电参数
    store.load_channels()
    conf.alarm.hysteresis = tonumber(store.get("hyst", conf.alarm.hysteresis)) or conf.alarm.hysteresis
    conf.alarm.delay_s = tonumber(store.get("delay", conf.alarm.delay_s)) or conf.alarm.delay_s

    -- 2. 模块初始化
    alarm.init()
    data.init()

    -- 3. 板级：上电时序 / 屏 / airui / 触摸
    --    conf.board.power_on 里含 { 64, 1 } 给 485 收发芯片供电，缺了它串口能开但总线上没波形
    board.init()
    sys.wait(50)

    -- 4. 外部看门狗（板载 Air153D，不喂狗约 12 分钟重启）
    if conf.board.wdt_pin then
        local ok, err = pcall(function()
            local wdt = require "exair153x_wdt"
            wdt.init({ wdt_pin = conf.board.wdt_pin })
        end)
        if ok then
            log.info("main", "外部看门狗已启动, GPIO" .. conf.board.wdt_pin)
        else
            log.warn("main", "外部看门狗启动失败", tostring(err))
        end
    end

    -- 5. 采集与界面
    data.start()
    ui.start()

    -- 6. 报警语音（异步起任务，不占开机时间）
    sound.start()

    -- 7. 首帧已出，点亮背光
    sys.wait(120)
    board.backlight_on()

    log.info("main", "启动完成")
end)

sys.run()
