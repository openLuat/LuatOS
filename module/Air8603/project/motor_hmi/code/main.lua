--[[
@module  main
@summary 电机 HMI 入口（Air8603W1 / 10寸 1024×600 / RS485 Modbus RTU）
@version 1.0.0
@date    2026.11.12

启动顺序（顺序不能乱）：
  0. fskv 初始化（间隔参数、报警记录都落在这里）
  1. 载入掉电参数（启动间隔）→ 恢复历史报警记录
  2. 板级上电时序 + RGB 屏 + airui + 触摸（含 485 芯片供电）
  3. 外部看门狗 Air153D（不喂狗约 12 分钟重启）
  4. 采集任务（串口 → 轮询变频器）
  5. 报警扫描任务
  6. 建首页 → 首帧绘制完成后点亮背光

固件要求：LUAT_USE_GUI（airui）、display（RGB）、tp（GT911）、uart、fskv
]]

PROJECT = "motor_hmi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION, rtos.bsp(), rtos.version())

local conf = require "conf"
local store = require "app_store"
local board = require "board"
local alarm = require "app_alarm"
local data = require "app_data"
local ui_main = require "ui_main"

sys.taskInit(function()
    -- 0. fskv 必须先初始化：未 init 时 get/set 直接返回 nil，表现为参数静默失效
    if fskv and type(fskv.init) == "function" then
        local ok, ret = pcall(fskv.init)
        if ok and ret ~= false then
            log.info("main", "fskv 初始化成功")
        else
            log.error("main", "fskv 初始化失败，参数/记录只存内存", tostring(ret))
        end
    else
        log.warn("main", "固件未启用 fskv，参数/记录只存内存")
    end

    -- 1. 掉电参数 + 历史报警
    store.load_gap()
    alarm.init()

    -- 2. 板级初始化
    board.init()
    sys.wait(50)

    -- 3. 外部看门狗
    if conf.board.wdt_pin then
        -- 模块名必须放在变量里：烧录合并工具会静态扫描 require 后面的字符串，
        -- 把它当成需要打包的脚本文件。而 exair153x_wdt 是固件内置库，
        -- 不在脚本区，写成字面量会报"合并失败：缺少 exair153x_wdt"。
        local wdt_lib = "exair153x_wdt"
        local ok, err = pcall(function()
            local wdt = require(wdt_lib)
            wdt.init({ wdt_pin = conf.board.wdt_pin })
        end)
        if ok then
            log.info("main", "外部看门狗已启动, GPIO" .. conf.board.wdt_pin)
        else
            log.warn("main", "外部看门狗启动失败（固件是否带 exair153x_wdt）", tostring(err))
        end
    end

    -- 4. 采集任务（内部完成串口初始化）
    data.start()

    -- 5. 报警扫描：跟着轮询节拍走，比轮询稍慢一档即可
    sys.taskInit(function()
        while true do
            sys.wait(conf.poll_ms + 100)
            pcall(alarm.scan)
        end
    end)

    -- 6. 界面
    ui_main.start()

    sys.wait(100)
    board.backlight_on()

    log.info("main", "启动完成")
end)

sys.run()
