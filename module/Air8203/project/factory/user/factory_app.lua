--[[
@module  factory_app
@summary Air8203V 出厂固件业务编排模块（外置 Air510w GNSS 开机即开 / 30s 上报 / LBS兜底）
@version 1.0.0
@date    2026.10.23
@usage
本模块为 Air8203V 出厂固件的业务编排模块，固定单一硬件配置：
- 开机即开外置 Air510w GNSS：UART2/115200，供电脚 GPIO25【高电平开机】
  与官方 Air780EHV+Air510W demo 一致：exgnss.setup 传 gnss_volgpio=25，库内自动拉高供电
- 一条上报通道：每 30s 上报 AirCloud TLV（信号/模组型号/IMEI/时间戳/CPU温度 + 定位）
- GNSS 无定位回退 LBS；不采集 I2C 环境传感器
- TTS 语音播报（仅 Air780EHV，EHM 无音频不初始化）：开机播"设备已启动"、
  GNSS 首次定位成功播"定位成功"、下行 "tts:文本" 远程朗读（ES8311+PA，走 exaudio）

核心功能：
1. build_uplink_tlv()：构建 30s 上报 TLV
   必填：信号(782 INTEGER)/整机型号 PROD，OTP优先空则Air8203(ASCII)/IMEI(798 ASCII)/时间戳(1280 INTEGER)/CPU温度(263 FLOAT)
   定位：纬度(513 ASCII %.6f)/经度(512 ASCII)/方式(1281 INTEGER，2=GNSS 1=LBS)；定位失败只发必填
2. handle_control_command()：下行 tag19
   "cycle:秒数" 改周期(最小5s, fskv持久化)；"led:on/off/blink" 控 GPIO27
3. start_uplink_timer()：AirCloud 连接成功后启动周期定时器

数据流向：
  create.aircloudTask 连上 → start_uplink_timer(uid)
  create.aircloudTask 收上报事件 → build_uplink_tlv() → excloud.send
  create.aircloudTask 收 tag19 → handle_control_command() → tag20 回复

硬件：
  LED 控制脚 GPIO27（高点亮）；网络状态灯由 iRTU netled 承载（预置/factory_config 为 GPIO17，避免冲突）
  UART1 被 exril_5101(9600) 独占、UART2 被 510w(115200) 独占 → main.lua 已置 IRTU_DISABLE_UART1/2
]]

local factory_app = {}

-- excloud / lbsLoc2 仅用于云端 TLV 与 LBS 兜底，绝不能因它们缺失而拖垮开机 GNSS。
-- 用 pcall 软加载：缺库时为 nil，GNSS 自检与开机照常执行（这是"一条 GNSS 日志都没有"的第二条隐患链）
local ok_ec, excloud = pcall(require, "excloud")
if not ok_ec then excloud = nil end
local ok_lbs, lbsLoc2 = pcall(require, "lbsLoc2")
if not ok_lbs then lbsLoc2 = nil end
local factory_config = require "factory_config"
-- prodmeta(OTP)：读取产线写入的整机型号 PROD；缺库/未写时回退默认，不影响开机
local ok_pm, prodmeta = pcall(require, "prodmeta")
if not ok_pm then prodmeta = nil end

-- ==================== 硬件与参数配置 ====================
local LED_PIN = 27
local MIN_CYCLE = 5                          -- 最小上报周期(秒)
local REPORT_CYCLE_KEY = "report_cycle"      -- fskv key
local DEFAULT_CYCLE = factory_config.get_report_cycle() or 30

-- 外置 Air510w GNSS 参数
local GNSS_UART_ID = 2
local GNSS_VOL_PIN = 25          -- 510w 供电开关脚，高电平开机（与官方 demo gnss_volgpio=25 一致）
local GNSS_UART_BAUD = 115200

-- TTS 语音参数（仅 Air780EHV 硬件有 ES8311+功放；Air780EHM 无音频，全程不初始化）
local IS_EHV = (rtos.bsp() == "Air780EHV")
local AUDIO_PA_PIN = 26          -- 音频功放 PA，高电平打开（板级自定义，勿用官方 GPIO22）
local AUDIO_DAC_PIN = 20         -- ES8311 codec 电源脚，Air780EHV 固定 GPIO20
local AUDIO_I2C_ID = 0           -- ES8311 挂 I2C0
-- =====================================================

