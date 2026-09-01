--[[
@module  config
@summary 配置管理模块（本地静态配置）
@version 2.1
@date    2026.07.17
@usage
本模块的核心功能为：
1. 定义设备工作模式配置
2. 定义上报间隔配置
3. 定义定位优先级配置
4. 定义GPS定位模式配置
5. 定义功耗模式配置
6. 定义 MQTT 服务配置（仅配置，连接由 mqttm 控制）
7. 定义 SIP 对讲配置
8. 定义定位配置
9. 定义充电管理（YHM2712A）/ 看门狗（Air153C）配置
10. 定义硬件引脚定义
]]

local config = {}

-- 设备模式
config.DEVICE_MODE = {
    UNACTIVATED = -1, -- 未激活模式
    PERFORMANCE = 0,   -- 常规模式
    SMART = 1,         -- 智能模式
    FIND = 2           -- GPS定位模式
}

-- 传感器配置（服务端未下发 sensor 时的默认值）
-- 默认开启运动检测（震动 → 运动中 → 使用配置上报间隔），关闭计步
config.SENSOR_CONFIG = {
    MOTION_DETECT_ON = true,   -- 开启运动检测：震动判定为运动中，静止时叠加间隔
    STEP_COUNT_ON = false,     -- 关闭计步上报
    MOTION_COOLDOWN = 600,     -- 震动上报冷却时间（秒）：震动触发立即上报后的防抖期，默认10分钟
}

-- 上报间隔（秒）
config.REPORT_INTERVAL = {
    PERFORMANCE = 300,
    PERFORMANCE_OPTIONS = {60, 300, 600},
    SMART_AWAY_MOVING = 180,
    SMART_AWAY_STATIC = 180,
    SMART_AWAY_STATIC_INCREMENT = 120,
    SMART_AWAY_STATIC_MAX = 660,
    LOW_POWER = 1800,
    UNACTIVATED = 600,
    SHORT = 600,
    CHARGING = 60   -- 充电状态下报间隔（秒），可被服务端覆盖
}
config.DEVICE_RESTART = ""

-- 定位优先级
config.LOCATION_PRIORITY = {
    PERFORMANCE = {"lbs"},
    SMART = {"lbs"},
    FIND = {"gps", "lbs"},
    LOW_POWER = {"lbs"},
    UNACTIVATED = {"lbs"}
}

-- 报警阈值（仅保留已生效的字段）
config.ALARM_THRESHOLD = {
    BATTERY_LOW = 20,
    BATTERY_CRITICAL = 10
}

-- 功耗模式（三种）
config.POWER_MODE = {
    NORMAL = "normal",         -- 正常状态：保持网络长连接，GPS/WiFi 可用
    POWER_SAVE = "power_save", -- 低功耗状态：降低外设功耗，网络保持
    PSM_SLEEP = "psm_sleep"    -- PSM超低功耗：深度休眠，唤醒后重启
}



-- GPS定位模式配置
config.FIND_MODE_CONFIG = {
    REPORT_INTERVAL = 30,       -- 上报间隔（秒）
    PLAY_VOICE_TIMES = 3,       -- 提示音播放次数
    BLE_ADV_OPEN = 1,           -- 是否开启蓝牙广播
}

-- SIP 对讲配置
-- 设备 SIP 账号 = 设备 IMEI，密码 = HuaShengSIP2026
-- 收到 MQTT call 指令后，设备主动拨打 touser 指定的目标
config.SIP_CONFIG = {
    SIP_SERVER_ADDR = "1.13.142.22",
    SIP_SERVER_PORT = 5060,
    SIP_DOMAIN = "1.13.142.22",
    SIP_PASSWORD = "HuaShengSIP2026",
    SIP_TRANSPORT = nil,            -- 由 sip_talk 设置为 exsip.TRANSPORT_UDP
    AUTO_ANSWER = true,             -- 来电自动接听
    DEFAULT_CALL_TARGET = "1002"    -- 默认呼叫目标: 手机/app
}

-- 定位配置
config.LOCATION_CONFIG = {
    GPS_TIMEOUT = 35,
    LBS_TIMEOUT = 10,
    WIFI_TIMEOUT = 10,
    CACHE_DURATION = 0,
    MAX_RETRY = 0,
}

-- AirLBS 配置（付费基站+WiFi混合定位）
-- mode: 0=免费(lbsLoc2单基站), 1=付费(AirLBS多基站+WiFi)
config.AIRLBS_CONFIG = {
    MODE = 0,                       -- 默认免费
    PROJECT_ID = "",                -- 付费模式时，合宙云平台项目ID
    PROJECT_KEY = ""                -- 付费模式时，合宙云平台项目密钥
}

