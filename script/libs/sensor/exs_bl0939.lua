--[[
@module  exs_bl0939
@summary BL0939 双路免校准电能计量芯片驱动扩展库
@version(0.1)
@date    2026.08.20
@author  蒋骞
@usage
本扩展库提供上海贝岭 BL0939 的 LuatOS 驱动，功能包括：
1、初始化（SPI/UART 通信、SEL 模式切换、交流频率、RMS 刷新、快速 RMS、校准参数）
2、数据读取（A/B 电流有效值、电压有效值、快速有效值、有功功率、电能脉冲计数、相角、温度、波形）
3、软复位、资源释放、版本查询

对外接口 4 个：
- exs_bl0939.setup(config)：初始化
- exs_bl0939.get_data()：读取数据
- exs_bl0939.close()：释放资源
- exs_bl0939.version()：获取版本号

可选接口：
- exs_bl0939.reset()：软复位

=== 版本更新说明 ===
-- 版本号：202608200000
-- 1、更新时间：2026-08-20
-- 2、更新内容：
--   - 初版实现
]]

-- ==================== 模块表 ====================
local exs_bl0939 = {}

-- ==================== 常量定义 ====================
-- SPI 命令字节（帧识别字节）
local SPI_CMD_WRITE = 0xA5  -- 写操作识别字节
local SPI_CMD_READ  = 0x55  -- 读操作识别字节

-- UART 命令字节高半字节（低半字节为器件地址 A4A3A2A1）
local UART_CMD_WRITE_HI = 0xA0  -- 写操作帧识别字节高 4 位
local UART_CMD_READ_HI  = 0x50  -- 读操作帧识别字节高 4 位
local UART_PACKET_ADDR  = 0xAA  -- 全电参数数据包请求地址

-- 关键寄存器地址（24-bit 数据宽度，按规格书 1.5 寄存器列表）
-- 电参量寄存器（只读）
local REG_IA_FAST_RMS = 0x00  -- A 通道快速有效值，24-bit 无符号
local REG_IA_WAVE     = 0x01  -- A 通道电流波形，20-bit 有符号
local REG_IB_WAVE     = 0x02  -- B 通道电流波形，20-bit 有符号
local REG_V_WAVE      = 0x03  -- 电压波形，20-bit 有符号
local REG_IA_RMS      = 0x04  -- A 通道电流有效值，24-bit 无符号
local REG_IB_RMS      = 0x05  -- B 通道电流有效值，24-bit 无符号
local REG_V_RMS       = 0x06  -- 电压有效值，24-bit 无符号
local REG_IB_FAST_RMS = 0x07  -- B 通道快速有效值，24-bit 无符号
local REG_A_WATT      = 0x08  -- A 通道有功功率，24-bit 有符号（bit23 符号位）
local REG_B_WATT      = 0x09  -- B 通道有功功率，24-bit 有符号
local REG_CFA_CNT     = 0x0A  -- A 通道有功电能脉冲计数，24-bit 无符号
local REG_CFB_CNT     = 0x0B  -- B 通道有功电能脉冲计数，24-bit 无符号
local REG_A_CORNER    = 0x0C  -- A 通道相角，16-bit 无符号
local REG_B_CORNER    = 0x0D  -- B 通道相角，16-bit 无符号
local REG_TPS1        = 0x0E  -- 内部温度，10-bit 无符号
local REG_TPS2        = 0x0F  -- 外部温度，10-bit 无符号

-- 用户操作寄存器（读写）
local REG_IA_FAST_RMS_CTRL = 0x10  -- A 通道快速有效值控制，16-bit
local REG_IA_RMSOS   = 0x13        -- A 通道电流有效值小信号校正，8-bit
local REG_IB_RMSOS   = 0x14        -- B 通道电流有效值小信号校正，8-bit
local REG_A_WATTOS   = 0x15        -- A 通道有功功率小信号校正，8-bit
local REG_B_WATTOS   = 0x16        -- B 通道有功功率小信号校正，8-bit
local REG_WA_CREEP   = 0x17        -- 有功功率防潜寄存器，8-bit，默认 0x0B
local REG_MODE       = 0x18        -- 用户模式选择寄存器，16-bit
local REG_SOFT_RESET = 0x19        -- 软复位寄存器，写 0x5A5A5A 复位用户区
local REG_USR_WRPROT = 0x1A        -- 用户写保护寄存器，写 0x55 解锁
local REG_TPS_CTRL   = 0x1B        -- 温度模式控制寄存器，16-bit
local REG_TPS2_A     = 0x1C        -- 外部温度传感器增益系数校正，8-bit
local REG_TPS2_B     = 0x1D        -- 外部温度传感器偏移系数校正，8-bit
local REG_IB_FAST_RMS_CTRL = 0x1E  -- B 通道快速有效值控制，16-bit

