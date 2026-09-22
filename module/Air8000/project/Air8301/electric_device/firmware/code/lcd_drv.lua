--[[
@module  lcd_drv
@summary ST6201 4.3寸 480×272 SPI LCD 显示驱动模块（Air8301）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
本模块由 Air8000A 版本的 lcd_drv（ST7796）移植而来，替换为 Air8301 的 ST6201 4.3寸屏驱动。
参考：module/Air8000/project/Air8301/hardware_test/drv/lcd/lcd_st6201_43in.lua

功能：
1、LCD 硬件初始化（lcd.init("custom") + 厂商寄存器序列）；
2、AirUI 渲染引擎 + 中文字库初始化；
3、初始化完成后发布 "LCD_READY" 消息（供 ui_main 等待并继续触摸/背光初始化）；
4、提供 lcd_drv.backlight_on() 通过 PWM0 开启背光。

对外接口：
- lcd_drv.backlight_on()  开启背光（PWM0）
]]

local lcd_drv = {}

-- 厂商初始化寄存器表：{命令, 数据字节}
-- 以 0xFF=0xA5 开头的扩展命令区，结束后需以 0xFF=0x00 退出扩展命令模式
local init_regs = {
    {0xFF,0xA5},{0xE7,0x10},{0x35,0x00},{0x3A,0x01},
    {0x40,0x01},{0x41,0x01},{0x55,0x01},{0x44,0x15},
    {0x45,0x15},{0x7D,0x03},{0xC1,0xBB},{0xC2,0x13},
    {0xC3,0x10},{0xC6,0x3E},{0xC7,0x25},{0xC8,0x11},
    {0x7A,0x66},{0x6F,0x49},{0x78,0x57},{0x73,0x08},
    {0x74,0x13},{0xC9,0x00},{0x67,0x33},{0x51,0x4B},
    {0x52,0x7C},{0x53,0x45},{0x54,0x77},{0x46,0x0A},
    {0x47,0x2A},{0x48,0x0A},{0x49,0x1A},{0x56,0x43},
    {0x57,0x42},{0x58,0x3C},{0x59,0x64},{0x5A,0x41},
    {0x5B,0x3C},{0x5C,0x02},{0x5D,0x3C},{0x5E,0x1F},
    {0x60,0x80},{0x61,0x3F},{0x62,0x21},{0x63,0x07},
    {0x64,0xE0},{0x65,0x01},{0x6E,0x14},{0xCA,0x20},
    {0xCB,0x52},{0xCC,0x10},{0xCD,0x42},{0xD0,0x20},
    {0xD1,0x52},{0xD2,0x10},{0xD3,0x42},{0xD4,0x0A},
    {0xD5,0x32},{0xE5,0x06},{0xE6,0x00},{0xF8,0x06},
    {0xF9,0x00},

    {0x80,0x00},{0xA0,0x00},{0x81,0x05},{0xA1,0x03},
    {0x82,0x02},{0xA2,0x02},{0x86,0x2D},{0xA6,0x1A},
    {0x87,0x40},{0xA7,0x3F},{0x83,0x38},{0xA3,0x37},
    {0x84,0x37},{0xA4,0x36},{0x85,0x28},{0xA5,0x28},
    {0x88,0x09},{0xA8,0x05},{0x89,0x0F},{0xA9,0x0C},
    {0x8A,0x18},{0xAA,0x14},{0x8B,0x12},{0xAB,0x0E},
    {0x8C,0x15},{0xAC,0x15},{0x8D,0x11},{0xAD,0x15},
    {0x8E,0x12},{0xAE,0x11},{0x8F,0x19},{0xAF,0x0F},
    {0x90,0x0A},{0xB0,0x01},{0x91,0x11},{0xB1,0x0D},
    {0x92,0x19},{0xB2,0x12},
}

-- MADCTL(0x36) 值：方向 0/1/2/3 对应 0x00/0xA0/0xC0/0x60（与参考工程一致）
local madctl = {0x00, 0xA0, 0xC0, 0x60}

-- 显示参数（Air8301 硬件测试板：direction=0，面板已物理旋转180°安装，rb_swap=true）
local LCD_DIRECTION = 0
local LCD_W = 480
local LCD_H = 272
local LCD_PIN_RST = 36

-- 运行环境标识：PC = LuatOS-PC 模拟器（无 SPI 自定义屏 / 无 PWM 背光硬件）
local IS_PC = (rtos.bsp() == "PC")

--[[
写命令（带单字节参数）: data 为 nil 时只发命令

@local
@function command
@param cmd number 命令码
@param data number 单字节参数（可选）
@return nil
]]
local function command(cmd, data)
    if data == nil then
        lcd.cmd(cmd)
    else
        lcd.cmd(cmd, string.char(data))
    end
end

