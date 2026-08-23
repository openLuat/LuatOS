--[[
@module  bl0939_app
@summary BL0939 双路免校准电能计量数据读取业务模块（适配 BL0939V1.4 板 + Air8101）
@version 1.6
@date    2026.08.21
@author  李明
@history
  1.6（2026.08.21）：由 Air780EHV 工程移植至 Air8101；UART1=MAIN_UART（U1TX=PIN12/GPIO0、U1RX=PIN11/GPIO1）；
                      SPI 用 SPI0 默认组（SCLK=PIN28、CS=PIN54、MISO=PIN55、MOSI=PIN57），备选 SPI1（PIN65/66/67/8）
  1.6（2026.08.21）：增加 SPI 模式支持，MODE 变量可在 uart/spi 间切换
  1.5（2026.08.21）：循环读取增加断线检测与自动重连（连续 3 次读取异常触发重新初始化），失联时不再打印全 0 误导数据
  1.4（2026.08.21）：Demo 10 次读取改为持续循环读取（while true），不再自动释放资源；校准系数维持 1.3 实测值
  1.3（2026.08.21）：按万用表 227V / 负载 698R 实机基准校准 KU/KI/KPA/KW
  1.2（2026.08.21）：由 Air780EPM 工程移植至 Air780EHV，UART1 引脚与 EPM 一致（GPIO17/18），仅换 core 固件
]]

local exs_bl0939 = require "exs_bl0939"

--======================================================================
-- 通信模式选择：MODE = "uart"（默认） 或 "spi"
--======================================================================
-- UART 模式（SEL 悬空内部下拉 = UART 模式，无需外部控制）
-- 隔离接口接线（接 220V 市电后使用 P2 光耦隔离口，勿再给 P3 供外部电源）：
--   Air8101 3.3V                   -> P2-1 V   （VDD_GPIO 域，VBAT>=3.5V 时固定 3.3V）
--   Air8101 GND                     -> P2-4 G
--   Air8101 UART1_TXD(U1TX/PIN12/GPIO0) -> P2-2 RXD
--   Air8101 UART1_RXD(U1RX/PIN11/GPIO1) <- P2-3 TXD
--
-- SPI 模式接线（无光耦隔离，信号为热侧直连，只能冷态测试，禁止接市电！）：
--   1) BL0939 板由外部 3.3V 供电：P3-1(+3V3)、P3-2(GND)，SEL(U1-16) 拉高到 3.3V
--   2) Air8101 使用 SPI0 默认组（SCLK=PIN28、CS0=PIN54、MISO=PIN55、MOSI=PIN57）；
--      也可改用 SPI1（SCLK=PIN65、CS=PIN66、MOSI=PIN67、MISO=PIN8），并同步修改下方 SPI_ID/SPI_CS
--   3) TX/SDO(U1-19) 需外部 10K 上拉到 3.3V；A1/A3(U1-9/11) 拉高到 3.3V、A2/A4 悬空
--      （规格书 3.1.5：20pin 封装 SPI 模式必须 A4A2 接地、A3A1 接高电平）
--   4) SPI 固定 Mode1(CPOL=0/CPHA=1)、500kHz、8bit MSB first、无片选、6 字节帧 + 校验
local MODE = "uart"

-- UART 模式专用：器件地址（本板 SSOP20L，A4~A1 未接高电平，地址=0）
local UART_ADDR = 0

-- SPI 模式专用：Air8101 使用 SPI0 默认组（CS=PIN54 占位，不接 BL0939）
local SPI_ID = 0
local SPI_CS = 54

-- 换算系数：规格书公式 + 本板采样电路 + 实机基准校准（2026.08.21）
-- 校准基准：万用表市电 227V；负载电阻实测 698R（500R+200R 串联），理论电流 I = 227/698 = 0.3252A
-- 电压采样：L -> 4x510K 串联 -> VP，VP -> 510R -> GND，分压比 510/2040510
--   V_RMS = 79931*V(mV)/Vref，U(V) = V_RMS/KU，KU = V_RMS_avg/227 = 3759154/227 = 16560
--   反推 Vref 实际约 1.206V（标称 1.218V）
-- 电流采样：1mR 分流器，I(mV) = IA_RMS*Vref/324004
--   I(A) = IA_RMS/KI，KI = IA_RMS_avg/(227/698) = 89578/0.3252 = 275447
--   反推分流器实际约 1.0255mR（含走线/焊接电阻）
-- 有功：A_WATT = 4046*I(mV)*V(mV)/Vref^2，P(W) = WATT/KPA，KPA = A_WATT_avg/(227*0.3252) = 52615/73.82 = 712.7
-- 电能：CF 周期 tCF = 1638.4*256/WATT，每脉冲 = 419430.4/712.7 约 588.5J = 0.0001635kWh
--   E(kWh) = CNT/6118
-- 注：电流建议用钳形表复核；电能需带载长测（>=10min）对比累计脉冲数进一步精调 KW。
local KU = 16560
local KI = 275447
local KPA = 712.7
local KPB = 712.7
local KW = 6118