-- 写保护解锁值与软复位值
local WRPROT_UNLOCK = 0x55      -- USR_WRPROT 解锁值（8-bit）
local RESET_USER    = 0x5A5A5A  -- SOFT_RESET 用户区复位值

-- MODE 寄存器位定义
local MODE_BIT_RMS_UPDATE_SEL = 0x0100  -- bit8：0=400ms，1=800ms
local MODE_BIT_AC_FREQ_SEL    = 0x0200  -- bit9：0=50Hz，1=60Hz
local MODE_BIT_CF_SEL          = 0x0800  -- bit11：0=A 通道，1=B 通道
local MODE_BIT_CF_UNABLE       = 0x1000  -- bit12：0=电能脉冲，1=报警功能

-- TPS_CTRL 寄存器位定义
local TPS_BIT_ALERT_CTRL = 0x4000  -- bit14：0=温度报警，1=A 通道漏电/过流报警

-- IA/IB_FAST_RMS_CTRL 寄存器位定义
local FAST_RMS_BIT_CYCLE = 0x8000  -- bit15：0=半周波，1=周波
local FAST_RMS_TH_MASK   = 0x7FFF  -- bit[14:0]：快速有效值阈值

-- CF 输出功能枚举（内部映射到 MODE/TPS_CTRL 位）
local CF_FUNC_ENERGY         = "energy"          -- CF 输出电能脉冲
local CF_FUNC_TEMP_ALERT     = "temp_alert"      -- CF 输出外部温度报警
local CF_FUNC_LEAKAGE_ALERT  = "leakage_alert"   -- CF 输出 A 通道漏电/过流报警

-- 交流频率枚举
local AC_FREQ_50HZ = 50
local AC_FREQ_60HZ = 60

-- RMS 刷新间隔枚举（ms）
local RMS_UPDATE_400 = 400
local RMS_UPDATE_800 = 800

-- 快速 RMS 刷新周期枚举
local FAST_RMS_CYCLE_FULL = "full"  -- 周波
local FAST_RMS_CYCLE_HALF = "half"  -- 半周波

-- UART 默认器件地址（SOP16L 封装固定为 5）
local UART_DEFAULT_ADDR = 5

-- 是否启用原始字节调试日志（真机排查时打开）
-- local COMM_DEBUG = true
local COMM_DEBUG = false

-- UART 数据包总长度（全电参数包，35 字节）
local UART_PACKET_LEN = 35

-- ==================== 内部变量 ====================
local g_mode      = nil   -- 通信方式 "spi" / "uart"
local g_spi_dev   = nil   -- SPI 设备句柄
local g_uart_id   = nil   -- UART 总线 id
local g_sel_pin   = nil   -- SEL 引脚（1=SPI，0=UART）
local g_dev_addr  = UART_DEFAULT_ADDR  -- UART 器件地址（0~15，SOP16L 固定 5）
local g_inited    = false -- 是否已初始化
local g_ac_freq  = AC_FREQ_50HZ   -- 当前交流频率
local g_rms_update = RMS_UPDATE_400  -- 当前 RMS 刷新间隔

-- ==================== 内部函数 ====================

-- 将字节数组格式化为十六进制字符串，便于调试
local function hex_str(buf)
    if not buf then return "nil" end
    local t = {}
    for i = 1, #buf do
        t[i] = string.format("%02X", buf:byte(i))
    end
    return table.concat(t, " ")
end

-- 24-bit 无符号大端字节转 number（SPI 数据为大端）
-- buf：字符串，offset：起始字节（1-based）
local function u24_be(buf, offset)
    if not buf or #buf < offset + 2 then return nil end
    local b1 = buf:byte(offset) or 0
    local b2 = buf:byte(offset + 1) or 0
    local b3 = buf:byte(offset + 2) or 0
    return (b1 << 16) | (b2 << 8) | b3
