--[[
@module  temp_hum
@summary 485 温湿度传感器（UART2 + SP3485，Modbus RTU 主站）
@version 1.0
@date    2026.10.19
@usage
参数照 Air8300 出厂固件（dtu_rtu/temp_hum_sensor.lua、collect_gateway/temp_hum_sensor.lua）：
    从站 1 / 9600 8N1 / 功能码 0x03（读保持寄存器）
    0x001E = 温度（有符号 16 位，/10.0 ℃）
    0x001F = 湿度（无符号 16 位，/10.0 %RH）
    周期 5 秒读取一次

对外接口
1. temp_hum.get()        → { t = 温度, h = 湿度, ts = 时间戳, online = 在线, err = 错误 }
2. temp_hum.read_once()  → 让后台任务立刻读一次（页面「立即读取」用）
3. temp_hum.get_config() → { slave = 从站, reg = 起始寄存器, baud = 波特率 }

对外消息
1. sys.publish("TEMP_HUM_UPDATE", t, h, ts)   读成功时广播（浮点值）
2. sys.publish("TEMP_HUM_STATUS", online, err) 每次事务后广播状态

硬件（EVB_Air8101 V3.0，见 board_pins.lua）
1. 485_EN = GPIO52：收发器供电，开总线时拉高；
2. 485_RE_DE = GPIO37（pad 70）：高 = 发送，低 = 接收，Lua 手动切；
3. UART2：TX = GPIO31（pad 73）、RX = GPIO30（pad 3）；
4. ⚠️ 板上 485 端子 A/B 与常见设备极性相反，接线要交叉（板 A → 传感器 B）。

方向脚为什么手动切
    从机在整帧收完后 3.5 字符（约 4ms）就开始应答；自动换向要等完延时
    （官方 demo 20ms）才打开接收器，回包会被挡在门外。
    手动时序：拉高 DE → uart.write → 按字节时间等整帧发完 → 拉低 DE 开始收。
]]

local board = require "board_pins"

-- ===== 传感器参数（照 Air8300 出厂固件）=====
local SLAVE_ID   = 1        -- 从站地址（传感器拨码/配置，出厂 1）
local REG_TEMP   = 0x001E   -- 温度寄存器
local REG_COUNT  = 2        -- 连读 2 个：温度 + 湿度
local BAUDRATE   = 9600     -- 传感器出厂 9600 8N1
local POLL_INTERVAL = 5000  -- 读取周期
local TIMEOUT_MS = 500      -- 单笔事务等应答超时

-- ===== 方向脚 / 调试开关 =====
local USE_MANUAL_DE = true
local DIR_DELAY     = 12000  -- 自动换向才用（µs）
local DEBUG_RAW     = true   -- 打印收发原始帧，稳定后可关

local DIR_TX = 1
local DIR_RX = 0

-- ===== 硬件参数（board_pins 为唯一来源，供电脚以 config 为准）=====
local uart_id = board.uart.rs485.id
local dir_pin = board.uart.rs485.dir
local dir_pad = board.rs485.pad_dir
local en_pin  = (((_G.project_config or {}).hw or {}).rs485 or {}).en
                or board.pwr.rs485_en

local M = {}

-- ===== 运行态 =====
local bus_ready = false
local tx_done   = true
local rx_buf    = ""
local online    = false
local last_err  = ""
local temperature, humidity, last_ts
local fail_streak = 0

-- ======================================================================
-- Modbus RTU 底层
-- ======================================================================

local function with_crc(body)
    local crc = crypto.crc16_modbus(body)
    return body .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

local function tohex(s)
    if not s or #s == 0 then return "" end
    return (s:gsub(".", function(c) return string.format("%02X ", c:byte()) end))
end

local function crc_ok(frame)
    if not frame or #frame < 4 then return false end
    local crc = crypto.crc16_modbus(frame:sub(1, -3))
    return crc == (frame:byte(-2) + frame:byte(-1) * 256)
end

