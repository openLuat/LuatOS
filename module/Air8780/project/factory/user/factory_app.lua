--[[
@module  factory_app
@summary 出厂固件业务编排模块（版本化：TLV上报 / 控制命令 / LED / TTS / GPS / 上报周期）
@version 2.0
@date    2026.09.20
@author  李源龙
@usage
本模块为出厂固件的业务编排模块，版本差异由 factory_config 集中控制：

版本行为：
- 8780  ：硬件I2C传感器 + 180s结构化上报 + 串口透传
- 8780V ：8780基础上 + 每10秒TTS播报"上海合宙欢迎你"
- 8780G ：8780基础上 + 开机打开GPS，每30秒上报GPS（无GPS回退LBS基站定位）
- 8781  ：8780基础上，传感器改软件I2C（GPIO模拟）
- 8782  ：8781基础上，串口1配置为RS485

核心功能：
1、build_report_tlv()：构建 AirCloud 结构化 TLV 上报数据（所有版本通用）
   必填字段：信号强度(782)/设备ID(798)/时间戳(1280)/CPU温度(263)
   可选字段：温度(256)/湿度(257)/VOC(258)（传感器，失败跳过）
            纬度(513)/经度(512)（LBS基站定位，失败跳过）
2、build_gps_tlv()：构建 GPS TLV（仅8780G），GPS失败回退LBS
3、handle_control_command()：处理下行控制命令（tag 19）
   - "cycle:秒数"   → 修改上报频率（最小5秒，fskv持久化，重启生效）
   - "led:blink"    → LED闪烁5秒
   - "led:on"       → LED常亮
   - "led:off"      → LED熄灭
   - "tts:文本"     → TTS播报（仅8780V）
4、start_report_timer()：启动周期结构化上报定时器（默认180秒）
5、TTS/GPS 开机自动启动（按版本启用，见 start_version_features）

数据流向：
- create.aircloudTask 连接成功后 → start_report_timer(uid)
- create.aircloudTask 收到上报事件 → build_report_tlv() → excloud.send
- create.aircloudTask 收到GPS事件 → build_gps_tlv() → excloud.send
- create.aircloudTask 收到tag19命令 → handle_control_command() → CONTROL_RESPONSE

硬件配置（可按实际板子修改）：
- LED控制引脚：LED_PIN=27（高电平点亮）
- 网络状态灯由 iRTU netled 承载（预置配置中已移到 GPIO17，避免与LED冲突）
]]

local factory_app = {}

local excloud = require "excloud"
local lbsLoc2 = require "lbsLoc2"
local sensor_task = require "sensor_task"
-- 版本配置
local factory_config = require "factory_config"

-- ==================== 硬件与参数配置 ====================
local LED_PIN = 27               -- 用户状态LED引脚（高电平点亮，可按板子修改）
local DEFAULT_CYCLE = 180        -- 默认上报频率（秒）
local MIN_CYCLE = 5              -- 最小上报频率（秒）
local REPORT_CYCLE_KEY = "report_cycle"  -- fskv存储key（断电不丢失）
-- 版本默认上报周期（可被 web 端 cycle:N 覆盖）
DEFAULT_CYCLE = factory_config.get_report_cycle() or 180
-- ========================================================

-- fskv初始化（幂等，default.lua 已初始化，此处兜底）
fskv.init()

-- 当前AirCloud通道uid（start_report_timer 时记录，供 cycle 命令重启定时器）
local current_uid = 1
-- 周期上报定时器
local report_timer

-- LED状态与定时器
local led_timer
local led_level = 0

-- ==================== 上报频率管理 ====================

-- 获取当前上报频率（优先读取fskv持久化值，否则默认180秒）
local function get_report_cycle()
    local val = fskv.get(REPORT_CYCLE_KEY)
    if val and type(val) == "number" and val >= MIN_CYCLE then
        return val
    end
    return DEFAULT_CYCLE
end

-- 保存上报频率到fskv
local function set_report_cycle(seconds)
    if type(seconds) ~= "number" or seconds < MIN_CYCLE then
        return false
    end
    fskv.set(REPORT_CYCLE_KEY, seconds)
    log.info("factory_app", "上报频率已保存:", seconds, "秒")
    return true
end