--[[
LCD 硬件初始化（不含 AirUI、不含背光）

@local
@function lcd_hw_init
@return boolean  true=成功
]]
local function lcd_hw_init()
    local direction = LCD_DIRECTION
    -- 方向 0/2 为横屏（480 宽），方向 1/3 为竖屏（272 宽）
    local width  = direction % 2 == 0 and LCD_W or LCD_H
    local height = direction % 2 == 0 and LCD_H or LCD_W

    -- ⚠️ PC 模拟器分支：模拟器不支持 "custom" 自定义屏（lcd.cmd / lcd.user_done 与厂商寄存器
    --    序列均为真机固件能力），改用模拟器支持的通用 LCD 初始化（复用源工程 Air8000A
    --    在 PC 上验证过的 ST7796 路径），仅创建渲染窗口供 AirUI 使用。
    if IS_PC then
        local pc_ok = lcd.init("st7796", {
            port      = lcd.HWID_0,
            pin_rst   = LCD_PIN_RST,
            direction = direction,
            w         = width,
            h         = height,
            xoffset   = 0,
            yoffset   = 0,
            bus_speed = 80 * 1000 * 1000,
        })
        if not pc_ok then
            log.error("lcd_drv", "PC 模拟器 lcd.init 失败")
            return false
        end
        lcd.clear(0xFFFF)
        log.info("lcd_drv", "LCD 初始化完成(PC 模拟器)", width, height, "direction", direction)
        return true
    end

    local lcd_config = {
        port           = lcd.HWID_0,
        pin_rst        = LCD_PIN_RST,
        direction      = direction,
        w              = width,
        h              = height,
        xoffset        = 0,
        yoffset        = 0,
        bus_speed      = 80 * 1000 * 1000,
        sleepcmd       = 0x10,
        wakecmd        = 0x11,
        interface_mode = lcd.WIRE_4_BIT_8_INTERFACE_I,
        rb_swap        = true,
    }

    local ok = lcd.init("custom", lcd_config)
    if not ok then
        log.error("lcd_drv", "lcd.init 失败")
        return false
    end

    -- 厂商初始化寄存器序列（0xFF=0xA5 解锁扩展命令 + GIP 时序 + 正负 Gamma）
    for _, item in ipairs(init_regs) do
        command(item[1], item[2])
    end

    -- MADCTL 旋转/镜像（direction=0 → 0x00 正常方向）
    command(0x36, madctl[direction + 1])

    -- 设置显示窗口（CASET/RASET），按实际分辨率计算
    local x_max = width - 1
    local y_max = height - 1
    lcd.cmd(0x2A, string.char(0x00, 0x00, math.floor(x_max / 256), x_max % 256))
    lcd.cmd(0x2B, string.char(0x00, 0x00, math.floor(y_max / 256), y_max % 256))

    -- 退出扩展命令模式
    command(0xFF, 0x00)

    -- Sleep Out 退出休眠
    command(0x11)
    sys.wait(120)

    -- 开启显示
    command(0x29)
    sys.wait(20)

    -- 结束自定义初始化
    lcd.user_done()

    -- 清屏
    lcd.clear(0xFFFF)

    log.info("lcd_drv", "LCD 硬件初始化完成", width, height, "direction", direction)
    return true
end

--[[
AirUI 引擎 + 字体初始化

@local
@function airui_init
@return boolean  true=成功
]]
local function airui_init()
    -- 获取 LCD 物理分辨率并初始化 AirUI 渲染引擎
    local w, h = lcd.getSize()
    local r = airui.init(w, h)
    if not r then
        log.error("lcd_drv", "airui.init 失败")
        return false
    end

    -- 字体加载：固件内置字库；字号与 Air8000A 版本 UI 保持一致（20 号字）
    airui.font_load({
        type       = "hzfont",
        size       = 20,
        cache_size = 1048,
        antialias  = 1,
    })

    -- 屏幕旋转（direction=0 已由硬件 MADCTL 处理，AirUI 不需额外旋转）
    airui.set_rotation(0)

    -- 记录逻辑分辨率
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        _G.screen_w, _G.screen_h = pw, ph
    else
        _G.screen_h, _G.screen_w = pw, ph
    end
    _G.is_landscape = (_G.screen_w > _G.screen_h)

    log.info("lcd_drv", "AirUI 初始化完成", _G.screen_w, _G.screen_h)
    return true
end

--[[
LCD 初始化协程（require 后自动启动）

@local
@function lcd_init_task
@return nil
]]
local function lcd_init_task()
    -- 确保 LCD 供电已使能（板级上电时序已设置，此处兜底）
    gpio.setup(28, 1)
    gpio.set(28, 1)
    sys.wait(100)

    -- 步骤1：LCD 硬件初始化
    if not lcd_hw_init() then
        -- 初始化失败也发布消息，避免 UI 任务无限等待
        sys.publish("LCD_READY", false)
        return
    end

    -- 步骤2：AirUI 引擎 + 字体初始化
    if not airui_init() then
        sys.publish("LCD_READY", false)
        return
    end

    -- 发布 LCD 初始化完成消息，供 UI 任务等待
    sys.publish("LCD_READY", true)
end

--[[
开启背光 PWM0（1kHz, 100% 占空比）

@api lcd_drv.backlight_on()
@return nil
]]
function lcd_drv.backlight_on()
    -- PC 模拟器：无 PWM 背光硬件，跳过（避免模拟器上 pwm 调用异常）
    if IS_PC then
        log.info("lcd_drv", "PC 模拟器环境：跳过背光 PWM 初始化")
        return
    end
    pwm.setup(0, 1000, 100)
    pwm.start(0)
    log.info("lcd_drv", "背光已开启 ch=0 freq=1000")
end

-- 以协程任务方式启动 LCD 初始化
sys.taskInit(lcd_init_task)

return lcd_drv
