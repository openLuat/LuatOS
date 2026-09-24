--[[
@module  uart_app
@summary UART1串口通信模块（通讯控制板 ↔ 高压控制板）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
根据《设备间通信协议文档》实现 UART1 串口通信（Air8301）：
- 下行控制帧（通讯板→高压板）：FE + 数据区(4B) + 校验码(1B)，1000ms 周期发送
- 上行状态帧（高压板→通讯板）：FE + 数据区(5B) + 校验码(1B)，接收解析

硬件说明（Air8301）：
- UART1 为本板 RS485_1 硬件通道（供电 GPIO29，由 board_init 使能）；
- 通信参数按协议约定：9600bps / 8 数据位 / 1 停止位 / 无校验；
- 本板 RS485_1 为**半双工**，收发方向由 RE/DE 脚 GPIO2 控制（高电平=发送，低电平=接收），
  通过 uart.setup 第 8/9/10 参数（rs485_gpio / rs485_level / rs485_delay）启用固件内置
  RS485 自动换向（参考 hardware_test/app/rs485_app.lua）；
  ⚠️ 若不传这些参数，485 收发芯片会始终停留在接收态，表现为"能收不能发"。

订阅消息：
- "UART_SEND_CTRL"：更新控制帧缓存（power, set_voltage），下个 1000ms 周期发送

发布消息：
- "UART_STATUS_UPDATED"：高压板状态更新（voltage, work_status）

对外接口：
- uart_app.set_power(power)      -- 设置开关机状态（1=开机，0=关机）
- uart_app.set_voltage(voltage)  -- 设置目标电压（0~6000）
- uart_app.get_status()          -- 获取最近一次高压板状态（voltage, work_status）
]]

local uart_app = {}
local aircloud_app = require "aircloud_app"

-- UART 配置（协议 5.1：UART1，9600bps，8数据位，1停止位，无校验）
local UART_ID = 1            -- UART1
local UART_BAUD = 9600       -- 波特率
local DATA_BITS = 8          -- 数据位
local STOP_BITS = 1          -- 停止位
local PARITY = uart.NONE     -- 无校验

-- RS485 方向控制（Air8301：RS485_1 的 RE/DE = GPIO2，高电平=发送，低电平=接收）
local RS485_RE_DE_PIN = 2        -- uart.setup 第 8 参数：485 方向控制脚
local RS485_RX_LEVEL = 0         -- 第 9 参数：低电平为接收态（高电平为发送态）
local RS485_TX_DELAY = 20000     -- 第 10 参数：方向切换延时(us)，9600bps 对应 20000us
local UART_RX_BUFF_SIZE = 1024   -- 接收缓冲区大小（uart.setup 第 7 参数）

-- 帧格式常量（协议 4.1/5.1/5.2）
local FRAME_START = 0xFE     -- 起始码
local TX_DATA_LEN = 4        -- 下行数据区长度（Byte1 工作状态 + Byte2-3 设定电压 + Byte4 预留）
local RX_DATA_LEN = 5        -- 上行数据区长度（Byte1-2 实际电压 + Byte3 工作状态 + Byte4-5 预留）
local FRAME_TX_LEN = 1 + TX_DATA_LEN + 1  -- 下行完整帧长度 6
local FRAME_RX_LEN = 1 + RX_DATA_LEN + 1  -- 上行完整帧长度 7

-- 控制帧缓存（协议 5.3.1/7：默认发送 3500，收到平台指令后更新）
local ctrl_power = 0             -- 当前开关机状态（Bit1: 1=设备开机，0=设备关机），默认关机
-- 设定电压（0-6000），默认 3500；从 fskv 读取持久化值（每次开机恢复上次设定）
local ctrl_set_voltage = 3500
local saved_voltage = fskv.get("set_voltage")
if saved_voltage ~= nil and saved_voltage >= 0 and saved_voltage <= 6000 then
    ctrl_set_voltage = saved_voltage
end

