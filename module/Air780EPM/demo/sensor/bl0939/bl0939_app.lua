--[[
@module  bl0939_app
@summary BL0939 双路免校准电能计量数据读取业务模块
@version 1.0
@date    2026.08.20
@author  李明
]]

local exs_bl0939 = require "exs_bl0939"

-- 通信模式切换：1=SPI / 2=UART
-- 根据实际硬件接线选择
-- SPI 模式：BL0939 SEL 接 Air780EPM GPIO28（高电平）
--          BL0939 SCLK -> Air780EPM SPI0_SCK
--          BL0939 RX/SDI -> Air780EPM SPI0_MOSI
--          BL0939 TX/SDO -> Air780EPM SPI0_MISO（需外部上拉电阻）
-- UART 模式：BL0939 SEL 接 Air780EPM GPIO28（低电平）
--           BL0939 RX/SDI -> Air780EPM UART1_TX (GPIO18)
--           BL0939 TX/SDO -> Air780EPM UART1_RX (GPIO17)（需外部上拉电阻）
-- 注意：BL0939 的 SEL 引脚悬空默认为 UART 模式（内部下拉）
local MODE = 2

-- UART 器件地址（仅 UART 模式生效）
-- SOP16L 封装固定为 5；SSOP20L 封装由 A4~A1 引脚电平决定 0~15
local UART_ADDR = 5

-- 外部采样电路参数，需根据实际互感器和分压电阻修改
-- 电流有效值换算：I(A) = IA/B_RMS * Vref / 324004（规格书 2.6）
-- 电压有效值换算：V(V) = V_RMS * Vref / 79931（规格书 2.6）
-- 有功功率换算：P(W) = WATT * Vref^2 / 4046（规格书 2.2）
-- Vref 为内置基准电压，典型值 1.218V
-- 以下 ratio 为简化系数，实际需根据互感器变比和分压比标定
local voltage_ratio = 1000  -- 电压分压比，例如 1000:1
local current_ratio = 1000  -- 电流互感器变比，例如 1000:1

-- 按 MODE 组装 setup 参数
local function build_config_func()
    if MODE == 1 then
        -- SPI 模式：BL0939 SEL 接高电平
        return {
            mode = "spi",
            spi_id = 0,
            cs = 20,           -- 占位 GPIO，BL0939 SPI 无 CS，不接 BL0939
            sel_pin = 28,      -- 接 BL0939 SEL，拉高选 SPI 模式
            ac_freq = 50,
            rms_update = 400,
            fast_rms_threshold = 0x7FFF,
            fast_rms_cycle = exs_bl0939.FAST_RMS_CYCLE_FULL,
            cf_func = exs_bl0939.CF_FUNC_ENERGY
        }
    else
        -- UART 模式：BL0939 SEL 接低电平
        return {
            mode = "uart",
            uart_id = 1,
            addr = UART_ADDR,  -- SOP16L 固定 5
            sel_pin = 28,      -- 接 BL0939 SEL，拉低选 UART 模式
            ac_freq = 50,
            rms_update = 400,
            fast_rms_threshold = 0x7FFF,
            fast_rms_cycle = exs_bl0939.FAST_RMS_CYCLE_FULL,
            cf_func = exs_bl0939.CF_FUNC_ENERGY
        }
    end
end

-- 传感器初始化函数
-- 重要：必须返回 boolean，失败时 return false
local function init_func()
    local result = exs_bl0939.setup(build_config_func())
    if not result then
        log.error("bl0939", "init failed")
        log.error("bl0939", "检查接线: VCC=3.3V GND, SEL=GPIO28, SPI 模式接 SCK/MOSI/MISO, UART 模式接 TX/RX")
        return false  -- 返回 false，不能只 return
    end
    log.info("bl0939", "init success, version:", exs_bl0939.version())
    return true
end

-- 读取并打印双路电能数据
local function read_data_func()
    local data = exs_bl0939.get_data()
    if not data then
        log.error("bl0939", "read data failed")
        return
    end

    -- 电压和温度
    log.info("bl0939", string.format("电压=%.2fV 温度=%.1f°C",
        data.v_rms / voltage_ratio, data.temp))

    -- A 通道
    log.info("bl0939", string.format("A路 电流=%.3fA 有功=%.2fW 相角=%.1f°",
        data.ia_rms / current_ratio,
        data.a_watt / voltage_ratio / current_ratio,
        data.a_angle))

    -- B 通道
    log.info("bl0939", string.format("B路 电流=%.3fA 有功=%.2fW 相角=%.1f°",
        data.ib_rms / current_ratio,
        data.b_watt / voltage_ratio / current_ratio,
        data.b_angle))

    -- 快速有效值（用于漏电/过流监控参考）
    log.info("bl0939", string.format("快速RMS A=%d B=%d 电能脉冲A=%d B=%d",
        data.ia_fast_rms, data.ib_fast_rms, data.cfa_cnt, data.cfb_cnt))
end

-- 传感器读取任务协程
local function sensor_task_func()
    sys.wait(100)       -- 等待系统稳定，100ms
    local ok = init_func()
    if not ok then return end  -- 按返回值判断是否继续

    for i = 1, 10 do
        read_data_func()
        sys.wait(1000)  -- 每隔 1 秒读取一次
    end

    exs_bl0939.close()
    log.info("bl0939", "demo finished")
end
sys.taskInit(sensor_task_func)