-- 重启周期上报定时器（cycle命令修改频率后调用）
local function restart_report_timer()
    if report_timer then
        sys.timerStop(report_timer)
        report_timer = nil
    end
    local cycle = get_report_cycle()
    report_timer = sys.timerLoopStart(sys.publish, cycle * 1000, "AIRCLOUD_EVENT_" .. current_uid, "report")
    log.info("factory_app", "上报定时器已更新，间隔", cycle, "秒")
end

--[[
启动周期结构化上报定时器（AirCloud连接成功后调用）

@number uid AirCloud通道uid（对应conf配置中的uid字段，默认1）
@usage
factory_app.start_report_timer(uid)
]]
function factory_app.start_report_timer(uid)
    current_uid = uid or 1
    restart_report_timer()
    -- 连接成功后立即触发一次结构化上报
    sys.publish("AIRCLOUD_EVENT_" .. current_uid, "report")
    log.info("factory_app", "结构化上报定时器已启动，uid=", current_uid)
end

-- ==================== 数据采集（必填字段） ====================

-- 获取CPU温度（单位：摄氏度）
local function get_cpu_temp()
    adc.open(adc.CH_CPU)
    local raw = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    if raw and raw > 0 then
        local temp = raw / 1000
        log.info("factory_app", string.format("CPU温度:%.1f℃", temp))
        return temp
    end
    return nil
end

-- 获取LBS基站经纬度（免费单基站定位，失败返回nil）
local function get_lbs()
    mobile.reqCellInfo(15)
    local result = sys.waitUntil("CELL_INFO_UPDATE", 3000)
    if not result then
        log.warn("factory_app", "基站信息扫描超时")
        return nil, nil
    end
    local lat, lng, t = lbsLoc2.request(5000)
    lat, lng = tonumber(lat), tonumber(lng)
    if lat and lng then
        log.info("factory_app", string.format("LBS: lat=%.6f lng=%.6f", lat, lng))
        return lat, lng
    end
    log.warn("factory_app", "未获取到LBS定位信息")
    return nil, nil
end

--[[
构建 AirCloud 结构化 TLV 上报数据

@return table  TLV列表（可直接传给 excloud.send）
@usage
local tlv_list = factory_app.build_report_tlv()
excloud.send(tlv_list, false)
]]
function factory_app.build_report_tlv()
    local tlv_list = {}

    -- 必填：4G信号强度
    local csq = mobile.csq()
    if csq then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = csq
        })
    end
    -- 必填：设备ID（IMEI）
    table.insert(tlv_list, {
        field_meaning = excloud.FIELD_MEANINGS.DEVICE_ID,
        data_type = excloud.DATA_TYPES.ASCII,
        value = mobile.imei()
    })
    -- 必填：时间戳
    table.insert(tlv_list, {
        field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
        data_type = excloud.DATA_TYPES.INTEGER,
        value = os.time()
    })
    -- 必填：CPU温度
    local cpu_temp = get_cpu_temp()
    if cpu_temp then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = cpu_temp
        })
    end
    -- 可选：SHT30 温湿度 / VOC 空气质量（采集失败自动跳过，不影响主数据上报）
    local temp, hum, voc = sensor_task.get_env()
    if temp then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = temp
        })
    end
    if hum then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = hum
        })
    end
    if voc then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.PARTICULATE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = voc
        })
    end
    -- 可选：LBS基站经纬度
    local lat, lng = get_lbs()
    if lat and lng then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = lat
        })
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = lng
        })
    end

    log.info("factory_app", "上报数据:", json.encode(tlv_list))
    return tlv_list
end

-- ==================== GPS 上报（仅8780G，按版本启用） ====================

-- 版本GPS配置
local gps_cfg = factory_config.get_gps()      -- {enable, interval}
local exgnss = nil
local gps_timer = nil

-- 懒加载 exgnss（仅8780G版本使用，避免其他版本报错）
local function get_exgnss()
    if not exgnss then
        local ok, m = pcall(require, "exgnss")
        if ok and m then exgnss = m end
    end
    return exgnss
end

--[[
获取当前定位（GPS优先，失败回退LBS基站定位）

@return number|nil 纬度
@return number|nil 经度
@return number|nil 定位方式：2=GPS，1=LBS
@usage
local lat, lng, method = get_location()
]]
local function get_location()
    -- 1. 尝试GPS
    local gnss = get_exgnss()
    if gnss and gnss.is_fix() then
        local rmc = gnss.rmc(2)
        if rmc and rmc.valid and rmc.lat and rmc.lng then
            log.info("factory_app", string.format("GPS定位: lat=%.6f lng=%.6f", rmc.lat, rmc.lng))
            return rmc.lat, rmc.lng, 2
        end
    end
    -- 2. 回退LBS基站定位
    local lat, lng = get_lbs()
    if lat and lng then
        return lat, lng, 1
    end
    return nil, nil, nil
