--[[
@module  config
@summary 配置管理模块（Air8203 工业模组）
@version 0.1（框架版）
@date    2026.09.28

与 8202G 版的差异：
 1. 板级派生字段全部来自 board.profile（单一真相源），本文件不出现板级字面量
 2. 删除 8202/8201 时代的 YHM2712A 充电配置段（8203 用 TP4066，无通信口）
 3. 看门狗配置段改为 BLE 兼任（MS1631C）
 4. 新增 RS485 / 对外数字 IO / 音频 三段配置
]]

local config = {}

-- ==================== 板级配置（唯一真相源） ====================
local board = require("board")
board.init()
local BP = board.profile

-- ==================== 设备模式 ====================
config.DEVICE_MODE = {
    PERFORMANCE = 0,   -- 常规模式
    SMART       = 1,   -- 智能模式
    FIND        = 2,   -- 定位模式（GNSS 常开）
}

-- ==================== 报警阈值 ====================
config.ALARM_THRESHOLD = {
    BATTERY_LOW      = 20,
    BATTERY_CRITICAL = 10,
}

-- ==================== 功耗模式 ====================
config.POWER_MODE = {
    NORMAL     = "normal",     -- 全功率：GNSS / 485 通信可用
    POWER_SAVE = "power_save", -- 低功耗：降低外设功耗，网络保持
    PSM_SLEEP  = "psm_sleep",  -- PSM+：深度休眠（★8203 为工业外电场景，一般不用）
}

-- ==================== 定位配置 ====================
-- 【改动】8203 的 GNSS 是外置 AIR510W（纯 NMEA），冷启动 <35s / 热启动 <1s（【官网】）
-- 超时值按 Air510W 特性给定，与 8202 的内置 GNSS 口径不同
config.LOCATION_CONFIG = {
    GPS_TIMEOUT  = 40,   -- 冷启动余量（Air510W 冷启 <35s）
    LBS_TIMEOUT  = 10,
    WIFI_TIMEOUT = 10,
    CACHE_DURATION = 0,
    MAX_RETRY = 0,
    -- LBS 服务器（可选）：nil = 用合宙官方 lbsLoc2 的默认列表
    --   官方默认（已查证）：{"free.bs.luatos.com", "bs.openluat.com"} —— 双域名容错
    -- iRTU 定制版曾把首选域名写死为 "free.bs.air32.cn"（第二个仍是 bs.openluat.com）。
    -- 如需回退到原域名，在此填 "free.bs.air32.cn"；
    -- ⚠️ 注意 lbsLoc2 的签名只接受**单个** host，填了就失去官方的双域名容错。
    LBS_HOST = nil,
}

-- AirLBS 配置（付费基站 + WiFi 混合定位）
config.AIRLBS_CONFIG = {
    MODE = 0,            -- 0=免费(lbsLoc2 单基站) 1=付费(AirLBS 多基站+WiFi)
    PROJECT_ID  = "",
    PROJECT_KEY = "",
}

-- ==================== 电池配置 ====================
-- ★★ 【已确认 2026-09-28】当前硬件**还不支持读取电池电量信息**，
--    电池功能已整体缩减为"日志打印"（见 modules/battery.lua）。
--    本段配置**暂时保留**，等硬件支持后再启用；期间 battery 模块不读取本段任何字段。
-- 【改动背景】8203 无 YHM2712A，拿不到真实电压/电流/阶段；
--    将来恢复时电压只能来自板级 ADC 分压（【待核】通道与分压比），充电状态靠"电压是否爬升"推断
config.BATTERY_CONFIG = {
    SUPPORTED    = false,  -- ★ 硬件尚不支持，恢复时置 true
    FULL_VOLTAGE = 4200,   -- 满电(mV)
    LOW_VOLTAGE  = 3200,   -- 0% 判定线(mV)
    STATUS_POLL_MS = 30000,
}

-- 低压截止保护
-- ★ 电池数据不可用的当下**必须关闭**：否则一旦出现误判就会走到 pm.shutdown()，
--   而 8203 是工业外电场景，误关机等于设备"消失"。
-- 【改动】8203 无船运模式（没有可通信的充电 IC），恢复后只能软件关机 pm.shutdown()
-- 【待核】若某些批次带电池且长期外电，需确认关机后是否可被 VIN 插拔唤醒
config.BATTERY_EMPTY_PROTECT = {
    ENABLE = false,        -- ★ 电池功能未支持期间保持 false（恢复电池后一并置 true）
    CUTOFF_VOLTAGE_MV = 3200,
    CONFIRM_TIMES = 2,
}