end

-- 24-bit 无符号小端字节转 number（UART 数据为小端）
local function u24_le(buf, offset)
    if not buf or #buf < offset + 2 then return nil end
    local b1 = buf:byte(offset) or 0
    local b2 = buf:byte(offset + 1) or 0
    local b3 = buf:byte(offset + 2) or 0
    return (b3 << 16) | (b2 << 8) | b1
end

-- 16-bit 无符号小端字节转 number
local function u16_le(buf, offset)
    if not buf or #buf < offset + 1 then return nil end
    local b1 = buf:byte(offset) or 0
    local b2 = buf:byte(offset + 1) or 0
    return (b2 << 8) | b1
end

-- 将 24-bit 有符号原始值转带符号 number（bit23 为符号位，补码）
local function to_signed_24(val)
    if val == nil then return 0 end
    if val >= 0x800000 then val = val - 0x1000000 end
    return val
end

-- SPI 校验和：((cmd + addr + dh + dm + dl) & 0xFF) 按位取反
-- 来源：规格书 3.1.2 帧结构
local function spi_checksum(cmd, addr, dh, dm, dl)
    return (~((cmd + addr + dh + dm + dl) & 0xFF)) & 0xFF
end

-- 通过 SPI 读取寄存器（24-bit，大端）
-- 读帧：发送 {0x55, Addr}，BL0939 返回 {Data_H, Data_M, Data_L, CHECKSUM}
-- 来源：规格书 3.1.2 / 3.1.4
local function spi_read_reg(addr)
    if not g_spi_dev then return nil end
    local cmd = SPI_CMD_READ
    local tx = string.char(cmd, addr)
    if COMM_DEBUG then
        log.debug("exs_bl0939", "SPI RD TX", hex_str(tx))
    end
    -- 发送 2 字节命令，共 48 个 SCLK（6 字节），返回 6 字节
    -- 返回数据布局：[r1,r2,DATA_H,DATA_M,DATA_L,CHECKSUM]
    -- r1/r2 为发送命令期间的回读（BL0939 未响应，无意义）
    local d = g_spi_dev:transfer(tx, 2, 6)
    if COMM_DEBUG then
        log.debug("exs_bl0939", "SPI RD RX", hex_str(d))
    end
    if not d or #d < 6 then return nil end
    local dh = d:byte(3) or 0
    local dm = d:byte(4) or 0
    local dl = d:byte(5) or 0
    local rx_sum = d:byte(6) or 0
    local val = (dh << 16) | (dm << 8) | dl
    local calc_sum = spi_checksum(cmd, addr, dh, dm, dl)
    if rx_sum ~= calc_sum then
        log.warn("exs_bl0939", string.format("SPI RD checksum 错误: addr=0x%02X rx=%02X calc=%02X", addr, rx_sum, calc_sum))
    end
    return val
end

-- 通过 SPI 写入寄存器（24-bit，大端）
-- 帧格式：0xA5 + Addr + Data_H + Data_M + Data_L + CHECKSUM
local function spi_write_reg(addr, value)
    if not g_spi_dev then return false end
    local b1 = (value >> 16) & 0xFF
    local b2 = (value >> 8) & 0xFF
    local b3 = value & 0xFF
    local sum = spi_checksum(SPI_CMD_WRITE, addr, b1, b2, b3)
    local tx = string.char(SPI_CMD_WRITE, addr, b1, b2, b3, sum)
    if COMM_DEBUG then
        log.debug("exs_bl0939", "SPI WR TX", hex_str(tx))
    end
    return g_spi_dev:send(tx) == true
end

-- 组装 UART 命令字节（高 4 位为命令，低 4 位为器件地址）
local function uart_cmd_byte(cmd_hi, addr)
    return (cmd_hi & 0xF0) | (addr & 0x0F)
end

-- UART 校验和：((cmd + addr + dl + dm + dh) & 0xFF) 按位取反
-- 来源：规格书 3.2.4 / 3.2.5
local function uart_checksum(cmd_byte, addr, dl, dm, dh)
    return (~((cmd_byte + addr + dl + dm + dh) & 0xFF)) & 0xFF
end

