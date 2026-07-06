local M = {}

-- ============================================================
-- ST6201 4.3 寸 480x272 LCD 驱动（HWID_0 硬件 SPI 接口）
--
-- 说明：
--   Air1780H 的 lcd.HWID_0 模式由硬件 LCD 控制器管理 SPI 总线，
--   固定引脚为 PIN49~PIN53，无需在参数中指定 pin_dc/pin_rst。
--   lcd.init("custom", ...) 不会调用 params.init 回调，
--   因此本模块把 "控制器初始化" 和 "IC 命令序列" 分成两步：
--     1. M.init() 调用 lcd.init 配置硬件控制器；
--     2. 然后调用 init_sequence() 通过 lcd.cmd 发送 ST6201 寄存器序列；
--     3. 最后调用 lcd.user_done() 通知驱动初始化完成。
--
-- 初始化命令序列参考：main1_ok.lua（4 线 SPI 8bit 模式 I，480x272）
-- ============================================================
sys = require("sys")

local PIN_BL = 1

-- LCD初始化参数（使用专用接口，无需指定 pin_dc/pin_rst，由内部默认管理）
local lcd_param = {
    port = lcd.HWID_0,      -- 专用LCD接口
    w = 480,
    h = 272,
    pin_pwr = PIN_BL,       -- 背光引脚
    direction = 0,
    bus_speed = 10 * 1000 * 1000,
    interface_mode = lcd.WIRE_4_BIT_8_INTERFACE_I, -- 4线SPI 8bit
    rb_swap          = true,           -- 红/蓝通道交换
}

-- 自定义初始化序列（使用 lcd.cmd）
local function init_sequence()
    -- 注意：lcd.cmd 会自动管理DC引脚，无需手动拉高拉低
    lcd.cmd(0x11); sys.wait(120)
    lcd.cmd(0x3A, string.char(0x05)); sys.wait(10)
    lcd.cmd(0x36, string.char(0x00)); sys.wait(1)  -- BGR 顺序（配合 rb_swap）
    lcd.cmd(0x40, string.char(0x00))
    lcd.cmd(0x41, string.char(0x03))   -- 4线SPI模式
    lcd.cmd(0x20); sys.wait(120)
    lcd.cmd(0x21); sys.wait(120)

    -- 设置全屏地址窗口（列 0~479，行 0~271）
    lcd.cmd(0x2A, string.char(0x00, 0x00, 0x01, 0xDF))
    lcd.cmd(0x2B, string.char(0x00, 0x00, 0x01, 0x0F))

    lcd.cmd(0x29); sys.wait(20)
end

-- ============================================================
-- 对外接口
-- ============================================================

-- 单独导出命令序列，方便外部在特殊时序下调用
M.init_sequence = init_sequence

-- 完整初始化：硬件控制器 + IC 命令序列 + 背光
function M.init()
    log.info("ST6201", "初始化开始")
    -- 1. 初始化LCD
    local ok = lcd.init("custom", lcd_param)
    if not ok then
        log.error("ST6201", "lcd.init失败")
        while true do sys.wait(1000) end
    end

    -- 2. 执行自定义初始化（注意，lcd.init后，可以调用lcd.cmd）
    init_sequence()

    -- 3. 标记自定义初始化完成（必须）
    lcd.user_done()

    -- 4. 开启背光
    gpio.setup(PIN_BL, 1)


    return true
end

return M