-- 高压板状态缓存（协议 5.3.2）
local hv_status = {
    voltage = 0,        -- 实际输出电压（V），由状态帧 Byte1-2 组合
    work_status = 0,    -- 工作状态（1=开机中，0=关机中），由状态帧 Byte3 Bit0
}

-- 接收缓存（处理粘包/半包）
local rx_buf = {}

--[[
计算校验码：起始码 + 数据区累加和，若累加和为 FE 则改为 FF（协议 4.3）

@local
@function calc_check_code
@param data table 数据区字节数组
@return number 校验码
]]
local function calc_check_code(data)
    local sum = FRAME_START
    for i = 1, #data do
        sum = (sum + data[i]) & 0xFF
    end
    if sum == FRAME_START then
        sum = 0xFF
    end
    return sum
end

--[[
组帧并发送控制帧（协议 5.3.1：FE + 工作状态/设定电压 + 校验码）

@local
@function send_ctrl_frame
@return nil
]]
local function send_ctrl_frame()
    -- 数据区：Byte1 工作状态 + Byte2-3 设定电压 + Byte4 预留
    local work_byte = 0x00
    -- Byte1 Bit1：1=设备开机（开关逆变输出，把输出电压设为0V），0=设备关机
    if ctrl_power == 1 then
        work_byte = work_byte | 0x02
    end
    -- Byte2-3 设定电压（0-6000），大端序：高字节在前
    local v = ctrl_set_voltage
    local data = {
        work_byte,
        (v >> 8) & 0xFF,
        v & 0xFF,
        0x00  -- Byte4 预留功能，默认为 0x00
    }
    -- 计算校验码
    local check = calc_check_code(data)
    -- 组帧并发送（uart.write 用于发送 string，uart.tx 仅接受 zbuff 对象）
    local frame = string.char(FRAME_START, data[1], data[2], data[3], data[4], check)
    local written = uart.write(UART_ID, frame)
    -- 发送结果校验：正常返回实际写入字节数（>0）；返回 -1 表示串口未就绪/参数缺失
    -- （Air8000W 上若 uart.setup 缺少 485 方向脚参数，uart.write 会返回 -1）
    if not written or written <= 0 then
        log.warn("uart_app", "控制帧发送失败, uart.write 返回:", tostring(written))
    end
    -- 注：控制帧为 1000ms 周期发送（即使无新指令也周期性重发），不在本处记录运维日志（避免每秒一条过频）；
    --     控制指令的关键日志由 business_app 的 ctrl/local 标签记录（用户操作/指令执行时，低频）
end

--[[
解析高压板状态帧（协议 5.3.2：FE + 实际电压/工作状态 + 校验码）

@local
@function parse_rx_frame
@param frame table 完整帧字节数组（长度 7）
@return nil
]]
local function parse_rx_frame(frame)
    -- 提取数据区
    local data = {}
    for i = 2, 1 + RX_DATA_LEN do
        data[i - 1] = frame[i]
    end
    -- 校验码校验（协议 6.2：校验失败丢弃该帧）
    local check = calc_check_code(data)
    if check ~= frame[FRAME_RX_LEN] then
        log.warn("uart_app", "校验失败，丢弃该帧")
        -- 运维日志（协议 9：通信异常便于运维诊断，仅异常时记录）
        aircloud_app.mtn_log("uart", "状态帧校验失败，丢弃该帧")
        return
    end
    -- 解析（协议 5.3.2）
    local voltage = (data[1] << 8) | data[2]      -- Byte1-2 实际输出电压
    local work_status = data[3] & 0x01            -- Byte3 Bit0：1=设备开机中 0=设备关机中
    hv_status.voltage = voltage
    hv_status.work_status = work_status
    log.info("uart_app", "高压板状态: 电压=" .. voltage .. "V, 工作状态=" .. work_status)
    -- 发布状态更新消息，供业务模块消费
    sys.publish("UART_STATUS_UPDATED", hv_status.voltage, hv_status.work_status)