-- 通过 UART 读取寄存器（24-bit，小端）
-- 帧格式：发送 {0x5{addr}, Addr}，BL0939 返回 {Data_L, Data_M, Data_H, CHECKSUM}
-- 来源：规格书 3.2.5
local function uart_read_reg(addr)
    if not g_uart_id then return nil end
    local cmd_byte = uart_cmd_byte(UART_CMD_READ_HI, g_dev_addr)
    -- 清空接收缓冲区，避免残留数据干扰
    while uart.rxSize(g_uart_id) > 0 do
        uart.read(g_uart_id, 128)
    end
    uart.write(g_uart_id, string.char(cmd_byte, addr))
    -- 轮询等待接收 4 字节，最多等 100ms（4800bps 下 4 字节约 10ms）
    local d = nil
    for _ = 1, 20 do
        sys.wait(5)  -- 每 5ms 检查一次
        if uart.rxSize(g_uart_id) >= 4 then
            d = uart.read(g_uart_id, 4)
            break
        end
    end
    if COMM_DEBUG then
        log.debug("exs_bl0939", "UART RD RX", hex_str(d))
    end
    if not d or #d < 4 then
        log.warn("exs_bl0939", string.format("UART RD 超时: addr=0x%02X rxSize=%d", addr, uart.rxSize(g_uart_id) or 0))
        return nil
    end
    local dl = d:byte(1) or 0
    local dm = d:byte(2) or 0
    local dh = d:byte(3) or 0
    local val = (dh << 16) | (dm << 8) | dl
    local rx_sum = d:byte(4) or 0
    local calc_sum = uart_checksum(cmd_byte, addr, dl, dm, dh)
    if rx_sum ~= calc_sum then
        log.warn("exs_bl0939", string.format("UART RD checksum 错误: addr=0x%02X rx=%02X calc=%02X data=%s", addr, rx_sum, calc_sum, hex_str(d)))
    end
    return val
end

-- 通过 UART 写入寄存器（24-bit，小端）
-- 帧格式：{0xA{addr}, Addr, Data_L, Data_M, Data_H, CHECKSUM}
local function uart_write_reg(addr, value)
    if not g_uart_id then return false end
    local cmd_byte = uart_cmd_byte(UART_CMD_WRITE_HI, g_dev_addr)
    local dl = value & 0xFF
    local dm = (value >> 8) & 0xFF
    local dh = (value >> 16) & 0xFF
    local sum = uart_checksum(cmd_byte, addr, dl, dm, dh)
    local tx = string.char(cmd_byte, addr, dl, dm, dh, sum)
    if COMM_DEBUG then
        log.debug("exs_bl0939", "UART WR TX", hex_str(tx))
    end
    uart.write(g_uart_id, tx)
    sys.wait(5)  -- 等待发送完成并给芯片处理时间，5ms
    return true
end

-- 通过 UART 读取全电参数数据包（35 字节，一次返回全部电参量）
-- 请求帧：{0x5{addr}, 0xAA}；返回：35 字节全电参数包
-- 来源：规格书 3.2.6 数据包发送模式
local function uart_read_packet()
    if not g_uart_id then return nil end
    local cmd_byte = uart_cmd_byte(UART_CMD_READ_HI, g_dev_addr)
    -- 清空接收缓冲区
    while uart.rxSize(g_uart_id) > 0 do
        uart.read(g_uart_id, 128)
    end
    uart.write(g_uart_id, string.char(cmd_byte, UART_PACKET_ADDR))
    -- 35 字节 @ 4800bps 约 77ms，轮询等待，最多 150ms
    local d = nil
    for _ = 1, 30 do
        sys.wait(5)  -- 每 5ms 检查一次
        if uart.rxSize(g_uart_id) >= UART_PACKET_LEN then
            d = uart.read(g_uart_id, UART_PACKET_LEN)
            break
        end
    end
    if COMM_DEBUG then
        log.debug("exs_bl0939", "UART PKT RX", hex_str(d))
    end
    if not d or #d < UART_PACKET_LEN then
        log.warn("exs_bl0939", string.format("UART PKT 超时: rxSize=%d/%d", uart.rxSize(g_uart_id) or 0, UART_PACKET_LEN))
        return nil
    end
    -- 校验包头和校验和
    local head = d:byte(1) or 0
    if head ~= 0x55 then
        log.warn("exs_bl0939", string.format("UART PKT 包头错误: head=0x%02X (应为 0x55)", head))
        return nil
    end
    -- checksum = ~((cmd + 0x55 + data1_l + data1_m + data1_h + ...) & 0xFF)
    local sum = cmd_byte + 0x55  -- 命令字节 + 包头
    for i = 2, UART_PACKET_LEN - 1 do  -- data 区为字节 2~34
        sum = sum + (d:byte(i) or 0)
    end
    local calc_sum = (~(sum & 0xFF)) & 0xFF
    local rx_sum = d:byte(UART_PACKET_LEN) or 0
    if rx_sum ~= calc_sum then
        log.warn("exs_bl0939", string.format("UART PKT checksum 错误: rx=%02X calc=%02X", rx_sum, calc_sum))
        return nil
    end
    return d
