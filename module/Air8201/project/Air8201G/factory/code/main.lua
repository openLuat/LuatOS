--[[
@module  main
@summary Air8201G-IRTU主入口文件
@version 1.2
@date    2026.05.27
@description
    Air8201G定位器项目主入口，负责系统初始化、任务调度和状态管理
    核心功能：4G通信、蓝牙、LBS定位、Gsensor、电源管理（低功耗常驻）、excloud云端通信
    本版本：
      1. 已删除默认/用户配置、FSKV持久化、远程配置合并功能，所有参数硬编码在各模块顶部常量。
      2. 已删除 PSM+ 模式与多模式切换逻辑，仅保留唯一工作模式 MODE1（低功耗常驻），
         软件从启动到运行全程工作在低功耗模式 pm.power(pm.WORK_MODE, 1) 下。
]] --
PROJECT = "Air8201G-Turnkey"
VERSION = "001.000.005"
PRODUCT_KEY = "9TTEMS6YwgpsjV7GE6B6kWyDrOAWMaL9"

log.info("项目信息:", PROJECT, VERSION, PRODUCT_KEY)

-- 模块导入（蓝牙暂时禁用）
local excloud_module = require "excloud_module"
local mygps = require "mygps"
-- local myble = require "myble"
local mypower = require "mypower"
local gsensor = require "gsensor"
local report = require "report"
local excloud = require "excloud"
local global_config = require "global_config"
local ota_manegement = require "ota_manegement"

-- ========== 全局配置/统计模块尽早初始化 ==========
-- 必须在其他模块开始统计计数前完成 FSKV 初始化
-- 内部会读 pm.lastReson() 判断冷启动 vs 软重启，自动决定是否清空 FSKV
global_config.init()
global_config.dump_stats()

-- ========== OTA 远程升级管理（基于 libfota3 + 合宙 iot 平台）==========
-- 自动：libfota3 内置定时器，支持时间戳持久化（跨重启延续）
-- 手动：PWRKEY 短按时立即检查（独立于自动定时器）
ota_manegement.init()

-- SIM 卡热插拔功能，通过gpio中断通过上下边沿电平触发中断
-- 设置防抖，使用wakeup6脚，常量为gpio.WAKEUP6
-- 自己设计其他gpio热插拔只需要替换对应的gpio即可
gpio.debounce(gpio.WAKEUP2, 500)
-- 设置中断触发，拔卡进入飞行模式，插卡进出飞行模式，val值为上升沿或者下降沿触发0/1
local function sim_hot_plug(val)
    if val == 0 then
        log.info("插卡")
        mobile.flymode(0, true)
        mobile.flymode(0, false)
    else
        log.info("拔卡")
        mobile.flymode(0, true)
    end
end

gpio.setup(gpio.WAKEUP2, sim_hot_plug)

-- ========== WAKEUP0 中断：手动触发 GPS 定位 + 上报 ==========
-- 配置：内部上拉 + 下降沿触发 + 200ms 防抖
-- 行为：中断到来时 publish "GPS_TRIGGER_REQ" 全局事件，
--       由 report 模块独立监听 task 负责：强制 GNSS 定位 → 立即上报一次
--       （定位成功上报 lat/lng；定位失败上报 "0.000000,0.000000"）
-- 与 30 分钟 GNSS 节流定时器**完全独立**，每次中断都必触发一次 GNSS+上报。
local WAKEUP0_DEBOUNCE_MS = 200
gpio.debounce(gpio.WAKEUP0, WAKEUP0_DEBOUNCE_MS)
gpio.setup(gpio.WAKEUP0, function()
    sys.publish("GPS_TRIGGER_REQ")
    log.info("MAIN", "WAKEUP0 中断已配置：PULLUP + FALLING + debounce " .. WAKEUP0_DEBOUNCE_MS ..
        "ms → 触发 GPS_TRIGGER_REQ")
end, gpio.PULLUP, gpio.FALLING)

-- 全局状态
local system_state = {
    initialized = false,
    working_mode = "MODE1", -- 唯一工作模式：MODE1（低功耗常驻）
    network_connected = false,
    excloud_connected = false,
    battery_level = 100
}

-- 初始化标志
local init_flags = {
    network_ready = false,
    excloud_ready = false,
    gps_ready = false,
    ble_ready = true,
    gsensor_ready = false,
    power_ready = false
}

-- 系统初始化完成检查
local function check_init_complete()
    for _, v in pairs(init_flags) do
        if not v then
            return false
        end
    end
    return true
end