fskv.init()   -- 幂等（default/main 已初始化，兜底）

local current_uid = 1
local uplink_timer
local led_timer
local led_level = 0

-- ==================== 上报周期管理 ====================
local function get_report_cycle()
    local val = fskv.get(REPORT_CYCLE_KEY)
    if val and type(val) == "number" and val >= MIN_CYCLE then
        return val
    end
    return DEFAULT_CYCLE
end

local function set_report_cycle(seconds)
    if type(seconds) ~= "number" or seconds < MIN_CYCLE then
        return false
    end
    fskv.set(REPORT_CYCLE_KEY, seconds)
    log.info("factory_app", "上报周期已保存:", seconds, "秒")
    return true
end

local function restart_uplink_timer()
    if uplink_timer then
        sys.timerStop(uplink_timer)
        uplink_timer = nil
    end
    local cycle = get_report_cycle()
    uplink_timer = sys.timerLoopStart(sys.publish, cycle * 1000, "AIRCLOUD_EVENT_" .. current_uid, "uplink")
    log.info("factory_app", "上报定时器已更新，间隔", cycle, "秒")
end

--[[
启动周期上报定时器（AirCloud 连接成功后调用）
@number uid AirCloud 通道 uid（默认 1）
]]
function factory_app.start_uplink_timer(uid)
    current_uid = uid or 1
    restart_uplink_timer()
    sys.publish("AIRCLOUD_EVENT_" .. current_uid, "uplink")  -- 连上立即上报一次
    log.info("factory_app", "周期上报定时器已启动, uid=", current_uid)
end

-- ==================== 必填字段采集 ====================
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

-- LBS 基站定位（失败返回 nil）：先等网络就绪，优先 scell，无则扫描，再 lbsLoc2.request
local function get_lbs()
    if not lbsLoc2 then
        log.warn("factory_app", "lbsLoc2 未打进固件，跳过LBS")
        return nil, nil
    end
    local wait_net = 0
    while not socket.adapter(socket.dft()) do
        if wait_net >= 30000 then
            log.warn("factory_app", "等待网络就绪超时，跳过LBS")
            return nil, nil
        end
        sys.waitUntil("IP_READY", 1000)
        wait_net = wait_net + 1000
    end
    local scell = mobile.scell and mobile.scell()
    if not (scell and scell.mcc) then
        local cellinfo = mobile.getCellInfo()
        if not cellinfo or #cellinfo == 0 then
            mobile.reqCellInfo(15)
            sys.waitUntil("CELL_INFO_UPDATE", 5000)
        end
    end
    local lat, lng = lbsLoc2.request(5000)
    lat, lng = tonumber(lat), tonumber(lng)
    if lat and lng then
        log.info("factory_app", string.format("LBS: lat=%.6f lng=%.6f", lat, lng))
        return lat, lng
    end
    log.warn("factory_app", "未获取到LBS定位")
    return nil, nil
end

-- ==================== 定位采集（GNSS 优先，回退 LBS） ====================
local gps_cfg = factory_config.get_gps()
local exgnss = nil

local function get_exgnss()
    if not exgnss then
        local ok, m = pcall(require, "exgnss")
        if ok and m then exgnss = m end
    end
    return exgnss
end

--[[
获取当前定位（GNSS 优先，失败回退 LBS）
@return number|nil 纬度
@return number|nil 经度
@return number|nil 方式：2=GNSS，1=LBS
]]
local function get_location()
    local gnss = get_exgnss()
    local isfix = gnss and gnss.is_fix()
    local rmc = gnss and gnss.rmc(2)
    log.info("factory_app", "[GNSS诊断] is_fix=", isfix,
        "rmc=", rmc and json.encode(rmc) or "nil")
    if isfix and rmc and rmc.valid and rmc.lat and rmc.lng then
        log.info("factory_app", string.format("[定位方式=GNSS(2)] lat=%.6f lng=%.6f", rmc.lat, rmc.lng))
        return rmc.lat, rmc.lng, 2
    end
    local lat, lng = get_lbs()
    if lat and lng then
        log.info("factory_app", string.format("[定位方式=LBS(1)] lat=%.6f lng=%.6f", lat, lng))
        return lat, lng, 1
    end
    return nil, nil, nil
