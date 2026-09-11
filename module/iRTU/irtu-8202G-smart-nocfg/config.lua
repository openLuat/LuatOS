--[[
@module  config
@summary 配置管理模块（本地静态配置）
@version 2.1
@date    2026.07.17
@usage
本模块的核心功能为：
1. 定义设备工作模式 / 功耗模式 / 报警阈值配置
2. 定义定位（GPS/LBS/AirLBS）与超时配置
3. 定义充电管理（YHM2712A）/ 看门狗（Air153C）配置
4. 定义硬件引脚（仅保留 LED：GPIO26 绿 / GPIO27 黄）
5. load_from_server() 处理服务端下发配置（已停用功能字段直接忽略）
004.000.030 清理：删除上报间隔表（GNSS 三态固定节奏替代）、定位优先级（旧按模式
定位链遗留）、FIND_MODE/SIP/传感器/DEVICE_RESTART 等无读取方配置。
]]

local config = {}

-- 设备模式
config.DEVICE_MODE = {
    UNACTIVATED = -1, -- 未激活模式
    PERFORMANCE = 0,   -- 常规模式
    SMART = 1,         -- 智能模式
    FIND = 2           -- GPS定位模式
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
    LOW_VOLTAGE = 3200,            -- 低电电压(mV)，电量线性折算下限（=0% 判定线，与低压截止保护一致）
    STATUS_POLL_MS = 30000,        -- 充电IC状态轮询间隔(ms)，充电器插拔检测延迟上限
}

-- 电池低压截止保护（V004.000.039 新增）
-- 语义：未充电 且 电池电压 ≤ CUTOFF_VOLTAGE_MV，连续 CONFIRM_TIMES 次确认（每次 60s 监测）后判定"没电"，
--       由 lowpower_app 执行 YHM2712A 船运模式：电池 FET 断开（~150nA）→ SYS 掉电主控关机，
--       USB 插入充电后芯片自动退出船运恢复供电开机。
-- 背景：历史版本无低压保护，电压被深放至 2.4V 仍持续运行上报，存在电池过放损坏风险。
config.BATTERY_EMPTY_PROTECT = {
    ENABLE = true,               -- 是否启用低压截止保护
    CUTOFF_VOLTAGE_MV = 3200,    -- 没电判定电压(mV)，即电池最低工作电压限制 3.2V
    CONFIRM_TIMES = 2,           -- 连续确认次数（battery_monitor_task 每 60s 检测一次）
}

-- 电池电压可信门控（V004.000.040 新增）
-- 背景：VBAT 系统轨在充电器在位时会被 YHM2712A 抬升（驱动注释 Vsys≈1.03×Vreg≈4.12V），
--       除以折算系数后仍可能产生 4.12V 假值污染上报；预充/涓流阶段不测压又会把脏值保留续传。
-- 机制：battery 模块以"最近可信基准"限制充电中电压单步跳变，拒绝系统轨污染，仅接受缓升真值。
config.BATTERY_RELIABILITY = {
    ENABLE = true,                -- 是否启用充电中电压可信门控
    CHARGING_MAX_STEP_MV = 400,   -- 充电中相对可信基准允许的最大单步变化(mV)（缓充每30s增量远小于此）
    CHARGING_FIRST_READ_MAX_MV = 3900, -- 无可信基准时充电首采的合理电压上限（>此值判系统轨污染）
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

-- 硬件引脚定义（仅保留存活项：LED；其余引脚配置由各驱动/库内部自行管理）
config.HARDWARE_PINS = {
    GREEN_LED = 26,      -- 绿灯 GPIO26（不充电亮灯场景）
    YELLOW_LED = 27,     -- 黄灯 GPIO27（充电中亮灯场景）
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

    -- 1. loc_strategy → 定位配置（含AirLBS）
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

    -- 2. battery → 电池参数（仅电压上下限；旧 ADC 直采字段 compensate_voltage/
    --    divider/adc_sample_* 已停用，服务端即使下发也忽略）
    if gnss_cfg.battery then
        local bt = gnss_cfg.battery
        config.BATTERY_CONFIG = config.BATTERY_CONFIG or {}
        if bt.full_voltage then config.BATTERY_CONFIG.FULL_VOLTAGE = bt.full_voltage end
        if bt.low_voltage then config.BATTERY_CONFIG.LOW_VOLTAGE = bt.low_voltage end
    end

    -- 3. charge → 充电管理配置（YHM2712A）
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

    -- 4. wdt → 看门狗配置（Air153C）
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

    -- 5. alarm → 报警阈值（仅保留已生效的字段）
    if gnss_cfg.alarm then
        local al = gnss_cfg.alarm
        if al.low_battery_pct then config.ALARM_THRESHOLD.BATTERY_LOW = al.low_battery_pct end
        if al.critical_battery_pct then config.ALARM_THRESHOLD.BATTERY_CRITICAL = al.critical_battery_pct end
    end

    -- 6. project_key → MQTT 认证密钥（已迁移，仅提示不处理）
    if project_key then
        log.info("config", "收到 project_key，已忽略:", project_key)
    end

    log.info("config", "服务端配置加载完成")
end

return config