-- 启动系统
local function start_system()
    log.info("MAIN", "System starting in MODE1 (low-power resident)...")

    -- 启动电源管理（init 内部直接进入低功耗常驻模式）
    mypower.init()
    init_flags.power_ready = true
    log.info("MAIN", "Power management initialized (low-power resident)")

    -- 启动Gsensor
    gsensor.init()
    -- 注册震动回调：发布全局 GSENSOR_MOTION 事件，由 report 任务感知做即时上报
    gsensor.on_vibration(function()
        log.info("MAIN", "震动检测 → publish GSENSOR_MOTION")
        sys.publish("GSENSOR_MOTION")
    end, 2000)
    -- 运动判定超时（参考花生宠物业务逻辑：智能模式无震动 10 秒切换为静止）
    gsensor.set_motion_timeout(10)
    init_flags.gsensor_ready = true
    log.info("MAIN", "Gsensor initialized")

    -- 启动蓝牙（暂时禁用）
    -- myble.init()
    -- init_flags.ble_ready = true
    -- log.info("MAIN", "Bluetooth initialized")

    -- 启动定位服务（v2.0：按需同步调用，不再独立定时定位）
    mygps.init()
    init_flags.gps_ready = true
    log.info("MAIN", "GPS module initialized (LBS+GNSS 按需同步调用模式)")

    -- 开机时单独执行一次 GPS 定位（后台异步，超时 60s，不阻塞其他初始化与上报）
    -- 定位结果写入缓存，后续上报会自动带上；上报本身不强制等待 GPS
    mygps.start_gnss_async()
    log.info("MAIN", "开机 GPS 定位已后台启动（超时 60s，不阻塞上报）")

    -- 不再独立启动 LBS/GNSS 定时循环，由 report 模块在每次上报前按需触发：
    --   - LBS：每次上报前刷新（5min/次）
    --   - GNSS：每 30min 触发一次（后台异步，不阻塞上报）

    -- 等待网络就绪后启动excloud
    sys.taskInit(function()
        while not socket.adapter(socket.dft()) do
            log.warn("MAIN", "Waiting for network...")
            sys.waitUntil("IP_READY", 10000)
        end

        init_flags.network_ready = true
        system_state.network_connected = true
        log.info("MAIN", "Network ready")

        -- 启动excloud
        excloud_module.init()
        init_flags.excloud_ready = true
        log.info("MAIN", "Excloud initialized")

        -- 初始化完成
        system_state.initialized = true
        log.info("MAIN", "System initialization complete")

        -- 启动定时上报任务
        report.start()
        log.info("MAIN", "定时上报已启动")
    end)
end

-- 系统状态查询
function get_system_state()
    return system_state
end

-- excloud消息处理回调
-- 注意：保留命令分支但已不再合并配置；PSM/SEARCH/NORMAL 模式切换全部移除，仅 MODE1 常驻
local function on_excloud_message(data)
    if data and data.tlvs then
        for _, tlv in ipairs(data.tlvs) do
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                local cmd = tlv.value
                log.info("MAIN", "Received control command: " .. cmd)

                if cmd == "UPDATE_CONFIG" then
                    log.warn("MAIN", "UPDATE_CONFIG ignored: 配置持久化已移除")
                elseif cmd == "RESET_FACTORY" then
                    log.warn("MAIN", "RESET_FACTORY received, rebooting...")
                    rtos.reboot()
                elseif cmd == "START_SEARCH" or cmd == "STOP_SEARCH" then
                    log.warn("MAIN", cmd .. " ignored: 仅支持 MODE1 低功耗常驻模式")
                elseif cmd == "GET_STATUS" then
                    -- 远程触发上报，标记 reason=MANUAL（不影响震动冷却期）
                    report.trigger_manual_report()
                end
            elseif tlv.field == excloud.FIELD_MEANINGS.REMOTE_CONFIG then
                log.warn("MAIN", "REMOTE_CONFIG ignored: 远程配置合并已移除, payload=" .. tostring(tlv.value))
            end
        end
    end
end

-- 主任务
sys.taskInit(function()
    -- 启动系统
    start_system()
    -- 配置打开USB功能，可以链接电脑打印日志
    gpio.debounce(gpio.WAKEUP5, 100, 1)
    gpio.setup(gpio.WAKEUP5, function()
        pm.power(pm.USB, 1)
        log.info("MAIN", "Wakeup5 detected")
    end, gpio.PULLUP, gpio.RISING)
    -- 配置关闭USB功能，调试完可以进入低功耗运行
    gpio.debounce(gpio.WAKEUP6, 100, 1)
    gpio.setup(gpio.WAKEUP6, function()
        pm.power(pm.USB, 0)
        log.info("MAIN", "Wakeup6 detected")
    end, gpio.PULLUP, gpio.RISING)

    -- 主循环：仅做电池状态采样
    while true do
        local battery = mypower.get_battery_level()
        system_state.battery_level = battery

        sys.wait(10000)
    end
end)

-- PWRKEY唤醒处理
sys.taskInit(function()
    while true do
        sys.waitUntil("PWRKEY_WAKEUP")
        log.info("MAIN", "PWRKEY wakeup detected")

        -- 上报状态（标记 reason=MANUAL）
        report.trigger_manual_report()
    end
end)

-- 注册excloud消息回调
excloud_module.register_callback(on_excloud_message)

-- 启动系统
sys.run()