end

--[[
构建 30s 上报 TLV（必填始终发，定位失败跳过位置字段）
@return table TLV 列表
]]
function factory_app.build_uplink_tlv()
    if not excloud then
        log.warn("factory_app", "excloud 未打进固件，无法构建TLV")
        return {}
    end
    local tlv_list = {}

    local csq = mobile.csq()
    if csq then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = csq
        })
    end
    -- 整机型号：优先 OTP 产线写入的 PROD，未写/缺库回退 Air8203
    local product_model = "Air8203"
    if prodmeta then
        local okg, p = pcall(prodmeta.get, "PROD")
        if okg and p and #tostring(p) > 0 then product_model = tostring(p) end
    end
    table.insert(tlv_list, {
        field_meaning = excloud.FIELD_MEANINGS.COMPONENT_MODEL,
        data_type = excloud.DATA_TYPES.ASCII,
        value = product_model
    })
    table.insert(tlv_list, {
        field_meaning = excloud.FIELD_MEANINGS.DEVICE_ID,
        data_type = excloud.DATA_TYPES.ASCII,
        value = mobile.imei()
    })
    table.insert(tlv_list, {
        field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
        data_type = excloud.DATA_TYPES.INTEGER,
        value = os.time()
    })
    local cpu_temp = get_cpu_temp()
    if cpu_temp then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = cpu_temp
        })
    end

    local lat, lng, method = get_location()
    if lat and lng then
        -- ASCII %.6f（约 0.1m，绕过 FLOAT ×1000 截断）
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
            data_type = excloud.DATA_TYPES.ASCII,
            value = string.format("%.6f", lat)
        })
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
            data_type = excloud.DATA_TYPES.ASCII,
            value = string.format("%.6f", lng)
        })
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.LOCATION_METHOD,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = method
        })
        log.info("factory_app", "上报(含定位):", json.encode(tlv_list))
    else
        log.warn("factory_app", "GNSS/LBS均无定位，本次仅上报基础字段")
    end
    return tlv_list
end

-- ==================== 开机默认 GNSS（外置 Air510w） ====================
-- 经真机验证：单独烧录官方 Air780EHV+Air510W demo(single) 可正常定位，其供电由
--   exgnss.setup({gnss_volgpio=25}) 交给库内 fnc_open 执行 gpio.setup(25,1)，
--   即 GPIO25【高电平】= 510w 上电开机。
-- 本函数严格对齐该 demo：只做 setup(gnss_volgpio=25) + open，不手动控制任何 GPIO，
--   不做串口探针（此前误判为反相拉低，等于一直关机，是 0 字节的真正根因）。
local function start_default_gps()
    if not gps_cfg or not gps_cfg.enable then
        log.info("factory_app", "未启用GNSS，跳过启动")
        return
    end
    sys.taskInit(function()
        -- 与官方 Air780EHV + Air510W demo(single/gnss.lua)一致：
        -- gnss_volgpio=25：库内拉高 GPIO25，为外置 Air510W 上电开机。
        -- 本模块不再手动控制 GPIO，也不做串口探针。
        local gnss = get_exgnss()
        if not gnss then
            log.error("factory_app", "exgnss 未打进固件(把 lib/exgnss.lua 一并烧录)，GNSS无法启动")
            return
        end

        gnss.setup({
            gnssmode = 1,            -- 全卫星
            agps_enable = true,      -- AGPS 加速
            debug = true,            -- libgnss.debug(true)，原始 NMEA 直接进 luatools 日志
            uart = GNSS_UART_ID,
            uartbaud = GNSS_UART_BAUD,
            gnss_volgpio = GNSS_VOL_PIN  -- 库内拉高给外挂 510w 供电开机
        })
        gnss.open(gnss.DEFAULT, { tag = "factory_gps" })  -- DEFAULT：一直运行
        log.info("factory_app", "外置 Air510w GNSS 已开机(UART2/115200, GPIO25高供电)，等 GNSS_STATE FIXED")
    end)