-- 连续读取失败达到该次数后触发重新初始化
local MAX_FAIL = 3

-- 组装 setup 参数（按 MODE 自动选择 UART/SPI）
local function build_config_func()
    local cfg = {
        mode = MODE,
        ac_freq = 50,
        rms_update = 400,
        fast_rms_threshold = 0x7FFF,
        fast_rms_cycle = exs_bl0939.FAST_RMS_CYCLE_FULL,
        cf_func = exs_bl0939.CF_FUNC_ENERGY
    }
    if MODE == "uart" then
        cfg.uart_id = 1
        cfg.addr = UART_ADDR
    elseif MODE == "spi" then
        cfg.spi_id = SPI_ID
        cfg.cs = SPI_CS
        -- 若 SEL 由 GPIO 控制，可加 cfg.sel_pin = xxx；本方案 SEL 硬件拉高，不传
    else
        log.error("bl0939", "未知通信模式:", MODE)
        return nil
    end
    return cfg
end

-- 传感器初始化函数
local function init_func()
    local config = build_config_func()
    if not config then return false end
    local result = exs_bl0939.setup(config)
    if not result then
        log.error("bl0939", "init failed")
        return false
    end
    log.info("bl0939", "init success, version:", exs_bl0939.version())
    return true
end

-- 判断一次读取结果是否为芯片失联特征（全部电参量为 0）
-- 注：芯片掉电/复位后读回全 0，正常测量不可能出现 V 与 IA 同时精确为 0
local function is_link_lost(data)
    return data == nil or (data.v_rms == 0 and data.ia_rms == 0 and data.ib_rms == 0 and data.tps1 == 0)
end

-- 打印双路电能数据（data 已由调用方读取）
local function read_data_func(data)
    -- 原始值（与 STM32 例程字段对应，便于核对）
    log.info("bl0939", string.format("RAW V=%d IA=%d IB=%d PA=%d PB=%d W1=%d W2=%d TPS1=%d",
        data.v_rms, data.ia_rms, data.ib_rms, data.a_watt, data.b_watt,
        data.cfa_cnt, data.cfb_cnt, data.tps1))

    -- 换算值（实测校准系数）
    log.info("bl0939", string.format("电压=%.2fV 温度=%.1fC", data.v_rms / KU, data.temp))
    log.info("bl0939", string.format("A路 电流=%.3fA 有功=%.2fW 相角=%.1f 电能=%.4fkWh",
        data.ia_rms / KI, data.a_watt / KPA, data.a_angle, data.cfa_cnt / KW))
    log.info("bl0939", string.format("B路 电流=%.3fA 有功=%.2fW 相角=%.1f 电能=%.4fkWh",
        data.ib_rms / KI, data.b_watt / KPB, data.b_angle, data.cfb_cnt / KW))
end

-- 传感器读取任务协程（持续循环读取，断线自动重连）
local function sensor_task_func()
    sys.wait(100)
    local ok = init_func()
    if not ok then return end

    local fail_count = 0
    while true do
        local data = exs_bl0939.get_data()
        if is_link_lost(data) then
            fail_count = fail_count + 1
            if fail_count >= MAX_FAIL then
                log.error("bl0939", string.format("连续 %d 次读取异常，重新初始化 BL0939...", fail_count))
                exs_bl0939.close()
                fail_count = 0
                if init_func() then
                    log.info("bl0939", "BL0939 重新连接成功（若为重新上电，电能计数已从 0 开始）")
                else
                    log.error("bl0939", "重新初始化失败，1 秒后重试")
                end
            else
                log.warn("bl0939", string.format("读取异常（%d/%d），等待恢复...", fail_count, MAX_FAIL))
            end
        else
            fail_count = 0
            read_data_func(data)
        end
        sys.wait(1000)
    end
end
sys.taskInit(sensor_task_func)