end

-- 寄存器读取入口
local function read_reg(addr)
    if g_mode == "spi" then
        return spi_read_reg(addr)
    elseif g_mode == "uart" then
        return uart_read_reg(addr)
    end
    return nil
end

-- 寄存器写入入口
local function write_reg(addr, value)
    if g_mode == "spi" then
        return spi_write_reg(addr, value)
    elseif g_mode == "uart" then
        return uart_write_reg(addr, value)
    end
    return false
end

-- 解锁写保护，并读回确认必须是 0x55 才算成功
local function unlock_write()
    for retry = 1, 3 do
        if write_reg(REG_USR_WRPROT, WRPROT_UNLOCK) then
            sys.wait(10)  -- 等待写入生效，10ms
            local val = read_reg(REG_USR_WRPROT)
            if val == WRPROT_UNLOCK then
                log.debug("exs_bl0939", "写保护解锁成功")
                return true
            else
                log.warn("exs_bl0939", string.format("写保护解锁确认失败: 0x%02X (重试 %d/3)", val or 0xFF, retry))
            end
        end
        sys.wait(10)  -- 重试间隔，10ms
    end
    log.error("exs_bl0939", "写保护解锁失败，请检查接线与 SEL 模式")
    return false
end

-- 写寄存器前自动解锁写保护
local function write_reg_unlock(addr, value)
    if not unlock_write() then
        return false
    end
    return write_reg(addr, value)
end

-- 设置 SEL 引脚电平切换通信模式
-- SEL=1 → SPI 模式；SEL=0 → UART 模式
-- 来源：规格书 1.4 管脚描述（SEL 内部下拉，悬空为 UART）
local function set_sel(level)
    if not g_sel_pin then return false end
    gpio.setup(g_sel_pin, 1, gpio.PULLUP)  -- 输出模式，初始高电平
    gpio.set(g_sel_pin, level)
    sys.wait(10)  -- 等待 SEL 电平稳定，10ms
    return true
end

-- 配置用户模式寄存器（交流频率、RMS 刷新间隔、CF 输出功能）
local function set_mode(ac_freq, rms_update, cf_func)
    local mode_val = 0
    -- 交流频率
    if ac_freq == AC_FREQ_60HZ then
        g_ac_freq = AC_FREQ_60HZ
        mode_val = mode_val | MODE_BIT_AC_FREQ_SEL
    else
        g_ac_freq = AC_FREQ_50HZ
    end
    -- RMS 刷新间隔
    if rms_update == RMS_UPDATE_800 then
        g_rms_update = RMS_UPDATE_800
        mode_val = mode_val | MODE_BIT_RMS_UPDATE_SEL
    else
        g_rms_update = RMS_UPDATE_400
    end
    -- CF 输出功能
    if cf_func == CF_FUNC_TEMP_ALERT then
        -- 温度报警：MODE[12]=1，TPS_CTRL[14]=0
        mode_val = mode_val | MODE_BIT_CF_UNABLE
        if not write_reg_unlock(REG_MODE, mode_val) then return false end
        -- 先写 MODE 再写 TPS_CTRL
        local tps_val = read_reg(REG_TPS_CTRL) or 0x07FF
        tps_val = tps_val & (~TPS_BIT_ALERT_CTRL & 0xFFFF)  -- 清 bit14，开启温度报警
        return write_reg_unlock(REG_TPS_CTRL, tps_val)
    elseif cf_func == CF_FUNC_LEAKAGE_ALERT then
        -- A 通道漏电/过流报警：MODE[12]=1，TPS_CTRL[14]=1
        mode_val = mode_val | MODE_BIT_CF_UNABLE
        if not write_reg_unlock(REG_MODE, mode_val) then return false end
        local tps_val = read_reg(REG_TPS_CTRL) or 0x07FF
        tps_val = tps_val | TPS_BIT_ALERT_CTRL  -- 置 bit14，开启 A 通道漏电报警
        return write_reg_unlock(REG_TPS_CTRL, tps_val)
    else
        -- 默认电能脉冲：MODE[12]=0
        return write_reg_unlock(REG_MODE, mode_val)
    end
