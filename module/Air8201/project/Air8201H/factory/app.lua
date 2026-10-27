--[[
@module  app
@summary 应用主逻辑模块（GNSS 开机常开 + 每30秒上报）
@version 4.0
@date    2026.10.23
@usage
1. 初始化设备硬件和各功能模块（电池/充电/gsensor/远程/低功耗）
2. 开机即打开 GNSS（永久常开），旧设备未激活(-1)强制转为寻宠模式(2)
3. 每 30 秒上报一帧：GNSS 优先（定位方式2），无 fix 回退 LBS 基站定位（定位方式1）
   字段对齐 8780G：信号强度(782)/纬度(513 ASCII %.6f)/经度(512 ASCII %.6f)/
                 定位方式(LOCATION_METHOD INTEGER)/时间戳(1280)/CPU温度(263 FLOAT)
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
local create = require("create")
local exgnss = require("exgnss")
local excloud = require("excloud")

-- 上报周期（秒）
local REPORT_INTERVAL = 30

-- 初始化所有功能模块
local function init_all_modules()
    log.info("app", "开始初始化功能模块")

    kvstore.init()

    -- 初始化电池充电检测
    battery.init()

    local work_mode = kvstore.get_work_mode()
    log.info("app", "当前工作模式:", work_mode)

    -- 传感器/定位先初始化（location.init 内部按 config.BOARD.gnss 完成 exgnss.setup）
    location.init()
    gsensor.init()

    -- 充电管理初始化（YHM2712A；charge.init 内部按 CHARGE_CONFIG.ENABLE/CMD_PIN 守卫，
    -- 8201G 无 CMD 自动跳过，8202/8201H 生效）
    require("charge").init()

    -- LED 状态机（8202 由 active_mode 初始化，该模块已删，此处直接启动）
    require("tools").init_led()

    -- 远程控制按需初始化（收到云平台指令时才生效）
    remote.init()

    log.info("app", "所有功能模块初始化完成")
end

-- 获取CPU温度（单位：摄氏度）
local function get_cpu_temp()
    adc.open(adc.CH_CPU)
    local raw = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    if raw and raw > 0 then
        return raw / 1000
    end
    return nil
end

-- 获取当前定位：GNSS 优先（2），无 fix 回退 LBS 基站定位（1）
-- @return number|nil 纬度
-- @return number|nil 经度
-- @return number|nil 定位方式 2=GPS 1=LBS
local function get_location()
    -- 1. GNSS 已定位
    if exgnss.is_fix() then
        local rmc = exgnss.rmc(2)
        if rmc and rmc.valid and rmc.lat and rmc.lng then
            log.info("app", string.format("GNSS定位: lat=%.6f lng=%.6f", rmc.lat, rmc.lng))
            return rmc.lat, rmc.lng, 2
        end
    end
    -- 2. 回退 LBS 基站定位（location 内部按免费/付费配置处理，含缓存）
    local loc = location.get_lbs_location()
    if loc and loc.lat and loc.lng then
        return loc.lat, loc.lng, 1
    end
    return nil, nil, nil
end

-- 设备唯一标识（官方口径，用于 1293 CUSTOM_DEVICE_ID）：
-- hmeta.devid() 在 4G 模组返回 IMEI；取不到逐级回退，避免上报空值
local function get_device_uid()
    if hmeta and hmeta.devid then
        local ok, v = pcall(hmeta.devid)
        if ok and type(v) == "string" and #v > 0 then return v end
    end
    local imei = mobile.imei()
    if imei and #imei > 0 then return imei end
    return "unknown"
end

-- 构建一帧定位上报 TLV（无定位返回空表，本次不发）
local function build_report_tlv()
    local tlv = {}
    local FM = excloud.FIELD_MEANINGS
    local DT = excloud.DATA_TYPES

    local lat, lng, method = get_location()
    if not (lat and lng) then
        log.warn("app", "GNSS/LBS 均无定位数据，本次不上报")
        return tlv
    end

    -- 必填：设备唯一标识（1293，4G 模组即 IMEI）、项目名称（1294）
    -- 默认 lib 的 excloud 无这两个常量，按官方字段号直接传数字
    table.insert(tlv, { field_meaning = 1293, data_type = DT.ASCII, value = get_device_uid() })
    table.insert(tlv, { field_meaning = 1294, data_type = DT.ASCII, value = PROJECT or "unknown" })
    -- 元器件型号（774）：取 OTP 的 PROD，缺库/未写/读异常兜底 Air8201（对齐 8203 写法）
    local product_model = "Air8201"
    local ok_pm, pm = pcall(require, "prodmeta")
    if ok_pm then
        local okg, p = pcall(pm.get, "PROD")
        if okg and p and #tostring(p) > 0 then product_model = tostring(p) end
    end
    table.insert(tlv, { field_meaning = FM.COMPONENT_MODEL, data_type = DT.ASCII, value = product_model })
    -- 4G信号强度
    local csq = mobile.csq()
    if csq then
        table.insert(tlv, { field_meaning = FM.SIGNAL_STRENGTH_4G, data_type = DT.INTEGER, value = csq })
    end
    -- 经纬度发 ASCII %.6f，绕过 FLOAT ×1000 截断
    table.insert(tlv, { field_meaning = FM.GNSS_LATITUDE, data_type = DT.ASCII, value = string.format("%.6f", lat) })
    table.insert(tlv, { field_meaning = FM.GNSS_LONGITUDE, data_type = DT.ASCII, value = string.format("%.6f", lng) })
    -- 定位方式 2=GPS 1=LBS
    table.insert(tlv, { field_meaning = FM.LOCATION_METHOD, data_type = DT.INTEGER, value = method or 1 })
    -- 时间戳
    table.insert(tlv, { field_meaning = FM.TIMESTAMP, data_type = DT.INTEGER, value = os.time() })
    -- CPU温度
    local cpu_temp = get_cpu_temp()
    if cpu_temp then
        table.insert(tlv, { field_meaning = FM.ENV_TEMPERATURE, data_type = DT.FLOAT, value = cpu_temp })
    end
    return tlv
end

-- 30 秒周期上报任务：等云连接建立后开始，每 30 秒发一帧
local function report_task()
    log.info("app", "等待 AirCloud 连接建立")
    while not create.is_connected() do
        sys.waitUntil("CLOUD_CONNECTED", 1000)
    end
    log.info("app", "AirCloud 已连接，启动 30s 周期上报")
    while true do
        local tlv = build_report_tlv()
        if #tlv > 0 then
            create.send_aircloud(tlv)
            log.info("app", "定位数据已通过 AirCloud TLV 发送")
        end
        sys.wait(REPORT_INTERVAL * 1000)
    end
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

    -- 获取工作模式：未激活(-1)强制转为寻宠模式(2)
    local work_mode = kvstore.get_work_mode()
    if work_mode == config.DEVICE_MODE.UNACTIVATED then
        log.info("app", "未激活模式已禁用，强制进入寻宠模式(GPS定位)")
        kvstore.set_work_mode(config.DEVICE_MODE.FIND)
        work_mode = config.DEVICE_MODE.FIND
    end
    log.info("app", "当前工作模式:", work_mode)

    -- GNSS 永久常开（location.init 已完成 setup，此处直接 open）
    location.start_find_gps()

    -- 启动 30s 周期上报（本款直接供电，不判电量、不切低功耗）
    sys.taskInit(report_task)
end

-- 启动应用
function app.start()
    log.info("app", "启动应用")
    sys.taskInit(app_task)
end

return app