local function on_rx(id, len)
    local d = uart.read(id, len)
    if not d or #d == 0 then return end

    local nz = 0
    for i = 1, #d do
        if d:byte(i) ~= 0 then nz = nz + 1 end
    end
    if nz <= 1 then return end

    rx_buf = rx_buf .. d
    if DEBUG_RAW then
        log.info("temp_hum", "RX", #d, tohex(d))
    end
    if #rx_buf > 512 then rx_buf = rx_buf:sub(-256) end
end

local function on_sent(id)
    tx_done = true
end

local function bus_open()
    if bus_ready then return true end

    gpio.setup(en_pin, 1)               -- 485_EN：收发器供电
    sys.wait(20)

    if USE_MANUAL_DE then
        local ok, msg = false, "pins 库不可用"
        if pins and pins.setup and dir_pad then
            ok, msg = pcall(pins.setup, dir_pad, "GPIO37")
        end
        log.info("temp_hum", "方向脚手动模式 pad", dir_pad,
            "pinmux", ok and tostring(msg) or ("失败:" .. tostring(msg)))
        gpio.setup(dir_pin, DIR_RX)
        sys.wait(5)
        uart.setup(uart_id, BAUDRATE, 8, 1, uart.NONE, uart.LSB, 1024)
    else
        uart.setup(uart_id, BAUDRATE, 8, 1, uart.NONE, uart.LSB, 1024,
            dir_pin, DIR_RX, DIR_DELAY)
        log.info("temp_hum", "方向脚内核自动换向 GPIO" .. dir_pin, "延时", DIR_DELAY)
    end

    uart.on(uart_id, "receive", on_rx)
    uart.on(uart_id, "sent", on_sent)

    bus_ready = true
    log.info("temp_hum", "UART" .. uart_id .. " 就绪", BAUDRATE .. " 8N1",
        "从站", SLAVE_ID, "寄存器", string.format("0x%04X", REG_TEMP),
        "DE=GPIO" .. dir_pin, "EN=GPIO" .. en_pin)
    return true
end

local function bus_xfer(frame)
    rx_buf  = ""
    tx_done = false

    if USE_MANUAL_DE then
        gpio.setup(dir_pin, DIR_TX)
        sys.wait(1)
    end

    if DEBUG_RAW then
        log.info("temp_hum", "TX", #frame, tohex(frame))
    end
    uart.write(uart_id, frame)

    local byte_ms = math.ceil(#frame * 10 * 1000 / BAUDRATE)

    if USE_MANUAL_DE then
        -- 至少等满字节时间再切回接收（见文件头说明）
        local waited = 0
        while waited < byte_ms do
            sys.wait(1)
            waited = waited + 1
        end
        local extra = 0
        while not tx_done and extra < 20 do
            sys.wait(1)
            extra = extra + 1
        end
        gpio.setup(dir_pin, DIR_RX)
    else
        local waited = 0
        while not tx_done and waited < byte_ms + 30 do
            sys.wait(2)
            waited = waited + 2
        end
        sys.wait(math.ceil(DIR_DELAY / 1000) + 1)
    end

    return rx_buf
end

--- 0x03 应答：addr + func + 字节数 + 数据 + CRC
--- 同样容忍"丢 CRC 最后一字节"的非标短帧（bc+4 字节即算齐）
local function frame_done(frame, func)
    if not frame or #frame < 5 then return false end
    if frame:byte(1) ~= SLAVE_ID then return false end

    local fc = frame:byte(2) or 0
    if fc == func + 0x80 then return true end
    local bc = frame:byte(3) or 0
    return bc > 0 and #frame >= bc + 4
end

local function transact(body, func)
    local resp   = bus_xfer(with_crc(body))
    local waited = 0
    while not frame_done(resp, func) and waited <= TIMEOUT_MS do
        sys.wait(10)
        waited = waited + 10
        resp   = rx_buf
    end

    if not resp or #resp < 5 then
        return nil, "无应答"
    end
    if resp:byte(1) ~= SLAVE_ID then
        return nil, "地址不符"
    end
    if resp:byte(2) == func + 0x80 then
        return nil, string.format("异常码 %02X", resp:byte(3) or 0)
    end
    if not crc_ok(resp) then
        local bc = resp:byte(3) or 0
        if bc > 0 and #resp == bc + 4 then
            log.warn("temp_hum", "应答少 1 字节（非标），按数据段解析")
            return resp
        end
        return nil, "校验错"
    end
    return resp
end

--- 读 0x001E / 0x001F，解析成温度、湿度
local function read_temp_hum()
    local body = string.char(
        SLAVE_ID, 0x03,
        (REG_TEMP >> 8) & 0xFF, REG_TEMP & 0xFF,
        0x00, REG_COUNT)

    local resp, err = transact(body, 0x03)
    if not resp then return false, err end

    local bc = resp:byte(3) or 0
    if bc < 4 or #resp < 7 then return false, "应答错" end

    local t = (resp:byte(4) << 8) | resp:byte(5)
    local h = (resp:byte(6) << 8) | resp:byte(7)

    -- 温度为有符号 16 位（负温时是补码）
    if t > 0x7FFF then t = t - 0x10000 end

    temperature = t / 10.0
    humidity    = h / 10.0
    last_ts     = os.time()
    return true
end

-- ======================================================================
-- 对外接口 + 后台任务
-- ======================================================================

--- 当前值（未读到过时 t/h 为 nil）
function M.get()
    return {
        t      = temperature,
        h      = humidity,
        ts     = last_ts,
        online = online,
        err    = last_err,
    }
end

--- 让后台任务立刻读一次（页面「立即读取」）
function M.read_once()
    sys.publish("TEMP_HUM_READ")
end

--- 当前配置（页面显示用）
function M.get_config()
    return {
        slave = SLAVE_ID,
        reg   = REG_TEMP,
        baud  = BAUDRATE,
        count = REG_COUNT,
    }
end

local function publish_status()
    sys.publish("TEMP_HUM_STATUS", online, last_err)
end

sys.taskInit(function()
    sys.wait(300)                       -- 先让界面起来
    if not bus_open() then
        log.error("temp_hum", "485 总线打开失败")
        return
    end

    while true do
        local ok, err = read_temp_hum()
        if ok then
            online, last_err, fail_streak = true, "", 0
            log.info("temp_hum", string.format("温度 %.1f ℃，湿度 %.1f %%RH",
                temperature, humidity))
            sys.publish("TEMP_HUM_UPDATE", temperature, humidity, last_ts)
        else
            online = false
            last_err = err or ""
            fail_streak = fail_streak + 1
            -- 日志节流：首次失败 + 之后每 10 次一条
            if fail_streak == 1 or fail_streak % 10 == 0 then
                log.warn("temp_hum", "读取失败", fail_streak, last_err)
            end
        end
        publish_status()

        sys.waitUntil("TEMP_HUM_READ", POLL_INTERVAL)
    end
end)

log.info("temp_hum", "485 温湿度模块加载完成，从站", SLAVE_ID,
    "寄存器", string.format("0x%04X", REG_TEMP), "波特率", BAUDRATE)

return M