end

-- 配置快速有效值（阈值 + 刷新周期）
-- 来源：规格书 2.8 漏电/过流检测
local function set_fast_rms(threshold, cycle)
    threshold = threshold or 0x7FFF
    local ctrl_val = threshold & FAST_RMS_TH_MASK
    if cycle == FAST_RMS_CYCLE_HALF then
        -- bit15=0 半周波（清 bit15）
        ctrl_val = ctrl_val & (~FAST_RMS_BIT_CYCLE & 0xFFFF)
    else
        -- 默认周波（bit15=1）
        ctrl_val = ctrl_val | FAST_RMS_BIT_CYCLE
    end
    if not write_reg_unlock(REG_IA_FAST_RMS_CTRL, ctrl_val) then
        return false
    end
    return write_reg_unlock(REG_IB_FAST_RMS_CTRL, ctrl_val)
end

-- 设置外部温度报警阈值
-- 来源：规格书 1.6.2 温度模式控制寄存器（TPS_CTRL[9:0]）
local function set_temp_alert_th(th)
    th = th or 0x3FF
    local tps_val = read_reg(REG_TPS_CTRL) or 0x07FF
    tps_val = (tps_val & 0xFC00) | (th & 0x03FF)  -- 保留高 6 位，低 10 位写阈值
    return write_reg_unlock(REG_TPS_CTRL, tps_val)
end

-- 内部温度换算：Tx = (170/448) * (TPS1/2 - 32) - 45
-- 来源：规格书 2.11 温度计量
local function convert_temp(tps1)
    if not tps1 then return 0 end
    return (170 / 448) * (tps1 / 2 - 32) - 45
end

-- 相角换算：angle = 2 * pi * CORNER * fc / f0（弧度），转角度
-- fc 为交流频率，f0 为采样频率（典型 1MHz）
-- 来源：规格书 2.9 相角计算
local function convert_angle(corner_raw, ac_freq)
    if not corner_raw then return 0 end
    local rad = 2 * 3.14159265 * corner_raw * ac_freq / 1000000
    return rad * 180 / 3.14159265  -- 转为角度
end

-- ==================== 对外 API ====================