-- 电池配置
-- 电压/电量数据源：YHM2712A 充电IC（exs_yhm2712a.status()），由 battery 模块后台轮询
config.BATTERY_CONFIG = {
    FULL_VOLTAGE = 4200,           -- 满电电压(mV)，电量线性折算上限
    LOW_VOLTAGE = 3300,            -- 低电电压(mV)，电量线性折算下限
    STATUS_POLL_MS = 30000,        -- 充电IC状态轮询间隔(ms)，充电器插拔检测延迟上限
    -- 以下为旧 ADC 直采方案的参数，现已停用，仅保留兼容
    COMPENSATE = 140,              -- 补偿电压(mV)，已停用
    DIVIDER_R1 = 1000,             -- 分压R1(kΩ)，已停用
    DIVIDER_R2 = 300,              -- 分压R2(kΩ)，已停用
    ADC_SAMPLE_COUNT = 5,          -- ADC采样次数，已停用
    ADC_SAMPLE_INTERVAL = 10,      -- ADC采样间隔(ms)，已停用
}

-- 充电管理配置（YHM2712A）
-- 注意：CMD(STACMD)引脚不能持续拉低超过14.4s，否则芯片触发硬件复位（关闭SYS电源200ms导致主控重启）。
--       扩展库已内置 CMD 空闲保持高电平处理（cmd_idle），每次通信后自动恢复，正常使用无风险。
-- 默认配置参考官方示例（osapi/ext/charger/exs_yhm2712a/ 2.1 + 同事示例 yhm2712a_app）：CMD=GPIO25，电池4.2V
-- 容量2000mAh：芯片库电流表最高只到1000mAh档（math.min 钳制），取 DEFAULT 档=500mA（0.25C，约5h充满，保守稳妥）
config.CHARGE_CONFIG = {
    ENABLE = true,                 -- 是否启用充电管理（默认开启）
    CMD_PIN = 25,                  -- YHM2712A CMD 引脚（STACMD 单线通信）
    FLOAT_VOLTAGE_MV = 4200,       -- 浮充电压(mV)：4200=4.2V / 4350=4.35V
    CAP_BATTERY_MAH = 2000,        -- 电池容量(mAh)：2000（实际装机容量）
    I_CHARGE = "DEFAULT",          -- 充电电流档位：MIN / DEFAULT / MAX（2000mAh 实际取 1000 档 DEFAULT=500mA）
}

-- 看门狗配置（Air153C 硬件看门狗）
-- 硬件接线：AGPIO24 → NPN → WTDOG（见 exair153x_wdt 库注释）
-- 默认开启：喂狗 GPIO24，周期 180 秒（Air153C 超时固定 240s，喂狗周期需 >150s）
config.WDT_CONFIG = {
    ENABLE = true,                 -- 是否启用看门狗（默认开启）
    FEED_PIN = 24,                 -- 喂狗引脚（AGPIO24 → NPN → WTDOG）
    FEED_INTERVAL = 180,           -- 喂狗间隔(秒)，需大于150
}

-- 硬件引脚定义
config.HARDWARE_PINS = {
    VBUS_PIN = 38,
    GREEN_LED = 26,      -- 绿灯 GPIO26（充满常亮 / GPS定位模式慢闪）
    YELLOW_LED = 27,     -- 黄灯 GPIO27（充电中常亮）
    I2C1_PULLUP = 28,
    V_BCKP = 24,
    NS2520_POWER = 26,
    AUDIO_POWER = 2,
    PA_POWER = 25,
    BLE_POWER = 27,
    GNSS_POWER = 21,
    GSENSOR_INT = 20
}

-- 默认网络通道配置（无服务端持久化配置时使用，见 main.lua）
-- 通道1 = AirCloud：TLV 直发合宙云平台，conf_on[1]=1 表示启用
-- 通道格式与 create.lua 的 connect 分发保持一致：{类型, prot, keepAlive, timeout, uid, ssl, qos}
config.DEFAULT_NETWORK = {
    conf = {
        {"AIRCLOUD", "tcp", 300, 0, 1, "", 0},  -- 通道1：AirCloud
    },
    conf_on = {1},
}

-- ==================== 服务端动态配置加载 ====================