-- 电压可信门控（仅 vbat_internal 电压源需要；ADC 通道不启用，避免误杀缓升真值）
-- ★ 当前未使用（电池功能未支持）
config.BATTERY_RELIABILITY = {
    ENABLE = false,        -- ★ 当前未使用
    CHARGING_MAX_STEP_MV = 400,
    CHARGING_FIRST_READ_MAX_MV = 3900,
}

-- ==================== 低功耗总开关 ====================
-- ★★ 【已确认 2026-09-28】低功耗功能**暂不开启**，设备固定运行在**常规模式**
--    （POWER_MODE.NORMAL / pm.power(pm.WORK_MODE, 0)）。
--    原因：低功耗的档位切换依赖电池状态（低电降档、没电关机），
--    而电池功能尚未支持 → 现在开低功耗只会在无电池数据的情况下乱切档。
--    待电池功能确认好之后再开发低功耗模式（见 lowpower/lowpower_app.lua）。
-- ⚠️ 置 true 前请先确认：modules/battery.lua 已恢复真实数据，
--    且 lowpower_app 的低电降档 / 截止关机逻辑经过实机验证。
config.LOWPOWER_CONFIG = {
    ENABLE = false,
    REASON = "电池功能尚未支持，先固定常规模式",
}

-- ==================== 充电配置（TP4066） ====================
-- ★ 与 8202/8201 的根本差异：TP4066 是纯硬件线性充电 IC
--   · 无可通信接口（非 YHM2712A 的单总线 CMD）
--   · 只有 CHRG/STDBY 两个开漏状态脚，且原理图中用于驱动充电灯
--   → 本工程**不做**充电参数配置，也读不到充电阶段
config.CHARGE_CONFIG = {
    IC = "TP4066",
    ENABLE = false,          -- 无软件可配
    STAGE_CAPABLE = false,   -- 读不到阶段
    -- 充电状态推断：电压在 30s 轮询中持续上升且高于阈值 → 认为在充电
    INFER_BY_VOLTAGE = true,
    INFER_RISE_MV = 30,      -- 相邻两轮电压上升超过该值视为充电中【待标定】
}

-- ==================== 看门狗配置（★ BLE MS1631C 兼任） ====================
-- 【图】原理图第 6 页：主控不按时喂 MS1631C → 它拉高 → 三极管反相 → 拉低主控 RESET_N
-- 【待核】P0：喂狗**物理形式**（专用 GPIO 脉冲 vs 串口 AT 心跳）与超时时长
config.WDT_CONFIG = {
    IMPL = "ble_ms1631c",
    CHIP = "MS1631C",
    ENABLE = false,          -- 【待核】机制确认后置 true
    FEED_PIN = BP.wdt.feed_pin,   -- 【待核】
    FEED_INTERVAL = nil,     -- 【待核】必须显著小于芯片超时（参考 Air153C 经验：超时 240s → 喂狗 180s）
}

-- ==================== RS485 / UART 对外口 ====================
-- ★★ 【已确认 2026-09-28】RS485 **暂不启用**：待明确现场接的是什么 485 设备（协议/波特率/
--    主从角色）之后再开发。本段只打日志提示，**不建串口、不注册任务、不操作方向脚**。
--    实现：config.RS485_CONFIG.ENABLE = false → rs485.init() 只输出一条提示日志后返回。
-- 【图】非隔离版方向脚 = GPIO1；隔离版 = CA-IS2092A（方向脚待核）
config.RS485_CONFIG = {
    ENABLE = false,                   -- ★ 485 功能暂不启用
    VARIANT = BP.rs485.variant,       -- iso485 / rs485 / uart
    UART = BP.rs485.uart,             -- 【待核】
    BAUD = BP.rs485.baud,             -- 【待核】
    DIR_PIN = BP.rs485.dir_pin,       -- 【图】1（GPIO1）
    -- 若采用"自动方向"（SIT3485E 部分型号支持自动收发切换），此处置 false
    DIR_MANUAL = true,
    -- Modbus 从站地址（若启用 Modbus 从站模式）
    MODBUS_SLAVE_ADDR = 1,
}

-- ==================== 对外数字 IO（J100/J101，三极管隔离） ====================
-- 【官网】GPIO22M/WAKEUP2M 为中断输入（湿接点，高电平触发）
--         GPIO28M/GPIO38M 为输出（主控高 → 端子低，**反相**）
config.DIO_CONFIG = {
    ENABLE = true,
    -- DI：中断输入（湿接点）
    DI_PINS = BP.dio.di_int_pins,     -- {22, nil}
    DI_DEBOUNCE_MS = 50,
    -- DO：输出（注意硬件反相！）
    DO_PINS = BP.dio.do_pins,         -- {28, 38}
    DO_INVERT = BP.dio.do_invert,     -- true：set(1) → 端子输出低
    -- 上电初始电平（逻辑值，未反相）
    DO_BOOT_LEVEL = { 0, 0 },
}