--[[
初始化 BL0939 传感器
注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait()，在 task 外调用会报错）
@api exs_bl0939.setup(config)
@param table config
参数含义：配置参数表
数据类型：table
取值范围：见 API 文档
是否必选：是
注意事项：config.mode 决定 SPI 或 UART 通信方式；config.sel_pin 用于切换 SEL 引脚电平
参数示例：{mode="spi", spi_id=0, cs=20, sel_pin=28}
@return boolean
含义说明：初始化是否成功
数据类型：boolean
]]
function exs_bl0939.setup(config)
    config = config or {}
    g_mode = config.mode or "spi"
    g_sel_pin = config.sel_pin

    -- 切换 SEL 引脚电平（1=SPI，0=UART）
    if g_mode == "spi" then
        set_sel(1)
    elseif g_mode == "uart" then
        set_sel(0)
    else
        log.error("exs_bl0939", "不支持的通信模式：" .. tostring(g_mode))
        return false
    end

    if g_mode == "spi" then
        local spi_id = config.spi_id or 0
        local cs_pin = config.cs or 20
        -- SPI 模式 1：CPOL=0, CPHA=1，500kHz 起步更稳定（规格书最大 900KHz）
        -- BL0939 SPI 无 CS 引脚，cs_pin 仅为 spi.deviceSetup 所需占位 GPIO，不接 BL0939
        g_spi_dev = spi.deviceSetup(spi_id, cs_pin, 0, 1, 8, 500000)
        if not g_spi_dev then
            log.error("exs_bl0939", "SPI 初始化失败")
            return false
        end
        -- SPI 接口软复位：发送 6 字节 0xFF（规格书 3.1.5）
        g_spi_dev:send(string.char(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))
        sys.wait(10)  -- 等待 SPI 接口复位完成，10ms
    elseif g_mode == "uart" then
        g_uart_id = config.uart_id or 1
        -- UART 固定 4800bps，N，8，1.5（规格书 3.2.2）
        -- 器件地址：SOP16L 固定为 5，SSOP20L 由 A4~A1 引脚决定 0~15
        g_dev_addr = config.addr or UART_DEFAULT_ADDR
        if g_dev_addr < 0 or g_dev_addr > 15 then
            log.warn("exs_bl0939", "UART 器件地址超出范围 0~15，使用默认 5")
            g_dev_addr = UART_DEFAULT_ADDR
        end
        uart.setup(g_uart_id, 4800, 8, uart.PAR_NONE, uart.STOP_1)
        sys.wait(20)  -- 等待 UART 稳定，20ms
        log.info("exs_bl0939", "UART 模式初始化完成，器件地址", g_dev_addr)
    end

    sys.wait(50)  -- 等待芯片上电稳定，50ms

    -- 解锁写保护
    if not unlock_write() then
        log.warn("exs_bl0939", "写保护解锁失败，继续尝试初始化")
    else
        local wrprot = read_reg(REG_USR_WRPROT)
        log.debug("exs_bl0939", string.format("USR_WRPROT 读回: 0x%02X", wrprot or 0xFF))
    end

    -- 配置用户模式（交流频率、RMS 刷新间隔、CF 输出功能）
    if not set_mode(config.ac_freq or AC_FREQ_50HZ,
                    config.rms_update or RMS_UPDATE_400,
                    config.cf_func or CF_FUNC_ENERGY) then
        log.error("exs_bl0939", "用户模式配置失败")
        return false
    end

    -- 配置快速有效值阈值和刷新周期
    if not set_fast_rms(config.fast_rms_threshold, config.fast_rms_cycle) then
        log.warn("exs_bl0939", "快速有效值配置失败")
    end

    -- 配置外部温度报警阈值（仅当用户传入时）
    if config.temp_alert_th then
        if not set_temp_alert_th(config.temp_alert_th) then
            log.warn("exs_bl0939", "温度报警阈值配置失败")
        end
    end

    -- 写入校准参数
    if config.calibration and type(config.calibration) == "table" then
        for _, item in ipairs(config.calibration) do
            if item[1] and item[2] then
                write_reg_unlock(item[1], item[2])
            end
        end
    end

    g_inited = true
    log.info("exs_bl0939", "初始化完成，模式：" .. g_mode)
    return true
end

