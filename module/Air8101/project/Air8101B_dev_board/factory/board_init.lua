--[[
@module  board_init
@summary 上电时序 + 基础引脚复用（产测 / 用户双模式共用）
@version 1.1
@date    2026.10.15
@usage
必须在协程内调用（内部使用 sys.wait）：
    sys.taskInit(function()
        require("board_init").power_on()
    end)
时序参数来自 _G.project_config.power_on，不要在代码里硬编码引脚号。
]]

local board_pins = require "board_pins"

local M = {}

local function out(pin, level)
    if pin then
        gpio.setup(pin, level, gpio.PULLUP)
    end
end

local function spi0_pinmux()
    -- 注意：核心库/rotable 用 type() 判断不可靠，改用"存在 + 方法存在"
    if not pins or not pins.setup then
        log.warn("board_init", "核心库 pins 不可用，跳过 SPI0 pinmux")
        return false
    end

    local sp = board_pins.spi0
    pins.setup(sp.pad_clk,  "SPI0_CLK")
    pins.setup(sp.pad_mosi, "SPI0_MOSI")
    pins.setup(sp.pad_miso, "SPI0_MISO")

    log.info("board_init", "SPI0 pinmux CLK pad", sp.pad_clk,
        "MOSI pad", sp.pad_mosi, "MISO pad", sp.pad_miso)
    return true
end

local function i2c1_pinmux()
    if not pins or not pins.setup then
        log.warn("board_init", "核心库 pins 不可用，跳过 I2C1 pinmux")
        return false
    end

    local ic = board_pins.i2c1
    local r1 = pins.setup(ic.pad_scl, "I2C1_SCL")
    local r2 = pins.setup(ic.pad_sda, "I2C1_SDA")

    log.info("board_init", "I2C1 pinmux pad", ic.pad_scl, ic.pad_sda,
        "返回值:", tostring(r1), tostring(r2))
    return (r1 ~= nil) and (r2 ~= nil)
end

local function uart1_pinmux()
    if not pins or not pins.setup then
        log.warn("board_init", "核心库 pins 不可用，跳过 UART1 pinmux")
        return false
    end

    local r1 = pins.setup(12, "UART1_TX")   -- pad12 = GPIO0 = U1TXD
    local r2 = pins.setup(11, "UART1_RX")   -- pad11 = GPIO1 = U1RXD
    log.info("board_init", "UART1 pinmux pad 12(U1TXD) pad 11(U1RXD) 返回值:", tostring(r1), tostring(r2))
    return (r1 ~= nil) and (r2 ~= nil)
end

function M.power_on()
    local cfg = _G.project_config or {}

    -- 1. 上电时序：屏幕供电 → 复位释放
    for _, step in ipairs(cfg.power_on or {}) do
        out(step.pin, step.level)
        log.info("board_init", "power", step.pin, step.level)
        if step.delay and step.delay > 0 then
            sys.wait(step.delay)
        end
    end

    -- 2. 总线引脚复用（SPI0 / I2C1 默认脚会撞上 LCD、UART1，必须先切）
    spi0_pinmux()
    i2c1_pinmux()

    -- 3. UART1 pinmux：显式把 pad 11/12 拿回来给 U1TXD / U1RXD
    --    （I2C1 默认就占这两个 pad，不显式声明时偶发被占，表现为"发指令没反应"）
    uart1_pinmux()

    -- 4. SPI0 两个设备的 CS 与两路 LDO 使能
    --    CH390H(CS0/GPIO34) 与 SPI NAND(CS1/GPIO49) 分时复用，
    --    两个 CS 与两路使能必须同时建立，否则总线电平混乱、通讯必失败
    out(board_pins.spi0.cs_lan, 1)
    out(board_pins.spi0.cs_nand, 1)
    out(board_pins.pwr.lan_en, 1)
    out(board_pins.pwr.nand_en, 1)

    log.info("board_init", "power_on done")
    return true
end

return M
