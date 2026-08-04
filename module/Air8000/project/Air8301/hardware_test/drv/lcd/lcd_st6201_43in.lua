--[[
@module  lcd_st6201_43in
@summary ST6201 4.3寸 480×272 SPI LCD 驱动（Air8301 硬件测试）
@version 2.0
@date    2026.08.04
@author  江访
@usage
require "lcd_st6201_43in" 即完成 LCD + AirUI 引擎 + 字体初始化（含 sys.wait，在任务中执行）。
初始化完成后发布 DISPLAY_READY 消息；背光在此注册（pwm.setup），收到 BACKLIGHT_ON 消息后开启。
]]

--[[
LCD 初始化协程（require 后自动启动，含多个 sys.wait 延时）：
1. 以 custom 模式初始化 ST6201 寄存器序列（含 Gamma 校正、180° 旋转）
2. lcd.user_done() 结束自定义初始化并清屏
3. 初始化 AirUI 渲染引擎 + 内置汉字字库
4. 注册背光 PWM0（仅 pwm.setup，不开启）
5. 发布 DISPLAY_READY 消息（TP 初始化、首页打开依赖此消息）

@local
@function lcd_init_task
]]
local function lcd_init_task()
    -- direction=0：框架不做旋转，旋转完全由自定义 MADCTL 序列（0x36=0xC0）控制
    local result = lcd.init("custom", {
        port            = lcd.HWID_0,
        w               = 480,
        h               = 272,
        pin_rst         = 36,
        direction       = 0,
        bus_speed       = 80 * 1000 * 1000,
        sleepcmd        = 0x10,
        wakecmd         = 0x11,
        interface_mode  = lcd.WIRE_4_BIT_8_INTERFACE_I,
        rb_swap         = true,
        endianness_swap = true,
    })
    log.info("lcd_st6201", "lcd.init result:", result)
    if not result then
        log.error("lcd_st6201", "lcd.init 失败")
        return
    end

    -- Sleep Out 退出休眠
    lcd.cmd(0x11); sys.wait(120)

    -- 关闭8色低彩闲置模式
    lcd.cmd(0x38); sys.wait(120) -- IDMOFF

    -- MADCTL: 180度旋转 RGB正常排列 0xC0
    lcd.cmd(0x36, string.char(0xC0)); sys.wait(1)

    lcd.cmd(0x20); sys.wait(120) -- INVOFF 关闭色彩反转
    lcd.cmd(0x21); sys.wait(120) -- INVON

    -- 正极性 Gamma P
    lcd.cmd(0x80, string.char(0x0C))
    lcd.cmd(0x81, string.char(0x1A))
    lcd.cmd(0x82, string.char(0x2E))
    lcd.cmd(0x83, string.char(0x42))
    lcd.cmd(0x84, string.char(0x56))
    lcd.cmd(0x85, string.char(0x6A))
    lcd.cmd(0x86, string.char(0x10))
    lcd.cmd(0x87, string.char(0x20))
    lcd.cmd(0x88, string.char(0x08))
    lcd.cmd(0x89, string.char(0x10))
    lcd.cmd(0x8A, string.char(0x18))
    lcd.cmd(0x8B, string.char(0x20))
    lcd.cmd(0x8C, string.char(0x2A))
    lcd.cmd(0x8D, string.char(0x34))
    lcd.cmd(0x8E, string.char(0x3E))
    lcd.cmd(0x8F, string.char(0x48))
    lcd.cmd(0x90, string.char(0x52))
    lcd.cmd(0x91, string.char(0x5C))
    lcd.cmd(0x92, string.char(0x66))

    -- 负极性 Gamma N
    lcd.cmd(0xA0, string.char(0x0C))
    lcd.cmd(0xA1, string.char(0x1A))
    lcd.cmd(0xA2, string.char(0x2E))
    lcd.cmd(0xA3, string.char(0x42))
    lcd.cmd(0xA4, string.char(0x56))
    lcd.cmd(0xA5, string.char(0x6A))
    lcd.cmd(0xA6, string.char(0x10))
    lcd.cmd(0xA7, string.char(0x20))
    lcd.cmd(0xA8, string.char(0x08))
    lcd.cmd(0xA9, string.char(0x10))
    lcd.cmd(0xAA, string.char(0x18))
    lcd.cmd(0xAB, string.char(0x20))
    lcd.cmd(0xAC, string.char(0x2A))
    lcd.cmd(0xAD, string.char(0x34))
    lcd.cmd(0xAE, string.char(0x3E))
    lcd.cmd(0xAF, string.char(0x48))
    lcd.cmd(0xB0, string.char(0x52))
    lcd.cmd(0xB1, string.char(0x5C))
    lcd.cmd(0xB2, string.char(0x66))

    -- 开启显示
    lcd.cmd(0x29); sys.wait(20) -- Display On
    -- 结束自定义初始化
    lcd.user_done()

    -- 清屏
    lcd.clear()

    -- 初始化 AirUI 渲染引擎 + 内置字库
    local w, h = lcd.getSize()
    if airui.init(w, h) then
        airui.font_load({
            type = "hzfont",
            size = 20,
            cache_size = 1024,
            antialias = 1,
        })
    else
        log.error("lcd_st6201", "airui.init 失败")
    end
    _G.screen_w = 480
    _G.screen_h = 272

    -- 背光开启回调：收到 BACKLIGHT_ON 消息后点亮 PWM0
    local function backlight_on_cb()
        pwm.start(0)
    end

    -- 注册背光（仅配置，不开启；收到 BACKLIGHT_ON 消息后点亮）
    pwm.setup(0, 1000, 100)
    sys.subscribe("BACKLIGHT_ON", backlight_on_cb)

    -- 通知其它模块：LCD/AirUI 已就绪（TP 初始化、首页打开依赖此消息）
    sys.publish("DISPLAY_READY")
    log.info("lcd_st6201", "初始化完成")
end

sys.taskInit(lcd_init_task)