end

--[[
构建 GPS 上报 TLV（仅8780G）

@return table TLV列表（可直接传给 excloud.send）
@usage
local tlv_list = factory_app.build_gps_tlv()
excloud.send(tlv_list, false)
]]
function factory_app.build_gps_tlv()
    local tlv_list = {}
    local lat, lng, method = get_location()
    if lat and lng then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = lat
        })
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = lng
        })
        -- 定位方式：2=GPS，1=LBS（可选字段）
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.LOCATION_METHOD,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = method or 1
        })
        -- 时间戳
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        })
        log.info("factory_app", "GPS上报:", json.encode(tlv_list))
    else
        log.warn("factory_app", "GPS/LBS均无定位数据，本次不上报")
    end
    return tlv_list
end

-- 启动8780G默认GPS上报（开机即启动，其他版本自动跳过）
local function start_default_gps()
    if not gps_cfg.enable then
        log.info("factory_app", "当前版本不启动GPS上报:", factory_config.get_ver())
        return
    end
    -- 开机直接打开GPS（常开）
    local gnss = get_exgnss()
    if gnss then
        gnss.setup({
            gnssmode = 1,        -- 卫星全定位
            agps_enable = true,  -- AGPS加速定位
            debug = false,
            uart_id = 2,         -- 8780G(Air780EGP) 内置GNSS默认UART2
            uartbaud = 115200,
        })
        gnss.open(gnss.DEFAULT, {tag = "factory_gps"})
        log.info("factory_app", "GPS已打开（常开）")
    else
        log.error("factory_app", "exgnss模块加载失败")
    end
    -- 每30秒发布GPS上报事件
    gps_timer = sys.timerLoopStart(sys.publish, gps_cfg.interval * 1000, "AIRCLOUD_EVENT_" .. current_uid, "gps")
    log.info("factory_app", "GPS上报定时器已启动，间隔", gps_cfg.interval, "秒")
end

-- ==================== LED 控制 ====================

-- LED闪烁切换回调
local function led_toggle()
    led_level = 1 - led_level
    gpio.setup(LED_PIN, led_level)
end

-- 停止LED闪烁定时器
local function led_stop_timer()
    if led_timer then
        sys.timerStop(led_timer)
        led_timer = nil
    end
end

--[[
LED 控制

@string action "on"=常亮, "off"=熄灭, "blink"=闪烁5秒
@return boolean 是否执行成功
@usage
factory_app.led_ctl("blink")
]]
function factory_app.led_ctl(action)
    led_stop_timer()
    if action == "on" then
        led_level = 1
        gpio.setup(LED_PIN, 1)
        log.info("factory_app", "LED常亮")
    elseif action == "off" then
        led_level = 0
        gpio.setup(LED_PIN, 0)
        log.info("factory_app", "LED熄灭")
    elseif action == "blink" then
        led_level = 0
        gpio.setup(LED_PIN, 0)
        -- 闪烁：亮1秒灭1秒，5秒后自动停止
        led_timer = sys.timerLoopStart(led_toggle, 1000)
        sys.timerStart(led_stop_timer, 5000)
        log.info("factory_app", "LED闪烁5秒")
    else
        log.warn("factory_app", "未知LED命令:", action)
        return false
    end
    return true
end

-- ==================== TTS 播报（仅8780V，按版本启用） ====================

-- 版本TTS配置
local tts_cfg = factory_config.get_tts()      -- {enable, text, interval}
local DEFAULT_TTS_TEXT = tts_cfg.text or "上海合宙欢迎你"   -- 开机欢迎播报文本
local audio_inited = false
local boot_tts_done = false

-- 初始化音频（仅 8780V 版本生效，幂等；失败可重试）
local function init_audio()
    if audio_inited then return true end
    if not tts_cfg.enable then
        log.info("factory_app", "当前版本不启用TTS:", factory_config.get_ver())
        return false
    end
    local ok, audio_config = pcall(require, "audio_config")
    if not ok or not audio_config or not audio_config.init then
        log.error("factory_app", "音频模块不可用")
        return false
    end
    local init_ok = audio_config.init()
    if not init_ok then
        log.error("factory_app", "音频初始化失败（ES8311）")
        return false
    end
    audio_inited = true
    log.info("factory_app", "音频初始化完成")
    return true