-- ==================== 音频（仅 V 系列） ====================
-- 【官网】仅国内版本（Air780EHV）支持 Mic 收音与 Speaker 播放
-- 【图】功放 AW8733，使能 PA_EN = GPIO26
config.AUDIO_CONFIG = {
    SUPPORTED = BP.audio.supported,
    PA_EN_PIN = BP.audio.pa_en_pin,   -- 【图】26
    VOLUME = 80,
}

-- ==================== 硬件引脚（板级派生） ====================
config.HARDWARE_PINS = {
    NET_LED = BP.led.net_pin,   -- 【图】27（网络灯 LED240）
    CHG_LED = BP.led.chg_pin,   -- 【待核】nil = 充电灯由 TP4066 硬件直驱
}

-- 板级配置与型号标识
config.BOARD = BP
config.BOARD_ID = board.id
config.BOARD_SERIES = board.series
config.BOARD_VARIANT = board.variant

-- ==================== 默认网络通道 ====================
-- AirCloud TLV 直发合宙云平台
config.DEFAULT_NETWORK = {
    conf = {
        { "AIRCLOUD", "tcp", 300, 0, 1, "", 0 },
    },
    conf_on = { 1 },
}

-- ==================== 服务端动态配置加载 ====================
--[[
从服务端 parameter_gnss 加载配置。保留 8202G 的"板级能力/引脚红线"原则：
  服务端不得下发改变板级硬件语义的字段（引脚、能力开关）
]]
function config.load_from_server(gnss_cfg, project_key)
    if not gnss_cfg then
        log.info("config", "无服务端配置，使用默认值")
        return
    end

    -- 1. 定位配置
    if gnss_cfg.loc_strategy then
        local ls = gnss_cfg.loc_strategy
        if ls.gps_timeout  then config.LOCATION_CONFIG.GPS_TIMEOUT  = ls.gps_timeout  end
        if ls.lbs_timeout  then config.LOCATION_CONFIG.LBS_TIMEOUT  = ls.lbs_timeout  end
        if ls.wifi_timeout then config.LOCATION_CONFIG.WIFI_TIMEOUT = ls.wifi_timeout end
        if ls.airlbs_mode ~= nil then config.AIRLBS_CONFIG.MODE = ls.airlbs_mode end
        if ls.airlbs_project_id and ls.airlbs_project_id ~= "" then
            config.AIRLBS_CONFIG.PROJECT_ID = ls.airlbs_project_id
        end
        if ls.airlbs_project_key and ls.airlbs_project_key ~= "" then
            config.AIRLBS_CONFIG.PROJECT_KEY = ls.airlbs_project_key
        end
    end

    -- 2. 电池参数（仅电压上下限）
    if gnss_cfg.battery then
        local bt = gnss_cfg.battery
        if bt.full_voltage then config.BATTERY_CONFIG.FULL_VOLTAGE = bt.full_voltage end
        if bt.low_voltage  then config.BATTERY_CONFIG.LOW_VOLTAGE  = bt.low_voltage  end
    end

    -- 3. 报警阈值
    if gnss_cfg.alarm then
        local al = gnss_cfg.alarm
        if al.low_battery_pct then config.ALARM_THRESHOLD.BATTERY_LOW = al.low_battery_pct end
        if al.critical_battery_pct then config.ALARM_THRESHOLD.BATTERY_CRITICAL = al.critical_battery_pct end
    end

    -- 4. ★ 板级红线：以下字段服务端下发一律忽略
    if gnss_cfg.charge and gnss_cfg.charge.enable ~= nil then
        log.warn("config", "本板为 TP4066（无充电 IC 通信能力），忽略服务端 charge.enable")
    end
    if gnss_cfg.wdt then
        if gnss_cfg.wdt.feed_pin then
            log.warn("config", "忽略服务端下发的 wdt.feed_pin（板级引脚由 board.profile 固定）")
        end
        if gnss_cfg.wdt.on ~= nil then
            log.warn("config", "忽略服务端下发的 wdt.on（8203 看门狗由 BLE 芯片兼任，不开放远程开关）")
        end
    end
    if gnss_cfg.rs485 and gnss_cfg.rs485.dir_pin then
        log.warn("config", "忽略服务端下发的 rs485.dir_pin（板级引脚由 board.profile 固定）")
    end

    log.info("config", "服务端配置加载完成")
end

return config