end

-- ==================== TTS 语音（仅 Air780EHV） ====================
-- 初始化与产测 factory.lua 同一套硬件参数（ES8311@I2C0 + PA GPIO26 + codec GPIO20）。
-- 统一走 exaudio：play_start(type=1) 朗读中文（本工程固件未含新音频框架库）。
-- 所有播报走单一串行任务，保证云端下发、开机、定位成功三类触发不抢音频、不重叠。
local tts_inited = false
local tts_ready = false
local exaudio_drv = nil

local function audio_init()
    if tts_inited then return tts_ready end
    tts_inited = true
    local ok = pcall(function()
        gpio.setup(AUDIO_PA_PIN, 1)
        gpio.setup(AUDIO_DAC_PIN, 1)
        sys.wait(100)
        exaudio_drv = require "exaudio"
        if not exaudio_drv.setup({
            model = "es8311",
            i2c_id = AUDIO_I2C_ID,
            pa_ctrl = AUDIO_PA_PIN,
            dac_ctrl = AUDIO_DAC_PIN,
            dac_delay = exaudio_drv.DAC_DELAY,
            bits_per_sample = 16
        }) then error("exaudio setup fail") end
    end)
    if ok then
        tts_ready = true
        log.info("factory_app", "[TTS] exaudio + es8311 初始化成功")
    else
        log.error("factory_app", "[TTS] exaudio 初始化失败")
    end
    return tts_ready
end

-- 朗读一段文本（仅中文），内部带超时与停止；成功返回 true
local function speak_once(text)
    if not exaudio_drv then return false end
    local done = false
    local function cb(event)
        if event == exaudio_drv.PLAY_DONE then done = true end
    end
    if not exaudio_drv.play_start({ type = 1, content = text, cbfnc = cb, priority = 1 }) then
        return false
    end
    local wait = 0
    while not done and wait < 20000 do
        sys.wait(100); wait = wait + 100
    end
    if done then return true end
    exaudio_drv.play_stop({ type = 1 })
    return false
end

-- 对外：入队播报（任意上下文可调用）。
-- 关键：用 Lua 表做缓冲队列，table.insert 同步发生、不依赖消息时序；
-- sys.publish 仅用于唤醒消费者。即使消费者正在 speak_once 阻塞播放、
-- 期间 publish 的唤醒被“错过”，数据已在队列里，阻塞结束后仍会被取出，绝不丢播报。
local tts_queue = {}
function factory_app.play_tts(text)
    if not IS_EHV then return false end
    text = text and tostring(text) or ""
    if #text == 0 then return false end
    table.insert(tts_queue, text)
    sys.publish("FACTORY_TTS_WAKE")
    return true
end

-- 串行播报任务：开机延迟→初始化→开机语入队头→循环消费队列（云端/连接/定位）
sys.taskInit(function()
    if not IS_EHV then
        log.info("factory_app", "[TTS] 非EHV(主控=" .. rtos.bsp() .. ")，不启用语音")
        return
    end
    -- 开机语插到队头（用汉字"八二零三"，确保 TTS 逐位朗读）
    table.insert(tts_queue, 1, "八二零三设备已启动")
    sys.wait(2000)  -- 等开机电源/系统稳定再初始化音频，避免与启动抢电
    if not audio_init() then return end
    while true do
        if #tts_queue > 0 then
            local text = table.remove(tts_queue, 1)
            log.info("factory_app", "[TTS] 播报:", text)
            local ok = speak_once(text)
            log.info("factory_app", "[TTS] 播报" .. (ok and "完成" or "失败/超时"))
        else
            -- 队列清空后才挂起等唤醒；唤醒丢失也无妨，因为入队数据不会丢
            sys.waitUntil("FACTORY_TTS_WAKE")
        end
    end
end)

