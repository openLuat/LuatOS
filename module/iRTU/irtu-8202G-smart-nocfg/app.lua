--[[
@module  app
@summary 应用主逻辑模块（支持服务端动态配置）
@version 3.2
@date    2026.07.17
@usage
1. 初始化设备硬件和各功能模块
2. 获取工作模式：旧设备若存储为未激活(-1)，强制转为寻宠模式(2)（绑定流程已废弃）
3. 统一进入已激活模式（active_mode：GNSS 三态策略主循环）
4. 配置由 main.lua 在启动前通过 config.load_from_server() 加载
]]

local app = {}

local kvstore = require("kvstore")
local config = require("config")

-- 导入功能模块
local location = require("location")
local gsensor = require("gsensor")
local remote = require("remote")
local battery = require("battery")
local lowpower_app = require("lowpower_app")

-- 初始化所有功能模块
local function init_all_modules()
    log.info("app", "开始初始化功能模块")

    kvstore.init()

    -- 初始化电池充电检测
    battery.init()

    local work_mode = kvstore.get_work_mode()
    log.info("app", "当前工作模式:", work_mode)

    -- 传感器/定位先初始化
    location.init()
    gsensor.init()

    -- 初始化充电管理（YHM2712A，config.CHARGE_CONFIG 控制是否启用）
    local charge = require("charge")
    if charge and charge.init then charge.init() end

    -- 初始化硬件看门狗（Air153C，config.WDT_CONFIG 控制是否启用）
    local air153c_wdt = require("air153c_wdt")
    if air153c_wdt and air153c_wdt.init then air153c_wdt.init() end

    -- 远程控制按需初始化（收到云平台指令时才生效）
    remote.init()
    lowpower_app.init()

    log.info("app", "所有功能模块初始化完成")
end

-- 应用主任务
local function app_task()
    log.info("app", "开始应用初始化")

    -- 获取唤醒原因
    local a, b, c, d = pm.lastReson()
    local wakeup_reason = "unknown"
    if a == 0 then
        if c == 0 then wakeup_reason = "powerkey"
        elseif c == 3 then wakeup_reason = "software_reboot"
        elseif c == 5 then wakeup_reason = "reset_key"
        elseif c == 6 then wakeup_reason = "exception_reboot"
        elseif c == 8 then wakeup_reason = "watchdog"
        elseif c == 9 then wakeup_reason = "external_reboot"
        elseif c == 10 then wakeup_reason = "charge_power"
        end
    elseif a == 1 then wakeup_reason = "timer_wakeup"
    elseif a == 2 then
        if d == 1 then wakeup_reason = "wakeup0"
        elseif d == 2 then wakeup_reason = "wakeup1"
        elseif d == 4 then wakeup_reason = "wakeup2"
        elseif d == 8 then wakeup_reason = "wakeup3"
        elseif d == 16 then wakeup_reason = "wakeup4"
        elseif d == 32 then wakeup_reason = "wakeup5"
        else wakeup_reason = "wakeup"
        end
    elseif a == 3 then wakeup_reason = "uart_wakeup"
    elseif a == 5 then wakeup_reason = "pwr_key"
    elseif a == 6 then wakeup_reason = "chg_det"
    end
    log.info("app", "唤醒原因:", a, b, c, d, "描述:", wakeup_reason)

    -- Power键监听（仅记录日志）
    if gpio.PWR_KEY then
        gpio.debounce(gpio.PWR_KEY, 200)
        gpio.setup(gpio.PWR_KEY, function()
            log.info("app", "Power键触发, level:", gpio.get(gpio.PWR_KEY))
        end, gpio.PULLUP, gpio.BOTH)
    else
        log.warn("app", "gpio.PWR_KEY不可用，跳过按键监听")
    end

    -- 初始化所有模块
    init_all_modules()

    -- 获取工作模式
    local work_mode = kvstore.get_work_mode()
    log.info("app", "当前工作模式:", work_mode)

    -- ============================================
    -- 未激活绑定窗口已废弃（unactive_mode.lua 已删除）。
    -- 默认开机即进入寻宠模式(GPS定位，mode=2)；
    -- 若旧版本设备存储的为未激活(-1，如云命令 change_mode 误设)，强制转为寻宠模式(2)
    -- ============================================
    if work_mode == config.DEVICE_MODE.UNACTIVATED then
        log.info("app", "未激活模式已禁用，强制进入寻宠模式(GPS定位)")
        kvstore.set_work_mode(config.DEVICE_MODE.FIND)
        work_mode = config.DEVICE_MODE.FIND
    end

    -- 统一进入已激活模式（active_mode：GNSS 三态策略主循环）
    -- 004.000.037 起 require 不再自动启动（create.lua 惰性加载查询 1290 时不应拉起主循环），
    -- 改为显式调用 active_mode.start()
    log.info("app", "进入已激活模式, work_mode:", work_mode)
    local am = require("active_mode")
    am.start()
end

-- 启动应用
function app.start()
    log.info("app", "启动应用")
    sys.taskInit(app_task)
end

return app