--[[
从服务端 parameter_gnss 加载配置，覆盖默认值
@param gnss_cfg table  parameter_gnss 数据
@param project_key string|nil  MQTT project_key
]]
function config.load_from_server(gnss_cfg, project_key)
    if not gnss_cfg then
        log.info("config", "无服务端配置，使用默认值")
        return
    end
    log.info("config", "从服务端加载配置")

    -- 1. work_mode → 上报间隔
    if gnss_cfg.work_mode then
        local wm = gnss_cfg.work_mode
        if wm.normal_interval then config.REPORT_INTERVAL.PERFORMANCE = wm.normal_interval end
        if wm.smart_interval then
            config.REPORT_INTERVAL.SMART_AWAY_MOVING = wm.smart_interval
            config.REPORT_INTERVAL.SMART_AWAY_STATIC = wm.smart_interval
        end
        if wm.emergency_interval then config.FIND_MODE_CONFIG.REPORT_INTERVAL = wm.emergency_interval end
        if wm.inactive_interval then config.REPORT_INTERVAL.UNACTIVATED = wm.inactive_interval end
        if wm.low_battery_interval then config.REPORT_INTERVAL.LOW_POWER = wm.low_battery_interval end
        if wm.charging_interval then config.REPORT_INTERVAL.CHARGING = wm.charging_interval end
    end

    -- 2. loc_strategy → 定位配置（含AirLBS）
    if gnss_cfg.loc_strategy then
        local ls = gnss_cfg.loc_strategy
        if ls.gps_timeout then config.LOCATION_CONFIG.GPS_TIMEOUT = ls.gps_timeout end
        if ls.wifi_timeout then config.LOCATION_CONFIG.WIFI_TIMEOUT = ls.wifi_timeout end
        if ls.lbs_timeout then config.LOCATION_CONFIG.LBS_TIMEOUT = ls.lbs_timeout end
        if ls.cache_duration then config.LOCATION_CONFIG.CACHE_DURATION = ls.cache_duration end
        if ls.max_retry then config.LOCATION_CONFIG.MAX_RETRY = ls.max_retry end
        -- AirLBS 配置（平铺在 loc_strategy 下）
        if ls.airlbs_mode ~= nil then config.AIRLBS_CONFIG.MODE = ls.airlbs_mode end
        if ls.airlbs_project_id and ls.airlbs_project_id ~= "" then config.AIRLBS_CONFIG.PROJECT_ID = ls.airlbs_project_id end
        if ls.airlbs_project_key and ls.airlbs_project_key ~= "" then config.AIRLBS_CONFIG.PROJECT_KEY = ls.airlbs_project_key end
        if ls.airlbs_mode ~= nil then
            log.info("config", "AirLBS配置:", "mode=" .. config.AIRLBS_CONFIG.MODE,
                "project_id=" .. (config.AIRLBS_CONFIG.PROJECT_ID or ""))
        end
    end

    -- 3. emergency → GPS定位模式配置
    if gnss_cfg.emergency then
        local em = gnss_cfg.emergency
        if em.play_voice_count then config.FIND_MODE_CONFIG.PLAY_VOICE_TIMES = em.play_voice_count end
        if em.report_interval then config.FIND_MODE_CONFIG.REPORT_INTERVAL = em.report_interval end
    end

    -- 4. battery → 电池参数
    if gnss_cfg.battery then
        local bt = gnss_cfg.battery
        config.BATTERY_CONFIG = config.BATTERY_CONFIG or {}
        if bt.full_voltage then config.BATTERY_CONFIG.FULL_VOLTAGE = bt.full_voltage end
        if bt.low_voltage then config.BATTERY_CONFIG.LOW_VOLTAGE = bt.low_voltage end
        if bt.compensate_voltage then config.BATTERY_CONFIG.COMPENSATE = bt.compensate_voltage end
        if bt.adc_sample_count then config.BATTERY_CONFIG.ADC_SAMPLE_COUNT = bt.adc_sample_count end
        if bt.adc_sample_interval then config.BATTERY_CONFIG.ADC_SAMPLE_INTERVAL = bt.adc_sample_interval end
        if bt.divider_r1 and bt.divider_r2 then
            config.BATTERY_CONFIG.DIVIDER_R1 = bt.divider_r1
            config.BATTERY_CONFIG.DIVIDER_R2 = bt.divider_r2
        end
    end

    -- 5. charge → 充电管理配置（YHM2712A）
    if gnss_cfg.charge then
        local ch = gnss_cfg.charge
        config.CHARGE_CONFIG = config.CHARGE_CONFIG or {}
        if ch.enable ~= nil then config.CHARGE_CONFIG.ENABLE = ch.enable == 1 end
        if ch.cmd_pin then
            local pin = ch.cmd_pin
            if type(pin) == "string" then
                pin = tonumber(pin:match("gpio(%d+)") or pin:match("(%d+)"))
            end
            config.CHARGE_CONFIG.CMD_PIN = tonumber(pin)
        end
        if ch.v_battery and ch.v_battery > 0 then config.CHARGE_CONFIG.FLOAT_VOLTAGE_MV = ch.v_battery end
        if ch.cap_battery and ch.cap_battery > 0 then
            -- 电池容量校验：与固件默认保持一致（2000mAh），避免网页端下发其他容量导致电流档异常
            local cap = tonumber(ch.cap_battery)
            if cap ~= 2000 then
                log.warn("config", "充电容量", cap, "mAh 与固件默认(2000mAh)不一致，已按固件默认处理")
                cap = 2000
            end
            config.CHARGE_CONFIG.CAP_BATTERY_MAH = cap
        end
        if ch.i_charge then config.CHARGE_CONFIG.I_CHARGE = ch.i_charge end
        log.info("config", "充电管理配置: enable=" .. tostring(config.CHARGE_CONFIG.ENABLE),
            " cmd_pin=" .. tostring(config.CHARGE_CONFIG.CMD_PIN),
            " v_battery=" .. tostring(config.CHARGE_CONFIG.FLOAT_VOLTAGE_MV),
            " cap_battery=" .. tostring(config.CHARGE_CONFIG.CAP_BATTERY_MAH))
    end

    -- 6. wdt → 看门狗配置（Air153C）
    if gnss_cfg.wdt then
        local wdt = gnss_cfg.wdt
        config.WDT_CONFIG = config.WDT_CONFIG or {}
        if wdt.on ~= nil then config.WDT_CONFIG.ENABLE = wdt.on == 1 end
        if wdt.feed_pin then
            local pin = wdt.feed_pin
            if type(pin) == "string" then
                pin = tonumber(pin:match("gpio(%d+)") or pin:match("(%d+)"))
            end
            config.WDT_CONFIG.FEED_PIN = tonumber(pin)
        end
        if wdt.feed_interval and tonumber(wdt.feed_interval) then
            config.WDT_CONFIG.FEED_INTERVAL = tonumber(wdt.feed_interval)
        end
        log.info("config", "看门狗配置: enable=" .. tostring(config.WDT_CONFIG.ENABLE),
            " feed_pin=" .. tostring(config.WDT_CONFIG.FEED_PIN),
            " interval=" .. tostring(config.WDT_CONFIG.FEED_INTERVAL))
    end

    -- 7. alarm → 报警阈值（仅保留已生效的字段）
    if gnss_cfg.alarm then
        local al = gnss_cfg.alarm
        if al.low_battery_pct then config.ALARM_THRESHOLD.BATTERY_LOW = al.low_battery_pct end
        if al.critical_battery_pct then config.ALARM_THRESHOLD.BATTERY_CRITICAL = al.critical_battery_pct end
    end

    -- 8. audio → 音频配置
    if gnss_cfg.audio then
        config.AUDIO_CONFIG = config.AUDIO_CONFIG or {}
        if gnss_cfg.audio.default_volume then config.AUDIO_CONFIG.DEFAULT_VOLUME = gnss_cfg.audio.default_volume end
    end

    -- 9. ble → 蓝牙配置
    if gnss_cfg.ble then
        config.BLE_CONFIG = gnss_cfg.ble
    end

    -- 10. sensor → 传感器配置
    if gnss_cfg.sensor then
        local sensor = gnss_cfg.sensor
        config.SENSOR_CONFIG = sensor
        if sensor.motion_detect_on ~= nil then
            config.SENSOR_CONFIG.MOTION_DETECT_ON = sensor.motion_detect_on == 1
        end
        if sensor.step_count_on ~= nil then
            config.SENSOR_CONFIG.STEP_COUNT_ON = sensor.step_count_on == 1
        end
        -- 震动上报冷却时间（秒）：震动触发立即上报后的防抖期，默认600秒=10分钟
        if sensor.motion_cooldown ~= nil and tonumber(sensor.motion_cooldown) and tonumber(sensor.motion_cooldown) > 0 then
            config.SENSOR_CONFIG.MOTION_COOLDOWN = tonumber(sensor.motion_cooldown)
        end
        log.info("config", "sensor配置: motion_detect_on=", config.SENSOR_CONFIG.MOTION_DETECT_ON,
                          "motion_cooldown=", config.SENSOR_CONFIG.MOTION_COOLDOWN)
    end

    -- 11. sip → SIP 对讲配置
    if gnss_cfg.sip then
        local sip = gnss_cfg.sip
        if sip.server and sip.server ~= "" then config.SIP_CONFIG.SIP_SERVER_ADDR = sip.server end
        if sip.port and sip.port ~= 0 then config.SIP_CONFIG.SIP_SERVER_PORT = sip.port end
        if sip.domain and sip.domain ~= "" then config.SIP_CONFIG.SIP_DOMAIN = sip.domain end
        if sip.password and sip.password ~= "" then config.SIP_CONFIG.SIP_PASSWORD = sip.password end
        if sip.auto_answer ~= nil then config.SIP_CONFIG.AUTO_ANSWER = sip.auto_answer == 1 end
        if sip.default_target and sip.default_target ~= "" then config.SIP_CONFIG.DEFAULT_CALL_TARGET = sip.default_target end
    end

    -- 12. project_key → MQTT 认证密钥（已迁移，保留字段兼容旧配置）
    if project_key then
        log.info("config", "收到 project_key，已忽略:", project_key)
    end

    log.info("config", "服务端配置加载完成")
end

return config