-- GNSS 首次定位成功播报：轮询 exgnss.is_fix，仅在“首次由未定位→定位”时播报一次
sys.taskInit(function()
    if not IS_EHV then return end
    local announced = false
    local was_fix = false
    while true do
        local gnss = get_exgnss()
        local fix = gnss and gnss.is_fix() and true or false
        if fix and not was_fix and not announced then
            announced = true
            factory_app.play_tts("定位成功")
            log.info("factory_app", "[TTS] 已触发首次定位成功播报")
        end
        was_fix = fix
        sys.wait(2000)
    end
end)

-- ==================== LED 控制 ====================
local function led_toggle()
    led_level = 1 - led_level
    gpio.setup(LED_PIN, led_level)
end

local function led_stop_timer()
    if led_timer then
        sys.timerStop(led_timer)
        led_timer = nil
    end
end

--[[
LED 控制
@string action "on"=常亮 "off"=熄灭 "blink"=闪烁5s
@return boolean
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
        led_timer = sys.timerLoopStart(led_toggle, 1000)
        sys.timerStart(led_stop_timer, 5000)
        log.info("factory_app", "LED闪烁5秒")
    else
        log.warn("factory_app", "未知LED命令:", action)
        return false
    end
    return true
end

-- ==================== 下行控制命令处理 ====================
-- hex 字符串 → UTF-8 字符串（用于 ttshex 命令，与官方 factory_ehv 实现一致）
-- @string hex 形如 "e4bda0e5a5bd"
-- @return string|nil UTF-8 文本，hex 非法返回 nil
local function hex_to_str(hex)
    if not hex or #hex == 0 or #hex % 2 ~= 0 then
        return nil
    end
    local t = {}
    for i = 1, #hex, 2 do
        local byte = tonumber(hex:sub(i, i + 1), 16)
        if not byte then return nil end
        t[#t + 1] = string.char(byte)
    end
    return table.concat(t)
end

--[[
处理 AirCloud 下行 tag19 CONTROL_COMMAND
支持：cycle:秒数 / led:on|off|blink / tts:明文 / ttshex:UTF-8十六进制
@string cmd
@return string 响应文本（回 tag20）
]]
function factory_app.handle_control_command(cmd)
    local resp_msg = "命令执行成功"
    if not cmd or cmd == "" then
        return "命令为空"
    end
    -- ttshex: 十六进制 UTF-8（平台默认编码方式），先解码
    local tts_hex = cmd:match("^ttshex:(%x+)$")
    if tts_hex then
        local text = hex_to_str(tts_hex)
        if not text or #text == 0 then
            resp_msg = "ttshex 解析失败: 无效的hex数据"
        elseif not IS_EHV then
            resp_msg = "当前硬件无TTS(主控=" .. rtos.bsp() .. ")"
        elseif factory_app.play_tts(text) then
            resp_msg = "TTS播报已执行"
        else
            resp_msg = "TTS播报失败（音频未就绪）"
        end
        log.info("factory_app", resp_msg, text)
        return resp_msg
    end
    local tts_text = cmd:match("^tts:(.+)$")
    if tts_text then
        if not IS_EHV then
            resp_msg = "当前硬件无TTS(主控=" .. rtos.bsp() .. ")"
        elseif #tts_text == 0 then
            resp_msg = "TTS文本为空"
        elseif factory_app.play_tts(tts_text) then
            resp_msg = "TTS播报已执行"
        else
            resp_msg = "TTS播报失败（音频未就绪）"
        end
        log.info("factory_app", resp_msg)
        return resp_msg
    end
    local cycle_val = cmd:match("^cycle:(%d+)$")
    if cycle_val then
        local seconds = tonumber(cycle_val)
        if seconds and seconds >= MIN_CYCLE then
            set_report_cycle(seconds)
            restart_uplink_timer()
            log.info("factory_app", "上报频率已修改为", seconds, "秒")
        else
            resp_msg = "无效的上报频率值: " .. cycle_val .. "（最小" .. MIN_CYCLE .. "秒）"
            log.warn("factory_app", resp_msg)
        end
        return resp_msg
    end
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
    resp_msg = "未知命令格式: " .. cmd
    log.warn("factory_app", resp_msg)
    return resp_msg
end

-- ==================== 特性启动 ====================
start_default_gps()
log.info("factory_app", "特性启动完成")

return factory_app
