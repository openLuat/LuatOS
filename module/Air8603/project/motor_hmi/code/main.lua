--[[
@module  main
@summary 电机 HMI 入口（Air8603W1 / 10寸 1024x600 / plcui + Modbus RTU）
@version 2.0.0
@date    2026.11.12

启动顺序（顺序不能乱）：
  0. fskv 初始化（启动间隔、报警记录落在这里）
  1. 载入掉电参数 + 历史报警
  2. 板级上电时序 → RGB 屏
  3. 外部看门狗 Air153D（不喂狗约 12 分钟重启）
  4. 触摸：i2c.setup → tp.init（必须在 plcui.init 之前）
  5. plcui.init → device_bind_touch → load 布局
  6. 采集任务（串口轮询变频器）+ 界面刷新循环
  7. 首帧出来之后点亮背光

固件要求：plcui、display(RGB)、tp(GT911)、uart、fskv
注意：plcui 与 airui 不能同时使用，本工程已完全移除 airui。
]]

PROJECT = "motor_hmi"
VERSION = "2.0.0"

log.info("main", PROJECT, VERSION, rtos.bsp(), rtos.version())

local conf  = require "conf"
local store = require "app_store"
local board = require "board"
local alarm = require "app_alarm"
local data  = require "app_data"
local tpg   = require "drv_tp_gt911"
local ui    = require "ui"

local xml

sys.taskInit(function()
    -- 0. fskv：未 init 时 get/set 全部静默失败
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
    data.init()

    -- 2. 板级：上电时序 + RGB 屏
    board.init()
    sys.wait(50)

    -- 3. 外部看门狗
    --    exair153x_wdt 是脚本库（同目录下的 .lua 文件），不是固件内置库，
    --    必须写成字面量 require 让合并工具把它打进脚本区。
    --    早期误判成固件库、把模块名藏进变量，导致文件没被打包，运行时报
    --    "module 'exair153x_wdt' not found"。
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

    -- 4. 触摸：i2c.setup → tp.init，必须在 plcui.init 之前
    local tp_dev = tpg.init(conf.board.tp)
    if not tp_dev then
        log.error("main", "触摸初始化失败，界面将无法操作")
    end

    -- 5. plcui：init → 绑定触摸 → 加载布局
    local ok_init, err_init = plcui.init({ width = conf.W, height = conf.H })
    if not ok_init then
        log.error("main", "plcui.init 失败", tostring(err_init and err_init.code))
    end

    if tp_dev and type(tp_dev) ~= "boolean" then
        local ok_bind, err_bind = plcui.device_bind_touch(tp_dev)
        if not ok_bind then
            log.error("main", "触摸绑定失败", tostring(err_bind and err_bind.code))
        end
    end

    -- 布局、切图、脚本打包后全部平铺在 /luadb 下
    local err_load
    xml, err_load = plcui.load("/luadb/main.xml", { handlers = ui.handlers })
    if not xml then
        log.error("main", "布局加载失败", tostring(err_load and err_load.code),
            tostring(err_load and err_load.message))
        return
    end
    log.info("main", "plcui", plcui.version(), "布局已加载")

    -- 6. 数据采集 + 界面
    ui.bind(xml)
    data.start()
    ui.start()

    -- 7. 首帧出来后再开背光
    sys.wait(100)
    board.backlight_on()

    log.info("main", "启动完成")
end)

sys.run()
