--[[
@module  rs485_reply
@summary 隔离 485 串口应答应用模块（Air8300 / UART1）
@version 1.0
@date    2026.10.27
@author  王城钧
@usage
本功能模块演示的内容为：
1、完成隔离 485 的管脚复用与串口初始化
    - 485 芯片供电脚：物理 PIN18 复用为 GPIO29，并拉高供电
    - 收发方向脚：物理 PIN28 复用为 GPIO37，交由 uart.setup 自动翻转
    - 隔离 485 固定接 UART1，9600 8N1
2、等待串口板发送数据，收到一帧后回复固定内容

注意事项：
1、串口接收回调中不能调用 sys.wait，因此回调只做两件事：缓存收到的数据、
   重启帧间隔定时器；真正的回复动作放在主任务中执行
2、总线静默 frame_gap 毫秒认为一帧接收结束，再执行回复，避免把一帧拆成两次应答
3、rs485_delay 是发送完成后保持发送态的时间（单位 us），9600bps 用 20000，
   改为 115200bps 时应调到 2000 左右，否则回复会变慢甚至丢尾字节
4、方向脚必须使用主控侧普通 GPIO（GPIO0~19、GPIO29~38），
   100 号以上是 WiFi 侧 WGPIO，主控串口硬件无法自动翻转
5、调试接线时可把 heartbeat_enable 置为 true，工控板会每 3 秒主动发送一次 PING，
   用于单独验证"板子 → 电脑"方向是否正常

本文件没有对外接口,直接在 main.lua 中 require "rs485_reply" 就可以加载运行；
]]


-- ============================================================
-- 参数配置
-- ============================================================
local uart_id     = 1                  -- 隔离 485 固定接 UART1
local baud_rate   = 9600               -- 波特率，需与串口板一致
local data_bits   = 8                  -- 数据位
local stop_bits   = 1                  -- 停止位
local dir_pin     = 28                 -- 方向脚物理编号（PIN28）
local dir_gpio    = 37                 -- 方向脚复用功能：GPIO37（高电平发送，低电平接收）
local pwr_pin     = 18                 -- 485 供电脚物理编号（PIN18）
local pwr_gpio    = 29                 -- 485 供电脚复用功能：GPIO29
local rs485_delay = 20000              -- 方向切换延时（us），9600 用 20000，115200 用 2000
local frame_gap   = 100                -- 帧间隔静默判定（ms），总线静默这么久认为一帧结束
local rx_max      = 256                -- 单帧最大缓存长度，超过则整帧丢弃
local reply_data  = "Air8300 OK\r\n"   -- 收到数据后回复的内容

-- 调试开关：true 时每 3 秒主动发送一次心跳，用于验证"板子 → 电脑"方向
local heartbeat_enable = false
local heartbeat_ms     = 3000
local heartbeat_data   = "PING\r\n"

-- 接收缓存
local rx_buf = ""        -- 未处理完的接收数据
local frame_timer = nil  -- 帧间隔定时器


-- 串口接收回调：只缓存数据并重启帧间隔定时器，不做耗时操作
local function uart_receive_cb(id, len)
    local data
    while true do
        data = uart.read(id, 1024)
        if not data or #data == 0 then break end
        -- 超长保护：整帧丢弃，避免回复半个帧
        if #rx_buf + #data > rx_max then
            log.warn("rs485_reply", "单帧超过", rx_max, "字节，丢弃本次数据", #data)
            rx_buf = ""
            return
        end
        rx_buf = rx_buf .. data
    end

    if #rx_buf > 0 then
        -- 还有数据在进来，把"帧结束"的判定时间往后推
        if frame_timer then
            sys.timerStop(frame_timer)
            frame_timer = nil
        end
        frame_timer = sys.timerStart(function()
            frame_timer = nil
            sys.publish("UART_FRAME_DONE")
        end, frame_gap)
    end
end


-- 串口发送完成回调
local function uart_sent_cb(id)
    log.info("rs485_reply", "发送完成")
end


-- ============================================================
-- 硬件初始化
-- ============================================================
-- 1、打开 485 芯片供电（PIN18 -> GPIO29），不拉高则收发器不工作
pins.setup(pwr_pin, "GPIO" .. pwr_gpio)
gpio.setup(pwr_gpio, 1, gpio.PULLUP)

-- 2、方向脚复用（PIN28 默认是 LCD 功能，必须重映射为 GPIO37）
pins.setup(dir_pin, "GPIO" .. dir_gpio)

-- 3、串口初始化：第 8 个参数为 485 方向脚，第 9 个参数为接收态电平，第 10 个参数为方向切换延时
local setup_result = uart.setup(uart_id, baud_rate, data_bits, stop_bits, uart.NONE, uart.LSB,
                                1024, dir_gpio, 0, rs485_delay)
log.info("rs485_reply", "uart.setup", setup_result)

-- 4、清空上电残留数据，注册收发回调
uart.rxClear(uart_id)
uart.on(uart_id, "receive", uart_receive_cb)
uart.on(uart_id, "sent", uart_sent_cb)


-- ============================================================
-- 主任务：收到一帧数据后回复
-- ============================================================
sys.taskInit(function()
    log.info("rs485_reply", "隔离485 初始化完成，等待串口板发送数据")

    while true do
        sys.waitUntil("UART_FRAME_DONE")

        if #rx_buf > 0 then
            local frame = rx_buf
            rx_buf = ""
            log.info("rs485_reply", "收到", #frame, "字节", frame:toHex())

            -- 等总线彻底静默、方向脚回到接收态后再回复
            sys.wait(frame_gap)

            uart.write(uart_id, reply_data)
            log.info("rs485_reply", "回复", reply_data)
        end
    end
end)


-- ============================================================
-- 调试用心跳（默认关闭，排查接线时置为 true）
-- ============================================================
if heartbeat_enable then
    sys.taskInit(function()
        sys.wait(2000)
        while true do
            if #rx_buf == 0 then
                uart.write(uart_id, heartbeat_data)
            end
            log.info("rs485_reply", "心跳发送", heartbeat_data)
            sys.wait(heartbeat_ms)
        end
    end)
end
