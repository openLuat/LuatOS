--[[
@module  relay_ctrl
@summary 继电器控制模块（隔离口 UART1）
@version 1.1
@date    2026.09.20
@usage
本功能模块演示的内容为：
1、在隔离485（UART1）上以 Modbus RTU 主站模式控制 4 路继电器模块（从站地址1）
2、封装继电器单路开/关/翻转、全量开/关、状态回读命令
3、通道编号 0~3，与 Modbus 线圈地址 0x0000~0x0003 一一对应
4、风扇=通道0、LED=通道1，通道2/3 预留


对外接口：
1、relay_ctrl.open(channel)      → 打开指定通道（0~3）
2、relay_ctrl.close(channel)     → 关闭指定通道
3、relay_ctrl.toggle(channel)    → 翻转指定通道
4、relay_ctrl.all_open()         → 全开 4 路
5、relay_ctrl.all_close()        → 全关 4 路
6、relay_ctrl.read_status()      → 回读继电器状态并广播
7、relay_ctrl.get_channel_count()→ 获取当前继电器路数（唯一配置源，供其他模块查询）
]]

local exmodbus = require "exmodbus"
local comm_core = require "comm_core"
local M = {}

-- 隔离485对应 UART1，管脚方向脚 GPIO37
pins.setup(28, "GPIO37")        -- 隔离485 方向脚复用（UART1）
-- 说明：RS485 芯片电源脚（GPIO29）的引脚复用与拉高已统一由 net_drv 初始化，避免多处重复 setup

-- RS485 方向引脚（隔离口）
local rs485_dir_gpio = 37

-- 创建 RTU 主站配置参数（UART1 / 隔离485）
local create_config = {
    mode = exmodbus.RTU_MASTER,      -- 通信模式：RTU主站
    uart_id = 1,                     -- UART 端口号：1（隔离485）
    baud_rate = 9600,                -- 波特率：9600
    data_bits = 8,                   -- 数据位：8
    stop_bits = 1,                   -- 停止位：1
    parity_bits = uart.None,         -- 校验位：无
    byte_order = uart.LSB,           -- 字节顺序：LSB（低位优先）
    rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚：37
    rs485_dir_rx_level = 0,          -- RS485 接收方向电平：0
    concat_timeout = 100,            -- 字符拼接超时时间：100 毫秒
}

-- 从站地址（继电器模块，按用户确认使用 01）
local SLAVE_ID = 1
-- ==================== 唯一配置源：继电器路数 ====================
-- 换硬件时"只改这一处"：4 路模块填 4，8 路模块填 8。
-- 状态缓存、全开/全关数据表、上层状态编码、Modbus 数量字段均按本值动态生成；
-- 其他模块请调用 relay_ctrl.get_channel_count() 获取，不要自行写死路数。
local CH_COUNT = 4
-- 通道基线地址（通道0=0x0000，通道号即地址偏移）
local CH_BASE_ADDR = 0x0000
-- 通道映射：风扇=通道0、LED=通道1
local CHANNEL = { FAN = 0, LED = 1 }

-- 继电器状态缓存（1-based 数组：relay[1] 对应通道0、relay[2] 对应通道1 ……）
-- 按 CH_COUNT 动态构造，换路数时此处无需改动
local relay_state = {}
for i = 1, CH_COUNT do relay_state[i] = 0 end
-- 是否已开启调试模式
local dbg_once = false
if not dbg_once then
    exmodbus.debug(false)
    dbg_once = true
end

-- 创建 RTU 主站实例
local rtu_master = comm_core.create_master(create_config)
if not rtu_master then
    log.error("relay_ctrl", "RTU 主站创建失败（UART1）")
end

-- 构建带 CRC 的标准 Modbus RTU 原始请求帧
-- @param body string 除 CRC 外的帧体字节串
-- @return string 完整帧（含 CRC，低字节在前）
local function build_raw_frame(body)
    local crc = crypto.crc16_modbus(body)
    return body .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