--[[
读取 BL0939 全部测量数据
注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait()，在 task 外调用会报错）
@api exs_bl0939.get_data()
@return table|nil
含义说明：传感器测量数据
数据类型：table 或 nil
]]
function exs_bl0939.get_data()
    if not g_inited then
        log.warn("exs_bl0939", "未初始化，请先调用 setup")
        return nil
    end

    local data = {}

    -- UART 模式优先使用数据包模式（一次返回全部电参量，77ms）
    -- SPI 模式或数据包失败时退化为逐寄存器读取
    local pkt = nil
    if g_mode == "uart" then
        pkt = uart_read_packet()
    end

    if pkt then
        -- 解析全电参数数据包（35 字节，小端）
        -- 包格式见规格书 3.2.6
        data.ia_fast_rms = u24_le(pkt, 2) or 0   -- 字节 1~3
        data.ia_rms      = u24_le(pkt, 5) or 0   -- 字节 4~6
        data.ib_rms      = u24_le(pkt, 8) or 0   -- 字节 7~9
        data.v_rms       = u24_le(pkt, 11) or 0  -- 字节 10~12
        data.ib_fast_rms = u24_le(pkt, 14) or 0  -- 字节 13~15
        data.a_watt      = to_signed_24(u24_le(pkt, 17))  -- 字节 16~18
        data.b_watt      = to_signed_24(u24_le(pkt, 20))  -- 字节 19~21
        data.cfa_cnt     = u24_le(pkt, 23) or 0  -- 字节 22~24
        data.cfb_cnt     = u24_le(pkt, 26) or 0  -- 字节 25~27
        -- TPS1：字节 28~29（小端 16-bit），字节 30 为 0x00 补齐
        data.tps1        = u16_le(pkt, 29) or 0  -- 字节 28~29
        -- TPS2：字节 31~32（小端 16-bit），字节 33 为 0x00 补齐
        data.tps2        = u16_le(pkt, 32) or 0  -- 字节 31~32
        data.temp        = convert_temp(data.tps1)
        data.a_angle     = convert_angle(read_reg(REG_A_CORNER), g_ac_freq)
        data.b_angle     = convert_angle(read_reg(REG_B_CORNER), g_ac_freq)
    else
        -- 逐寄存器读取（SPI 模式或 UART 数据包失败）
        data.ia_fast_rms = read_reg(REG_IA_FAST_RMS) or 0
        data.ia_rms      = read_reg(REG_IA_RMS) or 0
        data.ib_rms      = read_reg(REG_IB_RMS) or 0
        data.v_rms       = read_reg(REG_V_RMS) or 0
        data.ib_fast_rms = read_reg(REG_IB_FAST_RMS) or 0
        data.a_watt      = to_signed_24(read_reg(REG_A_WATT))
        data.b_watt      = to_signed_24(read_reg(REG_B_WATT))
        data.cfa_cnt     = read_reg(REG_CFA_CNT) or 0
        data.cfb_cnt     = read_reg(REG_CFB_CNT) or 0
        data.a_angle     = convert_angle(read_reg(REG_A_CORNER), g_ac_freq)
        data.b_angle     = convert_angle(read_reg(REG_B_CORNER), g_ac_freq)
        data.tps1        = read_reg(REG_TPS1) or 0
        data.tps2        = read_reg(REG_TPS2) or 0
        data.temp        = convert_temp(data.tps1)
    end

    return data
end

--[[
软复位 BL0939
注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait()，在 task 外调用会报错）
@api exs_bl0939.reset()
@return boolean
含义说明：复位是否成功
数据类型：boolean
]]
function exs_bl0939.reset()
    if not unlock_write() then
        log.warn("exs_bl0939", "复位前写保护解锁失败")
    end
    if write_reg(REG_SOFT_RESET, RESET_USER) then
        sys.wait(50)  -- 等待复位完成，50ms
        g_inited = false
        log.info("exs_bl0939", "软复位完成，需重新调用 setup")
        return true
    end
    return false
end

--[[
释放 BL0939 资源
@api exs_bl0939.close()
@return boolean
含义说明：是否成功释放资源
数据类型：boolean
]]
function exs_bl0939.close()
    if g_mode == "spi" and g_spi_dev then
        g_spi_dev = nil
    elseif g_mode == "uart" and g_uart_id then
        uart.close(g_uart_id)
    end
    -- SEL 引脚恢复悬空（输出高 + 上拉，等效 UART 模式默认态）
    if g_sel_pin then
        gpio.setup(g_sel_pin, 1, gpio.PULLUP)
        gpio.set(g_sel_pin, 0)
    end
    g_inited = false
    g_mode = nil
    g_spi_dev = nil
    g_uart_id = nil
    g_sel_pin = nil
    collectgarbage("collect")
    log.info("exs_bl0939", "资源已释放")
    return true
end

--[[
获取扩展库版本号
@api exs_bl0939.version()
@return string
含义说明：扩展库版本号
数据类型：string
]]
function exs_bl0939.version()
    return "202608200000"
end

-- ==================== 常量导出 ====================
exs_bl0939.CF_FUNC_ENERGY        = CF_FUNC_ENERGY
exs_bl0939.CF_FUNC_TEMP_ALERT    = CF_FUNC_TEMP_ALERT
exs_bl0939.CF_FUNC_LEAKAGE_ALERT = CF_FUNC_LEAKAGE_ALERT
exs_bl0939.AC_FREQ_50HZ          = AC_FREQ_50HZ
exs_bl0939.AC_FREQ_60HZ          = AC_FREQ_60HZ
exs_bl0939.RMS_UPDATE_400        = RMS_UPDATE_400
exs_bl0939.RMS_UPDATE_800        = RMS_UPDATE_800
exs_bl0939.FAST_RMS_CYCLE_FULL   = FAST_RMS_CYCLE_FULL
exs_bl0939.FAST_RMS_CYCLE_HALF   = FAST_RMS_CYCLE_HALF

return exs_bl0939