end

--[[
TTS 语音播报（仅 8780V 版本支持，其他版本返回错误）

@string text 播报文本
@return boolean 是否执行成功
@return string|nil 错误信息
@usage
local ok, err = factory_app.tts("温度正常")
]]
function factory_app.tts(text)
    if not tts_cfg.enable then
        return false, "当前版本不支持TTS"
    end
    if not init_audio() then
        return false, "音频初始化失败"
    end
    local ok, audio_config = pcall(require, "audio_config")
    if not ok or not audio_config or not audio_config.audio_play_tts then
        log.error("factory_app", "音频模块不可用")
        return false, "音频模块不可用"
    end
    audio_config.audio_play_tts(text)
    log.info("factory_app", "TTS播报:", text)
    return true, nil
end

-- 开机播报欢迎语（仅8780V，播一次，网络就绪后执行）
local function start_boot_tts()
    if not tts_cfg.enable then
        log.info("factory_app", "当前版本不启动TTS:", factory_config.get_ver())
        return
    end
    sys.taskInit(function()
        -- 等待网络就绪（TTS云端合成）
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end
        if boot_tts_done then return end
        boot_tts_done = true
        factory_app.tts(DEFAULT_TTS_TEXT)
        log.info("factory_app", "开机欢迎语播报:", DEFAULT_TTS_TEXT)
    end)
end

-- ==================== 下行控制命令处理 ====================

--[[
处理 AirCloud 下行控制命令（tag 19 CONTROL_COMMAND）

支持命令：
- "cycle:秒数"   → 修改上报频率（最小5秒，fskv持久化）
- "led:blink"    → LED闪烁5秒
- "led:on"       → LED常亮
- "led:off"      → LED熄灭
- "tts:文本"     → TTS播报（仅8780V）

@string cmd 控制命令字符串
@return string 响应文本（发送给 CONTROL_RESPONSE tag 20）
@usage
local resp_msg = factory_app.handle_control_command("cycle:60")
]]
function factory_app.handle_control_command(cmd)
    local resp_msg = "命令执行成功"
    if not cmd or cmd == "" then
        return "命令为空"
    end
    -- 1. 设置上报频率
    local cycle_val = cmd:match("^cycle:(%d+)$")
    if cycle_val then
        local seconds = tonumber(cycle_val)
        if seconds and seconds >= MIN_CYCLE then
            set_report_cycle(seconds)
            restart_report_timer()
            log.info("factory_app", "上报频率已修改为", seconds, "秒")
        else
            resp_msg = "无效的上报频率值: " .. cycle_val .. "（最小" .. MIN_CYCLE .. "秒）"
            log.warn("factory_app", resp_msg)
        end
        return resp_msg
    end
    -- 2. LED 控制
    local led_cmd = cmd:match("^led:(%w+)$")
    if led_cmd then
        if led_cmd == "blink" or led_cmd == "on" or led_cmd == "off" then
            factory_app.led_ctl(led_cmd)
            log.info("factory_app", "LED命令:", led_cmd)
        else
            resp_msg = "未知的LED命令: " .. led_cmd
            log.warn("factory_app", resp_msg)
        end
        return resp_msg
    end
    -- 3. TTS 播报
    local tts_text = cmd:match("^tts:(.+)$")
    if tts_text then
        local ok, err = factory_app.tts(tts_text)
        if not ok then
            resp_msg = "TTS执行失败: " .. tostring(err or "")
        end
        return resp_msg
    end
    -- 4. 未知命令
    resp_msg = "未知命令格式: " .. cmd
    log.warn("factory_app", resp_msg)
    return resp_msg
end

-- ==================== 版本特性启动 ====================
-- 按 factory_config.DEVICE_VER 启用对应版本能力：
--   8780V → 开机播报一次欢迎语 + 收到服务器 tts: 命令时播报
--   8780G → 开机开GPS，每30秒GPS上报（无GPS回退LBS）
--   其他版本 → 均自动跳过
start_boot_tts()
start_default_gps()

log.info("factory_app", "版本特性启动完成，当前版本:", factory_config.get_ver())

return factory_app