end

--[[
UART 接收回调：缓存字节并解析完整帧（处理粘包/半包）

@local
@function uart_rx_cb
@param id number UART 端口号
@return nil
]]
local function uart_rx_cb(id)
    local buff = uart.read(id, 1024)
    if buff and #buff > 0 then
        -- 追加到接收缓存
        for i = 1, #buff do
            table.insert(rx_buf, buff:byte(i))
        end
        -- 循环解析完整帧
        while #rx_buf >= FRAME_RX_LEN do
            -- 查找起始码
            local start_idx = nil
            for i = 1, #rx_buf do
                if rx_buf[i] == FRAME_START then
                    start_idx = i
                    break
                end
            end
            -- 未找到起始码，清空缓存等待新数据
            if not start_idx then
                rx_buf = {}
                break
            end
            -- 丢弃起始码之前的无效字节
            if start_idx > 1 then
                for i = 1, start_idx - 1 do
                    table.remove(rx_buf, 1)
                end
            end
            -- 缓存不足一帧，等待更多数据
            if #rx_buf < FRAME_RX_LEN then
                break
            end
            -- 截取完整帧
            local frame = {}
            for i = 1, FRAME_RX_LEN do
                frame[i] = rx_buf[i]
            end
            -- 移除已处理字节
            for i = 1, FRAME_RX_LEN do
                table.remove(rx_buf, 1)
            end
            -- 解析该帧
            parse_rx_frame(frame)
        end
    end
end

--[[
周期发送控制帧任务（协议 5.1/6.1：1000ms 更新输出一次）

@local
@function uart_send_task
@return nil
]]
local function uart_send_task()
    while true do
        send_ctrl_frame()
        sys.wait(1000)
    end
end

-- 设置开关机状态（1=开机，0=关机）
function uart_app.set_power(power)
    ctrl_power = power
    log.info("uart_app", "设置开关机状态: " .. power)
end

-- 设置目标电压（0~6000）
function uart_app.set_voltage(voltage)
    ctrl_set_voltage = voltage
    log.info("uart_app", "设置目标电压: " .. voltage)
end

-- 获取最近一次解析的高压板状态
function uart_app.get_status()
    return hv_status.voltage, hv_status.work_status
end

-- 订阅控制指令消息（更新缓存，下个 1000ms 周期发送）
sys.subscribe("UART_SEND_CTRL", function(power, set_voltage)
    if power ~= nil then
        ctrl_power = power
    end
    if set_voltage ~= nil then
        ctrl_set_voltage = set_voltage
    end
    log.info("uart_app", "收到控制指令: power=" .. tostring(power) .. ", set_voltage=" .. tostring(set_voltage))
end)

-- 初始化 UART1（协议 3.2：UART1，9600bps，8N1）
uart.on(UART_ID, "receive", uart_rx_cb)
local ok
if rtos.bsp() == "PC" then
    -- PC 模拟器：无 RS485 硬件/方向脚，使用基础串口参数（避免 485 相关参数在模拟器上报错）
    ok = uart.setup(UART_ID, UART_BAUD, DATA_BITS, STOP_BITS, PARITY)
    log.info("uart_app", "UART1 初始化(PC 模拟器, 无 RS485 方向控制): ", ok)
else
    -- 第 8/9/10 参数启用固件内置 RS485 自动换向：方向脚 GPIO2、低电平接收、方向切换延时 20000us
    ok = uart.setup(UART_ID, UART_BAUD, DATA_BITS, STOP_BITS, PARITY,
        uart.LSB, UART_RX_BUFF_SIZE, RS485_RE_DE_PIN, RS485_RX_LEVEL, RS485_TX_DELAY)
    log.info("uart_app", "UART1 初始化(RS485 模式, RE/DE=GPIO" .. RS485_RE_DE_PIN .. "): ", ok)
end

-- 启动周期发送任务
sys.taskInit(uart_send_task)

return uart_app