-- 写单个线圈（开/关用字段参数 0x05；翻转用 raw_request 0x5500）
-- @param channel number 通道号（0~3）
-- @param state string "open" / "close" / "toggle"
-- @return boolean 是否成功
local function write_single_coil(channel, state)
    if not rtu_master then return false end
    -- 通道号即线圈地址偏移（通道0 → 0x0000，通道3 → 0x0003）
    local addr = CH_BASE_ADDR + channel
    local status

    if state == "toggle" then
        -- 翻转：功能码 0x05，数据 0x5500（字段参数方式不支持，必须用原始帧）
        local frame = build_raw_frame(string.char(
            SLAVE_ID,                 -- 从站地址
            0x05,                     -- 功能码：写单个线圈
            (addr >> 8) & 0xFF, addr & 0xFF, -- 线圈地址
            0x55, 0x00                -- 数据：0x5500 翻转
        ))
        -- 走 comm_core.write_raw：自带总线串行 + 应答校验（库的 raw_request 分支本身不校验）
        -- 注意：翻转命令不做重试，避免一次操作被重复执行导致状态错乱
        status, _ = comm_core.write_raw(rtu_master, {
            slave_id = SLAVE_ID,
            func_code = 0x05,
            raw_request = frame,
            timeout = 1000,
        })
        if status == exmodbus.STATUS_SUCCESS then
            -- 更新缓存：翻转即取反（channel+1 为 1-based 数组下标）
            relay_state[channel + 1] = (relay_state[channel + 1] == 0) and 1 or 0
        end
    else
        -- 开/关：字段参数方式（0x05，库自动转 0xFF00/0x0000）
        local value = (state == "open") and 1 or 0
        status, _ = comm_core.write_coil(rtu_master, {
            slave_id = SLAVE_ID,
            start_addr = addr,
            value = value,
            timeout = 1000,
        })
        if status == exmodbus.STATUS_SUCCESS then
            relay_state[channel + 1] = value
        end
    end

    if status == exmodbus.STATUS_SUCCESS then
        log.info("relay_ctrl", "通道" .. channel .. "(" .. state .. ") 成功")
        -- 执行后广播最新状态
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return true
    end
    log.warn("relay_ctrl", "通道" .. channel .. "(" .. state .. ") 失败, 状态=", status)
    return false
end

-- 写多个线圈（全开/全关用功能码 0x0F）
-- @param vals table 各通道状态（0/1 数组）
-- @return boolean 是否成功
local function write_multiple_coils(vals)
    if not rtu_master then return false end
    local data = {}
    for i = 1, CH_COUNT do
        data[CH_BASE_ADDR + (i - 1)] = vals[i]
    end
    local status, _ = comm_core.write_coils(rtu_master, {
        slave_id = SLAVE_ID,
        start_addr = CH_BASE_ADDR,
        count = CH_COUNT,
        data = data,
        timeout = 1000,
    })
    if status == exmodbus.STATUS_SUCCESS then
        for i = 1, CH_COUNT do relay_state[i] = vals[i] end
        log.info("relay_ctrl", "多线圈写入成功")
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return true
    end
    log.warn("relay_ctrl", "多线圈写入失败, 状态=", status)
    return false
end

-- 打开指定通道（0~3）
function M.open(channel)
    if channel < 0 or channel > CH_COUNT - 1 then
        log.warn("relay_ctrl", "非法通道号", channel)
        return false
    end
    return write_single_coil(channel, "open")
end

-- 关闭指定通道（0~3）
function M.close(channel)
    if channel < 0 or channel > CH_COUNT - 1 then
        log.warn("relay_ctrl", "非法通道号", channel)
        return false
    end
    return write_single_coil(channel, "close")
end

-- 翻转指定通道（0~3）
function M.toggle(channel)
    if channel < 0 or channel > CH_COUNT - 1 then
        log.warn("relay_ctrl", "非法通道号", channel)
        return false
    end
    return write_single_coil(channel, "toggle")
end

-- 全开（按 CH_COUNT 动态生成：4 路模块即 4 路全开，8 路模块即 8 路全开）
function M.all_open()
    local vals = {}
    for i = 1, CH_COUNT do vals[i] = 1 end
    return write_multiple_coils(vals)
end

-- 全关（按 CH_COUNT 动态生成）
function M.all_close()
    local vals = {}
    for i = 1, CH_COUNT do vals[i] = 0 end
    return write_multiple_coils(vals)
end

-- 回读继电器线圈状态（功能码 0x01）并广播
-- @return table 状态数组，nil 表示失败
function M.read_status()
    if not rtu_master then return nil end
    local coils = comm_core.read_coils(rtu_master, {
        slave_id = SLAVE_ID,
        start_addr = CH_BASE_ADDR,
        count = CH_COUNT,
        timeout = 1000,
    })
    if coils then
        for i = 1, CH_COUNT do
            relay_state[i] = coils[CH_BASE_ADDR + (i - 1)] or 0
        end
        log.info("relay_ctrl", "回读继电器状态:", table.concat(relay_state, ","))
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return relay_state
    end
    log.warn("relay_ctrl", "回读继电器状态失败")
    return nil
end

-- 获取当前继电器路数（唯一配置源的对外出口，供 aircloud_data / app_main 等模块查询）
-- @return number 路数（4 路模块返回 4，8 路模块返回 8）
function M.get_channel_count()
    return CH_COUNT
end

-- 获取当前通道映射（供业务/命令层使用）
function M.get_channel_map()
    return { fan = CHANNEL.FAN, led = CHANNEL.LED }
end

-- 获取继电器当前缓存状态
function M.get_state()
    return relay_state
end

return M
